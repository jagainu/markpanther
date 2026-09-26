import { describe, expect, test } from "bun:test";
import path from "node:path";

const previewPath = path.resolve(
  import.meta.dir,
  "../../App/Resources/preview/preview.js",
);
// eslint-disable-next-line @typescript-eslint/no-var-requires
const preview = require(previewPath);

describe("splitFrontmatter", () => {
  test("disabled: returns whole text as body unchanged", () => {
    const md = "---\ntitle: Hi\n---\n# Body";
    const result = preview.splitFrontmatter(md, false);
    expect(result.hasFrontmatter).toBe(false);
    expect(result.body).toBe(md);
    expect(result.lineOffset).toBe(0);
  });

  test("no frontmatter present", () => {
    const md = "# Hello\n\nBody text";
    const result = preview.splitFrontmatter(md, true);
    expect(result.hasFrontmatter).toBe(false);
    expect(result.body).toBe(md);
    expect(result.lineOffset).toBe(0);
  });

  test("parses a simple frontmatter block and computes line offset", () => {
    const md = "---\ntitle: Hi\ntags: [a, b]\n---\n# Body\n\nmore text";
    const result = preview.splitFrontmatter(md, true);
    expect(result.hasFrontmatter).toBe(true);
    expect(result.frontmatterRaw).toBe("title: Hi\ntags: [a, b]");
    expect(result.body).toBe("# Body\n\nmore text");
    // lines: 0:'---' 1:'title...' 2:'tags...' 3:'---' -> closingIndex=3 -> offset=4
    expect(result.lineOffset).toBe(4);
  });

  test("unterminated frontmatter block is treated as no frontmatter", () => {
    const md = "---\ntitle: Hi\n# Body";
    const result = preview.splitFrontmatter(md, true);
    expect(result.hasFrontmatter).toBe(false);
    expect(result.body).toBe(md);
  });

  test("first line must be exactly --- (not e.g. a horizontal rule with spaces)", () => {
    const md = "--- \ntitle: Hi\n---\nBody";
    // trimmed comparison should still treat trailing space as ---
    const result = preview.splitFrontmatter(md, true);
    expect(result.hasFrontmatter).toBe(true);
  });

  test("handles CRLF line endings for line counting", () => {
    const md = "---\r\ntitle: Hi\r\n---\r\nBody line";
    const result = preview.splitFrontmatter(md, true);
    expect(result.hasFrontmatter).toBe(true);
    expect(result.frontmatterRaw).toBe("title: Hi");
    expect(result.body).toBe("Body line");
    expect(result.lineOffset).toBe(3);
  });
});

describe("renderFrontmatterTable / formatFrontmatterValue", () => {
  test("renders scalar values as table rows", () => {
    const html = preview.renderFrontmatterTable({ title: "Hello", count: 3 });
    expect(html).toContain('data-line="0"');
    expect(html).toContain("<th>title</th><td>Hello</td>");
    expect(html).toContain("<th>count</th><td>3</td>");
  });

  test("renders nested values as JSON-ish strings", () => {
    const html = preview.renderFrontmatterTable({ tags: ["a", "b"] });
    expect(html).toContain("[&quot;a&quot;,&quot;b&quot;]");
  });

  test("escapes HTML in keys and values", () => {
    const html = preview.renderFrontmatterTable({
      "<x>": "<script>alert(1)</script>",
    });
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });
});

describe("renderFrontmatterBlock", () => {
  test("falls back to a <pre> block for invalid YAML", () => {
    const html = preview.renderFrontmatterBlock("title: [unterminated");
    expect(html).toContain('class="frontmatter-raw"');
    expect(html).toContain('data-line="0"');
  });
});
