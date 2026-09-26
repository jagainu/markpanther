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

describe("zoom", () => {
  test("setZoom exposes the factor as a CSS variable and clamps it", () => {
    preview.setZoom(1.25);
    expect(document.documentElement.style.getPropertyValue("--markpanther-zoom")).toBe("1.25");
    preview.setZoom(99);
    expect(document.documentElement.style.getPropertyValue("--markpanther-zoom")).toBe("3");
    preview.setZoom("x" as any);
    expect(document.documentElement.style.getPropertyValue("--markpanther-zoom")).toBe("1");
  });

  test("diagrams scale by width (viewBox), remembering their natural size", async () => {
    await preview.render("text\n", null, { mermaid: false });
    const content = document.getElementById("content")!;
    const holder = document.createElement("div");
    holder.className = "mermaid-diagram";
    holder.innerHTML = '<svg style="max-width: 360px;" viewBox="0 0 360 64"></svg>';
    content.appendChild(holder);
    const svg = holder.querySelector("svg") as SVGElement;

    preview.setZoom(1.5);
    expect(svg.style.maxWidth).toBe("540px");
    preview.setZoom(1);
    expect(svg.style.maxWidth).toBe("360px");
    preview.setZoom(2);
    expect(svg.style.maxWidth).toBe("720px"); // 累積しない
  });
});
