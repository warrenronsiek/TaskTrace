//
//  ActivityTagOntologyModels.swift
//  TaskTrace
//

import Foundation
import GRDB

nonisolated enum ActivityTagAssignmentSource: String, Codable, Equatable, Sendable {
    case manual
    case ontology
}

nonisolated enum TagOriginKind: String, Codable, Equatable, Sendable {
    case manual
    case ontology
    case system
}

nonisolated enum ActivityTagOntologyDefaults {
    nonisolated static let neighborCount = Vars.activityTagOntologyNeighborCount
    nonisolated static let leidenResolution = 0.05
    nonisolated static let leidenTheta = 0.01
    nonisolated static let continuityAlpha = 0.7
    nonisolated static let continuityBeta = 0.3
    nonisolated static let continuityGamma = 0.6
}

struct ActivityEdgeRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "activity_edges"

    let firstActivityID: Int64
    let secondActivityID: Int64
    let weight: Double

    enum CodingKeys: String, CodingKey {
        case firstActivityID = "first_activity_id"
        case secondActivityID = "second_activity_id"
        case weight
    }

    nonisolated static func canonicalPair(_ firstActivityID: Int64, _ secondActivityID: Int64) -> ActivityEdgePair {
        ActivityEdgePair(firstActivityID: firstActivityID, secondActivityID: secondActivityID)
    }
}

nonisolated struct ActivityEdgePair: Hashable, Sendable {
    let firstActivityID: Int64
    let secondActivityID: Int64

    init(firstActivityID: Int64, secondActivityID: Int64) {
        if firstActivityID < secondActivityID {
            self.firstActivityID = firstActivityID
            self.secondActivityID = secondActivityID
        } else {
            self.firstActivityID = secondActivityID
            self.secondActivityID = firstActivityID
        }
    }
}

struct ActivityTagOntologyRunRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "activity_tag_ontology_runs"

    let id: Int64
    let createdAt: Date
    let previousRunID: Int64?
    let kNeighbors: Int
    let leidenResolution: Double
    let leidenTheta: Double
    let continuityAlpha: Double
    let continuityBeta: Double
    let continuityGamma: Double

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case previousRunID = "previous_run_id"
        case kNeighbors = "k_neighbors"
        case leidenResolution = "leiden_resolution"
        case leidenTheta = "leiden_theta"
        case continuityAlpha = "continuity_alpha"
        case continuityBeta = "continuity_beta"
        case continuityGamma = "continuity_gamma"
    }
}

struct ActivityTagOntologyCandidateRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "activity_tag_ontology_candidates"

    let id: Int64
    let runID: Int64
    let tagID: Int64
    let predecessorCandidateID: Int64?
    let name: String?
    let summary: String?
    let centroidVector: Data?
    let memberCount: Int
    let memberOverlap: Double?
    let centroidSimilarity: Double?
    let continuitySimilarity: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case runID = "run_id"
        case tagID = "tag_id"
        case predecessorCandidateID = "predecessor_candidate_id"
        case name
        case summary
        case centroidVector = "centroid_vector"
        case memberCount = "member_count"
        case memberOverlap = "member_overlap"
        case centroidSimilarity = "centroid_similarity"
        case continuitySimilarity = "continuity_similarity"
    }
}

struct ActivityTagOntologyCandidateActivityRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "activity_tag_ontology_candidate_activities"

    let candidateID: Int64
    let activityID: Int64
    let centralityScore: Double?

    enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case activityID = "activity_id"
        case centralityScore = "centrality_score"
    }
}

nonisolated struct ActivityOntologyAssignment: Equatable, Sendable {
    let activityID: Int64
    let tagID: Int64
    let ontologyCandidateID: Int64
}

nonisolated struct ActivityTagOntologyCandidateInput: Equatable, Sendable {
    let candidateID: Int64
    let tagID: Int64
    let predecessorCandidateID: Int64?
    let name: String?
    let summary: String?
    let centroidVector: Data?
    let memberActivityIDs: [Int64]
    let centralityScoreByActivityID: [Int64: Double]
    let memberOverlap: Double?
    let centroidSimilarity: Double?
    let continuitySimilarity: Double?
}

nonisolated struct ActivityTagOntologyRunInput: Equatable, Sendable {
    let runID: Int64
    let createdAt: Date
    let previousRunID: Int64?
    let candidates: [ActivityTagOntologyCandidateInput]
    let kNeighbors: Int
    let leidenResolution: Double
    let leidenTheta: Double
    let continuityAlpha: Double
    let continuityBeta: Double
    let continuityGamma: Double
}

nonisolated struct ActivityTagOntologyActivitySnapshot: Equatable, Sendable {
    let id: Int64
    let summary: String
    let summaryVector: Data
}

nonisolated struct ActivityTagOntologyCandidateSnapshot: Equatable, Sendable {
    let candidate: ActivityTagOntologyCandidateRecord
    let tag: TagRecord?
    let memberActivityIDs: [Int64]
}

nonisolated struct ActivityTagOntologyRefreshSnapshot: Equatable, Sendable {
    let activities: [ActivityTagOntologyActivitySnapshot]
    let edges: [ActivityEdgeRecord]
    let latestRun: ActivityTagOntologyRunRecord?
    let latestCandidates: [ActivityTagOntologyCandidateSnapshot]
}

nonisolated struct ActivityOntologyCatchUpSnapshot: Equatable, Sendable {
    let latestRunID: Int64?
    let activitiesMissingEmbeddings: [ActivityActor.Activity]
    let activityIDsMissingTags: [Int64]
    let activityIDsMissingOverviews: [Int64]
}

nonisolated struct ActivityTagOntologyGeneratedText: Equatable, Sendable {
    let name: String
    let summary: String
}

extension TagRecord {
    var resolvedOriginKind: TagOriginKind {
        if let originKind,
           let decodedOriginKind = TagOriginKind(rawValue: originKind) {
            return decodedOriginKind
        }

        return SystemTags.isProtected(id) ? .system : .manual
    }
}
