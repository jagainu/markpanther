import { beforeEach, describe, expect, test } from "bun:test";
import { loadAllVendorScripts, loadPreviewJs, setupDom } from "./dom-setup";

class FakeHighlight {
  ranges: Range[] = [];
  priority = 0;
  add(r: Range) { this.ranges.push(r); }
}
class FakeRegistry {
  store = new Map<string, FakeHighlight>();
  set(k: string, v: FakeHighlight) { this.store.set(k, v); }
  delete(k: string) { this.store.delete(k); }
  get(k: string) { return this.store.get(k); }
  has(k: string) { return this.store.has(k); }
}

let vendorLoaded = false;
let preview: any;

beforeEach(() => {
  setupDom();
  if (!vendorLoaded) {
    loadAllVendorScripts();
    vendorLoaded = true;
  }
  (globalThis as any).Highlight = FakeHighlight;
  (globalThis as any).CSS = { highlights: new FakeRegistry() };
  preview = loadPreviewJs();
});

const addedText = () => {
  const group = (globalThis as any).CSS.highlights.get("markpanther-added");
  return group ? group.ranges.map((r: Range) => r.toString()) : [];
};

const wholeAdded = () =>
  Array.from(document.querySelectorAll(".markpanther-added-whole")).map(
    (el) => el.textContent,
  );

describe("追加の網掛け", () => {
  // 箇条書きの点まで含めて塗りたいので、行ごと足された場合は範囲ハイライトではなく
  // 要素の背景で塗る（範囲ハイライトは文字にしか乗らない）
  test("行ごと足されたらブロックごと塗る", async () => {
    await preview.render("- 残る\n- これも残る", null, {});
    await preview.render("- 残る\n- これも残る\n- あとから足した行", null, {
      markChanges: true,
    });
    expect(wholeAdded()).toEqual(["あとから足した行"]);
    expect(addedText()).toEqual([]);
  });

  test("段落がまるごと足された場合もブロックごと", async () => {
    await preview.render("一段落目。", null, {});
    await preview.render("一段落目。\n\nまるごと新しい段落。", null, {
      markChanges: true,
    });
    expect(wholeAdded()).toEqual(["まるごと新しい段落。"]);
  });

  test("書き換えられた行は変わった部分だけを塗る", async () => {
    await preview.render("前提は3つある。", null, {});
    await preview.render("前提は4つある。", null, { markChanges: true });
    expect(addedText()).toEqual(["4"]);
    expect(wholeAdded()).toEqual([]);
  });

  test("消えただけの行は塗らない", async () => {
    await preview.render("段落です。ここは消える。", null, {});
    await preview.render("段落です。", null, { markChanges: true });
    expect(addedText()).toEqual([]);
  });
});
