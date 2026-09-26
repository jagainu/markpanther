import { describe, expect, test } from "bun:test";
import path from "node:path";

const previewPath = path.resolve(
  import.meta.dir,
  "../../App/Resources/preview/preview.js",
);
// eslint-disable-next-line @typescript-eslint/no-var-requires
const preview = require(previewPath);

describe("normalizePath", () => {
  test("collapses . and .. segments in an absolute path", () => {
    expect(preview.normalizePath("/a/b/c/../img.png")).toBe("/a/b/img.png");
    expect(preview.normalizePath("/a/./b/img.png")).toBe("/a/b/img.png");
  });

  test("ignores .. that would escape the root", () => {
    expect(preview.normalizePath("/../a")).toBe("/a");
  });
});

describe("joinPath", () => {
  test("joins a relative path onto a base directory", () => {
    expect(preview.joinPath("/Users/m/docs", "images/pic.png")).toBe(
      "/Users/m/docs/images/pic.png",
    );
  });

  test("resolves ../ against the base directory", () => {
    expect(preview.joinPath("/a/b/c", "../img.png")).toBe("/a/b/img.png");
  });

  test("an absolute rel path ignores the base entirely", () => {
    expect(preview.joinPath("/a/b", "/etc/img.png")).toBe("/etc/img.png");
  });
});

describe("rewriteImageSrc", () => {
  test("returns unchanged when docDir is null", () => {
    const result = preview.rewriteImageSrc("images/pic.png", null);
    expect(result.original).toBeNull();
    expect(result.src).toBe("images/pic.png");
  });

  test("leaves http(s) URLs unchanged", () => {
    expect(
      preview.rewriteImageSrc("https://example.com/a.png", "/docs").original,
    ).toBeNull();
    expect(
      preview.rewriteImageSrc("http://example.com/a.png", "/docs").original,
    ).toBeNull();
  });

  test("leaves data: URIs unchanged", () => {
    expect(
      preview.rewriteImageSrc("data:image/png;base64,AAAA", "/docs").original,
    ).toBeNull();
  });

  test("rewrites a relative path against docDir", () => {
    const result = preview.rewriteImageSrc("images/pic.png", "/Users/m/docs");
    expect(result.original).toBe("images/pic.png");
    expect(result.src).toBe(
      "markp://file/" + encodeURI("/Users/m/docs/images/pic.png"),
    );
  });

  test("resolves ../ in the relative path", () => {
    const result = preview.rewriteImageSrc("../assets/pic.png", "/a/b/c");
    expect(result.src).toBe(
      "markp://file/" + encodeURI("/a/b/assets/pic.png"),
    );
  });

  test("percent-encodes spaces and Japanese characters", () => {
    const result = preview.rewriteImageSrc("my file 図.png", "/docs");
    expect(result.src).toBe(
      "markp://file/" + encodeURI("/docs/my file 図.png"),
    );
    expect(result.src).toContain("%20");
    expect(result.src).not.toContain(" ");
  });

  test("an absolute filesystem path is normalized but not joined to docDir", () => {
    const result = preview.rewriteImageSrc("/etc/img.png", "/Users/m/docs");
    expect(result.src).toBe("markp://file/" + encodeURI("/etc/img.png"));
  });
});

describe("rewriteImagesInHtml", () => {
  test("rewrites src and records data-original-src for markdown-rendered images", () => {
    const html = '<p><img src="pic.png" alt="x"></p>';
    const out = preview.rewriteImagesInHtml(html, "/docs");
    expect(out).toContain(
      'src="markp://file/' + encodeURI("/docs/pic.png") + '"',
    );
    expect(out).toContain('data-original-src="pic.png"');
  });

  test("also rewrites raw-HTML <img> tags", () => {
    const html = '<div><img src="../x/pic.png" /></div>';
    const out = preview.rewriteImagesInHtml(html, "/a/b");
    expect(out).toContain(
      'src="markp://file/' + encodeURI("/a/x/pic.png") + '"',
    );
    expect(out).toContain('data-original-src="../x/pic.png"');
    expect(out).toContain("/>");
  });

  test("leaves absolute URLs untouched and does not add data-original-src", () => {
    const html = '<img src="https://example.com/a.png">';
    const out = preview.rewriteImagesInHtml(html, "/docs");
    expect(out).toBe(html);
  });

  test("returns html unchanged when docDir is null", () => {
    const html = '<img src="pic.png">';
    expect(preview.rewriteImagesInHtml(html, null)).toBe(html);
  });
});
