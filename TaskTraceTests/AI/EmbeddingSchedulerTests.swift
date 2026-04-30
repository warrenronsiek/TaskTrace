import Foundation
import Testing
@testable import TaskTrace

@MainActor
struct EmbeddingSchedulerTests {
    private actor RecordingEmbeddingExecutor {
        private var batchSizes: [Int] = []
        private var sources: [String] = []

        func execute(_ request: ModelEmbeddingRequest) async throws -> [[Float]] {
            batchSizes.append(request.texts.count)
            sources.append(request.source)

            return request.texts.indices.map { index in
                [Float(index + 1), 0, 0]
            }
        }

        func recordedBatchSizes() -> [Int] {
            batchSizes
        }

        func recordedSources() -> [String] {
            sources
        }
    }

    private actor BlockingEmbeddingExecutor {
        private var startedCount = 0
        private var pendingReleaseCount = 0
        private var startedContinuations: [(Int, CheckedContinuation<Void, Never>)] = []
        private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

        func execute(_ request: ModelEmbeddingRequest) async throws -> [[Float]] {
            startedCount += 1
            resumeStartedContinuations()

            if pendingReleaseCount > 0 {
                pendingReleaseCount -= 1
            } else {
                await withCheckedContinuation {
                    releaseContinuations.append($0)
                }
            }

            return request.texts.map { _ in [1, 0, 0] }
        }

        func waitUntilStarted(_ count: Int) async {
            guard startedCount < count else {
                return
            }

            await withCheckedContinuation {
                startedContinuations.append((count, $0))
            }
        }

        func releaseNext() {
            guard !releaseContinuations.isEmpty else {
                pendingReleaseCount += 1
                return
            }

            releaseContinuations.removeFirst().resume()
        }

        private func resumeStartedContinuations() {
            let ready = startedContinuations.filter { startedCount >= $0.0 }
            startedContinuations.removeAll { startedCount >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }

    private func register(
        scheduler: AIEmbeddingModelScheduler,
        bridge: AISchedulerEventBridge,
        actorSystem: ActorSystem
    ) async {
        await scheduler.attach(actorSystem: actorSystem)
        await bridge.attach(actorSystem: actorSystem)
        _ = await actorSystem.register(bridge)
        _ = await actorSystem.register(scheduler)
    }

    @Test("embedding scheduler batches same-prefix single text requests")
    func embeddingSchedulerBatchesSamePrefixSingleTextRequests() async throws {
        let executor = RecordingEmbeddingExecutor()
        let scheduler = AIEmbeddingModelScheduler(
            maxBatchSize: 8,
            maxWaitMilliseconds: 1,
            executor: { request in
                try await executor.execute(request)
            }
        )
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let first = bridge.requestEmbedding(
            ModelEmbeddingRequest(
                source: "test",
                priority: .background,
                texts: ["first"]
            )
        )
        async let second = bridge.requestEmbedding(
            ModelEmbeddingRequest(
                source: "test",
                priority: .background,
                texts: ["second"]
            )
        )
        async let third = bridge.requestEmbedding(
            ModelEmbeddingRequest(
                source: "test",
                priority: .background,
                texts: ["third"]
            )
        )

        _ = try await (first, second, third)
        let batchSizes = await executor.recordedBatchSizes()
        #expect(batchSizes == [3])
    }

    @Test("embedding scheduler defaults batch up to sixty four requests")
    func embeddingSchedulerDefaultsBatchUpToSixtyFourRequests() async throws {
        let executor = RecordingEmbeddingExecutor()
        let scheduler = AIEmbeddingModelScheduler(
            maxWaitMilliseconds: 1,
            executor: { request in
                try await executor.execute(request)
            }
        )
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        let requests = (0..<65).map {
            ModelEmbeddingRequest(
                source: "test",
                priority: .background,
                texts: ["text-\($0)"]
            )
        }
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        try await withThrowingTaskGroup(of: [[Float]].self) { group in
            requests.forEach { request in
                group.addTask {
                    try await bridge.requestEmbedding(request)
                }
            }

            for try await _ in group {}
        }
        let batchSizes = await executor.recordedBatchSizes()

        #expect((batchSizes.count, batchSizes.reduce(0, +), batchSizes.max() ?? 0) == (2, 65, 64))
    }

    @Test("embedding scheduler splits large multi-text requests at the row cap")
    func embeddingSchedulerSplitsLargeMultiTextRequestsAtTheRowCap() async throws {
        let executor = RecordingEmbeddingExecutor()
        let scheduler = AIEmbeddingModelScheduler(
            maxWaitMilliseconds: 1,
            executor: { request in
                try await executor.execute(request)
            }
        )
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        let vectors = try await bridge.requestEmbedding(
            ModelEmbeddingRequest(
                source: "test",
                priority: .background,
                texts: (0..<300).map { "text-\($0)" }
            )
        )
        let batchSizes = await executor.recordedBatchSizes()

        #expect((vectors.count, batchSizes) == (300, [256, 44]))
    }

    @Test("embedding scheduler throughput counts text rows")
    func embeddingSchedulerThroughputCountsTextRows() async throws {
        let executor = RecordingEmbeddingExecutor()
        let scheduler = AIEmbeddingModelScheduler(
            maxWaitMilliseconds: 1,
            executor: { request in
                try await executor.execute(request)
            }
        )
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        _ = try await bridge.requestEmbedding(
            ModelEmbeddingRequest(
                source: "test",
                priority: .background,
                texts: (0..<5).map { "text-\($0)" }
            )
        )
        let snapshot = await scheduler.statsSnapshot()
        let processedRecords = snapshot.queuedDepthByBucket
            .first?
            .processedRecordsTimeline
            .recordCounts
            .reduce(0, +)

        #expect((snapshot.processedRecordsLast60Seconds, processedRecords ?? 0, snapshot.averageBatchSize) == (5, 5, 1.0))
    }

    @Test("embedding scheduler counts processed rows by event kind")
    func embeddingSchedulerCountsProcessedRowsByEventKind() async throws {
        let executor = RecordingEmbeddingExecutor()
        let scheduler = AIEmbeddingModelScheduler(
            maxWaitMilliseconds: 1,
            executor: { request in
                try await executor.execute(request)
            }
        )
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        _ = try await bridge.requestEmbedding(
            ModelEmbeddingRequest(
                source: "knowledge-node-embedding",
                priority: .background,
                texts: (0..<5).map { "text-\($0)" }
            )
        )
        let timeline = await scheduler.statsSnapshot()
            .queuedDepthByBucket
            .first?
            .processedRecordsTimelineByKind
            .first
        let result = "\(timeline?.eventKind ?? ""):\(timeline?.processedRecordsLast60Seconds ?? 0):\(timeline?.timeline.recordCounts.reduce(0, +) ?? 0)"

        #expect(result == "knowledge-node-embedding:5:5")
    }

    @Test("embedding scheduler exposes active event kind")
    func embeddingSchedulerExposesActiveEventKind() async throws {
        let executor = BlockingEmbeddingExecutor()
        let scheduler = AIEmbeddingModelScheduler(
            maxWaitMilliseconds: 1,
            executor: { request in
                try await executor.execute(request)
            }
        )
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let vectors = bridge.requestEmbedding(
            ModelEmbeddingRequest(
                source: "knowledge-node-embedding",
                priority: .background,
                texts: ["node"]
            )
        )
        await executor.waitUntilStarted(1)
        let bucket = await scheduler.statsSnapshot().queuedDepthByBucket.first
        let activeBatch = bucket?.activeBatches.first
        let breakdown = bucket?.eventKindBreakdown.first
        let result = (
            activeBatch?.eventKind,
            activeBatch?.recordCount ?? 0,
            breakdown?.eventKind,
            breakdown?.activeRecordCount ?? 0
        )
        await executor.releaseNext()
        _ = try await vectors

        #expect(result == ("knowledge-node-embedding", 1, "knowledge-node-embedding", 1))
    }

    @Test("embedding client forwards caller source")
    func embeddingClientForwardsCallerSource() async {
        let executor = RecordingEmbeddingExecutor()
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            embeddingExecutor: { request in
                try await executor.execute(request)
            }
        )
        await registry.register(on: actorSystem)
        let client = AISchedulerClient(registry: registry)

        _ = await client.generateVectors(
            for: ["query"],
            promptPrefix: nil,
            source: "graph-rag-query-embedding"
        )

        #expect(await executor.recordedSources() == ["graph-rag-query-embedding"])
    }

    @Test("embedding scheduler keeps different prefixes in separate batches")
    func embeddingSchedulerKeepsDifferentPrefixesInSeparateBatches() async throws {
        let executor = RecordingEmbeddingExecutor()
        let scheduler = AIEmbeddingModelScheduler(
            maxBatchSize: 8,
            maxWaitMilliseconds: 1,
            executor: { request in
                try await executor.execute(request)
            }
        )
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let first = bridge.requestEmbedding(
            ModelEmbeddingRequest(
                source: "test",
                priority: .background,
                texts: ["first"],
                promptPrefix: "query:"
            )
        )
        async let second = bridge.requestEmbedding(
            ModelEmbeddingRequest(
                source: "test",
                priority: .background,
                texts: ["second"],
                promptPrefix: "passage:"
            )
        )

        _ = try await (first, second)
        let batchSizes = await executor.recordedBatchSizes().sorted()
        #expect(batchSizes == [1, 1])
    }
}
