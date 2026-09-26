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

const marked = () =>
  Array.from(
    document.querySelectorAll(
      "#content .markpanther-changed, #content .markpanther-changed-recent",
    ),
  ).map((el) => el.textContent);

const gaps = () =>
  Array.from(document.querySelectorAll(".markpanther-removed-block")).map((el) =>
    el.getAttribute("data-removed"),
  );

describe("変更の印は積み上がる", () => {
  test("2回続けて外から書き換わると、どちらの印も残る", async () => {
    await preview.render("A。\n\nB。\n\nC。", null, {});
    await preview.render("A2。\n\nB。\n\nC。", null, { markChanges: true });
    await preview.render("A2。\n\nB。\n\nC2。", null, { markChanges: true });

    // 1回目の A と 2回目の C が両方とも印を持つ
    expect(marked()).toEqual(["A2。", "C2。"]);
  });

  test("3回目も積み上がる", async () => {
    await preview.render("A。\n\nB。\n\nC。", null, {});
    await preview.render("A2。\n\nB。\n\nC。", null, { markChanges: true });
    await preview.render("A2。\n\nB2。\n\nC。", null, { markChanges: true });
    await preview.render("A2。\n\nB2。\n\nC2。", null, { markChanges: true });

    expect(marked()).toEqual(["A2。", "B2。", "C2。"]);
  });

  test("消えたブロックの印も積み上がる", async () => {
    await preview.render("A。\n\n消える1。\n\nB。\n\n消える2。", null, {});
    await preview.render("A。\n\nB。\n\n消える2。", null, { markChanges: true });
    await preview.render("A。\n\nB。", null, { markChanges: true });

    expect(gaps()).toEqual(["消える1。", "消える2。"]);
  });

  test("変更数も積み上がった数になる", async () => {
    await preview.render("A。\n\nB。\n\nC。", null, {});
    await preview.render("A2。\n\nB。\n\nC。", null, { markChanges: true });
    const result = await preview.render("A2。\n\nB。\n\nC2。", null, {
      markChanges: true,
    });
    expect(result.changed).toBe(2);
  });

  test("× で消すと、そこから積み直しになる", async () => {
    await preview.render("A。\n\nB。\n\nC。", null, {});
    await preview.render("A2。\n\nB。\n\nC。", null, { markChanges: true });
    preview.clearChangeMarks();

    await preview.render("A2。\n\nB。\n\nC2。", null, { markChanges: true });
    expect(marked()).toEqual(["C2。"]);
  });

  test("自分で編集したら積み直しになる", async () => {
    await preview.render("A。\n\nB。\n\nC。", null, {});
    await preview.render("A2。\n\nB。\n\nC。", null, { markChanges: true });
    expect(marked()).toEqual(["A2。"]);

    // エディタでの打鍵（markChanges なしで内容が変わる）
    await preview.render("A2。\n\nB。\n\nC。自分で足した。", null, {});
    expect(marked()).toEqual([]);

    await preview.render("A2。\n\nB2。\n\nC。自分で足した。", null, {
      markChanges: true,
    });
    expect(marked()).toEqual(["B2。"]);
  });

  test("設定変更などの引き直しでは積んだ印が消えない", async () => {
    await preview.render("A。\n\nB。", null, {});
    await preview.render("A2。\n\nB。", null, { markChanges: true });
    await preview.render("A2。\n\nB。", null, { codeLineNumbers: true });
    expect(marked()).toEqual(["A2。"]);
  });

  test("同じ場所が2回書き換わっても最初の版からの差分になる", async () => {
    await preview.render("前提は1つある。", null, {});
    await preview.render("前提は2つある。", null, { markChanges: true });
    await preview.render("前提は3つある。", null, { markChanges: true });

    // 基準は「1」の版。消えたのは 1 であって 2 ではない
    const removed = document.querySelector(".markpanther-removed");
    expect(removed!.getAttribute("data-removed")).toBe("1");
  });
});
