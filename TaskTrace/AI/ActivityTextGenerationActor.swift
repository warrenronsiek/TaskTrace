//
//  ActivityTextGenerationActor.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation
import MLXLMCommon
import OSLog

actor ActivityTextGenerationActor: Receiver, ActivityTextStreamingGenerating, SearchSummaryGenerating, SkillProcedureGenerating {
    nonisolated static let searchSummaryInstructions =
        """
        You are summarizing search results from a desktop activity retrieval system.
        Use only the provided ranked summaries and descriptions.
        Synthesize the most relevant work, entities, and tasks related to the query.
        Prefer concrete details over generic phrasing.
        If the context is mixed or weak, say so briefly.
        Start directly with the work or answer. Do not begin with phrases like "The user was" or similar lead-ins.
        """

    private let textGenerator: any ActivityTextStreamingGenerating & SearchSummaryGenerating & SkillProcedureGenerating = AISchedulerClient.shared
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    func receive(_ envelope: Envelope) async {}

    func streamResponse(
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        await textGenerator.streamResponse(
            prompt: prompt,
            instructions: instructions,
            generateParameters: generateParameters,
            traceStartedAt: traceStartedAt
        )
    }

    func warmSearchSummaryModel(traceStartedAt: Date?) async {
        await textGenerator.warmSearchSummaryModel(traceStartedAt: traceStartedAt)
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

        return await textGenerator.searchSummary(
            query: query,
            rankedDocuments: cleanedDocuments,
            traceStartedAt: traceStartedAt
        )
    }

    func skillProcedure(
        prompt: String,
        instructions: String,
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        await textGenerator.skillProcedure(
            prompt: prompt,
            instructions: instructions,
            traceStartedAt: traceStartedAt
        )
    }

    nonisolated static func searchSummaryPrompt(
        query: String,
        rankedDocuments: [String]
    ) -> String {
        let renderedDocuments = rankedDocuments.enumerated().map { index, document in
            """
            <result rank="\(index + 1)">
            \(AITextUtilities.xmlEscaped(document))
            </result>
            """
        }.joined(separator: "\n")

        return """
        <search_summary_request>
        <query>\(AITextUtilities.xmlEscaped(query))</query>
        <ranked_results>
        \(renderedDocuments)
        </ranked_results>
        <task>
        Summarize the most relevant work and findings related to the query using only the ranked results above. If the query is a question, use the ranked_results to answer the question directly.
        </task>
        </search_summary_request>
        """
    }
}
