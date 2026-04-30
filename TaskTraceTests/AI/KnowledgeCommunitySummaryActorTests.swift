import Foundation
import GRDB
import MLXLMCommon
import Testing
@testable import TaskTrace

@MainActor
struct KnowledgeCommunitySummaryActorTests {
    @Test("community direct summary output budget is three hundred twenty tokens")
    func communityDirectSummaryOutputBudgetIsThreeHundredTwentyTokens() {
        #expect(KnowledgeCommunitySummaryActor.directSummaryMaxTokens == 320)
    }

    @Test("community chunk summary output budget is one hundred eighty tokens")
    func communityChunkSummaryOutputBudgetIsOneHundredEightyTokens() {
        #expect(KnowledgeCommunitySummaryActor.chunkSummaryMaxTokens == 180)
    }

    private struct Fixture {
        let database: TaskTraceDatabase
        let actorSystem: ActorSystem
        let textResponder: RecordingSummaryTextResponder
        let collector: SummaryEventCollector
        let communityID: Int64
        let nodeIDs: [Int64]
    }

    private struct PromptRecord: Sendable {
        let prompt: String
        let instructions: String
    }

    private actor RecordingSummaryTextResponder: AITextResponding, Receiver {
        private let actorSystem: ActorSystem
        private let completesAutomatically: Bool
        private var records: [PromptRecord] = []
        private var pendingRequests: [(requestID: UUID, source: String)] = []

        init(
            actorSystem: ActorSystem,
            completesAutomatically: Bool = true
        ) {
            self.actorSystem = actorSystem
            self.completesAutomatically = completesAutomatically
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

            guard completesAutomatically else {
                pendingRequests.append((request.requestID, request.source))
                return
            }

            await complete(requestID: request.requestID, source: request.source)
        }

        func completeNext() async {
            guard !pendingRequests.isEmpty else {
                return
            }

            let request = pendingRequests.removeFirst()
            await complete(requestID: request.requestID, source: request.source)
        }

        private func complete(requestID: UUID, source: String) async {
            let now = Date()
            await actorSystem.broadcast(
                from: nil,
                message: ModelTextCompleted(
                    requestID: requestID,
                    response: """
                    Name: Example Community
                    Summary: Example community summary.
                    """,
                    schedulerMetadata: AISchedulerMetadata(
                        scheduler: .textBig,
                        bucket: "test",
                        batchSize: 1,
                        source: source
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

            return """
            Name: Example Community
            Summary: Example community summary.
            """
        }

        func callCount() -> Int {
            records.count
        }

        func requests() -> [PromptRecord] {
            records
        }
    }

    private actor SummaryEventCollector: Receiver {
        private var events: [CommunitySummarized] = []

        func receive(_ envelope: Envelope) async {
            guard let event = envelope.message as? CommunitySummarized else {
                return
            }

            events.append(event)
        }

        func count() -> Int {
            events.count
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () async throws -> Bool
    ) async throws {
        let startedAt = Date()

        while Date().timeIntervalSince(startedAt) < timeout {
            if try await condition() {
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func withFixture(
        debounceDelay: Duration = .milliseconds(40),
        completesAutomatically: Bool = true,
        _ block: (Fixture) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let actorSystem = ActorSystem()
        let communityID: Int64 = 500
        let nodeIDs: [Int64] = [501, 502]

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let knowledgeDatabaseActor = KnowledgeDatabaseActor(database: database, actorSystem: actorSystem)
        let textResponder = RecordingSummaryTextResponder(
            actorSystem: actorSystem,
            completesAutomatically: completesAutomatically
        )
        let collector = SummaryEventCollector()
        let actor = KnowledgeCommunitySummaryActor(
            actorSystem: actorSystem,
            knowledgeDatabaseActor: knowledgeDatabaseActor,
            textResponder: textResponder,
            debounceDelay: debounceDelay
        )

        _ = await actorSystem.register(knowledgeDatabaseActor)
        _ = await actorSystem.register(textResponder)
        _ = await actorSystem.register(actor)
        _ = await actorSystem.register(collector)

        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT INTO knowledge_communities (id, name, summary, summary_input_hash, embedding)
                    VALUES (?, NULL, NULL, NULL, NULL)
                    """,
                arguments: [communityID]
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
                    ) VALUES (?, ?, ?, ?, ?, NULL, NULL, ?, ?)
                    """,
                arguments: [
                    nodeIDs[0],
                    "Alice Example",
                    KnowledgeNodeRecord.normalizedName(for: "Alice Example"),
                    "person",
                    "Alice Example works on Acme Platform.",
                    communityID,
                    now
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
                    ) VALUES (?, ?, ?, ?, ?, NULL, NULL, ?, ?)
                    """,
                arguments: [
                    nodeIDs[1],
                    "Acme Platform",
                    KnowledgeNodeRecord.normalizedName(for: "Acme Platform"),
                    "product",
                    "Acme Platform stores workflow memory.",
                    communityID,
                    now.addingTimeInterval(1)
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
                    ) VALUES (?, ?, ?, ?, ?, NULL, ?)
                    """,
                arguments: [503, nodeIDs[0], nodeIDs[1], "works_on", "Alice Example works on Acme Platform.", now]
            )
            try db.execute(
                sql: """
                    INSERT INTO knowledge_claims (
                        id,
                        node_id,
                        text,
                        md5,
                        embedding,
                        create_date
                    ) VALUES (?, ?, ?, ?, NULL, ?)
                    """,
                arguments: [504, nodeIDs[0], "Alice Example works on Acme Platform.", "claim-504", now]
            )
        }

        try await block(
            Fixture(
                database: database,
                actorSystem: actorSystem,
                textResponder: textResponder,
                collector: collector,
                communityID: communityID,
                nodeIDs: nodeIDs
            )
        )
    }

    private func withOversizedCommunityFixture(
        completesAutomatically: Bool = true,
        _ block: (Fixture) async throws -> Void
    ) async throws {
        try await withFixture(
            debounceDelay: .zero,
            completesAutomatically: completesAutomatically
        ) { fixture in
            let now = Date(timeIntervalSince1970: 1_775_000_100)
            let longClaimText = String(
                repeating: "Alice Example records durable workflow memory details for a large connected work system. ",
                count: 2_000
            )

            try fixture.database.vectorAwareWrite { db in
                try db.execute(
                    sql: """
                        INSERT INTO knowledge_claims (
                            id,
                            node_id,
                            text,
                            md5,
                            embedding,
                            create_date
                        ) VALUES (?, ?, ?, ?, NULL, ?)
                        """,
                    arguments: [9_001, fixture.nodeIDs[0], longClaimText, "claim-9001", now]
                )
            }

            try await block(fixture)
        }
    }

    @Test("community summary actor suppresses duplicate direct requests while in flight")
    func communitySummaryActorSuppressesDuplicateDirectRequestsWhileInFlight() async throws {
        try await withFixture(
            debounceDelay: .zero,
            completesAutomatically: false
        ) { fixture in
            let event = CommunitiesGenerated(
                buildID: 11,
                communityByNodeID: [
                    fixture.nodeIDs[0]: fixture.communityID,
                    fixture.nodeIDs[1]: fixture.communityID
                ]
            )

            await fixture.actorSystem.broadcast(from: nil, message: event)
            try await waitUntil {
                await fixture.textResponder.callCount() == 1
            }
            await fixture.actorSystem.broadcast(from: nil, message: event)
            try await Task.sleep(for: .milliseconds(80))

            let callCount = await fixture.textResponder.callCount()
            #expect(callCount == 1)
        }
    }

    @Test("community summary actor reruns once when changed while in flight")
    func communitySummaryActorRerunsOnceWhenChangedWhileInFlight() async throws {
        try await withFixture(
            debounceDelay: .zero,
            completesAutomatically: false
        ) { fixture in
            let event = CommunitiesGenerated(
                buildID: 12,
                communityByNodeID: [
                    fixture.nodeIDs[0]: fixture.communityID,
                    fixture.nodeIDs[1]: fixture.communityID
                ]
            )

            await fixture.actorSystem.broadcast(from: nil, message: event)
            try await waitUntil {
                await fixture.textResponder.callCount() == 1
            }
            try fixture.database.vectorAwareWrite { db in
                try db.execute(
                    sql: """
                        INSERT INTO knowledge_claims (
                            id,
                            node_id,
                            text,
                            md5,
                            embedding,
                            create_date
                        ) VALUES (?, ?, ?, ?, NULL, ?)
                        """,
                    arguments: [
                        12_001,
                        fixture.nodeIDs[0],
                        "Alice Example adds a second workflow-memory fact while summarization is running.",
                        "claim-12001",
                        Date(timeIntervalSince1970: 1_775_000_200)
                    ]
                )
            }
            await fixture.actorSystem.broadcast(from: nil, message: event)
            try await Task.sleep(for: .milliseconds(20))
            await fixture.textResponder.completeNext()
            try await waitUntil {
                await fixture.textResponder.callCount() == 2
            }

            let callCount = await fixture.textResponder.callCount()
            #expect(callCount == 2)
        }
    }

    @Test("community summary actor debounces repeated updates for the same community")
    func communitySummaryActorDebouncesRepeatedUpdatesForTheSameCommunity() async throws {
        try await withFixture { fixture in
            let event = CommunitiesGenerated(
                buildID: 1,
                communityByNodeID: [
                    fixture.nodeIDs[0]: fixture.communityID,
                    fixture.nodeIDs[1]: fixture.communityID
                ]
            )

            await fixture.actorSystem.broadcast(from: nil, message: event)
            try await Task.sleep(for: .milliseconds(10))
            await fixture.actorSystem.broadcast(from: nil, message: event)
            try await waitUntil {
                await fixture.collector.count() == 1
            }
            try await Task.sleep(for: .milliseconds(80))

            let callCount = await fixture.textResponder.callCount()
            #expect(callCount == 1)
        }
    }

    @Test("community summary actor processes community events without build completion state")
    func communitySummaryActorProcessesCommunityEventsWithoutBuildCompletionState() async throws {
        try await withFixture(debounceDelay: .milliseconds(20)) { fixture in
            await fixture.actorSystem.broadcast(
                from: nil,
                message: CommunitiesGenerated(
                    buildID: 7,
                    communityByNodeID: [
                        fixture.nodeIDs[0]: fixture.communityID,
                        fixture.nodeIDs[1]: fixture.communityID
                    ]
                )
            )
            await fixture.actorSystem.broadcast(
                from: nil,
                message: KnowledgeBuildCompleted(buildID: 7, directoryID: 1)
            )
            try await waitUntil {
                await fixture.textResponder.callCount() == 1
            }

            let callCount = await fixture.textResponder.callCount()
            #expect(callCount == 1)
        }
    }

    @Test("community summary actor skips unchanged communities after a summary is persisted")
    func communitySummaryActorSkipsUnchangedCommunitiesAfterASummaryIsPersisted() async throws {
        try await withFixture { fixture in
            let event = CommunitiesGenerated(
                buildID: 2,
                communityByNodeID: [
                    fixture.nodeIDs[0]: fixture.communityID,
                    fixture.nodeIDs[1]: fixture.communityID
                ]
            )

            await fixture.actorSystem.broadcast(from: nil, message: event)
            try await waitUntil {
                try fixture.database.vectorAwareRead { db in
                    (try String.fetchOne(
                        db,
                        sql: """
                            SELECT summary_input_hash
                            FROM knowledge_communities
                            WHERE id = ?
                            """,
                        arguments: [fixture.communityID]
                    )?.isEmpty == false)
                }
            }
            await fixture.actorSystem.broadcast(from: nil, message: event)
            try await Task.sleep(for: .milliseconds(80))

            let callCount = await fixture.textResponder.callCount()
            #expect(callCount == 1)
        }
    }

    @Test("community summary prompt hashing is stable across input ordering")
    func communitySummaryPromptHashingIsStableAcrossInputOrdering() {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let firstNode = KnowledgeNodeRecord(
            id: 1,
            name: "Alice Example",
            normalizedName: KnowledgeNodeRecord.normalizedName(for: "Alice Example"),
            kind: "person",
            description: "Alice Example works on Acme Platform.",
            sourceChunkID: nil,
            embedding: nil,
            communityID: 10,
            createDate: now
        )
        let secondNode = KnowledgeNodeRecord(
            id: 2,
            name: "Acme Platform",
            normalizedName: KnowledgeNodeRecord.normalizedName(for: "Acme Platform"),
            kind: "product",
            description: "Acme Platform stores workflow memory.",
            sourceChunkID: nil,
            embedding: nil,
            communityID: 10,
            createDate: now.addingTimeInterval(1)
        )
        let edge = KnowledgeEdgeRecord(
            id: 3,
            firstNodeID: 1,
            secondNodeID: 2,
            relationshipType: "works_on",
            description: "Alice Example works on Acme Platform.",
            sourceChunkID: nil,
            createDate: now
        )
        let claim = KnowledgeClaimRecord(
            id: 4,
            nodeID: 1,
            text: "Alice Example works on Acme Platform.",
            md5: "claim-4",
            embedding: nil,
            createDate: now
        )
        let firstHash = KnowledgeCommunitySummaryActor.sha256Hex(
            of: KnowledgeCommunitySummaryActor.buildSummarizePrompt(
                summaryInput: KnowledgeCommunitySummaryInput(
                    currentSummary: nil,
                    summaryInputHash: nil,
                    nodes: [firstNode, secondNode],
                    edges: [edge],
                    claimsByNodeID: [1: [claim]]
                )
            )
        )
        let secondHash = KnowledgeCommunitySummaryActor.sha256Hex(
            of: KnowledgeCommunitySummaryActor.buildSummarizePrompt(
                summaryInput: KnowledgeCommunitySummaryInput(
                    currentSummary: nil,
                    summaryInputHash: nil,
                    nodes: [secondNode, firstNode],
                    edges: [edge],
                    claimsByNodeID: [1: [claim]]
                )
            )
        )

        #expect(firstHash == secondHash)
    }

    @Test("community recursive summary keeps every prompt under hard limit")
    func communityRecursiveSummaryKeepsEveryPromptUnderHardLimit() async throws {
        try await withOversizedCommunityFixture { fixture in
            await fixture.actorSystem.broadcast(
                from: nil,
                message: CommunitiesGenerated(
                    buildID: 9,
                    communityByNodeID: [
                        fixture.nodeIDs[0]: fixture.communityID,
                        fixture.nodeIDs[1]: fixture.communityID
                    ]
                )
            )
            try await waitUntil {
                await fixture.collector.count() == 1
            }

            let requests = await fixture.textResponder.requests()
            let eventCount = await fixture.collector.count()
            let promptsUnderLimit = requests.allSatisfy {
                AIRecursivePromptReducer.promptTokenEstimate(
                    prompt: $0.prompt,
                    instructions: $0.instructions
                ) <= AIRecursivePromptReducer.knowledgeSummaryTokenBudget.hardTokenLimit
            }

            #expect(eventCount == 1 && promptsUnderLimit)
        }
    }

    @Test("community recursive summary uses multiple AI calls for oversized input")
    func communityRecursiveSummaryUsesMultipleAICallsForOversizedInput() async throws {
        try await withOversizedCommunityFixture { fixture in
            await fixture.actorSystem.broadcast(
                from: nil,
                message: CommunitiesGenerated(
                    buildID: 10,
                    communityByNodeID: [
                        fixture.nodeIDs[0]: fixture.communityID,
                        fixture.nodeIDs[1]: fixture.communityID
                    ]
                )
            )
            try await waitUntil {
                await fixture.collector.count() == 1
            }

            let requests = await fixture.textResponder.requests()

            #expect(requests.count > 1)
        }
    }

    @Test("community recursive summary suppresses duplicate reductions while in flight")
    func communityRecursiveSummarySuppressesDuplicateReductionsWhileInFlight() async throws {
        try await withOversizedCommunityFixture(completesAutomatically: false) { fixture in
            let event = CommunitiesGenerated(
                buildID: 13,
                communityByNodeID: [
                    fixture.nodeIDs[0]: fixture.communityID,
                    fixture.nodeIDs[1]: fixture.communityID
                ]
            )

            await fixture.actorSystem.broadcast(from: nil, message: event)
            try await waitUntil {
                await fixture.textResponder.callCount() == 1
            }
            await fixture.actorSystem.broadcast(from: nil, message: event)
            try await Task.sleep(for: .milliseconds(80))

            let callCount = await fixture.textResponder.callCount()
            #expect(callCount == 1)
        }
    }
}
