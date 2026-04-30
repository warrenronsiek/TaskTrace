//
//  AIModelRuntime.swift
//  TaskTrace
//

import CoreImage
import Foundation
import MLX
import MLXEmbedders
import MLXLLM
import MLXLMCommon
import MLXVLM
import Tokenizers
import WebP

nonisolated enum AIImageDataDecoder {
    static func image(from imageData: Data) throws -> CIImage {
        if let image = CIImage(
            data: imageData,
            options: [.applyOrientationProperty: true]
        ) {
            return image
        }

        let webPImage = try WebPDecoder().decode(
            imageData,
            options: WebPDecoderOptions()
        )
        return CIImage(cgImage: webPImage)
    }
}

nonisolated enum AIModel: String, Sendable {
    case textBig
    case textSmall
    case visual
    case embedding
    case reranker
    case activityUMAP

    nonisolated enum Family: Sendable {
        case chatLLM
        case chatVLM
        case embedding
        case reranker
        case activityUMAP
    }

    nonisolated var family: Family {
        switch self {
        case .textBig, .textSmall:
            .chatLLM
        case .visual:
            .chatVLM
        case .embedding:
            .embedding
        case .reranker:
            .reranker
        case .activityUMAP:
            .activityUMAP
        }
    }

    nonisolated var directoryName: String {
        switch self {
        case .textBig:
            Vars.bigTextModelDirectoryName
        case .textSmall:
            Vars.smallTextModelDirectoryName
        case .visual:
            Vars.visualModelDirectoryName
        case .embedding:
            Vars.embeddingModelDirectoryName
        case .reranker:
            Vars.rerankerModelDirectoryName
        case .activityUMAP:
            "ActivityUMAP"
        }
    }

    nonisolated func directory(bundle: Bundle = .main) -> URL? {
        switch self {
        case .textBig:
            Vars.bigTextModelDirectory(bundle: bundle)
        case .textSmall:
            Vars.smallTextModelDirectory(bundle: bundle)
        case .visual:
            Vars.visualModelDirectory(bundle: bundle)
        case .embedding:
            Vars.embeddingModelDirectory(bundle: bundle)
        case .reranker:
            Vars.rerankerModelDirectory(bundle: bundle)
        case .activityUMAP:
            nil
        }
    }
}

nonisolated enum AITextModelLane: String, CaseIterable, Sendable {
    case small
    case big

    var model: AIModel {
        switch self {
        case .small:
            .textSmall
        case .big:
            .textBig
        }
    }

    var displayName: String {
        switch self {
        case .small:
            "Text Small"
        case .big:
            "Text Big"
        }
    }
}

nonisolated struct AIGenerateParametersSignature: Hashable, Sendable {
    let prefillStepSize: Int
    let maxTokens: Int?
    let maxKVSize: Int?
    let kvBits: Int?
    let kvGroupSize: Int
    let quantizedKVStart: Int
    let temperature: Float
    let topP: Float
    let topK: Int
    let minP: Float
    let repetitionPenalty: Float?
    let repetitionContextSize: Int
    let presencePenalty: Float?
    let presenceContextSize: Int
    let frequencyPenalty: Float?
    let frequencyContextSize: Int

    init(_ value: GenerateParameters) {
        self.prefillStepSize = value.prefillStepSize
        self.maxTokens = value.maxTokens
        self.maxKVSize = value.maxKVSize
        self.kvBits = value.kvBits
        self.kvGroupSize = value.kvGroupSize
        self.quantizedKVStart = value.quantizedKVStart
        self.temperature = value.temperature
        self.topP = value.topP
        self.topK = value.topK
        self.minP = value.minP
        self.repetitionPenalty = value.repetitionPenalty
        self.repetitionContextSize = value.repetitionContextSize
        self.presencePenalty = value.presencePenalty
        self.presenceContextSize = value.presenceContextSize
        self.frequencyPenalty = value.frequencyPenalty
        self.frequencyContextSize = value.frequencyContextSize
    }
}

nonisolated private struct AISchedulerTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return AISchedulerTokenizer(upstream: upstream)
    }
}

nonisolated private struct AISchedulerTokenizer: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

actor AISchedulerModelRuntime {
    static let shared = AISchedulerModelRuntime()

    private var chatModelTasks: [AIModel: Task<MLXLMCommon.ModelContainer, Error>] = [:]
    private var embeddingModelTasks: [AIModel: Task<MLXEmbedders.EmbedderModelContainer, Error>] = [:]
    private var activeModelUseCount: [AIModel: Int] = [:]
    private var unloadTasks: [AIModel: Task<Void, Never>] = [:]
    private var streamTaskByID: [UUID: Task<Void, Never>] = [:]
    private var activeOperationCount = 0
    private var isShuttingDown = false
    private var shutdownContinuations: [CheckedContinuation<Void, Never>] = []

    init(warmOnInit: Bool = true) {
        if warmOnInit {
            Task(priority: .utility) {
                await self.warmTextModel()
                try? await self.warmModel(.reranker)
            }
        }
    }

    func respond(
        prompts: [String],
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?
    ) async throws -> [String] {
        guard !prompts.isEmpty else {
            return []
        }

        let requests = prompts.map {
            ModelTextRequest(
                source: "direct-text-batch",
                priority: .interactive,
                prompt: $0,
                instructions: instructions,
                generateParameters: generateParameters,
                additionalContext: additionalContext,
                metadata: ["event_kind": "direct-text-batch"]
            )
        }
        let tokenCounts = prompts.map(AITextSchedulerPolicy.tokenEstimate)
        return try await executeText(
            AITextSchedulerBatch(
                lane: .big,
                requests: requests,
                promptTokenCounts: tokenCounts,
                bucket: AITextTokenBucket.bucket(for: tokenCounts.max() ?? 0),
                estimatedMemoryBytes: AITextSchedulerPolicy.estimatedBatchMemoryBytes(
                    promptTokens: tokenCounts,
                    maxTokens: generateParameters.maxTokens
                )
            )
        )
    }

    func executeText(_ batch: AITextSchedulerBatch) async throws -> [String] {
        guard !batch.requests.isEmpty else {
            return []
        }

        return try await respondBatch(
            model: batch.lane.model,
            requests: batch.requests,
            telemetryMetadata: [
                "modality": "text",
                "text_lane": batch.lane.rawValue,
                "scheduler_bucket": batch.bucket.rawValue,
                "batch_size": "\(batch.requests.count)"
            ]
        )
    }

    func executeVisual(_ batch: AIVisualSchedulerBatch) async throws -> [String] {
        guard !batch.requests.isEmpty else {
            return []
        }

        return try await respondVisualBatch(
            requests: batch.requests,
            telemetryMetadata: [
                "modality": "visual",
                "input_bytes": "\(batch.requests.reduce(0) { $0 + $1.imageData.count })",
                "scheduler_bucket": batch.bucket,
                "batch_size": "\(batch.requests.count)"
            ]
        )
    }

    func executeEmbedding(_ request: ModelEmbeddingRequest) async throws -> [[Float]] {
        let preparedTexts = request.texts.map {
            AITextUtilities.prefixedText($0, promptPrefix: request.promptPrefix)
        }

        guard !preparedTexts.isEmpty else {
            return []
        }

        return try await withTrackedOperation {
            beginModelUse(.embedding)
            let modelTask = cachedEmbeddingModelTask(for: .embedding)

            do {
                let vectors = try await modelTask.value.perform { context -> [[Float]] in
                    let model = context.model
                    let tokenizer = context.tokenizer
                    let encodedTexts = preparedTexts.map {
                        tokenizer.encode(text: $0, addSpecialTokens: true)
                    }
                    let maxLength = encodedTexts.map(\.count).max() ?? 0

                    guard maxLength > 0 else {
                        return Array(repeating: [Float](), count: preparedTexts.count)
                    }

                    let paddingToken = tokenizer.eosTokenId ?? 0
                    let padded = stacked(
                        encodedTexts.map { tokens in
                            MLXArray(
                                Array(
                                    repeating: paddingToken,
                                    count: maxLength - tokens.count
                                ) + tokens
                            )
                        }
                    )
                    let attentionMask = (padded .!= paddingToken)
                    let tokenTypes = MLXArray.zeros(like: padded)
                    let output = model(
                        padded,
                        positionIds: nil,
                        tokenTypeIds: tokenTypes,
                        attentionMask: attentionMask
                    )
                    let pooled = Pooling(strategy: .last)(
                        output,
                        mask: attentionMask,
                        normalize: true,
                        applyLayerNorm: false
                    )
                    pooled.eval()
                    return (0..<pooled.dim(0)).map { rowIndex in
                        pooled[rowIndex].asArray(Float.self)
                    }
                }
                Memory.clearCache()
                endModelUse(.embedding)
                return vectors
            } catch {
                endModelUse(.embedding)
                throw error
            }
        }
    }

    func executeRerank(_ request: ModelRerankRequest) async throws -> [ActivityAIReranking] {
        guard !request.query.isEmpty, !request.documents.isEmpty else {
            return []
        }

        return try await withTrackedOperation {
            beginModelUse(.reranker)
            let modelTask = cachedChatModelTask(for: .reranker)

            do {
                let rankings: [ActivityAIReranking] = try await modelTask.value.perform { context in
                    let yesTokenID = context.tokenizer.encode(
                        text: "yes",
                        addSpecialTokens: false
                    ).first
                    let noTokenID = context.tokenizer.encode(
                        text: "no",
                        addSpecialTokens: false
                    ).first

                    guard let yesTokenID, let noTokenID else {
                        return []
                    }

                    return request.documents.enumerated().map { index, document in
                        let prompt = ActivityRerankingActor.prompt(
                            query: request.query,
                            document: document,
                            instruction: request.instruction
                        )
                        let promptTokens = context.tokenizer.encode(
                            text: prompt,
                            addSpecialTokens: false
                        )
                        let score = ActivityRerankingActor.score(
                            promptTokens: promptTokens,
                            model: context.model,
                            yesTokenID: yesTokenID,
                            noTokenID: noTokenID
                        )
                        return ActivityAIReranking(documentIndex: index, score: score)
                    }
                    .sorted { $0.score > $1.score }
                }
                Memory.clearCache()
                endModelUse(.reranker)
                return rankings
            } catch {
                endModelUse(.reranker)
                throw error
            }
        }
    }

    func executeUMAP(_ request: ModelUMAPRequest) async throws -> [[Float]] {
        guard let modelDirectoryURL = request.modelDirectoryURL else {
            return request.vectors
        }

        guard let vectorDimension = request.vectors.first?.count else {
            return []
        }

        precondition(
            request.vectors.allSatisfy { $0.count == vectorDimension },
            "Activity UMAP requires consistent embedding dimensions."
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let artifact = try decoder.decode(
            ActivityUMAPModelArtifact.self,
            from: Data(contentsOf: modelDirectoryURL.appendingPathComponent("activity-umap-model.json"))
        )
        let model = try ActivityUMAPPersistedModel(
            artifact: artifact,
            directoryURL: modelDirectoryURL
        )
        let vectorData = request.vectors.reduce(
            into: Data(capacity: request.vectors.count * vectorDimension * MemoryLayout<Float>.stride)
        ) { data, vector in
            data.append(vector.withUnsafeBytes { Data($0) })
        }
        let reducedEmbeddings = model.transform(
            MLXArray(
                vectorData,
                [request.vectors.count, vectorDimension],
                type: Float.self
            )
        )
        let reducedValues = reducedEmbeddings.asArray(Float.self)
        let reducedDimension = reducedEmbeddings.dim(1)

        return request.vectors.indices.map { index in
            let start = index * reducedDimension
            let end = start + reducedDimension
            return Array(reducedValues[start..<end])
        }
    }

    func streamText(
        lane: AITextModelLane,
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?,
        telemetryMetadata: [String: String]
    ) async -> AsyncThrowingStream<String, Error> {
        guard !prompt.isEmpty,
              !isShuttingDown else {
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let streamTaskID = UUID()
        let task = Task.detached(priority: .userInitiated) {
            await self.runStream(
                id: streamTaskID,
                model: lane.model,
                prompt: prompt,
                instructions: instructions,
                generateParameters: generateParameters,
                additionalContext: additionalContext,
                telemetryMetadata: telemetryMetadata,
                continuation: continuation
            )
        }
        streamTaskByID[streamTaskID] = task
        continuation.onTermination = { _ in
            task.cancel()
        }
        return stream
    }

    func warmTextModel() async {
        try? await warmModel(.textSmall)
        try? await warmModel(.textBig)
    }

    func shutdown() async {
        isShuttingDown = true
        unloadTasks.values.forEach { $0.cancel() }
        unloadTasks.removeAll()

        let streamTasks = Array(streamTaskByID.values)
        streamTasks.forEach { $0.cancel() }

        guard activeOperationCount > 0 || !streamTaskByID.isEmpty else {
            chatModelTasks.removeAll()
            embeddingModelTasks.removeAll()
            Memory.clearCache()
            return
        }

        await withCheckedContinuation { continuation in
            shutdownContinuations.append(continuation)
        }
        chatModelTasks.removeAll()
        embeddingModelTasks.removeAll()
        Memory.clearCache()
    }

    private func warmModel(_ model: AIModel) async throws {
        try await withTrackedOperation {
            beginModelUse(model)
            do {
                switch model.family {
                case .embedding:
                    _ = try await cachedEmbeddingModelTask(for: model).value
                case .chatLLM, .chatVLM, .reranker:
                    _ = try await cachedChatModelTask(for: model).value
                case .activityUMAP:
                    break
                }
                endModelUse(model)
            } catch {
                endModelUse(model)
                throw error
            }
        }
    }

    private func respond(
        model: AIModel,
        prompt: String,
        image: CIImage? = nil,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?,
        telemetryMetadata: [String: String]
    ) async throws -> String {
        try await withChatSession(
            model: model,
            instructions: instructions,
            generateParameters: generateParameters,
            additionalContext: additionalContext,
            telemetryMetadata: telemetryMetadata
        ) { session in
            if let image {
                return try await session.respond(
                    to: prompt,
                    image: .ciImage(image)
                )
            }

            return try await session.respond(to: prompt)
        }
    }

    private func respondBatch(
        model: AIModel,
        requests: [ModelTextRequest],
        telemetryMetadata: [String: String]
    ) async throws -> [String] {
        guard let firstRequest = requests.first else {
            return []
        }

        let signature = AITextSchedulerPolicy.signature(
            instructions: firstRequest.instructions,
            generateParameters: firstRequest.generateParameters,
            additionalContext: firstRequest.additionalContext
        )
        precondition(
            requests.allSatisfy {
                AITextSchedulerPolicy.signature(
                    instructions: $0.instructions,
                    generateParameters: $0.generateParameters,
                    additionalContext: $0.additionalContext
                ) == signature
            },
            "Text batch requests must share instructions, generation parameters, and additional context."
        )

        return try await withTrackedOperation {
            beginModelUse(model)
            let modelTask = cachedChatModelTask(for: model)

            do {
                let responses: [String] = try await modelTask.value.perform { context in
                    let encodedRequests = try requests.enumerated().map { index, request in
                        let messages: [[String: any Sendable]] = {
                            let userMessage: [String: any Sendable] = [
                                "role": "user",
                                "content": request.prompt
                            ]

                            guard !request.instructions.isEmpty else {
                                return [userMessage]
                            }

                            return [
                                [
                                    "role": "system",
                                    "content": request.instructions
                                ] as [String: any Sendable],
                                userMessage
                            ]
                        }()
                        return (
                            index: index,
                            tokens: try context.tokenizer.applyChatTemplate(
                                messages: messages,
                                tools: nil,
                                additionalContext: request.additionalContext
                            )
                        )
                    }
                    let groups = {
                        guard firstRequest.generateParameters.maxKVSize == nil else {
                            return Array(
                                Dictionary(grouping: encodedRequests) {
                                    $0.tokens.count
                                }.values
                            )
                        }

                        return [encodedRequests]
                    }()
                    var responses = Array(repeating: "", count: requests.count)

                    for group in groups {
                        let tokenRows = group.map(\.tokens)
                        let promptLength = tokenRows.map(\.count).max() ?? 0
                        let paddingToken = context.tokenizer.eosTokenId ?? 0
                        let leftPadding = tokenRows.map { promptLength - $0.count }
                        let tokens = stacked(
                            tokenRows.map { row in
                                MLXArray(
                                    Array(repeating: paddingToken, count: promptLength - row.count) + row
                                )
                            }
                        )
                        var generateParameters = firstRequest.generateParameters
                        generateParameters.leftPadding = leftPadding.contains(where: { $0 > 0 }) ? leftPadding : nil
                        let cache = context.model.newCache(parameters: generateParameters)
                        let sampler = firstRequest.generateParameters.sampler()
                        let maxTokens = firstRequest.generateParameters.maxTokens ?? 160
                        let prefillStepSize = max(firstRequest.generateParameters.prefillStepSize, 1)
                        let eosTokenID = context.tokenizer.eosTokenId
                        var generatedTokens = Array(repeating: [Int](), count: group.count)
                        var finished = Array(repeating: false, count: group.count)
                        var chunkStart = 0
                        var logits: MLXArray?

                        while chunkStart < promptLength {
                            let chunkEnd = min(chunkStart + prefillStepSize, promptLength)
                            logits = context.model(
                                .init(tokens: tokens[0..., chunkStart ..< chunkEnd]),
                                cache: cache,
                                state: nil
                            ).logits
                            if chunkEnd < promptLength {
                                eval(cache)
                            }
                            chunkStart = chunkEnd
                        }

                        guard var nextToken = logits.map({ sampler.sample(logits: $0[0..., -1, 0...]) }) else {
                            continue
                        }
                        eval(nextToken)

                        for _ in 0 ..< maxTokens {
                            let tokenValues = nextToken.asArray(Int.self)
                            tokenValues.enumerated().forEach { rowIndex, tokenID in
                                guard !finished[rowIndex] else {
                                    return
                                }

                                if tokenID == eosTokenID {
                                    finished[rowIndex] = true
                                } else {
                                    generatedTokens[rowIndex].append(tokenID)
                                }
                            }

                            guard finished.contains(false) else {
                                break
                            }

                            let nextInputTokens = tokenValues.enumerated().map { rowIndex, tokenID in
                                if finished[rowIndex], let eosTokenID {
                                    return eosTokenID
                                }

                                return tokenID
                            }
                            nextToken = sampler.sample(
                                logits: context.model(
                                    .init(tokens: MLXArray(nextInputTokens)[0..., .newAxis]),
                                    cache: cache,
                                    state: nil
                                ).logits[0..., -1, 0...]
                            )
                            eval(nextToken)
                        }

                        zip(group, generatedTokens).forEach { item, tokenIDs in
                            responses[item.index] = context.tokenizer.decode(
                                tokenIds: tokenIDs,
                                skipSpecialTokens: true
                            )
                        }
                    }

                    return responses
                }
                Memory.clearCache()
                endModelUse(model)
                return responses
            } catch {
                endModelUse(model)
                throw error
            }
        }
    }

    private func respondVisualBatch(
        requests: [ModelVisualRequest],
        telemetryMetadata: [String: String]
    ) async throws -> [String] {
        guard let firstRequest = requests.first else {
            return []
        }

        let signature = [
            firstRequest.prompt,
            firstRequest.instructions,
            String(reflecting: AIGenerateParametersSignature(firstRequest.generateParameters)),
            firstRequest.additionalContext?.keys.sorted().map { key in
                let value = firstRequest.additionalContext?[key].map { String(reflecting: $0) } ?? "<nil>"
                return "\(key)=\(value)"
            }
            .joined(separator: "|") ?? "<nil>"
        ]
        .joined(separator: "|")
        precondition(
            requests.allSatisfy { request in
                [
                    request.prompt,
                    request.instructions,
                    String(reflecting: AIGenerateParametersSignature(request.generateParameters)),
                    request.additionalContext?.keys.sorted().map { key in
                        let value = request.additionalContext?[key].map { String(reflecting: $0) } ?? "<nil>"
                        return "\(key)=\(value)"
                    }
                    .joined(separator: "|") ?? "<nil>"
                ]
                .joined(separator: "|") == signature
            },
            "Visual batch requests must share prompt, instructions, generation parameters, and additional context."
        )

        return try await withTrackedOperation {
            beginModelUse(.visual)
            let modelTask = cachedChatModelTask(for: .visual)

            do {
                let responses: [String] = try await modelTask.value.perform { context in
                    struct PreparedVisualRequest {
                        let index: Int
                        let input: LMInput
                    }

                    struct PreparedVisualGroupKey: Hashable {
                        let tokenLength: Int
                        let maskShape: [Int]
                        let imageShapeAfterBatchAxis: [Int]
                        let imageFrames: String
                        let videoShapeAfterBatchAxis: [Int]
                        let videoFrames: String
                    }

                    var prepared: [PreparedVisualRequest] = []
                    prepared.reserveCapacity(requests.count)
                    for (index, request) in requests.enumerated() {
                        let image = try AIImageDataDecoder.image(from: request.imageData)
                        let messages: [Chat.Message] = {
                            let userMessage = Chat.Message.user(
                                request.prompt,
                                images: [.ciImage(image)]
                            )

                            guard !request.instructions.isEmpty else {
                                return [userMessage]
                            }

                            return [
                                .system(request.instructions),
                                userMessage
                            ]
                        }()
                        let input = try await context.processor.prepare(
                            input: UserInput(
                                chat: messages,
                                processing: .init(resize: CGSize(width: 512, height: 512)),
                                additionalContext: request.additionalContext
                            )
                        )

                        prepared.append(PreparedVisualRequest(index: index, input: input))
                    }
                    let keyForInput: (LMInput) -> PreparedVisualGroupKey = { input in
                        let imageShape = input.image?.pixels.shape ?? []
                        let videoShape = input.video?.pixels.shape ?? []
                        let imageFrames = input.image?.frames?.map { "\($0.t)x\($0.h)x\($0.w)" }.joined(separator: ",") ?? "<nil>"
                        let videoFrames = input.video?.frames?.map { "\($0.t)x\($0.h)x\($0.w)" }.joined(separator: ",") ?? "<nil>"

                        return PreparedVisualGroupKey(
                            tokenLength: input.text.tokens.dim(1),
                            maskShape: input.text.mask?.shape ?? [],
                            imageShapeAfterBatchAxis: Array(imageShape.dropFirst()),
                            imageFrames: imageFrames,
                            videoShapeAfterBatchAxis: Array(videoShape.dropFirst()),
                            videoFrames: videoFrames
                        )
                    }
                    let preparedByShape = Dictionary(grouping: prepared) {
                        keyForInput($0.input)
                    }
                    var responses = Array(repeating: "", count: requests.count)

                    for group in preparedByShape.values {
                        let textTokens = concatenated(group.map(\.input.text.tokens), axis: 0)
                        let textMasks = group.compactMap(\.input.text.mask)
                        let mask = textMasks.count == group.count
                            ? concatenated(textMasks, axis: 0)
                            : nil
                        let imageInputs = group.compactMap(\.input.image)
                        let imageFrames = imageInputs.flatMap { $0.frames ?? [] }
                        let image = imageInputs.isEmpty
                            ? nil
                            : LMInput.ProcessedImage(
                                pixels: concatenated(imageInputs.map(\.pixels), axis: 0),
                                frames: imageFrames.isEmpty ? nil : imageFrames
                            )
                        let videoInputs = group.compactMap(\.input.video)
                        let videoFrames = videoInputs.flatMap { $0.frames ?? [] }
                        let video = videoInputs.isEmpty
                            ? nil
                            : LMInput.ProcessedVideo(
                                pixels: concatenated(videoInputs.map(\.pixels), axis: 0),
                                frames: videoFrames.isEmpty ? nil : videoFrames
                            )
                        let input = LMInput(
                            text: .init(tokens: textTokens, mask: mask),
                            image: image,
                            video: video
                        )
                        let cache = context.model.newCache(parameters: firstRequest.generateParameters)
                        let sampler = firstRequest.generateParameters.sampler()
                        let maxTokens = firstRequest.generateParameters.maxTokens ?? 160
                        let prefillStepSize = max(firstRequest.generateParameters.prefillStepSize, 1)
                        var state: LMOutput.State?
                        let initialLogits: MLXArray

                        switch try context.model.prepare(input, cache: cache, windowSize: prefillStepSize) {
                        case .logits(let result):
                            state = result.state
                            initialLogits = result.logits

                        case .tokens(let tokens):
                            var chunkStart = 0
                            var logits: MLXArray?
                            let promptLength = tokens.tokens.dim(1)

                            while chunkStart < promptLength {
                                let chunkEnd = min(chunkStart + prefillStepSize, promptLength)
                                let output = context.model(
                                    .init(tokens: tokens.tokens[0..., chunkStart ..< chunkEnd]),
                                    cache: cache,
                                    state: state
                                )
                                state = output.state
                                logits = output.logits
                                if chunkEnd < promptLength {
                                    eval(cache)
                                }
                                chunkStart = chunkEnd
                            }

                            guard let logits else {
                                continue
                            }
                            initialLogits = logits
                        }

                        var nextToken = sampler.sample(logits: initialLogits[0..., -1, 0...])
                        eval(nextToken)

                        var generatedTokens = Array(repeating: [Int](), count: group.count)
                        var finished = Array(repeating: false, count: group.count)
                        let eosTokenID = context.tokenizer.eosTokenId

                        for _ in 0 ..< maxTokens {
                            let tokenValues = nextToken.asArray(Int.self)
                            tokenValues.enumerated().forEach { rowIndex, tokenID in
                                guard !finished[rowIndex] else {
                                    return
                                }

                                if tokenID == eosTokenID {
                                    finished[rowIndex] = true
                                } else {
                                    generatedTokens[rowIndex].append(tokenID)
                                }
                            }

                            guard finished.contains(false) else {
                                break
                            }

                            let nextInputTokens = tokenValues.enumerated().map { rowIndex, tokenID in
                                if finished[rowIndex], let eosTokenID {
                                    return eosTokenID
                                }

                                return tokenID
                            }
                            let output = context.model(
                                .init(tokens: MLXArray(nextInputTokens)[0..., .newAxis]),
                                cache: cache,
                                state: state
                            )
                            state = output.state
                            nextToken = sampler.sample(logits: output.logits[0..., -1, 0...])
                            eval(nextToken)
                        }

                        zip(group, generatedTokens).forEach { item, tokenIDs in
                            responses[item.index] = context.tokenizer.decode(
                                tokenIds: tokenIDs,
                                skipSpecialTokens: true
                            )
                        }
                    }

                    return responses
                }
                Memory.clearCache()
                endModelUse(.visual)
                return responses
            } catch {
                endModelUse(.visual)
                throw error
            }
        }
    }

    private func runStream(
        id: UUID,
        model: AIModel,
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?,
        telemetryMetadata: [String: String],
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        defer {
            Task {
                self.removeStreamTask(id: id)
            }
        }

        do {
            try await withChatSession(
                model: model,
                instructions: instructions,
                generateParameters: generateParameters,
                additionalContext: additionalContext,
                telemetryMetadata: telemetryMetadata
            ) { session in
                for try await chunk in session.streamResponse(to: prompt) {
                    if case .terminated = continuation.yield(chunk) {
                        break
                    }
                }

                continuation.finish()
            }
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func withChatSession<R>(
        model: AIModel,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?,
        telemetryMetadata: [String: String],
        _ body: (ChatSession) async throws -> R
    ) async throws -> R {
        try await withTrackedOperation {
            beginModelUse(model)
            let modelTask = cachedChatModelTask(for: model)

            do {
                let modelContainer = try await modelTask.value
                let session = ChatSession(
                    modelContainer,
                    instructions: instructions,
                    generateParameters: generateParameters,
                    additionalContext: additionalContext
                )
                let result = try await body(session)
                await session.clear()
                await session.synchronize()
                Memory.clearCache()
                endModelUse(model)
                return result
            } catch {
                endModelUse(model)
                throw error
            }
        }
    }

    private func withTrackedOperation<R>(
        _ body: () async throws -> R
    ) async throws -> R {
        guard !isShuttingDown else {
            throw CancellationError()
        }

        activeOperationCount += 1

        do {
            let result = try await body()
            endOperation()
            return result
        } catch {
            endOperation()
            throw error
        }
    }

    private func endOperation() {
        activeOperationCount = max(activeOperationCount - 1, 0)
        resumeShutdownContinuationsIfNeeded()
    }

    private func removeStreamTask(id: UUID) {
        streamTaskByID.removeValue(forKey: id)
        resumeShutdownContinuationsIfNeeded()
    }

    private func beginModelUse(_ model: AIModel) {
        activeModelUseCount[model, default: 0] += 1
        unloadTasks[model]?.cancel()
        unloadTasks[model] = nil
    }

    private func endModelUse(_ model: AIModel) {
        activeModelUseCount[model] = max((activeModelUseCount[model] ?? 1) - 1, 0)
        scheduleIdleUnloadIfNeeded(for: model)
    }

    private func scheduleIdleUnloadIfNeeded(for model: AIModel) {
        guard !isShuttingDown,
              (activeModelUseCount[model] ?? 0) == 0,
              model != .textSmall,
              model != .textBig,
              model != .reranker else {
            return
        }

        unloadTasks[model]?.cancel()
        unloadTasks[model] = Task {
            try? await Task.sleep(for: .seconds(60))
            self.unloadModelIfIdle(model)
        }
    }

    private func unloadModelIfIdle(_ model: AIModel) {
        guard !isShuttingDown,
              (activeModelUseCount[model] ?? 0) == 0 else {
            return
        }

        chatModelTasks.removeValue(forKey: model)
        embeddingModelTasks.removeValue(forKey: model)
        unloadTasks.removeValue(forKey: model)
        Memory.clearCache()
    }

    private func cachedChatModelTask(
        for model: AIModel
    ) -> Task<MLXLMCommon.ModelContainer, Error> {
        if let existing = chatModelTasks[model] {
            return existing
        }

        let task = Task(priority: .userInitiated) {
            guard let directory = model.directory() else {
                throw ActivityAIError.missingLocalModel(model.directoryName)
            }

            switch model.family {
            case .chatLLM, .reranker:
                return try await LLMModelFactory.shared.loadContainer(
                    from: directory,
                    using: AISchedulerTokenizerLoader()
                )
            case .chatVLM:
                return try await VLMModelFactory.shared.loadContainer(
                    from: directory,
                    using: AISchedulerTokenizerLoader()
                )
            case .embedding, .activityUMAP:
                preconditionFailure("cachedChatModelTask does not support \(model)")
            }
        }
        chatModelTasks[model] = task
        return task
    }

    private func cachedEmbeddingModelTask(
        for model: AIModel
    ) -> Task<MLXEmbedders.EmbedderModelContainer, Error> {
        if let existing = embeddingModelTasks[model] {
            return existing
        }

        let task = Task(priority: .userInitiated) {
            guard let directory = model.directory() else {
                throw ActivityAIError.missingLocalModel(model.directoryName)
            }

            return try await EmbedderModelFactory.shared.loadContainer(
                from: directory,
                using: AISchedulerTokenizerLoader()
            )
        }
        embeddingModelTasks[model] = task
        return task
    }

    private func resumeShutdownContinuationsIfNeeded() {
        guard isShuttingDown,
              activeOperationCount == 0,
              streamTaskByID.isEmpty else {
            return
        }

        let continuations = shutdownContinuations
        shutdownContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}
