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

/** 削除は新しい本文のどこで起きたかで表す。{at, text} の組で返る。 */
const removals = (before: string, after: string) =>
  preview.diffTexts(before, after).removals;

describe("diffTexts の removals", () => {
  test("途中が消えると、消えた文字列と新しい本文での位置が返る", () => {
    const result = removals("the quick brown fox", "the fox");
    expect(result.length).toBe(1);
    expect(result[0].text).toBe("quick brown ");
    // "the " の直後
    expect(result[0].at).toBe(4);
  });

  test("末尾が消えたときは新しい本文の終端を指す", () => {
    const result = removals("keep this away", "keep this");
    expect(result.length).toBe(1);
    expect(result[0].text.trim()).toBe("away");
    expect(result[0].at).toBe("keep this".length);
  });

  test("先頭が消えたときは 0 を指す", () => {
    const result = removals("drop the rest", "the rest");
    expect(result.length).toBe(1);
    expect(result[0].at).toBe(0);
    expect(result[0].text).toBe("drop ");
  });

  test("離れた2箇所の削除は別々に返る", () => {
    const result = removals(
      "alpha bravo charlie delta echo",
      "alpha charlie echo",
    );
    expect(result.length).toBe(2);
    expect(result.map((r: any) => r.text.trim())).toEqual(["bravo", "delta"]);
  });

  test("追加しかないときは空", () => {
    expect(removals("alpha", "alpha bravo")).toEqual([]);
  });

  test("同じ本文なら空", () => {
    expect(removals("same text", "same text")).toEqual([]);
  });

  test("空白だけの削除は印にしない", () => {
    // 行末の空白が消えただけ。読み手に知らせる価値がないので落とす
    expect(removals("alpha   bravo", "alpha bravo")).toEqual([]);
  });

  test("日本語でも消えた箇所が取れる", () => {
    const result = removals("前提は3つある。ここは消える。", "前提は3つある。");
    expect(result.length).toBe(1);
    expect(result[0].text).toBe("ここは消える。");
    expect(result[0].at).toBe("前提は3つある。".length);
  });

  test("全部消えたときも1件にまとまる", () => {
    const result = removals("everything goes", "");
    expect(result.length).toBe(1);
    expect(result[0].at).toBe(0);
  });

  test("大きすぎる入力でも落ちずに削除を返す", () => {
    const before = Array.from({ length: 2600 }, (_, i) => `token${i}`).join(
      " ",
    );
    const after = before.slice(0, 200);
    const result = removals(before, after);
    expect(Array.isArray(result)).toBe(true);
    expect(result.length).toBeGreaterThan(0);
  });
});

describe("プレビューに置く削除の印", () => {
  const markers = () =>
    Array.from(document.querySelectorAll(".markpanther-removed"));

  test("外部更新で消えた箇所に印が付く", async () => {
    await preview.render("段落です。ここは消える予定。", null, {});
    await preview.render("段落です。", null, { markChanges: true });

    const found = markers();
    expect(found.length).toBe(1);
    expect(found[0].getAttribute("data-removed")).toBe("ここは消える予定。");
  });

  test("印は本文の文字を1つも増やさない", async () => {
    await preview.render("keep this away", null, {});
    await preview.render("keep this", null, { markChanges: true });

    expect(markers().length).toBe(1);
    const content = document.getElementById("content")!;
    // 最新版の表示を乱さないことが要件。印は文字を持たない
    // （末尾の改行は markdown-it が出すもので、印とは無関係）
    expect(content.textContent!.trim()).toBe("keep this");
    expect(markers()[0].textContent).toBe("");
  });

  test("markChanges なしの描画では印を置かない", async () => {
    await preview.render("段落です。ここは消える予定。", null, {});
    await preview.render("段落です。", null, {});
    expect(markers().length).toBe(0);
  });

  test("追加だけの更新では印が出ない", async () => {
    await preview.render("alpha", null, {});
    await preview.render("alpha bravo", null, { markChanges: true });
    expect(markers().length).toBe(0);
  });

  test("書き出す HTML には印を残さない", async () => {
    await preview.render("段落です。ここは消える予定。", null, {});
    await preview.render("段落です。", null, { markChanges: true });
    expect(markers().length).toBe(1);

    expect(preview.getBodyHTML()).not.toContain("markpanther-removed");
    expect(preview.getBodyHTML()).not.toContain("data-removed");
  });

  test("削除だけのブロックは印を分けて持つ（● をグレーにするため）", async () => {
    await preview.render("段落です。ここは消える予定。", null, {});
    await preview.render("段落です。", null, { markChanges: true });

    const block = document.querySelector(".markpanther-changed")!;
    expect(block.classList.contains("markpanther-removal-only")).toBe(true);
  });

  test("追加も混ざるブロックは削除だけの印を持たない", async () => {
    await preview.render("前提は3つある。ここは消える。", null, {});
    await preview.render("前提は4つある。", null, { markChanges: true });

    const block = document.querySelector(".markpanther-changed")!;
    expect(block.classList.contains("markpanther-removal-only")).toBe(false);
  });

  test("追加だけのブロックも削除だけの印を持たない", async () => {
    await preview.render("alpha", null, {});
    await preview.render("alpha bravo", null, { markChanges: true });

    const block = document.querySelector(".markpanther-changed")!;
    expect(block.classList.contains("markpanther-removal-only")).toBe(false);
  });
});
