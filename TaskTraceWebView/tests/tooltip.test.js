// @vitest-environment jsdom
import { describe, it, expect, beforeEach, vi } from "vitest";

const mountAppContainer = () => {
  document.body.innerHTML = "";
  const app = document.createElement("main");
  app.id = "app";
  document.body.appendChild(app);
};

describe("tooltip state machine", () => {
  beforeEach(() => {
    mountAppContainer();
    vi.resetModules();
    if (!window.requestAnimationFrame) {
      window.requestAnimationFrame = (cb) => setTimeout(() => cb(performance.now()), 16);
      window.cancelAnimationFrame = (id) => clearTimeout(id);
    }
  });

  it("setTooltipHTML inserts markup synchronously and schedules is-visible", async () => {
    const { setTooltipHTML, tooltip } = await import("../src/webviewRuntime");

    setTooltipHTML("<span>hello</span>", 10, 20);

    expect(tooltip.innerHTML).toContain("hello");
    expect(tooltip.style.left).toBe("10px");
    expect(tooltip.style.top).toBe("20px");

    await new Promise((r) => setTimeout(r, 20));
    expect(tooltip.classList.contains("is-visible")).toBe(true);
  });

  it("a second call swaps content synchronously while visible", async () => {
    const { setTooltipHTML, tooltip } = await import("../src/webviewRuntime");

    setTooltipHTML("<span>first</span>", 10, 20);
    await new Promise((r) => setTimeout(r, 20));
    expect(tooltip.classList.contains("is-visible")).toBe(true);

    setTooltipHTML("<span>second</span>", 30, 40);

    expect(tooltip.innerHTML).toContain("second");
    expect(tooltip.style.left).toBe("30px");
  });

  it("hideTooltip removes is-visible and keeps markup until opacity transitionend", async () => {
    const { setTooltipHTML, hideTooltip, tooltip } = await import("../src/webviewRuntime");

    setTooltipHTML("<span>hello</span>", 10, 20);
    await new Promise((r) => setTimeout(r, 20));
    expect(tooltip.classList.contains("is-visible")).toBe(true);

    hideTooltip();
    expect(tooltip.classList.contains("is-visible")).toBe(false);
    expect(tooltip.innerHTML).not.toBe("");

    tooltip.dispatchEvent(new window.TransitionEvent("transitionend", { propertyName: "opacity" }));
    expect(tooltip.innerHTML).toBe("");
  });

  it("hideTooltip is safe when already hidden", async () => {
    const { hideTooltip, tooltip } = await import("../src/webviewRuntime");
    expect(() => hideTooltip()).not.toThrow();
    expect(tooltip.classList.contains("is-visible")).toBe(false);
  });
});
