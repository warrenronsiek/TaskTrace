//
//  GraphRAGMCPToolTests.swift
//  TaskTraceTests
//
//  Created by Codex on 4/12/26.
//

import Foundation
import MCP
import MLXLMCommon
import Testing
@testable import TaskTrace

@MainActor
struct GraphRAGMCPToolTests {
    private struct FixedEmbeddingGenerator: ActivityEmbeddingGenerating {
        let vector: [Float]

        func generateVectors(for texts: [String], promptPrefix: String?) async -> [[Float]] {
            texts.map { _ in vector }
        }
    }

    private struct FixedRerankingGenerator: ActivityRerankingGenerating {
        func generateRerankings(
            query: String,
            documents: [String],
            instruction: String
        ) async -> [ActivityAIReranking] {
            documents.enumerated().map { index, _ in
                ActivityAIReranking(documentIndex: index, score: Float(documents.count - index))
            }
        }
    }

    private struct EmptyStreamingGenerator: ActivityTextStreamingGenerating {
        func streamResponse(
            prompt: String,
            instructions: String,
            generateParameters: GenerateParameters,
            traceStartedAt: Date?
        ) async -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }

    private func withRuntime(
        _ block: (OverviewMCPServerRuntime, Int64) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
        let vector: [Float] = {
            var value = Array(repeating: Float(0), count: 1024)
            value[0] = 1
            return value
        }()
        let now = Date(timeIntervalSince1970: 1_775_000_000)

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let knowledgeDatabaseActor = KnowledgeDatabaseActor(
            database: database,
            actorSystem: ActorSystem()
        )
        let directoryID: Int64 = 1
        let alternateDirectoryID: Int64 = 101

        try await knowledgeDatabaseActor.saveKnowledgeDirectory(
            KnowledgeDirectoryInput(
                id: directoryID,
                slot: .obsidianVault,
                path: "/tmp/Knowledge",
                bookmarkData: nil,
                createdAt: now
            )
        )
        try await knowledgeDatabaseActor.saveKnowledgeFile(
            KnowledgeFileInput(
                id: 2,
                directoryID: directoryID,
                path: "OpenFang.md",
                title: "OpenFang",
                hash: "file-hash",
                modifiedAt: now,
                createDate: now,
                lastAccessed: nil,
                metadataJSON: nil,
                deletedAt: nil,
                byteCount: 128
            )
        )
        try await knowledgeDatabaseActor.insertKnowledgeAnchor(
            KnowledgeAnchorInput(
                id: 3,
                fileID: 2,
                anchorType: "heading",
                anchorKey: "openfang-memory",
                headingText: "OpenFang memory",
                blockID: nil,
                startLine: 1,
                endLine: 4,
                textHash: "anchor-hash"
            )
        )
        try await knowledgeDatabaseActor.insertKnowledgeChunk(
            KnowledgeChunkInput(
                id: 4,
                anchorID: 3,
                ordinal: 0,
                hash: "chunk-hash",
                text: "OpenFang memory architecture keeps graph context and retrieval state coherent."
            )
        )
        try await knowledgeDatabaseActor.saveKnowledgeNode(
            KnowledgeNodeInput(
                id: 10,
                name: "OpenFang memory",
                normalizedName: KnowledgeNodeRecord.normalizedName(for: "OpenFang memory"),
                kind: "concept",
                description: "OpenFang memory architecture and retrieval graph coordination.",
                sourceChunkID: 4,
                embedding: nil,
                createDate: now
            )
        )
        try await knowledgeDatabaseActor.saveKnowledgeNode(
            KnowledgeNodeInput(
                id: 11,
                name: "Graph retrieval",
                normalizedName: KnowledgeNodeRecord.normalizedName(for: "Graph retrieval"),
                kind: "system",
                description: "Graph retrieval ranks communities, nodes, and claims for memory questions.",
                sourceChunkID: 4,
                embedding: nil,
                createDate: now
            )
        )
        try await knowledgeDatabaseActor.saveNodeChunk(nodeID: 10, chunkID: 4)
        try await knowledgeDatabaseActor.saveNodeChunk(nodeID: 11, chunkID: 4)
        try await knowledgeDatabaseActor.saveKnowledgeEdge(
            KnowledgeEdgeInput(
                id: 20,
                firstNodeID: 10,
                secondNodeID: 11,
                relationshipType: "supports",
                description: "OpenFang memory supports graph retrieval for related claims.",
                sourceChunkID: 4,
                createDate: now
            )
        )
        try await knowledgeDatabaseActor.saveEdgeChunk(edgeID: 20, chunkID: 4)
        try await knowledgeDatabaseActor.saveCommunities(
            communityByNodeID: [
                10: 200,
                11: 200
            ]
        )
        try await knowledgeDatabaseActor.updateCommunitySummary(
            communityID: 200,
            name: "OpenFang memory systems",
            summary: "Community about OpenFang memory architecture and graph retrieval.",
            inputHash: "community-200-openfang"
        )
        try await knowledgeDatabaseActor.saveKnowledgeClaim(
            KnowledgeClaimInput(
                id: 300,
                nodeID: 10,
                text: "OpenFang memory persists retrieval context across graph updates.",
                md5: "claim-300",
                createDate: now
            )
        )
        try await knowledgeDatabaseActor.updateKnowledgeNodeEmbedding(nodeID: 10, vector: vector)
        try await knowledgeDatabaseActor.updateKnowledgeNodeEmbedding(nodeID: 11, vector: vector)
        try await knowledgeDatabaseActor.updateCommunityEmbedding(communityID: 200, vector: vector)
        try await knowledgeDatabaseActor.updateKnowledgeClaimEmbedding(claimID: 300, vector: vector)
        try await knowledgeDatabaseActor.saveKnowledgeDirectory(
            KnowledgeDirectoryInput(
                id: alternateDirectoryID,
                slot: .taskTraceIngest,
                path: "/tmp/DecoyKnowledge",
                bookmarkData: nil,
                createdAt: now
            )
        )
        try await knowledgeDatabaseActor.saveKnowledgeFile(
            KnowledgeFileInput(
                id: 102,
                directoryID: alternateDirectoryID,
                path: "Decoy.md",
                title: "Decoy",
                hash: "decoy-file-hash",
                modifiedAt: now,
                createDate: now,
                lastAccessed: nil,
                metadataJSON: nil,
                deletedAt: nil,
                byteCount: 128
            )
        )
        try await knowledgeDatabaseActor.insertKnowledgeAnchor(
            KnowledgeAnchorInput(
                id: 103,
                fileID: 102,
                anchorType: "heading",
                anchorKey: "decoy-payments-memory",
                headingText: "Decoy payments memory",
                blockID: nil,
                startLine: 1,
                endLine: 4,
                textHash: "decoy-anchor-hash"
            )
        )
        try await knowledgeDatabaseActor.insertKnowledgeChunk(
            KnowledgeChunkInput(
                id: 104,
                anchorID: 103,
                ordinal: 0,
                hash: "decoy-chunk-hash",
                text: "Decoy payments memory tracks invoice retries and failed billing retries."
            )
        )
        try await knowledgeDatabaseActor.saveKnowledgeNode(
            KnowledgeNodeInput(
                id: 110,
                name: "Decoy payments memory",
                normalizedName: KnowledgeNodeRecord.normalizedName(for: "Decoy payments memory"),
                kind: "concept",
                description: "Decoy directory node about invoice retries and failed billing recovery.",
                sourceChunkID: 104,
                embedding: nil,
                createDate: now
            )
        )
        try await knowledgeDatabaseActor.saveNodeChunk(nodeID: 110, chunkID: 104)
        try await knowledgeDatabaseActor.saveCommunities(
            communityByNodeID: [
                110: 400
            ]
        )
        try await knowledgeDatabaseActor.updateCommunitySummary(
            communityID: 400,
            name: "Decoy payments systems",
            summary: "Community about invoice retries and billing recovery.",
            inputHash: "community-400-decoy"
        )
        try await knowledgeDatabaseActor.updateKnowledgeNodeEmbedding(nodeID: 110, vector: vector)
        try await knowledgeDatabaseActor.updateCommunityEmbedding(communityID: 400, vector: vector)

        let runtime = OverviewMCPServerRuntime(
            graphRAGService: GraphRAGService(
                knowledgeReadDatabase: try KnowledgeReadDatabase(database: database),
                embeddingGenerator: FixedEmbeddingGenerator(vector: vector),
                rerankingGenerator: FixedRerankingGenerator(),
                textStreamingGenerator: EmptyStreamingGenerator()
            )
        )

        try await block(runtime, directoryID)
    }

    @Test("tool list includes the graph rag tool when graph retrieval is enabled")
    func toolListIncludesTheGraphRAGToolWhenGraphRetrievalIsEnabled() async throws {
        try await withRuntime { runtime, _ in
            await runtime.update(
                activeDay: Date(timeIntervalSince1970: 0),
                overviews: [],
                activities: [],
                configuration: .default
            )

            #expect((await runtime.toolNames()).contains(Vars.mcpGraphRAGToolName))
        }
    }

    @Test("graph rag tool calls are rejected when graph retrieval is disabled")
    func graphRAGToolCallsAreRejectedWhenGraphRetrievalIsDisabled() async throws {
        try await withRuntime { runtime, _ in
            var configuration = SettingsStore.MCPConfiguration.default
            configuration.graphSearchToolEnabled = false

            await runtime.update(
                activeDay: Date(timeIntervalSince1970: 0),
                overviews: [],
                activities: [],
                configuration: configuration
            )

            await #expect(throws: MCPError.self) {
                _ = try await runtime.callGraphRAGTool(query: "openfang memory", limit: 3)
            }
        }
    }

    @Test("graph rag tool returns retrieved graph context without summarization")
    func graphRAGToolReturnsRetrievedGraphContextWithoutSummarization() async throws {
        try await withRuntime { runtime, _ in
            await runtime.update(
                activeDay: Date(timeIntervalSince1970: 0),
                overviews: [],
                activities: [],
                configuration: .default
            )

            let response = try await runtime.callGraphRAGTool(
                query: "How does OpenFang memory use graph retrieval?",
                limit: 3
            )

            #expect(response.context.edges.map(\.id) == [20])
        }
    }

    @Test("graph rag tool retrieves across configured knowledge sources")
    func graphRAGToolRetrievesAcrossConfiguredKnowledgeSources() async throws {
        try await withRuntime { runtime, _ in
            await runtime.update(
                activeDay: Date(timeIntervalSince1970: 0),
                overviews: [],
                activities: [],
                configuration: .default
            )

            let response = try await runtime.callGraphRAGTool(
                query: "decoy payments memory",
                limit: 3
            )

            #expect(response.context.nodes.map(\.id).contains(110))
        }
    }
}
