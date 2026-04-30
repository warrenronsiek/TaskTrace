//
//  KnowledgeFileBuildProgress.swift
//  TaskTrace
//

import Foundation

struct KnowledgeFileBuildProgress: Equatable, Sendable {
    let buildID: Int64?
    let isIndexing: Bool
    let emittedChunkGraphs: Int
    let completedChunkGraphs: Int
    let emittedNodeEmbeddings: Int
    let completedNodeEmbeddings: Int

    nonisolated init(
        buildID: Int64? = nil,
        isIndexing: Bool = false,
        emittedChunkGraphs: Int = 0,
        completedChunkGraphs: Int = 0,
        emittedNodeEmbeddings: Int = 0,
        completedNodeEmbeddings: Int = 0
    ) {
        self.buildID = buildID
        self.isIndexing = isIndexing
        self.emittedChunkGraphs = emittedChunkGraphs
        self.completedChunkGraphs = completedChunkGraphs
        self.emittedNodeEmbeddings = emittedNodeEmbeddings
        self.completedNodeEmbeddings = completedNodeEmbeddings
    }

    nonisolated var pendingChunkGraphs: Int {
        max(emittedChunkGraphs - completedChunkGraphs, 0)
    }

    nonisolated var pendingNodeEmbeddings: Int {
        max(emittedNodeEmbeddings - completedNodeEmbeddings, 0)
    }

    nonisolated var isComplete: Bool {
        !isIndexing && pendingChunkGraphs == 0 && pendingNodeEmbeddings == 0
    }

    nonisolated var statusLabel: String {
        if isIndexing {
            return "Indexing"
        }

        if pendingChunkGraphs > 0 {
            return "Extracting graph"
        }

        if pendingNodeEmbeddings > 0 {
            return "Embedding nodes"
        }

        if emittedChunkGraphs > 0 || emittedNodeEmbeddings > 0 {
            return "Ready"
        }

        return "Indexed"
    }

    nonisolated var progressFraction: Double {
        if isComplete {
            return 1
        }

        let chunkFraction = emittedChunkGraphs > 0
            ? Double(completedChunkGraphs) / Double(max(emittedChunkGraphs, 1))
            : 1
        let embeddingFraction = emittedNodeEmbeddings > 0
            ? Double(completedNodeEmbeddings) / Double(max(emittedNodeEmbeddings, 1))
            : 1

        if isIndexing {
            return 0.12
        }

        if pendingChunkGraphs > 0 {
            return min(0.2 + (chunkFraction * 0.55), 0.75)
        }

        if pendingNodeEmbeddings > 0 {
            return min(0.75 + (embeddingFraction * 0.2), 0.95)
        }

        return 0.98
    }
}
