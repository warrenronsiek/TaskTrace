//
//  SkillsStore.swift
//  TaskTrace
//
//  Created by Codex on 4/21/26.
//

import Combine
import Foundation
import OSLog

enum SkillGenerationPhase: Equatable, Sendable {
    case idle
    case retrievingContext
    case thinking
    case streaming
    case writingToObsidian
    case complete
    case failed

    var title: String {
        switch self {
        case .idle:
            "Ready"
        case .retrievingContext:
            "Retrieving today's matching activity"
        case .thinking:
            "TaskTrace is thinking through the selected activities"
        case .streaming:
            "Writing the procedure"
        case .writingToObsidian:
            "Writing to Obsidian"
        case .complete:
            "Complete"
        case .failed:
            "Failed"
        }
    }
}

@MainActor
final class SkillsStore: ObservableObject {
    @Published var query: String
    @Published private(set) var markdown: String
    @Published private(set) var thinkingText: String
    @Published private(set) var matchedActivities: [SkillContextActivity]
    @Published private(set) var phase: SkillGenerationPhase
    @Published private(set) var errorMessage: String?
    @Published private(set) var obsidianFilePath: String?

    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "skills")
    private let skillGenerationService: SkillGenerationService?
    private let obsidianWriter: SkillObsidianWriter?
    private let now: @MainActor @Sendable () -> Date
    private var generationTask: Task<Void, Never>?
    private var writeTask: Task<Void, Never>?
    private var obsidianTarget: SkillObsidianWriteTarget?

    init(
        skillGenerationService: SkillGenerationService,
        obsidianWriter: SkillObsidianWriter,
        now: @escaping @MainActor @Sendable () -> Date = Date.init
    ) {
        self.skillGenerationService = skillGenerationService
        self.obsidianWriter = obsidianWriter
        self.now = now
        self.query = ""
        self.markdown = ""
        self.thinkingText = ""
        self.matchedActivities = []
        self.phase = .idle
        self.errorMessage = nil
        self.obsidianFilePath = nil
    }

    init(previewActivities: [SkillContextActivity] = []) {
        self.skillGenerationService = nil
        self.obsidianWriter = nil
        self.now = Date.init
        self.query = ""
        self.markdown = ""
        self.thinkingText = ""
        self.matchedActivities = previewActivities
        self.phase = .idle
        self.errorMessage = nil
        self.obsidianFilePath = nil
    }

    var isGenerating: Bool {
        switch phase {
        case .retrievingContext, .thinking, .streaming, .writingToObsidian:
            true
        case .idle, .complete, .failed:
            false
        }
    }

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        writeTask?.cancel()
        writeTask = nil
        phase = .idle
    }

    func generate() {
        let submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !submittedQuery.isEmpty else {
            markdown = ""
            thinkingText = ""
            matchedActivities = []
            errorMessage = nil
            phase = .idle
            return
        }

        guard let skillGenerationService else {
            errorMessage = "Skills are unavailable in preview mode."
            phase = .failed
            return
        }

        generationTask?.cancel()
        writeTask?.cancel()
        let startedAt = now()
        markdown = ""
        thinkingText = ""
        matchedActivities = []
        errorMessage = nil
        obsidianFilePath = nil
        obsidianTarget = nil
        phase = .retrievingContext

        generationTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let context = try await skillGenerationService.retrieveContext(query: submittedQuery, day: startedAt)

                guard !Task.isCancelled else {
                    return
                }

                guard !context.isEmpty else {
                    throw SkillGenerationError.noMatchedContext
                }

                matchedActivities = context
                phase = .thinking
                let stream = try await skillGenerationService.streamProcedure(
                    query: submittedQuery,
                    context: context,
                    traceStartedAt: startedAt
                )
                var rawStream = ""

                for try await chunk in stream {
                    guard !Task.isCancelled else {
                        return
                    }

                    rawStream.append(chunk)
                    let parsed = SkillThinkingParser.parse(rawStream)
                    markdown = parsed.markdown
                    thinkingText = parsed.activeThinkingText

                    if !parsed.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        phase = .streaming
                    } else if !parsed.activeThinkingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        phase = .thinking
                    }
                }

                guard !Task.isCancelled else {
                    return
                }

                thinkingText = ""

                if let obsidianWriter {
                    phase = .writingToObsidian
                    obsidianTarget = try await obsidianWriter.createTarget(query: submittedQuery, createdAt: startedAt)

                    if let obsidianTarget {
                        try await obsidianWriter.write(markdown: markdown, target: obsidianTarget)
                        obsidianFilePath = obsidianTarget.fileURL.path
                    }
                }

                phase = .complete
            } catch is CancellationError {
                return
            } catch {
                logger.error("skill generation failed error=\(String(describing: error), privacy: .public)")
                errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                phase = .failed
            }
        }
    }

    func userEditedMarkdown(_ value: String) {
        markdown = value

        guard phase == .complete,
              let obsidianWriter,
              let obsidianTarget
        else {
            return
        }

        writeTask?.cancel()
        writeTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 450_000_000)
                guard let self, !Task.isCancelled else {
                    return
                }

                try await obsidianWriter.write(markdown: value, target: obsidianTarget)
                obsidianFilePath = obsidianTarget.fileURL.path
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }
}
