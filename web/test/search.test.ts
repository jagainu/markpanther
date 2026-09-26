import { beforeEach, describe, expect, test } from "bun:test";
import { loadAllVendorScripts, loadPreviewJs, setupDom } from "./dom-setup";

let vendorLoaded = false;
let preview: any;

/** CSS Custom Highlight API のごく簡単なモック（happy-dom には無いため）。 */
class FakeHighlight {
  ranges: any[] = [];
  add(r: any) {
    this.ranges.push(r);
  }
}
class FakeHighlightRegistry {
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

beforeEach(() => {
  setupDom();
  if (!vendorLoaded) {
    loadAllVendorScripts();
    vendorLoaded = true;
  }
  preview = loadPreviewJs();
  delete (globalThis as any).CSS;
  delete (globalThis as any).Highlight;
});

describe("find(): pure matching logic (findMatches)", () => {
  test("finds all non-overlapping case-insensitive occurrences", () => {
    const matches = preview.findMatches("Foo bar foo BAR foo", "foo");
    expect(matches).toEqual([
      { start: 0, end: 3 },
      { start: 8, end: 11 },
      { start: 16, end: 19 },
    ]);
  });

  test("returns an empty array for an empty query", () => {
    expect(preview.findMatches("hello", "")).toEqual([]);
  });

  test("returns an empty array when there is no match", () => {
    expect(preview.findMatches("hello world", "xyz")).toEqual([]);
  });
});

describe("find(): against the live #content DOM (no CSS.highlights available)", () => {
  test("reports the correct total for a simple document (CSS.highlights unsupported -> no throw)", async () => {
    await preview.render("Hello world. Hello again.", null, {});
    const result = preview.find("hello");
    expect(result).toEqual({ current: 1, total: 2 });
  });

  test("is case-insensitive", async () => {
    await preview.render("FOO foo Foo", null, {});
    expect(preview.find("foo")).toEqual({ current: 1, total: 3 });
  });

  test("matches text spanning multiple inline elements within the same block", async () => {
    // **foo**bar renders as <strong>foo</strong>bar — the text "foobar"
    // spans two nodes and should still be found as one match.
    await preview.render("**foo**bar", null, {});
    const result = preview.find("foobar");
    expect(result).toEqual({ current: 1, total: 1 });
  });

  test("does not match across a block boundary", async () => {
    await preview.render("end of one\n\nstart of two", null, {});
    // "one\n\nstart" would only match if blocks were joined without a
    // separator; it must not match since blocks are separated by a newline.
    const result = preview.find("onestart");
    expect(result).toEqual({ current: 0, total: 0 });
  });

  test("returns {0, 0} and does not throw when there are no matches", async () => {
    await preview.render("hello world", null, {});
    expect(preview.find("nonexistent")).toEqual({ current: 0, total: 0 });
  });

  test("returns {0, 0} for an empty query", async () => {
    await preview.render("hello world", null, {});
    expect(preview.find("")).toEqual({ current: 0, total: 0 });
  });

  test("repeated calls with the same query advance to the next match, wrapping at the end", async () => {
    await preview.render("foo foo foo", null, {});
    expect(preview.find("foo")).toEqual({ current: 1, total: 3 });
    expect(preview.find("foo")).toEqual({ current: 2, total: 3 });
    expect(preview.find("foo")).toEqual({ current: 3, total: 3 });
    expect(preview.find("foo")).toEqual({ current: 1, total: 3 }); // wraps
  });

  test("backwards option cycles to the previous match, wrapping at the start", async () => {
    await preview.render("foo foo foo", null, {});
    expect(preview.find("foo")).toEqual({ current: 1, total: 3 });
    expect(preview.find("foo", { backwards: true })).toEqual({
      current: 3,
      total: 3,
    }); // wraps backwards from 1
    expect(preview.find("foo", { backwards: true })).toEqual({
      current: 2,
      total: 3,
    });
  });

  test("a new (different) query resets to a fresh match rather than advancing", async () => {
    await preview.render("foo foo bar", null, {});
    expect(preview.find("foo")).toEqual({ current: 1, total: 2 });
    expect(preview.find("foo")).toEqual({ current: 2, total: 2 });
    expect(preview.find("bar")).toEqual({ current: 1, total: 1 });
  });

  test("clearFind resets state so the next find() starts fresh", async () => {
    await preview.render("foo foo", null, {});
    preview.find("foo");
    preview.find("foo");
    preview.clearFind();
    expect(preview.find("foo")).toEqual({ current: 1, total: 2 });
  });
});

describe("find(): CSS Custom Highlight API integration (mocked)", () => {
  beforeEach(() => {
    (globalThis as any).Highlight = FakeHighlight;
    (globalThis as any).CSS = { highlights: new FakeHighlightRegistry() };
  });

  test("populates the markpanther-find and markpanther-find-current highlight groups without throwing", async () => {
    await preview.render("foo bar foo", null, {});
    const result = preview.find("foo");
    expect(result).toEqual({ current: 1, total: 2 });

    const registry: FakeHighlightRegistry = (globalThis as any).CSS.highlights;
    const current = registry.get("markpanther-find-current");
    const all = registry.get("markpanther-find");
    expect(current).toBeInstanceOf(FakeHighlight);
    expect(current!.ranges.length).toBe(1);
    expect(all).toBeInstanceOf(FakeHighlight);
    expect(all!.ranges.length).toBe(1); // the other (non-current) match
  });

  test("clearFind removes both highlight groups", async () => {
    await preview.render("foo bar foo", null, {});
    preview.find("foo");
    preview.clearFind();
    const registry: FakeHighlightRegistry = (globalThis as any).CSS.highlights;
    expect(registry.has("markpanther-find")).toBe(false);
    expect(registry.has("markpanther-find-current")).toBe(false);
  });
});

describe("find(): re-applied after render()", () => {
  test("a render() while a search is active re-highlights the same query", async () => {
    (globalThis as any).Highlight = FakeHighlight;
    (globalThis as any).CSS = { highlights: new FakeHighlightRegistry() };

    await preview.render("foo bar", null, {});
    expect(preview.find("foo")).toEqual({ current: 1, total: 1 });

    await preview.render("foo bar, foo again", null, {});

    const registry: FakeHighlightRegistry = (globalThis as any).CSS.highlights;
    // 再 render 後、同じ query でハイライトが張り直されているはず
    expect(registry.get("markpanther-find")!.ranges.length).toBe(1);
    expect(registry.get("markpanther-find-current")!.ranges.length).toBe(1);
  });

  test("if a render() removes the current match, the current index is clamped into range", async () => {
    await preview.render("foo foo foo", null, {});
    preview.find("foo");
    preview.find("foo"); // current = 2 of 3
    await preview.render("just one foo now", null, {});
    // re-apply should clamp: only 1 match remains, current must be 1 of 1
    const again = preview.find("foo"); // same query -> advances from clamped state, wraps within 1 match
    expect(again.total).toBe(1);
    expect(again.current).toBe(1);
  });

  test("render() without an active search does not create any highlight state", async () => {
    (globalThis as any).Highlight = FakeHighlight;
    (globalThis as any).CSS = { highlights: new FakeHighlightRegistry() };
    await preview.render("hello world", null, {});
    const registry: FakeHighlightRegistry = (globalThis as any).CSS.highlights;
    expect(registry.has("markpanther-find")).toBe(false);
    expect(registry.has("markpanther-find-current")).toBe(false);
  });
});
