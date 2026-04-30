//
//  KnowledgeGraphModels.swift
//  TaskTrace
//
//  Created by Codex on 4/3/26.
//

import Foundation
import GRDB

struct KnowledgeCommunityRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "knowledge_communities"

    let id: Int64
    let name: String?
    let summary: String?
    let summaryInputHash: String?
    let embedding: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case summary
        case summaryInputHash = "summary_input_hash"
        case embedding
    }
}

struct KnowledgeCommunityLinkRecord: Codable, Equatable, FetchableRecord, Sendable {
    let communityID: Int64
    let nodeID: Int64

    enum CodingKeys: String, CodingKey {
        case communityID = "community_id"
        case nodeID = "node_id"
    }
}

struct KnowledgeNodeRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "knowledge_nodes"

    let id: Int64
    let name: String
    let normalizedName: String
    let kind: String?
    let description: String?
    let sourceChunkID: Int64?
    let embedding: String?
    let communityID: Int64?
    let createDate: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case normalizedName = "normalized_name"
        case kind
        case description
        case sourceChunkID = "source_chunk_id"
        case embedding
        case communityID = "community_id"
        case createDate = "create_date"
    }

    nonisolated static func normalizedName(for value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}

struct KnowledgeNodeInput: Equatable, Sendable {
    let id: Int64
    let name: String
    let normalizedName: String
    let kind: String?
    let description: String?
    let sourceChunkID: Int64?
    let embedding: String?
    let createDate: Date
}

struct KnowledgeEdgeRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "knowledge_edges"

    let id: Int64
    let firstNodeID: Int64
    let secondNodeID: Int64
    let relationshipType: String?
    let description: String
    let sourceChunkID: Int64?
    let createDate: Date

    enum CodingKeys: String, CodingKey {
        case id
        case firstNodeID = "first_node_id"
        case secondNodeID = "second_node_id"
        case relationshipType = "relationship_type"
        case description
        case sourceChunkID = "source_chunk_id"
        case createDate = "create_date"
    }

    nonisolated static func canonicalPair(_ firstNodeID: Int64, _ secondNodeID: Int64) -> KnowledgeEdgePair {
        KnowledgeEdgePair(firstNodeID: firstNodeID, secondNodeID: secondNodeID)
    }
}

nonisolated struct KnowledgeEdgePair: Hashable, Sendable {
    let firstNodeID: Int64
    let secondNodeID: Int64

    init(firstNodeID: Int64, secondNodeID: Int64) {
        if firstNodeID < secondNodeID {
            self.firstNodeID = firstNodeID
            self.secondNodeID = secondNodeID
        } else {
            self.firstNodeID = secondNodeID
            self.secondNodeID = firstNodeID
        }
    }
}

struct KnowledgeEdgeInput: Equatable, Sendable {
    let id: Int64
    let firstNodeID: Int64
    let secondNodeID: Int64
    let relationshipType: String?
    let description: String
    let sourceChunkID: Int64?
    let createDate: Date
}

struct KnowledgeBridgeLinkRecord: Codable, Equatable, FetchableRecord, Sendable {
    let fileID: Int64
    let nodeID: Int64

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case nodeID = "node_id"
    }
}

struct KnowledgeActivityLinkRecord: Codable, Equatable, FetchableRecord, Sendable {
    let activityID: Int64
    let nodeID: Int64

    enum CodingKeys: String, CodingKey {
        case activityID = "activity_id"
        case nodeID = "node_id"
    }
}

struct KnowledgeOverviewLinkRecord: Codable, Equatable, FetchableRecord, Sendable {
    let overviewID: Int64
    let nodeID: Int64

    enum CodingKeys: String, CodingKey {
        case overviewID = "overview_id"
        case nodeID = "node_id"
    }
}

struct KnowledgeClaimRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "knowledge_claims"

    let id: Int64
    let nodeID: Int64
    let text: String
    let md5: String
    let embedding: String?
    let createDate: Date

    enum CodingKeys: String, CodingKey {
        case id
        case nodeID = "node_id"
        case text
        case md5
        case embedding
        case createDate = "create_date"
    }
}

struct KnowledgeClaimInput: Equatable, Sendable {
    let id: Int64
    let nodeID: Int64
    let text: String
    let md5: String
    let createDate: Date
}

struct KnowledgeCommunitySummaryInput: Equatable, Sendable {
    let currentSummary: String?
    let summaryInputHash: String?
    let nodes: [KnowledgeNodeRecord]
    let edges: [KnowledgeEdgeRecord]
    let claimsByNodeID: [Int64: [KnowledgeClaimRecord]]
}

struct KnowledgeObsidianSourceFileReference: Equatable, Sendable {
    let fileID: Int64
    let path: String
    let title: String?
}

struct KnowledgeObsidianRelatedNodeReference: Equatable, Sendable {
    enum Direction: String, Equatable, Sendable {
        case incoming
        case outgoing
    }

    let nodeID: Int64
    let name: String
    let direction: Direction
    let relationshipType: String?
    let description: String
}

enum KnowledgeObsidianExportNaming {
    nonisolated static func fileName(communityName: String) -> String {
        let stem = communityName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "|", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return "\(stem.isEmpty ? "Knowledge Community" : stem).md"
    }

    nonisolated static func anchorKey(sectionTitle: String) -> String {
        let slug = sectionTitle
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")

        return slug.isEmpty ? "section" : slug
    }
}

struct KnowledgeObsidianMemberReference: Equatable, Sendable {
    let nodeID: Int64
    let anchorKey: String
    let name: String
    let description: String?
    let claims: [KnowledgeClaimRecord]
    let sourceFiles: [KnowledgeObsidianSourceFileReference]
    let relatedNodes: [KnowledgeObsidianRelatedNodeReference]
    let edgeLinks: [KnowledgeObsidianEdgeLinkReference]
}

struct KnowledgeObsidianEdgeLinkReference: Equatable, Sendable {
    let communityID: Int64
    let communityName: String
    let targetNodeName: String
    let targetAnchorKey: String
    let relationshipType: String?
    let description: String
}

nonisolated struct KnowledgeObsidianExportTarget: Equatable, Hashable, Sendable {
    let directoryID: Int64
    let communityID: Int64
}

struct KnowledgeObsidianCommunityPayload: Equatable, Sendable {
    let directory: KnowledgeDirectoryRecord
    let community: KnowledgeCommunityRecord
    let members: [KnowledgeObsidianMemberReference]
}
