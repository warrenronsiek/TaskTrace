import * as d3 from "d3";
import { layoutWithLines, prepareWithSegments } from "@chenglou/pretext";
import {
  root,
  state,
  createSVG,
  hideTooltip,
  replaceShell,
  notifyNodeSelection
} from "../webviewRuntime";

const NODE_COLORS = {
  overview: "var(--accent)",
  activity: "var(--node-activity)",
  screenshot: "var(--node-screenshot)"
};

const SURFACE_COLORS = {
  containerFill: "var(--surface)",
  tileFill: "var(--surface-elevated)",
  tileStroke: "var(--border)",
  tileStrokeFocused: "rgba(255, 255, 255, 0.72)"
};

const TEXT_STYLES = {
  meta: {
    color: "var(--text-secondary)",
    fontFamily: "\"Helvetica Neue\", sans-serif",
    font: "600 10px \"Helvetica Neue\"",
    fontSize: 10,
    lineHeight: 12,
    letterSpacing: "0.08em",
    textTransform: "uppercase"
  },
  overviewTitle: {
    color: "var(--text-primary)",
    fontFamily: "\"Helvetica Neue\", sans-serif",
    font: "700 15px \"Helvetica Neue\"",
    fontSize: 15,
    lineHeight: 18
  },
  activityTitle: {
    color: "var(--text-primary)",
    fontFamily: "\"Helvetica Neue\", sans-serif",
    font: "700 14px \"Helvetica Neue\"",
    fontSize: 14,
    lineHeight: 17
  },
  screenshotTitle: {
    color: "var(--text-primary)",
    fontFamily: "\"Helvetica Neue\", sans-serif",
    font: "650 13px \"Helvetica Neue\"",
    fontSize: 13,
    lineHeight: 16
  },
  detail: {
    color: "var(--text-secondary)",
    fontFamily: "\"Helvetica Neue\", sans-serif",
    font: "400 12px \"Helvetica Neue\"",
    fontSize: 12,
    lineHeight: 15
  }
};

const preparedTextCache = new Map();
const textLineLayoutCache = new Map();
const SEARCH_TRANSITION_MS = 420;
const HOVER_STICKINESS_PX = 22;
const HOVER_REFOCUS_COOLDOWN_MS = 220;
const TEXT_LAYOUT_BUCKET_PX = 12;
const GLOW_SCORE_THRESHOLD = 0.12;
let searchScene = null;

const pluralizedLabel = (count, singular, plural) => `${count} ${count === 1 ? singular : plural}`;

const clipIDForNode = (nodeID) => `treemap-clip-${String(nodeID).replace(/[^a-zA-Z0-9_-]/g, "-")}`;

const prepareText = (text, font) => {
  const normalizedText = String(text ?? "").trim();

  if (normalizedText.length === 0) {
    return null;
  }

  const cacheKey = `${font}::${normalizedText}`;

  if (!preparedTextCache.has(cacheKey)) {
    preparedTextCache.set(cacheKey, prepareWithSegments(normalizedText, font));
  }

  return preparedTextCache.get(cacheKey);
};

const layoutTextLines = (blockKey, text, style, width) => {
  const renderedText = style.textTransform === "uppercase"
    ? String(text ?? "").trim().toUpperCase()
    : String(text ?? "").trim();
  const prepared = prepareText(renderedText, style.font);
  const safeWidth = Math.max(8, Math.floor(width));
  const widthBucket = Math.max(24, Math.floor(safeWidth / TEXT_LAYOUT_BUCKET_PX) * TEXT_LAYOUT_BUCKET_PX);

  if (!prepared || widthBucket < 24) {
    return null;
  }

  const cacheKey = `${blockKey}::${style.font}::${style.lineHeight}::${widthBucket}::${renderedText}`;

  if (!textLineLayoutCache.has(cacheKey)) {
    textLineLayoutCache.set(cacheKey, layoutWithLines(prepared, widthBucket, style.lineHeight).lines);
  }

  return {
    renderedText,
    lines: textLineLayoutCache.get(cacheKey)
  };
};

const appendTextBlock = (
  parent,
  {
    blockKey,
    text,
    x,
    y,
    width,
    maxHeight,
    style,
    opacity = 1
  }
) => {
  const safeWidth = Math.max(8, Math.floor(width));
  const maxLines = Math.max(0, Math.floor(maxHeight / style.lineHeight));
  const textLayout = layoutTextLines(blockKey, text, style, safeWidth);

  if (!textLayout || safeWidth < 24 || maxLines < 1) {
    return 0;
  }

  const visibleLines = textLayout.lines.slice(0, maxLines);

  if (visibleLines.length === 0) {
    return 0;
  }

  const textNode = parent.append("text")
    .attr("x", x)
    .attr("y", y + style.fontSize)
    .attr("fill", style.color)
    .attr("font-family", style.fontFamily)
    .attr("font-size", style.fontSize)
    .attr("font-weight", style.font.includes("700") ? 700 : style.font.includes("650") ? 650 : style.font.includes("600") ? 600 : 400)
    .attr("opacity", opacity)
    .style("pointer-events", "none");

  if (style.letterSpacing) {
    textNode.attr("letter-spacing", style.letterSpacing);
  }

  if (style.textTransform) {
    textNode.style("text-transform", style.textTransform);
  }

  visibleLines.forEach((line, lineIndex) => {
    textNode.append("tspan")
      .attr("x", x)
      .attr("dy", lineIndex === 0 ? 0 : style.lineHeight)
      .text(line.text);
  });

  return visibleLines.length * style.lineHeight;
};

const normalizedScoreLookup = (results) => results.reduce((partialResult, tree) => {
  partialResult[`overview:${tree.id}`] = Number(tree.score ?? 0);

  tree.activities.forEach((activity) => {
    partialResult[`activity:${activity.id}`] = Number(activity.score ?? 0);

    activity.screenshots.forEach((screenshot) => {
      partialResult[`screenshot:${screenshot.id}`] = Number(screenshot.score ?? 0);
    });
  });

  return partialResult;
}, {});

const formattedTimestamp = (value) => {
  const timestamp = value == null ? Number.NaN : Date.parse(value);

  if (!Number.isFinite(timestamp)) {
    return null;
  }

  return new Date(timestamp).toLocaleString([], {
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit"
  });
};

const sliceTimeForTree = (tree) => {
  const timestamps = tree.activities.flatMap((activity) => [
    Date.parse(activity.start_time),
    ...activity.screenshots
      .map((screenshot) => screenshot.ts)
      .filter(Boolean)
      .map((timestamp) => Date.parse(timestamp))
  ]).filter((value) => Number.isFinite(value));

  return timestamps.length > 0 ? Math.min(...timestamps) : Date.now();
};

const leafWeight = (kind, label, detail) => {
  const labelMass = Math.min(String(label ?? "").trim().length, 80) * 0.65;
  const detailMass = Math.min(String(detail ?? "").trim().length, 260) * 0.18;
  const kindFloor = {
    overview: 42,
    activity: 34,
    screenshot: 22
  };

  return kindFloor[kind] + labelMass + detailMass;
};

const normalizedNodeScore = (score) => Math.max(0, Math.min(Number(score ?? 0), 1));

const rerankWeightMultiplier = (score) => {
  const normalizedScore = normalizedNodeScore(score);

  if (normalizedScore <= GLOW_SCORE_THRESHOLD) {
    return 1;
  }

  const highlightedScore = (normalizedScore - GLOW_SCORE_THRESHOLD) / (1 - GLOW_SCORE_THRESHOLD);
  return 1 + (Math.pow(highlightedScore, 1.15) * 1.1);
};

const buildSearchHierarchy = (results) => ({
  nodeID: "root",
  kind: "root",
  children: results.map((tree) => {
    const overviewNodeID = `overview:${tree.id}`;
    const overviewTime = sliceTimeForTree(tree);
    const overviewLabel = tree.title ?? "Untitled Overview";
    const overviewDetail = tree.summary ?? "";

    return {
      nodeID: `group:${overviewNodeID}`,
      focusNodeID: overviewNodeID,
      kind: "overview-group",
      groupLabel: pluralizedLabel(tree.activities.length, "activity", "activities"),
      label: overviewLabel,
      detail: overviewDetail,
      time: overviewTime,
      children: [
        {
          nodeID: overviewNodeID,
          focusNodeID: overviewNodeID,
          kind: "overview",
          label: overviewLabel,
          detail: overviewDetail,
          meta: tree.activities.length > 0 ? pluralizedLabel(tree.activities.length, "activity", "activities") : null,
          score: Number(tree.score ?? 0),
          time: overviewTime,
          baseWeight: leafWeight("overview", overviewLabel, overviewDetail)
        },
        ...tree.activities.map((activity) => {
          const activityNodeID = `activity:${activity.id}`;
          const activityLabel = activity.application || "Activity";
          const activityDetail = activity.summary ?? activity.keystrokes ?? activity.microphone ?? "";
          const activityTime = Date.parse(activity.start_time);

          return {
            nodeID: `group:${activityNodeID}`,
            focusNodeID: activityNodeID,
            kind: "activity-group",
            groupLabel: pluralizedLabel(activity.screenshots.length, "screenshot", "screenshots"),
            label: activityLabel,
            detail: activityDetail,
            time: Number.isFinite(activityTime) ? activityTime : overviewTime,
            children: [
              {
                nodeID: activityNodeID,
                focusNodeID: activityNodeID,
                kind: "activity",
                label: activityLabel,
                detail: activityDetail,
                meta: formattedTimestamp(activity.start_time),
                score: Number(activity.score ?? 0),
                time: Number.isFinite(activityTime) ? activityTime : overviewTime,
                baseWeight: leafWeight("activity", activityLabel, activityDetail)
              },
              ...activity.screenshots.map((screenshot) => {
                const screenshotNodeID = `screenshot:${screenshot.id}`;
                const screenshotDescription = String(screenshot.description ?? "").trim();
                const screenshotOCR = String(screenshot.ocr_text ?? "").trim();
                const screenshotTime = screenshot.ts == null ? Number.NaN : Date.parse(screenshot.ts);
                const screenshotBody = screenshotDescription || screenshotOCR;

                return {
                  nodeID: screenshotNodeID,
                  focusNodeID: screenshotNodeID,
                  kind: "screenshot",
                  label: "",
                  detail: screenshotBody,
                  secondaryDetail: screenshotDescription && screenshotOCR ? screenshotOCR : null,
                  meta: formattedTimestamp(screenshot.ts) ?? "Screenshot",
                  score: Number(screenshot.score ?? 0),
                  time: Number.isFinite(screenshotTime) ? screenshotTime : (Number.isFinite(activityTime) ? activityTime : overviewTime),
                  baseWeight: leafWeight("screenshot", screenshotBody, screenshotOCR)
                };
              })
            ]
          };
        })
      ]
    };
  })
});

const rectFromNode = (node) => ({
  x: node.x0,
  y: node.y0,
  width: Math.max(0, node.x1 - node.x0),
  height: Math.max(0, node.y1 - node.y0)
});

const collapsedRect = (node) => ({
  x: (node.x0 + node.x1) / 2,
  y: (node.y0 + node.y1) / 2,
  width: 0,
  height: 0
});

const containsPoint = (frame, x, y, margin = 0) => (
  x >= frame.x - margin
    && x <= frame.x + frame.width + margin
    && y >= frame.y - margin
    && y <= frame.y + frame.height + margin
);

const rectChanged = (currentRect, previousRect) => (
  Math.abs(currentRect.x - previousRect.x) > 0.5
    || Math.abs(currentRect.y - previousRect.y) > 0.5
    || Math.abs(currentRect.width - previousRect.width) > 0.5
    || Math.abs(currentRect.height - previousRect.height) > 0.5
);

const applyClipRect = (rectSelection, rect, rectRadius) => {
  rectSelection
    .attr("x", 1)
    .attr("y", 1)
    .attr("width", Math.max(0, rect.width - 2))
    .attr("height", Math.max(0, rect.height - 2))
    .attr("rx", Math.max(0, rectRadius - 1))
    .attr("ry", Math.max(0, rectRadius - 1));
};

const translatedPositionFromTransform = (value) => {
  const match = /^translate\(([-\d.]+),\s*([-\d.]+)\)$/.exec(String(value ?? "").trim());

  if (!match) {
    return null;
  }

  const x = Number.parseFloat(match[1]);
  const y = Number.parseFloat(match[2]);

  return Number.isFinite(x) && Number.isFinite(y) ? { x, y } : null;
};

const renderedLeafRect = (group, fallbackRect) => {
  const tileRect = group.select(".treemap-leaf-tile");
  const translatedPosition = translatedPositionFromTransform(group.attr("transform"));
  const width = Number.parseFloat(tileRect.attr("width"));
  const height = Number.parseFloat(tileRect.attr("height"));

  return {
    x: translatedPosition?.x ?? fallbackRect.x,
    y: translatedPosition?.y ?? fallbackRect.y,
    width: Number.isFinite(width) ? width : fallbackRect.width,
    height: Number.isFinite(height) ? height : fallbackRect.height
  };
};

const textFrameKey = (rect) => (
  `${Math.max(0, Math.round(rect.width))}:${Math.max(0, Math.round(rect.height))}`
);

const cornerRadiusForNode = (node) => {
  if (node.depth === 1) {
    return 16;
  }

  if (node.depth === 2) {
    return 12;
  }

  return 10;
};

const colorKeyForNode = (kind) => {
  if (kind.startsWith("overview")) {
    return "overview";
  }

  if (kind.startsWith("activity")) {
    return "activity";
  }

  return "screenshot";
};

const renderLeafText = (parent, node, clipID, rectOverride = null) => {
  parent.selectAll("*").remove();
  parent.attr("clip-path", `url(#${clipID})`);
  const rect = {
    x: 0,
    y: 0,
    width: Math.max(0, rectOverride?.width ?? (node.x1 - node.x0)),
    height: Math.max(0, rectOverride?.height ?? (node.y1 - node.y0))
  };
  const padding = node.data.kind === "overview" ? 13 : 11;
  const contentX = rect.x + padding;
  const contentY = rect.y + padding;
  const contentWidth = rect.width - (padding * 2);
  let remainingHeight = rect.height - (padding * 2);
  let cursorY = contentY;

  if (contentWidth < 32 || remainingHeight < 24) {
    return;
  }

  if (node.data.meta) {
    const metaHeight = appendTextBlock(parent, {
      blockKey: `${node.data.nodeID}:meta`,
      text: node.data.meta,
      x: contentX,
      y: contentY,
      width: contentWidth,
      maxHeight: Math.min(remainingHeight, TEXT_STYLES.meta.lineHeight),
      style: TEXT_STYLES.meta
    });

    if (metaHeight > 0) {
      remainingHeight -= metaHeight + 6;
      cursorY += metaHeight + 6;
    }
  }

  if (node.data.kind === "screenshot") {
    if (remainingHeight >= TEXT_STYLES.detail.lineHeight && node.data.detail) {
      const detailHeight = appendTextBlock(parent, {
        blockKey: `${node.data.nodeID}:detail`,
        text: node.data.detail,
        x: contentX,
        y: cursorY,
        width: contentWidth,
        maxHeight: remainingHeight,
        style: TEXT_STYLES.detail,
        opacity: 0.98
      });

      if (
        detailHeight > 0
          && remainingHeight - detailHeight - 6 >= TEXT_STYLES.detail.lineHeight
          && node.data.secondaryDetail
      ) {
        appendTextBlock(parent, {
          blockKey: `${node.data.nodeID}:secondary-detail`,
          text: node.data.secondaryDetail,
          x: contentX,
          y: cursorY + detailHeight + 6,
          width: contentWidth,
          maxHeight: remainingHeight - detailHeight - 6,
          style: TEXT_STYLES.detail,
          opacity: 0.72
        });
      }
    }

    return;
  }

  const titleStyle = node.data.kind === "overview"
    ? TEXT_STYLES.overviewTitle
    : node.data.kind === "activity"
      ? TEXT_STYLES.activityTitle
      : TEXT_STYLES.screenshotTitle;
  const titleMaxHeight = Math.min(
    remainingHeight,
    titleStyle.lineHeight * (node.data.kind === "overview" ? 3 : 2)
  );
  const titleHeight = appendTextBlock(parent, {
    blockKey: `${node.data.nodeID}:title`,
    text: node.data.label,
    x: contentX,
    y: cursorY,
    width: contentWidth,
    maxHeight: titleMaxHeight,
    style: titleStyle
  });

  if (titleHeight > 0) {
    remainingHeight -= titleHeight + 6;
    cursorY += titleHeight + 6;
  }

  if (remainingHeight >= TEXT_STYLES.detail.lineHeight && node.data.detail) {
    appendTextBlock(parent, {
      blockKey: `${node.data.nodeID}:detail`,
      text: node.data.detail,
      x: contentX,
      y: cursorY,
      width: contentWidth,
      maxHeight: remainingHeight,
      style: TEXT_STYLES.detail,
      opacity: 0.94
    });
  }
};

const focusLeafWeight = (node, focusNode) => {
  const baseWeight = Number(node.data.baseWeight ?? 0) * rerankWeightMultiplier(node.data.score);

  if (!focusNode) {
    return baseWeight;
  }

  if (node.data.focusNodeID === focusNode.data.focusNodeID) {
    return baseWeight * 2.7;
  }

  const focusParentID = focusNode.parent?.data.nodeID;
  const focusGrandparentID = focusNode.parent?.parent?.data.nodeID;
  const ancestorIDs = new Set(node.ancestors().map((ancestor) => ancestor.data.nodeID));

  if (focusParentID && ancestorIDs.has(focusParentID)) {
    return baseWeight * 1.52;
  }

  if (focusGrandparentID && focusGrandparentID !== "root" && ancestorIDs.has(focusGrandparentID)) {
    return baseWeight * 1.18;
  }

  return baseWeight;
};

const emphasizedGlowScore = (score) => Math.pow(
  normalizedNodeScore(score),
  1.8
);

const ensureSearchScene = () => {
  if (!searchScene) {
    const svg = createSVG(1, 1);
    const defs = svg.append("defs");
    const glowFilter = defs.append("filter")
      .attr("id", "treemap-glow")
      .attr("x", "-45%")
      .attr("y", "-45%")
      .attr("width", "190%")
      .attr("height", "190%");
    glowFilter.append("feGaussianBlur")
      .attr("stdDeviation", 6)
      .attr("result", "blur");
    const glowMerge = glowFilter.append("feMerge");
    glowMerge.append("feMergeNode")
      .attr("in", "blur");
    glowMerge.append("feMergeNode")
      .attr("in", "SourceGraphic");

    searchScene = {
      svg,
      defs,
      clipLayer: defs.append("g").attr("class", "treemap-clip-layer"),
      containerLayer: svg.append("g").attr("class", "treemap-container-layer"),
      leafLayer: svg.append("g").attr("class", "treemap-leaf-layer")
    };
  }

  if (root.querySelector("svg.graph-svg") !== searchScene.svg.node()) {
    replaceShell(searchScene.svg.node());
  }

  return searchScene;
};

export const renderSearchResultsGraph = (results, render) => {
  const previousNodeScores = normalizedScoreLookup(state.previousSearchResults);
  state.previousSearchResults = results;

  const width = Math.max(root.clientWidth || 0, 840);
  const height = Math.max(root.clientHeight || 0, 620);
  const scene = ensureSearchScene();
  const geometryTransition = d3.transition()
    .duration(SEARCH_TRANSITION_MS)
    .ease(d3.easeCubicOut);

  scene.svg
    .attr("viewBox", `0 0 ${width} ${height}`)
    .attr("width", "100%")
    .attr("height", "100%");

  const hierarchyRoot = d3.hierarchy(buildSearchHierarchy(results));
  const leafNodes = hierarchyRoot.leaves();
  const leavesByID = new Map(leafNodes.map((node) => [node.data.focusNodeID, node]));

  state.selectedNodeID = leavesByID.has(state.selectedNodeID) ? state.selectedNodeID : null;
  state.hoveredNodeID = state.selectedNodeID == null && leavesByID.has(state.hoveredNodeID) ? state.hoveredNodeID : null;

  const focusNodeID = state.selectedNodeID ?? state.hoveredNodeID;
  const focusLeaf = focusNodeID == null ? null : leavesByID.get(focusNodeID);

  hierarchyRoot.eachAfter((node) => {
    const ownValue = node.children ? 0 : focusLeafWeight(node, focusLeaf);
    node.value = ownValue + (node.children ? d3.sum(node.children, (child) => child.value) : 0);
  });

  d3.treemap()
    .size([width, height])
    .tile(d3.treemapSliceDice)
    .round(true)
    .paddingOuter((node) => {
      if (node.depth === 0) {
        return 12;
      }

      if (node.depth === 1) {
        return 8;
      }

      return 6;
    })
    .paddingTop((node) => {
      if (node.depth === 1) {
        return 22;
      }

      if (node.depth === 2) {
        return 18;
      }

      return 0;
    })
    .paddingInner((node) => {
      if (node.depth === 1) {
        return 8;
      }

      if (node.depth === 2) {
        return 6;
      }

      return 0;
    })(hierarchyRoot);

  const previousLayouts = state.previousSearchLayoutByNodeID;
  const nextLayouts = new Map();
  const nextLeafFrames = [];
  const containerNodes = hierarchyRoot.descendants().filter((node) => node.depth > 0 && node.children);
  const containerFocusIDs = focusLeaf == null ? new Set() : new Set(
    focusLeaf.ancestors().map((ancestor) => ancestor.data.nodeID)
  );
  const orderedContainerNodes = containerNodes.sort((left, right) => left.depth - right.depth);
  const clipSelection = scene.clipLayer
    .selectAll("clipPath.treemap-leaf-clip")
    .data(leafNodes, (node) => node.data.nodeID);

  clipSelection.exit().remove();

  const clipEnter = clipSelection.enter()
    .append("clipPath")
    .attr("class", "treemap-leaf-clip")
    .attr("id", (node) => clipIDForNode(node.data.nodeID));

  clipEnter.append("rect");
  const clipRectsByNodeID = new Map();

  clipEnter
    .merge(clipSelection)
    .attr("id", (node) => clipIDForNode(node.data.nodeID))
    .each(function (node) {
      clipRectsByNodeID.set(node.data.nodeID, d3.select(this).select("rect"));
    });

  const containerSelection = scene.containerLayer
    .selectAll("g.treemap-container")
    .data(orderedContainerNodes, (node) => node.data.nodeID);

  containerSelection.exit()
    .each(function () {
      d3.select(this).interrupt();
      d3.select(this).selectAll("*").interrupt();
    })
    .transition(geometryTransition)
    .style("opacity", 0)
    .remove();

  const containerEnter = containerSelection.enter()
    .append("g")
    .attr("class", "treemap-container")
    .style("pointer-events", "none")
    .style("opacity", 0.001);

  containerEnter.append("rect");
  containerEnter.append("text")
    .attr("x", 10)
    .attr("y", 14)
    .attr("fill", "var(--text-secondary)")
    .attr("font-family", "\"Helvetica Neue\", sans-serif")
    .attr("font-size", 10)
    .attr("font-weight", 700)
    .attr("letter-spacing", "0.08em")
    .style("pointer-events", "none")
    .attr("opacity", 0);

  containerEnter.each(function (node) {
    const previousRect = previousLayouts.get(node.data.nodeID) ?? collapsedRect(node);
    const rectRadius = cornerRadiusForNode(node);

    d3.select(this)
      .attr("transform", `translate(${previousRect.x}, ${previousRect.y})`)
      .select("rect")
      .attr("x", 0)
      .attr("y", 0)
      .attr("width", previousRect.width)
      .attr("height", previousRect.height)
      .attr("rx", rectRadius)
      .attr("ry", rectRadius);
  });

  const containerMerge = containerEnter.merge(containerSelection);

  containerMerge
    .order()
    .each(function (node) {
      const currentRect = rectFromNode(node);
      const previousRect = previousLayouts.get(node.data.nodeID) ?? collapsedRect(node);
      const colorKey = colorKeyForNode(node.data.kind);
      const isFocusedBranch = containerFocusIDs.has(node.data.nodeID);
      const showLabel = currentRect.width > 74 && currentRect.height > 24 && node.data.groupLabel;
      const group = d3.select(this);
      const rect = group.select("rect");
      const label = group.select("text");

      group.interrupt();
      rect.interrupt();
      label.interrupt();

      group
        .transition(geometryTransition)
        .attr("transform", `translate(${currentRect.x}, ${currentRect.y})`)
        .style("opacity", 1);

      rect
        .attr("fill", SURFACE_COLORS.containerFill)
        .attr("fill-opacity", node.depth === 1 ? 0.84 : 0.72)
        .attr("stroke", NODE_COLORS[colorKey])
        .attr("stroke-width", isFocusedBranch ? 1.8 : 1.1)
        .attr("stroke-opacity", isFocusedBranch ? 0.18 : 0.08)
        .attr("rx", cornerRadiusForNode(node))
        .attr("ry", cornerRadiusForNode(node))
        .transition(geometryTransition)
        .attr("width", currentRect.width)
        .attr("height", currentRect.height);

      label
        .text(showLabel ? node.data.groupLabel.toUpperCase() : "")
        .transition(geometryTransition)
        .attr("opacity", showLabel ? 0.9 : 0);

      nextLayouts.set(node.data.nodeID, currentRect);
    });

  const leafSelection = scene.leafLayer
    .selectAll("g.treemap-leaf")
    .data(leafNodes, (node) => node.data.nodeID);

  leafSelection.exit()
    .each(function () {
      d3.select(this).interrupt();
      d3.select(this).selectAll("*").interrupt();
    })
    .transition(geometryTransition)
    .style("opacity", 0)
    .remove();

  const leafEnter = leafSelection.enter()
    .append("g")
    .attr("class", "treemap-leaf")
    .style("opacity", 0.001)
    .style("cursor", "pointer");

  leafEnter.append("rect")
    .attr("class", "treemap-leaf-tile")
    .attr("x", 0)
    .attr("y", 0);
  leafEnter.append("g")
    .attr("class", "treemap-leaf-text")
    .style("pointer-events", "none");

  leafEnter.each(function (node) {
    const previousRect = previousLayouts.get(node.data.nodeID) ?? collapsedRect(node);
    const rectRadius = cornerRadiusForNode(node);
    const group = d3.select(this);
    const clipRect = clipRectsByNodeID.get(node.data.nodeID);

    group.attr("transform", `translate(${previousRect.x}, ${previousRect.y})`);
    group.select(".treemap-leaf-glow")
      .attr("width", previousRect.width)
      .attr("height", previousRect.height)
      .attr("rx", rectRadius)
      .attr("ry", rectRadius);
    group.select(".treemap-leaf-tile")
      .attr("width", previousRect.width)
      .attr("height", previousRect.height)
      .attr("rx", rectRadius)
      .attr("ry", rectRadius);
    if (clipRect) {
      applyClipRect(clipRect, previousRect, rectRadius);
    }
    renderLeafText(group.select(".treemap-leaf-text"), node, clipIDForNode(node.data.nodeID), previousRect);
  });

  const leafMerge = leafEnter.merge(leafSelection);

  leafMerge
    .order()
    .each(function (node) {
      const currentRect = rectFromNode(node);
      const colorKey = colorKeyForNode(node.data.kind);
      const currentGlow = emphasizedGlowScore(node.data.score);
      const previousGlow = emphasizedGlowScore(previousNodeScores[node.data.focusNodeID] ?? 0);
      const rectRadius = cornerRadiusForNode(node);
      const isSelected = state.selectedNodeID === node.data.focusNodeID;
      const isFocused = focusNodeID === node.data.focusNodeID;
      const shouldShowGlow = currentGlow >= GLOW_SCORE_THRESHOLD;
      const group = d3.select(this);
      const fallbackRect = previousLayouts.get(node.data.nodeID) ?? collapsedRect(node);
      const startRect = renderedLeafRect(group, fallbackRect);
      const geometryChanged = rectChanged(currentRect, startRect);
      const rectInterpolator = d3.interpolateObject(startRect, currentRect);
      const shouldKeepGlow = shouldShowGlow || previousGlow >= GLOW_SCORE_THRESHOLD;
      let glowRect = group.select(".treemap-leaf-glow");

      if (shouldKeepGlow && glowRect.empty()) {
        glowRect = group.insert("rect", ".treemap-leaf-tile")
          .attr("class", "treemap-leaf-glow")
          .attr("x", 0)
          .attr("y", 0)
          .attr("fill", "none")
          .style("pointer-events", "none");
      } else if (!shouldKeepGlow && !glowRect.empty()) {
        glowRect.remove();
        glowRect = group.select(".treemap-leaf-glow");
      }

      const tileRect = group.select(".treemap-leaf-tile");
      const textGroup = group.select(".treemap-leaf-text");
      const clipRect = clipRectsByNodeID.get(node.data.nodeID);
      const previousGlowOpacity = previousGlow < GLOW_SCORE_THRESHOLD ? 0 : 0.10 + (previousGlow * 0.50);
      const nextGlowOpacity = shouldShowGlow ? 0.10 + (currentGlow * 0.50) : 0;
      let lastRenderedTextFrameKey = "";
      const renderTextFrame = (rect) => {
        const nextTextFrameKey = textFrameKey(rect);

        if (nextTextFrameKey === lastRenderedTextFrameKey) {
          return;
        }

        lastRenderedTextFrameKey = nextTextFrameKey;
        renderLeafText(textGroup, node, clipIDForNode(node.data.nodeID), rect);
      };

      group.interrupt();
      glowRect.interrupt();
      tileRect.interrupt();
      textGroup.interrupt();
      clipRect?.interrupt();

      if (clipRect) {
        applyClipRect(clipRect, startRect, rectRadius);

        if (geometryChanged) {
          clipRect
            .transition(geometryTransition)
            .tween("treemap-leaf-clip", () => (
              (t) => {
                applyClipRect(clipRect, rectInterpolator(t), rectRadius);
              }
            ));
        } else {
          applyClipRect(clipRect, currentRect, rectRadius);
        }
      }

      if (geometryChanged) {
        renderTextFrame(startRect);
      } else {
        renderLeafText(textGroup, node, clipIDForNode(node.data.nodeID), currentRect);
      }

      const groupTransition = group
        .on("click", (event) => {
          event.stopPropagation();

          state.selectedNodeID = state.selectedNodeID === node.data.focusNodeID ? null : node.data.focusNodeID;
          state.hoveredNodeID = null;
          state.searchLastHoverChangeAt = performance.now();
          notifyNodeSelection(state.selectedNodeID);
          render(state.payload);
        })
        .transition(geometryTransition)
        .attr("transform", `translate(${currentRect.x}, ${currentRect.y})`)
        .style("opacity", 1);

      if (geometryChanged) {
        groupTransition
          .tween("treemap-leaf-text", () => (
            (t) => {
              renderTextFrame(rectInterpolator(t));
            }
          ))
          .on("end.treemap-leaf-text", () => {
            renderLeafText(textGroup, node, clipIDForNode(node.data.nodeID), currentRect);
          });
      }

      if (!glowRect.empty()) {
        glowRect
          .attr("filter", "url(#treemap-glow)")
          .attr("stroke", NODE_COLORS[colorKey])
          .attr("stroke-width", 1.8 + (previousGlow * 4))
          .attr("stroke-opacity", previousGlowOpacity)
          .attr("rx", rectRadius)
          .attr("ry", rectRadius)
          .transition(geometryTransition)
          .attr("width", currentRect.width)
          .attr("height", currentRect.height)
          .attr("stroke-width", 1.8 + (currentGlow * 4))
          .attr("stroke-opacity", nextGlowOpacity);
      }

      tileRect
        .attr("fill", SURFACE_COLORS.tileFill)
        .attr("fill-opacity", isFocused ? 0.96 : 0.88)
        .attr("stroke", isSelected ? "var(--text-primary)" : (isFocused ? SURFACE_COLORS.tileStrokeFocused : SURFACE_COLORS.tileStroke))
        .attr("stroke-width", isSelected ? 2.2 : (isFocused ? 1.5 : 1.0))
        .attr("rx", rectRadius)
        .attr("ry", rectRadius)
        .transition(geometryTransition)
        .attr("width", currentRect.width)
        .attr("height", currentRect.height);

      nextLayouts.set(node.data.nodeID, currentRect);
      nextLeafFrames.push({
        nodeID: node.data.focusNodeID,
        x: currentRect.x,
        y: currentRect.y,
        width: currentRect.width,
        height: currentRect.height
      });
    });

  d3.select(scene.svg.node()).on("click", () => {
    if (state.selectedNodeID == null && state.hoveredNodeID == null) {
      return;
    }

    state.selectedNodeID = null;
    state.hoveredNodeID = null;
    state.searchLastHoverChangeAt = performance.now();
    notifyNodeSelection(null);
    render(state.payload);
  });

  d3.select(scene.svg.node()).on("mousemove", (event) => {
    if (state.selectedNodeID != null) {
      return;
    }

    const [pointerX, pointerY] = d3.pointer(event, scene.svg.node());
    const now = performance.now();
    const transitionIsActive = now < state.searchTreemapTransitionEndsAt;
    const currentHoveredFrames = state.hoveredNodeID == null
      ? []
      : [
        nextLeafFrames.find((frame) => frame.nodeID === state.hoveredNodeID) ?? null,
        state.searchTreemapLeafFrames.find((frame) => frame.nodeID === state.hoveredNodeID) ?? null
      ].filter(Boolean);
    const shouldKeepHoveredNode = currentHoveredFrames.some((frame) => (
      containsPoint(frame, pointerX, pointerY, transitionIsActive ? HOVER_STICKINESS_PX : 0)
    ));

    if (shouldKeepHoveredNode) {
      return;
    }

    const hoveredFrame = nextLeafFrames.find((frame) => containsPoint(frame, pointerX, pointerY))
      ?? state.searchTreemapLeafFrames.find((frame) => containsPoint(frame, pointerX, pointerY))
      ?? null;
    const nextHoveredNodeID = hoveredFrame?.nodeID ?? null;

    if (
      transitionIsActive
      && nextHoveredNodeID !== state.hoveredNodeID
      && now - state.searchLastHoverChangeAt < HOVER_REFOCUS_COOLDOWN_MS
    ) {
      return;
    }

    if (nextHoveredNodeID === state.hoveredNodeID) {
      return;
    }

    state.hoveredNodeID = nextHoveredNodeID;
    state.searchLastHoverChangeAt = now;
    render(state.payload);
  });

  d3.select(scene.svg.node()).on("mouseleave", () => {
    if (state.selectedNodeID != null || state.hoveredNodeID == null) {
      return;
    }

    state.hoveredNodeID = null;
    state.searchLastHoverChangeAt = performance.now();
    render(state.payload);
  });

  hideTooltip();
  state.previousSearchLayoutByNodeID = nextLayouts;
  state.searchTreemapLeafFrames = nextLeafFrames;
  state.searchTreemapTransitionEndsAt = performance.now() + SEARCH_TRANSITION_MS;
};
