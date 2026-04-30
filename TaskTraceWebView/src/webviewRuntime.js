import * as d3 from "d3";

export const root = document.getElementById("app");
export const shell = document.createElement("section");
export const tooltip = document.createElement("aside");

shell.className = "graph-shell";
tooltip.className = "graph-tooltip";
shell.appendChild(tooltip);
root.replaceChildren(shell);

export const state = {
  payload: { kind: "search-results-graph", results: [] },
  previousSearchResults: [],
  previousSearchLayoutByNodeID: new Map(),
  searchTreemapLeafFrames: [],
  searchTreemapTransitionEndsAt: 0,
  searchLastHoverChangeAt: 0,
  knowledgeGraph: {
    graphId: null,
    sourceNodes: null,
    sourceLinks: null,
    sourceSelectedNodeId: null,
    resolvedSelectedNodeID: null,
    sourcePruningThresholdKey: null,
    nodeLayoutKey: null,
    linkLayoutKey: null,
    visibleBaseLinkKey: null,
    allNodesById: new Map(),
    allLinksById: new Map(),
    allLinksByNodeId: new Map(),
    nodesById: new Map(),
    linksById: new Map(),
    linksByNodeId: new Map(),
    projectedNodesById: new Map(),
    allNodes: [],
    allLinks: [],
    nodes: [],
    links: [],
    visibleNodeIDs: new Set(),
    pruningThresholds: null,
    svgRoot: null,
    layerGroups: null,
    zoomBehavior: null,
    viewportTransform: {
      x: 0,
      y: 0,
      k: 1
    },
    viewportInitialized: false,
    lastViewport: null,
    width: 0,
    height: 0,
    runningSimHandle: null,
    layoutRunID: 0
  },
  selectedNodeID: null,
  hoveredNodeID: null,
  overlayLinks: [],
  renderedTreeIDs: new Set(),
  scheduledRenderFrameID: null,
  pendingRenderPayload: null,
  renderDispatcher: null
};

export const normalizedPayload = (payload) => {
  if (payload?.kind === "knowledge-graph") {
    return {
      kind: "knowledge-graph",
      graph: {
        graphId: payload?.graph?.graphId ?? "knowledge-empty",
        nodes: Array.isArray(payload?.graph?.nodes) ? payload.graph.nodes : [],
        links: Array.isArray(payload?.graph?.links) ? payload.graph.links : [],
        selectedNodeId: payload?.graph?.selectedNodeId ?? null,
        pruningThresholds: payload?.graph?.pruningThresholds ?? null
      }
    };
  }

  return {
    kind: "search-results-graph",
    results: Array.isArray(payload)
      ? payload
      : Array.isArray(payload?.results)
        ? payload.results
        : []
  };
};

export const createSVG = (width, height) => d3.create("svg")
  .attr("viewBox", `0 0 ${width} ${height}`)
  .attr("width", "100%")
  .attr("height", "100%")
  .attr("class", "graph-svg");

let pendingHideTransitionListener = null;

const cancelPendingHide = () => {
  if (pendingHideTransitionListener) {
    tooltip.removeEventListener("transitionend", pendingHideTransitionListener);
    pendingHideTransitionListener = null;
  }
};

export const setTooltipHTML = (html, left, top) => {
  cancelPendingHide();
  const nextHTML = `<div class="tooltip-card">${html}</div>`;
  tooltip.style.left = `${left}px`;
  tooltip.style.top = `${top}px`;

  const wasVisible = tooltip.classList.contains("is-visible");
  const contentChanged = tooltip.innerHTML !== nextHTML;

  if (!contentChanged) {
    if (!wasVisible) {
      requestAnimationFrame(() => tooltip.classList.add("is-visible"));
    }
    return;
  }

  if (wasVisible) {
    tooltip.classList.add("is-swapping");
    tooltip.innerHTML = nextHTML;
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        tooltip.classList.remove("is-swapping");
      });
    });
    return;
  }

  tooltip.innerHTML = nextHTML;
  requestAnimationFrame(() => tooltip.classList.add("is-visible"));
};

export const hideTooltip = () => {
  cancelPendingHide();

  if (!tooltip.classList.contains("is-visible")) {
    tooltip.innerHTML = "";
    return;
  }

  tooltip.classList.remove("is-swapping");
  tooltip.classList.remove("is-visible");

  const listener = (event) => {
    if (event.propertyName !== "opacity") {
      return;
    }
    tooltip.removeEventListener("transitionend", listener);
    pendingHideTransitionListener = null;
    if (!tooltip.classList.contains("is-visible")) {
      tooltip.innerHTML = "";
    }
  };
  pendingHideTransitionListener = listener;
  tooltip.addEventListener("transitionend", listener);
};

export const replaceShell = (node) => {
  shell.replaceChildren(node, tooltip);
};

export const notifyNodeSelection = (nodeID) => {
  try {
    window.webkit?.messageHandlers?.taskTraceGraphSelection?.postMessage({ nodeId: nodeID });
  } catch (_error) {
  }
};

export const configureRenderDispatcher = (dispatcher) => {
  state.renderDispatcher = dispatcher;
};

export const scheduleRender = (payload = state.payload) => {
  state.pendingRenderPayload = payload;

  if (state.scheduledRenderFrameID != null) {
    return;
  }

  state.scheduledRenderFrameID = window.requestAnimationFrame(() => {
    const nextPayload = state.pendingRenderPayload ?? state.payload;
    state.pendingRenderPayload = null;
    state.scheduledRenderFrameID = null;
    state.renderDispatcher?.(nextPayload);
  });
};
