//
//  AIModels.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation
import MLXLMCommon

nonisolated enum AIExecutionPriority: Int, CaseIterable, Sendable {
    case streaming = 0
    case interactive = 1
    case background = 2

    nonisolated var displayName: String {
        switch self {
        case .streaming:
            "Streaming"
        case .interactive:
            "Interactive"
        case .background:
            "Background"
        }
    }

    nonisolated static var admissionOrder: [AIExecutionPriority] {
        [.streaming, .interactive, .background]
    }
}

nonisolated struct ActivityOverviewMergeOption: Equatable, Sendable {
    let title: String
    let summary: String
    let durationSeconds: Int
}

nonisolated struct ActivityOverviewMergeDecision: Equatable, Sendable {
    let title: String?
    let summary: String?
}

nonisolated struct ActivityAIReranking: Equatable, Sendable {
    let documentIndex: Int
    let score: Float
}

enum ActivityAIError: Error, Equatable {
    case emptyOverviewMergeDecision
    case missingLocalModel(String)
}

protocol ActivityImageDescribing: Sendable {
    func describeImage(_ image: Data) async -> String
}

protocol ActivityScreenshotTextRecognizing: Sendable {
    func ocrImage(_ image: Data) async -> String
}

protocol ActivitySummarizing: Sendable {
    func summarizeActivity(_ activity: ActivityActor.Activity) async -> String
}

protocol ActivityScreenshotSummarizing: Sendable {
    func summarizeScreenshot(description: String, text: String) async -> String
}

protocol OverviewMerging: Sendable {
    func mergeOverviews(
        _ firstOverview: ActivityOverviewMergeOption,
        _ secondOverview: ActivityOverviewMergeOption
    ) async throws -> ActivityOverviewMergeDecision
}

protocol ActivityEmbeddingGenerating: Sendable {
    func generateVectors(for texts: [String], promptPrefix: String?) async -> [[Float]]
    func generateVectors(for texts: [String], promptPrefix: String?, source: String) async -> [[Float]]
}

protocol AITextResponding: Sendable {
    func respond(
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?
    ) async throws -> String
    func respond(
        prompts: [String],
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?
    ) async throws -> [String]
    func respond(
        source: String,
        priority: AIExecutionPriority,
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?
    ) async throws -> String
    func respond(
        source: String,
        priority: AIExecutionPriority,
        prompts: [String],
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?
    ) async throws -> [String]
}

protocol ActivityRerankingGenerating: Sendable {
    func generateRerankings(
        query: String,
        documents: [String],
        instruction: String
    ) async -> [ActivityAIReranking]
    func generateRerankings(
        query: String,
        documents: [String],
        instruction: String,
        source: String
    ) async -> [ActivityAIReranking]
}

extension ActivityEmbeddingGenerating {
    func generateVectors(for texts: [String], promptPrefix: String?, source: String) async -> [[Float]] {
        await generateVectors(for: texts, promptPrefix: promptPrefix)
    }
}

extension AITextResponding {
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
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?
    ) async throws -> String {
        try await respond(
            prompt: prompt,
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
        additionalContext: [String: any Sendable]?
    ) async throws -> [String] {
        var responses: [String] = []

        for prompt in prompts {
            responses.append(
                try await respond(
                    source: source,
                    priority: priority,
                    prompt: prompt,
                    instructions: instructions,
                    generateParameters: generateParameters,
                    additionalContext: additionalContext
                )
            )
        }

        return responses
    }
}

extension ActivityRerankingGenerating {
    func generateRerankings(
        query: String,
        documents: [String],
        instruction: String,
        source: String
    ) async -> [ActivityAIReranking] {
        await generateRerankings(
            query: query,
            documents: documents,
            instruction: instruction
        )
    }
}

protocol ActivityTextStreamingGenerating: Sendable {
    func streamResponse(
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error>
}

protocol SearchSummaryGenerating: Sendable {
    func warmSearchSummaryModel(traceStartedAt: Date?) async
    func searchSummary(
        query: String,
        rankedDocuments: [String],
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error>
}

protocol SkillProcedureGenerating: Sendable {
    func skillProcedure(
        prompt: String,
        instructions: String,
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error>
}

protocol ActivityAIOperating:
    ActivityImageDescribing,
    ActivityScreenshotTextRecognizing,
    ActivityScreenshotSummarizing,
    ActivitySummarizing,
    OverviewMerging,
    ActivityRerankingGenerating,
    ActivityTextStreamingGenerating,
    SearchSummaryGenerating,
    SkillProcedureGenerating,
    Sendable {}
