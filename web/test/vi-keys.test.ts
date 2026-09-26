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

/** キーイベントの最小限の形。preview.js が見るのは key と修飾キーと target だけ。 */
const key = (
  k: string,
  mods: Partial<
    Record<"ctrlKey" | "metaKey" | "altKey" | "shiftKey", boolean>
  > = {},
  target: any = null,
) => ({
  key: k,
  ctrlKey: false,
  metaKey: false,
  altKey: false,
  shiftKey: false,
  target,
  ...mods,
});

describe("viCommand", () => {
  test("j and k move one line", () => {
    expect(preview.viCommand(key("j"))).toEqual({ kind: "lines", amount: 1 });
    expect(preview.viCommand(key("k"))).toEqual({ kind: "lines", amount: -1 });
  });

  test("control-d and control-u move half a page", () => {
    expect(preview.viCommand(key("d", { ctrlKey: true }))).toEqual({
      kind: "pages",
      amount: 0.5,
    });
    expect(preview.viCommand(key("u", { ctrlKey: true }))).toEqual({
      kind: "pages",
      amount: -0.5,
    });
  });

  test("control-f and control-b move a full page", () => {
    expect(preview.viCommand(key("f", { ctrlKey: true }))).toEqual({
      kind: "pages",
      amount: 1,
    });
    expect(preview.viCommand(key("b", { ctrlKey: true }))).toEqual({
      kind: "pages",
      amount: -1,
    });
  });

  test("shift-G jumps to the bottom", () => {
    expect(preview.viCommand(key("G", { shiftKey: true }))).toEqual({
      kind: "bottom",
    });
  });

  test("gg jumps to the top, and a lone g does nothing", () => {
    expect(preview.viCommand(key("g"))).toBeNull();
    expect(preview.viCommand(key("g"))).toEqual({ kind: "top" });
  });

  test("the pending g is dropped when another key comes between", () => {
    expect(preview.viCommand(key("g"))).toBeNull();
    expect(preview.viCommand(key("j"))).toEqual({ kind: "lines", amount: 1 });
    expect(preview.viCommand(key("g"))).toBeNull();
    expect(preview.viCommand(key("g"))).toEqual({ kind: "top" });
  });

  test("a third g starts a fresh pair rather than repeating", () => {
    preview.viCommand(key("g"));
    expect(preview.viCommand(key("g"))).toEqual({ kind: "top" });
    expect(preview.viCommand(key("g"))).toBeNull();
  });

  // ⌘ は macOS のメニューショートカット、⌥ は文字入力。どちらも横取りしない
  test("command and option combinations are left alone", () => {
    expect(preview.viCommand(key("j", { metaKey: true }))).toBeNull();
    expect(preview.viCommand(key("j", { altKey: true }))).toBeNull();
    expect(
      preview.viCommand(key("d", { metaKey: true, ctrlKey: true })),
    ).toBeNull();
  });

  test("keys with no meaning here are left alone", () => {
    for (const k of ["a", "z", "Enter", "ArrowDown", "1"]) {
      expect(preview.viCommand(key(k))).toBeNull();
    }
  });

  test("typing into a field is never treated as scrolling", () => {
    const input = document.createElement("input");
    expect(preview.viCommand(key("j", {}, input))).toBeNull();

    const editable = document.createElement("div");
    // happy-dom は isContentEditable を持たないので、実ブラウザと同じ形に寄せる
    Object.defineProperty(editable, "isContentEditable", { value: true });
    expect(preview.viCommand(key("k", {}, editable))).toBeNull();
  });
});

describe("applyViCommand", () => {
  let scrolledBy: number[];
  let scrolledTo: number[];

  beforeEach(() => {
    scrolledBy = [];
    scrolledTo = [];
    (globalThis as any).scrollBy = (opts: any) =>
      scrolledBy.push(opts.top ?? opts);
    (globalThis as any).scrollTo = (opts: any) =>
      scrolledTo.push(opts.top ?? opts);
    Object.defineProperty(globalThis, "innerHeight", {
      value: 800,
      configurable: true,
    });
    // happy-dom はレイアウトしないので、末尾へ飛ぶ距離は自分で与える
    Object.defineProperty(document.documentElement, "scrollHeight", {
      value: 5000,
      configurable: true,
    });
  });

  test("a line command scrolls by a positive step", () => {
    preview.applyViCommand({ kind: "lines", amount: 1 });
    expect(scrolledBy.length).toBe(1);
    expect(scrolledBy[0]).toBeGreaterThan(0);
  });

  test("k scrolls the same distance the other way", () => {
    preview.applyViCommand({ kind: "lines", amount: 1 });
    preview.applyViCommand({ kind: "lines", amount: -1 });
    expect(scrolledBy[1]).toBe(-scrolledBy[0]);
  });

  test("a half page is half the viewport", () => {
    preview.applyViCommand({ kind: "pages", amount: 0.5 });
    expect(scrolledBy[0]).toBe(400);
  });

  test("top and bottom jump instead of stepping", () => {
    preview.applyViCommand({ kind: "top" });
    expect(scrolledTo[0]).toBe(0);
    preview.applyViCommand({ kind: "bottom" });
    expect(scrolledTo[1]).toBeGreaterThan(0);
  });

  test("an unknown command is ignored", () => {
    preview.applyViCommand(null);
    preview.applyViCommand({ kind: "sideways" });
    expect(scrolledBy.length + scrolledTo.length).toBe(0);
  });
});
