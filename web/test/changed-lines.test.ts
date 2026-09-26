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

describe("変更のあった行番号", () => {
  test("書き換えられたブロックの行を返す", async () => {
    await preview.render("# 見出し\n\n本文A。\n\n## 節\n\n本文B。", null, {});
    const result = await preview.render(
      "# 見出し\n\n本文A。\n\n## 節\n\n本文B2。",
      null,
      { markChanges: true },
    );
    // 行は 0 始まり（Swift の OutlineItem.line と同じ基準）。"本文B2。" は 7 行目 = 6
    expect(result.changedLines).toEqual([6]);
  });

  test("複数の変更は行順に並ぶ", async () => {
    await preview.render("A。\n\nB。\n\nC。", null, {});
    await preview.render("A2。\n\nB。\n\nC。", null, { markChanges: true });
    const result = await preview.render("A2。\n\nB。\n\nC2。", null, {
      markChanges: true,
    });
    expect(result.changedLines).toEqual([0, 4]);
  });

  test("消えたブロックの位置も含める", async () => {
    await preview.render("A。\n\n消える。\n\nC。", null, {});
    const result = await preview.render("A。\n\nC。", null, {
      markChanges: true,
    });
    // 消えた場所の手前に残っているブロック（A。= 先頭行）を指す
    expect(result.changedLines).toEqual([0]);
  });

  test("変更が無ければ空", async () => {
    await preview.render("A。\n\nB。", null, {});
    const result = await preview.render("A。\n\nB。", null, {
      markChanges: true,
    });
    expect(result.changedLines).toEqual([]);
  });

  test("外部更新でない描画でも、積んだ印の行を返す", async () => {
    await preview.render("A。\n\nB。", null, {});
    await preview.render("A2。\n\nB。", null, { markChanges: true });
    const result = await preview.render("A2。\n\nB。", null, {});
    expect(result.changedLines).toEqual([0]);
  });
});
