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

const MD = "# Title\n\npara one\n\n- item a\n- item b\n\n```js\nlet x = 1\n```\n";

describe("preview line numbers", () => {
  test("blocks carry their 1-based source line, and the body opts in when asked", async () => {
    await preview.render(MD, null, { mermaid: false, lineNumbers: true });
    expect(document.body.classList.contains("markpanther-line-numbers")).toBe(true);
    const lno = (sel: string) => document.querySelector(`#content ${sel}`)!.getAttribute("data-lno");
    expect(lno("h1")).toBe("1");
    expect(lno("p")).toBe("3");
    expect(lno("li")).toBe("5");
    expect(lno("li:nth-child(2)")).toBe("6");
    expect(lno("pre")).toBe("8");
  });

  test("frontmatter lines are counted, so numbers match the file", async () => {
    await preview.render("---\ntitle: x\n---\n\n# After\n", null, { lineNumbers: true });
    expect(document.querySelector("#content h1")!.getAttribute("data-lno")).toBe("5");
  });

  test("can be turned off", async () => {
    await preview.render(MD, null, { lineNumbers: false });
    expect(document.body.classList.contains("markpanther-line-numbers")).toBe(false);
  });

  test("numbers never leak into Copy HTML and a shifted line is not a change", async () => {
    await preview.render(MD, null, { lineNumbers: true });
    expect(preview.getBodyHTML()).not.toContain("data-lno");
    const result = await preview.render("\n" + MD, null, { markChanges: true, lineNumbers: true });
    expect(result.changed).toBe(0);
    expect(document.querySelector("#content h1")!.getAttribute("data-lno")).toBe("2");
  });
});
