//
//  AIScheduler.swift
//  TaskTrace
//

import Foundation
import MLX
import MLXLMCommon
import OSLog

nonisolated enum AISchedulerError: Error, Sendable {
    case unavailable(String)
    case responseCountMismatch(expected: Int, actual: Int)
}

nonisolated enum AIModelSchedulerKind: String, CaseIterable, Sendable {
    case textSmall
    case textBig
    case visual
    case embedding
    case reranker
    case activityUMAP

    var displayName: String {
        switch self {
        case .textSmall:
            "Text Small"
        case .textBig:
            "Text Big"
        case .visual:
            "Visual"
        case .embedding:
            "Embedding"
        case .reranker:
            "Reranker"
        case .activityUMAP:
            "Activity UMAP"
        }
    }
}

nonisolated struct AISchedulerMetadata: Sendable, Equatable {
    let scheduler: AIModelSchedulerKind
    let bucket: String
    let batchSize: Int
    let source: String
    let eventKind: String

    init(
        scheduler: AIModelSchedulerKind,
        bucket: String,
        batchSize: Int,
        source: String,
        eventKind: String? = nil
    ) {
        self.scheduler = scheduler
        self.bucket = bucket
        self.batchSize = batchSize
        self.source = source
        self.eventKind = eventKind ?? (source.isEmpty ? "unknown" : source)
    }
}

nonisolated struct AISchedulerTiming: Sendable, Equatable {
    let queuedAt: Date
    let startedAt: Date
    let finishedAt: Date

    var waitMilliseconds: Double {
        startedAt.timeIntervalSince(queuedAt) * 1000
    }

    var runMilliseconds: Double {
        finishedAt.timeIntervalSince(startedAt) * 1000
    }
}

nonisolated struct AISchedulerFailure: Identifiable, Sendable, Equatable {
    let id: UUID
    let requestID: UUID
    let message: String
    let retryable: Bool
    let occurredAt: Date
}

nonisolated enum AISchedulerStatsPolicy {
    static let timelineBucketDuration: TimeInterval = 15
    static let timelineBucketCount = 30
    static let timelineWindowDuration = timelineBucketDuration * Double(timelineBucketCount)
    static let throughputWindow: TimeInterval = 60
}

nonisolated struct AISchedulerProcessingTimeline: Sendable, Equatable {
    let bucketDuration: TimeInterval
    let windowDuration: TimeInterval
    let bucketProgress: Double
    let recordCounts: [Int]
    let batchCounts: [Int]

    static var empty: AISchedulerProcessingTimeline {
        AISchedulerProcessingTimeline(
            bucketDuration: AISchedulerStatsPolicy.timelineBucketDuration,
            windowDuration: AISchedulerStatsPolicy.timelineWindowDuration,
            bucketProgress: 0,
            recordCounts: Array(repeating: 0, count: AISchedulerStatsPolicy.timelineBucketCount),
            batchCounts: Array(repeating: 0, count: AISchedulerStatsPolicy.timelineBucketCount)
        )
    }
}

nonisolated struct AISchedulerEventKindTimelineSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    let eventKind: String
    let processedRecordsLast60Seconds: Int
    let recordsPerSecond: Double
    let timeline: AISchedulerProcessingTimeline

    init(
        eventKind: String,
        processedRecordsLast60Seconds: Int = 0,
        recordsPerSecond: Double = 0,
        timeline: AISchedulerProcessingTimeline = .empty
    ) {
        self.id = eventKind
        self.eventKind = eventKind
        self.processedRecordsLast60Seconds = processedRecordsLast60Seconds
        self.recordsPerSecond = recordsPerSecond
        self.timeline = timeline
    }
}

nonisolated struct AISchedulerMemoryEstimateBreakdown: Sendable, Equatable {
    let baseBytes: Int64
    let requestOverheadBytes: Int64
    let promptWorkingBytes: Int64
    let kvCacheBytes: Int64
    let prefillAttentionBytes: Int64
    let safetyMultiplier: Double
    let totalBytes: Int64
}

nonisolated struct AISchedulerActiveBatchSnapshot: Identifiable, Sendable, Equatable {
    let id: UUID
    let bucket: String
    let source: String
    let eventKind: String
    let requestCount: Int
    let recordCount: Int
    let batchSize: Int
    let ageSeconds: Double
    let estimatedMemoryBytes: Int64
    let modelName: String?
    let maxTokens: Int?
    let maxKVSize: Int?
    let kvBits: Int?
    let prefillStepSize: Int?
    let promptTokenEstimate: Int?
    let memoryEstimateBreakdown: AISchedulerMemoryEstimateBreakdown?

    init(
        id: UUID,
        bucket: String,
        source: String,
        eventKind: String? = nil,
        requestCount: Int,
        recordCount: Int,
        batchSize: Int,
        ageSeconds: Double,
        estimatedMemoryBytes: Int64,
        modelName: String? = nil,
        maxTokens: Int? = nil,
        maxKVSize: Int? = nil,
        kvBits: Int? = nil,
        prefillStepSize: Int? = nil,
        promptTokenEstimate: Int? = nil,
        memoryEstimateBreakdown: AISchedulerMemoryEstimateBreakdown? = nil
    ) {
        self.id = id
        self.bucket = bucket
        self.source = source
        self.eventKind = eventKind ?? (source.isEmpty ? "unknown" : source)
        self.requestCount = requestCount
        self.recordCount = recordCount
        self.batchSize = batchSize
        self.ageSeconds = ageSeconds
        self.estimatedMemoryBytes = estimatedMemoryBytes
        self.modelName = modelName
        self.maxTokens = maxTokens
        self.maxKVSize = maxKVSize
        self.kvBits = kvBits
        self.prefillStepSize = prefillStepSize
        self.promptTokenEstimate = promptTokenEstimate
        self.memoryEstimateBreakdown = memoryEstimateBreakdown
    }
}

nonisolated struct AISchedulerEventKindSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    let eventKind: String
    let queuedDepth: Int
    let activeRequestCount: Int
    let activeRecordCount: Int
    let oldestQueuedAgeSeconds: Double
}

nonisolated struct AISchedulerBucketSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    let queuedDepth: Int
    let oldestQueuedAgeSeconds: Double
    let activeBatches: [AISchedulerActiveBatchSnapshot]
    let eventKindBreakdown: [AISchedulerEventKindSnapshot]
    let processedRecordsLast60Seconds: Int
    let recordsPerSecond: Double
    let processedRecordsTimeline: AISchedulerProcessingTimeline
    let processedRecordsTimelineByKind: [AISchedulerEventKindTimelineSnapshot]

    init(
        id: String,
        queuedDepth: Int,
        oldestQueuedAgeSeconds: Double,
        activeBatches: [AISchedulerActiveBatchSnapshot] = [],
        eventKindBreakdown: [AISchedulerEventKindSnapshot] = [],
        processedRecordsLast60Seconds: Int = 0,
        recordsPerSecond: Double = 0,
        processedRecordsTimeline: AISchedulerProcessingTimeline = .empty,
        processedRecordsTimelineByKind: [AISchedulerEventKindTimelineSnapshot] = []
    ) {
        self.id = id
        self.queuedDepth = queuedDepth
        self.oldestQueuedAgeSeconds = oldestQueuedAgeSeconds
        self.activeBatches = activeBatches
        self.eventKindBreakdown = eventKindBreakdown
        self.processedRecordsLast60Seconds = processedRecordsLast60Seconds
        self.recordsPerSecond = recordsPerSecond
        self.processedRecordsTimeline = processedRecordsTimeline
        self.processedRecordsTimelineByKind = processedRecordsTimelineByKind
    }
}

nonisolated struct AISchedulerStatsSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let queuedDepthByBucket: [AISchedulerBucketSnapshot]
    let activeBatchCount: Int
    let activeRecordCount: Int
    let activeRecordCap: Int?
    let oldestQueuedAgeSeconds: Double
    let processedRecordsLast60Seconds: Int
    let recordsPerSecond: Double
    let averageWaitMilliseconds: Double
    let p95WaitMilliseconds: Double
    let averageRunMilliseconds: Double
    let p95RunMilliseconds: Double
    let averageBatchSize: Double
    let estimatedMemoryBytes: Int64
    let activeEstimatedMemoryBytes: Int64
    let estimatedMemoryCapBytes: Int64?
    let capacityUtilization: Double?
    let recentFailures: [AISchedulerFailure]

    init(
        id: String,
        name: String,
        queuedDepthByBucket: [AISchedulerBucketSnapshot],
        activeBatchCount: Int,
        activeRecordCount: Int,
        activeRecordCap: Int? = nil,
        oldestQueuedAgeSeconds: Double,
        processedRecordsLast60Seconds: Int,
        recordsPerSecond: Double,
        averageWaitMilliseconds: Double,
        p95WaitMilliseconds: Double,
        averageRunMilliseconds: Double,
        p95RunMilliseconds: Double,
        averageBatchSize: Double,
        estimatedMemoryBytes: Int64,
        activeEstimatedMemoryBytes: Int64 = 0,
        estimatedMemoryCapBytes: Int64? = nil,
        capacityUtilization: Double? = nil,
        recentFailures: [AISchedulerFailure]
    ) {
        self.id = id
        self.name = name
        self.queuedDepthByBucket = queuedDepthByBucket
        self.activeBatchCount = activeBatchCount
        self.activeRecordCount = activeRecordCount
        self.activeRecordCap = activeRecordCap
        self.oldestQueuedAgeSeconds = oldestQueuedAgeSeconds
        self.processedRecordsLast60Seconds = processedRecordsLast60Seconds
        self.recordsPerSecond = recordsPerSecond
        self.averageWaitMilliseconds = averageWaitMilliseconds
        self.p95WaitMilliseconds = p95WaitMilliseconds
        self.averageRunMilliseconds = averageRunMilliseconds
        self.p95RunMilliseconds = p95RunMilliseconds
        self.averageBatchSize = averageBatchSize
        self.estimatedMemoryBytes = estimatedMemoryBytes
        self.activeEstimatedMemoryBytes = activeEstimatedMemoryBytes
        self.estimatedMemoryCapBytes = estimatedMemoryCapBytes
        self.capacityUtilization = capacityUtilization
        self.recentFailures = recentFailures
    }
}

protocol AISchedulerStatsReporting: Sendable {
    func aiSchedulerSnapshots() async -> [AISchedulerStatsSnapshot]
}

nonisolated private struct AISchedulerProcessingSample: Sendable {
    let finishedAt: Date
    let bucket: String
    let requestCount: Int
    let recordCount: Int
    let batchSize: Int
    let eventKindBreakdown: [AISchedulerEventKindRecordState]
}

nonisolated private struct AISchedulerTimelineRecord: Sendable {
    let finishedAt: Date
    let recordCount: Int
    let batchCount: Int
}

nonisolated private struct AISchedulerQueuedWorkState: Sendable {
    let bucket: String
    let eventKind: String
    let queuedAt: Date
}

nonisolated private struct AISchedulerEventKindRecordState: Sendable {
    let eventKind: String
    let requestCount: Int
    let recordCount: Int
}

nonisolated private struct AISchedulerActiveBatchState: Sendable {
    let id: UUID
    let bucket: String
    let source: String
    let eventKind: String
    let eventKindBreakdown: [AISchedulerEventKindRecordState]
    let requestCount: Int
    let recordCount: Int
    let batchSize: Int
    let startedAt: Date
    let estimatedMemoryBytes: Int64
    let modelName: String?
    let maxTokens: Int?
    let maxKVSize: Int?
    let kvBits: Int?
    let prefillStepSize: Int?
    let promptTokenEstimate: Int?
    let memoryEstimateBreakdown: AISchedulerMemoryEstimateBreakdown?

    func snapshot(now: Date) -> AISchedulerActiveBatchSnapshot {
        AISchedulerActiveBatchSnapshot(
            id: id,
            bucket: bucket,
            source: source,
            eventKind: eventKind,
            requestCount: requestCount,
            recordCount: recordCount,
            batchSize: batchSize,
            ageSeconds: now.timeIntervalSince(startedAt),
            estimatedMemoryBytes: estimatedMemoryBytes,
            modelName: modelName,
            maxTokens: maxTokens,
            maxKVSize: maxKVSize,
            kvBits: kvBits,
            prefillStepSize: prefillStepSize,
            promptTokenEstimate: promptTokenEstimate,
            memoryEstimateBreakdown: memoryEstimateBreakdown
        )
    }
}

nonisolated struct ModelTextRequest: Sendable {
    let requestID: UUID
    let source: String
    let priority: AIExecutionPriority
    let prompt: String
    let instructions: String
    let generateParameters: GenerateParameters
    let additionalContext: [String: any Sendable]?
    let promptTokenEstimate: Int?
    let metadata: [String: String]

    init(
        requestID: UUID = UUID(),
        source: String,
        priority: AIExecutionPriority,
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]? = nil,
        promptTokenEstimate: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        self.requestID = requestID
        self.source = source
        self.priority = priority
        self.prompt = prompt
        self.instructions = instructions
        self.generateParameters = generateParameters
        self.additionalContext = additionalContext
        self.promptTokenEstimate = promptTokenEstimate
        self.metadata = metadata
    }
}

nonisolated struct ModelTextCompleted: Sendable {
    let requestID: UUID
    let response: String
    let schedulerMetadata: AISchedulerMetadata
    let timing: AISchedulerTiming
}

nonisolated struct ModelTextFailed: Sendable {
    let requestID: UUID
    let message: String
    let retryable: Bool
}

nonisolated struct ModelEmbeddingRequest: Sendable {
    let requestID: UUID
    let source: String
    let priority: AIExecutionPriority
    let texts: [String]
    let promptPrefix: String?
    let metadata: [String: String]

    init(
        requestID: UUID = UUID(),
        source: String,
        priority: AIExecutionPriority,
        texts: [String],
        promptPrefix: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.requestID = requestID
        self.source = source
        self.priority = priority
        self.texts = texts
        self.promptPrefix = promptPrefix
        self.metadata = metadata
    }
}

nonisolated struct ModelEmbeddingCompleted: Sendable {
    let requestID: UUID
    let vectors: [[Float]]
    let schedulerMetadata: AISchedulerMetadata
    let timing: AISchedulerTiming
}

nonisolated struct ModelEmbeddingFailed: Sendable {
    let requestID: UUID
    let message: String
    let retryable: Bool
}

nonisolated struct ModelVisualRequest: Sendable {
    let requestID: UUID
    let source: String
    let priority: AIExecutionPriority
    let prompt: String
    let imageData: Data
    let instructions: String
    let generateParameters: GenerateParameters
    let additionalContext: [String: any Sendable]?
    let metadata: [String: String]

    init(
        requestID: UUID = UUID(),
        source: String,
        priority: AIExecutionPriority,
        prompt: String,
        imageData: Data,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]? = nil,
        metadata: [String: String] = [:]
    ) {
        self.requestID = requestID
        self.source = source
        self.priority = priority
        self.prompt = prompt
        self.imageData = imageData
        self.instructions = instructions
        self.generateParameters = generateParameters
        self.additionalContext = additionalContext
        self.metadata = metadata
    }
}

nonisolated struct ModelVisualCompleted: Sendable {
    let requestID: UUID
    let response: String
    let schedulerMetadata: AISchedulerMetadata
    let timing: AISchedulerTiming
}

nonisolated struct ModelVisualFailed: Sendable {
    let requestID: UUID
    let message: String
    let retryable: Bool
}

nonisolated struct ModelRerankRequest: Sendable {
    let requestID: UUID
    let source: String
    let priority: AIExecutionPriority
    let query: String
    let documents: [String]
    let instruction: String
    let metadata: [String: String]

    init(
        requestID: UUID = UUID(),
        source: String,
        priority: AIExecutionPriority,
        query: String,
        documents: [String],
        instruction: String,
        metadata: [String: String] = [:]
    ) {
        self.requestID = requestID
        self.source = source
        self.priority = priority
        self.query = query
        self.documents = documents
        self.instruction = instruction
        self.metadata = metadata
    }
}

nonisolated struct ModelRerankCompleted: Sendable {
    let requestID: UUID
    let rankings: [ActivityAIReranking]
    let schedulerMetadata: AISchedulerMetadata
    let timing: AISchedulerTiming
}

nonisolated struct ModelRerankFailed: Sendable {
    let requestID: UUID
    let message: String
    let retryable: Bool
}

nonisolated struct ModelUMAPRequest: Sendable {
    let requestID: UUID
    let source: String
    let priority: AIExecutionPriority
    let vectors: [[Float]]
    let modelDirectoryURL: URL?
    let metadata: [String: String]

    init(
        requestID: UUID = UUID(),
        source: String,
        priority: AIExecutionPriority,
        vectors: [[Float]],
        modelDirectoryURL: URL? = nil,
        metadata: [String: String] = [:]
    ) {
        self.requestID = requestID
        self.source = source
        self.priority = priority
        self.vectors = vectors
        self.modelDirectoryURL = modelDirectoryURL
        self.metadata = metadata
    }
}

nonisolated struct ModelUMAPCompleted: Sendable {
    let requestID: UUID
    let vectors: [[Float]]
    let schedulerMetadata: AISchedulerMetadata
    let timing: AISchedulerTiming
}

nonisolated struct ModelUMAPFailed: Sendable {
    let requestID: UUID
    let message: String
    let retryable: Bool
}

nonisolated enum AITextTokenBucket: String, CaseIterable, Sendable {
    case upTo512 = "0...512"
    case upTo1024 = "513...1024"
    case upTo2048 = "1025...2048"
    case upTo4096 = "2049...4096"
    case upTo8192 = "4097...8192"
    case over8192 = "8193+"

    var safetyMultiplier: Double {
        switch self {
        case .upTo512:
            0.5
        case .upTo1024:
            0.707_106_781_186_5476
        case .upTo2048:
            1.0
        case .upTo4096:
            1.414_213_562_373_0951
        case .upTo8192, .over8192:
            2.0
        }
    }

    static func bucket(for tokenCount: Int) -> AITextTokenBucket {
        switch max(tokenCount, 0) {
        case 0...512:
            .upTo512
        case 513...1024:
            .upTo1024
        case 1025...2048:
            .upTo2048
        case 2049...4096:
            .upTo4096
        case 4097...8192:
            .upTo8192
        default:
            .over8192
        }
    }
}

nonisolated struct AITextSchedulerQueueKey: Hashable, Sendable {
    let signature: String
    let bucket: AITextTokenBucket
}

nonisolated struct AITextSchedulerCapacityProfile: Sendable, Equatable {
    let softMemoryLimitBytes: Int64
    let maxActiveBatches: Int
    let maxActiveRecords: Int
    let fullAttentionLayerCount: Int
    let numAttentionHeads: Int
    let numKeyValueHeads: Int
    let headDimension: Int
    let unquantizedKVElementBytes: Double
    let promptWorkingBytesPerToken: Int64
    let prefillAttentionLongTokenThreshold: Int
    let prefillAttentionWorkspaceBytesPerScore: Int64
    let perRequestOverheadBytes: Int64
    let batchBaseBytes: Int64

    static let qwen35FourBOptiQ4Bit = AITextSchedulerCapacityProfile(
        softMemoryLimitBytes: 12 * 1024 * 1024 * 1024,
        maxActiveBatches: 4,
        maxActiveRecords: 8,
        fullAttentionLayerCount: 8,
        numAttentionHeads: 16,
        numKeyValueHeads: 4,
        headDimension: 256,
        unquantizedKVElementBytes: 2,
        promptWorkingBytesPerToken: 128 * 1024,
        prefillAttentionLongTokenThreshold: 4_096,
        prefillAttentionWorkspaceBytesPerScore: 32,
        perRequestOverheadBytes: 384 * 1024 * 1024,
        batchBaseBytes: 512 * 1024 * 1024
    )

    static let qwen35PointEightBOptiQ4Bit = AITextSchedulerCapacityProfile(
        softMemoryLimitBytes: 4 * 1024 * 1024 * 1024,
        maxActiveBatches: 4,
        maxActiveRecords: 16,
        fullAttentionLayerCount: 4,
        numAttentionHeads: 16,
        numKeyValueHeads: 8,
        headDimension: 128,
        unquantizedKVElementBytes: 2,
        promptWorkingBytesPerToken: 32 * 1024,
        prefillAttentionLongTokenThreshold: 4_096,
        prefillAttentionWorkspaceBytesPerScore: 8,
        perRequestOverheadBytes: 96 * 1024 * 1024,
        batchBaseBytes: 160 * 1024 * 1024
    )
}

nonisolated enum AITextSchedulerPolicy {
    static let capacityProfile = AITextSchedulerCapacityProfile.qwen35FourBOptiQ4Bit
    static let softMemoryLimitBytes: Int64 = capacityProfile.softMemoryLimitBytes

    static func priorityWeight(_ priority: AIExecutionPriority) -> Double {
        switch priority {
        case .streaming:
            100_000
        case .interactive:
            10_000
        case .background:
            0
        }
    }

    static func score(
        priority: AIExecutionPriority,
        oldestAgeSeconds: Double,
        queueDepth: Int
    ) -> Double {
        priorityWeight(priority) + oldestAgeSeconds * 10 + Double(queueDepth) * 2
    }

    static func tokenEstimate(for prompt: String) -> Int {
        max(prompt.split { $0.isWhitespace || $0.isNewline }.count * 4 / 3, prompt.count / 4, 1)
    }

    static func estimatedBatchMemoryBytes(
        promptTokens: [Int],
        generateParameters: [GenerateParameters],
        capacityProfile: AITextSchedulerCapacityProfile = capacityProfile
    ) -> Int64 {
        estimatedBatchMemoryBreakdown(
            promptTokens: promptTokens,
            generateParameters: generateParameters,
            capacityProfile: capacityProfile
        ).totalBytes
    }

    static func estimatedBatchMemoryBreakdown(
        promptTokens: [Int],
        generateParameters: [GenerateParameters],
        capacityProfile: AITextSchedulerCapacityProfile = capacityProfile
    ) -> AISchedulerMemoryEstimateBreakdown {
        struct RowMemoryBreakdown {
            let requestOverheadBytes: Int64
            let promptWorkingBytes: Int64
            let kvCacheBytes: Int64
            let prefillAttentionBytes: Int64
        }

        let profile = capacityProfile
        let paddedPromptTokenCount = promptTokens.map { max($0, 0) }.max() ?? 0
        let kvElementsPerToken = profile.fullAttentionLayerCount
            * 2
            * profile.numKeyValueHeads
            * profile.headDimension
        var rowBreakdown = RowMemoryBreakdown(
            requestOverheadBytes: 0,
            promptWorkingBytes: 0,
            kvCacheBytes: 0,
            prefillAttentionBytes: 0
        )
        let rowCount = min(promptTokens.count, generateParameters.count)
        for index in 0 ..< rowCount {
            let promptTokenCount = paddedPromptTokenCount
            let parameters = generateParameters[index]
            let generationTokens = max(parameters.maxTokens ?? 256, 0)
            let totalTokens = promptTokenCount + generationTokens
            let effectiveKVTokens = min(totalTokens, parameters.maxKVSize ?? totalTokens)
            let kvElementBytes: Double
            if let kvBits = parameters.kvBits {
                kvElementBytes = max(Double(kvBits) / 8, 0.125)
            } else {
                kvElementBytes = profile.unquantizedKVElementBytes
            }
            let kvBytes = Int64((
                Double(effectiveKVTokens)
                * Double(kvElementsPerToken)
                * kvElementBytes
            ).rounded(.up))
            let promptWorkingBytes = Int64((
                Double(promptTokenCount)
                * Double(profile.promptWorkingBytesPerToken)
            ).rounded(.up))
            let prefillStepSize = max(parameters.prefillStepSize, 1)
            let prefillQueryTokens = min(promptTokenCount, prefillStepSize)
            let longContextTokens = max(promptTokenCount - profile.prefillAttentionLongTokenThreshold, 0)
            let prefillAttentionBytes = Int64((
                Double(profile.fullAttentionLayerCount)
                * Double(profile.numAttentionHeads)
                * Double(prefillQueryTokens)
                * Double(longContextTokens)
                * Double(profile.prefillAttentionWorkspaceBytesPerScore)
            ).rounded(.up))

            rowBreakdown = RowMemoryBreakdown(
                requestOverheadBytes: rowBreakdown.requestOverheadBytes + profile.perRequestOverheadBytes,
                promptWorkingBytes: rowBreakdown.promptWorkingBytes + promptWorkingBytes,
                kvCacheBytes: rowBreakdown.kvCacheBytes + kvBytes,
                prefillAttentionBytes: rowBreakdown.prefillAttentionBytes + prefillAttentionBytes
            )
        }
        let rawBytes = profile.batchBaseBytes
            + rowBreakdown.requestOverheadBytes
            + rowBreakdown.promptWorkingBytes
            + rowBreakdown.kvCacheBytes
            + rowBreakdown.prefillAttentionBytes
        let safetyMultiplier = AITextTokenBucket.bucket(for: paddedPromptTokenCount).safetyMultiplier
        let totalBytes = Int64((Double(rawBytes) * safetyMultiplier).rounded(.up))

        return AISchedulerMemoryEstimateBreakdown(
            baseBytes: profile.batchBaseBytes,
            requestOverheadBytes: rowBreakdown.requestOverheadBytes,
            promptWorkingBytes: rowBreakdown.promptWorkingBytes,
            kvCacheBytes: rowBreakdown.kvCacheBytes,
            prefillAttentionBytes: rowBreakdown.prefillAttentionBytes,
            safetyMultiplier: safetyMultiplier,
            totalBytes: totalBytes
        )
    }

    static func estimatedBatchMemoryBytes(
        promptTokens: [Int],
        maxTokens: Int?,
        capacityProfile: AITextSchedulerCapacityProfile = capacityProfile
    ) -> Int64 {
        estimatedBatchMemoryBytes(
            promptTokens: promptTokens,
            generateParameters: Array(
                repeating: GenerateParameters(maxTokens: maxTokens, temperature: 0),
                count: promptTokens.count
            ),
            capacityProfile: capacityProfile
        )
    }

    static func signature(
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?
    ) -> String {
        let parameters = AIGenerateParametersSignature(generateParameters)
        let contextSignature = additionalContextSignature(additionalContext)
        return "\(instructions)|\(String(reflecting: parameters))|\(contextSignature)"
    }

    private static func additionalContextSignature(
        _ additionalContext: [String: any Sendable]?
    ) -> String {
        guard let additionalContext else {
            return "<nil>"
        }

        return additionalContext.keys.sorted().map { key in
            let value = additionalContext[key].map { String(reflecting: $0) } ?? "<nil>"
            return "\(key)=\(value)"
        }
        .joined(separator: "|")
    }
}

nonisolated enum AITextModelLanePolicy {
    static let bigPromptTokenThreshold = 4_096
    static let bigOutputTokenThreshold = 512

    private static let smallSources: Set<String> = [
        "activity-summary",
        "screenshot-summary",
        "overview-merge",
        "activity-tag-ontology-summary",
        "ontology-overview-summary",
        "knowledge-community-summary",
        "knowledge-obsidian-summary",
        "search_summary"
    ]

    private static let bigSources: Set<String> = [
        "knowledge-chunk-graph",
        "knowledge-node-coalesce",
        "knowledge-edge-coalesce",
        "skill_procedure",
        "generic_stream",
        "direct-text",
        "direct-text-batch",
        "activity-goal-todo-assignment"
    ]

    static func lane(for request: ModelTextRequest) -> AITextModelLane {
        let promptTokens = request.promptTokenEstimate ?? AITextSchedulerPolicy.tokenEstimate(for: request.prompt)
        if promptTokens > bigPromptTokenThreshold {
            return .big
        }

        if (request.generateParameters.maxTokens ?? 0) > bigOutputTokenThreshold {
            return .big
        }

        let sourceKeys = [
            request.source,
            request.metadata["event_kind"],
            request.metadata["request_type"]
        ]
        .compactMap { $0 }

        if sourceKeys.contains(where: { bigSources.contains($0) }) {
            return .big
        }

        if sourceKeys.contains(where: { smallSources.contains($0) }) {
            return .small
        }

        return .big
    }
}

nonisolated struct AITextSchedulerBatch: Sendable {
    let lane: AITextModelLane
    let requests: [ModelTextRequest]
    let promptTokenCounts: [Int]
    let bucket: AITextTokenBucket
    let estimatedMemoryBytes: Int64
}

actor AITextModelScheduler: Receiver {
    typealias Executor = @Sendable (AITextSchedulerBatch) async throws -> [String]
    typealias StreamExecutor = @Sendable (
        AITextModelLane,
        String,
        String,
        GenerateParameters,
        [String: any Sendable]?,
        [String: String]
    ) async -> AsyncThrowingStream<String, Error>

    private struct QueuedRequest {
        let request: ModelTextRequest
        let key: AITextSchedulerQueueKey
        let tokenCount: Int
        let queuedAt: Date
        let continuation: CheckedContinuation<String, Error>?
        let streamStartContinuation: CheckedContinuation<AsyncThrowingStream<String, Error>, Never>?
    }

    private struct CompletionSample {
        let finishedAt: Date
        let waitMilliseconds: Double
        let runMilliseconds: Double
        let batchSize: Int
    }

    private struct SelectedBatch {
        let queued: [QueuedRequest]
        let estimatedMemoryBytes: Int64
        let memoryEstimateBreakdown: AISchedulerMemoryEstimateBreakdown
    }

    private let maxBatchSize: Int
    private let maxWaitMilliseconds: Int
    private let backgroundMaxWaitMilliseconds: Int
    private let maxActiveBatches: Int
    private let maxActiveRecords: Int
    private let schedulerKind: AIModelSchedulerKind
    private let lane: AITextModelLane
    private let capacityProfile: AITextSchedulerCapacityProfile
    private let streamExecutor: StreamExecutor
    private let executor: Executor
    private weak var actorSystem: ActorSystem?

    private var queuedByKey: [AITextSchedulerQueueKey: [QueuedRequest]] = [:]
    private var activeBatchCount = 0
    private var activeStreamingCount = 0
    private var activeEstimatedMemoryBytes: Int64 = 0
    private var scheduledFlushGeneration = 0
    private var scheduledFlushDeadline: Date?
    private var isShuttingDown = false
    private let singletonBuckets: Set<AITextTokenBucket> = [.upTo8192, .over8192]
    private let textExclusiveBuckets: Set<AITextTokenBucket> = [.upTo8192, .over8192]
    private var lastEstimatedMemoryBytesByBucket: [AITextTokenBucket: Int64] = [:]
    private var completionSamples: [CompletionSample] = []
    private var processingSamples: [AISchedulerProcessingSample] = []
    private var activeBatches: [UUID: AISchedulerActiveBatchState] = [:]
    private var recentFailures: [AISchedulerFailure] = []

    init(
        actorSystem: ActorSystem? = nil,
        schedulerKind: AIModelSchedulerKind = .textBig,
        lane: AITextModelLane = .big,
        capacityProfile: AITextSchedulerCapacityProfile = AITextSchedulerPolicy.capacityProfile,
        maxBatchSize: Int = 8,
        maxWaitMilliseconds: Int = 5,
        backgroundMaxWaitMilliseconds: Int = 15,
        maxActiveBatches: Int = AITextSchedulerPolicy.capacityProfile.maxActiveBatches,
        maxActiveRecords: Int = AITextSchedulerPolicy.capacityProfile.maxActiveRecords,
        streamExecutor: @escaping StreamExecutor = { _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: AISchedulerError.unavailable("No streaming text scheduler executor is configured."))
            }
        },
        executor: @escaping Executor
    ) {
        self.actorSystem = actorSystem
        self.maxBatchSize = max(maxBatchSize, 1)
        self.maxWaitMilliseconds = max(maxWaitMilliseconds, 0)
        self.backgroundMaxWaitMilliseconds = max(backgroundMaxWaitMilliseconds, self.maxWaitMilliseconds)
        self.maxActiveBatches = max(maxActiveBatches, 1)
        self.maxActiveRecords = max(maxActiveRecords, 1)
        self.schedulerKind = schedulerKind
        self.lane = lane
        self.capacityProfile = capacityProfile
        self.streamExecutor = streamExecutor
        self.executor = executor
    }

    func attach(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    func receive(_ envelope: Envelope) async {
        guard let request = envelope.message as? ModelTextRequest else {
            return
        }

        enqueue(
            request,
            continuation: nil,
            streamStartContinuation: nil
        )
    }

    func streamText(
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]? = nil,
        telemetryMetadata: [String: String] = [:]
    ) async -> AsyncThrowingStream<String, Error> {
        await streamText(
            ModelTextRequest(
                source: telemetryMetadata["request_type"] ?? "streaming-text",
                priority: .streaming,
                prompt: prompt,
                instructions: instructions,
                generateParameters: generateParameters,
                additionalContext: additionalContext,
                metadata: telemetryMetadata
            )
        )
    }

    func requestText(_ request: ModelTextRequest) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            enqueue(
                request,
                continuation: continuation,
                streamStartContinuation: nil
            )
        }
    }

    func enqueueBroadcast(_ request: ModelTextRequest) {
        enqueue(
            request,
            continuation: nil,
            streamStartContinuation: nil
        )
    }

    func streamText(_ request: ModelTextRequest) async -> AsyncThrowingStream<String, Error> {
        let streamRequest = ModelTextRequest(
            requestID: request.requestID,
            source: request.source,
            priority: .streaming,
            prompt: request.prompt,
            instructions: request.instructions,
            generateParameters: request.generateParameters,
            additionalContext: request.additionalContext,
            promptTokenEstimate: request.promptTokenEstimate,
            metadata: request.metadata
        )

        return await withCheckedContinuation { continuation in
            enqueue(
                streamRequest,
                continuation: nil,
                streamStartContinuation: continuation
            )
        }
    }

    func statsSnapshot(now: Date = Date()) -> AISchedulerStatsSnapshot {
        pruneSamples(now: now)
        let queuedWork = queuedByKey.flatMap { key, values in
            values.map {
                AISchedulerQueuedWorkState(
                    bucket: key.bucket.rawValue,
                    eventKind: schedulerEventKind(source: $0.request.source, metadata: $0.request.metadata),
                    queuedAt: $0.queuedAt
                )
            }
        }
        let bucketSnapshots = schedulerBucketSnapshots(
            queuedWork: queuedWork,
            activeBatches: Array(activeBatches.values),
            processingSamples: processingSamples,
            now: now
        )
        let waitDurations = completionSamples.map(\.waitMilliseconds).sorted()
        let runDurations = completionSamples.map(\.runMilliseconds).sorted()
        let batchSizes = processingSamples.map { Double($0.batchSize) }
        let oldestQueuedAge = queuedByKey.values
            .flatMap { $0 }
            .map { now.timeIntervalSince($0.queuedAt) }
            .max() ?? 0
        let processedRecordsLast60Seconds = schedulerRecentRecordCount(
            processingSamples: processingSamples,
            now: now
        )

        return AISchedulerStatsSnapshot(
            id: schedulerKind.rawValue,
            name: schedulerKind.displayName,
            queuedDepthByBucket: bucketSnapshots,
            activeBatchCount: activeBatchCount,
            activeRecordCount: activeRecordCount,
            activeRecordCap: maxActiveRecords,
            oldestQueuedAgeSeconds: oldestQueuedAge,
            processedRecordsLast60Seconds: processedRecordsLast60Seconds,
            recordsPerSecond: Double(processedRecordsLast60Seconds) / AISchedulerStatsPolicy.throughputWindow,
            averageWaitMilliseconds: average(waitDurations),
            p95WaitMilliseconds: p95(waitDurations),
            averageRunMilliseconds: average(runDurations),
            p95RunMilliseconds: p95(runDurations),
            averageBatchSize: average(batchSizes),
            estimatedMemoryBytes: lastEstimatedMemoryBytesByBucket.values.max() ?? 0,
            activeEstimatedMemoryBytes: activeEstimatedMemoryBytes,
            estimatedMemoryCapBytes: capacityProfile.softMemoryLimitBytes,
            capacityUtilization: Double(activeEstimatedMemoryBytes) / Double(capacityProfile.softMemoryLimitBytes),
            recentFailures: recentFailures
        )
    }

    func shutdown() {
        isShuttingDown = true
        let queued = queuedByKey.values.flatMap { $0 }
        queuedByKey.removeAll()
        queued.forEach {
            $0.continuation?.resume(throwing: CancellationError())
            $0.streamStartContinuation?.resume(
                returning: AsyncThrowingStream { continuation in
                    continuation.finish(throwing: CancellationError())
                }
            )
        }
    }

    private func enqueue(
        _ request: ModelTextRequest,
        continuation: CheckedContinuation<String, Error>?,
        streamStartContinuation: CheckedContinuation<AsyncThrowingStream<String, Error>, Never>?
    ) {
        guard !isShuttingDown else {
            continuation?.resume(throwing: CancellationError())
            streamStartContinuation?.resume(
                returning: AsyncThrowingStream { continuation in
                    continuation.finish(throwing: CancellationError())
                }
            )
            return
        }

        let tokenCount = request.promptTokenEstimate ?? AITextSchedulerPolicy.tokenEstimate(for: request.prompt)
        let bucket = AITextTokenBucket.bucket(for: tokenCount)
        let key = AITextSchedulerQueueKey(
            signature: AITextSchedulerPolicy.signature(
                instructions: request.instructions,
                generateParameters: request.generateParameters,
                additionalContext: request.additionalContext
            ),
            bucket: bucket
        )
        queuedByKey[key, default: []].append(
            QueuedRequest(
                request: request,
                key: key,
                tokenCount: tokenCount,
                queuedAt: Date(),
                continuation: continuation,
                streamStartContinuation: streamStartContinuation
            )
        )
        scheduleFlush(after: flushDelayMilliseconds(for: request.priority))
    }

    private func flushDelayMilliseconds(for priority: AIExecutionPriority) -> Int {
        switch priority {
        case .streaming:
            0
        case .interactive:
            maxWaitMilliseconds
        case .background:
            backgroundMaxWaitMilliseconds
        }
    }

    private func scheduleFlushForQueuedWork() {
        let delay = queuedByKey.values
            .flatMap { $0.map(\.request.priority) }
            .map(flushDelayMilliseconds)
            .min()
        guard let delay else {
            return
        }

        scheduleFlush(after: delay)
    }

    private func scheduleFlush(after milliseconds: Int) {
        guard milliseconds > 0 else {
            flushReadyBatches()
            return
        }

        let deadline = Date().addingTimeInterval(Double(milliseconds) / 1000)
        if let scheduledFlushDeadline, scheduledFlushDeadline <= deadline {
            return
        }

        scheduledFlushGeneration += 1
        let generation = scheduledFlushGeneration
        scheduledFlushDeadline = deadline
        Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            self.flushReadyBatches(scheduledGeneration: generation)
        }
    }

    private func flushReadyBatches(scheduledGeneration: Int) {
        guard scheduledGeneration == scheduledFlushGeneration else {
            return
        }

        flushReadyBatches()
    }

    private func flushReadyBatches() {
        scheduledFlushGeneration += 1
        scheduledFlushDeadline = nil

        guard !isShuttingDown else {
            return
        }

        while activeBatchCount < maxActiveBatches,
              let batch = nextBatch() {
            activeBatchCount += 1
            activeEstimatedMemoryBytes += batch.estimatedMemoryBytes
            if batch.queued.contains(where: { $0.request.priority == .streaming }) {
                activeStreamingCount += 1
            }
            let activeBatch = AISchedulerActiveBatchState(
                id: UUID(),
                bucket: batch.queued.first?.key.bucket.rawValue ?? "unknown",
                source: schedulerSourceSummary(batch.queued.map(\.request.source)),
                eventKind: schedulerSourceSummary(
                    batch.queued.map {
                        schedulerEventKind(source: $0.request.source, metadata: $0.request.metadata)
                    }
                ),
                eventKindBreakdown: schedulerEventKindRecordBreakdown(
                    batch.queued.map {
                        (
                            eventKind: schedulerEventKind(source: $0.request.source, metadata: $0.request.metadata),
                            recordCount: 1
                        )
                    }
                ),
                requestCount: batch.queued.count,
                recordCount: batch.queued.count,
                batchSize: batch.queued.count,
                startedAt: Date(),
                estimatedMemoryBytes: batch.estimatedMemoryBytes,
                modelName: lane.model.directoryName,
                maxTokens: batch.queued.first?.request.generateParameters.maxTokens,
                maxKVSize: batch.queued.first?.request.generateParameters.maxKVSize,
                kvBits: batch.queued.first?.request.generateParameters.kvBits,
                prefillStepSize: batch.queued.first?.request.generateParameters.prefillStepSize,
                promptTokenEstimate: batch.queued.map(\.tokenCount).max(),
                memoryEstimateBreakdown: batch.memoryEstimateBreakdown
            )
            activeBatches[activeBatch.id] = activeBatch

            Task {
                await self.execute(
                    batch,
                    activeBatchID: activeBatch.id,
                    startedAt: activeBatch.startedAt
                )
            }
        }

        if activeBatchCount < maxActiveBatches,
           queuedByKey.values.contains(where: { !$0.isEmpty }) {
            scheduleFlushForQueuedWork()
        }
    }

    private func nextBatch() -> SelectedBatch? {
        guard activeStreamingCount == 0 else {
            return nil
        }

        let streamingKey = queuedByKey.first { _, queued in
            queued.contains(where: { $0.request.priority == .streaming })
        }?.key

        if let streamingKey,
           let streamingRequest = queuedByKey[streamingKey]?.first(where: { $0.request.priority == .streaming }) {
            let memoryEstimateBreakdown = AITextSchedulerPolicy.estimatedBatchMemoryBreakdown(
                promptTokens: [streamingRequest.tokenCount],
                generateParameters: [streamingRequest.request.generateParameters],
                capacityProfile: capacityProfile
            )
            guard canAdmitTextBatch(
                memoryEstimateBreakdown.totalBytes,
                recordCount: 1,
                bucket: streamingKey.bucket
            ) else {
                return nil
            }
            queuedByKey = queuedByKey.mapValues {
                $0.filter { $0.request.requestID != streamingRequest.request.requestID }
            }
            .filter { !$0.value.isEmpty }
            return SelectedBatch(
                queued: [streamingRequest],
                estimatedMemoryBytes: memoryEstimateBreakdown.totalBytes,
                memoryEstimateBreakdown: memoryEstimateBreakdown
            )
        }

        let candidates = queuedByKey.compactMap { key, queued -> (key: AITextSchedulerQueueKey, batch: SelectedBatch, score: Double)? in
            guard let batch = selectedBatch(for: key, queued: queued) else {
                return nil
            }

            return (
                key,
                batch,
                queueScore(key, queued) + Double(batch.queued.count) * 3
            )
        }

        guard let candidate = candidates.max(by: { $0.score < $1.score }) else {
            return nil
        }

        let selectedIDs = Set(candidate.batch.queued.map { $0.request.requestID })
        let remaining = (queuedByKey[candidate.key] ?? []).filter { !selectedIDs.contains($0.request.requestID) }
        queuedByKey[candidate.key] = remaining.isEmpty ? nil : remaining

        return candidate.batch
    }

    private func selectedBatch(
        for key: AITextSchedulerQueueKey,
        queued: [QueuedRequest]
    ) -> SelectedBatch? {
        let remainingRecordSlots = maxActiveRecords - activeRecordCount
        guard remainingRecordSlots > 0 else {
            return nil
        }

        let maxRows = min(
            singletonBuckets.contains(key.bucket) ? 1 : maxBatchSize,
            remainingRecordSlots
        )
        let indexedQueued = Array(queued.enumerated())
        let candidates = indexedQueued.compactMap { anchorIndex, anchor -> (
            selected: [QueuedRequest],
            memoryEstimateBreakdown: AISchedulerMemoryEstimateBreakdown,
            highestPriority: Int,
            oldestQueuedAt: Date,
            paddingWaste: Int,
            anchorIndex: Int
        )? in
            let ordered = [anchor] + indexedQueued
                .filter { $0.offset != anchorIndex }
                .sorted { lhs, rhs in
                    let leftDistance = abs(lhs.element.tokenCount - anchor.tokenCount)
                    let rightDistance = abs(rhs.element.tokenCount - anchor.tokenCount)

                    if leftDistance != rightDistance {
                        return leftDistance < rightDistance
                    }

                    return lhs.offset < rhs.offset
                }
                .map(\.element)
            let selectedAndBreakdown = ordered.reduce(
                into: (
                    selected: [QueuedRequest](),
                    memoryEstimateBreakdown: Optional<AISchedulerMemoryEstimateBreakdown>.none
                )
            ) { partial, item in
                guard partial.selected.count < maxRows else {
                    return
                }

                let candidate = partial.selected + [item]
                let memoryEstimateBreakdown = AITextSchedulerPolicy.estimatedBatchMemoryBreakdown(
                    promptTokens: candidate.map(\.tokenCount),
                    generateParameters: candidate.map(\.request.generateParameters),
                    capacityProfile: capacityProfile
                )
                let isIdleSingletonOverCap = activeBatchCount == 0
                    && partial.selected.isEmpty
                    && memoryEstimateBreakdown.totalBytes > capacityProfile.softMemoryLimitBytes

                if canAdmitTextBatch(
                    memoryEstimateBreakdown.totalBytes,
                    recordCount: candidate.count,
                    bucket: key.bucket
                ),
                   memoryEstimateBreakdown.totalBytes <= capacityProfile.softMemoryLimitBytes || isIdleSingletonOverCap {
                    partial.selected = candidate
                    partial.memoryEstimateBreakdown = memoryEstimateBreakdown
                }
            }

            guard let memoryEstimateBreakdown = selectedAndBreakdown.memoryEstimateBreakdown,
                  !selectedAndBreakdown.selected.isEmpty else {
                return nil
            }

            let maxTokenCount = selectedAndBreakdown.selected.map(\.tokenCount).max() ?? 0
            let paddingWaste = maxTokenCount * selectedAndBreakdown.selected.count
                - selectedAndBreakdown.selected.reduce(0) { $0 + $1.tokenCount }

            return (
                selected: selectedAndBreakdown.selected,
                memoryEstimateBreakdown: memoryEstimateBreakdown,
                highestPriority: selectedAndBreakdown.selected.map(\.request.priority.rawValue).min() ?? AIExecutionPriority.background.rawValue,
                oldestQueuedAt: selectedAndBreakdown.selected.map(\.queuedAt).min() ?? .distantFuture,
                paddingWaste: paddingWaste,
                anchorIndex: anchorIndex
            )
        }

        guard let candidate = candidates.max(by: { lhs, rhs in
            if lhs.selected.count != rhs.selected.count {
                return lhs.selected.count < rhs.selected.count
            }

            if lhs.highestPriority != rhs.highestPriority {
                return lhs.highestPriority > rhs.highestPriority
            }

            if lhs.oldestQueuedAt != rhs.oldestQueuedAt {
                return lhs.oldestQueuedAt > rhs.oldestQueuedAt
            }

            if lhs.paddingWaste != rhs.paddingWaste {
                return lhs.paddingWaste > rhs.paddingWaste
            }

            return lhs.anchorIndex > rhs.anchorIndex
        }) else {
            return nil
        }

        return SelectedBatch(
            queued: candidate.selected,
            estimatedMemoryBytes: candidate.memoryEstimateBreakdown.totalBytes,
            memoryEstimateBreakdown: candidate.memoryEstimateBreakdown
        )
    }

    private var activeRecordCount: Int {
        activeBatches.values.reduce(0) { $0 + $1.recordCount }
    }

    private func canAdmitTextBatch(
        _ estimatedBytes: Int64,
        recordCount: Int,
        bucket: AITextTokenBucket
    ) -> Bool {
        guard activeRecordCount + recordCount <= maxActiveRecords else {
            return false
        }

        if textExclusiveBuckets.contains(bucket) {
            guard activeBatchCount == 0 else {
                return false
            }
        } else if hasActiveTextExclusiveBatch {
            return false
        }

        guard activeBatchCount > 0 else {
            return true
        }

        return activeEstimatedMemoryBytes + estimatedBytes <= capacityProfile.softMemoryLimitBytes
    }

    private var hasActiveTextExclusiveBatch: Bool {
        activeBatches.values.contains {
            AITextTokenBucket(rawValue: $0.bucket)
                .map { textExclusiveBuckets.contains($0) } ?? false
        }
    }

    private func queueScore(
        _ key: AITextSchedulerQueueKey,
        _ queued: [QueuedRequest]
    ) -> Double {
        let now = Date()
        let highestPriority = queued
            .map(\.request.priority)
            .min { $0.rawValue < $1.rawValue } ?? .background
        let oldestAge = queued
            .map { now.timeIntervalSince($0.queuedAt) }
            .max() ?? 0
        return AITextSchedulerPolicy.score(
            priority: highestPriority,
            oldestAgeSeconds: oldestAge,
            queueDepth: queued.count
        )
    }

    private func execute(
        _ batch: SelectedBatch,
        activeBatchID: UUID,
        startedAt: Date
    ) async {
        let queued = batch.queued
        if queued.count == 1,
           let item = queued.first,
           let streamStartContinuation = item.streamStartContinuation {
            await startStream(
                item,
                activeBatchID: activeBatchID,
                estimatedBytes: batch.estimatedMemoryBytes,
                startedAt: startedAt,
                streamStartContinuation: streamStartContinuation
            )
            return
        }

        let requests = queued.map(\.request)
        let tokenCounts = queued.map(\.tokenCount)
        let bucket = queued[0].key.bucket
        let schedulerBatch = AITextSchedulerBatch(
            lane: lane,
            requests: requests,
            promptTokenCounts: tokenCounts,
            bucket: bucket,
            estimatedMemoryBytes: batch.estimatedMemoryBytes
        )
        let finished: (Result<[String], Error>, Date) = await {
            do {
                let responses = try await executor(schedulerBatch)
                return (.success(responses), Date())
            } catch {
                return (.failure(error), Date())
            }
        }()

        complete(
            queued,
            activeBatchID: activeBatchID,
            bucket: bucket,
            estimatedBytes: batch.estimatedMemoryBytes,
            startedAt: startedAt,
            finishedAt: finished.1,
            result: finished.0
        )
    }

    private func startStream(
        _ item: QueuedRequest,
        activeBatchID: UUID,
        estimatedBytes: Int64,
        startedAt: Date,
        streamStartContinuation: CheckedContinuation<AsyncThrowingStream<String, Error>, Never>
    ) async {
        let upstream = await streamExecutor(
            lane,
            item.request.prompt,
            item.request.instructions,
            item.request.generateParameters,
            item.request.additionalContext,
            item.request.metadata
        )
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let task = Task {
            let finished: (Result<Void, Error>, Date) = await {
                do {
                    for try await chunk in upstream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                    return (.success(()), Date())
                } catch {
                    continuation.finish(throwing: error)
                    return (.failure(error), Date())
                }
            }()

            self.completeStream(
                item,
                activeBatchID: activeBatchID,
                estimatedBytes: estimatedBytes,
                startedAt: startedAt,
                finishedAt: finished.1,
                result: finished.0
            )
        }
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        streamStartContinuation.resume(returning: stream)
    }

    private func completeStream(
        _ item: QueuedRequest,
        activeBatchID: UUID,
        estimatedBytes: Int64,
        startedAt: Date,
        finishedAt: Date,
        result: Result<Void, Error>
    ) {
        activeBatchCount = max(activeBatchCount - 1, 0)
        activeEstimatedMemoryBytes = max(activeEstimatedMemoryBytes - estimatedBytes, 0)
        activeStreamingCount = max(activeStreamingCount - 1, 0)
        activeBatches.removeValue(forKey: activeBatchID)
        lastEstimatedMemoryBytesByBucket[item.key.bucket] = estimatedBytes
        let timing = AISchedulerTiming(
            queuedAt: item.queuedAt,
            startedAt: startedAt,
            finishedAt: finishedAt
        )

        switch result {
        case .success:
            completionSamples.append(
                CompletionSample(
                    finishedAt: finishedAt,
                    waitMilliseconds: timing.waitMilliseconds,
                    runMilliseconds: timing.runMilliseconds,
                    batchSize: 1
                )
            )
            processingSamples.append(
                AISchedulerProcessingSample(
                    finishedAt: finishedAt,
                    bucket: item.key.bucket.rawValue,
                    requestCount: 1,
                    recordCount: 1,
                    batchSize: 1,
                    eventKindBreakdown: schedulerEventKindRecordBreakdown([
                        (
                            eventKind: schedulerEventKind(
                                source: item.request.source,
                                metadata: item.request.metadata
                            ),
                            recordCount: 1
                        )
                    ])
                )
            )
        case .failure(let error):
            let failure = AISchedulerFailure(
                id: UUID(),
                requestID: item.request.requestID,
                message: String(describing: error),
                retryable: !(error is CancellationError),
                occurredAt: finishedAt
            )
            recentFailures = ([failure] + recentFailures).prefix(10).map { $0 }
            Task {
                await actorSystem?.broadcast(
                    from: nil,
                    message: ModelTextFailed(
                        requestID: item.request.requestID,
                        message: failure.message,
                        retryable: failure.retryable
                    )
                )
            }
        }

        pruneSamples(now: finishedAt)
        flushReadyBatches()
    }

    private func complete(
        _ queued: [QueuedRequest],
        activeBatchID: UUID,
        bucket: AITextTokenBucket,
        estimatedBytes: Int64,
        startedAt: Date,
        finishedAt: Date,
        result: Result<[String], Error>
    ) {
        activeBatchCount = max(activeBatchCount - 1, 0)
        activeEstimatedMemoryBytes = max(activeEstimatedMemoryBytes - estimatedBytes, 0)
        if queued.contains(where: { $0.request.priority == .streaming }) {
            activeStreamingCount = max(activeStreamingCount - 1, 0)
        }
        activeBatches.removeValue(forKey: activeBatchID)
        lastEstimatedMemoryBytesByBucket[bucket] = estimatedBytes

        switch result {
        case .success(let responses):
            guard responses.count == queued.count else {
                complete(
                    queued,
                    activeBatchID: activeBatchID,
                    bucket: bucket,
                    estimatedBytes: estimatedBytes,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    result: .failure(
                        AISchedulerError.responseCountMismatch(
                            expected: queued.count,
                            actual: responses.count
                        )
                    )
                )
                return
            }

            processingSamples.append(
                AISchedulerProcessingSample(
                    finishedAt: finishedAt,
                    bucket: bucket.rawValue,
                    requestCount: queued.count,
                    recordCount: queued.count,
                    batchSize: queued.count,
                    eventKindBreakdown: schedulerEventKindRecordBreakdown(
                        queued.map {
                            (
                                eventKind: schedulerEventKind(
                                    source: $0.request.source,
                                    metadata: $0.request.metadata
                                ),
                                recordCount: 1
                            )
                        }
                    )
                )
            )

            zip(queued, responses).forEach { item, response in
                let timing = AISchedulerTiming(
                    queuedAt: item.queuedAt,
                    startedAt: startedAt,
                    finishedAt: finishedAt
                )
                item.continuation?.resume(returning: response)
                Task {
                    await actorSystem?.broadcast(
                        from: nil,
                        message: ModelTextCompleted(
                            requestID: item.request.requestID,
                            response: response,
                            schedulerMetadata: AISchedulerMetadata(
                                scheduler: schedulerKind,
                                bucket: bucket.rawValue,
                                batchSize: queued.count,
                                source: item.request.source,
                                eventKind: schedulerEventKind(
                                    source: item.request.source,
                                    metadata: item.request.metadata
                                )
                            ),
                            timing: timing
                        )
                    )
                }
                completionSamples.append(
                    CompletionSample(
                        finishedAt: finishedAt,
                        waitMilliseconds: timing.waitMilliseconds,
                        runMilliseconds: timing.runMilliseconds,
                        batchSize: queued.count
                    )
                )
            }
        case .failure(let error):
            queued.forEach { item in
                let failure = AISchedulerFailure(
                    id: UUID(),
                    requestID: item.request.requestID,
                    message: String(describing: error),
                    retryable: !(error is CancellationError),
                    occurredAt: finishedAt
                )
                recentFailures = ([failure] + recentFailures).prefix(10).map { $0 }
                item.continuation?.resume(throwing: error)
                Task {
                    await actorSystem?.broadcast(
                        from: nil,
                        message: ModelTextFailed(
                            requestID: item.request.requestID,
                            message: failure.message,
                            retryable: failure.retryable
                        )
                    )
                }
            }
        }

        pruneSamples(now: finishedAt)
        flushReadyBatches()
    }

    private func pruneSamples(now: Date) {
        let cutoff = now.addingTimeInterval(-AIStatsWindow.rollingWindow)
        completionSamples = completionSamples.filter { $0.finishedAt >= cutoff }
        processingSamples = processingSamples.filter { $0.finishedAt >= cutoff }
        recentFailures = Array(recentFailures.prefix(10))
    }
}

actor AITextModelSchedulerRouter: Receiver {
    private let smallScheduler: AITextModelScheduler
    private let bigScheduler: AITextModelScheduler

    init(
        smallScheduler: AITextModelScheduler,
        bigScheduler: AITextModelScheduler
    ) {
        self.smallScheduler = smallScheduler
        self.bigScheduler = bigScheduler
    }

    func receive(_ envelope: Envelope) async {
        guard let request = envelope.message as? ModelTextRequest else {
            return
        }

        await scheduler(for: request).enqueueBroadcast(request)
    }

    func requestText(_ request: ModelTextRequest) async throws -> String {
        try await scheduler(for: request).requestText(request)
    }

    func streamText(
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]? = nil,
        telemetryMetadata: [String: String] = [:]
    ) async -> AsyncThrowingStream<String, Error> {
        let request = ModelTextRequest(
            source: telemetryMetadata["request_type"] ?? "streaming-text",
            priority: .streaming,
            prompt: prompt,
            instructions: instructions,
            generateParameters: generateParameters,
            additionalContext: additionalContext,
            metadata: telemetryMetadata
        )

        return await scheduler(for: request).streamText(request)
    }

    private func scheduler(for request: ModelTextRequest) -> AITextModelScheduler {
        switch AITextModelLanePolicy.lane(for: request) {
        case .small:
            smallScheduler
        case .big:
            bigScheduler
        }
    }
}

actor AIEmbeddingModelScheduler: Receiver {
    typealias Executor = @Sendable (ModelEmbeddingRequest) async throws -> [[Float]]

    private struct QueuedRequest {
        let request: ModelEmbeddingRequest
        let bucket: String
        let queuedAt: Date
        let continuation: CheckedContinuation<[[Float]], Error>?
    }

    private struct CompletionSample {
        let finishedAt: Date
        let waitMilliseconds: Double
        let runMilliseconds: Double
        let batchSize: Int
    }

    private let maxBatchSize: Int
    private let maxTextRowsPerBatch: Int
    private let maxWaitMilliseconds: Int
    private let executor: Executor
    private weak var actorSystem: ActorSystem?
    private var queue: [QueuedRequest] = []
    private var activeBatchCount = 0
    private var isFlushScheduled = false
    private var completionSamples: [CompletionSample] = []
    private var processingSamples: [AISchedulerProcessingSample] = []
    private var activeBatches: [UUID: AISchedulerActiveBatchState] = [:]
    private var recentFailures: [AISchedulerFailure] = []

    init(
        actorSystem: ActorSystem? = nil,
        maxBatchSize: Int = 64,
        maxTextRowsPerBatch: Int = 256,
        maxWaitMilliseconds: Int = 5,
        executor: @escaping Executor
    ) {
        self.actorSystem = actorSystem
        self.maxBatchSize = max(maxBatchSize, 1)
        self.maxTextRowsPerBatch = max(maxTextRowsPerBatch, 1)
        self.maxWaitMilliseconds = max(maxWaitMilliseconds, 0)
        self.executor = executor
    }

    func attach(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    func receive(_ envelope: Envelope) async {
        guard let request = envelope.message as? ModelEmbeddingRequest else {
            return
        }

        enqueue(request, continuation: nil)
    }

    func statsSnapshot(now: Date = Date()) -> AISchedulerStatsSnapshot {
        pruneSamples(now: now)
        let buckets = schedulerBucketSnapshots(
            queuedWork: queue.map {
                AISchedulerQueuedWorkState(
                    bucket: $0.bucket,
                    eventKind: schedulerEventKind(source: $0.request.source, metadata: $0.request.metadata),
                    queuedAt: $0.queuedAt
                )
            },
            activeBatches: Array(activeBatches.values),
            processingSamples: processingSamples,
            now: now
        )
        let waitDurations = completionSamples.map(\.waitMilliseconds).sorted()
        let runDurations = completionSamples.map(\.runMilliseconds).sorted()
        let batchSizes = processingSamples.map { Double($0.batchSize) }
        let processedRecordsLast60Seconds = schedulerRecentRecordCount(
            processingSamples: processingSamples,
            now: now
        )

        return AISchedulerStatsSnapshot(
            id: AIModelSchedulerKind.embedding.rawValue,
            name: AIModelSchedulerKind.embedding.displayName,
            queuedDepthByBucket: buckets,
            activeBatchCount: activeBatchCount,
            activeRecordCount: activeBatches.values.reduce(0) { $0 + $1.recordCount },
            oldestQueuedAgeSeconds: queue.map { now.timeIntervalSince($0.queuedAt) }.max() ?? 0,
            processedRecordsLast60Seconds: processedRecordsLast60Seconds,
            recordsPerSecond: Double(processedRecordsLast60Seconds) / AISchedulerStatsPolicy.throughputWindow,
            averageWaitMilliseconds: average(waitDurations),
            p95WaitMilliseconds: p95(waitDurations),
            averageRunMilliseconds: average(runDurations),
            p95RunMilliseconds: p95(runDurations),
            averageBatchSize: average(batchSizes),
            estimatedMemoryBytes: 0,
            recentFailures: recentFailures
        )
    }

    func shutdown() {
        let queued = queue
        queue.removeAll()
        queued.forEach {
            $0.continuation?.resume(throwing: CancellationError())
        }
    }

    private func enqueue(
        _ request: ModelEmbeddingRequest,
        continuation: CheckedContinuation<[[Float]], Error>?
    ) {
        queue.append(
            QueuedRequest(
                request: request,
                bucket: Self.bucket(for: request),
                queuedAt: Date(),
                continuation: continuation
            )
        )
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !isFlushScheduled else {
            return
        }

        isFlushScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(maxWaitMilliseconds))
            self.flushReadyBatch()
        }
    }

    private func flushReadyBatch() {
        isFlushScheduled = false

        guard activeBatchCount == 0,
              !queue.isEmpty else {
            return
        }

        let selectedBucket = queue.max {
            queueScore($0.bucket) < queueScore($1.bucket)
        }?.bucket
        guard let selectedBucket,
              let firstIndex = queue.firstIndex(where: { $0.bucket == selectedBucket }) else {
            return
        }

        let promptPrefix = queue[firstIndex].request.promptPrefix
        let selected = queue
            .filter {
                $0.bucket == selectedBucket && $0.request.promptPrefix == promptPrefix
            }
            .reduce(into: [QueuedRequest]()) { partial, item in
                guard partial.count < maxBatchSize else {
                    return
                }

                let currentTextCount = partial.reduce(0) { $0 + $1.request.texts.count }
                let nextTextCount = currentTextCount + item.request.texts.count

                if partial.isEmpty || nextTextCount <= maxTextRowsPerBatch {
                    partial.append(item)
                }
            }
        let selectedIDs = Set(selected.map(\.request.requestID))
        queue.removeAll { selectedIDs.contains($0.request.requestID) }
        activeBatchCount = 1
        let activeBatch = AISchedulerActiveBatchState(
            id: UUID(),
            bucket: selectedBucket,
            source: schedulerSourceSummary(selected.map(\.request.source)),
            eventKind: schedulerSourceSummary(
                selected.map {
                    schedulerEventKind(source: $0.request.source, metadata: $0.request.metadata)
                }
            ),
            eventKindBreakdown: schedulerEventKindRecordBreakdown(
                selected.map {
                    (
                        eventKind: schedulerEventKind(source: $0.request.source, metadata: $0.request.metadata),
                        recordCount: $0.request.texts.count
                    )
                }
            ),
            requestCount: selected.count,
            recordCount: selected.reduce(0) { $0 + $1.request.texts.count },
            batchSize: selected.count,
            startedAt: Date(),
            estimatedMemoryBytes: 0,
            modelName: AIModel.embedding.directoryName,
            maxTokens: nil,
            maxKVSize: nil,
            kvBits: nil,
            prefillStepSize: nil,
            promptTokenEstimate: nil,
            memoryEstimateBreakdown: nil
        )
        activeBatches[activeBatch.id] = activeBatch

        Task {
            await self.execute(
                Array(selected),
                activeBatchID: activeBatch.id,
                startedAt: activeBatch.startedAt
            )
        }
    }

    private func execute(
        _ queued: [QueuedRequest],
        activeBatchID: UUID,
        startedAt: Date
    ) async {
        let source = queued.map(\.request.source).joined(separator: ",")
        let priority = queued.map(\.request.priority).min { $0.rawValue < $1.rawValue } ?? .background
        let texts = queued.flatMap(\.request.texts)
        let promptPrefix = queued.first?.request.promptPrefix
        let finished: (Result<[[Float]], Error>, Date) = await {
            do {
                var vectors: [[Float]] = []
                for start in stride(from: 0, to: texts.count, by: maxTextRowsPerBatch) {
                    let end = min(start + maxTextRowsPerBatch, texts.count)
                    let chunkRequest = ModelEmbeddingRequest(
                        source: source,
                        priority: priority,
                        texts: Array(texts[start..<end]),
                        promptPrefix: promptPrefix,
                        metadata: [:]
                    )
                    vectors.append(contentsOf: try await executor(chunkRequest))
                }
                return (.success(vectors), Date())
            } catch {
                return (.failure(error), Date())
            }
        }()

        complete(
            queued,
            activeBatchID: activeBatchID,
            startedAt: startedAt,
            finishedAt: finished.1,
            result: finished.0
        )
    }

    private func complete(
        _ queued: [QueuedRequest],
        activeBatchID: UUID,
        startedAt: Date,
        finishedAt: Date,
        result: Result<[[Float]], Error>
    ) {
        activeBatchCount = 0
        activeBatches.removeValue(forKey: activeBatchID)

        switch result {
        case .success(let vectors):
            let expectedCount = queued.reduce(0) { $0 + $1.request.texts.count }
            guard vectors.count == expectedCount else {
                complete(
                    queued,
                    activeBatchID: activeBatchID,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    result: .failure(
                        AISchedulerError.responseCountMismatch(
                            expected: expectedCount,
                            actual: vectors.count
                        )
                    )
                )
                return
            }

            processingSamples.append(
                AISchedulerProcessingSample(
                    finishedAt: finishedAt,
                    bucket: queued.first?.bucket ?? "unknown",
                    requestCount: queued.count,
                    recordCount: expectedCount,
                    batchSize: queued.count,
                    eventKindBreakdown: schedulerEventKindRecordBreakdown(
                        queued.map {
                            (
                                eventKind: schedulerEventKind(
                                    source: $0.request.source,
                                    metadata: $0.request.metadata
                                ),
                                recordCount: $0.request.texts.count
                            )
                        }
                    )
                )
            )

            var offset = 0
            queued.forEach { item in
                let end = offset + item.request.texts.count
                let requestVectors = Array(vectors[offset..<end])
                offset = end
                let timing = AISchedulerTiming(
                    queuedAt: item.queuedAt,
                    startedAt: startedAt,
                    finishedAt: finishedAt
                )
                item.continuation?.resume(returning: requestVectors)
                completionSamples.append(
                    CompletionSample(
                        finishedAt: finishedAt,
                        waitMilliseconds: timing.waitMilliseconds,
                        runMilliseconds: timing.runMilliseconds,
                        batchSize: queued.count
                    )
                )
                Task {
                    await actorSystem?.broadcast(
                        from: nil,
                        message: ModelEmbeddingCompleted(
                            requestID: item.request.requestID,
                            vectors: requestVectors,
                            schedulerMetadata: AISchedulerMetadata(
                                scheduler: .embedding,
                                bucket: item.bucket,
                                batchSize: queued.count,
                                source: item.request.source,
                                eventKind: schedulerEventKind(
                                    source: item.request.source,
                                    metadata: item.request.metadata
                                )
                            ),
                            timing: timing
                        )
                    )
                }
            }
        case .failure(let error):
            queued.forEach { item in
                let failure = AISchedulerFailure(
                    id: UUID(),
                    requestID: item.request.requestID,
                    message: String(describing: error),
                    retryable: !(error is CancellationError),
                    occurredAt: finishedAt
                )
                recentFailures = ([failure] + recentFailures).prefix(10).map { $0 }
                item.continuation?.resume(throwing: error)
                Task {
                    await actorSystem?.broadcast(
                        from: nil,
                        message: ModelEmbeddingFailed(
                            requestID: item.request.requestID,
                            message: failure.message,
                            retryable: failure.retryable
                        )
                    )
                }
            }
        }

        pruneSamples(now: finishedAt)
        flushReadyBatch()
    }

    private func queueScore(_ bucket: String) -> Double {
        let now = Date()
        let queued = queue.filter { $0.bucket == bucket }
        let highestPriority = queued
            .map(\.request.priority)
            .min { $0.rawValue < $1.rawValue } ?? .background
        let oldestAge = queued.map { now.timeIntervalSince($0.queuedAt) }.max() ?? 0
        return AITextSchedulerPolicy.score(
            priority: highestPriority,
            oldestAgeSeconds: oldestAge,
            queueDepth: queued.count
        )
    }

    private func pruneSamples(now: Date) {
        let cutoff = now.addingTimeInterval(-AIStatsWindow.rollingWindow)
        completionSamples = completionSamples.filter { $0.finishedAt >= cutoff }
        processingSamples = processingSamples.filter { $0.finishedAt >= cutoff }
        recentFailures = Array(recentFailures.prefix(10))
    }

    nonisolated private static func bucket(for request: ModelEmbeddingRequest) -> String {
        let maxTokenEstimate = request.texts
            .map { AITextSchedulerPolicy.tokenEstimate(for: $0) }
            .max() ?? 0
        return "\(AITextTokenBucket.bucket(for: maxTokenEstimate).rawValue)|prefix:\(request.promptPrefix ?? "<nil>")"
    }
}

nonisolated private func schedulerBucketSnapshots(
    queuedWork: [AISchedulerQueuedWorkState],
    activeBatches: [AISchedulerActiveBatchState],
    processingSamples: [AISchedulerProcessingSample],
    now: Date
) -> [AISchedulerBucketSnapshot] {
    let timelineCutoff = now.addingTimeInterval(-AISchedulerStatsPolicy.timelineWindowDuration)
    let queuedByBucket = Dictionary(grouping: queuedWork, by: \.bucket)
    let activeBatchesByBucket = Dictionary(grouping: activeBatches, by: \.bucket)
    let processingSamplesByBucket = Dictionary(
        grouping: processingSamples.filter { $0.finishedAt >= timelineCutoff },
        by: \.bucket
    )
    let bucketIDs = Set(queuedByBucket.keys)
        .union(activeBatchesByBucket.keys)
        .union(processingSamplesByBucket.keys)

    return bucketIDs.map { bucketID in
        let queuedItems = queuedByBucket[bucketID] ?? []
        let activeStates = activeBatchesByBucket[bucketID] ?? []
        let activeSnapshots = activeStates
            .map { $0.snapshot(now: now) }
            .sorted { $0.ageSeconds > $1.ageSeconds }
        let bucketSamples = processingSamplesByBucket[bucketID] ?? []
        let processedRecordsLast60Seconds = schedulerRecentRecordCount(
            processingSamples: bucketSamples,
            now: now
        )
        let queuedByKind = Dictionary(grouping: queuedItems, by: \.eventKind)
        let activeByKind = activeStates
            .flatMap(\.eventKindBreakdown)
            .reduce(into: [String: (requestCount: Int, recordCount: Int)]()) { partial, item in
                let current = partial[item.eventKind] ?? (requestCount: 0, recordCount: 0)
                partial[item.eventKind] = (
                    requestCount: current.requestCount + item.requestCount,
                    recordCount: current.recordCount + item.recordCount
                )
            }
        let eventKindBreakdown = Set(queuedByKind.keys)
            .union(activeByKind.keys)
            .map { eventKind in
                let queuedForKind = queuedByKind[eventKind] ?? []
                let activeForKind = activeByKind[eventKind] ?? (requestCount: 0, recordCount: 0)

                return AISchedulerEventKindSnapshot(
                    id: eventKind,
                    eventKind: eventKind,
                    queuedDepth: queuedForKind.count,
                    activeRequestCount: activeForKind.requestCount,
                    activeRecordCount: activeForKind.recordCount,
                    oldestQueuedAgeSeconds: queuedForKind.map { now.timeIntervalSince($0.queuedAt) }.max() ?? 0
                )
            }
            .sorted { lhs, rhs in
                let lhsTotal = lhs.activeRecordCount + lhs.queuedDepth
                let rhsTotal = rhs.activeRecordCount + rhs.queuedDepth

                guard lhsTotal == rhsTotal else {
                    return lhsTotal > rhsTotal
                }

                return lhs.eventKind < rhs.eventKind
            }

        return AISchedulerBucketSnapshot(
            id: bucketID,
            queuedDepth: queuedItems.count,
            oldestQueuedAgeSeconds: queuedItems.map { now.timeIntervalSince($0.queuedAt) }.max() ?? 0,
            activeBatches: activeSnapshots,
            eventKindBreakdown: eventKindBreakdown,
            processedRecordsLast60Seconds: processedRecordsLast60Seconds,
            recordsPerSecond: Double(processedRecordsLast60Seconds) / AISchedulerStatsPolicy.throughputWindow,
            processedRecordsTimeline: schedulerProcessingTimeline(
                processingSamples: bucketSamples,
                now: now
            ),
            processedRecordsTimelineByKind: schedulerEventKindProcessingTimelines(
                processingSamples: bucketSamples,
                now: now
            )
        )
    }
    .sorted { $0.id < $1.id }
}

nonisolated private func schedulerEventKind(
    source: String,
    metadata: [String: String]
) -> String {
    let rawValue = [
        metadata["event_kind"],
        metadata["eventKind"],
        metadata["request_type"],
        source
    ]
    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
    .first { !$0.isEmpty }

    return rawValue ?? "unknown"
}

nonisolated private func schedulerEventKindRecordBreakdown(
    _ records: [(eventKind: String, recordCount: Int)]
) -> [AISchedulerEventKindRecordState] {
    records
        .reduce(into: [String: (requestCount: Int, recordCount: Int)]()) { partial, item in
            let current = partial[item.eventKind] ?? (requestCount: 0, recordCount: 0)
            partial[item.eventKind] = (
                requestCount: current.requestCount + 1,
                recordCount: current.recordCount + item.recordCount
            )
        }
        .map {
            AISchedulerEventKindRecordState(
                eventKind: $0.key,
                requestCount: $0.value.requestCount,
                recordCount: $0.value.recordCount
            )
        }
}

nonisolated private func schedulerEventKindProcessingTimelines(
    processingSamples: [AISchedulerProcessingSample],
    now: Date
) -> [AISchedulerEventKindTimelineSnapshot] {
    let cutoff = now.addingTimeInterval(-AISchedulerStatsPolicy.throughputWindow)
    let expandedRecords = processingSamples.flatMap { sample in
        sample.eventKindBreakdown.map {
            (
                eventKind: $0.eventKind,
                finishedAt: sample.finishedAt,
                recordCount: $0.recordCount
            )
        }
    }
    let recordsByKind = Dictionary(grouping: expandedRecords) { $0.eventKind }

    return recordsByKind.map { eventKind, records in
        let recentCount = records
            .filter { $0.finishedAt >= cutoff }
            .reduce(0) { $0 + $1.recordCount }

        return AISchedulerEventKindTimelineSnapshot(
            eventKind: eventKind,
            processedRecordsLast60Seconds: recentCount,
            recordsPerSecond: Double(recentCount) / AISchedulerStatsPolicy.throughputWindow,
            timeline: schedulerProcessingTimeline(
                records: records.map {
                    AISchedulerTimelineRecord(
                        finishedAt: $0.finishedAt,
                        recordCount: $0.recordCount,
                        batchCount: 1
                    )
                },
                now: now
            )
        )
    }
    .sorted { lhs, rhs in
        guard lhs.processedRecordsLast60Seconds == rhs.processedRecordsLast60Seconds else {
            return lhs.processedRecordsLast60Seconds > rhs.processedRecordsLast60Seconds
        }

        return lhs.eventKind < rhs.eventKind
    }
}

nonisolated private func schedulerProcessingTimeline(
    processingSamples: [AISchedulerProcessingSample],
    now: Date
) -> AISchedulerProcessingTimeline {
    schedulerProcessingTimeline(
        records: processingSamples.map {
            AISchedulerTimelineRecord(
                finishedAt: $0.finishedAt,
                recordCount: $0.recordCount,
                batchCount: 1
            )
        },
        now: now
    )
}

nonisolated private func schedulerProcessingTimeline(
    records: [AISchedulerTimelineRecord],
    now: Date
) -> AISchedulerProcessingTimeline {
    let bucketDuration = AISchedulerStatsPolicy.timelineBucketDuration
    let bucketCount = AISchedulerStatsPolicy.timelineBucketCount
    let nowReferenceInterval = now.timeIntervalSinceReferenceDate
    let currentBucketStartReferenceInterval = floor(nowReferenceInterval / bucketDuration) * bucketDuration
    let oldestBucketStartReferenceInterval =
        currentBucketStartReferenceInterval - Double(bucketCount - 1) * bucketDuration
    let bucketProgress = (nowReferenceInterval - currentBucketStartReferenceInterval) / bucketDuration
    let bucketIndex: (Date) -> Int? = { date in
        let relativeInterval = date.timeIntervalSinceReferenceDate - oldestBucketStartReferenceInterval

        guard relativeInterval >= 0 else {
            return nil
        }

        let index = Int(relativeInterval / bucketDuration)

        guard index < bucketCount else {
            return nil
        }

        return index
    }
    let buckets = records.reduce(
        into: Array(repeating: (records: 0, batches: 0), count: bucketCount)
    ) { partial, record in
        guard let index = bucketIndex(record.finishedAt) else {
            return
        }

        partial[index].records += record.recordCount
        partial[index].batches += record.batchCount
    }

    return AISchedulerProcessingTimeline(
        bucketDuration: bucketDuration,
        windowDuration: AISchedulerStatsPolicy.timelineWindowDuration,
        bucketProgress: bucketProgress,
        recordCounts: buckets.map(\.records),
        batchCounts: buckets.map(\.batches)
    )
}

nonisolated private func schedulerRecentRecordCount(
    processingSamples: [AISchedulerProcessingSample],
    now: Date
) -> Int {
    let cutoff = now.addingTimeInterval(-AISchedulerStatsPolicy.throughputWindow)

    return processingSamples
        .filter { $0.finishedAt >= cutoff }
        .reduce(0) { $0 + $1.recordCount }
}

nonisolated private func schedulerSourceSummary(_ sources: [String]) -> String {
    let uniqueSources = Array(Set(sources.filter { !$0.isEmpty })).sorted()

    guard let first = uniqueSources.first else {
        return "unknown"
    }

    guard uniqueSources.count > 1 else {
        return first
    }

    return "\(first) +\(uniqueSources.count - 1)"
}

nonisolated private func average(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
}

nonisolated private func p95(_ sortedValues: [Double]) -> Double {
    guard !sortedValues.isEmpty else {
        return 0
    }

    let index = min(
        max(Int(ceil(Double(sortedValues.count) * 0.95)) - 1, 0),
        sortedValues.count - 1
    )
    return sortedValues[index]
}

nonisolated struct AIVisualSchedulerBatch: Sendable {
    let requests: [ModelVisualRequest]
    let bucket: String
    let estimatedMemoryBytes: Int64
}

nonisolated enum AIVisualSchedulerPolicy {
    static let softMemoryLimitBytes: Int64 = 10 * 1024 * 1024 * 1024

    static func bucket(for request: ModelVisualRequest) -> String {
        [
            signature(for: request),
            "imageBytes:\(request.imageData.count / 262_144)",
            "promptTokens:\(AITextTokenBucket.bucket(for: AITextSchedulerPolicy.tokenEstimate(for: request.prompt)).rawValue)"
        ].joined(separator: "|")
    }

    static func estimatedBatchMemoryBytes(_ requests: [ModelVisualRequest]) -> Int64 {
        let imageBytes = requests.reduce(0) { $0 + $1.imageData.count }
        let promptTokens = requests.reduce(0) {
            $0 + AITextSchedulerPolicy.tokenEstimate(for: $1.prompt)
        }
        let maxTokens = requests.map { $0.generateParameters.maxTokens ?? 160 }.max() ?? 160
        return Int64(imageBytes * 4)
            + Int64(promptTokens * 1_000_000)
            + Int64(maxTokens * requests.count * 1_000_000)
            + Int64(requests.count * 512 * 1024 * 1024)
    }

    private static func signature(for request: ModelVisualRequest) -> String {
        let parameters = AIGenerateParametersSignature(request.generateParameters)
        let contextSignature = request.additionalContext?.keys.sorted().map { key in
            let value = request.additionalContext?[key].map { String(reflecting: $0) } ?? "<nil>"
            return "\(key)=\(value)"
        }
        .joined(separator: "|") ?? "<nil>"
        return "\(request.prompt)|\(request.instructions)|\(String(reflecting: parameters))|\(contextSignature)"
    }
}

actor AIVisualModelScheduler: Receiver {
    typealias Executor = @Sendable (AIVisualSchedulerBatch) async throws -> [String]

    private struct QueuedRequest {
        let bucket: String
        let request: ModelVisualRequest
        let queuedAt: Date
    }

    private struct CompletionSample {
        let finishedAt: Date
        let waitMilliseconds: Double
        let runMilliseconds: Double
        let batchSize: Int
    }

    private let maxBatchSize: Int
    private let maxWaitMilliseconds: Int
    private let executor: Executor
    private weak var actorSystem: ActorSystem?
    private var queue: [QueuedRequest] = []
    private var activeBatchCount = 0
    private var isFlushScheduled = false
    private var estimatedMemoryBytes: Int64 = 0
    private var completionSamples: [CompletionSample] = []
    private var processingSamples: [AISchedulerProcessingSample] = []
    private var activeBatches: [UUID: AISchedulerActiveBatchState] = [:]
    private var recentFailures: [AISchedulerFailure] = []

    init(
        actorSystem: ActorSystem? = nil,
        maxBatchSize: Int = 4,
        maxWaitMilliseconds: Int = 5,
        executor: @escaping Executor
    ) {
        self.actorSystem = actorSystem
        self.maxBatchSize = max(maxBatchSize, 1)
        self.maxWaitMilliseconds = max(maxWaitMilliseconds, 0)
        self.executor = executor
    }

    func attach(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    func receive(_ envelope: Envelope) async {
        guard let request = envelope.message as? ModelVisualRequest else {
            return
        }

        enqueue(request)
    }

    func statsSnapshot(now: Date = Date()) -> AISchedulerStatsSnapshot {
        pruneSamples(now: now)
        let oldestAge = queue.map { now.timeIntervalSince($0.queuedAt) }.max() ?? 0
        let buckets = schedulerBucketSnapshots(
            queuedWork: queue.map {
                AISchedulerQueuedWorkState(
                    bucket: $0.bucket,
                    eventKind: schedulerEventKind(source: $0.request.source, metadata: $0.request.metadata),
                    queuedAt: $0.queuedAt
                )
            },
            activeBatches: Array(activeBatches.values),
            processingSamples: processingSamples,
            now: now
        )
        let waitDurations = completionSamples.map(\.waitMilliseconds).sorted()
        let runDurations = completionSamples.map(\.runMilliseconds).sorted()
        let processedRecordsLast60Seconds = schedulerRecentRecordCount(
            processingSamples: processingSamples,
            now: now
        )

        return AISchedulerStatsSnapshot(
            id: AIModelSchedulerKind.visual.rawValue,
            name: AIModelSchedulerKind.visual.displayName,
            queuedDepthByBucket: buckets,
            activeBatchCount: activeBatchCount,
            activeRecordCount: activeBatches.values.reduce(0) { $0 + $1.recordCount },
            oldestQueuedAgeSeconds: oldestAge,
            processedRecordsLast60Seconds: processedRecordsLast60Seconds,
            recordsPerSecond: Double(processedRecordsLast60Seconds) / AISchedulerStatsPolicy.throughputWindow,
            averageWaitMilliseconds: average(waitDurations),
            p95WaitMilliseconds: p95(waitDurations),
            averageRunMilliseconds: average(runDurations),
            p95RunMilliseconds: p95(runDurations),
            averageBatchSize: average(processingSamples.map { Double($0.batchSize) }),
            estimatedMemoryBytes: estimatedMemoryBytes,
            activeEstimatedMemoryBytes: activeBatches.values.reduce(0) { $0 + $1.estimatedMemoryBytes },
            estimatedMemoryCapBytes: AIVisualSchedulerPolicy.softMemoryLimitBytes,
            recentFailures: recentFailures
        )
    }

    func shutdown() {
        let queued = queue
        queue.removeAll()
        queued.forEach { item in
            Task {
                await actorSystem?.broadcast(
                    from: nil,
                    message: ModelVisualFailed(
                        requestID: item.request.requestID,
                        message: String(describing: CancellationError()),
                        retryable: false
                    )
                )
            }
        }
    }

    private func enqueue(_ request: ModelVisualRequest) {
        queue.append(
            QueuedRequest(
                bucket: AIVisualSchedulerPolicy.bucket(for: request),
                request: request,
                queuedAt: Date()
            )
        )
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !isFlushScheduled else {
            return
        }

        isFlushScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(maxWaitMilliseconds))
            self.flushReadyBatch()
        }
    }

    private func flushReadyBatch() {
        isFlushScheduled = false

        guard activeBatchCount == 0,
              !queue.isEmpty else {
            return
        }

        let selectedBucket = queue.max {
            queueScore($0.bucket) < queueScore($1.bucket)
        }?.bucket
        guard let selectedBucket else {
            return
        }

        let selected = queue
            .filter { $0.bucket == selectedBucket }
            .reduce(into: [QueuedRequest]()) { partial, item in
                guard partial.count < maxBatchSize else {
                    return
                }

                let requests = (partial + [item]).map(\.request)
                let estimatedBytes = AIVisualSchedulerPolicy.estimatedBatchMemoryBytes(requests)
                if partial.isEmpty || estimatedBytes <= AIVisualSchedulerPolicy.softMemoryLimitBytes {
                    partial.append(item)
                }
            }
        let selectedIDs = Set(selected.map(\.request.requestID))
        let batchQueue = selected
        queue.removeAll { selectedIDs.contains($0.request.requestID) }
        activeBatchCount = 1
        let batch = AIVisualSchedulerBatch(
            requests: batchQueue.map(\.request),
            bucket: selectedBucket,
            estimatedMemoryBytes: AIVisualSchedulerPolicy.estimatedBatchMemoryBytes(batchQueue.map(\.request))
        )
        estimatedMemoryBytes = batch.estimatedMemoryBytes
        let activeBatch = AISchedulerActiveBatchState(
            id: UUID(),
            bucket: selectedBucket,
            source: schedulerSourceSummary(batchQueue.map(\.request.source)),
            eventKind: schedulerSourceSummary(
                batchQueue.map {
                    schedulerEventKind(source: $0.request.source, metadata: $0.request.metadata)
                }
            ),
            eventKindBreakdown: schedulerEventKindRecordBreakdown(
                batchQueue.map {
                    (
                        eventKind: schedulerEventKind(source: $0.request.source, metadata: $0.request.metadata),
                        recordCount: 1
                    )
                }
            ),
            requestCount: batchQueue.count,
            recordCount: batchQueue.count,
            batchSize: batchQueue.count,
            startedAt: Date(),
            estimatedMemoryBytes: batch.estimatedMemoryBytes,
            modelName: AIModel.visual.directoryName,
            maxTokens: batchQueue.first?.request.generateParameters.maxTokens,
            maxKVSize: batchQueue.first?.request.generateParameters.maxKVSize,
            kvBits: batchQueue.first?.request.generateParameters.kvBits,
            prefillStepSize: batchQueue.first?.request.generateParameters.prefillStepSize,
            promptTokenEstimate: nil,
            memoryEstimateBreakdown: nil
        )
        activeBatches[activeBatch.id] = activeBatch

        Task {
            await self.execute(
                batchQueue,
                batch: batch,
                activeBatchID: activeBatch.id,
                startedAt: activeBatch.startedAt
            )
        }
    }

    private func execute(
        _ queued: [QueuedRequest],
        batch: AIVisualSchedulerBatch,
        activeBatchID: UUID,
        startedAt: Date
    ) async {
        let finished: (Result<[String], Error>, Date) = await {
            do {
                let responses = try await executor(batch)
                return (.success(responses), Date())
            } catch {
                return (.failure(error), Date())
            }
        }()

        complete(
            queued,
            batch: batch,
            activeBatchID: activeBatchID,
            startedAt: startedAt,
            finishedAt: finished.1,
            result: finished.0
        )
    }

    private func complete(
        _ queued: [QueuedRequest],
        batch: AIVisualSchedulerBatch,
        activeBatchID: UUID,
        startedAt: Date,
        finishedAt: Date,
        result: Result<[String], Error>
    ) {
        activeBatchCount = 0
        activeBatches.removeValue(forKey: activeBatchID)

        switch result {
        case .success(let responses):
            guard responses.count == queued.count else {
                complete(
                    queued,
                    batch: batch,
                    activeBatchID: activeBatchID,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    result: .failure(
                        AISchedulerError.responseCountMismatch(
                            expected: queued.count,
                            actual: responses.count
                        )
                    )
                )
                return
            }

            processingSamples.append(
                AISchedulerProcessingSample(
                    finishedAt: finishedAt,
                    bucket: batch.bucket,
                    requestCount: queued.count,
                    recordCount: queued.count,
                    batchSize: queued.count,
                    eventKindBreakdown: schedulerEventKindRecordBreakdown(
                        queued.map {
                            (
                                eventKind: schedulerEventKind(
                                    source: $0.request.source,
                                    metadata: $0.request.metadata
                                ),
                                recordCount: 1
                            )
                        }
                    )
                )
            )

            zip(queued, responses).forEach { item, output in
                let timing = AISchedulerTiming(
                    queuedAt: item.queuedAt,
                    startedAt: startedAt,
                    finishedAt: finishedAt
                )
                completionSamples.append(
                    CompletionSample(
                        finishedAt: finishedAt,
                        waitMilliseconds: timing.waitMilliseconds,
                        runMilliseconds: timing.runMilliseconds,
                        batchSize: queued.count
                    )
                )
                Task {
                    await actorSystem?.broadcast(
                        from: nil,
                        message: ModelVisualCompleted(
                            requestID: item.request.requestID,
                            response: output,
                            schedulerMetadata: AISchedulerMetadata(
                                scheduler: .visual,
                                bucket: item.bucket,
                                batchSize: queued.count,
                                source: item.request.source,
                                eventKind: schedulerEventKind(
                                    source: item.request.source,
                                    metadata: item.request.metadata
                                )
                            ),
                            timing: timing
                        )
                    )
                }
            }
        case .failure(let error):
            queued.forEach { item in
                let failure = AISchedulerFailure(
                    id: UUID(),
                    requestID: item.request.requestID,
                    message: String(describing: error),
                    retryable: !(error is CancellationError),
                    occurredAt: finishedAt
                )
                recentFailures = ([failure] + recentFailures).prefix(10).map { $0 }
                Task {
                    await actorSystem?.broadcast(
                        from: nil,
                        message: ModelVisualFailed(
                            requestID: item.request.requestID,
                            message: failure.message,
                            retryable: failure.retryable
                        )
                    )
                }
            }
        }

        pruneSamples(now: finishedAt)
        flushReadyBatch()
    }

    private func queueScore(_ bucket: String) -> Double {
        let now = Date()
        let queued = queue.filter { $0.bucket == bucket }
        let highestPriority = queued
            .map(\.request.priority)
            .min { $0.rawValue < $1.rawValue } ?? .background
        let oldestAge = queued.map { now.timeIntervalSince($0.queuedAt) }.max() ?? 0
        return AITextSchedulerPolicy.score(
            priority: highestPriority,
            oldestAgeSeconds: oldestAge,
            queueDepth: queued.count
        )
    }

    private func pruneSamples(now: Date) {
        let cutoff = now.addingTimeInterval(-AIStatsWindow.rollingWindow)
        completionSamples = completionSamples.filter { $0.finishedAt >= cutoff }
        processingSamples = processingSamples.filter { $0.finishedAt >= cutoff }
        recentFailures = Array(recentFailures.prefix(10))
    }
}

actor AIRerankModelScheduler: Receiver {
    typealias Executor = @Sendable (ModelRerankRequest) async throws -> [ActivityAIReranking]

    private struct QueuedRequest {
        let request: ModelRerankRequest
        let bucket: String
        let queuedAt: Date
    }

    private struct CompletionSample {
        let finishedAt: Date
        let waitMilliseconds: Double
        let runMilliseconds: Double
    }

    private let executor: Executor
    private weak var actorSystem: ActorSystem?
    private var queue: [QueuedRequest] = []
    private var activeBatchCount = 0
    private var completionSamples: [CompletionSample] = []
    private var processingSamples: [AISchedulerProcessingSample] = []
    private var activeBatches: [UUID: AISchedulerActiveBatchState] = [:]
    private var recentFailures: [AISchedulerFailure] = []

    init(
        actorSystem: ActorSystem? = nil,
        executor: @escaping Executor
    ) {
        self.actorSystem = actorSystem
        self.executor = executor
    }

    func attach(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    func receive(_ envelope: Envelope) async {
        guard let request = envelope.message as? ModelRerankRequest else {
            return
        }

        queue.append(
            QueuedRequest(
                request: request,
                bucket: "documents:\(request.documents.count)",
                queuedAt: Date()
            )
        )
        drain()
    }

    func statsSnapshot(now: Date = Date()) -> AISchedulerStatsSnapshot {
        pruneSamples(now: now)
        let buckets = schedulerBucketSnapshots(
            queuedWork: queue.map {
                AISchedulerQueuedWorkState(
                    bucket: $0.bucket,
                    eventKind: schedulerEventKind(source: $0.request.source, metadata: $0.request.metadata),
                    queuedAt: $0.queuedAt
                )
            },
            activeBatches: Array(activeBatches.values),
            processingSamples: processingSamples,
            now: now
        )
        let waitDurations = completionSamples.map(\.waitMilliseconds).sorted()
        let runDurations = completionSamples.map(\.runMilliseconds).sorted()
        let processedRecordsLast60Seconds = schedulerRecentRecordCount(
            processingSamples: processingSamples,
            now: now
        )

        return AISchedulerStatsSnapshot(
            id: AIModelSchedulerKind.reranker.rawValue,
            name: AIModelSchedulerKind.reranker.displayName,
            queuedDepthByBucket: buckets,
            activeBatchCount: activeBatchCount,
            activeRecordCount: activeBatches.values.reduce(0) { $0 + $1.recordCount },
            oldestQueuedAgeSeconds: queue.map { now.timeIntervalSince($0.queuedAt) }.max() ?? 0,
            processedRecordsLast60Seconds: processedRecordsLast60Seconds,
            recordsPerSecond: Double(processedRecordsLast60Seconds) / AISchedulerStatsPolicy.throughputWindow,
            averageWaitMilliseconds: average(waitDurations),
            p95WaitMilliseconds: p95(waitDurations),
            averageRunMilliseconds: average(runDurations),
            p95RunMilliseconds: p95(runDurations),
            averageBatchSize: average(processingSamples.map { Double($0.batchSize) }),
            estimatedMemoryBytes: 0,
            recentFailures: recentFailures
        )
    }

    func shutdown() {
        let queued = queue
        queue.removeAll()
        queued.forEach { item in
            Task {
                await actorSystem?.broadcast(
                    from: nil,
                    message: ModelRerankFailed(
                        requestID: item.request.requestID,
                        message: String(describing: CancellationError()),
                        retryable: false
                    )
                )
            }
        }
    }

    private func drain() {
        guard activeBatchCount == 0,
              !queue.isEmpty else {
            return
        }

        let nextIndex = AIExecutionPriority.admissionOrder
            .compactMap { priority in
                queue.enumerated()
                    .filter { $0.element.request.priority == priority }
                    .min { $0.element.queuedAt < $1.element.queuedAt }?.offset
            }
            .first ?? 0
        let item = queue.remove(at: nextIndex)
        activeBatchCount = 1
        let activeBatch = AISchedulerActiveBatchState(
            id: UUID(),
            bucket: item.bucket,
            source: item.request.source,
            eventKind: schedulerEventKind(source: item.request.source, metadata: item.request.metadata),
            eventKindBreakdown: [
                AISchedulerEventKindRecordState(
                    eventKind: schedulerEventKind(source: item.request.source, metadata: item.request.metadata),
                    requestCount: 1,
                    recordCount: item.request.documents.count
                )
            ],
            requestCount: 1,
            recordCount: item.request.documents.count,
            batchSize: 1,
            startedAt: Date(),
            estimatedMemoryBytes: 0,
            modelName: AIModel.reranker.directoryName,
            maxTokens: nil,
            maxKVSize: nil,
            kvBits: nil,
            prefillStepSize: nil,
            promptTokenEstimate: nil,
            memoryEstimateBreakdown: nil
        )
        activeBatches[activeBatch.id] = activeBatch

        Task {
            let finished: (Result<[ActivityAIReranking], Error>, Date) = await {
                do {
                    let rankings = try await executor(item.request)
                    return (.success(rankings), Date())
                } catch {
                    return (.failure(error), Date())
                }
            }()
            complete(
                item,
                activeBatchID: activeBatch.id,
                startedAt: activeBatch.startedAt,
                finishedAt: finished.1,
                result: finished.0
            )
        }
    }

    private func complete(
        _ item: QueuedRequest,
        activeBatchID: UUID,
        startedAt: Date,
        finishedAt: Date,
        result: Result<[ActivityAIReranking], Error>
    ) {
        activeBatchCount = 0
        activeBatches.removeValue(forKey: activeBatchID)
        let timing = AISchedulerTiming(
            queuedAt: item.queuedAt,
            startedAt: startedAt,
            finishedAt: finishedAt
        )

        switch result {
        case .success(let rankings):
            completionSamples.append(
                CompletionSample(
                    finishedAt: finishedAt,
                    waitMilliseconds: timing.waitMilliseconds,
                    runMilliseconds: timing.runMilliseconds
                )
            )
            processingSamples.append(
                AISchedulerProcessingSample(
                    finishedAt: finishedAt,
                    bucket: item.bucket,
                    requestCount: 1,
                    recordCount: item.request.documents.count,
                    batchSize: 1,
                    eventKindBreakdown: schedulerEventKindRecordBreakdown([
                        (
                            eventKind: schedulerEventKind(
                                source: item.request.source,
                                metadata: item.request.metadata
                            ),
                            recordCount: item.request.documents.count
                        )
                    ])
                )
            )
            Task {
                await actorSystem?.broadcast(
                    from: nil,
                    message: ModelRerankCompleted(
                        requestID: item.request.requestID,
                        rankings: rankings,
                        schedulerMetadata: AISchedulerMetadata(
                            scheduler: .reranker,
                            bucket: item.bucket,
                            batchSize: 1,
                            source: item.request.source,
                            eventKind: schedulerEventKind(
                                source: item.request.source,
                                metadata: item.request.metadata
                            )
                        ),
                        timing: timing
                    )
                )
            }
        case .failure(let error):
            let failure = AISchedulerFailure(
                id: UUID(),
                requestID: item.request.requestID,
                message: String(describing: error),
                retryable: !(error is CancellationError),
                occurredAt: finishedAt
            )
            recentFailures = ([failure] + recentFailures).prefix(10).map { $0 }
            Task {
                await actorSystem?.broadcast(
                    from: nil,
                    message: ModelRerankFailed(
                        requestID: item.request.requestID,
                        message: failure.message,
                        retryable: failure.retryable
                    )
                )
            }
        }

        pruneSamples(now: finishedAt)
        drain()
    }

    private func pruneSamples(now: Date) {
        let cutoff = now.addingTimeInterval(-AIStatsWindow.rollingWindow)
        completionSamples = completionSamples.filter { $0.finishedAt >= cutoff }
        processingSamples = processingSamples.filter { $0.finishedAt >= cutoff }
        recentFailures = Array(recentFailures.prefix(10))
    }
}

actor AIActivityUMAPScheduler: Receiver {
    typealias Executor = @Sendable (ModelUMAPRequest) async throws -> [[Float]]

    private struct QueuedRequest {
        let request: ModelUMAPRequest
        let bucket: String
        let queuedAt: Date
    }

    private struct CompletionSample {
        let finishedAt: Date
        let waitMilliseconds: Double
        let runMilliseconds: Double
    }

    private let executor: Executor
    private weak var actorSystem: ActorSystem?
    private var queue: [QueuedRequest] = []
    private var activeBatchCount = 0
    private var completionSamples: [CompletionSample] = []
    private var processingSamples: [AISchedulerProcessingSample] = []
    private var activeBatches: [UUID: AISchedulerActiveBatchState] = [:]
    private var recentFailures: [AISchedulerFailure] = []

    init(
        actorSystem: ActorSystem? = nil,
        executor: @escaping Executor
    ) {
        self.actorSystem = actorSystem
        self.executor = executor
    }

    func attach(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    func receive(_ envelope: Envelope) async {
        guard let request = envelope.message as? ModelUMAPRequest else {
            return
        }

        queue.append(
            QueuedRequest(
                request: request,
                bucket: "vectors:\(request.vectors.count)",
                queuedAt: Date()
            )
        )
        drain()
    }

    func statsSnapshot(now: Date = Date()) -> AISchedulerStatsSnapshot {
        pruneSamples(now: now)
        let buckets = schedulerBucketSnapshots(
            queuedWork: queue.map {
                AISchedulerQueuedWorkState(
                    bucket: $0.bucket,
                    eventKind: schedulerEventKind(source: $0.request.source, metadata: $0.request.metadata),
                    queuedAt: $0.queuedAt
                )
            },
            activeBatches: Array(activeBatches.values),
            processingSamples: processingSamples,
            now: now
        )
        let waitDurations = completionSamples.map(\.waitMilliseconds).sorted()
        let runDurations = completionSamples.map(\.runMilliseconds).sorted()
        let processedRecordsLast60Seconds = schedulerRecentRecordCount(
            processingSamples: processingSamples,
            now: now
        )

        return AISchedulerStatsSnapshot(
            id: AIModelSchedulerKind.activityUMAP.rawValue,
            name: AIModelSchedulerKind.activityUMAP.displayName,
            queuedDepthByBucket: buckets,
            activeBatchCount: activeBatchCount,
            activeRecordCount: activeBatches.values.reduce(0) { $0 + $1.recordCount },
            oldestQueuedAgeSeconds: queue.map { now.timeIntervalSince($0.queuedAt) }.max() ?? 0,
            processedRecordsLast60Seconds: processedRecordsLast60Seconds,
            recordsPerSecond: Double(processedRecordsLast60Seconds) / AISchedulerStatsPolicy.throughputWindow,
            averageWaitMilliseconds: average(waitDurations),
            p95WaitMilliseconds: p95(waitDurations),
            averageRunMilliseconds: average(runDurations),
            p95RunMilliseconds: p95(runDurations),
            averageBatchSize: average(processingSamples.map { Double($0.batchSize) }),
            estimatedMemoryBytes: 0,
            recentFailures: recentFailures
        )
    }

    func shutdown() {
        let queued = queue
        queue.removeAll()
        queued.forEach { item in
            Task {
                await actorSystem?.broadcast(
                    from: nil,
                    message: ModelUMAPFailed(
                        requestID: item.request.requestID,
                        message: String(describing: CancellationError()),
                        retryable: false
                    )
                )
            }
        }
    }

    private func drain() {
        guard activeBatchCount == 0,
              !queue.isEmpty else {
            return
        }

        let item = queue.removeFirst()
        activeBatchCount = 1
        let activeBatch = AISchedulerActiveBatchState(
            id: UUID(),
            bucket: item.bucket,
            source: item.request.source,
            eventKind: schedulerEventKind(source: item.request.source, metadata: item.request.metadata),
            eventKindBreakdown: [
                AISchedulerEventKindRecordState(
                    eventKind: schedulerEventKind(source: item.request.source, metadata: item.request.metadata),
                    requestCount: 1,
                    recordCount: item.request.vectors.count
                )
            ],
            requestCount: 1,
            recordCount: item.request.vectors.count,
            batchSize: 1,
            startedAt: Date(),
            estimatedMemoryBytes: 0,
            modelName: AIModel.activityUMAP.directoryName,
            maxTokens: nil,
            maxKVSize: nil,
            kvBits: nil,
            prefillStepSize: nil,
            promptTokenEstimate: nil,
            memoryEstimateBreakdown: nil
        )
        activeBatches[activeBatch.id] = activeBatch
        Task {
            let finished: (Result<[[Float]], Error>, Date) = await {
                do {
                    let vectors = try await executor(item.request)
                    return (.success(vectors), Date())
                } catch {
                    return (.failure(error), Date())
                }
            }()
            complete(
                item,
                activeBatchID: activeBatch.id,
                startedAt: activeBatch.startedAt,
                finishedAt: finished.1,
                result: finished.0
            )
        }
    }

    private func complete(
        _ item: QueuedRequest,
        activeBatchID: UUID,
        startedAt: Date,
        finishedAt: Date,
        result: Result<[[Float]], Error>
    ) {
        activeBatchCount = 0
        activeBatches.removeValue(forKey: activeBatchID)
        let timing = AISchedulerTiming(
            queuedAt: item.queuedAt,
            startedAt: startedAt,
            finishedAt: finishedAt
        )

        switch result {
        case .success(let vectors):
            completionSamples.append(
                CompletionSample(
                    finishedAt: finishedAt,
                    waitMilliseconds: timing.waitMilliseconds,
                    runMilliseconds: timing.runMilliseconds
                )
            )
            processingSamples.append(
                AISchedulerProcessingSample(
                    finishedAt: finishedAt,
                    bucket: item.bucket,
                    requestCount: 1,
                    recordCount: item.request.vectors.count,
                    batchSize: 1,
                    eventKindBreakdown: schedulerEventKindRecordBreakdown([
                        (
                            eventKind: schedulerEventKind(
                                source: item.request.source,
                                metadata: item.request.metadata
                            ),
                            recordCount: item.request.vectors.count
                        )
                    ])
                )
            )
            Task {
                await actorSystem?.broadcast(
                    from: nil,
                    message: ModelUMAPCompleted(
                        requestID: item.request.requestID,
                        vectors: vectors,
                        schedulerMetadata: AISchedulerMetadata(
                            scheduler: .activityUMAP,
                            bucket: item.bucket,
                            batchSize: 1,
                            source: item.request.source,
                            eventKind: schedulerEventKind(
                                source: item.request.source,
                                metadata: item.request.metadata
                            )
                        ),
                        timing: timing
                    )
                )
            }
        case .failure(let error):
            let failure = AISchedulerFailure(
                id: UUID(),
                requestID: item.request.requestID,
                message: String(describing: error),
                retryable: !(error is CancellationError),
                occurredAt: finishedAt
            )
            recentFailures = ([failure] + recentFailures).prefix(10).map { $0 }
            Task {
                await actorSystem?.broadcast(
                    from: nil,
                    message: ModelUMAPFailed(
                        requestID: item.request.requestID,
                        message: failure.message,
                        retryable: failure.retryable
                    )
                )
            }
        }

        pruneSamples(now: finishedAt)
        drain()
    }

    private func pruneSamples(now: Date) {
        let cutoff = now.addingTimeInterval(-AIStatsWindow.rollingWindow)
        completionSamples = completionSamples.filter { $0.finishedAt >= cutoff }
        processingSamples = processingSamples.filter { $0.finishedAt >= cutoff }
        recentFailures = Array(recentFailures.prefix(10))
    }
}

actor AISchedulerEventBridge: Receiver {
    private weak var actorSystem: ActorSystem?
    private var textContinuations: [UUID: CheckedContinuation<String, Error>] = [:]
    private var visualContinuations: [UUID: CheckedContinuation<String, Error>] = [:]
    private var embeddingContinuations: [UUID: CheckedContinuation<[[Float]], Error>] = [:]
    private var rerankContinuations: [UUID: CheckedContinuation<[ActivityAIReranking], Error>] = [:]
    private var umapContinuations: [UUID: CheckedContinuation<[[Float]], Error>] = [:]

    func attach(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as ModelTextCompleted:
            textContinuations.removeValue(forKey: event.requestID)?.resume(returning: event.response)
        case let event as ModelTextFailed:
            textContinuations.removeValue(forKey: event.requestID)?.resume(
                throwing: AISchedulerError.unavailable(event.message)
            )
        case let event as ModelVisualCompleted:
            visualContinuations.removeValue(forKey: event.requestID)?.resume(returning: event.response)
        case let event as ModelVisualFailed:
            visualContinuations.removeValue(forKey: event.requestID)?.resume(
                throwing: AISchedulerError.unavailable(event.message)
            )
        case let event as ModelEmbeddingCompleted:
            embeddingContinuations.removeValue(forKey: event.requestID)?.resume(returning: event.vectors)
        case let event as ModelEmbeddingFailed:
            embeddingContinuations.removeValue(forKey: event.requestID)?.resume(
                throwing: AISchedulerError.unavailable(event.message)
            )
        case let event as ModelRerankCompleted:
            rerankContinuations.removeValue(forKey: event.requestID)?.resume(returning: event.rankings)
        case let event as ModelRerankFailed:
            rerankContinuations.removeValue(forKey: event.requestID)?.resume(
                throwing: AISchedulerError.unavailable(event.message)
            )
        case let event as ModelUMAPCompleted:
            umapContinuations.removeValue(forKey: event.requestID)?.resume(returning: event.vectors)
        case let event as ModelUMAPFailed:
            umapContinuations.removeValue(forKey: event.requestID)?.resume(
                throwing: AISchedulerError.unavailable(event.message)
            )
        default:
            return
        }
    }

    func requestText(_ request: ModelTextRequest) async throws -> String {
        guard let actorSystem else {
            throw AISchedulerError.unavailable("AI scheduler registry is not registered on an ActorSystem.")
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                textContinuations[request.requestID] = continuation
                Task {
                    await actorSystem.broadcast(from: nil, message: request)
                }
            }
        } onCancel: {
            Task {
                await self.cancelText(request.requestID)
            }
        }
    }

    func requestVisual(_ request: ModelVisualRequest) async throws -> String {
        guard let actorSystem else {
            throw AISchedulerError.unavailable("AI scheduler registry is not registered on an ActorSystem.")
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                visualContinuations[request.requestID] = continuation
                Task {
                    await actorSystem.broadcast(from: nil, message: request)
                }
            }
        } onCancel: {
            Task {
                await self.cancelVisual(request.requestID)
            }
        }
    }

    func requestEmbedding(_ request: ModelEmbeddingRequest) async throws -> [[Float]] {
        guard let actorSystem else {
            throw AISchedulerError.unavailable("AI scheduler registry is not registered on an ActorSystem.")
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                embeddingContinuations[request.requestID] = continuation
                Task {
                    await actorSystem.broadcast(from: nil, message: request)
                }
            }
        } onCancel: {
            Task {
                await self.cancelEmbedding(request.requestID)
            }
        }
    }

    func requestRerank(_ request: ModelRerankRequest) async throws -> [ActivityAIReranking] {
        guard let actorSystem else {
            throw AISchedulerError.unavailable("AI scheduler registry is not registered on an ActorSystem.")
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                rerankContinuations[request.requestID] = continuation
                Task {
                    await actorSystem.broadcast(from: nil, message: request)
                }
            }
        } onCancel: {
            Task {
                await self.cancelRerank(request.requestID)
            }
        }
    }

    func requestUMAP(_ request: ModelUMAPRequest) async throws -> [[Float]] {
        guard let actorSystem else {
            throw AISchedulerError.unavailable("AI scheduler registry is not registered on an ActorSystem.")
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                umapContinuations[request.requestID] = continuation
                Task {
                    await actorSystem.broadcast(from: nil, message: request)
                }
            }
        } onCancel: {
            Task {
                await self.cancelUMAP(request.requestID)
            }
        }
    }

    private func cancelText(_ requestID: UUID) {
        textContinuations.removeValue(forKey: requestID)?.resume(throwing: CancellationError())
    }

    private func cancelVisual(_ requestID: UUID) {
        visualContinuations.removeValue(forKey: requestID)?.resume(throwing: CancellationError())
    }

    private func cancelEmbedding(_ requestID: UUID) {
        embeddingContinuations.removeValue(forKey: requestID)?.resume(throwing: CancellationError())
    }

    private func cancelRerank(_ requestID: UUID) {
        rerankContinuations.removeValue(forKey: requestID)?.resume(throwing: CancellationError())
    }

    private func cancelUMAP(_ requestID: UUID) {
        umapContinuations.removeValue(forKey: requestID)?.resume(throwing: CancellationError())
    }
}

actor AISchedulerRegistryRegistrationState {
    private var hasRegistration = false

    func markRegistered() {
        hasRegistration = true
    }

    func claimFallbackRegistration() -> Bool {
        guard !hasRegistration else {
            return false
        }

        hasRegistration = true
        return true
    }
}

final class AISchedulerRegistry: AISchedulerStatsReporting, @unchecked Sendable {
    nonisolated static let shared = AISchedulerRegistry(runtime: AISchedulerModelRuntime.shared)

    let smallTextScheduler: AITextModelScheduler
    let bigTextScheduler: AITextModelScheduler
    let textRouter: AITextModelSchedulerRouter
    let visualScheduler: AIVisualModelScheduler
    let embeddingScheduler: AIEmbeddingModelScheduler
    let rerankerScheduler: AIRerankModelScheduler
    let activityUMAPScheduler: AIActivityUMAPScheduler
    private let eventBridge: AISchedulerEventBridge
    private let fallbackActorSystem = ActorSystem()
    private let registrationState = AISchedulerRegistryRegistrationState()
    private let warmTextExecutor: @Sendable () async -> Void

    convenience init(runtime: AISchedulerModelRuntime) {
        self.init(
            textExecutor: { batch in
                try await runtime.executeText(batch)
            },
            visualExecutor: { batch in
                try await runtime.executeVisual(batch)
            },
            embeddingExecutor: { request in
                try await runtime.executeEmbedding(request)
            },
            rerankerExecutor: { request in
                try await runtime.executeRerank(request)
            },
            activityUMAPExecutor: { request in
                try await runtime.executeUMAP(request)
            },
            streamTextExecutor: { lane, prompt, instructions, generateParameters, additionalContext, metadata in
                await runtime.streamText(
                    lane: lane,
                    prompt: prompt,
                    instructions: instructions,
                    generateParameters: generateParameters,
                    additionalContext: additionalContext,
                    telemetryMetadata: metadata
                )
            },
            warmTextExecutor: {
                await runtime.warmTextModel()
            }
        )
    }

    init(
        textExecutor: @escaping AITextModelScheduler.Executor = { _ in
            throw AISchedulerError.unavailable("No text scheduler executor is configured.")
        },
        visualExecutor: @escaping AIVisualModelScheduler.Executor = { _ in
            throw AISchedulerError.unavailable("No visual scheduler executor is configured.")
        },
        embeddingExecutor: @escaping AIEmbeddingModelScheduler.Executor = { _ in
            throw AISchedulerError.unavailable("No embedding scheduler executor is configured.")
        },
        rerankerExecutor: @escaping AIRerankModelScheduler.Executor = { _ in
            throw AISchedulerError.unavailable("No reranker scheduler executor is configured.")
        },
        activityUMAPExecutor: @escaping AIActivityUMAPScheduler.Executor = { request in
            request.vectors
        },
        streamTextExecutor: @escaping @Sendable (
            AITextModelLane,
            String,
            String,
            GenerateParameters,
            [String: any Sendable]?,
            [String: String]
        ) async -> AsyncThrowingStream<String, Error> = { _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: AISchedulerError.unavailable("No streaming text scheduler executor is configured."))
            }
        },
        warmTextExecutor: @escaping @Sendable () async -> Void = {}
    ) {
        self.warmTextExecutor = warmTextExecutor
        self.eventBridge = AISchedulerEventBridge()
        let smallTextScheduler = AITextModelScheduler(
            schedulerKind: .textSmall,
            lane: .small,
            capacityProfile: .qwen35PointEightBOptiQ4Bit,
            maxBatchSize: 16,
            maxActiveBatches: AITextSchedulerCapacityProfile.qwen35PointEightBOptiQ4Bit.maxActiveBatches,
            maxActiveRecords: AITextSchedulerCapacityProfile.qwen35PointEightBOptiQ4Bit.maxActiveRecords,
            streamExecutor: streamTextExecutor,
            executor: textExecutor
        )
        let bigTextScheduler = AITextModelScheduler(
            schedulerKind: .textBig,
            lane: .big,
            capacityProfile: .qwen35FourBOptiQ4Bit,
            streamExecutor: streamTextExecutor,
            executor: textExecutor
        )
        self.smallTextScheduler = smallTextScheduler
        self.bigTextScheduler = bigTextScheduler
        self.textRouter = AITextModelSchedulerRouter(
            smallScheduler: smallTextScheduler,
            bigScheduler: bigTextScheduler
        )
        self.visualScheduler = AIVisualModelScheduler(executor: visualExecutor)
        self.embeddingScheduler = AIEmbeddingModelScheduler(
            executor: embeddingExecutor
        )
        self.rerankerScheduler = AIRerankModelScheduler(executor: rerankerExecutor)
        self.activityUMAPScheduler = AIActivityUMAPScheduler(executor: activityUMAPExecutor)
    }

    func streamText(
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]? = nil,
        telemetryMetadata: [String: String] = [:]
    ) async -> AsyncThrowingStream<String, Error> {
        await ensureRegistered()
        return await textRouter.streamText(
            prompt: prompt,
            instructions: instructions,
            generateParameters: generateParameters,
            additionalContext: additionalContext,
            telemetryMetadata: telemetryMetadata
        )
    }

    func warmTextModel() async {
        await warmTextExecutor()
    }

    func register(on actorSystem: ActorSystem) async {
        await registrationState.markRegistered()
        await eventBridge.attach(actorSystem: actorSystem)
        await smallTextScheduler.attach(actorSystem: actorSystem)
        await bigTextScheduler.attach(actorSystem: actorSystem)
        await visualScheduler.attach(actorSystem: actorSystem)
        await embeddingScheduler.attach(actorSystem: actorSystem)
        await rerankerScheduler.attach(actorSystem: actorSystem)
        await activityUMAPScheduler.attach(actorSystem: actorSystem)
        _ = await actorSystem.register(eventBridge)
        _ = await actorSystem.register(textRouter)
        _ = await actorSystem.register(visualScheduler)
        _ = await actorSystem.register(embeddingScheduler)
        _ = await actorSystem.register(rerankerScheduler)
        _ = await actorSystem.register(activityUMAPScheduler)
    }

    func shutdownAll() async {
        await smallTextScheduler.shutdown()
        await bigTextScheduler.shutdown()
        await visualScheduler.shutdown()
        await embeddingScheduler.shutdown()
        await rerankerScheduler.shutdown()
        await activityUMAPScheduler.shutdown()
        await AISchedulerModelRuntime.shared.shutdown()
    }

    func aiSchedulerSnapshots() async -> [AISchedulerStatsSnapshot] {
        await [
            smallTextScheduler.statsSnapshot(),
            bigTextScheduler.statsSnapshot(),
            visualScheduler.statsSnapshot(),
            embeddingScheduler.statsSnapshot(),
            rerankerScheduler.statsSnapshot(),
            activityUMAPScheduler.statsSnapshot()
        ]
    }

    func requestText(_ request: ModelTextRequest) async throws -> String {
        await ensureRegistered()
        return try await eventBridge.requestText(request)
    }

    func requestVisual(_ request: ModelVisualRequest) async throws -> String {
        await ensureRegistered()
        return try await eventBridge.requestVisual(request)
    }

    func requestEmbedding(_ request: ModelEmbeddingRequest) async throws -> [[Float]] {
        await ensureRegistered()
        return try await eventBridge.requestEmbedding(request)
    }

    func requestRerank(_ request: ModelRerankRequest) async throws -> [ActivityAIReranking] {
        await ensureRegistered()
        return try await eventBridge.requestRerank(request)
    }

    func requestUMAP(_ request: ModelUMAPRequest) async throws -> [[Float]] {
        await ensureRegistered()
        return try await eventBridge.requestUMAP(request)
    }

    private func ensureRegistered() async {
        guard await registrationState.claimFallbackRegistration() else {
            return
        }

        await register(on: fallbackActorSystem)
    }
}

nonisolated final class AISchedulerClient:
    ActivityEmbeddingGenerating,
    AITextResponding,
    ActivityImageDescribing,
    ActivityRerankingGenerating,
    ActivityTextStreamingGenerating,
    SearchSummaryGenerating,
    SkillProcedureGenerating,
    @unchecked Sendable {
    nonisolated static let shared = AISchedulerClient()

    private let registry: AISchedulerRegistry
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init(registry: AISchedulerRegistry = .shared) {
        self.registry = registry
    }

    func respond(
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?
    ) async throws -> String {
        try await respond(
            source: "direct-text",
            priority: .interactive,
            prompt: prompt,
            instructions: instructions,
            generateParameters: generateParameters,
            additionalContext: additionalContext
        )
    }

    func respond(
        source: String,
        priority: AIExecutionPriority,
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]? = nil
    ) async throws -> String {
        try await registry.requestText(
            ModelTextRequest(
                source: source,
                priority: priority,
                prompt: prompt,
                instructions: instructions,
                generateParameters: generateParameters,
                additionalContext: additionalContext,
                metadata: ["event_kind": source]
            )
        )
    }

    func respond(
        prompts: [String],
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?
    ) async throws -> [String] {
        try await respond(
            source: "direct-text-batch",
            priority: .interactive,
            prompts: prompts,
            instructions: instructions,
            generateParameters: generateParameters,
            additionalContext: additionalContext
        )
    }

    func respond(
        source: String,
        priority: AIExecutionPriority,
        prompts: [String],
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]? = nil
    ) async throws -> [String] {
        guard !prompts.isEmpty else {
            return []
        }

        return try await withThrowingTaskGroup(
            of: (Int, String).self,
            returning: [String].self
        ) { group in
            prompts.enumerated().forEach { index, prompt in
                group.addTask {
                    let response = try await self.respond(
                        source: source,
                        priority: priority,
                        prompt: prompt,
                        instructions: instructions,
                        generateParameters: generateParameters,
                        additionalContext: additionalContext
                    )
                    return (index, response)
                }
            }

            var responses = Array(repeating: "", count: prompts.count)
            for try await (index, response) in group {
                responses[index] = response
            }
            return responses
        }
    }

    func describeImage(_ image: Data) async -> String {
        do {
            return try await registry.requestVisual(
                ModelVisualRequest(
                    source: "image-description",
                    priority: .interactive,
                    prompt: DescribeImageActor.prompt,
                    imageData: image,
                    instructions: DescribeImageActor.instructions,
                    generateParameters: GenerateParameters(maxTokens: 160, temperature: 0),
                    additionalContext: ["enable_thinking": false],
                    metadata: ["event_kind": "image-description"]
                )
            )
        } catch {
            logger.error("ai-scheduler-client visual request failed error=\(String(describing: error), privacy: .public)")
            return "Image description unavailable."
        }
    }

    func generateVectors(for texts: [String], promptPrefix: String?) async -> [[Float]] {
        await generateVectors(for: texts, promptPrefix: promptPrefix, source: "embedding")
    }

    func generateVectors(for texts: [String], promptPrefix: String?, source: String) async -> [[Float]] {
        do {
            return try await registry.requestEmbedding(
                ModelEmbeddingRequest(
                    source: source,
                    priority: .background,
                    texts: texts,
                    promptPrefix: promptPrefix,
                    metadata: ["event_kind": source]
                )
            )
        } catch {
            return []
        }
    }

    func generateRerankings(
        query: String,
        documents: [String],
        instruction: String
    ) async -> [ActivityAIReranking] {
        await generateRerankings(
            query: query,
            documents: documents,
            instruction: instruction,
            source: "reranking"
        )
    }

    func generateRerankings(
        query: String,
        documents: [String],
        instruction: String,
        source: String
    ) async -> [ActivityAIReranking] {
        do {
            return try await registry.requestRerank(
                ModelRerankRequest(
                    source: source,
                    priority: .interactive,
                    query: query,
                    documents: documents,
                    instruction: instruction,
                    metadata: ["event_kind": source]
                )
            )
        } catch {
            return []
        }
    }

    func streamResponse(
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        await registry.streamText(
            prompt: prompt,
            instructions: instructions,
            generateParameters: generateParameters,
            additionalContext: ["enable_thinking": false],
            telemetryMetadata: ["request_type": "generic_stream"]
        )
    }

    func warmSearchSummaryModel(traceStartedAt: Date?) async {
        await registry.warmTextModel()
    }

    func searchSummary(
        query: String,
        rankedDocuments: [String],
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        let cleanedDocuments = rankedDocuments.filter { !$0.isEmpty }

        guard !query.isEmpty,
              !cleanedDocuments.isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        return await registry.streamText(
            prompt: ActivityTextGenerationActor.searchSummaryPrompt(
                query: query,
                rankedDocuments: cleanedDocuments
            ),
            instructions: ActivityTextGenerationActor.searchSummaryInstructions,
            generateParameters: GenerateParameters(maxTokens: 220, temperature: 0),
            additionalContext: ["enable_thinking": false],
            telemetryMetadata: [
                "request_type": "search_summary",
                "ranked_document_count": "\(cleanedDocuments.count)"
            ]
        )
    }

    func skillProcedure(
        prompt: String,
        instructions: String,
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        await registry.streamText(
            prompt: prompt,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: Vars.skillProcedureMaxTokens, temperature: 0.2),
            additionalContext: ["enable_thinking": true],
            telemetryMetadata: ["request_type": "skill_procedure"]
        )
    }
}
