import { beforeEach, describe, expect, test } from "bun:test";
import { loadAllVendorScripts, loadPreviewJs, setupDom } from "./dom-setup";

// このファイル全体で1回だけ vendor を読み込み、preview.js は各テストで
// 読み直して previousUnitSignatures 等のモジュール内状態をリセットする
// （render() は「前回の render 結果」をモジュール変数で覚えているため、
// テスト間で汚染されないようにするには preview.js 自体を作り直す必要がある）。
let vendorLoaded = false;
let preview: any;

beforeEach(() => {
  setupDom();
  if (!vendorLoaded) {
    loadAllVendorScripts();
    vendorLoaded = true;
  }
  preview = loadPreviewJs();
});

function markedElements(): Element[] {
  return Array.from(document.querySelectorAll(".markpanther-changed"));
}

describe("markChanges: basic granularity", () => {
  test("changing one paragraph only marks that paragraph", async () => {
    await preview.render("Para A.\n\nPara B.", null, {});
    const result = await preview.render("Para A.\n\nPara B changed.", null, {
      markChanges: true,
    });
    expect(result.changed).toBe(1);
    const marked = markedElements();
    expect(marked.length).toBe(1);
    expect(marked[0].tagName).toBe("P");
    expect(marked[0].textContent).toContain("Para B changed.");
  });

  test("changing one list item only marks that li, not the whole list", async () => {
    const before = "- item one\n- item two\n- item three";
    const after = "- item one\n- item two changed\n- item three";
    await preview.render(before, null, {});
    const result = await preview.render(after, null, { markChanges: true });
    expect(result.changed).toBe(1);
    const marked = markedElements();
    expect(marked.length).toBe(1);
    expect(marked[0].tagName).toBe("LI");
    expect(marked[0].textContent).toContain("item two changed");
  });

  test("changing one table row only marks that tr", async () => {
    const before = "| a | b |\n| - | - |\n| 1 | 2 |\n| 3 | 4 |";
    const after = "| a | b |\n| - | - |\n| 1 | 2 |\n| 3 | 40 |";
    await preview.render(before, null, {});
    const result = await preview.render(after, null, { markChanges: true });
    expect(result.changed).toBe(1);
    const marked = markedElements();
    expect(marked.length).toBe(1);
    expect(marked[0].tagName).toBe("TR");
    expect(marked[0].textContent).toContain("40");
  });

  test("a block whose content is unchanged but whose data-line shifted (line inserted above) is not marked", async () => {
    await preview.render("Para A.\n\nPara B.", null, {});
    const result = await preview.render(
      "Para NEW.\n\nPara A.\n\nPara B.",
      null,
      { markChanges: true },
    );
    expect(result.changed).toBe(1);
    const marked = markedElements();
    expect(marked.length).toBe(1);
    expect(marked[0].textContent).toContain("Para NEW.");
  });

  // 以前は削除だけの更新を何も示さずに通していた。いちばん気づきたい変化なので、
  // 残った本文は動かさないまま、消えた場所に印を置いて数にも入れる。
  test("a pure deletion leaves a marker where the block was", async () => {
    await preview.render("Para A.\n\nPara B.\n\nPara C.", null, {});
    const result = await preview.render("Para A.\n\nPara C.", null, {
      markChanges: true,
    });
    expect(result.changed).toBe(1);
    // 残っているブロックは変わっていないので、ブロックの印は付かない
    expect(markedElements().length).toBe(0);

    const gaps = document.querySelectorAll(".markpanther-removed-block");
    expect(gaps.length).toBe(1);
    expect(gaps[0].getAttribute("data-removed")).toBe("Para B.");
  });
});

describe("markChanges: no-op cases", () => {
  test("the very first render is never marked, even with markChanges:true", async () => {
    const result = await preview.render("# Hello", null, {
      markChanges: true,
    });
    expect(result.changed).toBe(0);
    expect(markedElements().length).toBe(0);
  });

  test("markChanges:false always returns 0, even when content differs", async () => {
    await preview.render("Para A.", null, {});
    const result = await preview.render("Para A changed.", null, {
      markChanges: false,
    });
    expect(result.changed).toBe(0);
    expect(markedElements().length).toBe(0);
  });

  test("re-rendering identical content returns 0", async () => {
    const md = "# Title\n\nSame paragraph.";
    await preview.render(md, null, {});
    const result = await preview.render(md, null, { markChanges: true });
    expect(result.changed).toBe(0);
    expect(markedElements().length).toBe(0);
  });
});

describe("markChanges: does not false-positive on async DOM rewrites", () => {
  test("an unchanged highlighted code block is not marked when an unrelated paragraph changes", async () => {
    const codeBlock = "```js\nconst x = 1;\nfunction f() { return x; }\n```";
    const before = "Intro.\n\n" + codeBlock;
    const after = "Intro changed.\n\n" + codeBlock;
    await preview.render(before, null, {});
    const result = await preview.render(after, null, { markChanges: true });
    expect(result.changed).toBe(1);
    const marked = markedElements();
    expect(marked.length).toBe(1);
    expect(marked[0].textContent).toContain("Intro changed.");
    expect(document.querySelector(".code-block.markpanther-changed")).toBeNull();
  });

  test("an unchanged mermaid diagram is not marked after it resolves from pending to SVG between renders", async () => {
    const mermaidSource = "graph TD\n  A --> B";
    const md1 = "Intro.\n\n```mermaid\n" + mermaidSource + "\n```";
    const md2 = "Intro changed.\n\n```mermaid\n" + mermaidSource + "\n```";

    (globalThis as any).mermaid = {
      initialize: () => {},
      render: async () => ({ svg: '<svg data-real="1"></svg>' }),
    };
    try {
      // 1回目: markChanges なし。この時点では mermaid はまだ pending
      // プレースホルダとして描画され、その後非同期に SVG へ解決される。
      await preview.render(md1, null, {});
      const diagramAfterFirst = document.querySelector(".mermaid-diagram")!;
      expect(diagramAfterFirst.getAttribute("data-mermaid-pending")).toBeNull();
      expect(diagramAfterFirst.innerHTML).toContain('data-real="1"');

      // 2回目: 同じ mermaid ソースのまま、無関係な段落だけ変更する。
      const result = await preview.render(md2, null, { markChanges: true });
      expect(result.changed).toBe(1);
      const marked = markedElements();
      expect(marked.length).toBe(1);
      expect(marked[0].textContent).toContain("Intro changed.");
      expect(
        document.querySelector(".mermaid-diagram.markpanther-changed"),
      ).toBeNull();
    } finally {
      delete (globalThis as any).mermaid;
    }
  });
});

describe("markChanges: excluded from copy/export output", () => {
  test("getBodyHTML does not include markpanther-changed", async () => {
    await preview.render("Para A.", null, {});
    await preview.render("Para A changed.", null, { markChanges: true });
    expect(markedElements().length).toBe(1); // sanity: it really is marked live

    const html = preview.getBodyHTML();
    expect(html).not.toContain("markpanther-changed");
    expect(html).not.toContain("data-markpanther-changed-pending");
  });

  test("exportHTML does not include markpanther-changed", async () => {
    await preview.render("Para A.", null, {});
    await preview.render("Para A changed.", null, { markChanges: true });

    const exported = await preview.exportHTML({});
    expect(exported).not.toContain("markpanther-changed");
    expect(exported).not.toContain("data-markpanther-changed-pending");
  });
});

describe("persistent change markers", () => {
  test("after the flash, a changed block settles into a quieter marker that stays", async () => {
    const previewJs = loadPreviewJs();
    await previewJs.render("# T\n\none\n\ntwo\n", null, {});
    await previewJs.render("# T\n\none\n\ntwo changed\n", null, { markChanges: true });
    const el = document.querySelector("#content .markpanther-changed")!;
    expect(el).toBeTruthy();

    previewJs.demoteChangeHighlight(el);
    expect(el.classList.contains("markpanther-changed")).toBe(false);
    expect(el.classList.contains("markpanther-changed-recent")).toBe(true);
    // コピー/エクスポートには出さない
    expect(previewJs.getBodyHTML()).not.toContain("markpanther-changed");
  });

  test("markers survive re-renders that are not external updates (mode switch, settings)", async () => {
    const previewJs = loadPreviewJs();
    await previewJs.render("one\n\ntwo\n\nthree\n", null, {});
    await previewJs.render("one\n\ntwo!\n\nthree\n", null, { markChanges: true });
    await previewJs.render("one\n\ntwo!\n\nthree\n", null, { markChanges: false, codeLineNumbers: true });

    const kept = document.querySelectorAll("#content .markpanther-changed-recent");
    expect(kept.length).toBe(1);
    expect(kept[0].textContent).toBe("two!");
    // 再描画では光らせ直さない
    expect(document.querySelectorAll("#content .markpanther-changed").length).toBe(0);
  });

  // Claude Code は同じファイルを何度も書き換える。毎回置き換えると何がいつ変わったか
  // 追えないので、リセットするまで積み上げる
  test("the next external update keeps the earlier markers and adds to them", async () => {
    const previewJs = loadPreviewJs();
    await previewJs.render("one\n\ntwo\n\nthree\n", null, {});
    await previewJs.render("one\n\ntwo!\n\nthree\n", null, { markChanges: true });
    previewJs.demoteChangeHighlight(document.querySelector("#content .markpanther-changed")!);
    await previewJs.render("one\n\ntwo!\n\nthree!\n", null, { markChanges: true });

    const marked = document.querySelectorAll(
      "#content .markpanther-changed, #content .markpanther-changed-recent",
    );
    expect(Array.from(marked).map((el) => el.textContent)).toEqual(["two!", "three!"]);
  });

  test("a later deletion keeps the earlier block marker and adds a gap", async () => {
    const previewJs = loadPreviewJs();
    await previewJs.render("one\n\ntwo\n\nthree\n", null, {});
    await previewJs.render("one\n\ntwo!\n\nthree\n", null, { markChanges: true });
    await previewJs.render("one\n\ntwo!\n", null, { markChanges: true });

    const marked = document.querySelectorAll(
      "#content .markpanther-changed, #content .markpanther-changed-recent",
    );
    expect(Array.from(marked).map((el) => el.textContent)).toEqual(["two!"]);
    expect(document.querySelectorAll(".markpanther-removed-block").length).toBe(1);
  });

  test("scrollToFirstChange reports whether there is a marked block", async () => {
    const previewJs = loadPreviewJs();
    await previewJs.render("one\n\ntwo\n", null, {});
    expect(previewJs.scrollToFirstChange()).toBe(false);
    await previewJs.render("one\n\ntwo!\n", null, { markChanges: true });
    expect(previewJs.scrollToFirstChange()).toBe(true);
  });
});
