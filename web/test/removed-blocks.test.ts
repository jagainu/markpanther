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

const gaps = () =>
  Array.from(document.querySelectorAll(".markpanther-removed-block"));
const content = () => document.getElementById("content")!;

describe("ブロックごと消えた箇所", () => {
  test("段落がまるごと消えると、あった場所に印が残る", async () => {
    await preview.render("一段落目。\n\n消える段落。\n\n三段落目。", null, {});
    await preview.render("一段落目。\n\n三段落目。", null, {
      markChanges: true,
    });

    const found = gaps();
    expect(found.length).toBe(1);
    expect(found[0].getAttribute("data-removed")).toBe("消える段落。");
  });

  test("印は消えた段落と三段落目のあいだに入る", async () => {
    await preview.render("一段落目。\n\n消える段落。\n\n三段落目。", null, {});
    await preview.render("一段落目。\n\n三段落目。", null, {
      markChanges: true,
    });

    const children = Array.from(content().children);
    const gapIndex = children.indexOf(gaps()[0]);
    const first = children.findIndex((el) => el.textContent === "一段落目。");
    const third = children.findIndex((el) => el.textContent === "三段落目。");
    expect(gapIndex).toBeGreaterThan(first);
    expect(gapIndex).toBeLessThan(third);
  });

  test("先頭の段落が消えたときは本文の一番上に入る", async () => {
    await preview.render("消える段落。\n\n残る段落。", null, {});
    await preview.render("残る段落。", null, { markChanges: true });

    const found = gaps();
    expect(found.length).toBe(1);
    expect(content().children[0]).toBe(found[0]);
  });

  test("リスト項目が消えたときは、同じリストの中に印が入る", async () => {
    await preview.render("- 残る\n- 消える\n- これも残る", null, {});
    await preview.render("- 残る\n- これも残る", null, { markChanges: true });

    const found = gaps();
    expect(found.length).toBe(1);
    expect(found[0].tagName).toBe("LI");
    expect(found[0].parentElement!.tagName).toBe("UL");
    expect(found[0].getAttribute("data-removed")).toBe("消える");
  });

  test("連続して2つ消えると印も2つ出る", async () => {
    await preview.render("A。\n\nB。\n\nC。\n\nD。", null, {});
    await preview.render("A。\n\nD。", null, { markChanges: true });

    expect(gaps().length).toBe(2);
    expect(gaps().map((g) => g.getAttribute("data-removed"))).toEqual([
      "B。",
      "C。",
    ]);
  });

  test("書き換えられただけの段落は印を作らない", async () => {
    // 似ているので「消えて別のが出た」ではなく「変わった」として扱う
    await preview.render("前提は3つある。", null, {});
    await preview.render("前提は4つある。", null, { markChanges: true });
    expect(gaps().length).toBe(0);
  });

  test("追加だけなら印は出ない", async () => {
    await preview.render("A。", null, {});
    await preview.render("A。\n\nB。", null, { markChanges: true });
    expect(gaps().length).toBe(0);
  });

  test("印は本文の文字を増やさない", async () => {
    await preview.render("一段落目。\n\n消える段落。\n\n三段落目。", null, {});
    await preview.render("一段落目。\n\n三段落目。", null, {
      markChanges: true,
    });

    expect(gaps()[0].textContent).toBe("");
    expect(content().textContent).not.toContain("消える段落");
  });

  test("消えたブロックも変更数に数える", async () => {
    await preview.render("A。\n\n消える。\n\nC。", null, {});
    const result = await preview.render("A。\n\nC。", null, {
      markChanges: true,
    });
    expect(result.changed).toBe(1);
  });

  test("書き出す HTML には印を残さない", async () => {
    await preview.render("一段落目。\n\n消える段落。\n\n三段落目。", null, {});
    await preview.render("一段落目。\n\n三段落目。", null, {
      markChanges: true,
    });
    expect(gaps().length).toBe(1);

    const html = preview.getBodyHTML();
    expect(html).not.toContain("markpanther-removed-block");
    expect(html).not.toContain("消える段落");
  });

  test("外部更新でない再描画でも印は残る", async () => {
    await preview.render("一段落目。\n\n消える段落。\n\n三段落目。", null, {});
    await preview.render("一段落目。\n\n三段落目。", null, {
      markChanges: true,
    });
    expect(gaps().length).toBe(1);

    // 設定変更やモード切替での引き直し。光らせないが印は保つ
    await preview.render("一段落目。\n\n三段落目。", null, {});
    expect(gaps().length).toBe(1);
  });

  test("次の外部更新でも前の印は残る（積み上げ）", async () => {
    await preview.render("一段落目。\n\n消える段落。\n\n三段落目。", null, {});
    await preview.render("一段落目。\n\n三段落目。", null, {
      markChanges: true,
    });
    expect(gaps().length).toBe(1);

    await preview.render("一段落目。\n\n三段落目。\n\n足した。", null, {
      markChanges: true,
    });
    expect(gaps().length).toBe(1);
    expect(gaps()[0].getAttribute("data-removed")).toBe("消える段落。");
  });

  test("隣のブロックが書き換わっていても、印はその直後に入る", async () => {
    // 署名だけで残存を見ると、書き換えられたブロックは「消えた」扱いになり、
    // 印が前のブロックまで繰り上がってしまう
    await preview.render("見出しの段落。\n\n前提は3つある。\n\n消える段落。\n\n最後。", null, {});
    await preview.render("見出しの段落。\n\n前提は4つある。\n\n最後。", null, {
      markChanges: true,
    });

    const children = Array.from(content().children);
    const gapIndex = children.indexOf(gaps()[0]);
    const edited = children.findIndex((el) => el.textContent === "前提は4つある。");
    expect(gapIndex).toBe(edited + 1);
  });

  test("マウスを乗せていないあいだは消えた本文を持たない", async () => {
    await preview.render("一段落目。\n\n消える段落。\n\n三段落目。", null, {});
    await preview.render("一段落目。\n\n三段落目。", null, {
      markChanges: true,
    });

    expect(gaps()[0].textContent).toBe("");
    expect(content().textContent).not.toContain("消える段落");
  });

  test("印にマウスを乗せると、その場に変更前の本文が戻る", async () => {
    await preview.render("一段落目。\n\n消える段落。\n\n三段落目。", null, {});
    await preview.render("一段落目。\n\n三段落目。", null, {
      markChanges: true,
    });

    const gap = gaps()[0];
    preview.showRemovedReveal(gap);

    const reveal = gap.querySelector(".markpanther-removed-reveal")!;
    expect(reveal.textContent).toBe("消える段落。");
    expect(gap.classList.contains("is-open")).toBe(true);
  });

  test("離れると元に戻る", async () => {
    await preview.render("一段落目。\n\n消える段落。\n\n三段落目。", null, {});
    await preview.render("一段落目。\n\n三段落目。", null, {
      markChanges: true,
    });

    const gap = gaps()[0];
    preview.showRemovedReveal(gap);
    preview.hideRemovedReveal();

    expect(gap.querySelector(".markpanther-removed-reveal")).toBeNull();
    expect(gap.classList.contains("is-open")).toBe(false);
    expect(content().textContent).not.toContain("消える段落");
  });

  test("行内の ▲ では、消えた文字が元の位置に差し込まれる", async () => {
    await preview.render("段落です。ここは消える予定。", null, {});
    await preview.render("段落です。", null, { markChanges: true });

    const inline = document.querySelector(".markpanther-removed") as HTMLElement;
    preview.showRemovedReveal(inline);

    // 印のすぐ後ろ = 消えた文字があった位置
    const reveal = content().querySelector(".markpanther-removed-reveal")!;
    expect(reveal.textContent).toBe("ここは消える予定。");
    expect(inline.nextElementSibling).toBe(reveal);
    // 変更前の姿がそのまま読める（末尾の改行は markdown-it が出すもの）
    expect(content().textContent!.trim()).toBe("段落です。ここは消える予定。");
  });

  test("別の印に移ると前の表示は消える", async () => {
    await preview.render("A。\n\nB。\n\nC。\n\nD。", null, {});
    await preview.render("A。\n\nD。", null, { markChanges: true });

    const [first, second] = gaps();
    preview.showRemovedReveal(first);
    preview.showRemovedReveal(second);

    expect(first.querySelector(".markpanther-removed-reveal")).toBeNull();
    expect(second.querySelector(".markpanther-removed-reveal")!.textContent).toBe("C。");
  });

  test("戻して見せているあいだも書き出す HTML には残らない", async () => {
    await preview.render("一段落目。\n\n消える段落。\n\n三段落目。", null, {});
    await preview.render("一段落目。\n\n三段落目。", null, {
      markChanges: true,
    });
    preview.showRemovedReveal(gaps()[0]);

    const html = preview.getBodyHTML();
    expect(html).not.toContain("markpanther-removed-block");
    expect(html).not.toContain("消える段落");
  });

});
