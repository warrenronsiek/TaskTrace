//
//  AIRecursivePromptReducer.swift
//  TaskTrace
//

import Foundation
import MLXLMCommon

enum AIRecursivePromptReducerError: Error, CustomStringConvertible {
    case promptExceedsBudget(source: String, estimatedTokens: Int, hardTokenLimit: Int)
    case exceededMaximumDepth(source: String, depth: Int)

    var description: String {
        switch self {
        case .promptExceedsBudget(let source, let estimatedTokens, let hardTokenLimit):
            "Prompt for \(source) estimated \(estimatedTokens) tokens, exceeding limit \(hardTokenLimit)."
        case .exceededMaximumDepth(let source, let depth):
            "Recursive prompt reduction for \(source) exceeded maximum depth \(depth)."
        }
    }
}

enum AIRecursivePromptReducer {
    nonisolated static let hardTokenLimit = 8_000
    nonisolated static let packingTokenLimit = 7_500
    nonisolated static let defaultTokenBudget = TokenBudget(
        hardTokenLimit: hardTokenLimit,
        packingTokenLimit: packingTokenLimit
    )
    nonisolated static let knowledgeSummaryTokenBudget = TokenBudget(
        hardTokenLimit: 4_000,
        packingTokenLimit: 3_500
    )
    nonisolated static let maximumDepth = 8

    nonisolated struct TokenBudget: Sendable, Equatable {
        let hardTokenLimit: Int
        let packingTokenLimit: Int
    }

    nonisolated enum Stage: Sendable {
        case chunk(depth: Int, index: Int, count: Int)
        case final(depth: Int)
    }

    nonisolated struct RequestTemplate: Sendable {
        let source: String
        let priority: AIExecutionPriority
        let instructions: String
        let generateParameters: GenerateParameters
        let additionalContext: [String: any Sendable]?
        let metadata: [String: String]

        init(
            source: String,
            priority: AIExecutionPriority,
            instructions: String,
            generateParameters: GenerateParameters,
            additionalContext: [String: any Sendable]? = nil,
            metadata: [String: String] = [:]
        ) {
            self.source = source
            self.priority = priority
            self.instructions = instructions
            self.generateParameters = generateParameters
            self.additionalContext = additionalContext
            self.metadata = metadata
        }
    }

    nonisolated struct ReductionState: Sendable {
        let operationID: UUID
        let source: String
        let priority: AIExecutionPriority
        let finalPromptHeader: String
        let finalInstructions: String
        let finalGenerateParameters: GenerateParameters
        let chunkPromptHeader: String
        let chunkInstructions: String
        let chunkGenerateParameters: GenerateParameters
        let additionalContext: [String: any Sendable]?
        let metadata: [String: String]
        let tokenBudget: TokenBudget
        var evidenceItems: [String]
        var depth: Int
        var chunkedEvidence: [[String]]
        var partialSummaries: [String]
        var nextChunkIndex: Int
        var inFlightStage: Stage?

        init(
            operationID: UUID = UUID(),
            source: String,
            priority: AIExecutionPriority,
            evidenceItems: [String],
            finalPromptHeader: String,
            finalInstructions: String,
            finalGenerateParameters: GenerateParameters,
            chunkPromptHeader: String,
            chunkInstructions: String,
            chunkGenerateParameters: GenerateParameters,
            additionalContext: [String: any Sendable]? = nil,
            metadata: [String: String] = [:],
            tokenBudget: TokenBudget = AIRecursivePromptReducer.defaultTokenBudget,
            depth: Int = 0
        ) {
            self.operationID = operationID
            self.source = source
            self.priority = priority
            self.evidenceItems = evidenceItems
            self.finalPromptHeader = finalPromptHeader
            self.finalInstructions = finalInstructions
            self.finalGenerateParameters = finalGenerateParameters
            self.chunkPromptHeader = chunkPromptHeader
            self.chunkInstructions = chunkInstructions
            self.chunkGenerateParameters = chunkGenerateParameters
            self.additionalContext = additionalContext
            self.metadata = metadata
            self.tokenBudget = tokenBudget
            self.depth = depth
            self.chunkedEvidence = []
            self.partialSummaries = []
            self.nextChunkIndex = 0
            self.inFlightStage = nil
        }

        mutating func nextRequest() throws -> (request: ModelTextRequest, stage: Stage) {
            while true {
                let finalPrompt = AIRecursivePromptReducer.renderPrompt(
                    header: finalPromptHeader,
                    evidenceItems: evidenceItems
                )

                if AIRecursivePromptReducer.fitsHardLimit(
                    prompt: finalPrompt,
                    instructions: finalInstructions,
                    tokenBudget: tokenBudget
                ) {
                    let stage = Stage.final(depth: depth)
                    let request = try AIRecursivePromptReducer.makeRequest(
                        source: source,
                        priority: priority,
                        prompt: finalPrompt,
                        instructions: finalInstructions,
                        generateParameters: finalGenerateParameters,
                        additionalContext: additionalContext,
                        metadata: metadata.merging([
                            "event_kind": source,
                            "reduce_id": operationID.uuidString,
                            "reduce_stage": "final",
                            "reduce_depth": "\(depth)"
                        ]) { _, new in new },
                        tokenBudget: tokenBudget
                    )
                    inFlightStage = stage
                    return (request, stage)
                }

                guard depth < AIRecursivePromptReducer.maximumDepth else {
                    throw AIRecursivePromptReducerError.exceededMaximumDepth(
                        source: source,
                        depth: depth
                    )
                }

                if chunkedEvidence.isEmpty {
                    chunkedEvidence = AIRecursivePromptReducer.packedEvidenceItems(
                        evidenceItems,
                        promptHeader: chunkPromptHeader,
                        instructions: chunkInstructions,
                        tokenBudget: tokenBudget
                    )
                    partialSummaries = []
                    nextChunkIndex = 0
                }

                if nextChunkIndex < chunkedEvidence.count {
                    let chunkIndex = nextChunkIndex
                    let stage = Stage.chunk(
                        depth: depth,
                        index: chunkIndex,
                        count: chunkedEvidence.count
                    )
                    let prompt = AIRecursivePromptReducer.renderPrompt(
                        header: "\(chunkPromptHeader)\n\nChunk \(chunkIndex + 1) of \(chunkedEvidence.count).",
                        evidenceItems: chunkedEvidence[chunkIndex]
                    )
                    let request = try AIRecursivePromptReducer.makeRequest(
                        source: source,
                        priority: priority,
                        prompt: prompt,
                        instructions: chunkInstructions,
                        generateParameters: chunkGenerateParameters,
                        additionalContext: additionalContext,
                        metadata: metadata.merging([
                            "event_kind": source,
                            "reduce_id": operationID.uuidString,
                            "reduce_stage": "chunk",
                            "reduce_depth": "\(depth)",
                            "chunk_index": "\(chunkIndex)",
                            "chunk_count": "\(chunkedEvidence.count)"
                        ]) { _, new in new },
                        tokenBudget: tokenBudget
                    )
                    nextChunkIndex += 1
                    inFlightStage = stage
                    return (request, stage)
                }

                evidenceItems = partialSummaries
                chunkedEvidence = []
                partialSummaries = []
                nextChunkIndex = 0
                depth += 1
            }
        }

        mutating func acceptChunkResponse(_ rawResponse: String) {
            let response = AITextUtilities
                .strippingThinkingBlocks(from: rawResponse)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !response.isEmpty {
                partialSummaries.append(
                    "Partial Summary \(partialSummaries.count + 1):\n\(response)"
                )
            }

            inFlightStage = nil
        }

        mutating func acceptFinalResponse() {
            inFlightStage = nil
        }
    }

    nonisolated static func promptTokenEstimate(
        prompt: String,
        instructions: String
    ) -> Int {
        AITextSchedulerPolicy.tokenEstimate(for: prompt)
            + AITextSchedulerPolicy.tokenEstimate(for: instructions)
    }

    nonisolated static func fitsHardLimit(
        prompt: String,
        instructions: String,
        tokenBudget: TokenBudget = defaultTokenBudget
    ) -> Bool {
        promptTokenEstimate(prompt: prompt, instructions: instructions) <= tokenBudget.hardTokenLimit
    }

    nonisolated static func makeRequest(
        source: String,
        priority: AIExecutionPriority,
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]? = nil,
        tokenBudget: TokenBudget = defaultTokenBudget
    ) throws -> ModelTextRequest {
        try makeRequest(
            source: source,
            priority: priority,
            prompt: prompt,
            instructions: instructions,
            generateParameters: generateParameters,
            additionalContext: additionalContext,
            metadata: ["event_kind": source],
            tokenBudget: tokenBudget
        )
    }

    nonisolated static func makeRequest(
        source: String,
        priority: AIExecutionPriority,
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]? = nil,
        metadata: [String: String],
        tokenBudget: TokenBudget = defaultTokenBudget
    ) throws -> ModelTextRequest {
        let estimatedTokens = promptTokenEstimate(prompt: prompt, instructions: instructions)

        guard estimatedTokens <= tokenBudget.hardTokenLimit else {
            throw AIRecursivePromptReducerError.promptExceedsBudget(
                source: source,
                estimatedTokens: estimatedTokens,
                hardTokenLimit: tokenBudget.hardTokenLimit
            )
        }

        return ModelTextRequest(
            source: source,
            priority: priority,
            prompt: prompt,
            instructions: instructions,
            generateParameters: generateParameters,
            additionalContext: additionalContext,
            promptTokenEstimate: estimatedTokens,
            metadata: metadata
        )
    }

    nonisolated static func renderPrompt(
        header: String,
        evidenceItems: [String]
    ) -> String {
        ([header.trimmingCharacters(in: .whitespacesAndNewlines), ""] + evidenceItems.enumerated().map {
            "### Evidence \($0.offset + 1)\n\($0.element.trimmingCharacters(in: .whitespacesAndNewlines))"
        })
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func packedEvidenceItems(
        _ evidenceItems: [String],
        promptHeader: String,
        instructions: String,
        tokenBudget: TokenBudget = defaultTokenBudget
    ) -> [[String]] {
        evidenceItems
            .flatMap {
                splitOversizedEvidenceItem(
                    $0,
                    promptHeader: promptHeader,
                    instructions: instructions,
                    tokenBudget: tokenBudget
                )
            }
            .reduce(into: [[String]]()) { chunks, item in
                guard let lastChunk = chunks.last else {
                    chunks.append([item])
                    return
                }

                let candidate = lastChunk + [item]
                let prompt = renderPrompt(
                    header: promptHeader,
                    evidenceItems: candidate
                )

                if promptTokenEstimate(prompt: prompt, instructions: instructions) <= tokenBudget.packingTokenLimit {
                    chunks[chunks.count - 1] = candidate
                } else {
                    chunks.append([item])
                }
            }
    }

    private nonisolated static func splitOversizedEvidenceItem(
        _ evidenceItem: String,
        promptHeader: String,
        instructions: String,
        tokenBudget: TokenBudget
    ) -> [String] {
        let trimmed = evidenceItem.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = renderPrompt(header: promptHeader, evidenceItems: [trimmed])

        guard promptTokenEstimate(prompt: prompt, instructions: instructions) > tokenBudget.packingTokenLimit else {
            return [trimmed]
        }

        let linePieces = trimmed
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        let pieces = linePieces.count > 1
            ? linePieces
            : budgetedTextSegments(
                trimmed,
                promptHeader: promptHeader,
                instructions: instructions,
                tokenBudget: tokenBudget
            )

        return pieces
            .flatMap { piece in
                let segment = "Segment from oversized evidence item:\n\(piece)"
                let segmentPrompt = renderPrompt(header: promptHeader, evidenceItems: [segment])

                guard promptTokenEstimate(prompt: segmentPrompt, instructions: instructions) > tokenBudget.packingTokenLimit else {
                    return [segment]
                }

                return budgetedTextSegments(
                    piece,
                    promptHeader: promptHeader,
                    instructions: instructions,
                    tokenBudget: tokenBudget
                )
                .map {
                    "Segment from oversized evidence item:\n\($0)"
                }
            }
    }

    private nonisolated static func budgetedTextSegments(
        _ value: String,
        promptHeader: String,
        instructions: String,
        tokenBudget: TokenBudget
    ) -> [String] {
        let segmentPrefix = "Segment from oversized evidence item:\n"
        let fixedPrompt = renderPrompt(header: promptHeader, evidenceItems: [segmentPrefix])
        let segmentTokenBudget = max(
            tokenBudget.packingTokenLimit - promptTokenEstimate(prompt: fixedPrompt, instructions: instructions),
            1
        )
        let words = value
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard words.count > 1 else {
            return hardCharacterChunks(value, maxCharacters: max(segmentTokenBudget * 4, 1))
        }

        let wordLimit = max(segmentTokenBudget * 3 / 4, 1)
        let characterLimit = max(segmentTokenBudget * 4, 1)
        var segments: [String] = []
        var currentWords: [String] = []
        var currentCharacterCount = 0

        for word in words {
            let separatorCount = currentWords.isEmpty ? 0 : 1
            let candidateCharacterCount = currentCharacterCount + separatorCount + word.count

            if !currentWords.isEmpty,
               currentWords.count + 1 > wordLimit || candidateCharacterCount > characterLimit {
                segments.append(currentWords.joined(separator: " "))
                currentWords = []
                currentCharacterCount = 0
            }

            if word.count > characterLimit {
                segments.append(contentsOf: hardCharacterChunks(word, maxCharacters: characterLimit))
            } else {
                currentWords.append(word)
                currentCharacterCount += (currentWords.count == 1 ? 0 : 1) + word.count
            }
        }

        if !currentWords.isEmpty {
            segments.append(currentWords.joined(separator: " "))
        }

        return segments
    }

    private nonisolated static func hardCharacterChunks(
        _ value: String,
        maxCharacters: Int
    ) -> [String] {
        guard value.count > maxCharacters else {
            return [value]
        }

        var chunks: [String] = []
        var startIndex = value.startIndex

        while startIndex < value.endIndex {
            let endIndex = value.index(
                startIndex,
                offsetBy: maxCharacters,
                limitedBy: value.endIndex
            ) ?? value.endIndex
            chunks.append(String(value[startIndex..<endIndex]))
            startIndex = endIndex
        }

        return chunks
    }
}
