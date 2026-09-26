import { beforeEach, describe, expect, test } from "bun:test";
import { loadAllVendorScripts, loadPreviewJs, setupDom } from "./dom-setup";

let vendorLoaded = false;
let preview: any;
let posted: string[];

const MD = [
  "# Title",
  "",
  "```swift",
  "let x = 1",
  "print(x)",
  "```",
  "",
  "```",
  "plain block",
  "```",
  "",
  "```mermaid",
  "graph LR",
  "  A --> B",
  "```",
  "",
].join("\n");

function buttons(): HTMLButtonElement[] {
  return Array.from(document.querySelectorAll("#markpanther-overlays button.markpanther-copy-button")) as HTMLButtonElement[];
}

beforeEach(() => {
  setupDom();
  if (!vendorLoaded) {
    loadAllVendorScripts();
    vendorLoaded = true;
  }
  preview = loadPreviewJs();
  posted = [];
  (globalThis as any).window.webkit = {
    messageHandlers: { markpantherCopy: { postMessage: (text: string) => posted.push(text) } },
  };
});

describe("code block copy buttons", () => {
  test("codeTextForCopy returns the raw code, with or without line-number wrapping", async () => {
    await preview.render(MD, null, { mermaid: false, codeLineNumbers: false });
    const pre = document.querySelector("#content pre")!;
    expect(preview.codeTextForCopy(pre)).toBe("let x = 1\nprint(x)\n");

    await preview.render(MD, null, { mermaid: false, codeLineNumbers: true });
    const numbered = document.querySelector("#content pre")!;
    expect(preview.codeTextForCopy(numbered)).toBe("let x = 1\nprint(x)\n");
  });

  test("every code block gets an always-visible button that lives outside #content", async () => {
    await preview.render(MD, null, { mermaid: false });
    const content = document.getElementById("content")!;
    const before = content.innerHTML;

    // mermaid: false のときは mermaid フェンスも普通のコードブロックなので 3 個
    expect(buttons().length).toBe(3);
    for (const b of buttons()) {
      expect(b.hidden).toBe(false);
      expect(content.contains(b)).toBe(false);
    }
    // 本文の DOM には触らない（差分更新・検索・Copy HTML に影響させない）
    expect(content.innerHTML).toBe(before);
    expect(preview.getBodyHTML()).not.toContain("markpanther-copy");
  });

  test("clicking a button posts that block's code and flashes a copied state", async () => {
    await preview.render(MD, null, { mermaid: false });
    const [first, second] = buttons();
    second.click();
    expect(posted).toEqual(["plain block\n"]);
    expect(second.classList.contains("is-copied")).toBe(true);
    expect(first.classList.contains("is-copied")).toBe(false);
    first.click();
    expect(posted[1]).toBe("let x = 1\nprint(x)\n");
  });

  test("a re-render rebuilds the buttons to match the new code blocks", async () => {
    await preview.render(MD, null, { mermaid: false });
    await preview.render("no code here\n", null, { mermaid: false });
    expect(buttons().length).toBe(0);
    await preview.render("```js\n1\n```\n", null, { mermaid: false });
    expect(buttons().length).toBe(1);
    buttons()[0].click();
    expect(posted).toEqual(["1\n"]);
  });
});

describe("Copy HTML output", () => {
  test("does not leak internal attributes", async () => {
    await preview.render("# T\n\ntext\n\n| a |\n|---|\n| b |\n", null, { mermaid: false });
    const html = preview.getBodyHTML();
    expect(html).not.toContain("data-line");
    expect(html).not.toContain("data-mermaid");
    expect(html).toContain("<h1");
    // 表示中の DOM 側には残っている（位置の引き継ぎに使う）
    expect(document.getElementById("content")!.innerHTML).toContain("data-line");
  });
});
