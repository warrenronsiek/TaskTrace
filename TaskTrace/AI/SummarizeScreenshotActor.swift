//
//  SummarizeScreenshotActor.swift
//  TaskTrace
//
//  Created by Codex on 4/26/26.
//

import Foundation
import MLXLMCommon
import OSLog

actor SummarizeScreenshotActor: Receiver, ActivityScreenshotSummarizing {
    nonisolated static let maxOutputTokens = 80

    nonisolated static let instructions =
        """
        You summarize one desktop screenshot using OCR text and a visual description.
        Describe what the user appears to be doing from the combined evidence.
        Prefer concrete actions, applications, documents, UI state, and visible work context.
        Do not list raw OCR. Do not mention XML. Do not speculate beyond the provided evidence.
        Start directly with the work itself. Do not begin with phrases like "The user was", "The user is", or similar preambles.
        Return a concise plain-text summary.
        """

    private let actorSystem: ActorSystem?
    private let fallbackSummarizer: (any ActivityScreenshotSummarizing)?
    private var pendingRequests: [UUID: SummarizeScreenshot] = [:]
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.fallbackSummarizer = nil
    }

    init(
        actorSystem: ActorSystem,
        screenshotSummarizer: any ActivityScreenshotSummarizing
    ) {
        self.actorSystem = actorSystem
        self.fallbackSummarizer = screenshotSummarizer
    }

    func summarizeScreenshot(description: String, text: String) async -> String {
        if let fallbackSummarizer {
            return await fallbackSummarizer.summarizeScreenshot(description: description, text: text)
        }

        return "Screenshot summary unavailable."
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let request as SummarizeScreenshot:
            logger.log(
                "summarize-screenshot-actor received sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) screenshotID=\(request.screenshotID, privacy: .public)"
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

    private func process(_ request: SummarizeScreenshot) async {
        if let fallbackSummarizer {
            let summary = await fallbackSummarizer.summarizeScreenshot(
                description: request.description,
                text: request.text
            )
            await broadcastSummary(screenshotID: request.screenshotID, summary: summary)
            return
        }

        do {
            let modelRequest = try AIRecursivePromptReducer.makeRequest(
                source: "screenshot-summary",
                priority: .background,
                prompt: Self.summaryPrompt(description: request.description, text: request.text),
                instructions: Self.instructions,
                generateParameters: GenerateParameters(maxTokens: Self.maxOutputTokens, temperature: 0),
                additionalContext: ["enable_thinking": false]
            )
            pendingRequests[modelRequest.requestID] = request
            await actorSystem?.broadcast(from: nil, message: modelRequest)
        } catch {
            logger.error(
                "summarize-screenshot-actor failed screenshotID=\(request.screenshotID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            await broadcastSummary(screenshotID: request.screenshotID, summary: "Screenshot summary unavailable.")
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
            ? "Screenshot summary unavailable."
            : AITextUtilities.normalizedNarration(response)
        await broadcastSummary(screenshotID: request.screenshotID, summary: summary)
    }

    private func handleFailed(_ event: ModelTextFailed) async {
        guard let request = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        logger.error(
            "summarize-screenshot-actor failed screenshotID=\(request.screenshotID, privacy: .public) error=\(event.message, privacy: .public)"
        )
        await broadcastSummary(screenshotID: request.screenshotID, summary: "Screenshot summary unavailable.")
    }

    private func broadcastSummary(screenshotID: Int64, summary: String) async {
        logger.log(
            "summarize-screenshot-actor broadcasting screenshot-summarized screenshotID=\(screenshotID, privacy: .public) characters=\(summary.count, privacy: .public)"
        )
        await actorSystem?.broadcast(
            from: nil,
            message: ScreenshotSummarized(screenshotID: screenshotID, summary: summary)
        )
    }

    nonisolated static func summaryPrompt(description: String, text: String) -> String {
        """
        <screenshot>
        <description>\(AITextUtilities.xmlEscaped(AITextUtilities.clippedPromptSourceText(description)))</description>
        <ocr>\(AITextUtilities.xmlEscaped(AITextUtilities.clippedPromptSourceText(text)))</ocr>
        </screenshot>
        """
    }
}
