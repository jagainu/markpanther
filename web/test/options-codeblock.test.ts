import { describe, expect, test } from "bun:test";
import path from "node:path";

const previewPath = path.resolve(
  import.meta.dir,
  "../../App/Resources/preview/preview.js",
);
// eslint-disable-next-line @typescript-eslint/no-var-requires
const preview = require(previewPath);

describe("normalizeOptions", () => {
  test("applies documented defaults when nothing is passed", () => {
    const opts = preview.normalizeOptions(undefined);
    expect(opts).toEqual({
      smartypants: false,
      superscript: false,
      highlightMark: true,
      hardLineBreaks: true,
      syntaxHighlighting: true,
      codeLineNumbers: false,
      math: true,
      frontmatter: true,
      tocToken: true,
      taskList: true,
      mermaid: true,
      markChanges: false,
      lineNumbers: false,
      changeBand: false,
    });
  });

  test("respects explicit overrides", () => {
    const opts = preview.normalizeOptions({
      smartypants: true,
      math: false,
      tocToken: false,
    });
    expect(opts.smartypants).toBe(true);
    expect(opts.math).toBe(false);
    expect(opts.tocToken).toBe(false);
    expect(opts.highlightMark).toBe(true);
  });
});

describe("wrapCodeLines", () => {
  test("wraps each line in a span, preserving line count", () => {
    const html = "line one\nline two\nline three";
    const out = preview.wrapCodeLines(html);
    const matches = out.match(/<span class="line">/g) || [];
    expect(matches.length).toBe(3);
    expect(out).toContain("line one</span>");
    expect(out).toContain("line three</span>");
  });

  test("keeps a span open across a line break (multi-line highlighted token)", () => {
    // simulate hljs wrapping a multi-line comment in one <span>
    const html = '<span class="hljs-comment">/*\nmulti\nline\n*/</span>';
    const out = preview.wrapCodeLines(html);
    // every line must be well-formed HTML: 4 lines -> 4 <span class="line">
    const lineSpans = out.match(/<span class="line">/g) || [];
    expect(lineSpans.length).toBe(4);
    // the inner hljs-comment span must be reopened on each continuation line
    const commentSpans = out.match(/<span class="hljs-comment">/g) || [];
    expect(commentSpans.length).toBe(4);
    // and closed the same number of times (once per line + reopen), tags balanced
    const closeSpans = out.match(/<\/span>/g) || [];
    // 4 line spans + 4 comment spans = 8 closing tags
    expect(closeSpans.length).toBe(8);
  });
});
