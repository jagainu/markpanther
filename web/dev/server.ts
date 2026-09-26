#!/usr/bin/env bun
/**
 * dev/server.ts — 手元のブラウザで preview.js の動作を確認するための
 * 簡易静的サーバ。`bun run dev` から起動する。
 *
 * ルーティング:
 *   GET /                 -> dev/index.html（開発用ハーネス、CSP はゆるい）
 *   GET /sample.md         -> dev/sample.md
 *   GET /preview/*         -> App/Resources/preview/*（本番と同じファイル一式）
 */

import path from "node:path";

const WEB_ROOT = path.resolve(import.meta.dir, "..");
const DEV_ROOT = path.join(WEB_ROOT, "dev");
const PREVIEW_ROOT = path.resolve(
  WEB_ROOT,
  "..",
  "App",
  "Resources",
  "preview",
);

const PORT = Number(process.env.PORT || 4173);

function contentTypeFor(filePath: string): string | undefined {
  if (filePath.endsWith(".html")) return "text/html; charset=utf-8";
  if (filePath.endsWith(".js")) return "text/javascript; charset=utf-8";
  if (filePath.endsWith(".css")) return "text/css; charset=utf-8";
  if (filePath.endsWith(".md")) return "text/markdown; charset=utf-8";
  if (filePath.endsWith(".woff2")) return "font/woff2";
  if (filePath.endsWith(".json")) return "application/json; charset=utf-8";
  return undefined;
}

function serveFile(filePath: string): Response {
  const file = Bun.file(filePath);
  const type = contentTypeFor(filePath);
  return new Response(
    file,
    type ? { headers: { "content-type": type } } : undefined,
  );
}

async function handle(req: Request): Promise<Response> {
  const url = new URL(req.url);
  let pathname = decodeURIComponent(url.pathname);

  if (pathname === "/") {
    return serveFile(path.join(DEV_ROOT, "index.html"));
  }

  if (pathname === "/sample.md") {
    return serveFile(path.join(DEV_ROOT, "sample.md"));
  }

  if (pathname.startsWith("/preview/")) {
    const rel = pathname.slice("/preview/".length);
    const filePath = path.join(PREVIEW_ROOT, rel);
    // ディレクトリトラバーサル対策: 解決後のパスが PREVIEW_ROOT の外に出ていないか確認する
    if (
      !filePath.startsWith(PREVIEW_ROOT + path.sep) &&
      filePath !== PREVIEW_ROOT
    ) {
      return new Response("Forbidden", { status: 403 });
    }
    const file = Bun.file(filePath);
    if (!(await file.exists())) {
      return new Response("Not found: " + rel, { status: 404 });
    }
    return serveFile(filePath);
  }

  return new Response("Not found", { status: 404 });
}

const server = Bun.serve({
  port: PORT,
  fetch: handle,
});

console.log(`MarkPanther dev server: http://localhost:${server.port}/`);
console.log(`  preview files served from: ${PREVIEW_ROOT}`);
