# Knowledge Graph Benchmark

Use this benchmark when changing `TaskTraceWebView/src/renderers/knowledgeGraph.js` or any code that affects knowledge graph payload size, projection, transitions, SVG node/link counts, or camera interaction.

This is a real browser benchmark. Do not use `vitest` or `jsdom` numbers as a proxy for rendering smoothness.

## Run It

From the repo root:

```bash
cd TaskTraceWebView
npm run benchmark:knowledge-graph
```

That command builds the bundle, starts a local static server, and prints benchmark URLs.

Open one of the printed URLs in a real browser:

- `selection=none`
  Measures the default unselected graph state.
- `selection=densest`
  Measures the heavier selected-node state where adjacency edges are visible.

The benchmark page renders a large synthetic knowledge graph, performs a scripted 2D pan path across the viewport, and reports:

- `initialRenderMs`
- `averageFrameMs`
- `p95FrameMs`
- `p99FrameMs`
- `worstFrameMs`
- `missed60FpsFrames`
- `droppedFramesOver33Ms`
- `severeFramesOver50Ms`
- `effectiveFps`

The same JSON is also exposed at `window.__TASKTRACE_KNOWLEDGE_GRAPH_BENCHMARK__`.

## Change Evaluation

If you change the knowledge graph renderer:

1. Run the benchmark before the change.
2. Run the benchmark after the change.
3. Compare at least:
   `initialRenderMs`, `p95FrameMs`, `worstFrameMs`, `missed60FpsFrames`, `droppedFramesOver33Ms`.
4. Report both the `selection=none` and `selection=densest` runs if the change affects pan, projection, edge rendering, or node sizing.

## Query Parameters

The benchmark harness lives inside the normal webview bundle and activates when `benchmark=knowledge-graph` is in the URL.

Supported query params:

- `seed`
- `knowledgeNodes`
- `communities`
- `files`
- `overviews`
- `activities`
- `knowledgeEdges`
- `fileLinksPerFile`
- `panDurationMs`
- `settleFrames`
- `selection`

Example:

```text
http://127.0.0.1:4173/index.html?benchmark=knowledge-graph&knowledgeNodes=2000&knowledgeEdges=12000&selection=densest
```
