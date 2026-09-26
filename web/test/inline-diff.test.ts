import { beforeEach, describe, expect, test } from "bun:test";
import { loadAllVendorScripts, loadPreviewJs, setupDom } from "./dom-setup";

let vendorLoaded = false;
let preview: any;

class FakeHighlight {
  ranges: Range[] = [];
  priority = 0;
  add(r: Range) {
    this.ranges.push(r);
  }
}
class FakeRegistry {
  store = new Map<string, FakeHighlight>();
  set(k: string, v: FakeHighlight) {
    this.store.set(k, v);
  }
  delete(k: string) {
    this.store.delete(k);
  }
  get(k: string) {
    return this.store.get(k);
  }
  has(k: string) {
    return this.store.has(k);
  }
}

function addedTexts(): string[] {
  const registry = (globalThis as any).CSS?.highlights as FakeRegistry | undefined;
  const hl = registry?.get("markpanther-added");
  return hl ? hl.ranges.map((r) => r.toString()) : [];
}

beforeEach(() => {
  setupDom();
  if (!vendorLoaded) {
    loadAllVendorScripts();
    vendorLoaded = true;
  }
  preview = loadPreviewJs();
  (globalThis as any).CSS = { highlights: new FakeRegistry() };
  (globalThis as any).Highlight = FakeHighlight;
});

function slices(text: string, ranges: number[][]): string[] {
  return ranges.map(([s, e]) => text.slice(s, e));
}

describe("diffAddedRanges", () => {
  test("appended words", () => {
    const next = "edited after the move testtest";
    expect(slices(next, preview.diffAddedRanges("edited after the move", next))).toEqual([" testtest"]);
  });

  test("a replaced word in the middle", () => {
    const next = "the slow brown fox";
    expect(slices(next, preview.diffAddedRanges("the quick brown fox", next))).toEqual(["slow"]);
  });

  test("Japanese is compared character by character", () => {
    const next = "これは新しい文章です。";
    expect(slices(next, preview.diffAddedRanges("これは文章です。", next))).toEqual(["新しい"]);
  });

  test("identical text and pure deletions yield nothing", () => {
    expect(preview.diffAddedRanges("same", "same")).toEqual([]);
    expect(preview.diffAddedRanges("one two three", "one three")).toEqual([]);
  });

  test("adjacent added tokens merge into one range", () => {
    const next = "a brand new b";
    expect(slices(next, preview.diffAddedRanges("a b", next))).toEqual(["brand new "]);
  });

  test("very large inputs fall back to prefix/suffix trimming", () => {
    const base = "word ".repeat(4000);
    const next = base + "TAIL";
    expect(slices(next, preview.diffAddedRanges(base, next))).toEqual(["TAIL"]);
  });
});

describe("inline added marks on external updates", () => {
  test("only the added part of an edited paragraph is marked", async () => {
    await preview.render("# T\n\nedited after the move\n\nother\n", null, {});
    await preview.render("# T\n\nedited after the move testtest\n\nother\n", null, { markChanges: true });
    expect(addedTexts()).toEqual([" testtest"]);
    // 本文の DOM には印を埋め込まない
    expect(document.getElementById("content")!.innerHTML).not.toContain("markpanther-added");
  });

  test("works across inline markup and list items", async () => {
    await preview.render("- alpha **bold** end\n- beta\n", null, {});
    await preview.render("- alpha **bold** and more end\n- beta\n", null, { markChanges: true });
    expect(addedTexts()).toEqual(["and more "]);
  });

  test("a short line that gains a longer tail is still paired with its old version", async () => {
    await preview.render("- alpha\n- beta\n", null, {});
    await preview.render("- alpha\n- beta (edited)\n", null, { markChanges: true });
    expect(addedTexts()).toEqual([" (edited)"]);
  });

  // 対応が付かない = 書き換えではなく「新しい行」。語単位の誤った印を出す代わりに
  // 行全体を塗って「これは丸ごと新しい」と示す
  test("an unrelated replacement is marked whole, not word by word", async () => {
    await preview.render("first paragraph here\n\ntail\n", null, {});
    await preview.render("totally different words now\n\ntail\n", null, { markChanges: true });
    expect(addedTexts()).toEqual([]);
    expect(document.querySelectorAll(".markpanther-added-whole").length).toBe(1);
  });

  test("a brand-new block is shaded across the whole line", async () => {
    await preview.render("one\n", null, {});
    await preview.render("one\n\ncompletely new paragraph\n", null, { markChanges: true });
    expect(document.querySelectorAll("#content .markpanther-changed").length).toBe(1);
    expect(addedTexts()).toEqual([]);
    expect(document.querySelectorAll(".markpanther-added-whole").length).toBe(1);
  });

  test("marks survive a non-external re-render and accumulate on the next update", async () => {
    await preview.render("hello world\n", null, {});
    await preview.render("hello big world\n", null, { markChanges: true });
    await preview.render("hello big world\n", null, { markChanges: false, codeLineNumbers: true });
    expect(addedTexts()).toEqual(["big "]);

    // 印は積み上がるので、前回の "big " も残ったまま新しい行が加わる
    await preview.render("hello big world\n\nnew para\n", null, { markChanges: true });
    expect(addedTexts()).toEqual(["big "]);
    expect(document.querySelectorAll(".markpanther-added-whole").length).toBe(1);
  });

  test("find highlights take priority over added marks", async () => {
    await preview.render("hello world\n", null, {});
    await preview.render("hello big world\n", null, { markChanges: true });
    preview.find("big");
    const registry = (globalThis as any).CSS.highlights as FakeRegistry;
    expect(registry.get("markpanther-find-current")!.priority).toBeGreaterThan(registry.get("markpanther-added")!.priority);
  });
});
