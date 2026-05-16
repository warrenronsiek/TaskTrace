import Foundation
import MLXLMCommon
import Testing
@testable import TaskTrace

struct AISchedulerTests {
    private actor BatchRecorder {
        private var batchSizes: [Int] = []
        private var batchLanes: [AITextModelLane] = []
        private var promptBatches: [[String]] = []
        private var continuations: [(Int, CheckedContinuation<Void, Never>)] = []

        func execute(_ batch: AITextSchedulerBatch) async throws -> [String] {
            batchSizes.append(batch.requests.count)
            batchLanes.append(batch.lane)
            promptBatches.append(batch.requests.map(\.prompt))
            resumeContinuations()
            return batch.requests.map { "response:\($0.prompt)" }
        }

        func sizes() -> [Int] {
            batchSizes
        }

        func prompts() -> [[String]] {
            promptBatches
        }

        func lanes() -> [AITextModelLane] {
            batchLanes
        }

        func waitUntilBatchCount(_ count: Int) async {
            guard batchSizes.count < count else {
                return
            }

            await withCheckedContinuation {
                continuations.append((count, $0))
            }
        }

        private func resumeContinuations() {
            let ready = continuations.filter { batchSizes.count >= $0.0 }
            continuations.removeAll { batchSizes.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }

    private actor BlockingBatchRecorder {
        private var activeCount = 0
        private var startedCount = 0
        private var maxActiveCount = 0
        private var pendingReleaseCount = 0
        private var startedContinuations: [(Int, CheckedContinuation<Void, Never>)] = []
        private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

        func execute(_ batch: AITextSchedulerBatch) async throws -> [String] {
            activeCount += 1
            startedCount += 1
            maxActiveCount = max(maxActiveCount, activeCount)
            resumeStartedContinuations()

            if pendingReleaseCount > 0 {
                pendingReleaseCount -= 1
            } else {
                await withCheckedContinuation {
                    releaseContinuations.append($0)
                }
            }

            activeCount = max(activeCount - 1, 0)
            return batch.requests.map { "response:\($0.prompt)" }
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

        func maximumActiveCount() -> Int {
            maxActiveCount
        }

        private func resumeStartedContinuations() {
            let ready = startedContinuations.filter { startedCount >= $0.0 }
            startedContinuations.removeAll { startedCount >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }

    private actor StreamingRecorder {
        private var normalStartedCount = 0
        private var streamStartedCount = 0
        private var streamContinuations: [AsyncThrowingStream<String, Error>.Continuation] = []
        private var streamStartedContinuations: [CheckedContinuation<Void, Never>] = []

        func execute(_ batch: AITextSchedulerBatch) async throws -> [String] {
            normalStartedCount += 1
            return batch.requests.map { "response:\($0.prompt)" }
        }

        func stream(
            prompt: String,
            instructions: String,
            generateParameters: GenerateParameters,
            additionalContext: [String: any Sendable]?,
            telemetryMetadata: [String: String]
        ) async -> AsyncThrowingStream<String, Error> {
            streamStartedCount += 1
            let pending = streamStartedContinuations
            streamStartedContinuations.removeAll()
            pending.forEach { $0.resume() }
            let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
            streamContinuations.append(continuation)
            return stream
        }

        func waitUntilStreamStarted() async {
            guard streamStartedCount == 0 else {
                return
            }

            await withCheckedContinuation {
                streamStartedContinuations.append($0)
            }
        }

        func finishStream() {
            guard !streamContinuations.isEmpty else {
                return
            }

            let continuation = streamContinuations.removeFirst()
            continuation.yield("chunk")
            continuation.finish()
        }

        func normalStarts() -> Int {
            normalStartedCount
        }
    }

    private actor MultiKindBlockingRecorder {
        private var activeCount = 0
        private var startedCount = 0
        private var maxActiveCount = 0
        private var pendingReleaseCount = 0
        private var startedContinuations: [(Int, CheckedContinuation<Void, Never>)] = []
        private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

        func executeText(_ batch: AITextSchedulerBatch) async throws -> [String] {
            await blockUntilReleased()
            return batch.requests.map { "text:\($0.prompt)" }
        }

        func executeVisual(_ batch: AIVisualSchedulerBatch) async throws -> [String] {
            await blockUntilReleased()
            return batch.requests.map { _ in "visual" }
        }

        func executeEmbedding(_ request: ModelEmbeddingRequest) async throws -> [[Float]] {
            await blockUntilReleased()
            return request.texts.map { _ in [1, 0, 0] }
        }

        func executeRerank(_ request: ModelRerankRequest) async throws -> [ActivityAIReranking] {
            await blockUntilReleased()
            return request.documents.indices.map {
                ActivityAIReranking(documentIndex: $0, score: Float(request.documents.count - $0))
            }
        }

        func executeUMAP(_ request: ModelUMAPRequest) async throws -> [[Float]] {
            await blockUntilReleased()
            return request.vectors
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

        func maximumActiveCount() -> Int {
            maxActiveCount
        }

        private func blockUntilReleased() async {
            activeCount += 1
            startedCount += 1
            maxActiveCount = max(maxActiveCount, activeCount)
            resumeStartedContinuations()

            if pendingReleaseCount > 0 {
                pendingReleaseCount -= 1
            } else {
                await withCheckedContinuation {
                    releaseContinuations.append($0)
                }
            }

            activeCount = max(activeCount - 1, 0)
        }

        private func resumeStartedContinuations() {
            let ready = startedContinuations.filter { startedCount >= $0.0 }
            startedContinuations.removeAll { startedCount >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }

    private actor TextCompletionCollector: Receiver {
        private let expectedID: UUID
        private var completion: ModelTextCompleted?
        private var continuations: [CheckedContinuation<ModelTextCompleted, Never>] = []

        init(expectedID: UUID) {
            self.expectedID = expectedID
        }

        func receive(_ envelope: Envelope) async {
            guard let event = envelope.message as? ModelTextCompleted,
                  event.requestID == expectedID else {
                return
            }

            completion = event
            let pending = continuations
            continuations.removeAll()
            pending.forEach { $0.resume(returning: event) }
        }

        func waitForCompletion() async -> ModelTextCompleted {
            if let completion {
                return completion
            }

            return await withCheckedContinuation {
                continuations.append($0)
            }
        }
    }

    private actor VisualRequestRecorder {
        private var request: ModelVisualRequest?
        private var batchSizes: [Int] = []

        func execute(_ batch: AIVisualSchedulerBatch) async throws -> [String] {
            self.request = batch.requests.first
            batchSizes.append(batch.requests.count)
            return batch.requests.map { _ in "visual-ok" }
        }

        func capturedPrompt() -> String? {
            request?.prompt
        }

        func capturedEnableThinking() -> Bool? {
            request?.additionalContext?["enable_thinking"] as? Bool
        }

        func recordedBatchSizes() -> [Int] {
            batchSizes
        }
    }

    private actor RerankRequestRecorder {
        private var sources: [String] = []

        func execute(_ request: ModelRerankRequest) async throws -> [ActivityAIReranking] {
            sources.append(request.source)

            return request.documents.indices.map {
                ActivityAIReranking(documentIndex: $0, score: Float(request.documents.count - $0))
            }
        }

        func recordedSources() -> [String] {
            sources
        }
    }

    private func register(
        scheduler: AITextModelScheduler,
        bridge: AISchedulerEventBridge,
        actorSystem: ActorSystem
    ) async {
        await scheduler.attach(actorSystem: actorSystem)
        await bridge.attach(actorSystem: actorSystem)
        _ = await actorSystem.register(bridge)
        _ = await actorSystem.register(scheduler)
    }

    private func textRequest(
        id: UUID = UUID(),
        source: String = "test",
        prompt: String,
        instructions: String = "Summarize",
        priority: AIExecutionPriority = .interactive,
        promptTokenEstimate: Int? = nil,
        metadata: [String: String] = [:]
    ) -> ModelTextRequest {
        ModelTextRequest(
            requestID: id,
            source: source,
            priority: priority,
            prompt: prompt,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: 32, temperature: 0),
            additionalContext: ["enable_thinking": false],
            promptTokenEstimate: promptTokenEstimate,
            metadata: metadata
        )
    }

    @Test("text token buckets assign 8193+ prompts to the largest bucket")
    func textTokenBucketsAssignLargestBucket() {
        #expect(AITextTokenBucket.bucket(for: 8_193) == .over8192)
    }

    @Test("text token bucket safety multipliers decline geometrically")
    func textTokenBucketSafetyMultipliersDeclineGeometrically() {
        let multipliers = AITextTokenBucket.allCases.map(\.safetyMultiplier)

        #expect(multipliers == [0.5, 0.707_106_781_186_5476, 1.0, 1.414_213_562_373_0951, 2.0, 2.0])
    }

    @Test("queue scoring gives interactive work priority over deeper background work")
    func queueScoringPrioritizesInteractiveWork() {
        let interactiveScore = AITextSchedulerPolicy.score(
            priority: .interactive,
            oldestAgeSeconds: 0,
            queueDepth: 1
        )
        let backgroundScore = AITextSchedulerPolicy.score(
            priority: .background,
            oldestAgeSeconds: 30,
            queueDepth: 10
        )

        #expect(interactiveScore > backgroundScore)
    }

    @Test("text lane policy routes simple summary sources to the small model")
    func textLanePolicyRoutesSimpleSummarySourcesToSmallModel() {
        let sources = [
            "activity-summary",
            "screenshot-summary",
            "overview-merge",
            "activity-tag-ontology-summary",
            "ontology-overview-summary",
            "knowledge-community-summary",
            "knowledge-obsidian-summary"
        ]
        let lanes = sources.map {
            AITextModelLanePolicy.lane(
                for: textRequest(source: $0, prompt: "small", promptTokenEstimate: 200)
            )
        }

        #expect(lanes == Array(repeating: .small, count: sources.count))
    }

    @Test("text lane policy routes complex and unknown sources to the big model")
    func textLanePolicyRoutesComplexAndUnknownSourcesToBigModel() {
        let sources = [
            "knowledge-chunk-graph",
            "knowledge-node-coalesce",
            "knowledge-edge-coalesce",
            "skill_procedure",
            "generic_stream",
            "direct-text",
            "direct-text-batch",
            "activity-goal-todo-assignment",
            "unknown"
        ]
        let lanes = sources.map {
            AITextModelLanePolicy.lane(
                for: textRequest(source: $0, prompt: "big", promptTokenEstimate: 200)
            )
        }

        #expect(lanes == Array(repeating: .big, count: sources.count))
    }

    @Test("text lane policy sends oversized summary prompts to the big model")
    func textLanePolicySendsOversizedSummaryPromptsToBigModel() {
        let lane = AITextModelLanePolicy.lane(
            for: textRequest(source: "activity-summary", prompt: "large", promptTokenEstimate: 4_097)
        )

        #expect(lane == .big)
    }

    @Test("text lane policy sends long output requests to the big model")
    func textLanePolicySendsLongOutputRequestsToBigModel() {
        let request = ModelTextRequest(
            source: "activity-summary",
            priority: .interactive,
            prompt: "small prompt",
            instructions: "Summarize",
            generateParameters: GenerateParameters(maxTokens: 513, temperature: 0),
            additionalContext: ["enable_thinking": false],
            promptTokenEstimate: 200,
            metadata: ["event_kind": "activity-summary"]
        )

        #expect(AITextModelLanePolicy.lane(for: request) == .big)
    }

    @Test("same-signature small text requests batch together")
    func sameSignatureSmallTextRequestsBatchTogether() async throws {
        let recorder = BatchRecorder()
        let scheduler = AITextModelScheduler(maxBatchSize: 4, maxWaitMilliseconds: 10) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let first = bridge.requestText(textRequest(prompt: "first", promptTokenEstimate: 200))
        async let second = bridge.requestText(textRequest(prompt: "second", promptTokenEstimate: 220))
        _ = try await (first, second)

        #expect(await recorder.sizes() == [2])
    }

    @Test("registry sends compatible small lane requests as one true batch")
    func registrySendsCompatibleSmallLaneRequestsAsOneTrueBatch() async throws {
        let recorder = BatchRecorder()
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            textExecutor: { try await recorder.execute($0) }
        )
        await registry.register(on: actorSystem)

        async let first = registry.requestText(
            textRequest(source: "activity-summary", prompt: "first", promptTokenEstimate: 200)
        )
        async let second = registry.requestText(
            textRequest(source: "activity-summary", prompt: "second", promptTokenEstimate: 220)
        )
        _ = try await (first, second)
        let sizes = await recorder.sizes()
        let lanes = await recorder.lanes()

        #expect((sizes, lanes) == ([2], [.small]))
    }

    @Test("registry does not batch small and big lane requests together")
    func registryDoesNotBatchSmallAndBigLaneRequestsTogether() async throws {
        let recorder = BatchRecorder()
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            textExecutor: { try await recorder.execute($0) }
        )
        await registry.register(on: actorSystem)

        async let small = registry.requestText(
            textRequest(source: "activity-summary", prompt: "small", promptTokenEstimate: 200)
        )
        async let big = registry.requestText(
            textRequest(source: "knowledge-chunk-graph", prompt: "big", promptTokenEstimate: 220)
        )
        _ = try await (small, big)
        let lanes = await recorder.lanes()
        let sizes = await recorder.sizes()
        let result = zip(lanes, sizes)
            .map { "\($0.0.rawValue):\($0.1)" }
            .sorted()

        #expect(result == ["big:1", "small:1"])
    }

    @Test("registry exposes separate text scheduler snapshots")
    func registryExposesSeparateTextSchedulerSnapshots() async {
        let registry = AISchedulerRegistry()
        let actorSystem = ActorSystem()
        await registry.register(on: actorSystem)
        let textSnapshotIDs = await registry.aiSchedulerSnapshots()
            .map(\.id)
            .filter { $0.hasPrefix("text") }

        #expect(textSnapshotIDs == [AIModelSchedulerKind.textSmall.rawValue, AIModelSchedulerKind.textBig.rawValue])
    }

    @Test("text scheduler defaults batch up to eight small requests")
    func textSchedulerDefaultsBatchUpToEightSmallRequests() async throws {
        let recorder = BatchRecorder()
        let scheduler = AITextModelScheduler(maxWaitMilliseconds: 1) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        let requests = (0..<9).map {
            textRequest(prompt: "request-\($0)", promptTokenEstimate: 200)
        }
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        try await withThrowingTaskGroup(of: String.self) { group in
            requests.forEach { request in
                group.addTask {
                    try await bridge.requestText(request)
                }
            }

            for try await _ in group {}
        }

        #expect(await recorder.sizes().sorted() == [1, 8])
    }

    @Test("text scheduler default active batch slots are four")
    func textSchedulerDefaultActiveBatchSlotsAreFour() async throws {
        let recorder = BlockingBatchRecorder()
        let scheduler = AITextModelScheduler(
            maxBatchSize: 1,
            maxWaitMilliseconds: 1
        ) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        let requests = (0..<5).map { index in
            textRequest(
                source: "source-\(index)",
                prompt: "request-\(index)",
                instructions: "Instruction \(index)",
                promptTokenEstimate: 200
            )
        }
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        let tasks = requests.map { request in
            Task {
                try await bridge.requestText(request)
            }
        }
        await recorder.waitUntilStarted(4)
        let maximumBeforeRelease = await recorder.maximumActiveCount()
        for _ in 0..<5 {
            await recorder.releaseNext()
        }
        for task in tasks {
            _ = try await task.value
        }

        #expect(maximumBeforeRelease == 4)
    }

    @Test("interactive text work shortens a pending background flush")
    func interactiveTextWorkShortensPendingBackgroundFlush() async throws {
        let recorder = BlockingBatchRecorder()
        let scheduler = AITextModelScheduler(
            maxBatchSize: 2,
            maxWaitMilliseconds: 1,
            backgroundMaxWaitMilliseconds: 200,
            maxActiveBatches: 1
        ) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let background = bridge.requestText(
            textRequest(
                prompt: "background",
                priority: .background,
                promptTokenEstimate: 200
            )
        )
        try await Task.sleep(for: .milliseconds(50))
        let startedBeforeInteractive = await recorder.maximumActiveCount()
        async let interactive = bridge.requestText(
            textRequest(
                prompt: "interactive",
                priority: .interactive,
                promptTokenEstimate: 200
            )
        )
        await recorder.waitUntilStarted(1)
        let startedAfterInteractive = await recorder.maximumActiveCount()
        await recorder.releaseNext()
        _ = try await (background, interactive)

        #expect((startedBeforeInteractive, startedAfterInteractive) == (0, 1))
    }

    @Test("singleton completion does not cap later same bucket batches")
    func singletonCompletionDoesNotCapLaterSameBucketBatches() async throws {
        let recorder = BatchRecorder()
        let scheduler = AITextModelScheduler(
            maxBatchSize: 8,
            maxWaitMilliseconds: 1,
            maxActiveBatches: 1
        ) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        let laterRequests = (0..<8).map {
            textRequest(prompt: "later-\($0)", promptTokenEstimate: 1_500)
        }
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        _ = try await bridge.requestText(textRequest(prompt: "single", promptTokenEstimate: 1_500))
        try await withThrowingTaskGroup(of: String.self) { group in
            laterRequests.forEach { request in
                group.addTask {
                    try await bridge.requestText(request)
                }
            }

            for try await _ in group {}
        }

        #expect(await recorder.sizes() == [1, 8])
    }

    @Test("text memory estimates respond to generation and kv settings")
    func textMemoryEstimatesRespondToGenerationAndKVSettings() {
        let promptTokens = [1_200]
        let shortEstimate = AITextSchedulerPolicy.estimatedBatchMemoryBytes(
            promptTokens: promptTokens,
            generateParameters: [GenerateParameters(maxTokens: 120, temperature: 0)]
        )
        let longEstimate = AITextSchedulerPolicy.estimatedBatchMemoryBytes(
            promptTokens: promptTokens,
            generateParameters: [GenerateParameters(maxTokens: 240, temperature: 0)]
        )
        let cappedKVEstimate = AITextSchedulerPolicy.estimatedBatchMemoryBytes(
            promptTokens: promptTokens,
            generateParameters: [GenerateParameters(maxTokens: 240, maxKVSize: 512, temperature: 0)]
        )
        let quantizedKVEstimate = AITextSchedulerPolicy.estimatedBatchMemoryBytes(
            promptTokens: promptTokens,
            generateParameters: [GenerateParameters(maxTokens: 240, kvBits: 4, temperature: 0)]
        )

        #expect(shortEstimate < longEstimate && cappedKVEstimate < longEstimate && quantizedKVEstimate < longEstimate)
    }

    @Test("text memory estimates charge mixed prompt batches at padded length")
    func textMemoryEstimatesChargeMixedPromptBatchesAtPaddedLength() {
        let parameters = Array(
            repeating: GenerateParameters(maxTokens: 120, temperature: 0),
            count: 2
        )
        let mixedEstimate = AITextSchedulerPolicy.estimatedBatchMemoryBytes(
            promptTokens: [100, 400],
            generateParameters: parameters
        )
        let paddedEstimate = AITextSchedulerPolicy.estimatedBatchMemoryBytes(
            promptTokens: [400, 400],
            generateParameters: parameters
        )

        #expect(mixedEstimate == paddedEstimate)
    }

    @Test("text memory estimates include prefill workspace for long prompts")
    func textMemoryEstimatesIncludePrefillWorkspaceForLongPrompts() {
        let shortBreakdown = AITextSchedulerPolicy.estimatedBatchMemoryBreakdown(
            promptTokens: [3_000],
            generateParameters: [GenerateParameters(maxTokens: 220, temperature: 0)]
        )
        let longBreakdown = AITextSchedulerPolicy.estimatedBatchMemoryBreakdown(
            promptTokens: [6_000],
            generateParameters: [GenerateParameters(maxTokens: 220, temperature: 0)]
        )

        #expect(longBreakdown.prefillAttentionBytes > shortBreakdown.prefillAttentionBytes && longBreakdown.totalBytes > shortBreakdown.totalBytes)
    }

    @Test("text memory estimates respond to prefill step size")
    func textMemoryEstimatesRespondToPrefillStepSize() {
        let smallerPrefill = AITextSchedulerPolicy.estimatedBatchMemoryBreakdown(
            promptTokens: [6_000],
            generateParameters: [GenerateParameters(maxTokens: 220, temperature: 0, prefillStepSize: 256)]
        )
        let defaultPrefill = AITextSchedulerPolicy.estimatedBatchMemoryBreakdown(
            promptTokens: [6_000],
            generateParameters: [GenerateParameters(maxTokens: 220, temperature: 0)]
        )

        #expect(smallerPrefill.prefillAttentionBytes < defaultPrefill.prefillAttentionBytes)
    }

    @Test("text scheduler exposes active batch records by bucket")
    func textSchedulerExposesActiveBatchRecordsByBucket() async throws {
        let recorder = BlockingBatchRecorder()
        let scheduler = AITextModelScheduler(
            maxBatchSize: 4,
            maxWaitMilliseconds: 1,
            maxActiveBatches: 1
        ) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let first = bridge.requestText(textRequest(prompt: "first", promptTokenEstimate: 200))
        async let second = bridge.requestText(textRequest(prompt: "second", promptTokenEstimate: 220))
        await recorder.waitUntilStarted(1)
        let snapshot = await scheduler.statsSnapshot()
        let activeBatch = snapshot.queuedDepthByBucket
            .first { $0.id == AITextTokenBucket.upTo512.rawValue }?
            .activeBatches
            .first
        await recorder.releaseNext()
        _ = try await (first, second)

        #expect((snapshot.activeRecordCount, activeBatch?.recordCount ?? 0, activeBatch?.batchSize ?? 0) == (2, 2, 2))
    }

    @Test("text scheduler reports active estimated memory against cap")
    func textSchedulerReportsActiveEstimatedMemoryAgainstCap() async throws {
        let recorder = BlockingBatchRecorder()
        let scheduler = AITextModelScheduler(
            maxBatchSize: 4,
            maxWaitMilliseconds: 1,
            maxActiveBatches: 1
        ) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let first = bridge.requestText(textRequest(prompt: "first", promptTokenEstimate: 200))
        async let second = bridge.requestText(textRequest(prompt: "second", promptTokenEstimate: 220))
        await recorder.waitUntilStarted(1)
        let snapshot = await scheduler.statsSnapshot()
        let activeBatchEstimate = snapshot.queuedDepthByBucket
            .first { $0.id == AITextTokenBucket.upTo512.rawValue }?
            .activeBatches
            .first?
            .estimatedMemoryBytes ?? 0
        let result = (
            snapshot.activeEstimatedMemoryBytes,
            activeBatchEstimate,
            snapshot.estimatedMemoryCapBytes ?? 0,
            snapshot.activeRecordCap ?? 0,
            (snapshot.capacityUtilization ?? 0) > 0
        )
        await recorder.releaseNext()
        _ = try await (first, second)

        #expect(result == (activeBatchEstimate, activeBatchEstimate, AITextSchedulerPolicy.softMemoryLimitBytes, 8, true))
    }

    @Test("text scheduler exposes active memory estimate breakdown")
    func textSchedulerExposesActiveMemoryEstimateBreakdown() async throws {
        let recorder = BlockingBatchRecorder()
        let scheduler = AITextModelScheduler(
            maxBatchSize: 1,
            maxWaitMilliseconds: 1,
            maxActiveBatches: 1
        ) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let request = bridge.requestText(textRequest(prompt: "large", promptTokenEstimate: 6_000))
        await recorder.waitUntilStarted(1)
        let prefillBytes = await scheduler.statsSnapshot()
            .queuedDepthByBucket
            .flatMap(\.activeBatches)
            .first?
            .memoryEstimateBreakdown?
            .prefillAttentionBytes ?? 0
        await recorder.releaseNext()
        _ = try await request

        #expect(prefillBytes > 0)
    }

    @Test("text scheduler exposes queued and active event kinds")
    func textSchedulerExposesQueuedAndActiveEventKinds() async throws {
        let recorder = BlockingBatchRecorder()
        let scheduler = AITextModelScheduler(
            maxBatchSize: 1,
            maxWaitMilliseconds: 1,
            maxActiveBatches: 1
        ) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let first = bridge.requestText(
            textRequest(
                source: "activity-summary",
                prompt: "first",
                promptTokenEstimate: 200
            )
        )
        await recorder.waitUntilStarted(1)
        async let second = bridge.requestText(
            textRequest(
                source: "knowledge-chunk-graph",
                prompt: "second",
                promptTokenEstimate: 220
            )
        )
        try? await Task.sleep(for: .milliseconds(50))
        let bucket = await scheduler.statsSnapshot()
            .queuedDepthByBucket
            .first { $0.id == AITextTokenBucket.upTo512.rawValue }
        let breakdown = bucket?.eventKindBreakdown.reduce(into: [String: (Int, Int, Int)]()) { partial, item in
            partial[item.eventKind] = (item.queuedDepth, item.activeRequestCount, item.activeRecordCount)
        } ?? [:]
        let activeBatch = bucket?.activeBatches.first
        let result = [
            "\(bucket?.queuedDepth ?? 0)",
            activeBatch?.eventKind ?? "",
            "\(activeBatch?.maxTokens ?? 0)",
            "\(activeBatch?.promptTokenEstimate ?? 0)",
            "\(breakdown["activity-summary"]?.0 ?? 0)",
            "\(breakdown["activity-summary"]?.1 ?? 0)",
            "\(breakdown["activity-summary"]?.2 ?? 0)",
            "\(breakdown["knowledge-chunk-graph"]?.0 ?? 0)",
            "\(breakdown["knowledge-chunk-graph"]?.1 ?? 0)",
            "\(breakdown["knowledge-chunk-graph"]?.2 ?? 0)"
        ]
        await recorder.releaseNext()
        await recorder.waitUntilStarted(2)
        await recorder.releaseNext()
        _ = try await (first, second)

        #expect(result == ["1", "activity-summary", "32", "200", "0", "1", "1", "1", "0", "0"])
    }

    @Test("text scheduler counts processed records in fifteen second buckets")
    func textSchedulerCountsProcessedRecordsInFifteenSecondBuckets() async throws {
        let recorder = BatchRecorder()
        let scheduler = AITextModelScheduler(maxBatchSize: 4, maxWaitMilliseconds: 1) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let first = bridge.requestText(textRequest(prompt: "first", promptTokenEstimate: 200))
        async let second = bridge.requestText(textRequest(prompt: "second", promptTokenEstimate: 220))
        _ = try await (first, second)
        let snapshot = await scheduler.statsSnapshot()
        let bucket = snapshot.queuedDepthByBucket.first { $0.id == AITextTokenBucket.upTo512.rawValue }
        let processedRecords = bucket?.processedRecordsTimeline.recordCounts.reduce(0, +) ?? 0
        let processedBatches = bucket?.processedRecordsTimeline.batchCounts.reduce(0, +) ?? 0
        let result = (
            snapshot.processedRecordsLast60Seconds,
            snapshot.recordsPerSecond > 0,
            processedRecords,
            processedBatches
        )

        #expect(result == (2, true, 2, 1))
    }

    @Test("text scheduler counts processed records by event kind")
    func textSchedulerCountsProcessedRecordsByEventKind() async throws {
        let recorder = BatchRecorder()
        let scheduler = AITextModelScheduler(maxBatchSize: 4, maxWaitMilliseconds: 1) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let first = bridge.requestText(
            textRequest(
                source: "activity-summary",
                prompt: "first",
                promptTokenEstimate: 200
            )
        )
        async let second = bridge.requestText(
            textRequest(
                source: "knowledge-chunk-graph",
                prompt: "second",
                promptTokenEstimate: 220
            )
        )
        _ = try await (first, second)
        let bucket = await scheduler.statsSnapshot()
            .queuedDepthByBucket
            .first { $0.id == AITextTokenBucket.upTo512.rawValue }
        let result = bucket?.processedRecordsTimelineByKind
            .map {
                "\($0.eventKind):\($0.processedRecordsLast60Seconds):\($0.timeline.recordCounts.reduce(0, +))"
            }
            .sorted() ?? []

        #expect(result == ["activity-summary:1:1", "knowledge-chunk-graph:1:1"])
    }

    @Test("different token buckets do not batch together")
    func differentTokenBucketsDoNotBatchTogether() async throws {
        let recorder = BatchRecorder()
        let scheduler = AITextModelScheduler(maxBatchSize: 4, maxWaitMilliseconds: 10) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let first = bridge.requestText(textRequest(prompt: "long", promptTokenEstimate: 6_712))
        async let second = bridge.requestText(textRequest(prompt: "medium", promptTokenEstimate: 1_069))
        _ = try await (first, second)

        #expect(await recorder.sizes().sorted() == [1, 1])
    }

    @Test("same bucket mixed prompt lengths pack all memory safe requests")
    func sameBucketMixedPromptLengthsPackAllMemorySafeRequests() async throws {
        let recorder = BatchRecorder()
        let scheduler = AITextModelScheduler(
            maxBatchSize: 8,
            maxWaitMilliseconds: 20,
            maxActiveBatches: 1
        ) {
            try await recorder.execute($0)
        }
        let requests = [
            textRequest(prompt: "outlier", promptTokenEstimate: 4_096),
            textRequest(prompt: "near-2100", promptTokenEstimate: 2_100),
            textRequest(prompt: "near-2200", promptTokenEstimate: 2_200),
            textRequest(prompt: "near-2300", promptTokenEstimate: 2_300),
            textRequest(prompt: "near-2400", promptTokenEstimate: 2_400),
            textRequest(prompt: "near-2500", promptTokenEstimate: 2_500),
            textRequest(prompt: "near-2600", promptTokenEstimate: 2_600)
        ]
        for request in requests {
            await scheduler.receive(Envelope(sender: nil, message: request))
        }
        await recorder.waitUntilBatchCount(1)

        #expect(await recorder.sizes() == [7])
    }

    @Test("same bucket equal sized candidates prefer lower padding waste")
    func sameBucketEqualSizedCandidatesPreferLowerPaddingWaste() async throws {
        let recorder = BatchRecorder()
        let scheduler = AITextModelScheduler(
            maxBatchSize: 3,
            maxWaitMilliseconds: 20,
            maxActiveBatches: 1
        ) {
            try await recorder.execute($0)
        }
        let requests = [
            textRequest(prompt: "bridge", promptTokenEstimate: 260),
            textRequest(prompt: "small-a", promptTokenEstimate: 100),
            textRequest(prompt: "small-b", promptTokenEstimate: 110),
            textRequest(prompt: "large-a", promptTokenEstimate: 400),
            textRequest(prompt: "large-b", promptTokenEstimate: 410)
        ]
        for request in requests {
            await scheduler.receive(Envelope(sender: nil, message: request))
        }
        await recorder.waitUntilBatchCount(1)
        let firstBatch = await recorder.prompts().first?.sorted()

        #expect(firstBatch == ["bridge", "large-a", "large-b"])
    }

    @Test("4097 to 8192 token text requests run as singleton batches")
    func largeTextBucketRunsSingletonBatches() async throws {
        let recorder = BatchRecorder()
        let scheduler = AITextModelScheduler(maxBatchSize: 4, maxWaitMilliseconds: 1) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let first = bridge.requestText(textRequest(prompt: "first", promptTokenEstimate: 6_000))
        async let second = bridge.requestText(textRequest(prompt: "second", promptTokenEstimate: 6_100))
        _ = try await (first, second)

        #expect(await recorder.sizes() == [1, 1])
    }

    @Test("text scheduler keeps finite local batch slots")
    func textSchedulerKeepsFiniteLocalBatchSlots() async throws {
        let recorder = BlockingBatchRecorder()
        let scheduler = AITextModelScheduler(
            maxBatchSize: 1,
            maxWaitMilliseconds: 1,
            maxActiveBatches: 2
        ) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let first = bridge.requestText(textRequest(prompt: "first", promptTokenEstimate: 200))
        async let second = bridge.requestText(textRequest(prompt: "second", promptTokenEstimate: 1_200))
        async let third = bridge.requestText(textRequest(prompt: "third", promptTokenEstimate: 2_400))
        await recorder.waitUntilStarted(2)
        await recorder.releaseNext()
        await recorder.waitUntilStarted(3)
        await recorder.releaseNext()
        await recorder.releaseNext()
        _ = try await (first, second, third)

        #expect(await recorder.maximumActiveCount() == 2)
    }

    @Test("over budget active text singleton prevents another active text batch")
    func overBudgetActiveTextSingletonPreventsAnotherActiveTextBatch() async throws {
        let recorder = BlockingBatchRecorder()
        let scheduler = AITextModelScheduler(
            maxBatchSize: 1,
            maxWaitMilliseconds: 1,
            maxActiveBatches: 2
        ) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let first = bridge.requestText(textRequest(prompt: "huge", promptTokenEstimate: 100_000))
        async let second = bridge.requestText(textRequest(prompt: "small", promptTokenEstimate: 200))
        await recorder.waitUntilStarted(1)
        await recorder.releaseNext()
        await recorder.waitUntilStarted(2)
        await recorder.releaseNext()
        _ = try await (first, second)

        #expect(await recorder.maximumActiveCount() == 1)
    }

    @Test("large active text batch blocks smaller queued text")
    func largeActiveTextBatchBlocksSmallerQueuedText() async throws {
        let recorder = BlockingBatchRecorder()
        let scheduler = AITextModelScheduler(
            maxBatchSize: 1,
            maxWaitMilliseconds: 10,
            maxActiveBatches: 2
        ) {
            try await recorder.execute($0)
        }
        let actorSystem = ActorSystem()
        let bridge = AISchedulerEventBridge()
        await register(scheduler: scheduler, bridge: bridge, actorSystem: actorSystem)

        async let active = bridge.requestText(
            textRequest(source: "active-large", prompt: "active", instructions: "active", promptTokenEstimate: 6_000)
        )
        await recorder.waitUntilStarted(1)
        async let small = bridge.requestText(
            textRequest(source: "small-waiting", prompt: "small", instructions: "small", promptTokenEstimate: 200)
        )
        try? await Task.sleep(for: .milliseconds(50))
        let activeSources = await scheduler.statsSnapshot()
            .queuedDepthByBucket
            .flatMap(\.activeBatches)
            .map(\.source)
            .sorted()
        await recorder.releaseNext()
        await recorder.waitUntilStarted(2)
        await recorder.releaseNext()
        _ = try await (active, small)

        #expect(activeSources == ["active-large"])
    }

    @Test("streaming text holds the text scheduler lane")
    func streamingTextHoldsTextSchedulerLane() async throws {
        let recorder = StreamingRecorder()
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            textExecutor: { try await recorder.execute($0) },
            streamTextExecutor: { _, prompt, instructions, generateParameters, additionalContext, telemetryMetadata in
                await recorder.stream(
                    prompt: prompt,
                    instructions: instructions,
                    generateParameters: generateParameters,
                    additionalContext: additionalContext,
                    telemetryMetadata: telemetryMetadata
                )
            }
        )
        await registry.register(on: actorSystem)

        let stream = await registry.streamText(
            prompt: "stream",
            instructions: "Stream",
            generateParameters: GenerateParameters(maxTokens: 32, temperature: 0)
        )
        await recorder.waitUntilStreamStarted()
        async let normal = registry.requestText(textRequest(prompt: "normal", promptTokenEstimate: 200))
        try? await Task.sleep(for: .milliseconds(50))
        let startsBeforeStreamFinishes = await recorder.normalStarts()
        await recorder.finishStream()
        _ = stream
        _ = try await normal

        #expect(startsBeforeStreamFinishes == 0)
    }

    @Test("different model schedulers run concurrently")
    func differentModelSchedulersRunConcurrently() async throws {
        let recorder = MultiKindBlockingRecorder()
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            textExecutor: { try await recorder.executeText($0) },
            visualExecutor: { try await recorder.executeVisual($0) },
            embeddingExecutor: { try await recorder.executeEmbedding($0) },
            rerankerExecutor: { try await recorder.executeRerank($0) },
            activityUMAPExecutor: { try await recorder.executeUMAP($0) }
        )
        await registry.register(on: actorSystem)

        async let text = registry.requestText(textRequest(prompt: "text", promptTokenEstimate: 200))
        async let visual = registry.requestVisual(
            ModelVisualRequest(
                source: "test",
                priority: .interactive,
                prompt: "describe",
                imageData: Data("image".utf8),
                instructions: "Describe",
                generateParameters: GenerateParameters(maxTokens: 32, temperature: 0)
            )
        )
        async let embedding = registry.requestEmbedding(
            ModelEmbeddingRequest(
                source: "test",
                priority: .background,
                texts: ["embedding"]
            )
        )
        async let rerank = registry.requestRerank(
            ModelRerankRequest(
                source: "test",
                priority: .interactive,
                query: "query",
                documents: ["one", "two"],
                instruction: "rank"
            )
        )
        async let umap = registry.requestUMAP(
            ModelUMAPRequest(
                source: "test",
                priority: .background,
                vectors: [[1, 2, 3]]
            )
        )

        await recorder.waitUntilStarted(5)
        await recorder.releaseNext()
        await recorder.releaseNext()
        await recorder.releaseNext()
        await recorder.releaseNext()
        await recorder.releaseNext()
        _ = try await (text, visual, embedding, rerank, umap)

        #expect(await recorder.maximumActiveCount() == 5)
    }

    @Test("event routing emits completions with matching request IDs")
    func eventRoutingMatchesRequestID() async {
        let actorSystem = ActorSystem()
        let requestID = UUID()
        let collector = TextCompletionCollector(expectedID: requestID)
        let scheduler = AITextModelScheduler(maxBatchSize: 2, maxWaitMilliseconds: 1) { batch in
            batch.requests.map { "response:\($0.prompt)" }
        }
        await scheduler.attach(actorSystem: actorSystem)
        _ = await actorSystem.register(scheduler)
        _ = await actorSystem.register(collector)

        await actorSystem.broadcast(
            from: nil,
            message: ModelTextCompleted(
                requestID: UUID(),
                response: "ignore",
                schedulerMetadata: AISchedulerMetadata(
                    scheduler: .textBig,
                    bucket: "test",
                    batchSize: 1,
                    source: "test"
                ),
                timing: AISchedulerTiming(
                    queuedAt: Date(),
                    startedAt: Date(),
                    finishedAt: Date()
                )
            )
        )
        await actorSystem.broadcast(
            from: nil,
            message: textRequest(id: requestID, prompt: "expected", promptTokenEstimate: 100)
        )
        let completion = await collector.waitForCompletion()

        #expect(completion.requestID == requestID)
    }

    @Test("visual client emits the restored screenshot prompt")
    func visualClientEmitsRestoredScreenshotPrompt() async {
        let recorder = VisualRequestRecorder()
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            visualExecutor: { batch in
                try await recorder.execute(batch)
            }
        )
        await registry.register(on: actorSystem)
        let client = AISchedulerClient(
            registry: registry
        )
        _ = await client.describeImage(Data("image".utf8))

        #expect(await recorder.capturedPrompt() == DescribeImageActor.prompt)
    }

    @Test("visual scheduler defaults batch up to four compatible screenshots")
    func visualSchedulerDefaultsBatchUpToFourCompatibleScreenshots() async throws {
        let recorder = VisualRequestRecorder()
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            visualExecutor: { batch in
                try await recorder.execute(batch)
            }
        )
        let requests = (0..<5).map { index in
            ModelVisualRequest(
                source: "test",
                priority: .interactive,
                prompt: "describe",
                imageData: Data("image-\(index)".utf8),
                instructions: "Describe",
                generateParameters: GenerateParameters(maxTokens: 32, temperature: 0),
                additionalContext: ["enable_thinking": false]
            )
        }
        await registry.register(on: actorSystem)

        try await withThrowingTaskGroup(of: String.self) { group in
            requests.forEach { request in
                group.addTask {
                    try await registry.requestVisual(request)
                }
            }

            for try await _ in group {}
        }

        #expect(await recorder.recordedBatchSizes().sorted() == [1, 4])
    }

    @Test("visual scheduler exposes active image batch records")
    func visualSchedulerExposesActiveImageBatchRecords() async throws {
        let recorder = MultiKindBlockingRecorder()
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            visualExecutor: { batch in
                try await recorder.executeVisual(batch)
            }
        )
        let requests = (0..<3).map { index in
            ModelVisualRequest(
                source: "test",
                priority: .interactive,
                prompt: "describe",
                imageData: Data("image-\(index)".utf8),
                instructions: "Describe",
                generateParameters: GenerateParameters(maxTokens: 32, temperature: 0),
                additionalContext: ["enable_thinking": false]
            )
        }
        await registry.register(on: actorSystem)
        let tasks = requests.map { request in
            Task {
                try await registry.requestVisual(request)
            }
        }

        await recorder.waitUntilStarted(1)
        let snapshot = await registry.aiSchedulerSnapshots()
            .first { $0.id == AIModelSchedulerKind.visual.rawValue }
        let activeBatch = snapshot?.queuedDepthByBucket.first?.activeBatches.first
        await recorder.releaseNext()
        for task in tasks {
            _ = try await task.value
        }

        #expect((snapshot?.activeRecordCount ?? 0, activeBatch?.batchSize ?? 0, activeBatch?.recordCount ?? 0) == (3, 3, 3))
    }

    @Test("visual scheduler reports active estimated memory against cap")
    func visualSchedulerReportsActiveEstimatedMemoryAgainstCap() async throws {
        let recorder = MultiKindBlockingRecorder()
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            visualExecutor: { batch in
                try await recorder.executeVisual(batch)
            }
        )
        let requests = (0..<2).map { index in
            ModelVisualRequest(
                source: "test",
                priority: .interactive,
                prompt: "describe",
                imageData: Data("image-\(index)".utf8),
                instructions: "Describe",
                generateParameters: GenerateParameters(maxTokens: 32, temperature: 0),
                additionalContext: ["enable_thinking": false]
            )
        }
        await registry.register(on: actorSystem)
        let tasks = requests.map { request in
            Task {
                try await registry.requestVisual(request)
            }
        }

        await recorder.waitUntilStarted(1)
        let snapshot = await registry.aiSchedulerSnapshots()
            .first { $0.id == AIModelSchedulerKind.visual.rawValue }
        let activeBatchEstimate = snapshot?.queuedDepthByBucket
            .first?
            .activeBatches
            .first?
            .estimatedMemoryBytes ?? 0
        let result = (
            snapshot?.activeEstimatedMemoryBytes ?? 0,
            activeBatchEstimate,
            snapshot?.estimatedMemoryCapBytes ?? 0
        )
        await recorder.releaseNext()
        for task in tasks {
            _ = try await task.value
        }

        #expect(result == (activeBatchEstimate, activeBatchEstimate, AIVisualSchedulerPolicy.softMemoryLimitBytes))
    }

    @Test("visual scheduler counts processed records by event kind")
    func visualSchedulerCountsProcessedRecordsByEventKind() async throws {
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            visualExecutor: { batch in
                batch.requests.map { _ in "visual-ok" }
            }
        )
        await registry.register(on: actorSystem)

        _ = try await registry.requestVisual(
            ModelVisualRequest(
                source: "image-description",
                priority: .interactive,
                prompt: "describe",
                imageData: Data("image".utf8),
                instructions: "Describe",
                generateParameters: GenerateParameters(maxTokens: 32, temperature: 0)
            )
        )
        let timeline = await registry.aiSchedulerSnapshots()
            .first { $0.id == AIModelSchedulerKind.visual.rawValue }?
            .queuedDepthByBucket
            .first?
            .processedRecordsTimelineByKind
            .first
        let result = "\(timeline?.eventKind ?? ""):\(timeline?.processedRecordsLast60Seconds ?? 0):\(timeline?.timeline.recordCounts.reduce(0, +) ?? 0)"

        #expect(result == "image-description:1:1")
    }

    @Test("reranker throughput counts documents")
    func rerankerThroughputCountsDocuments() async throws {
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            rerankerExecutor: { request in
                request.documents.indices.map {
                    ActivityAIReranking(documentIndex: $0, score: Float(request.documents.count - $0))
                }
            }
        )
        await registry.register(on: actorSystem)

        _ = try await registry.requestRerank(
            ModelRerankRequest(
                source: "test",
                priority: .interactive,
                query: "query",
                documents: ["one", "two", "three"],
                instruction: "rank"
            )
        )
        let snapshot = await registry.aiSchedulerSnapshots()
            .first { $0.id == AIModelSchedulerKind.reranker.rawValue }
        let processedRecords = snapshot?.queuedDepthByBucket
            .first?
            .processedRecordsTimeline
            .recordCounts
            .reduce(0, +)
        let timeline = snapshot?.queuedDepthByBucket
            .first?
            .processedRecordsTimelineByKind
            .first
        let result = "\(snapshot?.processedRecordsLast60Seconds ?? 0):\(processedRecords ?? 0):\((snapshot?.recordsPerSecond ?? 0) > 0):\(timeline?.eventKind ?? ""):\(timeline?.processedRecordsLast60Seconds ?? 0):\(timeline?.timeline.recordCounts.reduce(0, +) ?? 0)"

        #expect(result == "3:3:true:test:3:3")
    }

    @Test("reranking client forwards caller source")
    func rerankingClientForwardsCallerSource() async {
        let recorder = RerankRequestRecorder()
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            rerankerExecutor: { request in
                try await recorder.execute(request)
            }
        )
        await registry.register(on: actorSystem)
        let client = AISchedulerClient(registry: registry)

        _ = await client.generateRerankings(
            query: "query",
            documents: ["one", "two"],
            instruction: "rank",
            source: "search-reranking"
        )

        #expect(await recorder.recordedSources() == ["search-reranking"])
    }

    @Test("UMAP throughput counts vectors")
    func umapThroughputCountsVectors() async throws {
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            activityUMAPExecutor: { request in
                request.vectors
            }
        )
        await registry.register(on: actorSystem)

        _ = try await registry.requestUMAP(
            ModelUMAPRequest(
                source: "test",
                priority: .background,
                vectors: [[1, 0], [0, 1], [1, 1], [0, 0]]
            )
        )
        let snapshot = await registry.aiSchedulerSnapshots()
            .first { $0.id == AIModelSchedulerKind.activityUMAP.rawValue }
        let processedRecords = snapshot?.queuedDepthByBucket
            .first?
            .processedRecordsTimeline
            .recordCounts
            .reduce(0, +)
        let timeline = snapshot?.queuedDepthByBucket
            .first?
            .processedRecordsTimelineByKind
            .first
        let result = "\(snapshot?.processedRecordsLast60Seconds ?? 0):\(processedRecords ?? 0):\((snapshot?.recordsPerSecond ?? 0) > 0):\(timeline?.eventKind ?? ""):\(timeline?.processedRecordsLast60Seconds ?? 0):\(timeline?.timeline.recordCounts.reduce(0, +) ?? 0)"

        #expect(result == "4:4:true:test:4:4")
    }

    @Test("visual client disables Gemma thinking")
    func visualClientDisablesGemmaThinking() async {
        let recorder = VisualRequestRecorder()
        let actorSystem = ActorSystem()
        let registry = AISchedulerRegistry(
            visualExecutor: { batch in
                try await recorder.execute(batch)
            }
        )
        await registry.register(on: actorSystem)
        let client = AISchedulerClient(
            registry: registry
        )
        _ = await client.describeImage(Data("image".utf8))

        #expect(await recorder.capturedEnableThinking() == false)
    }
}
