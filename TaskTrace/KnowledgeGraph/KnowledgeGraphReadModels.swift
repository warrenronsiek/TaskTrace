//
//  KnowledgeGraphReadModels.swift
//  TaskTrace
//

import Foundation
import GRDB

nonisolated struct KnowledgeFileSystemEntry: Codable, Equatable, FetchableRecord, Identifiable, Sendable {
    let id: Int64
    let directoryID: Int64
    let sourceSlot: KnowledgeSourceSlot
    let path: String
    let title: String?
    let byteCount: Int64
    let totalChunks: Int
    let processedChunks: Int
    let totalNodeEmbeddings: Int
    let embeddedNodeCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case directoryID = "directory_id"
        case sourceSlot = "source_slot"
        case path
        case title
        case byteCount = "byte_count"
        case totalChunks = "total_chunks"
        case processedChunks = "processed_chunks"
        case totalNodeEmbeddings = "total_node_embeddings"
        case embeddedNodeCount = "embedded_node_count"
    }

    nonisolated var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    nonisolated var treePath: String {
        "\(sourceSlot.rawValue)/\(path)"
    }

    nonisolated var pendingChunkGraphs: Int {
        max(totalChunks - processedChunks, 0)
    }

    nonisolated var pendingNodeEmbeddings: Int {
        max(totalNodeEmbeddings - embeddedNodeCount, 0)
    }

    nonisolated var isComplete: Bool {
        pendingChunkGraphs == 0 && pendingNodeEmbeddings == 0
    }

    nonisolated var statusLabel: String {
        if totalChunks == 0 {
            return "Indexed"
        }

        if pendingChunkGraphs > 0 {
            return "Extracting graph"
        }

        if pendingNodeEmbeddings > 0 {
            return "Embedding nodes"
        }

        return "Ready"
    }

    nonisolated var progressFraction: Double {
        if isComplete {
            return 1
        }

        let chunkFraction = totalChunks > 0
            ? Double(processedChunks) / Double(max(totalChunks, 1))
            : 1
        let embeddingFraction = totalNodeEmbeddings > 0
            ? Double(embeddedNodeCount) / Double(max(totalNodeEmbeddings, 1))
            : 1

        if pendingChunkGraphs > 0 {
            return min(0.18 + (chunkFraction * 0.57), 0.75)
        }

        return min(0.76 + (embeddingFraction * 0.19), 0.95)
    }
}

nonisolated struct KnowledgeFileGraphLinkRecord: Codable, Equatable, FetchableRecord, Sendable {
    let sourceFileID: Int64
    let targetFileID: Int64
    let weight: Int

    enum CodingKeys: String, CodingKey {
        case sourceFileID = "source_file_id"
        case targetFileID = "target_file_id"
        case weight
    }
}

nonisolated struct KnowledgeGraphNodeEntry: Codable, Equatable, FetchableRecord, Identifiable, Sendable {
    let id: Int64
    let name: String
    let kind: String?
    let description: String?
    let communityID: Int64?
    let sourcePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case description
        case communityID = "community_id"
        case sourcePath = "source_path"
    }
}

nonisolated struct KnowledgeGraphOverviewEntry: Codable, Equatable, FetchableRecord, Identifiable, Sendable {
    let id: Int64
    let title: String
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
    }
}

nonisolated struct KnowledgeGraphActivityEntry: Codable, Equatable, FetchableRecord, Identifiable, Sendable {
    let id: Int64
    let overviewID: Int64?
    let application: String
    let summary: String?
    let startTime: Date

    enum CodingKeys: String, CodingKey {
        case id
        case overviewID = "overview_id"
        case application
        case summary
        case startTime = "start_time"
    }
}

nonisolated struct KnowledgeGraphDirectorySnapshot: Codable, Equatable, Sendable {
    let fileLinks: [KnowledgeFileGraphLinkRecord]
    let knowledgeNodes: [KnowledgeGraphNodeEntry]
    let knowledgeEdges: [KnowledgeEdgeRecord]
    let communities: [KnowledgeCommunityRecord]
    let overviews: [KnowledgeGraphOverviewEntry]
    let activities: [KnowledgeGraphActivityEntry]

    nonisolated init(
        fileLinks: [KnowledgeFileGraphLinkRecord] = [],
        knowledgeNodes: [KnowledgeGraphNodeEntry] = [],
        knowledgeEdges: [KnowledgeEdgeRecord] = [],
        communities: [KnowledgeCommunityRecord] = [],
        overviews: [KnowledgeGraphOverviewEntry] = [],
        activities: [KnowledgeGraphActivityEntry] = []
    ) {
        self.fileLinks = fileLinks
        self.knowledgeNodes = knowledgeNodes
        self.knowledgeEdges = knowledgeEdges
        self.communities = communities
        self.overviews = overviews
        self.activities = activities
    }
}
