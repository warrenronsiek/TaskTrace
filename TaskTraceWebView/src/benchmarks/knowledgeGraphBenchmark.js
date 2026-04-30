import { scheduleRender, state } from "../webviewRuntime";

const DEFAULT_BENCHMARK_CONFIG = Object.freeze({
  seed: 7,
  knowledgeNodes: 1200,
  communities: 48,
  files: 180,
  overviews: 36,
  activities: 240,
  knowledgeEdges: 7200,
  fileLinksPerFile: 3,
  knowledgeThreshold: 450,
  fileThreshold: 125,
  activityThreshold: 150,
  overviewThreshold: 60,
  panDurationMs: 5000,
  settleFrames: 2,
  selection: "none"
});

const BENCHMARK_PANEL_ID = "tasktrace-knowledge-benchmark-panel";
const BENCHMARK_REPORT_ID = "tasktrace-knowledge-benchmark-report";

const nextFrame = () => new Promise((resolve) => requestAnimationFrame(resolve));

const percentile = (sortedValues, fraction) => {
  if (sortedValues.length === 0) {
    return 0;
  }

  const scaledIndex = (sortedValues.length - 1) * fraction;
  const lowerIndex = Math.floor(scaledIndex);
  const upperIndex = Math.ceil(scaledIndex);

  if (lowerIndex === upperIndex) {
    return sortedValues[lowerIndex];
  }

  const weight = scaledIndex - lowerIndex;
  return sortedValues[lowerIndex] + ((sortedValues[upperIndex] - sortedValues[lowerIndex]) * weight);
};

const createPRNG = (seed) => {
  let current = seed >>> 0;

  return () => {
    current += 0x6D2B79F5;
    let value = Math.imul(current ^ (current >>> 15), current | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
};

const parseIntegerParam = (params, key, fallback) => {
  const rawValue = params.get(key);
  const parsed = rawValue == null ? Number.NaN : Number.parseInt(rawValue, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
};

const parseSelectionParam = (params) => {
  const rawValue = params.get("selection");
  return rawValue === "densest" ? "densest" : "none";
};

const benchmarkConfigFromURL = () => {
  const params = new URLSearchParams(window.location.search);

  return {
    seed: parseIntegerParam(params, "seed", DEFAULT_BENCHMARK_CONFIG.seed),
    knowledgeNodes: parseIntegerParam(params, "knowledgeNodes", DEFAULT_BENCHMARK_CONFIG.knowledgeNodes),
    communities: parseIntegerParam(params, "communities", DEFAULT_BENCHMARK_CONFIG.communities),
    files: parseIntegerParam(params, "files", DEFAULT_BENCHMARK_CONFIG.files),
    overviews: parseIntegerParam(params, "overviews", DEFAULT_BENCHMARK_CONFIG.overviews),
    activities: parseIntegerParam(params, "activities", DEFAULT_BENCHMARK_CONFIG.activities),
    knowledgeEdges: parseIntegerParam(params, "knowledgeEdges", DEFAULT_BENCHMARK_CONFIG.knowledgeEdges),
    fileLinksPerFile: parseIntegerParam(params, "fileLinksPerFile", DEFAULT_BENCHMARK_CONFIG.fileLinksPerFile),
    knowledgeThreshold: parseIntegerParam(params, "knowledgeThreshold", DEFAULT_BENCHMARK_CONFIG.knowledgeThreshold),
    fileThreshold: parseIntegerParam(params, "fileThreshold", DEFAULT_BENCHMARK_CONFIG.fileThreshold),
    activityThreshold: parseIntegerParam(params, "activityThreshold", DEFAULT_BENCHMARK_CONFIG.activityThreshold),
    overviewThreshold: parseIntegerParam(params, "overviewThreshold", DEFAULT_BENCHMARK_CONFIG.overviewThreshold),
    panDurationMs: parseIntegerParam(params, "panDurationMs", DEFAULT_BENCHMARK_CONFIG.panDurationMs),
    settleFrames: parseIntegerParam(params, "settleFrames", DEFAULT_BENCHMARK_CONFIG.settleFrames),
    selection: parseSelectionParam(params)
  };
};

const syntheticKnowledgeGraphPayload = (partialConfig = {}) => {
  const config = { ...DEFAULT_BENCHMARK_CONFIG, ...partialConfig };
  const nextRandom = createPRNG(config.seed);
  const overviewNodes = Array.from({ length: config.overviews }, (_, index) => ({
    id: `knowledge-overview:bench-${index}`,
    label: `Overview ${index + 1}`,
    detail: "Synthetic benchmark overview",
    nodeType: "overview",
    layer: 1,
    communityId: null,
    kind: "overview",
    sourcePath: null
  }));
  const activityNodes = Array.from({ length: config.activities }, (_, index) => ({
    id: `knowledge-activity:bench-${index}`,
    label: `Activity ${index + 1}`,
    detail: "Synthetic benchmark activity",
    nodeType: "activity",
    layer: 1,
    communityId: null,
    kind: "activity",
    sourcePath: null,
    parentNodeId: overviewNodes[index % Math.max(overviewNodes.length, 1)]?.id ?? null
  }));
  const fileNodes = Array.from({ length: config.files }, (_, index) => ({
    id: `knowledge-file:bench-${index}`,
    label: `Source ${index + 1}.md`,
    detail: "Synthetic benchmark file",
    nodeType: "file",
    layer: index % 3 === 0 ? 4 : 0,
    communityId: null,
    kind: "file",
    sourcePath: `Synthetic/Source-${index + 1}.md`
  }));
  const communityNodes = Array.from({ length: config.communities }, (_, index) => ({
    id: `knowledge-community:bench-${index}`,
    label: `Community ${index + 1}`,
    detail: "Synthetic benchmark community",
    nodeType: "community",
    layer: 2,
    communityId: `bench-${index}`,
    kind: "community",
    sourcePath: null
  }));
  const knowledgeNodes = Array.from({ length: config.knowledgeNodes }, (_, index) => {
    const communityID = communityNodes[index % Math.max(communityNodes.length, 1)]?.communityId ?? null;
    return {
      id: `knowledge-node:bench-${index}`,
      label: `Concept ${index + 1}`,
      detail: "Synthetic benchmark concept",
      nodeType: "knowledge",
      layer: 2,
      communityId: communityID,
      kind: "concept",
      sourcePath: fileNodes[index % Math.max(fileNodes.length, 1)]?.sourcePath ?? null
    };
  });
  const knowledgeNodesByCommunityID = knowledgeNodes.reduce((partial, node) => {
    if (node.communityId == null) {
      return partial;
    }

    partial[node.communityId] = partial[node.communityId] ?? [];
    partial[node.communityId].push(node);
    return partial;
  }, {});
  const overviewActivityLinks = activityNodes.map((activityNode, index) => ({
    kind: "overview-activity",
    sourceId: overviewNodes[index % Math.max(overviewNodes.length, 1)]?.id ?? activityNode.parentNodeId,
    targetId: activityNode.id,
    weight: 1
  }));
  const communityLinks = knowledgeNodes
    .filter((node) => node.communityId != null)
    .map((node) => ({
      kind: "community",
      sourceId: `knowledge-community:${node.communityId}`,
      targetId: node.id,
      weight: 1
    }));
  const fileKnowledgeLinks = fileNodes.flatMap((fileNode, fileIndex) => (
    Array.from({ length: config.fileLinksPerFile }, (_, offset) => {
      const knowledgeIndex = (fileIndex * config.fileLinksPerFile + offset) % Math.max(knowledgeNodes.length, 1);
      return {
        kind: "file-knowledge",
        sourceId: fileNode.id,
        targetId: knowledgeNodes[knowledgeIndex]?.id,
        weight: 1
      };
    })
  ));
  const knowledgeEdgeIDs = new Set();
  const knowledgeLinks = [];

  while (knowledgeLinks.length < config.knowledgeEdges && knowledgeNodes.length > 1) {
    const sourceIndex = Math.floor(nextRandom() * knowledgeNodes.length);
    const sourceNode = knowledgeNodes[sourceIndex];
    const withinCommunity = nextRandom() < 0.78;
    const communityPool = withinCommunity
      ? knowledgeNodesByCommunityID[sourceNode.communityId] ?? []
      : knowledgeNodes;
    const targetNode = communityPool[Math.floor(nextRandom() * communityPool.length)];

    if (!targetNode || targetNode.id === sourceNode.id) {
      continue;
    }

    const orderedIDs = [sourceNode.id, targetNode.id].sort();
    const edgeID = orderedIDs.join("|");

    if (knowledgeEdgeIDs.has(edgeID)) {
      continue;
    }

    knowledgeEdgeIDs.add(edgeID);
    knowledgeLinks.push({
      kind: "knowledge",
      sourceId: sourceNode.id,
      targetId: targetNode.id,
      weight: 1
    });
  }

  const nodes = [...fileNodes, ...overviewNodes, ...activityNodes, ...knowledgeNodes, ...communityNodes];
  const links = [...overviewActivityLinks, ...fileKnowledgeLinks, ...communityLinks, ...knowledgeLinks];
  const linkCountByNodeID = links.reduce((partial, link) => {
    partial[link.sourceId] = (partial[link.sourceId] ?? 0) + link.weight;
    partial[link.targetId] = (partial[link.targetId] ?? 0) + link.weight;
    return partial;
  }, {});
  const selectedNodeID = config.selection === "densest"
    ? nodes
      .filter((node) => node.nodeType === "knowledge" || node.nodeType === "community")
      .reduce((currentBest, node) => (
        (linkCountByNodeID[node.id] ?? 0) > (linkCountByNodeID[currentBest?.id] ?? -1) ? node : currentBest
      ), null)?.id ?? null
    : null;

  return {
    graphId: `knowledge-benchmark-${config.seed}-${nodes.length}-${links.length}`,
    nodes: nodes.map((node) => ({
      ...node,
      linkCount: linkCountByNodeID[node.id] ?? 0
    })),
    links,
    selectedNodeId: selectedNodeID,
    pruningThresholds: config.pruningThresholds ?? {
      knowledge: config.knowledgeThreshold,
      file: config.fileThreshold,
      activity: config.activityThreshold,
      overview: config.overviewThreshold
    }
  };
};

const summarizeFrameDurations = (frameDurations, panDurationMs) => {
  const sortedDurations = [...frameDurations].sort((left, right) => left - right);
  const totalFrameMs = frameDurations.reduce((sum, duration) => sum + duration, 0);

  return {
    sampledFrames: frameDurations.length,
    averageFrameMs: frameDurations.length > 0 ? totalFrameMs / frameDurations.length : 0,
    p95FrameMs: percentile(sortedDurations, 0.95),
    p99FrameMs: percentile(sortedDurations, 0.99),
    worstFrameMs: sortedDurations.at(-1) ?? 0,
    missed60FpsFrames: frameDurations.filter((duration) => duration > 16.7).length,
    droppedFramesOver33Ms: frameDurations.filter((duration) => duration > 33.3).length,
    severeFramesOver50Ms: frameDurations.filter((duration) => duration > 50).length,
    effectiveFps: panDurationMs > 0 ? (frameDurations.length / panDurationMs) * 1000 : 0
  };
};

const ensureBenchmarkPanel = () => {
  const existingPanel = document.getElementById(BENCHMARK_PANEL_ID);

  if (existingPanel) {
    return existingPanel;
  }

  const panel = document.createElement("aside");
  panel.id = BENCHMARK_PANEL_ID;
  panel.style.position = "fixed";
  panel.style.top = "16px";
  panel.style.right = "16px";
  panel.style.zIndex = "9999";
  panel.style.width = "360px";
  panel.style.maxWidth = "calc(100vw - 32px)";
  panel.style.padding = "14px 16px";
  panel.style.borderRadius = "16px";
  panel.style.background = "rgba(24, 28, 38, 0.88)";
  panel.style.border = "1px solid rgba(255, 255, 255, 0.12)";
  panel.style.backdropFilter = "blur(18px)";
  panel.style.boxShadow = "0 24px 54px rgba(0, 0, 0, 0.32)";
  panel.style.color = "rgba(244, 247, 250, 0.96)";
  panel.style.fontFamily = "\"SF Pro Text\", \"Helvetica Neue\", sans-serif";
  panel.style.fontSize = "12px";
  panel.style.lineHeight = "1.45";
  document.body.appendChild(panel);
  return panel;
};

const renderBenchmarkPanel = ({ status, config, result, error }) => {
  const panel = ensureBenchmarkPanel();
  const reportJSON = result == null ? "" : JSON.stringify(result, null, 2);
  const summaryRows = result == null
    ? ""
    : [
      ["Initial render", `${result.initialRenderMs.toFixed(1)} ms`],
      ["Average frame", `${result.averageFrameMs.toFixed(2)} ms`],
      ["P95 frame", `${result.p95FrameMs.toFixed(2)} ms`],
      ["Worst frame", `${result.worstFrameMs.toFixed(2)} ms`],
      ["Missed 60fps", String(result.missed60FpsFrames)],
      ["Over 33ms", String(result.droppedFramesOver33Ms)],
      ["Over 50ms", String(result.severeFramesOver50Ms)],
      ["Effective FPS", `${result.effectiveFps.toFixed(1)}`],
      ["Rendered nodes", `${result.renderedNodeCount}/${result.nodeCount}`],
      ["Rendered links", `${result.renderedLinkCount}/${result.linkCount}`]
    ]
      .map(([label, value]) => `<div style="display:flex;justify-content:space-between;gap:12px;"><strong>${label}</strong><span>${value}</span></div>`)
      .join("");

  panel.innerHTML = `
    <div style="display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:10px;">
      <strong style="font-size:13px;">Knowledge Graph Benchmark</strong>
      <span style="padding:2px 8px;border-radius:999px;background:rgba(255,255,255,0.08);text-transform:uppercase;letter-spacing:0.05em;">${status}</span>
    </div>
    <div style="margin-bottom:10px;color:rgba(225,231,238,0.76);">
      nodes=${config.knowledgeNodes}, communities=${config.communities}, files=${config.files}, overviews=${config.overviews}, activities=${config.activities}, knowledgeEdges=${config.knowledgeEdges}, selection=${config.selection}
      <br>
      thresholds=knowledge:${config.knowledgeThreshold}, file:${config.fileThreshold}, activity:${config.activityThreshold}, overview:${config.overviewThreshold}
    </div>
    ${summaryRows}
    ${error ? `<div style="margin-top:10px;color:#ffb4b4;">${error}</div>` : ""}
    <pre id="${BENCHMARK_REPORT_ID}" style="margin:10px 0 0;padding:10px;border-radius:12px;background:rgba(0,0,0,0.24);max-height:280px;overflow:auto;white-space:pre-wrap;">${reportJSON}</pre>
  `;
};

export const runKnowledgeGraphBenchmark = async (partialConfig = {}) => {
  const config = { ...DEFAULT_BENCHMARK_CONFIG, ...partialConfig };
  const payload = syntheticKnowledgeGraphPayload(config);
  const initialRenderStart = performance.now();

  renderBenchmarkPanel({ status: "running", config, result: null, error: null });
  state.selectedNodeID = payload.selectedNodeId ?? null;
  scheduleRender({ kind: "knowledge-graph", graph: payload });

  await nextFrame();
  await nextFrame();

  const initialRenderMs = performance.now() - initialRenderStart;
  const frameDurations = [];
  const initialViewport = { ...state.knowledgeGraph.viewportTransform };
  const horizontalAmplitude = 180;
  const verticalAmplitude = 110;
  const panStartTime = await nextFrame();
  let previousTimestamp = panStartTime;

  await new Promise((resolve) => {
    const step = (timestamp) => {
      frameDurations.push(timestamp - previousTimestamp);
      previousTimestamp = timestamp;

      const progress = Math.min((timestamp - panStartTime) / config.panDurationMs, 1);
      const theta = progress * Math.PI * 2;
      state.knowledgeGraph.viewportTransform = {
        ...initialViewport,
        x: initialViewport.x + (Math.cos(theta) * horizontalAmplitude),
        y: initialViewport.y + (Math.sin(theta) * verticalAmplitude)
      };
      scheduleRender(state.payload);

      if (progress < 1) {
        requestAnimationFrame(step);
        return;
      }

      resolve();
    };

    requestAnimationFrame(step);
  });

  await Promise.all(Array.from({ length: Math.max(config.settleFrames, 0) }, () => nextFrame()));
  const summary = summarizeFrameDurations(frameDurations.slice(1), config.panDurationMs);
  const result = {
    ...summary,
    config,
    initialRenderMs,
    nodeCount: payload.nodes.length,
    linkCount: payload.links.length,
    renderedNodeCount: state.knowledgeGraph.nodes.length,
    renderedLinkCount: state.knowledgeGraph.links.length,
    pruningThresholds: payload.pruningThresholds,
    selectedNodeId: payload.selectedNodeId ?? null
  };

  window.__TASKTRACE_KNOWLEDGE_GRAPH_BENCHMARK__ = result;
  renderBenchmarkPanel({ status: "done", config, result, error: null });
  return result;
};

export const maybeStartKnowledgeGraphBenchmark = () => {
  const params = new URLSearchParams(window.location.search);

  if (params.get("benchmark") !== "knowledge-graph") {
    return;
  }

  const config = benchmarkConfigFromURL();
  window.TaskTraceKnowledgeGraphBenchmark = {
    run: runKnowledgeGraphBenchmark,
    syntheticKnowledgeGraphPayload
  };

  requestAnimationFrame(() => {
    runKnowledgeGraphBenchmark(config).catch((error) => {
      const message = error instanceof Error ? error.message : String(error);
      renderBenchmarkPanel({ status: "failed", config, result: null, error: message });
    });
  });
};

export const __testables__ = {
  DEFAULT_BENCHMARK_CONFIG,
  benchmarkConfigFromURL,
  syntheticKnowledgeGraphPayload,
  summarizeFrameDurations
};
