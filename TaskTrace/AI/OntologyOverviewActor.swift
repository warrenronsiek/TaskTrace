//
//  OntologyOverviewActor.swift
//  TaskTrace
//

import Foundation
import MLXLMCommon
import OSLog

actor OntologyOverviewActor: Receiver {
    nonisolated enum Request: Sendable {
        case summarize(OntologyOverviewSummaryKey)
        case rebuild
    }

    nonisolated static let summaryMaxOutputTokens = 160

    nonisolated static let summarizeInstructions =
        """
        Summarize the following sequence of desktop activities.
        Return plain text using exactly this structure:

        Title: a short concrete label
        Summary: one concise paragraph

        The title should be 2 to 8 words.
        The summary should describe the actual work progression visible across the provided activities.
        Be factual, specific, and concise.
        """

    private let actorSystem: ActorSystem
    private let overviewDatabaseActor: OverviewDatabaseActor
    private let identifierActor: IdentifierActor
    private let debounceNanoseconds: UInt64
    private var pendingRequests: [UUID: OntologyOverviewSummaryKey] = [:]
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init(
        actorSystem: ActorSystem,
        overviewDatabaseActor: OverviewDatabaseActor,
        identifierActor: IdentifierActor = .shared,
        textResponder: (any AITextResponding)? = nil,
        debounceNanoseconds: UInt64 = 300_000_000
    ) {
        self.actorSystem = actorSystem
        self.overviewDatabaseActor = overviewDatabaseActor
        self.identifierActor = identifierActor
        self.debounceNanoseconds = debounceNanoseconds
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as ActivityTagAssigned:
            Task {
                await self.handleActivityTagAssigned(event)
            }
        case _ as ActivityTagOntologyRunPublished:
            Task {
                await self.process(.rebuild)
            }
        case _ as OntologyOverviewRebuildRequested:
            Task {
                await self.process(.rebuild)
            }
        case let event as ModelTextCompleted:
            await handleCompleted(event)
        case let event as ModelTextFailed:
            await handleFailed(event)
        default:
            return
        }
    }

    private func handleActivityTagAssigned(_ event: ActivityTagAssigned) async {
        do {
            guard let key = try await overviewDatabaseActor.loadOntologyOverviewRefreshKey(
                activityID: event.activityID,
                tagID: event.tagID
            ) else {
                return
            }

            await ensureAssignmentAndScheduleSummary(for: key)
        } catch {
            logger.error(
                "ontology-overview-actor failed to load refresh key activityID=\(event.activityID, privacy: .public) tagID=\(event.tagID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func process(_ message: Request) async {
        do {
            switch message {
            case .summarize(let key):
                try await summarizeOverview(for: key)
            case .rebuild:
                let keys = try await overviewDatabaseActor.loadOntologyOverviewRefreshKeys()

                for key in keys {
                    await ensureAssignmentAndScheduleSummary(
                        for: key,
                        debounceNanoseconds: 0
                    )
                }
            }
        } catch {
            logger.error(
                "ontology-overview-actor failed message error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func ensureAssignmentAndScheduleSummary(
        for key: OntologyOverviewRefreshKey,
        debounceNanoseconds: UInt64? = nil
    ) async {
        do {
            guard let summaryKey = try await overviewDatabaseActor.ensureOntologyOverviewAssignment(
                key: key,
                newOverviewID: await identifierActor.makeIdentifier()
            ) else {
                await reloadVisibleDay(key.day)
                return
            }

            await reloadVisibleDay(key.day)
            await scheduleSummary(
                for: summaryKey,
                debounceNanoseconds: debounceNanoseconds ?? self.debounceNanoseconds
            )
        } catch {
            logger.error(
                "ontology-overview-actor failed assignment day=\(key.day.formatted(TaskTraceDatabase.sqlDateStyle), privacy: .public) tagID=\(key.tagID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func scheduleSummary(
        for key: OntologyOverviewSummaryKey,
        debounceNanoseconds: UInt64
    ) async {
        Task {
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            await self.process(.summarize(key))
        }
    }

    private func summarizeOverview(
        for key: OntologyOverviewSummaryKey
    ) async throws {
        do {
            let snapshot = try await overviewDatabaseActor.loadOntologyOverviewSummarySnapshot(key: key)

            guard !snapshot.activityIDs.isEmpty else {
                return
            }

            guard !snapshot.activities.isEmpty else {
                return
            }

            let modelRequest = try AIRecursivePromptReducer.makeRequest(
                source: "ontology-overview-summary",
                priority: .interactive,
                prompt: Self.buildPrompt(snapshot.activities),
                instructions: Self.summarizeInstructions,
                generateParameters: GenerateParameters(maxTokens: Self.summaryMaxOutputTokens, temperature: 0),
                additionalContext: ["enable_thinking": false]
            )
            pendingRequests[modelRequest.requestID] = key
            await actorSystem.broadcast(from: nil, message: modelRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error(
                "ontology-overview-actor failed summarize day=\(key.day.formatted(TaskTraceDatabase.sqlDateStyle), privacy: .public) overviewID=\(key.overviewID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func handleCompleted(_ event: ModelTextCompleted) async {
        guard let key = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        do {
            let response = AITextUtilities.strippingThinkingBlocks(from: event.response)
            try await overviewDatabaseActor.applyOntologyOverviewGeneratedText(
                overviewID: key.overviewID,
                generatedTitle: Self.parseField("Title:", in: response) ?? "Untitled Overview",
                generatedSummary: Self.parseField("Summary:", in: response)
                    ?? response.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            await reloadVisibleDay(key.day)
        } catch {
            logger.error(
                "ontology-overview-actor failed summarize day=\(key.day.formatted(TaskTraceDatabase.sqlDateStyle), privacy: .public) overviewID=\(key.overviewID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func handleFailed(_ event: ModelTextFailed) async {
        guard let key = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        logger.error(
            "ontology-overview-actor failed summarize day=\(key.day.formatted(TaskTraceDatabase.sqlDateStyle), privacy: .public) overviewID=\(key.overviewID, privacy: .public) error=\(event.message, privacy: .public)"
        )
    }

    private func reloadVisibleDay(_ day: Date) async {
        await actorSystem.broadcast(
            from: nil,
            message: ActivityDayReloadRequested(day: day)
        )
        await actorSystem.broadcast(
            from: nil,
            message: OverviewDayReloadRequested(day: day)
        )
    }

    nonisolated private static func buildPrompt(
        _ activities: [OntologyOverviewSummaryActivity]
    ) -> String {
        AITextUtilities.clippedPromptSourceText(
            activities.enumerated().map { index, activity in
            """
            Activity \(index + 1) at \(activity.startTime.ISO8601Format()):
            \(activity.summary)
            """
        }
        .joined(separator: "\n\n")
        )
    }

    nonisolated private static func parseField(
        _ prefix: String,
        in response: String
    ) -> String? {
        response
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix(prefix) })
            .flatMap {
                let value = String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
    }
}
