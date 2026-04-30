import Foundation
import GRDB
import MLXLMCommon
import Testing
@testable import TaskTrace

@MainActor
struct KnowledgeObsidianWriterActorTests {
    @Test("obsidian direct summary output budget is one hundred sixty tokens")
    func obsidianDirectSummaryOutputBudgetIsOneHundredSixtyTokens() {
        #expect(KnowledgeObsidianWriterActor.directSummaryMaxTokens == 160)
    }

    @Test("obsidian chunk summary output budget is one hundred twenty tokens")
    func obsidianChunkSummaryOutputBudgetIsOneHundredTwentyTokens() {
        #expect(KnowledgeObsidianWriterActor.chunkSummaryMaxTokens == 120)
    }

    private struct PromptRecord: Sendable {
        let prompt: String
        let instructions: String
    }

    private actor StubKnowledgeObsidianTextResponder: AITextResponding, Receiver {
        private let actorSystem: ActorSystem
        private var records: [PromptRecord] = []

        init(actorSystem: ActorSystem) {
            self.actorSystem = actorSystem
        }

        func receive(_ envelope: Envelope) async {
            guard let request = envelope.message as? ModelTextRequest else {
                return
            }

            records.append(
                PromptRecord(
                    prompt: request.prompt,
                    instructions: request.instructions
                )
            )

            let now = Date()
            await actorSystem.broadcast(
                from: nil,
                message: ModelTextCompleted(
                    requestID: request.requestID,
                    response: "Summary: Stub member summary.",
                    schedulerMetadata: AISchedulerMetadata(
                        scheduler: .textBig,
                        bucket: "test",
                        batchSize: 1,
                        source: request.source
                    ),
                    timing: AISchedulerTiming(
                        queuedAt: now,
                        startedAt: now,
                        finishedAt: now
                    )
                )
            )
        }

        func respond(
            prompt: String,
            instructions: String,
            generateParameters: GenerateParameters,
            additionalContext: [String: any Sendable]?
        ) async throws -> String {
            records.append(
                PromptRecord(
                    prompt: prompt,
                    instructions: instructions
                )
            )

            return "Summary: Stub member summary."
        }

        func requests() -> [PromptRecord] {
            records
        }
    }

    private struct Fixture {
        let database: TaskTraceDatabase
        let knowledgeDatabaseActor: KnowledgeDatabaseActor
        let writer: KnowledgeObsidianWriterActor
        let textResponder: StubKnowledgeObsidianTextResponder
        let exportDirectoryURL: URL
    }

    private func withKnowledgeDatabase(
        _ block: (TaskTraceDatabase, KnowledgeDatabaseActor, ActorSystem) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let actorSystem = ActorSystem()
        let knowledgeDatabaseActor = KnowledgeDatabaseActor(
            database: database,
            actorSystem: actorSystem
        )

        try await block(database, knowledgeDatabaseActor, actorSystem)
    }

    private func withKnowledgeObsidianFixture(
        _ block: (Fixture) async throws -> Void
    ) async throws {
        try await withKnowledgeDatabase { database, knowledgeDatabaseActor, actorSystem in
            let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let now = Date(timeIntervalSince1970: 1_776_000_000)

            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            try "Alpha".write(
                to: directoryURL.appendingPathComponent("Alpha.md"),
                atomically: true,
                encoding: .utf8
            )
            try "Beta".write(
                to: directoryURL.appendingPathComponent("Beta.md"),
                atomically: true,
                encoding: .utf8
            )
            try "Gamma".write(
                to: directoryURL.appendingPathComponent("Gamma.md"),
                atomically: true,
                encoding: .utf8
            )

            try await knowledgeDatabaseActor.saveKnowledgeDirectory(
                KnowledgeDirectoryInput(
                    id: 1,
                    slot: .obsidianVault,
                    path: directoryURL.path,
                    bookmarkData: nil,
                    createdAt: now
                )
            )

            let files = [
                KnowledgeFileInput(
                    id: 11,
                    directoryID: 1,
                    path: "Alpha.md",
                    title: "Alpha",
                    hash: "alpha-hash",
                    modifiedAt: now,
                    createDate: now,
                    lastAccessed: nil,
                    metadataJSON: nil,
                    deletedAt: nil,
                    byteCount: 5
                ),
                KnowledgeFileInput(
                    id: 12,
                    directoryID: 1,
                    path: "Beta.md",
                    title: "Beta",
                    hash: "beta-hash",
                    modifiedAt: now,
                    createDate: now,
                    lastAccessed: nil,
                    metadataJSON: nil,
                    deletedAt: nil,
                    byteCount: 4
                ),
                KnowledgeFileInput(
                    id: 13,
                    directoryID: 1,
                    path: "Gamma.md",
                    title: "Gamma",
                    hash: "gamma-hash",
                    modifiedAt: now,
                    createDate: now,
                    lastAccessed: nil,
                    metadataJSON: nil,
                    deletedAt: nil,
                    byteCount: 5
                )
            ]

            for file in files {
                try await knowledgeDatabaseActor.saveKnowledgeFile(file)
            }

            let anchors = [
                KnowledgeAnchorInput(
                    id: 21,
                    fileID: 11,
                    anchorType: "heading",
                    anchorKey: "alpha",
                    headingText: "Alpha",
                    blockID: nil,
                    startLine: 1,
                    endLine: 1,
                    textHash: "anchor-alpha"
                ),
                KnowledgeAnchorInput(
                    id: 22,
                    fileID: 12,
                    anchorType: "heading",
                    anchorKey: "beta",
                    headingText: "Beta",
                    blockID: nil,
                    startLine: 1,
                    endLine: 1,
                    textHash: "anchor-beta"
                ),
                KnowledgeAnchorInput(
                    id: 23,
                    fileID: 13,
                    anchorType: "heading",
                    anchorKey: "gamma",
                    headingText: "Gamma",
                    blockID: nil,
                    startLine: 1,
                    endLine: 1,
                    textHash: "anchor-gamma"
                )
            ]

            for anchor in anchors {
                try await knowledgeDatabaseActor.insertKnowledgeAnchor(anchor)
            }

            let chunks = [
                KnowledgeChunkInput(
                    id: 31,
                    anchorID: 21,
                    ordinal: 0,
                    hash: "chunk-alpha",
                    text: "Alpha Analyst coordinates workflow memory."
                ),
                KnowledgeChunkInput(
                    id: 32,
                    anchorID: 22,
                    ordinal: 0,
                    hash: "chunk-beta",
                    text: "Workflow Memory records durable task context."
                ),
                KnowledgeChunkInput(
                    id: 33,
                    anchorID: 23,
                    ordinal: 0,
                    hash: "chunk-gamma",
                    text: "Billing Ledger stores billing state."
                )
            ]

            for chunk in chunks {
                try await knowledgeDatabaseActor.insertKnowledgeChunk(chunk)
                try await knowledgeDatabaseActor.markKnowledgeChunkProcessed(chunkID: chunk.id, processed: true)
            }

            let nodes = [
                KnowledgeNodeInput(
                    id: 101,
                    name: "Alpha Analyst",
                    normalizedName: KnowledgeNodeRecord.normalizedName(for: "Alpha Analyst"),
                    kind: "person",
                    description: "Alpha Analyst coordinates workflow memory.",
                    sourceChunkID: 31,
                    embedding: nil,
                    createDate: now
                ),
                KnowledgeNodeInput(
                    id: 102,
                    name: "Workflow Memory",
                    normalizedName: KnowledgeNodeRecord.normalizedName(for: "Workflow Memory"),
                    kind: "system",
                    description: "Workflow Memory records durable task context.",
                    sourceChunkID: 32,
                    embedding: nil,
                    createDate: now
                ),
                KnowledgeNodeInput(
                    id: 201,
                    name: "Billing Ledger",
                    normalizedName: KnowledgeNodeRecord.normalizedName(for: "Billing Ledger"),
                    kind: "system",
                    description: "Billing Ledger stores billing state.",
                    sourceChunkID: 33,
                    embedding: nil,
                    createDate: now
                )
            ]

            for node in nodes {
                try await knowledgeDatabaseActor.saveKnowledgeNode(node)
            }

            try await knowledgeDatabaseActor.saveNodeChunk(nodeID: 101, chunkID: 31)
            try await knowledgeDatabaseActor.saveNodeChunk(nodeID: 102, chunkID: 32)
            try await knowledgeDatabaseActor.saveNodeChunk(nodeID: 201, chunkID: 33)

            try await knowledgeDatabaseActor.saveKnowledgeClaim(
                KnowledgeClaimInput(
                    id: 401,
                    nodeID: 101,
                    text: "Alpha Analyst coordinates workflow memory.",
                    md5: "claim-alpha",
                    createDate: now
                )
            )
            try await knowledgeDatabaseActor.saveKnowledgeClaim(
                KnowledgeClaimInput(
                    id: 402,
                    nodeID: 102,
                    text: "Workflow Memory records durable task context.",
                    md5: "claim-beta",
                    createDate: now
                )
            )
            try await knowledgeDatabaseActor.saveKnowledgeClaim(
                KnowledgeClaimInput(
                    id: 403,
                    nodeID: 201,
                    text: "Billing Ledger stores billing state.",
                    md5: "claim-gamma",
                    createDate: now
                )
            )

            try await knowledgeDatabaseActor.saveKnowledgeEdge(
                KnowledgeEdgeInput(
                    id: 501,
                    firstNodeID: 101,
                    secondNodeID: 102,
                    relationshipType: "supports",
                    description: "Alpha Analyst supports Workflow Memory.",
                    sourceChunkID: 31,
                    createDate: now
                )
            )
            try await knowledgeDatabaseActor.saveKnowledgeEdge(
                KnowledgeEdgeInput(
                    id: 502,
                    firstNodeID: 102,
                    secondNodeID: 201,
                    relationshipType: "syncs_with",
                    description: "Workflow Memory syncs with Billing Ledger.",
                    sourceChunkID: 32,
                    createDate: now
                )
            )

            try await knowledgeDatabaseActor.saveCommunities(
                communityByNodeID: [
                    101: 100,
                    102: 100,
                    201: 200
                ]
            )
            try await knowledgeDatabaseActor.updateCommunitySummary(
                communityID: 100,
                name: "Workflow Systems",
                summary: "Workflow systems collect durable task context.",
                inputHash: "community-100-workflow"
            )
            try await knowledgeDatabaseActor.updateCommunitySummary(
                communityID: 200,
                name: "Billing Systems",
                summary: "Billing systems store billing state.",
                inputHash: "community-200-billing"
            )

            let textResponder = StubKnowledgeObsidianTextResponder(actorSystem: actorSystem)
            _ = await actorSystem.register(textResponder)
            let writer = KnowledgeObsidianWriterActor(
                actorSystem: actorSystem,
                knowledgeDatabaseActor: knowledgeDatabaseActor,
                textResponder: textResponder
            )
            _ = await actorSystem.register(writer)

            try await block(
                Fixture(
                    database: database,
                    knowledgeDatabaseActor: knowledgeDatabaseActor,
                    writer: writer,
                    textResponder: textResponder,
                    exportDirectoryURL: directoryURL.appendingPathComponent("TaskTrace", isDirectory: true)
                )
            )
        }
    }

    private func withOversizedObsidianFixture(
        _ block: (Fixture) async throws -> Void
    ) async throws {
        try await withKnowledgeObsidianFixture { fixture in
            let now = Date(timeIntervalSince1970: 1_776_000_100)
            let longClaimText = String(
                repeating: "Alpha Analyst records durable workflow memory details for a large connected work system. ",
                count: 2_000
            )

            try await fixture.knowledgeDatabaseActor.saveKnowledgeClaim(
                KnowledgeClaimInput(
                    id: 9_101,
                    nodeID: 101,
                    text: longClaimText,
                    md5: "claim-9101",
                    createDate: now
                )
            )

            try await block(fixture)
        }
    }

    private func export(
        _ target: KnowledgeObsidianExportTarget,
        using writer: KnowledgeObsidianWriterActor
    ) async {
        await writer.receive(Envelope(sender: nil, message: target))
        await writer.waitForQuiescence()
    }

    @Test("community summaries persist unique names when labels collide")
    func communitySummariesPersistUniqueNamesWhenLabelsCollide() async throws {
        try await withKnowledgeDatabase { database, knowledgeDatabaseActor, _ in
            let now = Date(timeIntervalSince1970: 1_776_100_000)

            try await knowledgeDatabaseActor.saveKnowledgeNode(
                KnowledgeNodeInput(
                    id: 1,
                    name: "Alpha",
                    normalizedName: KnowledgeNodeRecord.normalizedName(for: "Alpha"),
                    kind: nil,
                    description: nil,
                    sourceChunkID: nil,
                    embedding: nil,
                    createDate: now
                )
            )
            try await knowledgeDatabaseActor.saveKnowledgeNode(
                KnowledgeNodeInput(
                    id: 2,
                    name: "Beta",
                    normalizedName: KnowledgeNodeRecord.normalizedName(for: "Beta"),
                    kind: nil,
                    description: nil,
                    sourceChunkID: nil,
                    embedding: nil,
                    createDate: now
                )
            )
            try await knowledgeDatabaseActor.saveCommunities(communityByNodeID: [1: 100, 2: 200])
            try await knowledgeDatabaseActor.updateCommunitySummary(
                communityID: 100,
                name: "Project Memory",
                summary: "Alpha summary.",
                inputHash: "community-100-project"
            )
            try await knowledgeDatabaseActor.updateCommunitySummary(
                communityID: 200,
                name: "Project Memory",
                summary: "Beta summary.",
                inputHash: "community-200-project"
            )

            let names = try database.read { db in
                try String.fetchAll(
                    db,
                    sql: "SELECT name FROM knowledge_communities ORDER BY id ASC"
                )
            }

            #expect(names == ["Project Memory", "Project Memory 2"])
        }
    }

    @Test("obsidian writer replaces legacy node markdown with one file per community")
    func obsidianWriterReplacesLegacyNodeMarkdownWithOneFilePerCommunity() async throws {
        try await withKnowledgeObsidianFixture { fixture in
            try FileManager.default.createDirectory(at: fixture.exportDirectoryURL, withIntermediateDirectories: true)
            try "legacy".write(
                to: fixture.exportDirectoryURL.appendingPathComponent("Alpha Analyst.md"),
                atomically: true,
                encoding: .utf8
            )

            await export(
                KnowledgeObsidianExportTarget(directoryID: 1, communityID: 100),
                using: fixture.writer
            )
            await export(
                KnowledgeObsidianExportTarget(directoryID: 1, communityID: 200),
                using: fixture.writer
            )

            let fileNames = try FileManager.default
                .contentsOfDirectory(at: fixture.exportDirectoryURL, includingPropertiesForKeys: nil)
                .map(\.lastPathComponent)
                .sorted()

            #expect(fileNames == ["Billing Systems.md", "Workflow Systems.md"])
        }
    }

    @Test("obsidian writer groups community members into a single markdown file")
    func obsidianWriterGroupsCommunityMembersIntoASingleMarkdownFile() async throws {
        try await withKnowledgeObsidianFixture { fixture in
            await export(
                KnowledgeObsidianExportTarget(directoryID: 1, communityID: 100),
                using: fixture.writer
            )

            let markdown = try String(
                contentsOf: fixture.exportDirectoryURL.appendingPathComponent("Workflow Systems.md"),
                encoding: .utf8
            )

            #expect(markdown.contains("### Alpha Analyst") && markdown.contains("### Workflow Memory"))
        }
    }

    @Test("obsidian writer renders deterministic node anchors")
    func obsidianWriterRendersDeterministicNodeAnchors() async throws {
        try await withKnowledgeObsidianFixture { fixture in
            await export(
                KnowledgeObsidianExportTarget(directoryID: 1, communityID: 100),
                using: fixture.writer
            )

            let markdown = try String(
                contentsOf: fixture.exportDirectoryURL.appendingPathComponent("Workflow Systems.md"),
                encoding: .utf8
            )

            #expect(markdown.contains("<a id=\"workflow-memory\"></a>\n### Workflow Memory"))
        }
    }

    @Test("obsidian writer links same-community edges to node anchors")
    func obsidianWriterLinksSameCommunityEdgesToNodeAnchors() async throws {
        try await withKnowledgeObsidianFixture { fixture in
            await export(
                KnowledgeObsidianExportTarget(directoryID: 1, communityID: 100),
                using: fixture.writer
            )

            let markdown = try String(
                contentsOf: fixture.exportDirectoryURL.appendingPathComponent("Workflow Systems.md"),
                encoding: .utf8
            )

            #expect(markdown.contains("#### Relationships\n- [Alpha Analyst supports Workflow Memory.](<#workflow-memory>)"))
        }
    }

    @Test("obsidian writer links cross-community edges to node anchors")
    func obsidianWriterLinksCrossCommunityEdgesToNodeAnchors() async throws {
        try await withKnowledgeObsidianFixture { fixture in
            await export(
                KnowledgeObsidianExportTarget(directoryID: 1, communityID: 100),
                using: fixture.writer
            )

            let markdown = try String(
                contentsOf: fixture.exportDirectoryURL.appendingPathComponent("Workflow Systems.md"),
                encoding: .utf8
            )

            #expect(markdown.contains("#### Relationships\n- [Workflow Memory syncs with Billing Ledger.](<Billing Systems.md#billing-ledger>)"))
        }
    }

    @Test("obsidian recursive member summary keeps every prompt under hard limit")
    func obsidianRecursiveMemberSummaryKeepsEveryPromptUnderHardLimit() async throws {
        try await withOversizedObsidianFixture { fixture in
            await export(
                KnowledgeObsidianExportTarget(directoryID: 1, communityID: 100),
                using: fixture.writer
            )

            let requests = await fixture.textResponder.requests()
            let markdownExists = FileManager.default.fileExists(
                atPath: fixture.exportDirectoryURL.appendingPathComponent("Workflow Systems.md").path
            )
            let promptsUnderLimit = requests.allSatisfy {
                AIRecursivePromptReducer.promptTokenEstimate(
                    prompt: $0.prompt,
                    instructions: $0.instructions
                ) <= AIRecursivePromptReducer.knowledgeSummaryTokenBudget.hardTokenLimit
            }

            #expect(markdownExists && promptsUnderLimit)
        }
    }

    @Test("obsidian recursive member summary uses multiple AI calls for oversized input")
    func obsidianRecursiveMemberSummaryUsesMultipleAICallsForOversizedInput() async throws {
        try await withOversizedObsidianFixture { fixture in
            await export(
                KnowledgeObsidianExportTarget(directoryID: 1, communityID: 100),
                using: fixture.writer
            )

            let requests = await fixture.textResponder.requests()

            #expect(requests.count > 2)
        }
    }
}
