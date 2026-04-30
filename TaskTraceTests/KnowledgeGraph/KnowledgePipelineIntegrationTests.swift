import Foundation
import GRDB
import MLXLMCommon
import Testing
@testable import TaskTrace

@MainActor
struct KnowledgePipelineIntegrationTests {
    private struct Fixture {
        let database: TaskTraceDatabase
        let actorSystem: ActorSystem
        let knowledgeGraphActor: KnowledgeGraphActor
        let knowledgeReadDatabase: KnowledgeReadDatabase
        let knowledgeDatabaseActor: KnowledgeDatabaseActor
        let collector: EventCollector
        let directoryID: Int64
    }

    private struct BacklogFixture {
        let database: TaskTraceDatabase
        let actorSystem: ActorSystem
        let textScheduler: BlockingKnowledgeTextScheduler
        let chunkGraphActor: KnowledgeChunkGraphActor
        let directoryID: Int64
    }

    private struct DirectorySyncFixture {
        let database: TaskTraceDatabase
        let actorSystem: ActorSystem
        let knowledgeGraphActor: KnowledgeGraphActor
        let knowledgeDatabaseActor: KnowledgeDatabaseActor
        let directoryID: Int64
    }

    private enum FixtureError: Error {
        case timedOut
    }

    actor EventCollector: Receiver {
        private var countsByMessageType: [String: Int] = [:]

        func receive(_ envelope: Envelope) async {
            let messageType = await MainActor.run {
                String(reflecting: type(of: envelope.message))
            }
            countsByMessageType[messageType, default: 0] += 1
        }

        func count<Message>(_ type: Message.Type) -> Int {
            countsByMessageType[String(reflecting: type), default: 0]
        }

        func deterministicPipelineCounts() -> (
            chunks: Int,
            nodes: Int,
            claims: Int,
            edges: Int,
            nodeEmbeddings: Int,
            claimEmbeddings: Int
        ) {
            (
                count(KnowledgeChunkCreated.self),
                count(KnowledgeNodeCreated.self),
                count(KnowledgeClaimCreated.self),
                count(KnowledgeEdgeCreated.self),
                count(KnowledgeNodeEmbedded.self),
                count(KnowledgeClaimEmbedded.self)
            )
        }
    }

    private actor FixedKnowledgeTextScheduler: Receiver {
        private let actorSystem: ActorSystem

        init(actorSystem: ActorSystem) {
            self.actorSystem = actorSystem
        }

        func receive(_ envelope: Envelope) async {
            guard let request = envelope.message as? ModelTextRequest else {
                return
            }

            let now = Date()
            await actorSystem.broadcast(
                from: nil,
                message: ModelTextCompleted(
                    requestID: request.requestID,
                    response: response(for: request.prompt),
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

        private func response(for prompt: String) -> String {
            if prompt.contains("Alice Example works on Acme Platform") {
                return """
                ## Entities
                Name: Alice Example
                Type: person
                Description: Alice Example works on Acme Platform memory workflows.
                Claims:
                - Alice Example works on Acme Platform memory workflows.
                ---
                Name: Acme Platform
                Type: product
                Description: Acme Platform stores workflow memory for task replay.
                Claims:
                - Acme Platform stores workflow memory for task replay.

                ## Relationships
                Source: Alice Example
                Target: Acme Platform
                Type: works_on
                Description: Alice Example works on Acme Platform.
                """
            }

            if prompt.contains("Bob Example works on Beta Ledger") {
                return """
                ## Entities
                Name: Bob Example
                Type: person
                Description: Bob Example maintains Beta Ledger memory operations.
                Claims:
                - Bob Example maintains Beta Ledger memory operations.
                ---
                Name: Beta Ledger
                Type: product
                Description: Beta Ledger stores billing memory for reconciliation tasks.
                Claims:
                - Beta Ledger stores billing memory for reconciliation tasks.

                ## Relationships
                Source: Bob Example
                Target: Beta Ledger
                Type: maintains
                Description: Bob Example maintains Beta Ledger.
                """
            }

            if prompt.contains("Alice Example") && prompt.contains("Acme Platform") {
                return """
                Name: Alpha Memory Systems
                Summary: Alpha memory systems connect Alice Example to Acme Platform and describe workflow memory handling.
                """
            }

            if prompt.contains("Bob Example") && prompt.contains("Beta Ledger") {
                return """
                Name: Beta Memory Systems
                Summary: Beta memory systems connect Bob Example to Beta Ledger and describe billing memory handling.
                """
            }

            return """
            ## Entities
            (none)

            ## Relationships
            (none)
            """
        }
    }

    private actor BlockingKnowledgeTextScheduler: Receiver {
        private let actorSystem: ActorSystem
        private var released = false
        private var continuations: [CheckedContinuation<Void, Never>] = []

        init(actorSystem: ActorSystem) {
            self.actorSystem = actorSystem
        }

        func receive(_ envelope: Envelope) async {
            guard let request = envelope.message as? ModelTextRequest else {
                return
            }

            if !released {
                await withCheckedContinuation { continuation in
                    continuations.append(continuation)
                }
            }

            let now = Date()
            await actorSystem.broadcast(
                from: nil,
                message: ModelTextCompleted(
                    requestID: request.requestID,
                    response: """
                    ## Entities
                    (none)

                    ## Relationships
                    (none)
                    """,
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

        func releaseAll() {
            released = true
            continuations.forEach { $0.resume() }
            continuations.removeAll()
        }

        func blockedCount() -> Int {
            continuations.count
        }
    }

    private struct FixedKnowledgeEmbeddingGenerator: ActivityEmbeddingGenerating {
        private let alphaVector = Self.vector(index: 0)
        private let betaVector = Self.vector(index: 1)

        static func vector(index: Int) -> [Float] {
            var vector = Array(repeating: Float(0), count: 1024)
            vector[index] = 1
            return vector
        }

        func generateVectors(for texts: [String], promptPrefix: String?) async -> [[Float]] {
            texts.map {
                let normalized = AITextUtilities.prefixedText($0, promptPrefix: promptPrefix).lowercased()
                return normalized.contains("alice")
                    || normalized.contains("acme")
                    || normalized.contains("alpha")
                    ? alphaVector
                    : betaVector
            }
        }
    }

    private func withCompletedKnowledgePipeline(
        _ block: (Fixture) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
        let knowledgeURL = rootURL.appendingPathComponent("Knowledge", isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let directoryID: Int64 = 1
        let actorSystem = ActorSystem()
        let identifierActor = IdentifierActor(now: { now }, latestIdentifier: 10_000)
        let collector = EventCollector()
        let textScheduler = FixedKnowledgeTextScheduler(actorSystem: actorSystem)
        let embeddingGenerator = FixedKnowledgeEmbeddingGenerator()

        try FileManager.default.createDirectory(at: knowledgeURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let knowledgeReadDatabase = try KnowledgeReadDatabase(database: database)
        let activityDatabaseActor = ActivityDatabaseActor(database: database)
        let knowledgeDatabaseActor = KnowledgeDatabaseActor(database: database, actorSystem: actorSystem)
        let knowledgeGraphActor = KnowledgeGraphActor(
            activityDatabaseActor: activityDatabaseActor,
            knowledgeDatabaseActor: knowledgeDatabaseActor,
            actorSystem: actorSystem,
            identifierActor: identifierActor,
            now: { now }
        )
        let buildTracker = KnowledgeBuildTrackerActor(actorSystem: actorSystem)
        let communityDetectionActor = KnowledgeCommunityDetectionActor(
            actorSystem: actorSystem,
            knowledgeDatabaseActor: knowledgeDatabaseActor,
            computeCommunities: { nodes, _, _, _ in
                let alphaNodeIDs = nodes
                    .filter { $0.name.contains("Alice") || $0.name.contains("Acme") }
                    .map(\.id)
                let betaNodeIDs = nodes
                    .filter { $0.name.contains("Bob") || $0.name.contains("Beta") }
                    .map(\.id)
                return Dictionary(
                    uniqueKeysWithValues:
                        (alphaNodeIDs.count >= 2 ? alphaNodeIDs.map { ($0, Int64(100)) } : [])
                        + (betaNodeIDs.count >= 2 ? betaNodeIDs.map { ($0, Int64(200)) } : [])
                )
            }
        )
        let chunkGraphActor = KnowledgeChunkGraphActor(
            actorSystem: actorSystem,
            knowledgeDatabaseActor: knowledgeDatabaseActor,
            activityDatabaseActor: activityDatabaseActor,
            identifierActor: identifierActor,
            now: { now }
        )
        let nodeEmbeddingActor = KnowledgeNodeEmbeddingActor(
            actorSystem: actorSystem,
            embeddingGenerator: embeddingGenerator
        )
        let claimEmbeddingActor = KnowledgeClaimEmbeddingActor(
            actorSystem: actorSystem,
            embeddingGenerator: embeddingGenerator
        )
        let communitySummaryActor = KnowledgeCommunitySummaryActor(
            actorSystem: actorSystem,
            knowledgeDatabaseActor: knowledgeDatabaseActor,
        )
        let communityEmbeddingActor = KnowledgeCommunityEmbeddingActor(
            actorSystem: actorSystem,
            embeddingGenerator: embeddingGenerator
        )

        _ = await actorSystem.register(collector)
        _ = await actorSystem.register(activityDatabaseActor)
        _ = await actorSystem.register(textScheduler)
        _ = await actorSystem.register(knowledgeDatabaseActor)
        _ = await actorSystem.register(knowledgeGraphActor)
        _ = await actorSystem.register(buildTracker)
        _ = await actorSystem.register(communityDetectionActor)
        _ = await actorSystem.register(chunkGraphActor)
        _ = await actorSystem.register(nodeEmbeddingActor)
        _ = await actorSystem.register(claimEmbeddingActor)
        _ = await actorSystem.register(communitySummaryActor)
        _ = await actorSystem.register(communityEmbeddingActor)

        try """
        # Alpha

        Alice Example works on Acme Platform. Alice Example says Acme Platform keeps workflow memory durable.
        """.write(
            to: knowledgeURL.appendingPathComponent("Alpha.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # Beta

        Bob Example works on Beta Ledger. Bob Example says Beta Ledger keeps billing memory durable.
        """.write(
            to: knowledgeURL.appendingPathComponent("Beta.md"),
            atomically: true,
            encoding: .utf8
        )

        await actorSystem.broadcast(
            from: nil,
            message: KnowledgeDirectoryCreated(
                directory: KnowledgeDirectoryRecord(
                    id: directoryID,
                    slot: .obsidianVault,
                    path: knowledgeURL.path,
                    bookmarkData: nil,
                    createdAt: now
                )
            )
        )

        let startedAt = Date()
        while Date().timeIntervalSince(startedAt) < 10 {
            let isComplete = try database.read { db in
                let counts = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT
                            (SELECT COUNT(*) FROM knowledge_chunks) AS chunk_count,
                            (SELECT COUNT(*) FROM knowledge_chunks WHERE processed = 1) AS processed_chunk_count,
                            (SELECT COUNT(*) FROM knowledge_nodes WHERE embedding IS NOT NULL) AS embedded_node_count,
                            (SELECT COUNT(*) FROM knowledge_claims WHERE embedding IS NOT NULL) AS embedded_claim_count,
                            (SELECT COUNT(*) FROM knowledge_communities WHERE summary IS NOT NULL) AS summarized_community_count,
                            (SELECT COUNT(*) FROM knowledge_communities WHERE embedding IS NOT NULL) AS embedded_community_count
                        """
                )
                let chunkCount = (counts?["chunk_count"] as Int64?) ?? 0
                let processedChunkCount = (counts?["processed_chunk_count"] as Int64?) ?? 0
                let embeddedNodeCount = (counts?["embedded_node_count"] as Int64?) ?? 0
                let embeddedClaimCount = (counts?["embedded_claim_count"] as Int64?) ?? 0
                let summarizedCommunityCount = (counts?["summarized_community_count"] as Int64?) ?? 0
                let embeddedCommunityCount = (counts?["embedded_community_count"] as Int64?) ?? 0
                let completionSnapshot = (
                    chunkCount,
                    processedChunkCount,
                    embeddedNodeCount,
                    embeddedClaimCount,
                    summarizedCommunityCount,
                    embeddedCommunityCount
                )

                return completionSnapshot == (2, 2, 4, 4, 2, 2)
            }

            if isComplete {
        try await block(
            Fixture(
                database: database,
                actorSystem: actorSystem,
                knowledgeGraphActor: knowledgeGraphActor,
                knowledgeReadDatabase: knowledgeReadDatabase,
                knowledgeDatabaseActor: knowledgeDatabaseActor,
                collector: collector,
                directoryID: directoryID
            )
                )
                return
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        throw FixtureError.timedOut
    }

    private func withBlockedKnowledgeChunkBacklog(
        _ block: (BacklogFixture) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
        let knowledgeURL = rootURL.appendingPathComponent("Knowledge", isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_775_100_000)
        let directoryID: Int64 = 2
        let actorSystem = ActorSystem()
        let identifierActor = IdentifierActor(now: { now }, latestIdentifier: 20_000)
        let textScheduler = BlockingKnowledgeTextScheduler(actorSystem: actorSystem)

        try FileManager.default.createDirectory(at: knowledgeURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let activityDatabaseActor = ActivityDatabaseActor(database: database)
        let knowledgeDatabaseActor = KnowledgeDatabaseActor(database: database, actorSystem: actorSystem)
        let knowledgeGraphActor = KnowledgeGraphActor(
            activityDatabaseActor: activityDatabaseActor,
            knowledgeDatabaseActor: knowledgeDatabaseActor,
            actorSystem: actorSystem,
            identifierActor: identifierActor,
            now: { now }
        )
        let chunkGraphActor = KnowledgeChunkGraphActor(
            actorSystem: actorSystem,
            knowledgeDatabaseActor: knowledgeDatabaseActor,
            activityDatabaseActor: activityDatabaseActor,
            identifierActor: identifierActor,
            now: { now }
        )

        _ = await actorSystem.register(knowledgeDatabaseActor)
        _ = await actorSystem.register(textScheduler)
        _ = await actorSystem.register(activityDatabaseActor)
        _ = await actorSystem.register(knowledgeGraphActor)
        _ = await actorSystem.register(chunkGraphActor)

        try (1...20)
            .map { "Paragraph \($0) explains durable workflow memory for the same system." }
            .joined(separator: "\n\n")
            .write(
                to: knowledgeURL.appendingPathComponent("Backlog.md"),
                atomically: true,
                encoding: .utf8
            )

        await actorSystem.broadcast(
            from: nil,
            message: KnowledgeDirectoryCreated(
                directory: KnowledgeDirectoryRecord(
                    id: directoryID,
                    slot: .obsidianVault,
                    path: knowledgeURL.path,
                    bookmarkData: nil,
                    createdAt: now
                )
            )
        )

        let startedAt = Date()
        while Date().timeIntervalSince(startedAt) < 10 {
            let chunkCount = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM knowledge_chunks") ?? 0
            }
            let blockedCount = await textScheduler.blockedCount()

            if chunkCount == 20,
               blockedCount == 20 {
                defer { Task { await textScheduler.releaseAll() } }
                try await block(
                    BacklogFixture(
                        database: database,
                        actorSystem: actorSystem,
                        textScheduler: textScheduler,
                        chunkGraphActor: chunkGraphActor,
                        directoryID: directoryID
                    )
                )
                return
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        throw FixtureError.timedOut
    }

    private func withDirectorySyncFixture(
        files: [(path: String, content: String)] = [],
        bookmarkData: Data? = nil,
        seedExistingFile: KnowledgeFileInput? = nil,
        _ block: (DirectorySyncFixture) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
        let knowledgeURL = rootURL.appendingPathComponent("Knowledge", isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_775_200_000)
        let directoryID: Int64 = 3
        let actorSystem = ActorSystem()
        let identifierActor = IdentifierActor(now: { now }, latestIdentifier: 30_000)

        try FileManager.default.createDirectory(at: knowledgeURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let activityDatabaseActor = ActivityDatabaseActor(database: database)
        let knowledgeDatabaseActor = KnowledgeDatabaseActor(database: database, actorSystem: actorSystem)
        let knowledgeGraphActor = KnowledgeGraphActor(
            activityDatabaseActor: activityDatabaseActor,
            knowledgeDatabaseActor: knowledgeDatabaseActor,
            actorSystem: actorSystem,
            identifierActor: identifierActor,
            now: { now }
        )
        let directory = KnowledgeDirectoryRecord(
            id: directoryID,
            slot: .obsidianVault,
            path: knowledgeURL.path,
            bookmarkData: bookmarkData,
            createdAt: now
        )

        try files.forEach { file in
            let fileURL = knowledgeURL.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        if let seedExistingFile {
            try await knowledgeDatabaseActor.saveKnowledgeDirectory(KnowledgeDirectoryInput(
                id: directory.id,
                slot: directory.slot,
                path: directory.path,
                bookmarkData: directory.bookmarkData,
                createdAt: directory.createdAt
            ))
            try await knowledgeDatabaseActor.saveKnowledgeFile(seedExistingFile)
        }

        _ = await actorSystem.register(knowledgeDatabaseActor)
        _ = await actorSystem.register(knowledgeGraphActor)

        await actorSystem.broadcast(
            from: nil,
            message: KnowledgeDirectoryCreated(directory: directory)
        )

        try await block(
            DirectorySyncFixture(
                database: database,
                actorSystem: actorSystem,
                knowledgeGraphActor: knowledgeGraphActor,
                knowledgeDatabaseActor: knowledgeDatabaseActor,
                directoryID: directoryID
            )
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () async throws -> Bool
    ) async throws {
        let startedAt = Date()

        while Date().timeIntervalSince(startedAt) < timeout {
            if try await condition() {
                return
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        throw FixtureError.timedOut
    }

    @Test("knowledge pipeline persists file chunk rows and marks chunks processed")
    func knowledgePipelinePersistsFileChunkRowsAndMarksChunksProcessed() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            let snapshot = try fixture.database.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT
                            (SELECT COUNT(*) FROM knowledge_files WHERE directory_id = ?) AS file_count,
                            (SELECT COUNT(*) FROM knowledge_chunks) AS chunk_count,
                            (SELECT COUNT(*) FROM knowledge_chunks WHERE processed = 1) AS processed_chunk_count
                        """,
                    arguments: [fixture.directoryID]
                )

                return (
                    (row?["file_count"] as Int64?) ?? 0,
                    (row?["chunk_count"] as Int64?) ?? 0,
                    (row?["processed_chunk_count"] as Int64?) ?? 0
                )
            }

            #expect(snapshot == (2, 2, 2))
        }
    }

    @Test("knowledge pipeline persists nodes claims edges and source joins")
    func knowledgePipelinePersistsNodesClaimsEdgesAndSourceJoins() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            let snapshot = try fixture.database.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT
                            (SELECT COUNT(*) FROM knowledge_nodes) AS node_count,
                            (SELECT COUNT(*) FROM knowledge_claims) AS claim_count,
                            (SELECT COUNT(*) FROM knowledge_edges) AS edge_count,
                            (SELECT COUNT(*) FROM knowledge_node_chunks) AS node_chunk_count,
                            (SELECT COUNT(*) FROM knowledge_edge_chunks) AS edge_chunk_count
                    """
                )

                return (
                    (row?["node_count"] as Int64?) ?? 0,
                    (row?["claim_count"] as Int64?) ?? 0,
                    (row?["edge_count"] as Int64?) ?? 0,
                    (row?["node_chunk_count"] as Int64?) ?? 0,
                    (row?["edge_chunk_count"] as Int64?) ?? 0
                )
            }

            #expect(snapshot == (4, 4, 2, 4, 2))
        }
    }

    @Test("knowledge pipeline persists node claim and community embeddings")
    func knowledgePipelinePersistsNodeClaimAndCommunityEmbeddings() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            let snapshot = try fixture.database.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT
                            (SELECT COUNT(*) FROM knowledge_nodes WHERE embedding IS NOT NULL) AS embedded_node_count,
                            (SELECT COUNT(*) FROM knowledge_claims WHERE embedding IS NOT NULL) AS embedded_claim_count,
                            (SELECT COUNT(*) FROM knowledge_communities WHERE embedding IS NOT NULL) AS embedded_community_count
                    """
                )

                return (
                    (row?["embedded_node_count"] as Int64?) ?? 0,
                    (row?["embedded_claim_count"] as Int64?) ?? 0,
                    (row?["embedded_community_count"] as Int64?) ?? 0
                )
            }

            #expect(snapshot == (4, 4, 2))
        }
    }

    @Test("knowledge pipeline persists community assignments and summaries")
    func knowledgePipelinePersistsCommunityAssignmentsAndSummaries() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            let snapshot = try fixture.database.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT
                            (SELECT COUNT(*) FROM knowledge_nodes WHERE community_id IS NOT NULL) AS assigned_node_count,
                            (SELECT COUNT(*) FROM knowledge_communities WHERE summary IS NOT NULL) AS summarized_community_count,
                            (SELECT COUNT(*) FROM knowledge_communities WHERE name IS NOT NULL) AS named_community_count
                    """
                )

                return (
                    (row?["assigned_node_count"] as Int64?) ?? 0,
                    (row?["summarized_community_count"] as Int64?) ?? 0,
                    (row?["named_community_count"] as Int64?) ?? 0
                )
            }

            #expect(snapshot == (4, 2, 2))
        }
    }

    @Test("knowledge pipeline emits deterministic extraction and embedding events once per entity stage")
    func knowledgePipelineEmitsDeterministicExtractionAndEmbeddingEventsOncePerEntityStage() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            #expect(await fixture.collector.deterministicPipelineCounts() == (2, 4, 4, 2, 4, 4))
        }
    }

    @Test("directory sync clears scan state after graph events")
    func directorySyncClearsScanStateAfterGraphEvents() async throws {
        try await withDirectorySyncFixture(files: [
            (
                path: "One.md",
                content: """
                # One

                One keeps a durable note.
                """
            )
        ]) { fixture in
            #expect(await fixture.knowledgeGraphActor.scanStateCountsForTesting() == .empty)
        }
    }

    @Test("directory sync failure clears scan state")
    func directorySyncFailureClearsScanState() async throws {
        let now = Date(timeIntervalSince1970: 1_775_200_000)

        try await withDirectorySyncFixture(
            bookmarkData: Data("not a bookmark".utf8),
            seedExistingFile: KnowledgeFileInput(
                id: 30_100,
                directoryID: 3,
                path: "Seed.md",
                title: "Seed",
                hash: "seed",
                modifiedAt: now,
                createDate: now,
                lastAccessed: nil,
                metadataJSON: #"{"content_type":"markdown"}"#,
                deletedAt: nil,
                byteCount: 4
            )
        ) { fixture in
            #expect(await fixture.knowledgeGraphActor.scanStateCountsForTesting() == .empty)
        }
    }

    @Test("directory sync resolves links before clearing scan state")
    func directorySyncResolvesLinksBeforeClearingScanState() async throws {
        try await withDirectorySyncFixture(files: [
            (
                path: "01 Target.md",
                content: """
                # Target

                Target note.
                """
            ),
            (
                path: "02 Source.md",
                content: """
                # Source

                Link to [[01 Target]].
                """
            )
        ]) { fixture in
            try await waitUntil {
                try fixture.database.read { db in
                    (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM knowledge_links") ?? 0) == 1
                }
            }

            let snapshot = try fixture.database.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT
                            (SELECT COUNT(*) FROM knowledge_links) AS link_count,
                            (SELECT COUNT(*) FROM knowledge_links WHERE dst_file_id IS NULL) AS unresolved_count
                        """
                )

                return (
                    (row?["link_count"] as Int64?) ?? 0,
                    (row?["unresolved_count"] as Int64?) ?? 0
                )
            }

            #expect(snapshot == (1, 0))
        }
    }

    @Test("knowledge pipeline vectors make the alpha community win the final graph retrieval")
    func knowledgePipelineVectorsMakeTheAlphaCommunityWinTheFinalGraphRetrieval() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            let queryVectorJSONString = String(
                decoding: try JSONEncoder().encode(FixedKnowledgeEmbeddingGenerator.vector(index: 0)),
                as: UTF8.self
            )
            let candidates = try fixture.knowledgeReadDatabase.loadGraphRAGCandidates(
                directoryID: fixture.directoryID,
                ftsQuery: "memory",
                queryVectorJSONString: queryVectorJSONString,
                perSourceLimit: 6,
                totalLimit: 12
            )

            #expect(Set(candidates.prefix(3).compactMap(\.communityID)) == Set([100]))
        }
    }

    @Test("simple markdown ingestion persists the expected file anchor and chunk counts")
    func simpleMarkdownIngestionPersistsExpectedCounts() async throws {
        try await withBlockedKnowledgeChunkBacklog { fixture in
            let snapshot = try fixture.database.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT
                            (SELECT COUNT(*) FROM knowledge_files WHERE directory_id = ?) AS file_count,
                            (SELECT COUNT(*) FROM knowledge_anchors) AS anchor_count,
                            (SELECT COUNT(*) FROM knowledge_chunks) AS chunk_count
                        """,
                    arguments: [fixture.directoryID]
                )

                return (
                    (row?["file_count"] as Int64?) ?? 0,
                    (row?["anchor_count"] as Int64?) ?? 0,
                    (row?["chunk_count"] as Int64?) ?? 0
                )
            }

            #expect(snapshot == (1, 1, 20))
        }
    }

    @Test("rebuild records fresh chunk work without actor-local queues")
    func rebuildRecordsFreshChunkWorkWithoutActorLocalQueues() async throws {
        try await withBlockedKnowledgeChunkBacklog { fixture in
            await fixture.actorSystem.broadcast(
                from: nil,
                message: RebuildKnowledge(directoryID: fixture.directoryID)
            )
            await fixture.actorSystem.broadcast(
                from: nil,
                message: KnowledgeDirectorySyncRequested(directoryID: fixture.directoryID)
            )

            let startedAt = Date()
            while Date().timeIntervalSince(startedAt) < 10 {
                let unprocessedChunkCount = try fixture.database.read { db in
                    try Int.fetchOne(
                        db,
                    sql: "SELECT COUNT(*) FROM knowledge_chunks WHERE processed = 0"
                    ) ?? 0
                }
                let blockedCount = await fixture.textScheduler.blockedCount()

                if unprocessedChunkCount == 20,
                   blockedCount >= 20 {
                    #expect(unprocessedChunkCount == 20)
                    return
                }

                try await Task.sleep(nanoseconds: 50_000_000)
            }

            throw FixtureError.timedOut
        }
    }

    @Test("rebuild preserves activity-linked graph rows and prunes file-only graph rows")
    func rebuildPreservesActivityLinkedGraphRowsAndPrunesFileOnlyGraphRows() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            let alphaGraph = try fixture.database.read { db in
                let nodeRows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, community_id
                        FROM knowledge_nodes
                        WHERE normalized_name IN ('alice example', 'acme platform')
                        ORDER BY id ASC
                        """
                )

                return (
                    nodeRows.compactMap { $0["id"] as Int64? },
                    Set(nodeRows.compactMap { $0["community_id"] as Int64? }).first,
                    try Int64.fetchOne(
                        db,
                        sql: "SELECT id FROM knowledge_edges WHERE description = ?",
                        arguments: ["Alice Example works on Acme Platform."]
                    )
                )
            }
            let alphaNodeIDs = alphaGraph.0
            let alphaCommunityID = try #require(alphaGraph.1)
            let alphaEdgeID = try #require(alphaGraph.2)
            let activityID: Int64 = 90_001

            try #require(alphaNodeIDs.count == 2)

            try fixture.database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO activities (
                            id,
                            start_time,
                            application,
                            keystrokes,
                            microphone,
                            summary,
                            tag_id,
                            json_properties,
                            overview_id
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        activityID,
                        Date(timeIntervalSince1970: 1_775_000_100).formatted(TaskTraceDatabase.sqlTimestampStyle),
                        "TaskTrace",
                        nil,
                        nil,
                        "Alpha work references Alice Example and Acme Platform.",
                        nil,
                        nil,
                        nil
                    ]
                )

                try alphaNodeIDs.forEach {
                    try db.execute(
                        sql: """
                            INSERT INTO knowledge_node_activities (node_id, activity_id)
                            VALUES (?, ?)
                            """,
                        arguments: [$0, activityID]
                    )
                }

                try db.execute(
                    sql: """
                        INSERT INTO knowledge_edge_activities (edge_id, activity_id)
                        VALUES (?, ?)
                        """,
                    arguments: [alphaEdgeID, activityID]
                )
            }

            try await fixture.knowledgeDatabaseActor.rebuildKnowledgeDirectory(id: fixture.directoryID)

            let snapshot = try fixture.database.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT
                            (SELECT COUNT(*) FROM knowledge_files WHERE directory_id = ?) AS file_count,
                            (SELECT COUNT(*) FROM knowledge_chunks) AS chunk_count,
                            (SELECT COUNT(*) FROM knowledge_node_chunks) AS node_chunk_count,
                            (SELECT COUNT(*) FROM knowledge_edge_chunks) AS edge_chunk_count,
                            (SELECT COUNT(*) FROM knowledge_nodes) AS node_count,
                            (SELECT COUNT(*) FROM knowledge_edges) AS edge_count,
                            (SELECT COUNT(*) FROM knowledge_claims) AS claim_count,
                            (SELECT COUNT(*) FROM knowledge_communities) AS community_count,
                            (SELECT COUNT(*) FROM knowledge_node_activities) AS node_activity_count,
                            (SELECT COUNT(*) FROM knowledge_edge_activities) AS edge_activity_count,
                            (SELECT COUNT(*) FROM knowledge_nodes WHERE id IN (?, ?)) AS preserved_node_count,
                            (SELECT COUNT(*) FROM knowledge_edges WHERE id = ?) AS preserved_edge_count,
                            (SELECT COUNT(*) FROM knowledge_communities WHERE id = ?) AS preserved_community_count,
                            (SELECT COUNT(*) FROM knowledge_nodes WHERE source_chunk_id IS NOT NULL) AS node_source_count,
                            (SELECT COUNT(*) FROM knowledge_edges WHERE source_chunk_id IS NOT NULL) AS edge_source_count
                        """,
                    arguments: [
                        fixture.directoryID,
                        alphaNodeIDs[0],
                        alphaNodeIDs[1],
                        alphaEdgeID,
                        alphaCommunityID
                    ]
                )

                return [
                    (row?["file_count"] as Int64?) ?? 0,
                    (row?["chunk_count"] as Int64?) ?? 0,
                    (row?["node_chunk_count"] as Int64?) ?? 0,
                    (row?["edge_chunk_count"] as Int64?) ?? 0,
                    (row?["node_count"] as Int64?) ?? 0,
                    (row?["edge_count"] as Int64?) ?? 0,
                    (row?["claim_count"] as Int64?) ?? 0,
                    (row?["community_count"] as Int64?) ?? 0,
                    (row?["node_activity_count"] as Int64?) ?? 0,
                    (row?["edge_activity_count"] as Int64?) ?? 0,
                    (row?["preserved_node_count"] as Int64?) ?? 0,
                    (row?["preserved_edge_count"] as Int64?) ?? 0,
                    (row?["preserved_community_count"] as Int64?) ?? 0,
                    (row?["node_source_count"] as Int64?) ?? 0,
                    (row?["edge_source_count"] as Int64?) ?? 0
                ]
            }

            #expect(snapshot == [0, 0, 0, 0, 2, 1, 2, 1, 2, 1, 2, 1, 1, 0, 0])
        }
    }

    @Test("knowledge graph snapshot excludes unlinked active day overview lane entries")
    func knowledgeGraphSnapshotExcludesUnlinkedActiveDayOverviewLaneEntries() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            let overviewID: Int64 = 91_000
            let activityID: Int64 = 91_001
            let unrelatedOverviewID: Int64 = 91_002
            let unrelatedActivityID: Int64 = 91_003
            let activeDay = Date(timeIntervalSince1970: 1_775_000_000)
            let alphaNodeIDs = try fixture.database.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id
                        FROM knowledge_nodes
                        WHERE normalized_name IN ('alice example', 'acme platform')
                        ORDER BY id ASC
                        """
                ).compactMap { $0["id"] as Int64? }
            }

            try fixture.database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO overviews (
                            id,
                            title,
                            summary,
                            summary_vector,
                            json_properties,
                            edited_duration,
                            tag_id
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        overviewID,
                        "Alpha Overview",
                        "Alpha work on Alice Example and Acme Platform.",
                        nil,
                        nil,
                        nil,
                        nil
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO overviews (
                            id,
                            title,
                            summary,
                            summary_vector,
                            json_properties,
                            edited_duration,
                            tag_id
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        unrelatedOverviewID,
                        "Unrelated Overview",
                        "Same-day work that is not linked into the knowledge graph.",
                        nil,
                        nil,
                        nil,
                        nil
                    ]
                )

                try db.execute(
                    sql: """
                        INSERT INTO activities (
                            id,
                            start_time,
                            application,
                            keystrokes,
                            microphone,
                            summary,
                            tag_id,
                            json_properties,
                            overview_id
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        activityID,
                        Date(timeIntervalSince1970: 1_775_000_100).formatted(TaskTraceDatabase.sqlTimestampStyle),
                        "TaskTrace",
                        nil,
                        nil,
                        "Alpha activity references Alice Example and Acme Platform.",
                        nil,
                        nil,
                        overviewID
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO activities (
                            id,
                            start_time,
                            application,
                            keystrokes,
                            microphone,
                            summary,
                            tag_id,
                            json_properties,
                            overview_id
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        unrelatedActivityID,
                        Date(timeIntervalSince1970: 1_775_000_200).formatted(TaskTraceDatabase.sqlTimestampStyle),
                        "TaskTrace",
                        nil,
                        nil,
                        "Unrelated activity with no knowledge joins.",
                        nil,
                        nil,
                        unrelatedOverviewID
                    ]
                )

                try alphaNodeIDs.forEach {
                    try db.execute(
                        sql: """
                            INSERT INTO knowledge_node_activities (node_id, activity_id)
                            VALUES (?, ?)
                            """,
                        arguments: [$0, activityID]
                    )
                }
            }

            let snapshot = try fixture.knowledgeReadDatabase.loadKnowledgeGraphDirectorySnapshot(
                directoryID: fixture.directoryID,
                activeDay: activeDay
            )

            #expect((snapshot.overviews.map(\.id), snapshot.activities.map(\.id)) == ([overviewID], [activityID]))
        }
    }

    @Test("knowledge graph overview and activity overlay queries return linked node ids")
    func knowledgeGraphOverviewAndActivityOverlayQueriesReturnLinkedNodeIDs() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            let overviewID: Int64 = 92_000
            let activityID: Int64 = 92_001
            let activeDay = Date(timeIntervalSince1970: 1_775_000_000)
            let alphaNodeIDs = try fixture.database.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id
                        FROM knowledge_nodes
                        WHERE normalized_name IN ('alice example', 'acme platform')
                        ORDER BY id ASC
                        """
                ).compactMap { $0["id"] as Int64? }
            }

            try fixture.database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO overviews (
                            id,
                            title,
                            summary,
                            summary_vector,
                            json_properties,
                            edited_duration,
                            tag_id
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        overviewID,
                        "Alpha Overview",
                        "Alpha work on Alice Example and Acme Platform.",
                        nil,
                        nil,
                        nil,
                        nil
                    ]
                )

                try db.execute(
                    sql: """
                        INSERT INTO activities (
                            id,
                            start_time,
                            application,
                            keystrokes,
                            microphone,
                            summary,
                            tag_id,
                            json_properties,
                            overview_id
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        activityID,
                        Date(timeIntervalSince1970: 1_775_000_100).formatted(TaskTraceDatabase.sqlTimestampStyle),
                        "TaskTrace",
                        nil,
                        nil,
                        "Alpha activity references Alice Example and Acme Platform.",
                        nil,
                        nil,
                        overviewID
                    ]
                )

                try alphaNodeIDs.forEach {
                    try db.execute(
                        sql: """
                            INSERT INTO knowledge_node_activities (node_id, activity_id)
                            VALUES (?, ?)
                            """,
                        arguments: [$0, activityID]
                    )
                }
            }

            let activityLinks = try fixture.knowledgeReadDatabase.loadKnowledgeActivityLinks(
                activityID: activityID
            )
            let overviewLinks = try fixture.knowledgeReadDatabase.loadKnowledgeOverviewLinks(
                overviewID: overviewID,
                activeDay: activeDay
            )

            #expect((activityLinks.map(\.nodeID), overviewLinks.map(\.nodeID)) == (alphaNodeIDs, alphaNodeIDs))
        }
    }

    @Test("community link queries include file-backed members in the all-sources graph")
    func communityLinkQueriesIncludeFileBackedMembersInTheAllSourcesGraph() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            let activeDay = Date(timeIntervalSince1970: 1_775_000_000)
            let alphaNodeIDs = try fixture.database.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id
                        FROM knowledge_nodes
                        WHERE normalized_name IN ('alice example', 'acme platform')
                        ORDER BY id ASC
                        """
                ).compactMap { $0["id"] as Int64? }
            }
            let communityLinks = try fixture.knowledgeReadDatabase.loadKnowledgeCommunityLinks(
                directoryID: nil,
                activeDay: activeDay,
                communityID: 100
            )

            #expect(communityLinks.map(\.nodeID) == alphaNodeIDs)
        }
    }

    @Test("knowledge graph progress includes current day activity and overview knowledge status")
    func knowledgeGraphProgressIncludesCurrentDayActivityAndOverviewKnowledgeStatus() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            let activeDay = Date(timeIntervalSince1970: 1_775_000_000)

            try fixture.database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO overviews (
                            id,
                            title,
                            summary,
                            json_properties,
                            edited_duration,
                            tag_id,
                            knowledge_processed
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [93_000, "Processed Overview", "Processed overview summary.", nil, nil, nil, 1]
                )
                try db.execute(
                    sql: """
                        INSERT INTO overviews (
                            id,
                            title,
                            summary,
                            json_properties,
                            edited_duration,
                            tag_id,
                            knowledge_processed
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [93_001, "Pending Overview", "Pending overview summary.", nil, nil, nil, 0]
                )
                try db.execute(
                    sql: """
                        INSERT INTO activities (
                            id,
                            start_time,
                            application,
                            keystrokes,
                            microphone,
                            summary,
                            tag_id,
                            json_properties,
                            overview_id,
                            knowledge_processed
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        93_010,
                        Date(timeIntervalSince1970: 1_775_000_100).formatted(TaskTraceDatabase.sqlTimestampStyle),
                        "TaskTrace",
                        nil,
                        nil,
                        "Processed activity summary.",
                        nil,
                        nil,
                        93_000,
                        1
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO activities (
                            id,
                            start_time,
                            application,
                            keystrokes,
                            microphone,
                            summary,
                            tag_id,
                            json_properties,
                            overview_id,
                            knowledge_processed
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        93_011,
                        Date(timeIntervalSince1970: 1_775_000_200).formatted(TaskTraceDatabase.sqlTimestampStyle),
                        "TaskTrace",
                        nil,
                        nil,
                        "Pending activity summary.",
                        nil,
                        nil,
                        93_001,
                        0
                    ]
                )
            }

            let progress = try fixture.knowledgeReadDatabase.loadKnowledgeGraphBuildProgress(
                directoryID: fixture.directoryID,
                activeDay: activeDay
            )

            #expect((progress.totalActivities, progress.processedActivities, progress.totalOverviews, progress.processedOverviews) == (2, 1, 2, 1))
        }
    }

    @Test("knowledge graph load replays unprocessed activity knowledge for the requested active day")
    func knowledgeGraphLoadReplaysUnprocessedActivityKnowledgeForRequestedActiveDay() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            let requestedDay = Date(timeIntervalSince1970: 1_774_913_600)
            let overviewID: Int64 = 93_050
            let activityID: Int64 = 93_051
            let activitySummary = "Alice Example works on Acme Platform. Alice Example says Acme Platform keeps workflow memory durable."

            try fixture.database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO overviews (
                            id,
                            title,
                            summary,
                            json_properties,
                            edited_duration,
                            tag_id,
                            knowledge_processed
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [overviewID, "Requested Day Overview", "Requested day overview summary.", nil, nil, nil, 0]
                )
                try db.execute(
                    sql: """
                        INSERT INTO activities (
                            id,
                            start_time,
                            application,
                            keystrokes,
                            microphone,
                            summary,
                            tag_id,
                            json_properties,
                            overview_id,
                            knowledge_processed
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        activityID,
                        Date(timeIntervalSince1970: 1_774_913_700).formatted(TaskTraceDatabase.sqlTimestampStyle),
                        "TaskTrace",
                        nil,
                        nil,
                        activitySummary,
                        nil,
                        nil,
                        overviewID,
                        0
                    ]
                )
            }

            await fixture.knowledgeGraphActor.receive(
                Envelope(
                    sender: nil,
                    message: KnowledgeLoadRequested(activeDay: requestedDay)
                )
            )

            let startedAt = Date()
            var snapshot: [Int64] = [-1, -1, -1]

            while Date().timeIntervalSince(startedAt) < 3 {
                let encodedCount = await fixture.collector.count(ActivityKnowledgeEncoded.self)
                snapshot = try fixture.database.read { db in
                    let row = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT
                                COALESCE((SELECT knowledge_processed FROM activities WHERE id = ?), -1) AS activity_processed,
                                COALESCE((SELECT knowledge_processed FROM overviews WHERE id = ?), -1) AS overview_processed,
                                (SELECT COUNT(*) FROM knowledge_node_activities WHERE activity_id = ?) AS node_activity_count
                            """,
                        arguments: [activityID, overviewID, activityID]
                    )

                    return [
                        (row?["activity_processed"] as Int64?) ?? -1,
                        (row?["overview_processed"] as Int64?) ?? -1,
                        (((row?["node_activity_count"] as Int64?) ?? 0) > 0 && encodedCount > 0) ? 1 : 0
                    ]
                }

                if snapshot == [1, 1, 1] {
                    break
                }

                try? await Task.sleep(for: .milliseconds(25))
            }

            #expect(snapshot == [1, 1, 1])
        }
    }

    @Test("rebuild activity knowledge event requeues current day activity summaries")
    func rebuildActivityKnowledgeEventRequeuesCurrentDayActivitySummaries() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            let activeDay = Date(timeIntervalSince1970: 1_775_000_000)
            let overviewID: Int64 = 93_100
            let activityID: Int64 = 93_101
            let activitySummary = "Alice Example works on Acme Platform. Alice Example says Acme Platform keeps workflow memory durable."

            try fixture.database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO overviews (
                            id,
                            title,
                            summary,
                            json_properties,
                            edited_duration,
                            tag_id,
                            knowledge_processed
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [overviewID, "Activity Overview", "Activity overview summary.", nil, nil, nil, 1]
                )
                try db.execute(
                    sql: """
                        INSERT INTO activities (
                            id,
                            start_time,
                            application,
                            keystrokes,
                            microphone,
                            summary,
                            tag_id,
                            json_properties,
                            overview_id,
                            knowledge_processed
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        activityID,
                        Date(timeIntervalSince1970: 1_775_000_100).formatted(TaskTraceDatabase.sqlTimestampStyle),
                        "TaskTrace",
                        nil,
                        nil,
                        activitySummary,
                        nil,
                        nil,
                        overviewID,
                        1
                    ]
                )
            }

            await fixture.actorSystem.broadcast(
                from: nil,
                message: RebuildActivityKnowledge(activeDay: activeDay)
            )

            let startedAt = Date()
            var snapshot: [Int64] = [-1, -1, -1, -1, -1]

            while Date().timeIntervalSince(startedAt) < 3 {
                let encodedCount = await fixture.collector.count(ActivityKnowledgeEncoded.self)
                snapshot = try fixture.database.read { db in
                    let row = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT
                                COALESCE((SELECT knowledge_processed FROM activities WHERE id = ?), -1) AS activity_processed,
                                COALESCE((SELECT knowledge_processed FROM overviews WHERE id = ?), -1) AS overview_processed,
                                (SELECT COUNT(*) FROM knowledge_node_activities WHERE activity_id = ?) AS node_activity_count,
                                (SELECT COUNT(*) FROM knowledge_edge_activities WHERE activity_id = ?) AS edge_activity_count
                            """,
                        arguments: [activityID, overviewID, activityID, activityID]
                    )

                    return [
                        (row?["activity_processed"] as Int64?) ?? -1,
                        (row?["overview_processed"] as Int64?) ?? -1,
                        ((row?["node_activity_count"] as Int64?) ?? 0) > 0 ? 1 : 0,
                        ((row?["edge_activity_count"] as Int64?) ?? 0) > 0 ? 1 : 0,
                        encodedCount > 0 ? 1 : 0
                    ]
                }

                if snapshot == [1, 1, 1, 1, 1] {
                    break
                }

                try? await Task.sleep(for: .milliseconds(25))
            }

            #expect(snapshot == [1, 1, 1, 1, 1])
        }
    }

    @Test("activity knowledge rebuild clears day links and prunes orphan activity graph records")
    func activityKnowledgeRebuildClearsDayLinksAndPrunesOrphanActivityGraphRecords() async throws {
        try await withCompletedKnowledgePipeline { fixture in
            let activeDay = Date(timeIntervalSince1970: 1_775_000_000)
            let overviewID: Int64 = 94_000
            let activityID: Int64 = 94_001
            let communityID: Int64 = 94_010
            let firstNodeID: Int64 = 94_011
            let secondNodeID: Int64 = 94_012
            let edgeID: Int64 = 94_013

            try fixture.database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO overviews (
                            id,
                            title,
                            summary,
                            json_properties,
                            edited_duration,
                            tag_id,
                            knowledge_processed
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [overviewID, "Activity Overview", "Activity overview summary.", nil, nil, nil, 1]
                )
                try db.execute(
                    sql: """
                        INSERT INTO activities (
                            id,
                            start_time,
                            application,
                            keystrokes,
                            microphone,
                            summary,
                            tag_id,
                            json_properties,
                            overview_id,
                            knowledge_processed
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        activityID,
                        Date(timeIntervalSince1970: 1_775_000_300).formatted(TaskTraceDatabase.sqlTimestampStyle),
                        "TaskTrace",
                        nil,
                        nil,
                        "Activity knowledge rebuild summary.",
                        nil,
                        nil,
                        overviewID,
                        1
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO knowledge_communities (id, name, summary, embedding)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [communityID, "Activity Community", "Activity-only community.", nil]
                )
                try db.execute(
                    sql: """
                        INSERT INTO knowledge_nodes (
                            id,
                            name,
                            normalized_name,
                            kind,
                            description,
                            source_chunk_id,
                            embedding,
                            community_id,
                            create_date
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        firstNodeID,
                        "Activity Node A",
                        "activity node a",
                        "product",
                        "Activity-only node A.",
                        nil,
                        nil,
                        communityID,
                        activeDay.formatted(TaskTraceDatabase.sqlTimestampStyle)
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO knowledge_nodes (
                            id,
                            name,
                            normalized_name,
                            kind,
                            description,
                            source_chunk_id,
                            embedding,
                            community_id,
                            create_date
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        secondNodeID,
                        "Activity Node B",
                        "activity node b",
                        "product",
                        "Activity-only node B.",
                        nil,
                        nil,
                        communityID,
                        activeDay.formatted(TaskTraceDatabase.sqlTimestampStyle)
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO knowledge_edges (
                            id,
                            first_node_id,
                            second_node_id,
                            relationship_type,
                            description,
                            source_chunk_id,
                            create_date
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [edgeID, firstNodeID, secondNodeID, "connected_to", "Activity-only edge.", nil, activeDay.formatted(TaskTraceDatabase.sqlTimestampStyle)]
                )
                try db.execute(
                    sql: """
                        INSERT INTO knowledge_node_activities (node_id, activity_id)
                        VALUES (?, ?), (?, ?)
                        """,
                    arguments: [firstNodeID, activityID, secondNodeID, activityID]
                )
                try db.execute(
                    sql: """
                        INSERT INTO knowledge_edge_activities (edge_id, activity_id)
                        VALUES (?, ?)
                        """,
                    arguments: [edgeID, activityID]
                )
            }

            try await fixture.knowledgeDatabaseActor.rebuildActivityKnowledge(activeDay: activeDay)

            let snapshot = try fixture.database.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT
                            COALESCE((SELECT knowledge_processed FROM activities WHERE id = ?), -1) AS activity_processed,
                            COALESCE((SELECT knowledge_processed FROM overviews WHERE id = ?), -1) AS overview_processed,
                            (SELECT COUNT(*) FROM knowledge_node_activities WHERE activity_id = ?) AS node_activity_count,
                            (SELECT COUNT(*) FROM knowledge_edge_activities WHERE activity_id = ?) AS edge_activity_count,
                            (SELECT COUNT(*) FROM knowledge_nodes WHERE id IN (?, ?)) AS node_count,
                            (SELECT COUNT(*) FROM knowledge_edges WHERE id = ?) AS edge_count,
                            (SELECT COUNT(*) FROM knowledge_communities WHERE id = ?) AS community_count
                        """,
                    arguments: [activityID, overviewID, activityID, activityID, firstNodeID, secondNodeID, edgeID, communityID]
                )

                return [
                    (row?["activity_processed"] as Int64?) ?? -1,
                    (row?["overview_processed"] as Int64?) ?? -1,
                    (row?["node_activity_count"] as Int64?) ?? -1,
                    (row?["edge_activity_count"] as Int64?) ?? -1,
                    (row?["node_count"] as Int64?) ?? -1,
                    (row?["edge_count"] as Int64?) ?? -1,
                    (row?["community_count"] as Int64?) ?? -1
                ]
            }

            #expect(snapshot == [0, 0, 0, 0, 0, 0, 0])
        }
    }
}
