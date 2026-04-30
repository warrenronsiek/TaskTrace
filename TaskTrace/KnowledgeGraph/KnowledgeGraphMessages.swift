//
//  KnowledgeGraphMessages.swift
//  TaskTrace
//
//  Created by Codex on 4/7/26.
//

import Foundation

struct KnowledgeLoadRequested: Sendable {
    let activeDay: Date
}

struct KnowledgeBuildStarted: Sendable {
    let buildID: Int64
    let directoryID: Int64
}

struct KnowledgeBuildCompleted: Sendable {
    let buildID: Int64
    let directoryID: Int64
}

struct KnowledgeBuildFailed: Sendable {
    let buildID: Int64
    let directoryID: Int64
    let errorMessage: String
}

struct KnowledgeGraphProjectionLoadRequested: Sendable {
    let directoryID: Int64?
}

struct KnowledgeDataInvalidated: Sendable {
    let directoryID: Int64?
}

struct KnowledgeDirectoryCreated: Sendable {
    let directory: KnowledgeDirectoryRecord
}

struct KnowledgeDirectoryDeleted: Sendable {
    let directoryID: Int64
}

struct KnowledgeDirectorySyncRequested: Sendable {
    let directoryID: Int64
}

struct KnowledgeDirectoryScanCompleted: Sendable {
    let buildID: Int64
    let directoryID: Int64
    let retainingPaths: Set<String>
    let deletedAt: Date

    init(
        buildID: Int64,
        directoryID: Int64,
        retainingPaths: Set<String>,
        deletedAt: Date
    ) {
        self.buildID = buildID
        self.directoryID = directoryID
        self.retainingPaths = retainingPaths
        self.deletedAt = deletedAt
    }
}

struct KnowledgeFileCreated: Sendable {
    let buildID: Int64
    let directoryID: Int64
    let file: KnowledgeFileInput

    init(
        buildID: Int64,
        directoryID: Int64,
        file: KnowledgeFileInput
    ) {
        self.buildID = buildID
        self.directoryID = directoryID
        self.file = file
    }
}

struct KnowledgeFileIndexed: Sendable {
    let buildID: Int64
    let fileID: Int64
}

struct KnowledgeFileSelected: Sendable {
    let path: String
}

struct KnowledgeFileAccessed: Sendable {
    let fileID: Int64
    let lastAccessed: Date
}

struct KnowledgeFileIndexReset: Sendable {
    let fileID: Int64
}

struct KnowledgeAliasCreated: Sendable {
    let fileID: Int64
    let alias: KnowledgeAliasInput
}

struct KnowledgeAnchorCreated: Sendable {
    let buildID: Int64
    let fileID: Int64
    let anchor: KnowledgeAnchorInput
    let scannedAnchor: KnowledgeScannedAnchor

    init(
        buildID: Int64,
        fileID: Int64,
        anchor: KnowledgeAnchorInput,
        scannedAnchor: KnowledgeScannedAnchor
    ) {
        self.buildID = buildID
        self.fileID = fileID
        self.anchor = anchor
        self.scannedAnchor = scannedAnchor
    }
}

struct KnowledgeChunkCreated: Sendable {
    let buildID: Int64
    let fileID: Int64
    let anchorID: Int64
    let anchorKey: String
    let chunk: KnowledgeChunkInput
    let scannedChunk: KnowledgeScannedChunk

    init(
        buildID: Int64,
        fileID: Int64,
        anchorID: Int64,
        anchorKey: String,
        chunk: KnowledgeChunkInput,
        scannedChunk: KnowledgeScannedChunk
    ) {
        self.buildID = buildID
        self.fileID = fileID
        self.anchorID = anchorID
        self.anchorKey = anchorKey
        self.chunk = chunk
        self.scannedChunk = scannedChunk
    }
}

struct KnowledgeChunkGraphProcessed: Sendable {
    let buildID: Int64?
    let chunkID: Int64
    let success: Bool
}

struct KnowledgeChunkEncodeRequested: Sendable {
    let buildID: Int64?
    let fileID: Int64
    let anchorID: Int64
    let anchorKey: String
    let chunk: KnowledgeChunkInput
    let scannedChunk: KnowledgeScannedChunk

    nonisolated init(
        buildID: Int64? = nil,
        fileID: Int64,
        anchorID: Int64,
        anchorKey: String,
        chunk: KnowledgeChunkInput,
        scannedChunk: KnowledgeScannedChunk
    ) {
        self.buildID = buildID
        self.fileID = fileID
        self.anchorID = anchorID
        self.anchorKey = anchorKey
        self.chunk = chunk
        self.scannedChunk = scannedChunk
    }
}

enum KnowledgeGraphSource: Sendable {
    case chunk(KnowledgeChunkInput)
    case activity(activityID: Int64)

    nonisolated var logDescription: String {
        switch self {
        case .chunk(let chunk):
            return "chunkID=\(chunk.id)"
        case .activity(let activityID):
            return "activityID=\(activityID)"
        }
    }
}

struct KnowledgeNodeCreated: Sendable {
    let buildID: Int64?
    let source: KnowledgeGraphSource
    let node: KnowledgeNodeInput

    init(
        buildID: Int64? = nil,
        source: KnowledgeGraphSource,
        node: KnowledgeNodeInput
    ) {
        self.buildID = buildID
        self.source = source
        self.node = node
    }
}

struct ActivityKnowledgeEncodeRequested: Sendable {
    let activityID: Int64
    let summary: String
}

struct ActivityKnowledgeEncoded: Sendable {
    let activityID: Int64
    let success: Bool
}

struct CoalesceKnowledgeNode: Sendable {
    let buildID: Int64?
    let source: KnowledgeGraphSource
    let existingNode: KnowledgeNodeRecord
    let incomingNode: KnowledgeNodeInput

    init(
        buildID: Int64? = nil,
        source: KnowledgeGraphSource,
        existingNode: KnowledgeNodeRecord,
        incomingNode: KnowledgeNodeInput
    ) {
        self.buildID = buildID
        self.source = source
        self.existingNode = existingNode
        self.incomingNode = incomingNode
    }
}

struct UpdateKnowledgeNode: Sendable {
    let buildID: Int64?
    let source: KnowledgeGraphSource
    let node: KnowledgeNodeInput

    init(
        buildID: Int64? = nil,
        source: KnowledgeGraphSource,
        node: KnowledgeNodeInput
    ) {
        self.buildID = buildID
        self.source = source
        self.node = node
    }
}

struct KnowledgeNodeEmbedded: Sendable {
    let buildID: Int64?
    let nodeID: Int64
    let vector: [Float]

    init(
        buildID: Int64? = nil,
        nodeID: Int64,
        vector: [Float]
    ) {
        self.buildID = buildID
        self.nodeID = nodeID
        self.vector = vector
    }
}

struct KnowledgeEdgeCreated: Sendable {
    let buildID: Int64?
    let source: KnowledgeGraphSource
    let edge: KnowledgeEdgeInput

    init(
        buildID: Int64? = nil,
        source: KnowledgeGraphSource,
        edge: KnowledgeEdgeInput
    ) {
        self.buildID = buildID
        self.source = source
        self.edge = edge
    }
}

struct CoalesceKnowledgeEdge: Sendable {
    let buildID: Int64?
    let source: KnowledgeGraphSource
    let existingEdge: KnowledgeEdgeRecord
    let incomingEdge: KnowledgeEdgeInput

    init(
        buildID: Int64? = nil,
        source: KnowledgeGraphSource,
        existingEdge: KnowledgeEdgeRecord,
        incomingEdge: KnowledgeEdgeInput
    ) {
        self.buildID = buildID
        self.source = source
        self.existingEdge = existingEdge
        self.incomingEdge = incomingEdge
    }
}

struct UpdateKnowledgeEdge: Sendable {
    let source: KnowledgeGraphSource
    let edge: KnowledgeEdgeInput
}

struct CommunitiesGenerated: Sendable {
    let buildID: Int64?
    let communityByNodeID: [Int64: Int64]

    init(
        buildID: Int64? = nil,
        communityByNodeID: [Int64: Int64]
    ) {
        self.buildID = buildID
        self.communityByNodeID = communityByNodeID
    }
}

struct CommunitySummarized: Sendable {
    let buildID: Int64?
    let communityID: Int64
    let name: String
    let summary: String
    let inputHash: String
}

struct CommunityEmbedded: Sendable {
    let buildID: Int64?
    let communityID: Int64
    let vector: [Float]
}

struct RebuildCommunities: Sendable {
    let resolution: Double
    let theta: Double
}

struct RebuildKnowledge: Sendable {
    let directoryID: Int64
}

struct RebuildActivityKnowledge: Sendable {
    let activeDay: Date
}

struct ReplayActivityKnowledge: Sendable {
    let activeDay: Date
}

struct KnowledgeClaimCreated: Sendable {
    let buildID: Int64?
    let source: KnowledgeGraphSource
    let claim: KnowledgeClaimInput
}

struct KnowledgeClaimEmbedded: Sendable {
    let claimID: Int64
    let vector: [Float]
}

struct KnowledgeLinkCreated: Sendable {
    let fileID: Int64
    let link: KnowledgeLinkInput
    let scannedLink: KnowledgeScannedLink
}
