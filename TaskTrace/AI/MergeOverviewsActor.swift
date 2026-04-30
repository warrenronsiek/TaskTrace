//
//  MergeOverviewsActor.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation
import MLXLMCommon
import OSLog

actor MergeOverviewsActor: Receiver, OverviewMerging {
    nonisolated static let maxOutputTokens = 120

    nonisolated static let instructions =
        """
        You are merging two day-level work overviews into a single replacement overview.
        Produce one concise merged title and one concise merged summary.
        Preserve the actual scope of the work, but remove duplicate phrasing.
        If the two overviews describe the same project or workstream at different levels of detail, unify them.
        If they are adjacent sub-phases of the same deliverable, produce a broader merged overview that still feels specific.
        Do not mention that a merge happened.
        Do not output XML.
        Reply with exactly these two lines and nothing else:
        TITLE: MERGED_TITLE
        SUMMARY: MERGED_SUMMARY
        """

    private let actorSystem: ActorSystem?
    private let fallbackOverviewMerger: (any OverviewMerging)?
    private var pendingRequests: [UUID: OverviewMergeComputationRequested] = [:]
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.fallbackOverviewMerger = nil
    }

    init(
        actorSystem: ActorSystem,
        overviewMerger: any OverviewMerging
    ) {
        self.actorSystem = actorSystem
        self.fallbackOverviewMerger = overviewMerger
    }

    func mergeOverviews(
        _ firstOverview: ActivityOverviewMergeOption,
        _ secondOverview: ActivityOverviewMergeOption
    ) async throws -> ActivityOverviewMergeDecision {
        if let fallbackOverviewMerger {
            return try await fallbackOverviewMerger.mergeOverviews(firstOverview, secondOverview)
        }

        throw ActivityAIError.emptyOverviewMergeDecision
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let request as OverviewMergeComputationRequested:
            logger.log(
                "merge-overviews-actor received sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) firstOverviewID=\(request.firstOverview.id, privacy: .public) secondOverviewID=\(request.secondOverview.id, privacy: .public)"
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

    private func process(_ request: OverviewMergeComputationRequested) async {
        if let fallbackOverviewMerger {
            do {
                let decision = try await fallbackOverviewMerger.mergeOverviews(
                    ActivityOverviewMergeOption(
                        title: request.firstOverview.title ?? "Untitled Overview",
                        summary: request.firstOverview.summary ?? "Overview summary unavailable.",
                        durationSeconds: request.firstDuration
                    ),
                    ActivityOverviewMergeOption(
                        title: request.secondOverview.title ?? "Untitled Overview",
                        summary: request.secondOverview.summary ?? "Overview summary unavailable.",
                        durationSeconds: request.secondDuration
                    )
                )
                await broadcastResolved(request, decision: decision)
            } catch {
                await broadcastFailed(request, error: error)
            }
            return
        }

        do {
            let prompt = Self.request(
                firstOverview: ActivityOverviewMergeOption(
                    title: request.firstOverview.title ?? "Untitled Overview",
                    summary: request.firstOverview.summary ?? "Overview summary unavailable.",
                    durationSeconds: request.firstDuration
                ),
                secondOverview: ActivityOverviewMergeOption(
                    title: request.secondOverview.title ?? "Untitled Overview",
                    summary: request.secondOverview.summary ?? "Overview summary unavailable.",
                    durationSeconds: request.secondDuration
                )
            )
            prompt
                .components(separatedBy: "\n")
                .enumerated()
                .forEach { lineNumber, line in
                    self.logger.log(
                        "mergeOverviews request line=\(lineNumber, privacy: .public) text=\(line, privacy: .public)"
                    )
                }
            let modelRequest = try AIRecursivePromptReducer.makeRequest(
                source: "overview-merge",
                priority: .interactive,
                prompt: prompt,
                instructions: Self.instructions,
                generateParameters: GenerateParameters(maxTokens: Self.maxOutputTokens, temperature: 0),
                additionalContext: ["enable_thinking": false]
            )
            pendingRequests[modelRequest.requestID] = request
            await actorSystem?.broadcast(from: nil, message: modelRequest)
        } catch {
            await broadcastFailed(request, error: error)
        }
    }

    private func handleCompleted(_ event: ModelTextCompleted) async {
        guard let request = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        event.response
            .components(separatedBy: "\n")
            .enumerated()
            .forEach { lineNumber, line in
                self.logger.log(
                    "mergeOverviews response line=\(lineNumber, privacy: .public) text=\(line, privacy: .public)"
                )
            }
        let decision = Self.parseDecision(
            AITextUtilities.strippingThinkingBlocks(from: event.response)
        )
        logger.log(
            "mergeOverviews parse completed success=\(decision.title != nil || decision.summary != nil, privacy: .public) title=\(String(describing: decision.title), privacy: .public)"
        )

        guard decision.title != nil || decision.summary != nil else {
            await broadcastFailed(request, error: ActivityAIError.emptyOverviewMergeDecision)
            return
        }

        await broadcastResolved(request, decision: decision)
    }

    private func handleFailed(_ event: ModelTextFailed) async {
        guard let request = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        await broadcastFailed(request, error: event.message)
    }

    private func broadcastResolved(
        _ request: OverviewMergeComputationRequested,
        decision: ActivityOverviewMergeDecision
    ) async {
        logger.log(
            "merge-overviews-actor broadcasting overview-merge-resolved firstOverviewID=\(request.firstOverview.id, privacy: .public) secondOverviewID=\(request.secondOverview.id, privacy: .public)"
        )
        await actorSystem?.broadcast(
            from: nil,
            message: OverviewMergeResolved(
                mergedOverviewID: request.mergedOverviewID,
                firstOverview: request.firstOverview,
                secondOverview: request.secondOverview,
                firstDuration: request.firstDuration,
                secondDuration: request.secondDuration,
                activityIDs: request.activityIDs,
                decision: decision
            )
        )
    }

    private func broadcastFailed(
        _ request: OverviewMergeComputationRequested,
        error: Any
    ) async {
        logger.error(
            "merge-overviews-actor failed firstOverviewID=\(request.firstOverview.id, privacy: .public) secondOverviewID=\(request.secondOverview.id, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
        await actorSystem?.broadcast(
            from: nil,
            message: OverviewMergeFailed(
                firstOverviewID: request.firstOverview.id,
                secondOverviewID: request.secondOverview.id,
                errorMessage: String(describing: error)
            )
        )
    }

    nonisolated static func request(
        firstOverview: ActivityOverviewMergeOption,
        secondOverview: ActivityOverviewMergeOption
    ) -> String {
        let xmlForOverview = { (label: String, overview: ActivityOverviewMergeOption) in
            """
            <\(label)>
            <title>\(AITextUtilities.xmlEscaped(AITextUtilities.strippingThinkingBlocks(from: overview.title)))</title>
            <summary>\(AITextUtilities.xmlEscaped(AITextUtilities.strippingThinkingBlocks(from: overview.summary)))</summary>
            <duration_seconds>\(overview.durationSeconds)</duration_seconds>
            <duration_human>\(AITextUtilities.xmlEscaped(Duration.seconds(overview.durationSeconds).formatted(.units(width: .wide, maximumUnitCount: 2))))</duration_human>
            </\(label)>
            """
        }

        return """
        <overview_merge_request>
        \(xmlForOverview("first_overview", firstOverview))
        \(xmlForOverview("second_overview", secondOverview))
        </overview_merge_request>
        """
    }

    nonisolated static func parseDecision(_ response: String) -> ActivityOverviewMergeDecision {
        let capture = { (pattern: String) -> String? in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
                  let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
                  match.numberOfRanges > 1 else {
                return nil
            }

            let range = match.range(at: 1)

            guard range.location != NSNotFound,
                  let resolvedRange = Range(range, in: response) else {
                return nil
            }

            return String(response[resolvedRange])
        }

        return ActivityOverviewMergeDecision(
            title: capture(#"^TITLE:[ \t]*(.*)"#).flatMap { $0.isEmpty ? nil : $0 },
            summary: capture(#"(?s)^SUMMARY:[ \t]*(.+)"#).flatMap {
                $0.isEmpty ? nil : AITextUtilities.normalizedNarration($0)
            }
        )
    }

    nonisolated static func mergeKey(firstOverviewID: Int64, secondOverviewID: Int64) -> String {
        let sorted = [firstOverviewID, secondOverviewID].sorted()
        return "\(sorted[0])-\(sorted[1])"
    }
}
