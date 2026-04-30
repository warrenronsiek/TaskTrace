//
//  GraphRAGModels.swift
//  TaskTrace
//

import Foundation
import GRDB

nonisolated enum GraphRAGEntityType: String, Codable, Equatable, Sendable {
    case community
    case node
    case claim
}

nonisolated struct GraphRAGHit: Codable, Equatable, Sendable {
    let entityType: GraphRAGEntityType
    let entityID: Int64
    let nodeID: Int64?
    let communityID: Int64?
    let title: String
    let description: String
    let hybridScore: Double
    let rerankScore: Float
}

nonisolated struct GraphRAGCommunityContext: Codable, Equatable, Sendable {
    let id: Int64
    let name: String?
    let summary: String?
}

nonisolated struct GraphRAGNodeContext: Codable, Equatable, Sendable {
    let id: Int64
    let name: String
    let kind: String?
    let description: String?
    let communityID: Int64?
}

nonisolated struct GraphRAGEdgeContext: Codable, Equatable, Sendable {
    let id: Int64
    let firstNodeID: Int64
    let secondNodeID: Int64
    let relationshipType: String?
    let description: String
}

nonisolated struct GraphRAGClaimContext: Codable, Equatable, Sendable {
    let id: Int64
    let nodeID: Int64
    let text: String
}

nonisolated struct GraphRAGContext: Codable, Equatable, Sendable {
    let communities: [GraphRAGCommunityContext]
    let nodes: [GraphRAGNodeContext]
    let edges: [GraphRAGEdgeContext]
    let claims: [GraphRAGClaimContext]

    nonisolated init(
        communities: [GraphRAGCommunityContext] = [],
        nodes: [GraphRAGNodeContext] = [],
        edges: [GraphRAGEdgeContext] = [],
        claims: [GraphRAGClaimContext] = []
    ) {
        self.communities = communities
        self.nodes = nodes
        self.edges = edges
        self.claims = claims
    }
}

nonisolated struct GraphRAGRetrievalResult: Codable, Equatable, Sendable {
    let query: String
    let hits: [GraphRAGHit]
    let context: GraphRAGContext
}

nonisolated struct GraphRAGHybridCandidateRow: Codable, Equatable, FetchableRecord, Sendable {
    let entityType: String
    let entityID: Int64
    let nodeID: Int64?
    let communityID: Int64?
    let title: String
    let description: String
    let hybridScore: Double

    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case entityID = "entity_id"
        case nodeID = "node_id"
        case communityID = "community_id"
        case title
        case description
        case hybridScore = "hybrid_score"
    }
}
