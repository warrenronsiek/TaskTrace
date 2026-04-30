// @vitest-environment jsdom
import { describe, it, expect, beforeEach } from "vitest";

document.body.innerHTML = '<main id="app"></main>';

const { __testables__ } = await import("../src/renderers/knowledgeGraph");
const { state } = await import("../src/webviewRuntime");

const {
  linkID,
  project,
  nodeRadius,
  searchHitStrength,
  classifyRenderDelta,
  buildLinksByNodeId,
  computePrunedNodeIDs,
  computeVisibleGraph,
  computeScenePositions,
  updateDisplayedScenePositions
} = __testables__;

const indexedLinks = (links) => buildLinksByNodeId(links);

describe("linkID", () => {
  it("produces a stable key from kind/source/target", () => {
    expect(linkID({ kind: "knowledge", sourceId: "a", targetId: "b" })).toBe("knowledge:a:b");
  });

  it("is deterministic given the same inputs", () => {
    const link = { kind: "overview-activity", sourceId: "o1", targetId: "a1" };
    expect(linkID(link)).toBe(linkID(link));
  });

  it("differentiates links that differ only by kind", () => {
    expect(linkID({ kind: "file", sourceId: "a", targetId: "b" })).not.toBe(
      linkID({ kind: "knowledge", sourceId: "a", targetId: "b" })
    );
  });
});

describe("searchHitStrength", () => {
  it("returns 0 for null rank", () => {
    expect(searchHitStrength(null)).toBe(0);
  });

  it("decreases monotonically within the clamp region", () => {
    expect(searchHitStrength(0)).toBeGreaterThan(searchHitStrength(1));
  });

  it("clamps to the floor for high ranks", () => {
    expect(searchHitStrength(100)).toBeGreaterThanOrEqual(0.38);
  });
});

describe("project", () => {
  beforeEach(() => {
    state.knowledgeGraph.viewportTransform = { x: 450, y: 300, k: 1 };
  });

  it("maps the scene origin to the viewport translation", () => {
    expect(project(900, 600, 0, 0)).toEqual({ x: 450, y: 300, scale: 1 });
  });

  it("shifts x by the scaled scene x value", () => {
    expect(project(900, 600, 100, 0).x).toBe(550);
  });

  it("shifts y by the scaled scene y value", () => {
    expect(project(900, 600, 0, 100).y).toBe(400);
  });

  it("returns the current viewport scale", () => {
    state.knowledgeGraph.viewportTransform = { x: 450, y: 300, k: 2 };
    expect(project(900, 600, 100, 0).scale).toBe(2);
  });
});

describe("nodeRadius", () => {
  it("returns larger radii for community nodes than knowledge nodes", () => {
    expect(nodeRadius({ nodeType: "community", linkCount: 0 })).toBeGreaterThan(
      nodeRadius({ nodeType: "knowledge", linkCount: 0 })
    );
  });

  it("grows community radius with link count", () => {
    expect(nodeRadius({ nodeType: "community", linkCount: 4 })).toBeGreaterThan(
      nodeRadius({ nodeType: "community", linkCount: 0 })
    );
  });

  it("keeps low-link communities compact", () => {
    expect(nodeRadius({ nodeType: "community", linkCount: 0 })).toBeLessThan(20);
  });

  it("keeps high-link communities visibly larger than low-link communities", () => {
    expect(nodeRadius({ nodeType: "community", linkCount: 16 })).toBeGreaterThan(
      nodeRadius({ nodeType: "community", linkCount: 1 }) + 14
    );
  });

  it("returns a fixed radius for claim nodes", () => {
    expect(nodeRadius({ nodeType: "claim" })).toBe(5);
  });

  it("grows file radius with link count", () => {
    expect(nodeRadius({ nodeType: "file", linkCount: 10 })).toBeGreaterThan(
      nodeRadius({ nodeType: "file", linkCount: 0 })
    );
  });
});

describe("computePrunedNodeIDs", () => {
  it("renders every node when buckets are below threshold", () => {
    const nodes = [
      { id: "k1", nodeType: "knowledge", linkCount: 0 },
      { id: "k2", nodeType: "knowledge", linkCount: 0 }
    ];

    expect(computePrunedNodeIDs({
      nodes,
      links: [],
      linksByNodeId: indexedLinks([]),
      thresholds: { knowledge: 3, file: 3, activity: 3, overview: 3 }
    }).size).toBe(2);
  });

  it("hides low-connection nodes in oversized knowledge buckets", () => {
    const nodes = [
      { id: "k1", nodeType: "knowledge", linkCount: 0 },
      { id: "k2", nodeType: "knowledge", linkCount: 1 },
      { id: "k3", nodeType: "knowledge", linkCount: 2 },
      { id: "k4", nodeType: "knowledge", linkCount: 3 }
    ];

    expect([...computePrunedNodeIDs({
      nodes,
      links: [],
      linksByNodeId: indexedLinks([]),
      thresholds: { knowledge: 2, file: 3, activity: 3, overview: 3 }
    })].sort()).toEqual(["k3", "k4"]);
  });

  it("keeps file buckets independent by layer", () => {
    const nodes = [
      { id: "f1", nodeType: "file", layer: 0, linkCount: 0 },
      { id: "f2", nodeType: "file", layer: 0, linkCount: 1 },
      { id: "f3", nodeType: "file", layer: 0, linkCount: 2 },
      { id: "f4", nodeType: "file", layer: 4, linkCount: 0 }
    ];

    expect(computePrunedNodeIDs({
      nodes,
      links: [],
      linksByNodeId: indexedLinks([]),
      thresholds: { knowledge: 3, file: 2, activity: 3, overview: 3 }
    }).has("f4")).toBe(true);
  });

  it("keeps community nodes visible regardless of thresholds", () => {
    expect(computePrunedNodeIDs({
      nodes: [{ id: "c1", nodeType: "community", linkCount: 0 }],
      links: [],
      linksByNodeId: indexedLinks([]),
      thresholds: { knowledge: 1, file: 1, activity: 1, overview: 1 }
    }).has("c1")).toBe(true);
  });

  it("keeps search-hit nodes visible regardless of connection count", () => {
    const nodes = [
      { id: "k1", nodeType: "knowledge", linkCount: 0, searchHitRank: 0 },
      { id: "k2", nodeType: "knowledge", linkCount: 0 },
      { id: "k3", nodeType: "knowledge", linkCount: 0 }
    ];

    expect(computePrunedNodeIDs({
      nodes,
      links: [],
      linksByNodeId: indexedLinks([]),
      thresholds: { knowledge: 1, file: 3, activity: 3, overview: 3 }
    }).has("k1")).toBe(true);
  });

  it("reveals hidden neighbors of the selected node", () => {
    const nodes = [
      { id: "hub", nodeType: "knowledge", linkCount: 3 },
      { id: "hidden", nodeType: "knowledge", linkCount: 0 },
      { id: "other", nodeType: "knowledge", linkCount: 0 }
    ];
    const links = [{ id: "l1", kind: "knowledge", sourceId: "hub", targetId: "hidden", weight: 1 }];

    expect(computePrunedNodeIDs({
      nodes,
      links,
      linksByNodeId: indexedLinks(links),
      selectedNodeID: "hub",
      thresholds: { knowledge: 1, file: 3, activity: 3, overview: 3 }
    }).has("hidden")).toBe(true);
  });
});

describe("computeVisibleGraph", () => {
  it("filters links whose endpoints are hidden", () => {
    const nodes = [
      { id: "k1", nodeType: "knowledge", linkCount: 3 },
      { id: "k2", nodeType: "knowledge", linkCount: 0 },
      { id: "k3", nodeType: "knowledge", linkCount: 3 }
    ];
    const links = [
      { id: "l1", kind: "knowledge", sourceId: "k1", targetId: "k2", weight: 1 },
      { id: "l2", kind: "knowledge", sourceId: "k1", targetId: "k3", weight: 1 }
    ];

    expect(computeVisibleGraph({
      nodes,
      links,
      linksByNodeId: indexedLinks(links),
      thresholds: { knowledge: 1, file: 3, activity: 3, overview: 3 }
    }).links.map((link) => link.id)).toEqual(["l2"]);
  });
});

describe("classifyRenderDelta", () => {
  beforeEach(() => {
    state.knowledgeGraph.nodeLayoutKey = "n1|n2";
    state.knowledgeGraph.linkLayoutKey = "l1|l2";
    state.knowledgeGraph.viewportTransform = { x: 450, y: 300, k: 1 };
    state.knowledgeGraph.lastViewport = { x: 450, y: 300, k: 1, width: 900, height: 600 };
  });

  it("marks structure dirty when the node layout key changes", () => {
    expect(classifyRenderDelta({
      nodeLayoutKey: "n1|n2|n3",
      linkLayoutKey: "l1|l2",
      width: 900,
      height: 600
    }).structure).toBe(true);
  });

  it("marks layout dirty when the node layout key changes", () => {
    expect(classifyRenderDelta({
      nodeLayoutKey: "n1|n2|n3",
      linkLayoutKey: "l1|l2",
      width: 900,
      height: 600
    }).layout).toBe(true);
  });

  it("marks projection dirty when the node layout key changes", () => {
    expect(classifyRenderDelta({
      nodeLayoutKey: "n1|n2|n3",
      linkLayoutKey: "l1|l2",
      width: 900,
      height: 600
    }).projection).toBe(true);
  });

  it("always marks visuals dirty", () => {
    expect(classifyRenderDelta({
      nodeLayoutKey: "n1|n2",
      linkLayoutKey: "l1|l2",
      width: 900,
      height: 600
    }).visual).toBe(true);
  });

  it("marks viewport changes when the viewport translation changes", () => {
    state.knowledgeGraph.viewportTransform = { x: 492, y: 300, k: 1 };

    expect(classifyRenderDelta({
      nodeLayoutKey: "n1|n2",
      linkLayoutKey: "l1|l2",
      width: 900,
      height: 600
    }).viewportChanged).toBe(true);
  });

  it("marks projection dirty when the viewport width changes", () => {
    expect(classifyRenderDelta({
      nodeLayoutKey: "n1|n2",
      linkLayoutKey: "l1|l2",
      width: 1200,
      height: 600
    }).projection).toBe(true);
  });
});

describe("computeScenePositions", () => {
  it("preserves wide knowledge-node separation in scene coordinates", () => {
    const nodes = [
      { id: "k1", nodeType: "knowledge", communityId: "c1", layer: 2, x: -420, y: 0, radius: 10 },
      { id: "k2", nodeType: "knowledge", communityId: "c1", layer: 2, x: 420, y: 0, radius: 10 },
      { id: "cc", nodeType: "community", communityId: "c1", layer: 2, x: 0, y: 160, radius: 20 }
    ];

    computeScenePositions(nodes);

    expect(Math.hypot(
      nodes[0].sceneX - nodes[1].sceneX,
      nodes[0].sceneY - nodes[1].sceneY
    )).toBeGreaterThan(700);
  });

  it("pushes source-layer nodes outside the knowledge envelope", () => {
    const nodes = [
      { id: "k1", nodeType: "knowledge", communityId: "c1", layer: 2, x: -520, y: 0, radius: 10 },
      { id: "k2", nodeType: "knowledge", communityId: "c1", layer: 2, x: 520, y: 0, radius: 10 },
      { id: "cc", nodeType: "community", communityId: "c1", layer: 2, x: 0, y: 220, radius: 22 },
      { id: "f1", nodeType: "file", layer: 0, x: 0, y: 0, radius: 14 }
    ];

    computeScenePositions(nodes);

    const knowledgeEnvelope = nodes
      .filter((node) => node.nodeType === "knowledge" || node.nodeType === "community")
      .reduce((largestRadius, node) => (
        Math.max(largestRadius, Math.hypot(node.sceneX, node.sceneY) + node.radius)
      ), 0);
    const fileNode = nodes.find((node) => node.id === "f1");
    const fileEdgeDistance = Math.hypot(fileNode.sceneX, fileNode.sceneY) - fileNode.radius;

    expect(fileEdgeDistance).toBeGreaterThan(knowledgeEnvelope);
  });

  it("leaves orphan community nodes in place", () => {
    const nodes = [
      { id: "cc", nodeType: "community", communityId: "orphan", layer: 2, x: 50, y: 60, radius: 20 }
    ];

    computeScenePositions(nodes);

    expect({ x: nodes[0].x, y: nodes[0].y }).toEqual({ x: 50, y: 60 });
  });

  it("places claim nodes around their parent node", () => {
    const nodes = [
      { id: "k1", nodeType: "knowledge", communityId: "c1", layer: 2, x: 0, y: 0, radius: 12 },
      { id: "claim1", nodeType: "claim", parentNodeId: "k1", layer: 2, x: 0, y: 0, radius: 5 }
    ];

    computeScenePositions(nodes);

    expect(Math.hypot(nodes[1].sceneX - nodes[0].sceneX, nodes[1].sceneY - nodes[0].sceneY)).toBeGreaterThan(0);
  });
});

describe("updateDisplayedScenePositions", () => {
  it("eases displayed scene x toward the target position", () => {
    const nodes = [
      { id: "k1", sceneX: 100, sceneY: 80, displaySceneX: 0, displaySceneY: 0 }
    ];

    updateDisplayedScenePositions(nodes, { smoothPositions: true });

    expect(nodes[0].displaySceneX).toBeGreaterThan(0);
  });

  it("snaps displayed positions exactly to the target when requested", () => {
    const nodes = [
      { id: "k1", sceneX: 100, sceneY: 80, displaySceneX: 5, displaySceneY: 5 }
    ];

    updateDisplayedScenePositions(nodes, { snapPositions: true });

    expect({ x: nodes[0].displaySceneX, y: nodes[0].displaySceneY }).toEqual({ x: 100, y: 80 });
  });
});
