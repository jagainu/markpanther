import { beforeEach, describe, expect, test } from "bun:test";
import { loadAllVendorScripts, loadPreviewJs, setupDom } from "./dom-setup";

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

describe("already percent-encoded image paths", () => {
  test("are not double-encoded", () => {
    const encoded = "assets/%E6%97%A5%E6%9C%AC%E8%AA%9E%20pic.png";
    const result = preview.rewriteImageSrc(encoded, "/docs");
    expect(result.src).toBe("markp://file/" + encodeURI("/docs/assets/日本語 pic.png"));
    expect(result.original).toBe(encoded);
  });

  test("a literal percent sign that is not an escape still works", () => {
    const result = preview.rewriteImageSrc("100%.png", "/docs");
    expect(result.src).toBe("markp://file/" + encodeURI("/docs/100%.png"));
  });

  test("raw and encoded spellings resolve to the same URL", () => {
    const raw = preview.rewriteImageSrc("a b/図.png", "/d").src;
    const enc = preview.rewriteImageSrc("a%20b/%E5%9B%B3.png", "/d").src;
    expect(enc).toBe(raw);
  });
});

describe("image refresh", () => {
  test("bumpImageVersion adds a cache-busting query to local images only", async () => {
    const md = "![a](pic.png) ![b](https://example.com/x.png)";
    await preview.render(md, "/docs", {});
    const before = document.querySelector("#content img")!.getAttribute("src")!;
    expect(before).toBe("markp://file//docs/pic.png");

    preview.bumpImageVersion();
    await preview.render(md, "/docs", {});
    const imgs = document.querySelectorAll("#content img");
    expect(imgs[0].getAttribute("src")).toBe("markp://file//docs/pic.png?v=1");
    expect(imgs[1].getAttribute("src")).toBe("https://example.com/x.png");
    // コピー/エクスポートには元のパスが出る
    expect(preview.getBodyHTML()).toContain('src="pic.png"');
    expect(preview.getBodyHTML()).not.toContain("?v=1");
  });
});

describe("broken images", () => {
  test("get a class and a readable title, and keep it across re-renders", async () => {
    const md = "![my alt](missing.png)\n";
    await preview.render(md, "/docs", {});
    const img = document.querySelector("#content img")!;
    img.dispatchEvent(new (globalThis as any).window.MouseEvent("error"));
    expect(img.classList.contains("markpanther-broken-image")).toBe(true);
    expect(img.getAttribute("title")).toContain("missing.png");

    await preview.render(md + "\nmore\n", "/docs", {});
    const again = document.querySelector("#content img")!;
    expect(again.classList.contains("markpanther-broken-image")).toBe(true);
    expect(preview.getBodyHTML()).not.toContain("markpanther-broken-image");
  });

  test("a later successful load clears the broken state", async () => {
    await preview.render("![x](late.png)\n", "/docs", {});
    const img = document.querySelector("#content img")!;
    img.dispatchEvent(new (globalThis as any).window.MouseEvent("error"));
    img.dispatchEvent(new (globalThis as any).window.MouseEvent("load"));
    expect(img.classList.contains("markpanther-broken-image")).toBe(false);
  });
});
