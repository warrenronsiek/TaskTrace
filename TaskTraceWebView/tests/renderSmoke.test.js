// @vitest-environment jsdom
import { describe, it, expect, beforeEach, vi } from "vitest";

const mountAppContainer = () => {
  document.body.innerHTML = "";
  const app = document.createElement("main");
  app.id = "app";
  document.body.appendChild(app);
};

describe("renderKnowledgeGraph — jsdom smoke test", () => {
  beforeEach(() => {
    mountAppContainer();
    vi.resetModules();
    if (!window.requestAnimationFrame) {
      window.requestAnimationFrame = (cb) => setTimeout(() => cb(performance.now()), 16);
      window.cancelAnimationFrame = (id) => clearTimeout(id);
    }
  });

  it("creates the SVG scene and emits nodes for a knowledge-graph payload", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g1",
      selectedNodeId: null,
      nodes: [
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 3 },
        { id: "k2", label: "Beta", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 4 },
        { id: "k3", label: "Gamma", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 2 },
        { id: "cc1", label: "Community", nodeType: "community", layer: 2, communityId: "c1", linkCount: 5 },
        { id: "f1", label: "notes.md", nodeType: "file", layer: 0, linkCount: 1 },
        { id: "a1", label: "ActivityX", nodeType: "activity", layer: 1, linkCount: 1 }
      ],
      links: [
        { kind: "knowledge", sourceId: "k1", targetId: "k2", weight: 2 },
        { kind: "knowledge", sourceId: "k2", targetId: "k3", weight: 1 },
        { kind: "community", sourceId: "cc1", targetId: "k1", weight: 1 },
        { kind: "community", sourceId: "cc1", targetId: "k2", weight: 1 },
        { kind: "file-knowledge", sourceId: "f1", targetId: "k1", weight: 1 },
        { kind: "overview-activity", sourceId: "a1", targetId: "k2", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});

    await new Promise((r) => setTimeout(r, 50));

    const svg = document.querySelector("svg.graph-svg");
    expect(svg).not.toBeNull();

    const nodes = svg.querySelectorAll("g.k-node");
    expect(nodes.length).toBe(payload.nodes.length);

    const glowFilter = svg.querySelector("#knowledge-node-glow");
    expect(glowFilter).not.toBeNull();
    const blur = svg.querySelector("#knowledge-node-glow-blur");
    expect(blur).not.toBeNull();
  });

  it("does not render the guide layer", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g1",
      selectedNodeId: null,
      nodes: [
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 1 }
      ],
      links: []
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 30));

    expect(document.querySelector(".knowledge-guides")).toBeNull();
  });

  it("does not render an idle community halo", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g-idle-halo",
      selectedNodeId: null,
      nodes: [
        { id: "cc1", label: "Community", nodeType: "community", layer: 2, communityId: "c1", linkCount: 3 },
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 1 }
      ],
      links: [
        { kind: "community", sourceId: "cc1", targetId: "k1", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    expect(document.querySelectorAll("circle.k-community-halo").length).toBe(0);
  });

  it("does not render a community halo when a community member is a graph search hit", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g-search-halo",
      selectedNodeId: null,
      nodes: [
        { id: "cc1", label: "Community", nodeType: "community", layer: 2, communityId: "c1", linkCount: 3 },
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 1, searchHitRank: 0 }
      ],
      links: [
        { kind: "community", sourceId: "cc1", targetId: "k1", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    expect(document.querySelectorAll("circle.k-community-halo").length).toBe(0);
  });

  it("uses node glow when a community member is a graph search hit", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g-search-glow",
      selectedNodeId: null,
      nodes: [
        { id: "cc1", label: "Community", nodeType: "community", layer: 2, communityId: "c1", linkCount: 3 },
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 1, searchHitRank: 0 }
      ],
      links: [
        { kind: "community", sourceId: "cc1", targetId: "k1", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    const communityGroup = Array.from(document.querySelectorAll("g.k-node")).find((node) => node.__data__?.id === "cc1");
    expect(Number(communityGroup.querySelector("circle.k-node-glow")?.getAttribute("opacity"))).toBeGreaterThan(0);
  });

  it("does not show idle node glow", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g-idle-glow",
      selectedNodeId: null,
      nodes: [
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 1 },
        { id: "cc1", label: "Community", nodeType: "community", layer: 2, communityId: "c1", linkCount: 2 }
      ],
      links: [
        { kind: "community", sourceId: "cc1", targetId: "k1", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    expect(Array.from(document.querySelectorAll("circle.k-node-glow")).every((node) => node.getAttribute("opacity") === "0")).toBe(true);
  });

  it("uses consistent white node labels for every node type", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g-labels",
      selectedNodeId: null,
      nodes: [
        { id: "cc1", label: "Community", nodeType: "community", layer: 2, communityId: "c1", linkCount: 3 },
        { id: "k1", label: "Knowledge", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 12 },
        { id: "f1", label: "File", nodeType: "file", layer: 0, linkCount: 12 },
        { id: "o1", label: "Overview", nodeType: "overview", layer: 3, linkCount: 12 }
      ],
      links: [
        { kind: "community", sourceId: "cc1", targetId: "k1", weight: 1 },
        { kind: "file-knowledge", sourceId: "f1", targetId: "k1", weight: 1 },
        { kind: "overview-knowledge", sourceId: "o1", targetId: "k1", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    expect(Array.from(document.querySelectorAll("text.k-node-label")).every((node) => (
      node.getAttribute("fill") === "rgba(249, 249, 247, 0.94)"
        && node.getAttribute("font-size") === "10"
        && node.getAttribute("font-weight") === "600"
    ))).toBe(true);
  });

  it("does not render base edge DOM before a node is selected", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g1",
      selectedNodeId: null,
      nodes: [
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 3 },
        { id: "k2", label: "Beta", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 4 }
      ],
      links: [
        { kind: "knowledge", sourceId: "k1", targetId: "k2", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    expect(document.querySelectorAll("line.k-link").length).toBe(0);
  });

  it("renders one base edge when one adjacent link matches the selected node", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g1",
      selectedNodeId: "k1",
      nodes: [
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 3 },
        { id: "k2", label: "Beta", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 2 },
        { id: "k3", label: "Gamma", nodeType: "knowledge", layer: 2, communityId: "c2", linkCount: 1 }
      ],
      links: [
        { kind: "knowledge", sourceId: "k1", targetId: "k2", weight: 1 },
        { kind: "knowledge", sourceId: "k2", targetId: "k3", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    expect(document.querySelectorAll("line.k-link").length).toBe(1);
  });

  it("renders fewer SVG nodes than payload nodes when pruning thresholds are exceeded", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g-pruned",
      selectedNodeId: null,
      pruningThresholds: { knowledge: 1, file: 10, activity: 10, overview: 10 },
      nodes: [
        { id: "hub", label: "Hub", nodeType: "knowledge", layer: 2, linkCount: 3 },
        { id: "low1", label: "Low 1", nodeType: "knowledge", layer: 2, linkCount: 0 },
        { id: "low2", label: "Low 2", nodeType: "knowledge", layer: 2, linkCount: 0 }
      ],
      links: []
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    expect(document.querySelectorAll("g.k-node").length).toBeLessThan(payload.nodes.length);
  });

  it("reveals a pruned neighbor when its visible neighbor is selected", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g-reveal",
      selectedNodeId: null,
      pruningThresholds: { knowledge: 1, file: 10, activity: 10, overview: 10 },
      nodes: [
        { id: "hub", label: "Hub", nodeType: "knowledge", layer: 2, linkCount: 3 },
        { id: "hidden", label: "Hidden", nodeType: "knowledge", layer: 2, linkCount: 0 },
        { id: "other", label: "Other", nodeType: "knowledge", layer: 2, linkCount: 0 }
      ],
      links: [
        { kind: "knowledge", sourceId: "hub", targetId: "hidden", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    document.querySelector("g.k-node")?.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
    await new Promise((r) => setTimeout(r, 50));

    expect(document.querySelectorAll("g.k-node").length).toBe(2);
  });

  it("fades a revealed pruned neighbor out after selection is cleared", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g-clear-pruned",
      selectedNodeId: null,
      pruningThresholds: { knowledge: 1, file: 10, activity: 10, overview: 10 },
      nodes: [
        { id: "hub", label: "Hub", nodeType: "knowledge", layer: 2, linkCount: 3 },
        { id: "hidden", label: "Hidden", nodeType: "knowledge", layer: 2, linkCount: 0 },
        { id: "other", label: "Other", nodeType: "knowledge", layer: 2, linkCount: 0 }
      ],
      links: [
        { kind: "knowledge", sourceId: "hub", targetId: "hidden", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));
    document.querySelector("g.k-node")?.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
    await new Promise((r) => setTimeout(r, 50));

    document.querySelector("svg.graph-svg")?.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    await new Promise((r) => setTimeout(r, 380));

    expect(document.querySelectorAll("g.k-node").length).toBe(1);
  });

  it("renders an empty graph without throwing", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    state.payload = { kind: "knowledge-graph", graph: { graphId: "empty", nodes: [], links: [] } };
    expect(() =>
      renderKnowledgeGraph({ graphId: "empty", nodes: [], links: [] }, () => {})
    ).not.toThrow();

    const svg = document.querySelector("svg.graph-svg");
    expect(svg).not.toBeNull();
  });

  it("updating the graph with added nodes keeps the cached svg root", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const initial = {
      graphId: "g1",
      nodes: [
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, linkCount: 1 },
        { id: "k2", label: "Beta", nodeType: "knowledge", layer: 2, linkCount: 1 }
      ],
      links: [{ kind: "knowledge", sourceId: "k1", targetId: "k2", weight: 1 }]
    };

    state.payload = { kind: "knowledge-graph", graph: initial };
    renderKnowledgeGraph(initial, () => {});
    await new Promise((r) => setTimeout(r, 30));

    const svgFirst = document.querySelector("svg.graph-svg");

    const updated = {
      ...initial,
      nodes: [...initial.nodes, { id: "k3", label: "Gamma", nodeType: "knowledge", layer: 2, linkCount: 0 }]
    };
    state.payload = { kind: "knowledge-graph", graph: updated };
    renderKnowledgeGraph(updated, () => {});
    await new Promise((r) => setTimeout(r, 30));

    const svgSecond = document.querySelector("svg.graph-svg");
    expect(svgSecond).toBe(svgFirst);

    const nodes = svgSecond.querySelectorAll("g.k-node");
    expect(nodes.length).toBe(3);
  });

  it("clicking a node sets state.selectedNodeID and keeps the svg mounted", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g1",
      nodes: [
        { id: "k1", label: "A", nodeType: "knowledge", layer: 2, linkCount: 1 },
        { id: "k2", label: "B", nodeType: "knowledge", layer: 2, linkCount: 1 }
      ],
      links: []
    };
    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 30));

    const allNodes = document.querySelectorAll("g.k-node");
    expect(allNodes.length).toBe(2);
    const firstNode = allNodes[0];

    const event = new window.MouseEvent("click", { bubbles: true, cancelable: true });
    firstNode.dispatchEvent(event);

    expect(["k1", "k2"]).toContain(state.selectedNodeID);
    expect(document.querySelector("svg.graph-svg")).not.toBeNull();
  });

  it("viewport changes update the scene transform", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g1",
      nodes: [
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 2 },
        { id: "k2", label: "Beta", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 2 },
        { id: "cc1", label: "Community", nodeType: "community", layer: 2, communityId: "c1", linkCount: 2 }
      ],
      links: [
        { kind: "knowledge", sourceId: "k1", targetId: "k2", weight: 1 },
        { kind: "community", sourceId: "cc1", targetId: "k1", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    const firstTransform = document.querySelector("g.knowledge-scene")?.getAttribute("transform");

    state.knowledgeGraph.viewportTransform = {
      ...state.knowledgeGraph.viewportTransform,
      x: state.knowledgeGraph.viewportTransform.x + 42,
      y: state.knowledgeGraph.viewportTransform.y - 28
    };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 30));

    const secondTransform = document.querySelector("g.knowledge-scene")?.getAttribute("transform");
    expect(secondTransform).not.toBe(firstTransform);
  });

  it("keeps lower-link knowledge nodes closer to their community core", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g-community-core",
      nodes: [
        { id: "cc1", label: "Community", nodeType: "community", layer: 2, communityId: "c1", linkCount: 8 },
        { id: "low", label: "Low", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 0 },
        { id: "high", label: "High", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 8 }
      ],
      links: [
        { kind: "community", sourceId: "cc1", targetId: "low", weight: 1 },
        { kind: "community", sourceId: "cc1", targetId: "high", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    const communityNode = state.knowledgeGraph.nodesById.get("cc1");
    const lowNode = state.knowledgeGraph.nodesById.get("low");
    const highNode = state.knowledgeGraph.nodesById.get("high");
    const lowDistance = Math.hypot(lowNode.sceneX - communityNode.sceneX, lowNode.sceneY - communityNode.sceneY);
    const highDistance = Math.hypot(highNode.sceneX - communityNode.sceneX, highNode.sceneY - communityNode.sceneY);

    expect(lowDistance).toBeLessThan(highDistance);
  });

  it("keeps community members closest to their own community core", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g-community-members",
      nodes: [
        { id: "cc1", label: "Community 1", nodeType: "community", layer: 2, communityId: "c1", linkCount: 4 },
        { id: "cc2", label: "Community 2", nodeType: "community", layer: 2, communityId: "c2", linkCount: 4 },
        { id: "c1a", label: "A", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 1 },
        { id: "c1b", label: "B", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 1 },
        { id: "c2a", label: "C", nodeType: "knowledge", layer: 2, communityId: "c2", linkCount: 1 },
        { id: "c2b", label: "D", nodeType: "knowledge", layer: 2, communityId: "c2", linkCount: 1 }
      ],
      links: [
        { kind: "community", sourceId: "cc1", targetId: "c1a", weight: 1 },
        { kind: "community", sourceId: "cc1", targetId: "c1b", weight: 1 },
        { kind: "community", sourceId: "cc2", targetId: "c2a", weight: 1 },
        { kind: "community", sourceId: "cc2", targetId: "c2b", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    const node = (id) => state.knowledgeGraph.nodesById.get(id);
    const distance = (left, right) => Math.hypot(left.sceneX - right.sceneX, left.sceneY - right.sceneY);
    const ownDistances = [
      distance(node("c1a"), node("cc1")),
      distance(node("c1b"), node("cc1")),
      distance(node("c2a"), node("cc2")),
      distance(node("c2b"), node("cc2"))
    ];
    const crossDistances = [
      distance(node("c1a"), node("cc2")),
      distance(node("c1b"), node("cc2")),
      distance(node("c2a"), node("cc1")),
      distance(node("c2b"), node("cc1"))
    ];

    expect(Math.max(...ownDistances)).toBeLessThan(Math.min(...crossDistances));
  });

  it("spreads independent knowledge nodes instead of collapsing them into the center", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g-orphan-spread",
      nodes: [
        { id: "cc1", label: "Community 1", nodeType: "community", layer: 2, communityId: "c1", linkCount: 2 },
        { id: "cc2", label: "Community 2", nodeType: "community", layer: 2, communityId: "c2", linkCount: 2 },
        { id: "c1a", label: "A", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 1 },
        { id: "c2a", label: "B", nodeType: "knowledge", layer: 2, communityId: "c2", linkCount: 1 },
        { id: "o1", label: "One", nodeType: "knowledge", layer: 2, communityId: null, linkCount: 1 },
        { id: "o2", label: "Two", nodeType: "knowledge", layer: 2, communityId: null, linkCount: 1 },
        { id: "o3", label: "Three", nodeType: "knowledge", layer: 2, communityId: null, linkCount: 1 },
        { id: "o4", label: "Four", nodeType: "knowledge", layer: 2, communityId: null, linkCount: 1 }
      ],
      links: [
        { kind: "community", sourceId: "cc1", targetId: "c1a", weight: 1 },
        { kind: "community", sourceId: "cc2", targetId: "c2a", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    const orphanNodes = ["o1", "o2", "o3", "o4"].map((id) => state.knowledgeGraph.nodesById.get(id));
    const spread = orphanNodes.reduce((largestDistance, leftNode, leftIndex) => (
      Math.max(
        largestDistance,
        ...orphanNodes.slice(leftIndex + 1).map((rightNode) => (
          Math.hypot(leftNode.sceneX - rightNode.sceneX, leftNode.sceneY - rightNode.sceneY)
        ))
      )
    ), 0);

    expect(spread).toBeGreaterThan(80);
  });

  it("positions follow-up selected claims around their parent knowledge node", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const initialPayload = {
      graphId: "g-selected-claims",
      selectedNodeId: "k1",
      nodes: [
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 2 },
        { id: "k2", label: "Beta", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 1 }
      ],
      links: [
        { kind: "knowledge", sourceId: "k1", targetId: "k2", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: initialPayload };
    renderKnowledgeGraph(initialPayload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    const updatedPayload = {
      ...initialPayload,
      nodes: [
        ...initialPayload.nodes,
        { id: "claim1", label: "Claim 1", nodeType: "claim", layer: 2, parentNodeId: "k1", linkCount: 1 },
        { id: "claim2", label: "Claim 2", nodeType: "claim", layer: 2, parentNodeId: "k1", linkCount: 1 }
      ],
      links: [
        ...initialPayload.links,
        { kind: "claim", sourceId: "k1", targetId: "claim1", weight: 1 },
        { kind: "claim", sourceId: "k1", targetId: "claim2", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: updatedPayload };
    renderKnowledgeGraph(updatedPayload, () => {});
    await new Promise((r) => setTimeout(r, 80));

    const parentNode = state.knowledgeGraph.nodesById.get("k1");
    const claimNode = state.knowledgeGraph.nodesById.get("claim1");
    expect(Math.hypot(claimNode.displaySceneX - parentNode.displaySceneX, claimNode.displaySceneY - parentNode.displaySceneY)).toBeGreaterThan(40);
  });

  it("attaches follow-up selected claim links to their parent knowledge node", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const initialPayload = {
      graphId: "g-selected-claim-links",
      selectedNodeId: "k1",
      nodes: [
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 2 },
        { id: "k2", label: "Beta", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 1 }
      ],
      links: [
        { kind: "knowledge", sourceId: "k1", targetId: "k2", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: initialPayload };
    renderKnowledgeGraph(initialPayload, () => {});
    await new Promise((r) => setTimeout(r, 50));

    const updatedPayload = {
      ...initialPayload,
      nodes: [
        ...initialPayload.nodes,
        { id: "claim1", label: "Claim 1", nodeType: "claim", layer: 2, parentNodeId: "k1", linkCount: 1 }
      ],
      links: [
        ...initialPayload.links,
        { kind: "claim", sourceId: "k1", targetId: "claim1", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: updatedPayload };
    renderKnowledgeGraph(updatedPayload, () => {});
    await new Promise((r) => setTimeout(r, 80));

    const parentNode = state.knowledgeGraph.nodesById.get("k1");
    const claimLink = Array.from(document.querySelectorAll("line.k-link")).find((node) => node.__data__?.kind === "claim");
    expect({
      x1: Number(claimLink.getAttribute("x1")),
      y1: Number(claimLink.getAttribute("y1"))
    }).toEqual({
      x1: parentNode.displaySceneX,
      y1: parentNode.displaySceneY
    });
  });

  it("renders only overlay edges attached to the selected node", async () => {
    const { renderKnowledgeGraph, updateOverlayLinks } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g1",
      selectedNodeId: "k1",
      nodes: [
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 2 },
        { id: "k2", label: "Beta", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 2 },
        { id: "k3", label: "Gamma", nodeType: "knowledge", layer: 2, communityId: "c2", linkCount: 2 },
        { id: "a1", label: "Activity A", nodeType: "activity", layer: 1, linkCount: 1 },
        { id: "a2", label: "Activity B", nodeType: "activity", layer: 1, linkCount: 1 }
      ],
      links: []
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    updateOverlayLinks([
      { kind: "activity-knowledge", sourceId: "a1", targetId: "k1", weight: 1 },
      { kind: "activity-knowledge", sourceId: "a2", targetId: "k3", weight: 1 }
    ]);
    await new Promise((r) => setTimeout(r, 50));

    expect(document.querySelectorAll(".overlay-links line").length).toBe(1);
  });

  it("clears overlay edges immediately when the selection is cleared", async () => {
    const { renderKnowledgeGraph, updateOverlayLinks } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g1",
      selectedNodeId: "k1",
      nodes: [
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 1 },
        { id: "a1", label: "Activity A", nodeType: "activity", layer: 1, linkCount: 1 }
      ],
      links: []
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    updateOverlayLinks([
      { kind: "activity-knowledge", sourceId: "a1", targetId: "k1", weight: 1 }
    ]);
    await new Promise((r) => setTimeout(r, 30));

    document.querySelector("svg.graph-svg")?.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

    expect(document.querySelectorAll(".overlay-links line").length).toBe(0);
  });

  it("clears base edges immediately when the selection is cleared", async () => {
    const { renderKnowledgeGraph } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    const payload = {
      graphId: "g1",
      selectedNodeId: "k1",
      nodes: [
        { id: "k1", label: "Alpha", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 1 },
        { id: "k2", label: "Beta", nodeType: "knowledge", layer: 2, communityId: "c1", linkCount: 1 }
      ],
      links: [
        { kind: "knowledge", sourceId: "k1", targetId: "k2", weight: 1 }
      ]
    };

    state.payload = { kind: "knowledge-graph", graph: payload };
    renderKnowledgeGraph(payload, () => {});
    await new Promise((r) => setTimeout(r, 30));

    document.querySelector("svg.graph-svg")?.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

    expect(document.querySelectorAll("line.k-link").length).toBe(0);
  });
});

describe("knowledgeGraph helpers", () => {
  beforeEach(() => {
    mountAppContainer();
    vi.resetModules();
  });

  it("indexes links for both endpoints", async () => {
    const { __testables__ } = await import("../src/renderers/knowledgeGraph");

    expect(__testables__.buildLinksByNodeId([
      { id: "l1", sourceId: "a", targetId: "b" }
    ]).get("b")?.[0]?.id).toBe("l1");
  });

  it("returns no visible base links without a selected node", async () => {
    const { __testables__ } = await import("../src/renderers/knowledgeGraph");

    expect(__testables__.visibleBaseLinks(new Map([["a", [{ id: "l1" }]]]), null)).toEqual([]);
  });

  it("filters overlay links to the selected node", async () => {
    const { __testables__ } = await import("../src/renderers/knowledgeGraph");
    const { state } = await import("../src/webviewRuntime");

    state.selectedNodeID = "k1";

    expect(__testables__.visibleOverlayLinks([
      { kind: "activity-knowledge", sourceId: "a1", targetId: "k1" },
      { kind: "activity-knowledge", sourceId: "a2", targetId: "k2" }
    ])).toEqual([
      { kind: "activity-knowledge", sourceId: "a1", targetId: "k1" }
    ]);
  });
});
