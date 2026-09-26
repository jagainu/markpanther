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

describe("chrome insets", () => {
  test("setInsets exposes the values as CSS variables on the root element", () => {
    preview.setInsets(46, 52);
    const style = document.documentElement.style;
    expect(style.getPropertyValue("--markpanther-top-inset")).toBe("46px");
    expect(style.getPropertyValue("--markpanther-bottom-inset")).toBe("52px");
  });

  test("negative or non-numeric insets are clamped to zero", () => {
    preview.setInsets(-5, "x" as any);
    const style = document.documentElement.style;
    expect(style.getPropertyValue("--markpanther-top-inset")).toBe("0px");
    expect(style.getPropertyValue("--markpanther-bottom-inset")).toBe("0px");
  });

  test("pickTopLine prefers the element nearest the inset line, not the window top", () => {
    const rects = [
      { line: 0, top: -30, bottom: 10 },   // カプセルの下に隠れている
      { line: 4, top: 50, bottom: 90 },    // 余白のすぐ下 = 見えている先頭
      { line: 9, top: 300, bottom: 340 },
    ];
    expect(preview.pickTopLine(rects, 46)).toBe(4);
    expect(preview.pickTopLine(rects, 0)).toBe(0);
    expect(preview.pickTopLine([], 46)).toBe(0);
  });
});
