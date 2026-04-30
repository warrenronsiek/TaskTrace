import {
  configureRenderDispatcher,
  normalizedPayload,
  scheduleRender,
  state
} from "./webviewRuntime";
import { renderSearchResultsGraph } from "./renderers/searchResultsGraph";
import { renderKnowledgeGraph, updateOverlayLinks, registerLayerType } from "./renderers/knowledgeGraph";
import { maybeStartKnowledgeGraphBenchmark, runKnowledgeGraphBenchmark } from "./benchmarks/knowledgeGraphBenchmark";

const renderNow = (payload) => {
  const nextPayload = normalizedPayload(payload);

  if (state.payload.kind !== nextPayload.kind) {
    state.selectedNodeID = null;
    state.hoveredNodeID = null;
    state.renderedTreeIDs = new Set();
    state.previousSearchResults = [];
    state.previousSearchLayoutByNodeID = new Map();
    state.searchTreemapLeafFrames = [];
    state.searchTreemapTransitionEndsAt = 0;
    state.searchLastHoverChangeAt = 0;
    if (state.knowledgeGraph.scheduledProjectionFrameID != null) {
      cancelAnimationFrame(state.knowledgeGraph.scheduledProjectionFrameID);
    }
    if (state.knowledgeGraph.runningSimHandle != null) {
      cancelAnimationFrame(state.knowledgeGraph.runningSimHandle);
    }
    if (state.knowledgeGraph.interactionSettleTimeoutID != null) {
      clearTimeout(state.knowledgeGraph.interactionSettleTimeoutID);
    }
    state.knowledgeGraph.graphId = null;
    state.knowledgeGraph.sourceNodes = null;
    state.knowledgeGraph.sourceLinks = null;
    state.knowledgeGraph.sourceSelectedNodeId = null;
    state.knowledgeGraph.resolvedSelectedNodeID = null;
    state.knowledgeGraph.sourcePruningThresholdKey = null;
    state.knowledgeGraph.nodeLayoutKey = null;
    state.knowledgeGraph.linkLayoutKey = null;
    state.knowledgeGraph.visibleBaseLinkKey = null;
    state.knowledgeGraph.allNodesById = new Map();
    state.knowledgeGraph.allLinksById = new Map();
    state.knowledgeGraph.allLinksByNodeId = new Map();
    state.knowledgeGraph.nodesById = new Map();
    state.knowledgeGraph.linksById = new Map();
    state.knowledgeGraph.linksByNodeId = new Map();
    state.knowledgeGraph.projectedNodesById = new Map();
    state.knowledgeGraph.allNodes = [];
    state.knowledgeGraph.allLinks = [];
    state.knowledgeGraph.nodes = [];
    state.knowledgeGraph.links = [];
    state.knowledgeGraph.visibleNodeIDs = new Set();
    state.knowledgeGraph.pruningThresholds = null;
    state.knowledgeGraph.lastCamera = null;
    state.knowledgeGraph.layoutRunID = 0;
    state.knowledgeGraph.runningSimHandle = null;
    state.knowledgeGraph.scheduledProjectionFrameID = null;
    state.knowledgeGraph.pendingProjectionOptions = null;
    state.knowledgeGraph.interactionSettleTimeoutID = null;
  }

  state.payload = nextPayload;

  switch (nextPayload.kind) {
  case "knowledge-graph":
    renderKnowledgeGraph(nextPayload.graph, render);
    return
  case "search-results-graph":
  default:
    renderSearchResultsGraph(nextPayload.results, render);
  }
};

const render = (payload) => {
  scheduleRender(payload);
};

configureRenderDispatcher(renderNow);

window.TaskTraceWebView = { render, updateOverlayLinks, registerLayerType, runKnowledgeGraphBenchmark };
window.addEventListener("resize", () => {
  scheduleRender(state.payload);
});

scheduleRender({ kind: "search-results-graph", results: [] });
maybeStartKnowledgeGraphBenchmark();
