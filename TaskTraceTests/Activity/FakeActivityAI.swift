//
//  FakeActivityAI.swift
//  TaskTraceTests
//
//  Created by Codex on 3/13/26.
//

import Foundation
import MLXLMCommon
@testable import TaskTrace

@MainActor final class FakeActivityAI: ActivityAIOperating, ActivityEmbeddingGenerating, AITextResponding, @unchecked Sendable {
    nonisolated init() {}

    var overviewMergeDecision = ActivityOverviewMergeDecision(
        title: "Merged Overview",
        summary: "Merged overview summary."
    )
    var rerankingScoresByDocument: [String: Float] = [:]
    var streamedResponseChunks: [String] = ["Stub streamed response."]
    var rerankingDelayNanoseconds: UInt64 = 0
    var searchSummaryWarmupCallCount = 0
    var skillProcedureCallCount = 0
    var skillProcedurePrompts: [String] = []

    func setOverviewMergeDecision(_ value: ActivityOverviewMergeDecision) {
        overviewMergeDecision = value
    }

    func setRerankingScoresByDocument(_ value: [String: Float]) {
        rerankingScoresByDocument = value
    }

    func setStreamedResponseChunks(_ value: [String]) {
        streamedResponseChunks = value
    }

    func setRerankingDelayNanoseconds(_ value: UInt64) {
        rerankingDelayNanoseconds = value
    }

    func currentSearchSummaryWarmupCallCount() -> Int {
        searchSummaryWarmupCallCount
    }

    func currentSkillProcedureCallCount() -> Int {
        skillProcedureCallCount
    }

    func describeImage(_ image: Data) async -> String {
        "desc-\(image.count)"
    }

    func ocrImage(_ image: Data) async -> String {
        "ocr-\(image.count)"
    }

    func summarizeScreenshot(description: String, text: String) async -> String {
        [text, description]
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    func summarizeActivity(_ activity: ActivityActor.Activity) async -> String {
        activity.screenshots
            .compactMap(\.summary)
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
    }

    func mergeOverviews(
        _ firstOverview: ActivityOverviewMergeOption,
        _ secondOverview: ActivityOverviewMergeOption
    ) async throws -> ActivityOverviewMergeDecision {
        overviewMergeDecision
    }

    func generateVectors(for texts: [String], promptPrefix: String?) async -> [[Float]] {
        texts.map { text in
            let base = AITextUtilities.prefixedText(text, promptPrefix: promptPrefix)
            return Array(
                repeating: Float(base.count),
                count: TaskTraceDatabaseBootstrap.activityEmbeddingDimension
            )
        }
    }

    func generateRerankings(
        query: String,
        documents: [String],
        instruction: String
    ) async -> [ActivityAIReranking] {
        if rerankingDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: rerankingDelayNanoseconds)
        }

        return documents.enumerated().map { index, document in
            ActivityAIReranking(
                documentIndex: index,
                score: rerankingScoresByDocument[document] ?? Float(query.count + instruction.count + document.count)
            )
        }
        .sorted { $0.score > $1.score }
    }

    func warmSearchSummaryModel(traceStartedAt: Date?) async {
        searchSummaryWarmupCallCount += 1
    }

    func streamResponse(
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        let chunks = streamedResponseChunks

        return AsyncThrowingStream { continuation in
            Task {
                chunks.forEach { chunk in
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    func searchSummary(
        query: String,
        rankedDocuments: [String],
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        await streamResponse(
            prompt: ActivityTextGenerationActor.searchSummaryPrompt(
                query: query,
                rankedDocuments: rankedDocuments
            ),
            instructions: "",
            generateParameters: GenerateParameters(),
            traceStartedAt: traceStartedAt
        )
    }

    func skillProcedure(
        prompt: String,
        instructions: String,
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        skillProcedureCallCount += 1
        skillProcedurePrompts.append(prompt)
        return await streamResponse(
            prompt: prompt,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: Vars.skillProcedureMaxTokens, temperature: 0.2),
            traceStartedAt: traceStartedAt
        )
    }

    func respond(
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?
    ) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackSummary = trimmedPrompt.isEmpty ? "Generated overview summary." : trimmedPrompt

        return """
        Title: Generated Overview
        Summary: \(fallbackSummary)
        """
    }
}
