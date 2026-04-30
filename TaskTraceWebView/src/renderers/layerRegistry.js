const layerRegistry = new Map();

const DEFAULT_PANE_SPEC = {
  label: "Layer",
  kind: "pane",
  radialRadius: 170,
  guideLength: 160,
  guideDepth: 110,
  tangentScale: 1.05,
  paneDepthScale: 0.96,
  guideOffset: 28
};

const DEFAULT_CENTRAL_SPEC = {
  label: "Knowledge Graph",
  kind: "central",
  radialRadius: 150,
  guideLength: 130,
  guideDepth: 84,
  tangentScale: 1,
  paneDepthScale: 1,
  guideOffset: 22,
  anchorOverride: { x: 0, y: 0, z: 0 }
};

export const registerLayerType = (id, spec) => {
  const base = spec.kind === "central" ? DEFAULT_CENTRAL_SPEC : DEFAULT_PANE_SPEC;
  layerRegistry.set(id, { ...base, ...spec });
};

export const getLayerSpec = (id) => (
  layerRegistry.get(id) ?? { ...DEFAULT_PANE_SPEC, label: `Layer ${id}` }
);

export const computeLayerAnchors = (layerIDs) => {
  const anchors = new Map();
  const autoPanes = [];

  layerIDs.forEach((id) => {
    const spec = getLayerSpec(id);
    if (spec.kind === "central" || spec.anchorOverride) {
      anchors.set(id, spec.anchorOverride ?? { x: 0, y: 0, z: 0 });
      return;
    }
    autoPanes.push({ id, spec });
  });

  if (autoPanes.length === 0) {
    return anchors;
  }

  autoPanes.sort((left, right) => (left.id - right.id));

  const paneRadius = 560;
  const useAlternatingOffset = autoPanes.length <= 4;
  const startAngle = -Math.PI / 2 - (Math.PI / 6);

  autoPanes.forEach((entry, index) => {
    const angle = typeof entry.spec.angularHint === "number"
      ? entry.spec.angularHint
      : startAngle + ((2 * Math.PI * index) / autoPanes.length);
    const verticalOffset = useAlternatingOffset
      ? (index % 2 === 0 ? 0 : 120)
      : 0;

    anchors.set(entry.id, {
      x: Math.cos(angle) * paneRadius,
      y: (Math.sin(angle) * paneRadius) + verticalOffset,
      z: 0
    });
  });

  return anchors;
};

registerLayerType(0, {
  label: "Markdown Files",
  kind: "pane",
  radialRadius: 190,
  guideLength: 160,
  guideDepth: 116,
  tangentScale: 1.08,
  paneDepthScale: 0.98,
  guideOffset: 28,
  anchorOverride: { x: 500, y: -250, z: 0 }
});

registerLayerType(1, {
  label: "Activities + Overviews",
  kind: "pane",
  radialRadius: 180,
  guideLength: 170,
  guideDepth: 120,
  tangentScale: 1.04,
  paneDepthScale: 0.96,
  guideOffset: 28,
  anchorOverride: { x: -500, y: -250, z: 0 }
});

registerLayerType(2, {
  label: "Knowledge Graph",
  kind: "central",
  radialRadius: 150,
  guideLength: 130,
  guideDepth: 84,
  tangentScale: 1,
  paneDepthScale: 1,
  guideOffset: 22
});

registerLayerType(4, {
  label: "TaskTrace Ingest",
  kind: "pane",
  radialRadius: 150,
  guideLength: 150,
  guideDepth: 108,
  tangentScale: 1.02,
  paneDepthScale: 0.94,
  guideOffset: 28,
  anchorOverride: { x: 0, y: 370, z: 0 }
});
