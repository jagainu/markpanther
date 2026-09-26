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

const marks = () =>
  document.querySelectorAll(
    ".markpanther-changed, .markpanther-changed-recent, .markpanther-removed, .markpanther-removed-block, .markpanther-removal-only",
  ).length;

async function makeChanges() {
  await preview.render("一段落目。ここは消える。\n\n消える段落。\n\n最後。", null, {});
  await preview.render("一段落目。\n\n最後。足した。", null, { markChanges: true });
}

describe("clearChangeMarks", () => {
  test("追加・削除・ブロック削除の印をまとめて消す", async () => {
    await makeChanges();
    expect(marks()).toBeGreaterThan(0);

    preview.clearChangeMarks();
    expect(marks()).toBe(0);
  });

  test("本文そのものは変えない", async () => {
    await makeChanges();
    const before = document.getElementById("content")!.textContent;
    preview.clearChangeMarks();
    expect(document.getElementById("content")!.textContent).toBe(before);
  });

  test("消したあとの再描画で印が戻らない", async () => {
    await makeChanges();
    preview.clearChangeMarks();

    // 設定変更やモード切替での引き直し
    await preview.render("一段落目。\n\n最後。足した。", null, {});
    expect(marks()).toBe(0);
  });

  test("次の外部更新では新しい印が出る", async () => {
    await makeChanges();
    preview.clearChangeMarks();

    await preview.render("一段落目。\n\n最後。足した。\n\nさらに足した。", null, {
      markChanges: true,
    });
    expect(marks()).toBeGreaterThan(0);
  });

  test("印が無いときに呼んでも落ちない", () => {
    expect(() => preview.clearChangeMarks()).not.toThrow();
  });
});
