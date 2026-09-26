#!/usr/bin/env bun
/**
 * vendor.ts — node_modules の prebuilt browser dist を
 * App/Resources/preview/vendor/<lib>/ へ必要ファイルだけコピーする。
 *
 * バンドラは使わない。各ライブラリの UMD/グローバル公開ビルドをそのまま置く。
 * markdown-it-texmath のように「単一ファイルでそのままブラウザで動く」ものは
 * 無加工でコピーする（require('katex') はブラウザでは呼ばれない分岐にある）。
 *
 * 実行: `bun run vendor`（package.json の scripts.vendor から）
 */

import { mkdir, readdir, rm, copyFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";

const WEB_ROOT = path.resolve(import.meta.dir, "..");
const NODE_MODULES = path.join(WEB_ROOT, "node_modules");
const VENDOR_ROOT = path.resolve(
  WEB_ROOT,
  "..",
  "App",
  "Resources",
  "preview",
  "vendor",
);

type CopySpec = {
  /** vendor/<dest 以下の相対パス> */
  dest: string;
  /** node_modules 以下の相対パス（絶対パスも可） */
  src: string;
};

const specs: CopySpec[] = [
  // markdown-it 本体（14.3.2 に固定 — 15.x 以降は UMD browser dist が廃止されたため）
  {
    dest: "markdown-it/markdown-it.min.js",
    src: "markdown-it/dist/markdown-it.min.js",
  },

  // markdown-it プラグイン群（すべて UMD dist あり）
  {
    dest: "markdown-it-footnote/markdown-it-footnote.min.js",
    src: "markdown-it-footnote/dist/markdown-it-footnote.min.js",
  },
  {
    dest: "markdown-it-task-lists/markdown-it-task-lists.min.js",
    src: "markdown-it-task-lists/dist/markdown-it-task-lists.min.js",
  },
  {
    dest: "markdown-it-sup/markdown-it-sup.min.js",
    src: "markdown-it-sup/dist/markdown-it-sup.min.js",
  },
  {
    dest: "markdown-it-mark/markdown-it-mark.min.js",
    src: "markdown-it-mark/dist/markdown-it-mark.min.js",
  },

  // markdown-it-texmath: browser 用の単体 dist は無いが、texmath.js 自体が
  // 「require はブラウザでは通らない分岐に隔離されている」単一ファイルなので無加工でコピー可能。
  {
    dest: "markdown-it-texmath/texmath.js",
    src: "markdown-it-texmath/texmath.js",
  },

  // KaTeX
  { dest: "katex/katex.min.js", src: "katex/dist/katex.min.js" },
  { dest: "katex/katex.min.css", src: "katex/dist/katex.min.css" },

  // js-yaml（4.1.0 に固定 — 5.x は UMD browser dist が廃止されたため）
  { dest: "js-yaml/js-yaml.min.js", src: "js-yaml/dist/js-yaml.min.js" },

  // DOMPurify
  { dest: "dompurify/purify.min.js", src: "dompurify/dist/purify.min.js" },

  // highlight.js（@highlightjs/cdn-assets は全言語同梱の単体ビルド）
  {
    dest: "highlightjs/highlight.min.js",
    src: "@highlightjs/cdn-assets/highlight.min.js",
  },
  {
    dest: "highlightjs/styles/github.min.css",
    src: "@highlightjs/cdn-assets/styles/github.min.css",
  },
  {
    dest: "highlightjs/styles/github-dark.min.css",
    src: "@highlightjs/cdn-assets/styles/github-dark.min.css",
  },

  // mermaid
  { dest: "mermaid/mermaid.min.js", src: "mermaid/dist/mermaid.min.js" },

  // idiomorph
  {
    dest: "idiomorph/idiomorph.min.js",
    src: "idiomorph/dist/idiomorph.min.js",
  },
];

async function copyOne(
  spec: CopySpec,
): Promise<{ dest: string; bytes: number }> {
  const srcPath = path.join(NODE_MODULES, spec.src);
  const destPath = path.join(VENDOR_ROOT, spec.dest);
  if (!existsSync(srcPath)) {
    throw new Error(`vendor source missing: ${srcPath} (for ${spec.dest})`);
  }
  await mkdir(path.dirname(destPath), { recursive: true });
  await copyFile(srcPath, destPath);
  const bytes = Bun.file(destPath).size;
  return { dest: spec.dest, bytes };
}

async function copyKatexFonts(): Promise<{ dest: string; bytes: number }[]> {
  const fontsSrcDir = path.join(NODE_MODULES, "katex/dist/fonts");
  const fontsDestDir = path.join(VENDOR_ROOT, "katex/fonts");
  await mkdir(fontsDestDir, { recursive: true });
  const entries = await readdir(fontsSrcDir);
  const woff2Files = entries.filter((f) => f.endsWith(".woff2"));
  const results: { dest: string; bytes: number }[] = [];
  for (const file of woff2Files) {
    const srcPath = path.join(fontsSrcDir, file);
    const destPath = path.join(fontsDestDir, file);
    await copyFile(srcPath, destPath);
    results.push({
      dest: `katex/fonts/${file}`,
      bytes: Bun.file(destPath).size,
    });
  }
  return results;
}

async function main() {
  console.log(`vendor root: ${VENDOR_ROOT}`);
  await rm(VENDOR_ROOT, { recursive: true, force: true });
  await mkdir(VENDOR_ROOT, { recursive: true });

  const results: { dest: string; bytes: number }[] = [];
  for (const spec of specs) {
    results.push(await copyOne(spec));
  }
  results.push(...(await copyKatexFonts()));

  results.sort((a, b) => a.dest.localeCompare(b.dest));
  let total = 0;
  for (const r of results) {
    total += r.bytes;
    console.log(`  ${r.dest}  (${(r.bytes / 1024).toFixed(1)} KiB)`);
  }
  console.log(
    `vendored ${results.length} files, ${(total / 1024 / 1024).toFixed(2)} MiB total`,
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
