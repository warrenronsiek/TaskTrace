//
//  SkillGenerationService.swift
//  TaskTrace
//
//  Created by Codex on 4/21/26.
//

import Foundation
import OSLog

enum SkillGenerationError: LocalizedError, Equatable {
    case emptyQuery
    case missingQueryEmbedding
    case noMatchedContext
    case promptTooLargeBecauseOfMicrophone

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "Skill query cannot be empty."
        case .missingQueryEmbedding:
            "TaskTrace could not generate an embedding for this skill query."
        case .noMatchedContext:
            "TaskTrace did not find relevant activity from today for this skill."
        case .promptTooLargeBecauseOfMicrophone:
            "The matched microphone narration is too large. Try a narrower skill query."
        }
    }
}

nonisolated struct SkillThinkingParseResult: Equatable, Sendable {
    let markdown: String
    let activeThinkingText: String
}

nonisolated enum SkillThinkingParser {
    static func parse(_ rawText: String) -> SkillThinkingParseResult {
        var remaining = rawText[...]
        var markdown = ""
        var activeThinkingText = ""

        while let openingRange = remaining.range(of: "<think>", options: [.caseInsensitive]) {
            markdown.append(contentsOf: remaining[..<openingRange.lowerBound])
            let afterOpening = remaining[openingRange.upperBound...]

            guard let closingRange = afterOpening.range(of: "</think>", options: [.caseInsensitive]) else {
                activeThinkingText = String(afterOpening)
                return SkillThinkingParseResult(markdown: markdown, activeThinkingText: activeThinkingText)
            }

            remaining = afterOpening[closingRange.upperBound...]
        }

        markdown.append(contentsOf: remaining)
        return SkillThinkingParseResult(markdown: markdown, activeThinkingText: "")
    }
}

final class SkillGenerationService: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "skills")
    private let searchDatabaseActor: SearchDatabaseActor
    private let embeddingGenerator: any ActivityEmbeddingGenerating
    private let procedureGenerator: any SkillProcedureGenerating
    private let calendar: Calendar

    init(
        searchDatabaseActor: SearchDatabaseActor,
        embeddingGenerator: any ActivityEmbeddingGenerating,
        procedureGenerator: any SkillProcedureGenerating,
        calendar: Calendar = .current
    ) {
        self.searchDatabaseActor = searchDatabaseActor
        self.embeddingGenerator = embeddingGenerator
        self.procedureGenerator = procedureGenerator
        self.calendar = calendar
    }

    func retrieveContext(query: String, day: Date) async throws -> [SkillContextActivity] {
        let submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !submittedQuery.isEmpty else {
            throw SkillGenerationError.emptyQuery
        }

        let queryVector = await embeddingGenerator.generateVectors(
            for: [submittedQuery],
            promptPrefix: nil,
            source: "skill-context-embedding"
        ).first ?? []

        guard !queryVector.isEmpty else {
            throw SkillGenerationError.missingQueryEmbedding
        }

        let queryVectorJSONString = String(
            decoding: try JSONEncoder().encode(queryVector),
            as: UTF8.self
        )
        let keywordizedQuery = SearchKeywordizer.keywordize(submittedQuery)
        let results = try await searchDatabaseActor.skillContext(
            ftsQuery: keywordizedQuery,
            queryVectorJSONString: queryVectorJSONString,
            day: day,
            calendar: calendar
        )

        logger.log(
            "skill context retrieved queryCharacters=\(submittedQuery.count, privacy: .public) activityCount=\(results.count, privacy: .public)"
        )
        return results
    }

    func streamProcedure(
        query: String,
        context: [SkillContextActivity],
        traceStartedAt: Date?
    ) async throws -> AsyncThrowingStream<String, Error> {
        let submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !submittedQuery.isEmpty else {
            throw SkillGenerationError.emptyQuery
        }

        guard !context.isEmpty else {
            throw SkillGenerationError.noMatchedContext
        }

        return await procedureGenerator.skillProcedure(
            prompt: try Self.prompt(query: submittedQuery, context: context),
            instructions: Self.instructions,
            traceStartedAt: traceStartedAt
        )
    }

    nonisolated static let instructions =
        """
        You create step-by-step Markdown procedures from TaskTrace desktop activity evidence.
        Think carefully through the evidence before writing.
        Use only the supplied activity summaries, microphone narration, keystrokes, and screenshot summaries.
        Prefer concrete procedural steps over generic advice.
        If the evidence is incomplete, include a short "Gaps" section at the end.
        Output Markdown only after thinking.
        """

    nonisolated static func prompt(
        query: String,
        context: [SkillContextActivity]
    ) throws -> String {
        let microphoneCharacters = context.map(\.microphone.count).reduce(0, +)

        guard microphoneCharacters < Vars.skillContextPromptCharacterLimit - 8_000 else {
            throw SkillGenerationError.promptTooLargeBecauseOfMicrophone
        }

        let prompt = renderPrompt(query: query, context: context, nonMicrophoneCharacterLimit: 2_000)

        guard prompt.count > Vars.skillContextPromptCharacterLimit else {
            return prompt
        }

        let aggressivelyClippedPrompt = renderPrompt(query: query, context: context, nonMicrophoneCharacterLimit: 700)

        guard aggressivelyClippedPrompt.count <= Vars.skillContextPromptCharacterLimit else {
            throw SkillGenerationError.promptTooLargeBecauseOfMicrophone
        }

        return aggressivelyClippedPrompt
    }

    private nonisolated static func renderPrompt(
        query: String,
        context: [SkillContextActivity],
        nonMicrophoneCharacterLimit: Int
    ) -> String {
        let renderedActivities = context.map { activity in
            let markdownBlock: (String, String, Bool) -> String = { title, value, clip in
                let text = (clip ? AITextUtilities.clippedPromptSourceText(value, maxCharacters: nonMicrophoneCharacterLimit) : value)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "```", with: "'''")

                return text.isEmpty
                    ? ""
                    : "  - \(title):\n    ```text\n    \(text.replacingOccurrences(of: "\n", with: "\n    "))\n    ```"
            }

            let renderedScreenshots = {
                let descriptions = activity.screenshots.compactMap { screenshot in
                    AITextUtilities.clippedPromptSourceText(
                        screenshot.summary ?? screenshot.description,
                        maxCharacters: nonMicrophoneCharacterLimit
                    )
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }

                return descriptions.isEmpty
                    ? ""
                    : (["  - Screenshots:"] + descriptions.map { "    - \($0.replacingOccurrences(of: "\n", with: "\n      "))" })
                        .joined(separator: "\n")
            }()

            return [
                "- Activity:",
                activity.application.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "  - Application: \(activity.application)",
                markdownBlock("Summary", activity.summary ?? "", true),
                markdownBlock("Microphone narration", activity.microphone, false),
                markdownBlock("Keystrokes", activity.keystrokes, true),
                renderedScreenshots
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        }
        .joined(separator: "\n\n")

        return """
        # Skill Request

        \(query)

        # Evidence

        The following activity array is in chronological order.

        \(renderedActivities)

        # Task

        Create a step-by-step Markdown procedure that teaches someone how to accomplish the request using the evidence above. Preserve concrete commands, file paths, UI labels, decisions, and gotchas when present.
        """
    }
}
