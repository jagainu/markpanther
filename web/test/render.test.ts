import {
  afterEach,
  beforeAll,
  beforeEach,
  describe,
  expect,
  test,
} from "bun:test";
import { loadAllVendorScripts, loadPreviewJs, setupDom } from "./dom-setup";

let preview: any;

beforeAll(() => {
  setupDom();
  loadAllVendorScripts();
  preview = loadPreviewJs();
});

describe("buildHtmlFromMarkdown (pure HTML string output, uses real markdown-it)", () => {
  test("renders GFM tables and strikethrough without extra plugins", () => {
    const md = "| a | b |\n| - | - |\n| 1 | 2 |\n\n~~gone~~";
    const opts = preview.normalizeOptions({});
    const html = preview.buildHtmlFromMarkdown(md, opts, null);
    expect(html).toContain("<table");
    expect(html).toContain("<s>gone</s>");
  });

  test("assigns data-line to block-level tokens", () => {
    const md = "# Title\n\nParagraph one.\n\nParagraph two.";
    const opts = preview.normalizeOptions({});
    const html = preview.buildHtmlFromMarkdown(md, opts, null);
    expect(html).toContain('data-line="0"');
    expect(html).toContain('data-line="2"');
    expect(html).toContain('data-line="4"');
  });

  test("shifts data-line by the frontmatter line count", () => {
    const md = "---\ntitle: Hi\n---\n# Title\n\nBody";
    const opts = preview.normalizeOptions({});
    const html = preview.buildHtmlFromMarkdown(md, opts, null);
    // frontmatter table itself is at line 0, heading follows at source line 3
    expect(html).toContain('class="frontmatter-table" data-line="0"');
    expect(html).toContain('data-line="3"');
  });

  test("options.frontmatter=false disables frontmatter parsing entirely", () => {
    const md = "---\ntitle: Hi\n---\n# Title";
    const opts = preview.normalizeOptions({ frontmatter: false });
    const html = preview.buildHtmlFromMarkdown(md, opts, null);
    expect(html).not.toContain("frontmatter-table");
    expect(html).toContain("<hr");
  });

  test("task list checkboxes are rendered disabled", () => {
    const md = "- [ ] todo\n- [x] done";
    const opts = preview.normalizeOptions({});
    const html = preview.buildHtmlFromMarkdown(md, opts, null);
    expect(html).toContain('type="checkbox"');
    expect(html).toContain("disabled");
  });

  test("options.taskList=false leaves literal [ ] text", () => {
    const md = "- [ ] todo";
    const opts = preview.normalizeOptions({ taskList: false });
    const html = preview.buildHtmlFromMarkdown(md, opts, null);
    expect(html).not.toContain('type="checkbox"');
  });

  test("superscript plugin is gated by options.superscript", () => {
    const md = "x^2^";
    const off = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({}),
      null,
    );
    expect(off).not.toContain("<sup>");
    const on = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({ superscript: true }),
      null,
    );
    expect(on).toContain("<sup>2</sup>");
  });

  test("mark plugin is gated by options.highlightMark", () => {
    const md = "==hi==";
    const on = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({}),
      null,
    );
    expect(on).toContain("<mark>hi</mark>");
    const off = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({ highlightMark: false }),
      null,
    );
    expect(off).not.toContain("<mark>");
  });

  test("math renders inline and block KaTeX output via katex.renderToString", () => {
    const md = "Inline $x^2$ math.\n\n$$\\int_0^1 x\\,dx$$";
    const html = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({}),
      null,
    );
    expect(html).toContain("katex");
  });

  test("options.math=false leaves dollar signs untouched", () => {
    const md = "Inline $x^2$ math.";
    const html = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({ math: false }),
      null,
    );
    expect(html).not.toContain("katex");
  });

  test("footnotes render a footnotes section", () => {
    const md = "Text with a note.[^1]\n\n[^1]: The note.";
    const html = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({}),
      null,
    );
    expect(html).toContain("footnote");
  });

  test("[TOC] token expands to a nested link list with heading ids", () => {
    const md = "[TOC]\n\n# First\n\n## Second\n\n# Third";
    const html = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({}),
      null,
    );
    expect(html).toContain('class="toc"');
    expect(html).toContain('id="first"');
    expect(html).toContain('id="second"');
    expect(html).toContain('href="#first"');
  });

  test("options.tocToken=false leaves [TOC] as literal text", () => {
    const md = "[TOC]\n\n# First";
    const html = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({ tocToken: false }),
      null,
    );
    expect(html).not.toContain('class="toc"');
    expect(html).toContain("[TOC]");
  });

  test("smartypants converts straight quotes when enabled", () => {
    const md = '"quoted" text';
    const on = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({ smartypants: true }),
      null,
    );
    expect(on).toContain("“quoted”");
    const off = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({}),
      null,
    );
    expect(off).toContain("&quot;quoted&quot;");
  });

  test("hardLineBreaks turns single newlines into <br>", () => {
    const md = "line one\nline two";
    const on = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({ hardLineBreaks: true }),
      null,
    );
    expect(on).toContain("<br");
    const off = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({ hardLineBreaks: false }),
      null,
    );
    expect(off).not.toContain("<br");
    // 既定はオン（打ったとおりに改行を表示する）
    const byDefault = preview.buildHtmlFromMarkdown(md, preview.normalizeOptions({}), null);
    expect(byDefault).toContain("<br");
  });

  test("syntax highlighting wraps known languages with hljs spans", () => {
    const md = "```js\nconst x = 1;\n```";
    const on = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({}),
      null,
    );
    expect(on).toContain("hljs-keyword");
    const off = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({ syntaxHighlighting: false }),
      null,
    );
    expect(off).not.toContain("hljs-keyword");
  });

  test("code blocks with no language are not auto-detected", () => {
    const md = "```\nconst x = 1;\n```";
    const html = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({}),
      null,
    );
    expect(html).not.toContain("hljs-keyword");
    expect(html).toContain("const x = 1;");
  });

  test("codeLineNumbers wraps highlighted code lines", () => {
    const md = "```js\nconst a = 1;\nconst b = 2;\n```";
    const html = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({ codeLineNumbers: true }),
      null,
    );
    expect(html).toContain('class="line"');
    expect(html).toContain("line-numbers");
  });

  test("mermaid fences become a pending diagram placeholder", () => {
    const md = "```mermaid\ngraph TD; A-->B;\n```";
    const html = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({}),
      null,
    );
    expect(html).toContain("mermaid-diagram");
    expect(html).toContain('data-mermaid-pending="true"');
  });

  test("options.mermaid=false treats mermaid fences as plain code", () => {
    const md = "```mermaid\ngraph TD; A-->B;\n```";
    const html = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({ mermaid: false }),
      null,
    );
    expect(html).not.toContain("mermaid-diagram");
    expect(html).toContain("code-block");
  });

  test("rewrites relative image paths and preserves the original", () => {
    const md = "![alt](pic.png)";
    const html = preview.buildHtmlFromMarkdown(
      md,
      preview.normalizeOptions({}),
      "/docs",
    );
    expect(html).toContain("markp://file/");
    expect(html).toContain('data-original-src="pic.png"');
  });
});

describe("sanitizeHtml", () => {
  test("removes <script> tags", () => {
    const clean = preview.sanitizeHtml("<p>hi</p><script>alert(1)</script>");
    expect(clean).not.toContain("<script>");
    expect(clean).toContain("<p>hi</p>");
  });

  test("removes inline event handler attributes like onerror", () => {
    const clean = preview.sanitizeHtml('<img src="x.png" onerror="alert(1)">');
    expect(clean).not.toContain("onerror");
  });

  test("allows markp: scheme image sources", () => {
    const clean = preview.sanitizeHtml(
      '<img src="markp://file/docs/pic.png">',
    );
    expect(clean).toContain("markp://file/docs/pic.png");
  });

  test("blocks javascript: URLs", () => {
    const clean = preview.sanitizeHtml('<a href="javascript:alert(1)">x</a>');
    expect(clean).not.toContain("javascript:");
  });

  test("preserves data-line attributes", () => {
    const clean = preview.sanitizeHtml('<p data-line="3">hi</p>');
    expect(clean).toContain('data-line="3"');
  });
});

describe("render() end-to-end via #content + Idiomorph", () => {
  test("renders into #content", async () => {
    await preview.render("# Hello", null, {});
    const content = document.getElementById("content")!;
    expect(content.innerHTML).toContain("Hello");
    expect(content.querySelector("h1")).not.toBeNull();
  });

  test("a later render() call wins over a slower earlier one (no stale overwrite)", async () => {
    const first = preview.render("# First", null, {});
    const second = preview.render("# Second", null, {});
    await Promise.all([first, second]);
    const content = document.getElementById("content")!;
    expect(content.textContent).toContain("Second");
    expect(content.textContent).not.toContain("First");
  });

  test("getBodyHTML restores original relative image src", async () => {
    await preview.render("![alt](pic.png)", "/docs", {});
    const html = preview.getBodyHTML();
    expect(html).toContain('src="pic.png"');
    expect(html).not.toContain("markp://file/");
  });

  test("setStyle switches the stylesheet link for built-in styles", () => {
    preview.setStyle("Clearness");
    const link = document.getElementById("markpanther-style-link")!;
    expect(link.getAttribute("href")).toBe("styles/Clearness.css");
    preview.setStyle("GitHub");
    expect(link.getAttribute("href")).toBe("styles/GitHub.css");
  });

  test("setStyle uses the markp://style/ scheme for user styles", () => {
    preview.setStyle("MyCustomTheme");
    const link = document.getElementById("markpanther-style-link")!;
    expect(link.getAttribute("href")).toBe("markp://style/MyCustomTheme.css");
    preview.setStyle("GitHub");
  });

  test("getTopLine returns 0 when there is no content", async () => {
    await preview.render("", null, {});
    expect(preview.getTopLine()).toBe(0);
  });
});

describe("mermaid pipeline (mermaid itself mocked)", () => {
  // 各テストで preview.js を読み直し、mermaidCache / mermaidScriptPromise を
  // まっさらにする（loadMermaidScript は一度解決したら使い回すため、テスト間で
  // モックの mermaid を挿げ替えられるようにするにはモジュール自体を作り直す必要がある）。
  let localPreview: any;

  beforeEach(() => {
    localPreview = loadPreviewJs();
  });

  afterEach(() => {
    delete (globalThis as any).mermaid;
  });

  test("passes the exact fence source — including -->, |, multiple lines — to mermaid.render", async () => {
    const fenceBody =
      "graph LR\n  Claude -->|Write| File --> FSEvents --> MarkPanther";
    const md = "```mermaid\n" + fenceBody + "\n```";
    const calls: string[] = [];
    (globalThis as any).mermaid = {
      initialize: () => {},
      render: async (_id: string, source: string) => {
        calls.push(source);
        return { svg: '<svg data-mock="1"></svg>' };
      },
    };

    await localPreview.render(md, null, {});

    expect(calls).toEqual([fenceBody]);
    const diagram = document.querySelector(".mermaid-diagram")!;
    expect(diagram.getAttribute("data-mermaid-pending")).toBeNull();
    expect(diagram.innerHTML).toContain('data-mock="1"');
  });

  test("reuses the cached SVG for an unchanged mermaid source without calling mermaid.render again", async () => {
    const fenceBody = "graph TD\n  A --> B";
    const md = "```mermaid\n" + fenceBody + "\n```";
    let callCount = 0;
    (globalThis as any).mermaid = {
      initialize: () => {},
      render: async () => {
        callCount++;
        return { svg: '<svg data-call="' + callCount + '"></svg>' };
      },
    };

    await localPreview.render(md, null, {});
    await localPreview.render(md, null, {});

    expect(callCount).toBe(1);
    const diagram = document.querySelector(".mermaid-diagram")!;
    expect(diagram.innerHTML).toContain('data-call="1"');
  });

  test("a mermaid render error is shown inline instead of throwing out of render()", async () => {
    const md = "```mermaid\nnot a real diagram\n```";
    (globalThis as any).mermaid = {
      initialize: () => {},
      render: async () => {
        throw new Error("No diagram type detected");
      },
    };

    // render() は changedLines も返すので、見たい項目だけを確かめる
    await expect(localPreview.render(md, null, {})).resolves.toMatchObject({
      changed: 0,
    });
    const diagram = document.querySelector(".mermaid-diagram")!;
    expect(diagram.innerHTML).toContain("No diagram type detected");
    expect(diagram.getAttribute("data-mermaid-pending")).toBeNull();
  });
});
