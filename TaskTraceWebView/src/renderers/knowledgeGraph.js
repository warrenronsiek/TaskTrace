import * as d3 from "d3";
import {
  root,
  shell,
  tooltip,
  state,
  createSVG,
  setTooltipHTML,
  hideTooltip,
  replaceShell,
  notifyNodeSelection
} from "../webviewRuntime";
import { getLayerSpec, computeLayerAnchors, registerLayerType } from "./layerRegistry";

let currentLayerAnchors = new Map();

const LABEL_VISIBILITY_THRESHOLD = 9;
const LAYOUT_POSITION_SMOOTHING = 0.18;
const POSITION_SNAP_EPSILON = 0.35;
const MIN_VIEWPORT_SCALE = 0.35;
const MAX_VIEWPORT_SCALE = 2.4;
const SUPPORTS_SVG_TRANSFORM_TRANSITIONS = typeof document === "undefined"
  ? false
  : document.createElementNS("http://www.w3.org/2000/svg", "g").transform?.baseVal != null;
const DEFAULT_PRUNING_THRESHOLDS = Object.freeze({
  knowledge: 450,
  file: 125,
  activity: 150,
  overview: 60
});

const resolveLayerAnchors = (layerIDs) => {
  currentLayerAnchors = computeLayerAnchors(layerIDs);
};

const layerConfig = (layer) => {
  const spec = getLayerSpec(layer);
  const anchor = currentLayerAnchors.get(layer) ?? spec.anchorOverride ?? { x: 0, y: 0, z: 0 };
  return {
    label: spec.label,
    anchorX: anchor.x,
    anchorY: anchor.y,
    radialRadius: spec.radialRadius,
    guideLength: spec.guideLength,
    tangentScale: spec.tangentScale,
    paneDepthScale: spec.paneDepthScale,
    guideOffset: spec.guideOffset,
    kind: spec.kind
  };
};

const layerAxes = (layer) => {
  const currentLayerConfig = layerConfig(layer);
  const anchorLength = Math.hypot(currentLayerConfig.anchorX, currentLayerConfig.anchorY);

  if (anchorLength < 1) {
    return {
      radialX: 0,
      radialY: 1,
      tangentX: 1,
      tangentY: 0
    };
  }

  const radialX = currentLayerConfig.anchorX / anchorLength;
  const radialY = currentLayerConfig.anchorY / anchorLength;

  return {
    radialX,
    radialY,
    tangentX: -radialY,
    tangentY: radialX
  };
};

const COMMUNITY_PASTEL_PALETTE = Object.freeze([
  { hue: 198, saturation: 58, lightness: 68 },
  { hue: 154, saturation: 50, lightness: 66 },
  { hue: 262, saturation: 50, lightness: 70 },
  { hue: 334, saturation: 50, lightness: 69 },
  { hue: 28, saturation: 54, lightness: 70 },
  { hue: 48, saturation: 54, lightness: 68 },
  { hue: 218, saturation: 50, lightness: 69 },
  { hue: 286, saturation: 46, lightness: 71 }
]);

const communityPaletteEntry = (communityID) => {
  if (!communityID) {
    return null;
  }

  const numericValue = Array.from(String(communityID)).reduce((sum, character) => (
    ((sum << 5) - sum) + character.charCodeAt(0)
  ), 0);
  return COMMUNITY_PASTEL_PALETTE[Math.abs(numericValue) % COMMUNITY_PASTEL_PALETTE.length];
};

const communityColor = (communityID, selected) => {
  const color = communityPaletteEntry(communityID);

  if (color == null) {
    return selected
      ? { fill: "var(--knowledge-node-selected)", stroke: "var(--knowledge-node-selected-stroke)" }
      : { fill: "var(--knowledge-node)", stroke: "var(--knowledge-node-stroke)" };
  }

  const lightness = color.lightness + (selected ? 4 : 0);
  const saturation = color.saturation + (selected ? 8 : 0);

  return {
    fill: `hsla(${color.hue}, ${saturation}%, ${lightness}%, ${selected ? 0.97 : 0.86})`,
    stroke: `hsla(${color.hue}, ${Math.max(28, color.saturation - 10)}%, ${selected ? 34 : 27}%, ${selected ? 0.84 : 0.62})`
  };
};

const knowledgeNodeColor = (communityID, selected) => {
  const color = communityPaletteEntry(communityID);

  if (color == null) {
    return selected
      ? { fill: "var(--knowledge-node-selected)", stroke: "var(--knowledge-node-selected-stroke)" }
      : { fill: "var(--knowledge-node)", stroke: "var(--knowledge-node-stroke)" };
  }

  return {
    fill: `hsla(${color.hue}, ${Math.max(28, color.saturation - 6)}%, ${selected ? color.lightness + 6 : color.lightness + 9}%, ${selected ? 0.92 : 0.62})`,
    stroke: `hsla(${color.hue}, ${Math.max(18, color.saturation - 18)}%, ${selected ? 34 : 25}%, ${selected ? 0.66 : 0.36})`
  };
};

const nodeColors = (node, selected) => {
  if (node.nodeType === "claim") {
    return {
      fill: selected ? "hsla(45, 48%, 72%, 0.94)" : "hsla(45, 38%, 76%, 0.72)",
      stroke: "hsla(45, 20%, 26%, 0.48)"
    };
  }

  if (node.nodeType === "file") {
    return {
      fill: selected ? "var(--knowledge-file-node-selected)" : "var(--knowledge-file-node)",
      stroke: "var(--knowledge-file-node-stroke)"
    };
  }

  if (node.nodeType === "overview") {
    return selected
      ? { fill: "hsla(26, 48%, 76%, 0.94)", stroke: "hsla(26, 28%, 28%, 0.68)" }
      : { fill: "hsla(26, 36%, 80%, 0.68)", stroke: "hsla(26, 18%, 28%, 0.46)" };
  }

  if (node.nodeType === "activity") {
    return selected
      ? { fill: "hsla(194, 48%, 74%, 0.94)", stroke: "hsla(194, 28%, 28%, 0.68)" }
      : { fill: "hsla(194, 34%, 80%, 0.66)", stroke: "hsla(194, 18%, 28%, 0.44)" };
  }

  if (node.nodeType === "community") {
    return communityColor(node.communityId, selected);
  }

  return knowledgeNodeColor(node.communityId, selected);
};

const linkID = (link) => [link.kind, link.sourceId, link.targetId].join(":");

const normalizePruningThresholds = (thresholds = null) => (
  Object.entries(DEFAULT_PRUNING_THRESHOLDS).reduce((partial, [key, fallback]) => {
    const value = Number(thresholds?.[key]);
    partial[key] = Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
    return partial;
  }, {})
);

const pruningThresholdKey = (thresholds) => (
  Object.entries(normalizePruningThresholds(thresholds))
    .map(([key, value]) => `${key}:${value}`)
    .join("|")
);

const pruningBucketKey = (node) => {
  if (node.nodeType === "file") return `file:${node.layer}`;
  if (node.nodeType === "knowledge") return "knowledge";
  if (node.nodeType === "activity") return "activity";
  if (node.nodeType === "overview") return "overview";
  return null;
};

const pruningThresholdForBucket = (bucketKey, thresholds) => {
  if (bucketKey?.startsWith("file:")) return thresholds.file;
  return thresholds[bucketKey] ?? Number.POSITIVE_INFINITY;
};

const weightedLinkCountByNodeID = (links) => links.reduce((partial, link) => {
  partial.set(link.sourceId, (partial.get(link.sourceId) ?? 0) + (link.weight ?? 1));
  partial.set(link.targetId, (partial.get(link.targetId) ?? 0) + (link.weight ?? 1));
  return partial;
}, new Map());

const computePrunedNodeIDs = ({
  nodes,
  links,
  linksByNodeId,
  overlayLinks = [],
  selectedNodeID = null,
  thresholds = DEFAULT_PRUNING_THRESHOLDS
}) => {
  const normalizedThresholds = normalizePruningThresholds(thresholds);
  const baseLinkCounts = weightedLinkCountByNodeID(links);
  const buckets = nodes.reduce((partial, node) => {
    const bucketKey = pruningBucketKey(node);

    if (bucketKey == null) {
      return partial;
    }

    const bucketNodes = partial.get(bucketKey) ?? [];
    bucketNodes.push(node);
    partial.set(bucketKey, bucketNodes);
    return partial;
  }, new Map());
  const cutoffsByBucket = Array.from(buckets.entries()).reduce((partial, [bucketKey, bucketNodes]) => {
    const threshold = pruningThresholdForBucket(bucketKey, normalizedThresholds);
    partial.set(bucketKey, bucketNodes.length > threshold ? Math.ceil(bucketNodes.length / threshold) : 0);
    return partial;
  }, new Map());
  const visibleNodeIDs = nodes.reduce((partial, node) => {
    const isAlwaysVisible = node.nodeType === "community"
      || node.searchHitRank != null
      || node.id === selectedNodeID;
    const bucketKey = pruningBucketKey(node);
    const cutoff = bucketKey == null ? 0 : cutoffsByBucket.get(bucketKey) ?? 0;
    const connectionCount = node.linkCount ?? baseLinkCounts.get(node.id) ?? 0;

    if (isAlwaysVisible || cutoff === 0 || connectionCount >= cutoff) {
      partial.add(node.id);
    }

    return partial;
  }, new Set());

  if (selectedNodeID != null) {
    visibleNodeIDs.add(selectedNodeID);
    (linksByNodeId.get(selectedNodeID) ?? []).forEach((link) => {
      visibleNodeIDs.add(link.sourceId);
      visibleNodeIDs.add(link.targetId);
    });
    overlayLinks
      .filter((link) => link.sourceId === selectedNodeID || link.targetId === selectedNodeID)
      .forEach((link) => {
        visibleNodeIDs.add(link.sourceId);
        visibleNodeIDs.add(link.targetId);
      });
  }

  nodes
    .filter((node) => node.nodeType === "claim" && node.parentNodeId != null && visibleNodeIDs.has(node.parentNodeId))
    .forEach((node) => visibleNodeIDs.add(node.id));

  return visibleNodeIDs;
};

const computeVisibleGraph = ({
  nodes,
  links,
  linksByNodeId,
  overlayLinks = [],
  selectedNodeID = null,
  thresholds = DEFAULT_PRUNING_THRESHOLDS
}) => {
  const visibleNodeIDs = computePrunedNodeIDs({
    nodes,
    links,
    linksByNodeId,
    overlayLinks,
    selectedNodeID,
    thresholds
  });
  const visibleNodes = nodes.filter((node) => visibleNodeIDs.has(node.id));
  const visibleLinks = links.filter((link) => (
    visibleNodeIDs.has(link.sourceId) && visibleNodeIDs.has(link.targetId)
  ));

  return {
    nodes: visibleNodes,
    links: visibleLinks,
    nodesById: new Map(visibleNodes.map((node) => [node.id, node])),
    linksById: new Map(visibleLinks.map((link) => [link.id, link])),
    visibleNodeIDs
  };
};

const linkStroke = (kind) => {
  if (kind === "claim") {
    return "hsla(45, 50%, 50%, 0.5)";
  }

  if (kind === "file") {
    return "var(--knowledge-file-edge)";
  }

  if (kind === "file-knowledge" || kind === "community") {
    return "var(--knowledge-bridge-edge)";
  }

  if (kind === "overview-activity") {
    return "hsla(198, 40%, 70%, 0.44)";
  }

  return "var(--knowledge-entity-edge)";
};

const overlayStroke = (kind) => {
  if (kind === "community") {
    return "var(--knowledge-bridge-edge)";
  }

  if (kind === "activity-knowledge") {
    return "hsla(194, 74%, 68%, 0.86)";
  }

  if (kind === "overview-knowledge") {
    return "hsla(26, 86%, 68%, 0.86)";
  }

  return "var(--knowledge-bridge-edge)";
};

const project = (_width, _height, sceneX, sceneY) => {
  const viewportTransform = state.knowledgeGraph.viewportTransform;

  return {
    x: (sceneX * viewportTransform.k) + viewportTransform.x,
    y: (sceneY * viewportTransform.k) + viewportTransform.y,
    scale: viewportTransform.k
  };
};

const nodeRadius = (node) => {
  if (node.nodeType === "claim") {
    return 5;
  }

  if (node.nodeType === "file") {
    return 12 + Math.min(node.linkCount ?? 0, 18) * 0.75;
  }

  if (node.nodeType === "overview") {
    return 16 + Math.min(node.linkCount ?? 0, 16) * 0.8;
  }

  if (node.nodeType === "activity") {
    return 11 + Math.min(node.linkCount ?? 0, 14) * 0.6;
  }

  if (node.nodeType === "community") {
    return Math.min(46, 14 + (Math.sqrt(Math.max(node.linkCount ?? 0, 0)) * 5.25));
  }

  return 6 + Math.min(node.linkCount ?? 0, 20) * 0.42;
};

const searchHitStrength = (searchHitRank) => {
  if (searchHitRank == null) {
    return 0;
  }

  return Math.max(0.38, 0.9 - (searchHitRank * 0.12));
};

const linkStrokeWidth = (kind, weight) => {
  if (kind === "knowledge") return 1.1;
  if (kind === "overview-activity") return 1.15;
  if (kind === "community") return 1;
  return 0.9 + Math.min(weight ?? 1, 4) * 0.18;
};

const overlayLinkID = (link) => [link.kind, link.sourceId, link.targetId].join(":");

const buildLinksByNodeId = (links) => links.reduce((linksByNodeId, link) => {
  const sourceLinks = linksByNodeId.get(link.sourceId) ?? [];
  sourceLinks.push(link);
  linksByNodeId.set(link.sourceId, sourceLinks);

  if (link.targetId !== link.sourceId) {
    const targetLinks = linksByNodeId.get(link.targetId) ?? [];
    targetLinks.push(link);
    linksByNodeId.set(link.targetId, targetLinks);
  }

  return linksByNodeId;
}, new Map());

const visibleBaseLinks = (
  linksByNodeId = state.knowledgeGraph.linksByNodeId,
  selectedNodeID = state.selectedNodeID,
  visibleNodeIDs = state.knowledgeGraph.visibleNodeIDs
) => {
  if (selectedNodeID == null) {
    return [];
  }

  return (linksByNodeId.get(selectedNodeID) ?? []).filter((link) => (
    visibleNodeIDs == null
      || visibleNodeIDs.size === 0
      || (visibleNodeIDs.has(link.sourceId) && visibleNodeIDs.has(link.targetId))
  ));
};

const visibleOverlayLinks = (
  links = state.overlayLinks,
  visibleNodeIDs = state.knowledgeGraph.visibleNodeIDs
) => {
  const selectedID = state.selectedNodeID;

  if (selectedID == null) {
    return [];
  }

  return links.filter((link) => (
    (link.sourceId === selectedID || link.targetId === selectedID)
      && (
        visibleNodeIDs == null
          || visibleNodeIDs.size === 0
          || (visibleNodeIDs.has(link.sourceId) && visibleNodeIDs.has(link.targetId))
      )
  ));
};

const normalizeNodes = (graphPayload, previousNodesById) => {
  const normalizedNodesById = new Map();

  return (graphPayload.nodes ?? []).map((node) => {
    const previousNode = previousNodesById.get(node.id);
    const parentNode = node.parentNodeId == null
      ? null
      : (previousNodesById.get(node.parentNodeId) ?? normalizedNodesById.get(node.parentNodeId));
    const currentLayerConfig = layerConfig(node.layer);
    const initialSceneX = node.nodeType === "claim" && parentNode
      ? (parentNode.displaySceneX ?? parentNode.sceneX ?? currentLayerConfig.anchorX)
      : currentLayerConfig.anchorX;
    const initialSceneY = node.nodeType === "claim" && parentNode
      ? (parentNode.displaySceneY ?? parentNode.sceneY ?? currentLayerConfig.anchorY)
      : currentLayerConfig.anchorY;

    if (previousNode) {
      Object.assign(previousNode, node, {
        radius: nodeRadius(node),
        x: previousNode.x ?? parentNode?.x ?? ((Math.random() - 0.5) * 420),
        y: previousNode.y ?? parentNode?.y ?? ((Math.random() - 0.5) * 360),
        sceneX: previousNode.sceneX ?? initialSceneX,
        sceneY: previousNode.sceneY ?? initialSceneY,
        displaySceneX: previousNode.displaySceneX ?? previousNode.sceneX ?? initialSceneX,
        displaySceneY: previousNode.displaySceneY ?? previousNode.sceneY ?? initialSceneY
      });

      normalizedNodesById.set(previousNode.id, previousNode);
      return previousNode;
    }

    const normalizedNode = {
      ...node,
      radius: nodeRadius(node),
      x: parentNode?.x ?? ((Math.random() - 0.5) * 420),
      y: parentNode?.y ?? ((Math.random() - 0.5) * 360),
      sceneX: initialSceneX,
      sceneY: initialSceneY,
      displaySceneX: initialSceneX,
      displaySceneY: initialSceneY
    };

    normalizedNodesById.set(normalizedNode.id, normalizedNode);
    return normalizedNode;
  });
};

const normalizeLinks = (graphPayload, nodeLookup) => (
  (graphPayload.links ?? [])
    .filter((link) => nodeLookup.has(link.sourceId) && nodeLookup.has(link.targetId))
    .map((link) => ({
      ...link,
      id: linkID(link),
      source: link.sourceId,
      target: link.targetId
    }))
);

const syncVisibleGraphFromCache = () => {
  const cache = state.knowledgeGraph;
  const visibleGraph = computeVisibleGraph({
    nodes: cache.allNodes ?? [],
    links: cache.allLinks ?? [],
    linksByNodeId: cache.allLinksByNodeId ?? new Map(),
    overlayLinks: state.overlayLinks,
    selectedNodeID: state.selectedNodeID,
    thresholds: cache.pruningThresholds
  });

  cache.nodes = visibleGraph.nodes;
  cache.links = visibleGraph.links;
  cache.nodesById = visibleGraph.nodesById;
  cache.linksById = visibleGraph.linksById;
  cache.linksByNodeId = cache.allLinksByNodeId ?? new Map();
  cache.visibleNodeIDs = visibleGraph.visibleNodeIDs;

  const currentVisibleBaseLinks = visibleBaseLinks(
    cache.linksByNodeId,
    state.selectedNodeID,
    visibleGraph.visibleNodeIDs
  );

  return {
    nodeLayoutKey: visibleGraph.nodes.map((node) => node.id).sort().join("|"),
    linkLayoutKey: visibleGraph.links.map((link) => link.id).sort().join("|"),
    visibleBaseLinkKey: currentVisibleBaseLinks.map((link) => link.id).join("|"),
    currentVisibleBaseLinks
  };
};

const refreshVisibleGraphForSelection = ({ animateLayout = true } = {}) => {
  const cache = state.knowledgeGraph;
  const previousVisibleNodesById = cache.nodesById ?? new Map();
  const {
    nodeLayoutKey,
    linkLayoutKey,
    visibleBaseLinkKey,
    currentVisibleBaseLinks
  } = syncVisibleGraphFromCache();
  const structureChanged = cache.nodeLayoutKey !== nodeLayoutKey
    || cache.linkLayoutKey !== linkLayoutKey
    || cache.visibleBaseLinkKey !== visibleBaseLinkKey;
  const layoutChanged = cache.nodeLayoutKey !== nodeLayoutKey || cache.linkLayoutKey !== linkLayoutKey;
  const selectionChanged = cache.resolvedSelectedNodeID !== state.selectedNodeID;

  if (structureChanged) {
    runStructureTier({ nodes: cache.nodes ?? [], links: currentVisibleBaseLinks });
  }

  if (layoutChanged) {
    cache.layoutRunID += 1;
    const layoutRunID = cache.layoutRunID;

    runLayoutTierAsync({
      nodes: cache.nodes ?? [],
      links: cache.links ?? [],
      layers: cache.layers ?? [],
      previousNodesById: previousVisibleNodesById,
      layoutRunID
    }).then(({ bootstrapSettled, cancelled }) => {
      if (cancelled || cache.layoutRunID !== layoutRunID) {
        return;
      }

      runPositionTier({
        animate: animateLayout && !bootstrapSettled,
        snapPositions: true
      });
    });
  } else if (structureChanged || selectionChanged) {
    runPositionTier({
      animate: false,
      refreshVisuals: true,
      refreshOverlay: true
    });
  } else {
    runVisualTier();
  }

  updateSelectionTooltip();

  cache.nodeLayoutKey = nodeLayoutKey;
  cache.linkLayoutKey = linkLayoutKey;
  cache.visibleBaseLinkKey = visibleBaseLinkKey;
  cache.resolvedSelectedNodeID = state.selectedNodeID;
};

const buildLayerSimulation = (layerIndex, nodes, links, hasExistingNodes, previousNodesById) => {
  const currentLayerConfig = layerConfig(layerIndex);
  const simulationNodes = nodes.filter((node) => node.nodeType !== "claim");
  const nonClaimLinks = links.filter((link) => link.kind !== "claim");
  const layerNodes = simulationNodes.filter((node) => node.layer === layerIndex);

  if (layerNodes.length === 0) {
    return null;
  }

  const layerNodeIDs = new Set(layerNodes.map((node) => node.id));
  const layerLinks = nonClaimLinks.filter(
    (link) => layerNodeIDs.has(link.source.id ?? link.source)
      && layerNodeIDs.has(link.target.id ?? link.target)
  );
  const spec = getLayerSpec(layerIndex);
  const isFileLayer = layerIndex === 0 || layerIndex === 4;
  const isActivityLayer = layerIndex === 1;
  const isKnowledgeLayer = spec.kind === "central";
  const communityNodes = isKnowledgeLayer
    ? layerNodes.filter((node) => node.nodeType === "community" && node.communityId != null)
    : [];
  const communityNodeByCommunityId = new Map(communityNodes.map((node) => [node.communityId, node]));
  const knowledgeMembersByCommunity = isKnowledgeLayer
    ? layerNodes.reduce((partial, node) => {
      if (node.nodeType !== "knowledge" || node.communityId == null || !communityNodeByCommunityId.has(node.communityId)) {
        return partial;
      }

      const list = partial.get(node.communityId) ?? [];
      list.push(node);
      partial.set(node.communityId, list);
      return partial;
    }, new Map())
    : new Map();
  const orphanKnowledgeNodes = isKnowledgeLayer
    ? layerNodes.filter((node) => (
      node.nodeType === "knowledge"
        && (node.communityId == null || !communityNodeByCommunityId.has(node.communityId))
    ))
    : [];
  const clusterRadiusByCommunityId = new Map(communityNodes.map((node) => {
    const memberCount = knowledgeMembersByCommunity.get(node.communityId)?.length ?? 0;
    return [node.communityId, node.radius + 24 + (Math.sqrt(Math.max(memberCount, 1)) * 16)];
  }));
  const knowledgeTargetByNodeId = isKnowledgeLayer
    ? (() => {
      const targets = new Map();
      const averageClusterRadius = communityNodes.length === 0
        ? 72
        : Array.from(clusterRadiusByCommunityId.values()).reduce((sum, radius) => sum + radius, 0) / communityNodes.length;
      const goldenAngle = Math.PI * (3 - Math.sqrt(5));

      communityNodes.forEach((communityNode, index) => {
        const distance = communityNodes.length <= 1
          ? 0
          : Math.sqrt(index) * Math.max(averageClusterRadius * 0.88, 62);
        const angle = index * goldenAngle;

        targets.set(communityNode.id, {
          x: Math.cos(angle) * distance,
          y: Math.sin(angle) * distance
        });
      });

      Array.from(knowledgeMembersByCommunity.entries()).forEach(([communityId, members]) => {
        const communityNode = communityNodeByCommunityId.get(communityId);
        const communityTarget = communityNode == null
          ? { x: 0, y: 0 }
          : targets.get(communityNode.id) ?? { x: communityNode.x ?? 0, y: communityNode.y ?? 0 };
        const clusterRadius = clusterRadiusByCommunityId.get(communityId) ?? ((communityNode?.radius ?? 0) + 44);
        const baseOrbitRadius = Math.max(
          (communityNode?.radius ?? 0) + 20,
          clusterRadius * 0.58
        );

        members.forEach((node, index) => {
          const angle = ((2 * Math.PI) / Math.max(members.length, 1)) * index;
          const orbitRadius = baseOrbitRadius + (Math.min(node.linkCount ?? 0, 12) * 2.2);

          targets.set(node.id, {
            x: communityTarget.x + (Math.cos(angle) * orbitRadius),
            y: communityTarget.y + (Math.sin(angle) * orbitRadius)
          });
        });
      });

      orphanKnowledgeNodes.forEach((node, index) => {
        if (communityNodes.length >= 2) {
          const leftCommunity = communityNodes[index % communityNodes.length];
          const rightCommunity = communityNodes[(index + Math.floor(communityNodes.length / 2) + 1) % communityNodes.length];
          const leftTarget = targets.get(leftCommunity.id) ?? { x: leftCommunity.x ?? 0, y: leftCommunity.y ?? 0 };
          const rightTarget = targets.get(rightCommunity.id) ?? { x: rightCommunity.x ?? 0, y: rightCommunity.y ?? 0 };
          const dx = rightTarget.x - leftTarget.x;
          const dy = rightTarget.y - leftTarget.y;
          const distance = Math.max(Math.hypot(dx, dy), 0.0001);
          const midpointX = (leftTarget.x + rightTarget.x) / 2;
          const midpointY = (leftTarget.y + rightTarget.y) / 2;
          const stagger = ((index % 5) - 2) * (node.radius + 7);

          targets.set(node.id, {
            x: midpointX + ((-dy / distance) * stagger),
            y: midpointY + ((dx / distance) * stagger)
          });
          return;
        }

        const angle = index * goldenAngle;
        const orbitRadius = communityNodes.length === 1
          ? (averageClusterRadius * 0.84) + node.radius + 16
          : Math.sqrt(index + 1) * Math.max(node.radius + 18, 34);

        targets.set(node.id, {
          x: Math.cos(angle) * orbitRadius,
          y: Math.sin(angle) * orbitRadius
        });
      });

      return targets;
    })()
    : new Map();

  if (isKnowledgeLayer) {
    communityNodes.forEach((communityNode, index) => {
      if (previousNodesById.has(communityNode.id)) {
        return;
      }

      const target = knowledgeTargetByNodeId.get(communityNode.id);
      communityNode.x = target?.x ?? 0;
      communityNode.y = target?.y ?? 0;
    });

    Array.from(knowledgeMembersByCommunity.entries()).forEach(([, members]) => {
      members.forEach((node) => {
        if (previousNodesById.has(node.id)) {
          return;
        }

        const target = knowledgeTargetByNodeId.get(node.id);
        node.x = target?.x ?? node.x;
        node.y = target?.y ?? node.y;
      });
    });

    orphanKnowledgeNodes.forEach((node, index) => {
      if (previousNodesById.has(node.id)) {
        return;
      }

      const target = knowledgeTargetByNodeId.get(node.id);
      node.x = target?.x ?? node.x;
      node.y = target?.y ?? node.y;
    });
  }

  if (hasExistingNodes) {
    layerNodes.forEach((node) => {
      if (previousNodesById.has(node.id)) {
        node.fx = node.x;
        node.fy = node.y;
      }
    });
  }

  const chargeStrength = (node) => {
    if (isKnowledgeLayer && node.nodeType === "community") {
      return -110 - (Math.sqrt(knowledgeMembersByCommunity.get(node.communityId)?.length ?? 0) * 18);
    }

    if (node.nodeType === "community") return -40;
    if (isKnowledgeLayer && orphanKnowledgeNodes.includes(node)) return -30;
    if (isKnowledgeLayer) return -18;
    if (isActivityLayer) return -300;
    return -280;
  };

  const simulation = d3.forceSimulation(layerNodes)
    .force(
      "link",
      d3.forceLink(layerLinks)
        .id((node) => node.id)
        .distance((link) => {
          if (link.kind === "overview-activity") return 95;
          if (isKnowledgeLayer && link.kind === "community") return 64;
          if (isFileLayer) return Math.max(94, 140 - (Math.min(link.weight ?? 1, 5) * 12));
          if (isActivityLayer) return 108;
          if (isKnowledgeLayer) return Math.max(24, 42 - (Math.min(link.weight ?? 1, 5) * 3));
          return Math.max(78, 120 - (Math.min(link.weight ?? 1, 5) * 10));
        })
        .strength((link) => {
          if (link.kind === "overview-activity") return 0.2;
          if (isKnowledgeLayer && link.kind === "community") return 0.018;
          if (isFileLayer) return 0.1 + Math.min((link.weight ?? 1) * 0.03, 0.13);
          if (isActivityLayer) return 0.16;
          if (isKnowledgeLayer) return 0.025 + Math.min((link.weight ?? 1) * 0.008, 0.025);
          return 0.12 + Math.min((link.weight ?? 1) * 0.025, 0.08);
        })
    )
    .force("charge", d3.forceManyBody().strength(chargeStrength))
    .force(
      "collide",
      d3.forceCollide()
        .radius((node) => {
          if (isKnowledgeLayer && node.nodeType === "community") {
            return node.radius + 8;
          }

          if (isKnowledgeLayer) {
            return node.radius + 5;
          }

          return node.radius + (isFileLayer ? 18 : isActivityLayer ? 20 : 16);
        })
        .iterations(isKnowledgeLayer ? 3 : 2)
    )
    .force(
      "x",
      d3.forceX((node) => knowledgeTargetByNodeId.get(node.id)?.x ?? 0)
        .strength((node) => {
          if (!isKnowledgeLayer) return 0.04;
          if (node.nodeType === "community") return 0.18;
          if (orphanKnowledgeNodes.includes(node)) return 0.08;
          return 0.12;
        })
    )
    .force(
      "y",
      d3.forceY((node) => knowledgeTargetByNodeId.get(node.id)?.y ?? 0)
        .strength((node) => {
          if (!isKnowledgeLayer) return 0.04;
          if (node.nodeType === "community") return 0.18;
          if (orphanKnowledgeNodes.includes(node)) return 0.08;
          return 0.12;
        })
    );

  if (isKnowledgeLayer) {
    if (communityNodes.length > 0) {
      const communityClusterForce = (alpha) => {
        layerNodes.forEach((node) => {
          if (node.nodeType !== "knowledge" || node.communityId == null) {
            return;
          }

          const communityNode = communityNodeByCommunityId.get(node.communityId);

          if (!communityNode) {
            return;
          }

          const dx = node.x - communityNode.x;
          const dy = node.y - communityNode.y;
          const distance = Math.max(Math.hypot(dx, dy), 0.0001);
          const targetDistance = communityNode.radius
            + node.radius
            + 20
            + (Math.min(node.linkCount ?? 0, 12) * 2.2);
          const springOffset = distance - targetDistance;
          const force = alpha * 0.18;
          const normalX = dx / distance;
          const normalY = dy / distance;

          node.vx = (node.vx ?? 0) - (normalX * springOffset * force);
          node.vy = (node.vy ?? 0) - (normalY * springOffset * force);
          communityNode.vx = (communityNode.vx ?? 0) + (normalX * springOffset * force * 0.04);
          communityNode.vy = (communityNode.vy ?? 0) + (normalY * springOffset * force * 0.04);
        });
      };

      const communitySeparationForce = (alpha) => {
        communityNodes.forEach((leftNode, leftIndex) => {
          const leftCluster = clusterRadiusByCommunityId.get(leftNode.communityId) ?? leftNode.radius;
          communityNodes.forEach((rightNode, rightIndex) => {
            if (rightIndex <= leftIndex) {
              return;
            }

            const rightCluster = clusterRadiusByCommunityId.get(rightNode.communityId) ?? rightNode.radius;
            const dx = rightNode.x - leftNode.x;
            const dy = rightNode.y - leftNode.y;
            const distance = Math.max(Math.hypot(dx, dy), 0.0001);
            const minimumDistance = (leftCluster * 0.86) + (rightCluster * 0.86) + 18;

            if (distance >= minimumDistance) {
              return;
            }

            const push = ((minimumDistance - distance) / distance) * alpha * 0.18;
            const offsetX = dx * push;
            const offsetY = dy * push;

            rightNode.vx = (rightNode.vx ?? 0) + offsetX;
            rightNode.vy = (rightNode.vy ?? 0) + offsetY;
            leftNode.vx = (leftNode.vx ?? 0) - offsetX;
            leftNode.vy = (leftNode.vy ?? 0) - offsetY;
          });
        });
      };

      simulation.force("community-cluster", communityClusterForce);
      simulation.force("community-separation", communitySeparationForce);
    }
  } else {
    simulation.force(
      "radial",
      d3.forceRadial(currentLayerConfig.radialRadius * 0.78, 0, 0).strength(0.02)
    );
  }

  simulation.stop();

  return {
    simulation,
    layerNodes,
    pinRemaining: hasExistingNodes ? 18 : 0,
    remaining: hasExistingNodes ? 18 : 280
  };
};

const computeScenePositions = (nodes) => {
  const knowledgeLayerAnchor = layerConfig(2);
  const knowledgeCloudNodes = nodes.filter((node) => node.nodeType === "knowledge" || node.nodeType === "community");
  let knowledgeEnvelopeRadius = 0;

  if (knowledgeCloudNodes.length > 0) {
    const centroidX = knowledgeCloudNodes.reduce((sum, node) => sum + node.x, 0) / knowledgeCloudNodes.length;
    const centroidY = knowledgeCloudNodes.reduce((sum, node) => sum + node.y, 0) / knowledgeCloudNodes.length;
    const compactScale = 0.84;

    knowledgeCloudNodes.forEach((node) => {
      node.sceneX = knowledgeLayerAnchor.anchorX + ((node.x - centroidX) * compactScale);
      node.sceneY = knowledgeLayerAnchor.anchorY + ((node.y - centroidY) * compactScale);
    });

    knowledgeEnvelopeRadius = knowledgeCloudNodes.reduce((largestRadius, node) => (
      Math.max(
        largestRadius,
        Math.hypot(
          node.sceneX - knowledgeLayerAnchor.anchorX,
          node.sceneY - knowledgeLayerAnchor.anchorY
        ) + node.radius
      )
    ), 0);
  }

  const nodeLookup = new Map(nodes.map((node) => [node.id, node]));
  Array.from(
    nodes
      .filter((node) => node.nodeType !== "knowledge" && node.nodeType !== "community" && node.nodeType !== "claim")
      .reduce((partial, node) => {
        const list = partial.get(node.layer) ?? [];
        list.push(node);
        partial.set(node.layer, list);
        return partial;
      }, new Map())
      .entries()
  )
    .forEach(([layer, layerNodes]) => {
      const currentLayerConfig = layerConfig(layer);
      const { tangentX, tangentY, radialX, radialY } = layerAxes(layer);
      const projectedNodes = layerNodes.map((node) => {
        const tangentOffset = node.x * currentLayerConfig.tangentScale;
        const radialOffset = node.y * currentLayerConfig.paneDepthScale;
        return {
          node,
          sceneX: currentLayerConfig.anchorX + (tangentX * tangentOffset) + (radialX * radialOffset),
          sceneY: currentLayerConfig.anchorY + (tangentY * tangentOffset) + (radialY * radialOffset)
        };
      });
      const layerSafetyGap = 96 + currentLayerConfig.guideOffset + (currentLayerConfig.radialRadius * 0.18);
      const inwardEdgeDistance = projectedNodes.reduce((smallestDistance, entry) => (
        Math.min(
          smallestDistance,
          Math.hypot(
            entry.sceneX - knowledgeLayerAnchor.anchorX,
            entry.sceneY - knowledgeLayerAnchor.anchorY
          ) - entry.node.radius
        )
      ), Number.POSITIVE_INFINITY);
      const outwardShift = knowledgeEnvelopeRadius > 0
        ? Math.max(0, (knowledgeEnvelopeRadius + layerSafetyGap) - inwardEdgeDistance)
        : 0;

      projectedNodes.forEach((entry) => {
        entry.node.sceneX = entry.sceneX + (radialX * outwardShift);
        entry.node.sceneY = entry.sceneY + (radialY * outwardShift);
      });
    });

  nodes
    .filter((node) => node.nodeType !== "knowledge" && node.nodeType !== "community" && node.nodeType !== "claim")
    .forEach((node) => {
      if (!Number.isFinite(node.sceneX) || !Number.isFinite(node.sceneY)) {
        node.sceneX = layerConfig(node.layer).anchorX;
        node.sceneY = layerConfig(node.layer).anchorY;
      }
    });

  const claimsByParentID = nodes
    .filter((node) => node.nodeType === "claim" && node.parentNodeId != null)
    .reduce((partial, node) => {
      const list = partial.get(node.parentNodeId) ?? [];
      list.push(node);
      partial.set(node.parentNodeId, list);
      return partial;
    }, new Map());

  Array.from(claimsByParentID.entries()).forEach(([parentNodeId, claimNodes]) => {
    const parentNode = nodeLookup.get(parentNodeId);

    if (!parentNode) {
      return;
    }

    claimNodes.forEach((claimNode, index) => {
      const orbitRadius = parentNode.radius + 42 + (claimNodes.length * 4);
      const angle = ((2 * Math.PI) / Math.max(claimNodes.length, 1)) * index;
      claimNode.sceneX = parentNode.sceneX + (orbitRadius * Math.cos(angle));
      claimNode.sceneY = parentNode.sceneY + (orbitRadius * Math.sin(angle));
    });
  });
};

const runLayoutTierAsync = ({ nodes, links, layers, previousNodesById, layoutRunID }) => {
  const cache = state.knowledgeGraph;

  if (cache.runningSimHandle != null) {
    cancelAnimationFrame(cache.runningSimHandle);
    cache.runningSimHandle = null;
  }

  const hasExistingNodes = previousNodesById.size > 0;
  const layersToSimulate = hasExistingNodes
    ? layers.filter((layer) => {
      const layerNodes = nodes.filter((node) => node.layer === layer && node.nodeType !== "claim");
      return layerNodes.some((node) => !previousNodesById.has(node.id))
        || Array.from(previousNodesById.values()).some((prev) => prev.layer === layer && !nodes.some((node) => node.id === prev.id));
    })
    : layers.slice();

  const layerSims = layersToSimulate
    .map((layer) => buildLayerSimulation(layer, nodes, links, hasExistingNodes, previousNodesById))
    .filter(Boolean);

  return new Promise((resolve) => {
    const finish = (result) => {
      if (cache.layoutRunID !== layoutRunID) {
        layerSims.forEach((entry) => entry.simulation.stop());
        resolve({ bootstrapSettled: false, cancelled: true });
        return;
      }

      resolve({ ...result, cancelled: false });
    };

    if (layerSims.length === 0) {
      computeScenePositions(nodes);
      finish({ bootstrapSettled: !hasExistingNodes });
      return;
    }

    if (!hasExistingNodes) {
      layerSims.forEach((entry) => {
        while (entry.remaining > 0) {
          const batch = Math.min(24, entry.remaining);
          for (let index = 0; index < batch; index += 1) entry.simulation.tick();
          entry.remaining -= batch;
        }
        entry.simulation.stop();
      });

      computeScenePositions(nodes);
      finish({ bootstrapSettled: true });
      return;
    }

    layerSims.forEach((entry) => {
      while (entry.remaining > 0) {
        entry.simulation.tick();
        entry.remaining -= 1;
      }
      entry.simulation.stop();
    });

    computeScenePositions(nodes);
    finish({ bootstrapSettled: true });
  });
};

const handleNodeClick = (event, datum) => {
  event.stopPropagation();
  state.selectedNodeID = datum.id;
  notifyNodeSelection(datum.id);
  refreshVisibleGraphForSelection();
};

const applyViewportTransform = (cache, { animate = false } = {}) => {
  const { x, y, k } = cache.viewportTransform;
  const target = cache.layerGroups.scene;

  if (animate && SUPPORTS_SVG_TRANSFORM_TRANSITIONS) {
    target.transition()
      .duration(260)
      .ease(d3.easeCubicOut)
      .attr("transform", `translate(${x}, ${y}) scale(${k})`);
    return;
  }

  target.attr("transform", `translate(${x}, ${y}) scale(${k})`);
};

const syncViewportTransform = (cache, { throughZoomBehavior = false, animate = false } = {}) => {
  if (throughZoomBehavior && cache.zoomBehavior && cache.svgRoot) {
    const transform = d3.zoomIdentity
      .translate(cache.viewportTransform.x, cache.viewportTransform.y)
      .scale(cache.viewportTransform.k);
    cache.svgRoot.call(cache.zoomBehavior.transform, transform);
    return;
  }

  applyViewportTransform(cache, { animate });
};

const fitViewportTransform = (nodes, width, height) => {
  if (nodes.length === 0) {
    return {
      x: width / 2,
      y: height / 2,
      k: 1
    };
  }

  const bounds = nodes.reduce((partial, node) => {
    const padding = node.radius + 72;
    partial.minX = Math.min(partial.minX, node.sceneX - padding);
    partial.maxX = Math.max(partial.maxX, node.sceneX + padding);
    partial.minY = Math.min(partial.minY, node.sceneY - padding);
    partial.maxY = Math.max(partial.maxY, node.sceneY + padding);
    return partial;
  }, {
    minX: Number.POSITIVE_INFINITY,
    maxX: Number.NEGATIVE_INFINITY,
    minY: Number.POSITIVE_INFINITY,
    maxY: Number.NEGATIVE_INFINITY
  });
  const contentWidth = Math.max(bounds.maxX - bounds.minX, 1);
  const contentHeight = Math.max(bounds.maxY - bounds.minY, 1);
  const paddedWidth = contentWidth + 180;
  const paddedHeight = contentHeight + 180;
  const scale = Math.max(
    MIN_VIEWPORT_SCALE,
    Math.min(
      MAX_VIEWPORT_SCALE,
      Math.min(width / paddedWidth, height / paddedHeight) * 0.92
    )
  );
  const centerX = (bounds.minX + bounds.maxX) / 2;
  const centerY = (bounds.minY + bounds.maxY) / 2;

  return {
    x: (width / 2) - (centerX * scale),
    y: (height / 2) - (centerY * scale),
    k: scale
  };
};

const ensureKnowledgeScene = (width, height) => {
  const cache = state.knowledgeGraph;

  if (!cache.svgRoot) {
    const svgSel = createSVG(width, height);
    const defs = svgSel.append("defs");
    const glowFilter = defs.append("filter")
      .attr("id", "knowledge-node-glow")
      .attr("x", "-90%")
      .attr("y", "-90%")
      .attr("width", "280%")
      .attr("height", "280%");
    glowFilter.append("feGaussianBlur")
      .attr("id", "knowledge-node-glow-blur")
      .attr("stdDeviation", 8)
      .attr("result", "blur");
    const glowMerge = glowFilter.append("feMerge");
    glowMerge.append("feMergeNode").attr("in", "blur");
    glowMerge.append("feMergeNode").attr("in", "SourceGraphic");

    const clearSelection = (event) => {
      if (event?.defaultPrevented || state.selectedNodeID == null) {
        return;
      }

      state.selectedNodeID = null;
      notifyNodeSelection(null);
      refreshVisibleGraphForSelection({ animateLayout: false });
    };
    const background = svgSel.append("rect")
      .attr("class", "knowledge-background")
      .attr("fill", "transparent")
      .on("click", clearSelection);
    const scene = svgSel.append("g").attr("class", "knowledge-scene");
    const halos = scene.append("g").attr("class", "knowledge-community-halos");
    const links = scene.append("g").attr("class", "knowledge-links");
    const overlayLinks = scene.append("g").attr("class", "overlay-links");
    const nodes = scene.append("g").attr("class", "knowledge-nodes");
    const zoomBehavior = d3.zoom()
      .scaleExtent([MIN_VIEWPORT_SCALE, MAX_VIEWPORT_SCALE])
      .filter((event) => !event.button)
      .on("zoom", (event) => {
        cache.viewportTransform = {
          x: event.transform.x,
          y: event.transform.y,
          k: event.transform.k
        };
        applyViewportTransform(cache);
        cache.lastViewport = {
          ...cache.viewportTransform,
          width: cache.width,
          height: cache.height
        };
      });

    svgSel.call(zoomBehavior).on("dblclick.zoom", null);
    svgSel.on("click", clearSelection);

    cache.svgRoot = svgSel;
    cache.zoomBehavior = zoomBehavior;
    cache.layerGroups = {
      defs,
      background,
      scene,
      halos,
      links,
      nodes,
      overlayLinks
    };
  }

  cache.svgRoot.attr("viewBox", `0 0 ${width} ${height}`);
  cache.layerGroups.background
    .attr("width", width)
    .attr("height", height);
  cache.width = width;
  cache.height = height;

  if (shell.firstChild !== cache.svgRoot.node()) {
    replaceShell(cache.svgRoot.node());
  }
};

const updateDisplayedScenePositions = (nodes, { smoothPositions = false, snapPositions = false } = {}) => {
  nodes.forEach((node) => {
    if (
      snapPositions
      || !Number.isFinite(node.displaySceneX)
      || !Number.isFinite(node.displaySceneY)
    ) {
      node.displaySceneX = node.sceneX;
      node.displaySceneY = node.sceneY;
      return;
    }

    if (!smoothPositions) {
      return;
    }

    node.displaySceneX += (node.sceneX - node.displaySceneX) * LAYOUT_POSITION_SMOOTHING;
    node.displaySceneY += (node.sceneY - node.displaySceneY) * LAYOUT_POSITION_SMOOTHING;

    if (
      Math.abs(node.sceneX - node.displaySceneX) < POSITION_SNAP_EPSILON
      && Math.abs(node.sceneY - node.displaySceneY) < POSITION_SNAP_EPSILON
    ) {
      node.displaySceneX = node.sceneX;
      node.displaySceneY = node.sceneY;
    }
  });
};

const positionLineSelection = (
  lineSelection,
  {
    nodeLookup,
    duration = 0,
    ease = d3.easeCubicInOut
  }
) => {
  const lineCoords = (datum) => {
    const sourceNode = nodeLookup.get(datum.sourceId);
    const targetNode = nodeLookup.get(datum.targetId);

    if (!sourceNode || !targetNode) {
      return null;
    }

    return {
      sourceX: sourceNode.displaySceneX ?? sourceNode.sceneX,
      sourceY: sourceNode.displaySceneY ?? sourceNode.sceneY,
      targetX: targetNode.displaySceneX ?? targetNode.sceneX,
      targetY: targetNode.displaySceneY ?? targetNode.sceneY
    };
  };

  if (duration > 0) {
    lineSelection.transition().duration(duration).ease(ease)
      .attr("x1", (datum) => lineCoords(datum)?.sourceX ?? 0)
      .attr("y1", (datum) => lineCoords(datum)?.sourceY ?? 0)
      .attr("x2", (datum) => lineCoords(datum)?.targetX ?? 0)
      .attr("y2", (datum) => lineCoords(datum)?.targetY ?? 0);
    return;
  }

  lineSelection
    .attr("x1", (datum) => lineCoords(datum)?.sourceX ?? 0)
    .attr("y1", (datum) => lineCoords(datum)?.sourceY ?? 0)
    .attr("x2", (datum) => lineCoords(datum)?.targetX ?? 0)
    .attr("y2", (datum) => lineCoords(datum)?.targetY ?? 0);
};

const runStructureTier = ({ nodes, links }) => {
  const cache = state.knowledgeGraph;
  const { links: linksGroup, nodes: nodesGroup } = cache.layerGroups;
  const nodeLookup = cache.nodesById ?? new Map();

  if (links.length === 0) {
    linksGroup.selectAll("line.k-link")
      .interrupt()
      .remove();
  } else {
    const linkSelection = linksGroup.selectAll("line.k-link").data(links, (datum) => datum.id);
    linkSelection.exit()
      .interrupt()
      .transition()
      .duration(320)
      .attr("stroke-opacity", 0)
      .remove();
    const linkEnter = linkSelection.enter().append("line")
      .attr("class", "k-link")
      .attr("stroke-opacity", 0)
      .attr("vector-effect", "non-scaling-stroke");
    positionLineSelection(linkEnter, { nodeLookup });
  }

  const nodeSelection = nodesGroup.selectAll("g.k-node").data(nodes, (datum) => datum.id);
  nodeSelection.exit()
    .classed("is-exiting", true)
    .interrupt()
    .transition()
    .duration(320)
    .style("opacity", 0)
    .remove();
  const nodeEnter = nodeSelection.enter().append("g")
    .attr("class", "k-node")
    .style("cursor", "pointer")
    .style("opacity", 0);
  nodeEnter.append("circle")
    .attr("class", "k-node-glow")
    .attr("cx", 0).attr("cy", 0).attr("r", 0)
    .attr("opacity", 0)
    .attr("filter", "url(#knowledge-node-glow)");
  nodeEnter.append("circle")
    .attr("class", "k-node-core")
    .attr("cx", 0).attr("cy", 0).attr("r", 0)
    .attr("vector-effect", "non-scaling-stroke");
  nodeEnter.append("text")
    .attr("class", "k-node-label")
    .attr("x", 0)
    .attr("text-anchor", "middle")
    .attr("font-family", "SF Pro Text, Helvetica Neue, sans-serif")
    .attr("fill", "var(--text-primary)")
    .attr("opacity", 0);
  nodeEnter.on("click", handleNodeClick);
};

const runPositionTier = ({
  animate = false,
  smoothPositions = false,
  snapPositions = false,
  refreshVisuals = true,
  refreshOverlay = true,
  fitViewport = false
} = {}) => {
  const cache = state.knowledgeGraph;

  if (!cache.layerGroups) {
    return;
  }

  const nodes = cache.nodes ?? [];
  const nodeLookup = cache.nodesById ?? new Map();

  updateDisplayedScenePositions(nodes, { smoothPositions, snapPositions });

  if (fitViewport && nodes.length > 0) {
    cache.viewportTransform = fitViewportTransform(nodes, cache.width, cache.height);
    cache.viewportInitialized = true;
    syncViewportTransform(cache, { throughZoomBehavior: true });
  } else {
    applyViewportTransform(cache);
  }

  const duration = animate && SUPPORTS_SVG_TRANSFORM_TRANSITIONS ? 600 : 0;
  const ease = d3.easeCubicInOut;
  const nodeSelection = cache.layerGroups.nodes.selectAll("g.k-node:not(.is-exiting)");
  const linkSelection = cache.layerGroups.links.selectAll("line.k-link");

  if (!animate) {
    nodeSelection.interrupt();
    linkSelection.interrupt();
  }

  if (duration > 0 && SUPPORTS_SVG_TRANSFORM_TRANSITIONS) {
    nodeSelection.transition().duration(duration).ease(ease)
      .attr("transform", (datum) => `translate(${datum.displaySceneX ?? datum.sceneX}, ${datum.displaySceneY ?? datum.sceneY})`);
  } else {
    nodeSelection.attr("transform", (datum) => `translate(${datum.displaySceneX ?? datum.sceneX}, ${datum.displaySceneY ?? datum.sceneY})`);
  }

  positionLineSelection(linkSelection, { nodeLookup, duration, ease });

  drawCommunityHalos();

  if (refreshOverlay) {
    drawOverlayLinks(visibleOverlayLinks(), false);
  }

  cache.layerGroups.overlayLinks.attr("opacity", state.selectedNodeID != null ? 1 : 0);
  positionLineSelection(
    cache.layerGroups.overlayLinks.selectAll("line.k-overlay-link"),
    { nodeLookup }
  );

  if (refreshVisuals) {
    runVisualTier({ animate });
  }
};

const drawCommunityHalos = () => {
  const cache = state.knowledgeGraph;
  const haloGroup = cache.layerGroups?.halos;

  if (!haloGroup) {
    return;
  }

  haloGroup.selectAll("circle.k-community-halo")
    .interrupt()
    .remove();
};

const runVisualTier = ({ animate = true } = {}) => {
  const cache = state.knowledgeGraph;

  if (!cache.layerGroups) {
    return;
  }

  const selectedID = state.selectedNodeID;
  const duration = animate ? 220 : 0;
  const ease = d3.easeCubicOut;
  const anySearchActive = (cache.nodes ?? []).some((node) => node.searchHitRank != null);
  const searchStrengthByCommunityId = (cache.nodes ?? []).reduce((partial, node) => {
    if (node.communityId == null) {
      return partial;
    }

    partial.set(
      node.communityId,
      Math.max(partial.get(node.communityId) ?? 0, searchHitStrength(node.searchHitRank))
    );
    return partial;
  }, new Map());

  if (cache.lastAnySearchActive !== anySearchActive) {
    const blur = d3.select("#knowledge-node-glow-blur");

    if (!blur.empty()) {
      const targetStdDev = anySearchActive ? 12 : 8;
      if (animate) {
        blur.transition().duration(320).ease(d3.easeCubicOut).attr("stdDeviation", targetStdDev);
      } else {
        blur.attr("stdDeviation", targetStdDev);
      }
    }
    cache.lastAnySearchActive = anySearchActive;
  }

  cache.layerGroups.nodes.selectAll("g.k-node:not(.is-exiting)").each(function (datum) {
    const group = d3.select(this);
    const isSelected = datum.id === selectedID;
    const isCommunity = datum.nodeType === "community";
    const colors = nodeColors(datum, isSelected);
    const hitStrength = datum.nodeType === "community" && datum.communityId != null
      ? Math.max(searchHitStrength(datum.searchHitRank), searchStrengthByCommunityId.get(datum.communityId) ?? 0)
      : searchHitStrength(datum.searchHitRank);
    const isSearchHit = hitStrength > 0;
    const glowOpacity = isSelected
      ? (datum.nodeType === "file" ? 0.22 : 0.36)
      : isSearchHit
        ? Math.max(0.18, hitStrength * 0.58)
        : 0;
    const glowPadding = (
      (isCommunity ? 16 : datum.nodeType === "overview" ? 12 : datum.nodeType === "activity" ? 10 : datum.nodeType === "file" ? 8 : 8)
        + (isSearchHit ? (18 * hitStrength) : 0)
    );
    const showLabel = datum.nodeType !== "activity" && (
      isCommunity
      || (datum.linkCount ?? 0) > LABEL_VISIBILITY_THRESHOLD
      || isSearchHit
      || isSelected
    );
    const strokeWidth = isSelected
      ? (isCommunity ? 2.2 : 1.6)
      : isCommunity
        ? 1.8
        : isSearchHit
          ? 1.25 + (hitStrength * 0.8)
          : 0.8;

    const glow = group.select("circle.k-node-glow");
    const core = group.select("circle.k-node-core");
    const label = group.select("text.k-node-label");

    (duration > 0 ? glow.transition().duration(duration).ease(ease) : glow)
      .attr("r", datum.radius + glowPadding)
      .attr("fill", colors.fill)
      .attr("opacity", glowOpacity);

    (duration > 0 ? core.transition().duration(duration).ease(ease) : core)
      .attr("r", datum.radius)
      .attr("fill", colors.fill)
      .attr("stroke", colors.stroke)
      .attr("stroke-width", strokeWidth);

    label
      .attr("y", -(datum.radius + 10))
      .attr("font-size", 10)
      .attr("font-weight", 600)
      .attr("fill", "rgba(249, 249, 247, 0.94)")
      .text(datum.label.length > 34 ? `${datum.label.slice(0, 33)}...` : datum.label);

    (duration > 0 ? label.transition().duration(duration).ease(ease) : label)
      .attr("opacity", showLabel ? 0.95 : 0);

    if (group.style("opacity") !== "1") {
      (duration > 0 ? group.transition().duration(Math.max(duration, 400)).ease(d3.easeCubicOut) : group)
        .style("opacity", 1);
    }
  });

  cache.layerGroups.links.selectAll("line.k-link").each(function (datum) {
    const line = d3.select(this);
    const sourceNode = cache.nodesById.get(datum.sourceId);
    const targetNode = cache.nodesById.get(datum.targetId);
    const shouldEmphasize = selectedID != null
      && (sourceNode?.id === selectedID || targetNode?.id === selectedID);
    const restingOpacity = selectedID == null ? 0 : shouldEmphasize ? 0.8 : 0;

    line
      .attr("stroke", linkStroke(datum.kind))
      .attr("stroke-width", linkStrokeWidth(datum.kind, datum.weight));

    (duration > 0 ? line.transition().duration(duration).ease(ease) : line)
      .attr("stroke-opacity", restingOpacity);
  });
};

const updateSelectionTooltip = () => {
  const cache = state.knowledgeGraph;
  const { width } = cache;
  const selectedID = state.selectedNodeID;
  const selectedNode = selectedID != null ? cache.nodesById.get(selectedID) : null;

  if (!selectedNode) {
    hideTooltip();
    return;
  }

  const tooltipWidth = Math.min(420, Math.max((width ?? 900) - 36, 0));
  const left = Math.max(18, (width ?? 900) - tooltipWidth - 18);
  const top = 18;
  const detailHTML = [
    [
      "Layer",
      selectedNode.nodeType === "file"
        ? "File"
        : selectedNode.nodeType === "community"
          ? "Community"
          : selectedNode.nodeType === "overview"
            ? "Overview"
            : selectedNode.nodeType === "activity"
              ? "Activity"
              : (selectedNode.kind ?? "Knowledge")
    ],
    ["Title", selectedNode.label],
    selectedNode.sourcePath ? ["Source", selectedNode.sourcePath] : null,
    selectedNode.detail ? ["Details", selectedNode.detail] : null,
    ["Connections", String(selectedNode.linkCount ?? 0)]
  ]
    .filter(Boolean)
    .map(([label, value]) => `
      <div class="tooltip-row">
        <span class="tooltip-label">${label}</span>
        <span class="tooltip-value">${value}</span>
      </div>
    `)
    .join("");

  setTooltipHTML(detailHTML, left, top);
};

const classifyRenderDelta = ({ nodeLayoutKey, linkLayoutKey, width, height }) => {
  const cache = state.knowledgeGraph;
  const structureChanged = cache.nodeLayoutKey !== nodeLayoutKey || cache.linkLayoutKey !== linkLayoutKey;
  const viewportTransform = cache.viewportTransform;
  const viewportChanged = cache.lastViewport == null
    || cache.lastViewport.x !== viewportTransform.x
    || cache.lastViewport.y !== viewportTransform.y
    || cache.lastViewport.k !== viewportTransform.k
    || cache.lastViewport.width !== width
    || cache.lastViewport.height !== height;

  return {
    structure: structureChanged,
    layout: structureChanged,
    viewportChanged,
    projection: structureChanged || viewportChanged,
    visual: true
  };
};

export { registerLayerType };

export const __testables__ = {
  linkID,
  overlayLinkID,
  project,
  nodeRadius,
  searchHitStrength,
  classifyRenderDelta,
  buildLinksByNodeId,
  visibleBaseLinks,
  visibleOverlayLinks,
  DEFAULT_PRUNING_THRESHOLDS,
  normalizePruningThresholds,
  pruningThresholdKey,
  computePrunedNodeIDs,
  computeVisibleGraph,
  computeScenePositions,
  updateDisplayedScenePositions,
  fitViewportTransform,
  layerConfig,
  layerAxes
};

export const renderKnowledgeGraph = (graphPayload, _render) => {
  const width = Math.max(root.clientWidth || 0, 900);
  const height = Math.max(root.clientHeight || 0, 680);

  ensureKnowledgeScene(width, height);
  const cache = state.knowledgeGraph;
  const payloadSelectedNodeID = graphPayload.selectedNodeId ?? null;
  const nextPruningThresholds = normalizePruningThresholds(graphPayload.pruningThresholds);
  const nextPruningThresholdKey = pruningThresholdKey(nextPruningThresholds);
  const resolvedCachedSelection = state.selectedNodeID != null
    ? ((cache.allNodesById ?? cache.nodesById).has(state.selectedNodeID) ? state.selectedNodeID : payloadSelectedNodeID)
    : payloadSelectedNodeID;
  const payloadUnchanged = cache.graphId === graphPayload.graphId
    && cache.sourceNodes === (graphPayload.nodes ?? [])
    && cache.sourceLinks === (graphPayload.links ?? [])
    && cache.sourceSelectedNodeId === payloadSelectedNodeID
    && cache.resolvedSelectedNodeID === resolvedCachedSelection
    && cache.sourcePruningThresholdKey === nextPruningThresholdKey;

  if (payloadUnchanged) {
    state.selectedNodeID = resolvedCachedSelection;

    const delta = classifyRenderDelta({
      nodeLayoutKey: cache.nodeLayoutKey,
      linkLayoutKey: cache.linkLayoutKey,
      width,
      height
    });

    if (delta.viewportChanged) {
      syncViewportTransform(cache, { throughZoomBehavior: true });
    }

    updateSelectionTooltip();
    cache.lastViewport = {
      ...cache.viewportTransform,
      width,
      height
    };
    return;
  }

  const previousVisibleNodesById = cache.nodesById ?? new Map();
  const previousAllNodesById = cache.allNodesById ?? cache.nodesById ?? new Map();
  const rawNodes = graphPayload.nodes ?? [];
  const layers = Array.from(new Set(rawNodes.map((node) => node.layer))).sort((left, right) => left - right);
  resolveLayerAnchors(layers);

  const allNodes = normalizeNodes(graphPayload, previousAllNodesById);
  const allNodeLookup = new Map(allNodes.map((node) => [node.id, node]));
  const allLinks = normalizeLinks(graphPayload, allNodeLookup);
  const allLinksByNodeId = buildLinksByNodeId(allLinks);

  cache.allNodes = allNodes;
  cache.allLinks = allLinks;
  cache.allNodesById = allNodeLookup;
  cache.allLinksById = new Map(allLinks.map((link) => [link.id, link]));
  cache.allLinksByNodeId = allLinksByNodeId;
  cache.linksByNodeId = allLinksByNodeId;
  cache.layers = layers;
  cache.pruningThresholds = nextPruningThresholds;

  const resolvedSelectedNodeID = state.selectedNodeID != null
    ? (allNodeLookup.has(state.selectedNodeID) ? state.selectedNodeID : (graphPayload.selectedNodeId ?? null))
    : (graphPayload.selectedNodeId ?? null);
  state.selectedNodeID = resolvedSelectedNodeID;
  const {
    nodeLayoutKey,
    linkLayoutKey,
    visibleBaseLinkKey,
    currentVisibleBaseLinks
  } = syncVisibleGraphFromCache();
  const delta = classifyRenderDelta({ nodeLayoutKey, linkLayoutKey, width, height });
  const visibleBaseStructureChanged = cache.visibleBaseLinkKey !== visibleBaseLinkKey;
  const shouldFitViewport = !cache.viewportInitialized || previousAllNodesById.size === 0;

  if (delta.structure || visibleBaseStructureChanged) {
    runStructureTier({ nodes: cache.nodes, links: currentVisibleBaseLinks });
  }

  if (delta.layout) {
    cache.layoutRunID += 1;
    const layoutRunID = cache.layoutRunID;

    runLayoutTierAsync({
      nodes: cache.nodes,
      links: cache.links,
      layers,
      previousNodesById: previousVisibleNodesById,
      layoutRunID
    }).then(({ bootstrapSettled, cancelled }) => {
      if (cancelled || cache.layoutRunID !== layoutRunID) {
        return;
      }

      runPositionTier({
        animate: !bootstrapSettled,
        snapPositions: true,
        fitViewport: shouldFitViewport
      });
    });
  } else if (delta.projection || visibleBaseStructureChanged) {
    if (cache.nodes.length === 0) {
      cache.viewportInitialized = false;
    }

    runPositionTier({
      animate: false,
      refreshVisuals: true,
      refreshOverlay: true,
      fitViewport: shouldFitViewport
    });
  } else if (delta.visual) {
    runVisualTier();
  }

  updateSelectionTooltip();

  cache.graphId = graphPayload.graphId;
  cache.sourceNodes = graphPayload.nodes ?? [];
  cache.sourceLinks = graphPayload.links ?? [];
  cache.sourceSelectedNodeId = payloadSelectedNodeID;
  cache.sourcePruningThresholdKey = nextPruningThresholdKey;
  cache.resolvedSelectedNodeID = resolvedSelectedNodeID;
  cache.nodeLayoutKey = nodeLayoutKey;
  cache.linkLayoutKey = linkLayoutKey;
  cache.visibleBaseLinkKey = visibleBaseLinkKey;
  cache.lastViewport = {
    ...cache.viewportTransform,
    width,
    height
  };
};

const drawOverlayLinks = (links, animate) => {
  const cache = state.knowledgeGraph;
  const overlayGroup = cache.layerGroups?.overlayLinks;

  if (!overlayGroup) {
    return;
  }

  const visibleLinks = state.selectedNodeID != null ? links : [];
  overlayGroup.attr("opacity", visibleLinks.length > 0 ? 1 : 0);

  const overlaySelection = overlayGroup.selectAll("line.k-overlay-link").data(visibleLinks, overlayLinkID);
  overlaySelection.exit()
    .interrupt()
    .remove();

  const overlayEnter = overlaySelection.enter().append("line")
    .attr("class", "k-overlay-link")
    .attr("stroke-opacity", animate ? 0 : 0.84)
    .attr("vector-effect", "non-scaling-stroke");

  const mergedSelection = overlayEnter.merge(overlaySelection)
    .attr("stroke", (link) => overlayStroke(link.kind))
    .attr("stroke-width", (link) => (
      link.kind === "activity-knowledge" || link.kind === "overview-knowledge" ? 1.25 : 1
    ));

  positionLineSelection(mergedSelection, {
    nodeLookup: cache.nodesById ?? new Map()
  });

  if (animate) {
    overlayEnter.transition()
      .duration(420)
      .ease(d3.easeCubicOut)
      .attr("stroke-opacity", 0.84);
  } else {
    mergedSelection.attr("stroke-opacity", 0.84);
  }
};

export const updateOverlayLinks = (links) => {
  const linksKey = links.map(overlayLinkID).join("|");
  const stateKey = state.overlayLinks.map(overlayLinkID).join("|");

  if (linksKey === stateKey) {
    return;
  }

  state.overlayLinks = links;
  if ((state.knowledgeGraph.allNodes ?? []).length > 0) {
    refreshVisibleGraphForSelection();
    return;
  }

  drawOverlayLinks(visibleOverlayLinks(links), true);
};
