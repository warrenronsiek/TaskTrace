import Foundation
import GRDB
import MLXLMCommon
import Testing
@testable import TaskTrace

@MainActor
struct GraphRAGTests {
    private struct GraphRAGFixture {
        let database: TaskTraceDatabase
        let knowledgeReadDatabase: KnowledgeReadDatabase
        let directoryID: Int64
    }

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

    private func withGraphRAGFixture(
        _ block: (GraphRAGFixture) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let knowledgeDatabaseActor = KnowledgeDatabaseActor(
            database: database,
            actorSystem: ActorSystem()
        )
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let vector: [Float] = {
            var value = Array(repeating: Float(0), count: 1024)
            value[0] = 1
            return value
        }()

        try await knowledgeDatabaseActor.saveKnowledgeDirectory(
            KnowledgeDirectoryInput(
                id: 1,
                slot: .obsidianVault,
                path: "/tmp/Knowledge",
                bookmarkData: nil,
                createdAt: now
            )
        )
        try await knowledgeDatabaseActor.saveKnowledgeFile(
            KnowledgeFileInput(
                id: 2,
                directoryID: 1,
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

        let firstNode = KnowledgeNodeInput(
            id: 10,
            name: "OpenFang memory",
            normalizedName: KnowledgeNodeRecord.normalizedName(for: "OpenFang memory"),
            kind: "concept",
            description: "OpenFang memory architecture and retrieval graph coordination.",
            sourceChunkID: 4,
            embedding: nil,
            createDate: now
        )
        let secondNode = KnowledgeNodeInput(
            id: 11,
            name: "Graph retrieval",
            normalizedName: KnowledgeNodeRecord.normalizedName(for: "Graph retrieval"),
            kind: "system",
            description: "Graph retrieval ranks communities, nodes, and claims for memory questions.",
            sourceChunkID: 4,
            embedding: nil,
            createDate: now
        )

        try await knowledgeDatabaseActor.saveKnowledgeNode(firstNode)
        try await knowledgeDatabaseActor.saveKnowledgeNode(secondNode)
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
        try await knowledgeDatabaseActor.saveKnowledgeClaim(
            KnowledgeClaimInput(
                id: 301,
                nodeID: 11,
                text: "Graph retrieval reranks communities, nodes, and claims together.",
                md5: "claim-301",
                createDate: now
            )
        )
        try await knowledgeDatabaseActor.updateKnowledgeNodeEmbedding(nodeID: 10, vector: vector)
        try await knowledgeDatabaseActor.updateKnowledgeNodeEmbedding(nodeID: 11, vector: vector)
        try await knowledgeDatabaseActor.updateCommunityEmbedding(communityID: 200, vector: vector)
        try await knowledgeDatabaseActor.updateKnowledgeClaimEmbedding(claimID: 300, vector: vector)
        try await knowledgeDatabaseActor.updateKnowledgeClaimEmbedding(claimID: 301, vector: vector)

        try await block(
            GraphRAGFixture(
                database: database,
                knowledgeReadDatabase: try KnowledgeReadDatabase(database: database),
                directoryID: 1
            )
        )
    }

    @Test("knowledge node embeddings use a blob column after migration")
    func knowledgeNodeEmbeddingsUseABlobColumnAfterMigration() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let embeddingType = try database.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(knowledge_nodes)")
                .first { ($0["name"] as String?) == "embedding" }?["type"] as String?
        }

        #expect(embeddingType == "BLOB")
    }

    @Test("graph rag candidate retrieval returns community node and claim hits")
    func graphRAGCandidateRetrievalReturnsCommunityNodeAndClaimHits() async throws {
        try await withGraphRAGFixture { fixture in
            let vectorJSONString = String(
                decoding: try JSONEncoder().encode({
                    var value = Array(repeating: Float(0), count: 1024)
                    value[0] = 1
                    return value
                }()),
                as: UTF8.self
            )

            let candidates = try fixture.knowledgeReadDatabase.loadGraphRAGCandidates(
                directoryID: fixture.directoryID,
                ftsQuery: "openfang memory",
                queryVectorJSONString: vectorJSONString,
                perSourceLimit: 6,
                totalLimit: 12
            )

            #expect(Set(candidates.map(\.entityType)) == Set(["community", "node", "claim"]))
        }
    }

    @Test("graph rag service retrieval returns the internal edge context")
    func graphRAGServiceRetrievalReturnsTheInternalEdgeContext() async throws {
        try await withGraphRAGFixture { fixture in
            let queryVector: [Float] = {
                var value = Array(repeating: Float(0), count: 1024)
                value[0] = 1
                return value
            }()
            let service = GraphRAGService(
                knowledgeReadDatabase: fixture.knowledgeReadDatabase,
                embeddingGenerator: FixedEmbeddingGenerator(vector: queryVector),
                rerankingGenerator: FixedRerankingGenerator(),
                textStreamingGenerator: EmptyStreamingGenerator()
            )

            let retrieval = try await service.retrieve(
                query: "How does OpenFang memory use graph retrieval?",
                directoryID: fixture.directoryID,
                topN: 3
            )

            #expect(retrieval.context.edges.map(\.id) == [20])
        }
    }
}
