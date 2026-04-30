//
//  SummarizeActivityActor.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation
import MLXLMCommon
import OSLog

actor SummarizeActivityActor: Receiver, ActivitySummarizing {
    nonisolated static let instructions =
        """
        You are summarizing a sequence of screenshots from one computer activity.
        Each screenshot contains a concise screenshot summary.
        Use the full sequence to infer what the user was doing over time.
        Mention any user goals, accomplishments, or completed work if such things are evident from the activity.
        Prefer concrete actions and work context. Do not mention XML. Do not speculate beyond the provided evidence.
        Start directly with the work itself. Do not begin with phrases like "The user was", "The user is", or similar preambles.
        Return a detailed summary in plain text. 
        """

    private let actorSystem: ActorSystem?
    private let fallbackSummarizer: (any ActivitySummarizing)?
    private var pendingRequests: [UUID: ActivitySummaryRequested] = [:]
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.fallbackSummarizer = nil
    }

    init(
        actorSystem: ActorSystem,
        summarizer: any ActivitySummarizing
    ) {
        self.actorSystem = actorSystem
        self.fallbackSummarizer = summarizer
    }

    func summarizeActivity(_ activity: ActivityActor.Activity) async -> String {
        if let fallbackSummarizer {
            return await fallbackSummarizer.summarizeActivity(activity)
        }

        return "Activity summary unavailable."
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let request as ActivitySummaryRequested:
            logger.log(
                "summarize-activity-actor received sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(request.activity.id, privacy: .public)"
            )
            Task {
                await self.process(request)
            }
        case let event as ModelTextCompleted:
            await handleCompleted(event)
        case let event as ModelTextFailed:
            await handleFailed(event)
        default:
            return
        }
    }

    private func process(_ request: ActivitySummaryRequested) async {
        if let fallbackSummarizer {
            let summary = await fallbackSummarizer.summarizeActivity(request.activity)
            await broadcastSummary(activity: request.activity, summary: summary)
            return
        }

        do {
            let modelRequest = try AIRecursivePromptReducer.makeRequest(
                source: "activity-summary",
                priority: .interactive,
                prompt: Self.summaryPrompt(for: request.activity),
                instructions: Self.instructions,
                generateParameters: GenerateParameters(maxTokens: 220, temperature: 0),
                additionalContext: ["enable_thinking": false]
            )
            pendingRequests[modelRequest.requestID] = request
            await actorSystem?.broadcast(from: nil, message: modelRequest)
        } catch {
            logger.error(
                "summarize-activity-actor failed activityID=\(request.activity.id, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            await broadcastSummary(activity: request.activity, summary: "Activity summary unavailable.")
        }
    }

    private func handleCompleted(_ event: ModelTextCompleted) async {
        guard let request = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        let response = AITextUtilities
            .strippingThinkingBlocks(from: event.response)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = response.isEmpty
            ? "Activity summary unavailable."
            : AITextUtilities.normalizedNarration(response)
        await broadcastSummary(activity: request.activity, summary: summary)
    }

    private func handleFailed(_ event: ModelTextFailed) async {
        guard let request = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        logger.error(
            "summarize-activity-actor failed activityID=\(request.activity.id, privacy: .public) error=\(event.message, privacy: .public)"
        )
        await broadcastSummary(activity: request.activity, summary: "Activity summary unavailable.")
    }

    private func broadcastSummary(activity: ActivityActor.Activity, summary: String) async {
        let updatedActivity = {
            var activity = activity
            activity.summary = summary
            return activity
        }()

        logger.log(
            "summarize-activity-actor broadcasting activity-summarized activityID=\(updatedActivity.id, privacy: .public) characters=\(summary.count, privacy: .public)"
        )
        await actorSystem?.broadcast(
            from: nil,
            message: ActivitySummarized(activity: updatedActivity)
        )
    }

    nonisolated static func summaryPrompt(for activity: ActivityActor.Activity) -> String {
        let screenshots = activity.screenshots.enumerated().map { index, screenshot in
            let parts = [
                "<index>\(index + 1)</index>",
                "<timestamp>\(screenshot.timestamp.ISO8601Format())</timestamp>",
                "<summary>\(AITextUtilities.xmlEscaped(AITextUtilities.clippedPromptSourceText(screenshot.summary)))</summary>"
            ].joined(separator: "")
            return "<screenshot>\(parts)</screenshot>"
        }.joined()

        return """
        <activity>
        <application>\(AITextUtilities.xmlEscaped(activity.application))</application>
        <started_at>\(activity.startTime.ISO8601Format())</started_at>
        <screenshots>\(screenshots)</screenshots>
        </activity>
        """
    }
}
