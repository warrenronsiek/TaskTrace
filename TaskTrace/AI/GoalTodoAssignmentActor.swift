//
//  GoalTodoAssignmentActor.swift
//  TaskTrace
//
//  Created by Codex on 5/8/26.
//

import Foundation
import MLXLMCommon
import OSLog

actor GoalTodoAssignmentActor: Receiver {
    nonisolated static let instructions =
        """
        You assign one summarized computer activity to one available todo.
        Activities can only be assigned to todos, not directly to goals.
        Use the goal context only to understand what each todo means.
        Return exactly one value: either the zero-based todo index or nil.
        Do not return markdown, explanation, labels, JSON, or any other text.
        """

    private struct PendingRequest: Sendable {
        let activityID: Int64
        let candidateTodoIDs: [Int64]
    }

    private let actorSystem: ActorSystem
    private let goalsDatabaseActor: GoalsDatabaseActor
    private var pendingRequests: [UUID: PendingRequest] = [:]
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init(
        actorSystem: ActorSystem,
        goalsDatabaseActor: GoalsDatabaseActor
    ) {
        self.actorSystem = actorSystem
        self.goalsDatabaseActor = goalsDatabaseActor
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as ActivitySummarized:
            guard !(event.activity.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                  event.activity.goalTodoAssignmentSource != .manual else {
                return
            }
            Task {
                await self.process(event.activity)
            }
        case let event as ModelTextCompleted:
            await handleCompleted(event)
        case let event as ModelTextFailed:
            await handleFailed(event)
        default:
            return
        }
    }

    private func process(_ activity: ActivityActor.Activity) async {
        do {
            let candidates = try await goalsDatabaseActor.loadOpenTodoCandidates(
                forActivityDay: activity.startTime
            )

            guard !candidates.isEmpty else {
                await actorSystem.broadcast(
                    from: nil,
                    message: GoalTodoAssignmentDecided(activityID: activity.id, todoID: nil)
                )
                return
            }

            let modelRequest = try AIRecursivePromptReducer.makeRequest(
                source: "activity-goal-todo-assignment",
                priority: .background,
                prompt: Self.prompt(activity: activity, candidates: candidates),
                instructions: Self.instructions,
                generateParameters: GenerateParameters(maxTokens: 8, temperature: 0),
                additionalContext: ["enable_thinking": false]
            )

            pendingRequests[modelRequest.requestID] = PendingRequest(
                activityID: activity.id,
                candidateTodoIDs: candidates.map(\.todo.id)
            )
            await actorSystem.broadcast(from: nil, message: modelRequest)
        } catch {
            logger.error(
                "goal-todo-assignment-actor failed activityID=\(activity.id, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            await actorSystem.broadcast(
                from: nil,
                message: GoalTodoAssignmentDecided(activityID: activity.id, todoID: nil)
            )
        }
    }

    private func handleCompleted(_ event: ModelTextCompleted) async {
        guard let request = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        let decision = Self.parseDecision(event.response)
        let todoID = decision.flatMap { index in
            request.candidateTodoIDs.indices.contains(index)
                ? request.candidateTodoIDs[index]
                : nil
        }

        logger.log(
            "goal-todo-assignment-actor completed activityID=\(request.activityID, privacy: .public) todoID=\(todoID.map(String.init) ?? "<nil>", privacy: .public)"
        )
        await actorSystem.broadcast(
            from: nil,
            message: GoalTodoAssignmentDecided(
                activityID: request.activityID,
                todoID: todoID
            )
        )
    }

    private func handleFailed(_ event: ModelTextFailed) async {
        guard let request = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        logger.error(
            "goal-todo-assignment-actor failed activityID=\(request.activityID, privacy: .public) error=\(event.message, privacy: .public)"
        )
        await actorSystem.broadcast(
            from: nil,
            message: GoalTodoAssignmentDecided(activityID: request.activityID, todoID: nil)
        )
    }

    nonisolated static func parseDecision(_ response: String) -> Int? {
        let normalized = AITextUtilities
            .strippingThinkingBlocks(from: response)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.lowercased() != "nil" else {
            return nil
        }

        return Int(normalized)
    }

    nonisolated static func prompt(
        activity: ActivityActor.Activity,
        candidates: [GoalTodoCandidate]
    ) -> String {
        let todos = candidates.enumerated().map { index, candidate in
            let targetMode = switch candidate.todo.dailyTargetMode {
            case .minimum:
                "at least"
            case .maximum:
                "at most"
            }
            let target = [
                candidate.todo.targetDate.map { "target day: \($0.formatted(TaskTraceDatabase.sqlDateStyle))" },
                candidate.todo.dailyTargetSeconds.map { "daily target: \(targetMode) \($0) seconds" }
            ]
            .compactMap { $0 }
            .joined(separator: "; ")
            let details = [
                candidate.goal.map { "goal: \($0.name)" } ?? "standalone todo",
                candidate.goal?.description.map { "goal description: \($0)" },
                "todo: \(candidate.todo.name)",
                target.isEmpty ? nil : target
            ]
            .compactMap { $0 }
            .joined(separator: "\n  ")
            return "\(index). \(details)"
        }
        .joined(separator: "\n\n")
        let screenshots = activity.screenshots.enumerated().compactMap { index, screenshot in
            guard let summary = screenshot.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !summary.isEmpty else {
                return nil
            }

            return "\(index). \(summary)"
        }
        .joined(separator: "\n")

        return """
        # Available todos
        \(todos)

        # Activity
        Application: \(activity.application)
        Started at: \(activity.startTime.ISO8601Format())
        Summary: \(activity.summary ?? "")

        # Screenshot summaries
        \(screenshots.isEmpty ? "None" : screenshots)
        """
    }
}
