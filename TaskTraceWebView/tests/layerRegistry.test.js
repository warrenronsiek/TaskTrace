import { describe, it, expect, beforeEach } from "vitest";
import {
  registerLayerType,
  getLayerSpec,
  computeLayerAnchors
} from "../src/renderers/layerRegistry";

describe("layerRegistry", () => {
  beforeEach(() => {
    registerLayerType(0, {
      label: "Markdown Files",
      kind: "pane",
      anchorOverride: { x: 500, y: -250, z: 0 }
    });
    registerLayerType(1, {
      label: "Activities + Overviews",
      kind: "pane",
      anchorOverride: { x: -500, y: -250, z: 0 }
    });
    registerLayerType(2, {
      label: "Knowledge Graph",
      kind: "central"
    });
    registerLayerType(4, {
      label: "TaskTrace Ingest",
      kind: "pane",
      anchorOverride: { x: 0, y: 370, z: 0 }
    });
  });

  it("registers and retrieves a layer spec with defaults filled in", () => {
    registerLayerType(99, { label: "Test", kind: "pane" });
    const spec = getLayerSpec(99);

    expect(spec.label).toBe("Test");
    expect(spec.kind).toBe("pane");
    expect(typeof spec.radialRadius).toBe("number");
    expect(typeof spec.guideLength).toBe("number");
  });

  it("returns a default pane spec for unknown ids", () => {
    const spec = getLayerSpec(12345);
    expect(spec.kind).toBe("pane");
    expect(spec.label).toContain("12345");
  });

  it("applies anchorOverride for central layers", () => {
    const anchors = computeLayerAnchors([2]);
    expect(anchors.get(2)).toEqual({ x: 0, y: 0, z: 0 });
  });

  it("honors explicit anchorOverride for panes", () => {
    const anchors = computeLayerAnchors([0, 1, 2, 4]);
    expect(anchors.get(0)).toEqual({ x: 500, y: -250, z: 0 });
    expect(anchors.get(1)).toEqual({ x: -500, y: -250, z: 0 });
    expect(anchors.get(2)).toEqual({ x: 0, y: 0, z: 0 });
    expect(anchors.get(4)).toEqual({ x: 0, y: 370, z: 0 });
  });

  it("auto-places N=5 panes without overrides around origin on a ring", () => {
    [10, 11, 12, 13, 14].forEach((id) =>
      registerLayerType(id, { label: `P${id}`, kind: "pane" })
    );

    const anchors = computeLayerAnchors([10, 11, 12, 13, 14]);

    expect(anchors.size).toBe(5);
    const placed = [10, 11, 12, 13, 14].map((id) => anchors.get(id));
    placed.forEach((anchor) => {
      const r = Math.hypot(anchor.x, anchor.y);
      expect(r).toBeGreaterThan(400);
      expect(r).toBeLessThan(700);
    });
  });

  it("auto-places N=9 panes with distinct angular positions", () => {
    const ids = [20, 21, 22, 23, 24, 25, 26, 27, 28];
    ids.forEach((id) => registerLayerType(id, { label: `P${id}`, kind: "pane" }));

    const anchors = computeLayerAnchors(ids);
    const angles = ids.map((id) => {
      const a = anchors.get(id);
      return Math.atan2(a.y, a.x);
    });

    const uniqueAngles = new Set(angles.map((a) => a.toFixed(3)));
    expect(uniqueAngles.size).toBe(ids.length);
  });

  it("honors angularHint when provided on a pane", () => {
    registerLayerType(30, {
      label: "Hinted",
      kind: "pane",
      angularHint: 0
    });
    const anchors = computeLayerAnchors([30]);
    const anchor = anchors.get(30);
    expect(anchor.x).toBeGreaterThan(400);
    expect(Math.abs(anchor.y)).toBeLessThan(200);
  });
});
