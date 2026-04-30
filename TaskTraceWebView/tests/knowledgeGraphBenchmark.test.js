// @vitest-environment jsdom
import { beforeEach, describe, expect, it } from "vitest";

document.body.innerHTML = '<main id="app"></main>';

const { __testables__ } = await import("../src/benchmarks/knowledgeGraphBenchmark");

const {
  DEFAULT_BENCHMARK_CONFIG,
  benchmarkConfigFromURL,
  syntheticKnowledgeGraphPayload,
  summarizeFrameDurations
} = __testables__;
const SMALL_BENCHMARK_CONFIG = {
  ...DEFAULT_BENCHMARK_CONFIG,
  knowledgeNodes: 24,
  communities: 6,
  files: 8,
  overviews: 4,
  activities: 12,
  knowledgeEdges: 48
};

describe("benchmarkConfigFromURL", () => {
  beforeEach(() => {
    window.history.replaceState({}, "", "/");
  });

  it("reads the densest selection mode from the query string", () => {
    window.history.replaceState({}, "", "/?selection=densest");
    expect(benchmarkConfigFromURL().selection).toBe("densest");
  });

  it("reads pruning thresholds from the query string", () => {
    window.history.replaceState({}, "", "/?knowledgeThreshold=600&fileThreshold=150&activityThreshold=180&overviewThreshold=80");
    expect(benchmarkConfigFromURL().knowledgeThreshold).toBe(600);
  });
});

describe("syntheticKnowledgeGraphPayload", () => {
  it("leaves selection empty by default", () => {
    expect(syntheticKnowledgeGraphPayload({ ...SMALL_BENCHMARK_CONFIG, selection: "none" }).selectedNodeId).toBeNull();
  });

  it("can select a densest node", () => {
    expect(syntheticKnowledgeGraphPayload({ ...SMALL_BENCHMARK_CONFIG, selection: "densest" }).selectedNodeId).not.toBeNull();
  });

  it("assigns at least one non-zero node link count", () => {
    expect(
      Math.max(...syntheticKnowledgeGraphPayload(SMALL_BENCHMARK_CONFIG).nodes.map((node) => node.linkCount))
    ).toBeGreaterThan(0);
  });

  it("includes pruning thresholds in the synthetic payload", () => {
    expect(syntheticKnowledgeGraphPayload(SMALL_BENCHMARK_CONFIG).pruningThresholds.knowledge).toBe(
      SMALL_BENCHMARK_CONFIG.knowledgeThreshold
    );
  });
});

describe("summarizeFrameDurations", () => {
  it("counts frames that miss the 60fps budget", () => {
    expect(summarizeFrameDurations([10, 17, 40], 100).missed60FpsFrames).toBe(2);
  });

  it("counts frames over 33 milliseconds", () => {
    expect(summarizeFrameDurations([10, 17, 40], 100).droppedFramesOver33Ms).toBe(1);
  });

  it("counts frames over 50 milliseconds", () => {
    expect(summarizeFrameDurations([10, 17, 55], 100).severeFramesOver50Ms).toBe(1);
  });
});
