import { describe, expect, test } from "bun:test";
import path from "node:path";

const previewPath = path.resolve(
  import.meta.dir,
  "../../App/Resources/preview/preview.js",
);
// eslint-disable-next-line @typescript-eslint/no-var-requires
const preview = require(previewPath);

describe("slugify / createSlugger", () => {
  test("lowercases and hyphenates spaces", () => {
    expect(preview.slugify("Hello World")).toBe("hello-world");
  });

  test("keeps Japanese characters", () => {
    expect(preview.slugify("日本語 見出し")).toBe("日本語-見出し");
  });

  test("strips punctuation", () => {
    expect(preview.slugify("Foo, Bar! (Baz)")).toBe("foo-bar-baz");
  });

  test("dedupes with -1, -2 suffixes", () => {
    const slugger = preview.createSlugger();
    expect(slugger("Intro")).toBe("intro");
    expect(slugger("Intro")).toBe("intro-1");
    expect(slugger("Intro")).toBe("intro-2");
    expect(slugger("Other")).toBe("other");
  });
});

describe("buildTocHtml", () => {
  test("empty heading list produces an empty list", () => {
    expect(preview.buildTocHtml([])).toBe('<ul class="toc-list"></ul>');
  });

  test("flat list of same-level headings", () => {
    const html = preview.buildTocHtml([
      { level: 1, id: "a", text: "A" },
      { level: 1, id: "b", text: "B" },
    ]);
    expect(html).toBe(
      '<ul class="toc-list"><li><a href="#a">A</a></li><li><a href="#b">B</a></li></ul>',
    );
  });

  test("nests deeper headings under their parent", () => {
    const html = preview.buildTocHtml([
      { level: 1, id: "a", text: "A" },
      { level: 2, id: "b", text: "B" },
      { level: 2, id: "c", text: "C" },
      { level: 1, id: "d", text: "D" },
    ]);
    expect(html).toBe(
      '<ul class="toc-list"><li><a href="#a">A</a>' +
        '<ul class="toc-list"><li><a href="#b">B</a></li><li><a href="#c">C</a></li></ul>' +
        '</li><li><a href="#d">D</a></li></ul>',
    );
  });

  test("escapes text and href", () => {
    const html = preview.buildTocHtml([{ level: 1, id: 'a"b', text: "<x>" }]);
    expect(html).toContain("&lt;x&gt;");
    expect(html).toContain("a&quot;b");
    expect(html).not.toContain("<x>");
  });
});
