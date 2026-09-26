import { Window } from "happy-dom";
import { readFileSync } from "node:fs";
import path from "node:path";

const PREVIEW_DIR = path.resolve(
  import.meta.dir,
  "../../App/Resources/preview",
);

let happyWindow: InstanceType<typeof Window> | null = null;

/**
 * happy-dom の Window インスタンスのプロパティを globalThis へコピーし、
 * globalThis.window = globalThis というエイリアスを張ることで、
 * UMD スクリプト（`typeof window !== 'undefined' ? window : self` 式の分岐や
 * 素の `var X = ...` トップレベル宣言）が実ブラウザの <script> 読み込みと
 * 同じようにグローバルへ現れるようにする（happy-dom v20 に
 * GlobalRegistrator が無いための手動版）。
 */
export function setupDom(): void {
  if (!happyWindow) {
    happyWindow = new Window({ url: "https://markpanther.invalid/" });
    const anyWindow = happyWindow as unknown as Record<string, unknown>;
    const anyGlobal = globalThis as unknown as Record<string, unknown>;
    for (const key of Object.getOwnPropertyNames(anyWindow)) {
      if (
        key === "window" ||
        key === "self" ||
        key === "globalThis" ||
        key === "top" ||
        key === "parent"
      )
        continue;
      // ECMAScript 組み込み（String/Object/Array/Promise/...）や Bun が既に
      // 提供しているグローバル（fetch/btoa 等）は上書きしない。ループの
      // 途中で Object/Function 自体を差し替えてしまうと、この後の
      // Object.defineProperty 呼び出し自体が壊れる事故になるため。
      if (key in anyGlobal) continue;
      try {
        Object.defineProperty(globalThis, key, {
          value: anyWindow[key],
          writable: true,
          configurable: true,
          enumerable: true,
        });
      } catch (e) {
        // 一部のプロパティ（既存の読み取り専用グローバル等）は再定義できないため無視する
      }
    }
    (globalThis as unknown as Record<string, unknown>).window = globalThis;
    (globalThis as unknown as Record<string, unknown>).self = globalThis;
    patchNodeNameForDOMPurify();
  }
  document.documentElement.innerHTML =
    '<head><link id="markpanther-style-link" rel="stylesheet" href="styles/GitHub.css"></head>' +
    '<body><article id="content" class="markdown-body"></article></body>';
}

/**
 * happy-dom v20 は `nodeName` の getter を Node.prototype だけでなく
 * Element.prototype / Text.prototype など各サブクラスにも個別実装として
 * 持っている（本来 DOM 仕様では Node.prototype 側の単一実装が nodeType に
 * 応じて多態的に振る舞うべきところ）。通常のプロパティアクセス
 * （`el.nodeName`）はプロトタイプチェーン上近いサブクラス側の実装が優先され
 * 正しく動くが、DOMPurify 3.4.x は「realm-safe」な取得のため
 * `Node.prototype` から getter を一度だけ切り出して `.call(element)` で
 * 使い回す実装になっており、そちらは空文字を返すダミー実装を掴んでしまい、
 * すべてのノードが `tagName === ""` としてまるごと除去される事故になる
 * （happy-dom 側の非互換であり、実ブラウザ / WKWebView では発生しない。
 * 実機検証でも DOMPurify 経由の他の要素は正しく描画されることを確認済み）。
 * テスト環境だけの回避策として、Node.prototype 側の nodeName getter を
 * 「実際のインスタンスのプロトタイプチェーンを辿って、サブクラス固有の
 * 実装があればそちらに委譲する」ものに差し替える。
 */
function patchNodeNameForDOMPurify(): void {
  const g = globalThis as unknown as { Node?: any };
  if (!g.Node) return;
  const nodeProto = g.Node.prototype;
  const nodeDesc = Object.getOwnPropertyDescriptor(nodeProto, "nodeName");
  if (!nodeDesc || !nodeDesc.get) return;
  const fallbackGetter = nodeDesc.get;

  function delegatingNodeNameGetter(this: unknown): unknown {
    let proto: unknown = Object.getPrototypeOf(this);
    while (proto && proto !== nodeProto) {
      const desc = Object.getOwnPropertyDescriptor(proto, "nodeName");
      if (desc && desc.get && desc.get !== delegatingNodeNameGetter) {
        return desc.get.call(this);
      }
      proto = Object.getPrototypeOf(proto);
    }
    return fallbackGetter.call(this);
  }

  Object.defineProperty(nodeProto, "nodeName", {
    configurable: true,
    enumerable: nodeDesc.enumerable,
    get: delegatingNodeNameGetter,
  });
}

/**
 * vendor/ 以下の UMD スクリプトを、実際の <script> タグ読み込みと同じ形で
 * 現在のグローバルスコープへ反映する（間接 eval によりトップレベル var/function
 * 宣言が globalThis に付く）。
 */
export function loadVendorScript(relPath: string): void {
  const code = readFileSync(path.join(PREVIEW_DIR, "vendor", relPath), "utf8");
  const indirectEval = eval;
  indirectEval(code);
}

export function loadAllVendorScripts(): void {
  loadVendorScript("markdown-it/markdown-it.min.js");
  loadVendorScript("markdown-it-footnote/markdown-it-footnote.min.js");
  loadVendorScript("markdown-it-task-lists/markdown-it-task-lists.min.js");
  loadVendorScript("markdown-it-sup/markdown-it-sup.min.js");
  loadVendorScript("markdown-it-mark/markdown-it-mark.min.js");
  loadVendorScript("markdown-it-texmath/texmath.js");
  loadVendorScript("katex/katex.min.js");
  loadVendorScript("js-yaml/js-yaml.min.js");
  loadVendorScript("dompurify/purify.min.js");
  loadVendorScript("highlightjs/highlight.min.js");
  loadVendorScript("idiomorph/idiomorph.min.js");
}

/** preview.js をモジュールキャッシュを無視して読み直し、公開 API を返す。 */
export function loadPreviewJs(): any {
  const previewPath = path.join(PREVIEW_DIR, "preview.js");
  const resolved = require.resolve(previewPath);
  delete require.cache[resolved];
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  return require(previewPath);
}

export { PREVIEW_DIR };
