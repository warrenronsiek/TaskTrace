//
//  OverviewActor.swift
//  TaskTrace
//
//  Created by Codex on 3/17/26.
//

import Foundation
import OSLog

actor OverviewActor: Receiver {
    struct State: Equatable, Sendable {
        var overviews: [LoadedOverview]
        var errorMessage: String?
        var revision: Int

        init(
            overviews: [LoadedOverview] = [],
            errorMessage: String? = nil,
            revision: Int = 0
        ) {
            self.overviews = overviews
            self.errorMessage = errorMessage
            self.revision = revision
        }
    }

    private let overviewDatabaseActor: OverviewDatabaseActor
    private let activityActor: ActivityActor
    private let actorSystem: ActorSystem
    private let identifierActor: IdentifierActor
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "overview")

    private var overviews: [LoadedOverview]
    private var errorMessage: String?
    private var revision: Int
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
    private var pendingOverviewMergeKeys: Set<String> = []
    private var localOverviewAssignments: [Int64: Int64] = [:]
    private var loadedDay: Date?

    init(
        overviewDatabaseActor: OverviewDatabaseActor,
        activityActor: ActivityActor,
        actorSystem: ActorSystem,
        identifierActor: IdentifierActor? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.overviewDatabaseActor = overviewDatabaseActor
        self.activityActor = activityActor
        self.actorSystem = actorSystem
        self.identifierActor = identifierActor ?? IdentifierActor.shared
        self.overviews = []
        self.errorMessage = nil
        self.revision = 0
    }

    func updates() -> AsyncStream<State> {
        let id = UUID()

        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(snapshot())
            continuation.onTermination = { _ in
                Task {
                    await self.removeContinuation(id)
                }
            }
        }
    }

    func snapshot() -> State {
        State(
            overviews: overviews,
            errorMessage: errorMessage,
            revision: revision
        )
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as OverviewEditedDurationSetRequested:
            logger.log(
                "overview-actor received overview-edited-duration-set-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) overviewID=\(event.overviewID, privacy: .public) duration=\(event.duration, privacy: .public)"
            )
            guard let existingOverview = overviews.first(where: { $0.id == event.overviewID }) else {
                return
            }

            overviews = overviews.map {
                guard $0.id == existingOverview.id else {
                    return $0
                }

                return LoadedOverview(
                    id: $0.id,
                    title: $0.title,
                    summary: $0.summary,
                    editedDuration: event.duration,
                    tagID: $0.tagID
                )
            }
            errorMessage = nil
            broadcast()
        case let event as OverviewTitleSetRequested:
            logger.log(
                "overview-actor received overview-title-set-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) overviewID=\(event.overviewID, privacy: .public)"
            )
            guard let existingOverview = overviews.first(where: { $0.id == event.overviewID }) else {
                return
            }

            overviews = overviews.map {
                guard $0.id == existingOverview.id else {
                    return $0
                }

                return LoadedOverview(
                    id: $0.id,
                    title: event.title.isEmpty ? nil : event.title,
                    summary: $0.summary,
                    editedDuration: $0.editedDuration,
                    tagID: $0.tagID
                )
            }
            errorMessage = nil
            broadcast()
        case let event as OverviewSummarySetRequested:
            logger.log(
                "overview-actor received overview-summary-set-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) overviewID=\(event.overviewID, privacy: .public)"
            )
            guard let existingOverview = overviews.first(where: { $0.id == event.overviewID }) else {
                return
            }

            overviews = overviews.map {
                guard $0.id == existingOverview.id else {
                    return $0
                }

                return LoadedOverview(
                    id: $0.id,
                    title: $0.title,
                    summary: event.summary.isEmpty ? nil : event.summary,
                    editedDuration: $0.editedDuration,
                    tagID: $0.tagID
                )
            }
            errorMessage = nil
            broadcast()
        case let event as OverviewTagSetRequested:
            logger.log(
                "overview-actor received overview-tag-set-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) overviewID=\(event.overviewID, privacy: .public) tagID=\(event.tagID, privacy: .public)"
            )
            guard let existingOverview = overviews.first(where: { $0.id == event.overviewID }) else {
                return
            }

            overviews = overviews.map {
                guard $0.id == existingOverview.id else {
                    return $0
                }

                return LoadedOverview(
                    id: $0.id,
                    title: $0.title,
                    summary: $0.summary,
                    editedDuration: $0.editedDuration,
                    tagID: event.tagID
                )
            }
            errorMessage = nil
            broadcast()
        case let event as OverviewMergeRequested:
            logger.log(
                "overview-actor received overview-merge-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) overviewID=\(event.overviewID, privacy: .public) otherOverviewID=\(event.otherOverviewID, privacy: .public)"
            )
            let mergeKey = [event.overviewID, event.otherOverviewID].sorted().map(String.init).joined(separator: "-")

            guard pendingOverviewMergeKeys.insert(mergeKey).inserted else {
                logger.log(
                    "overview-actor skipped duplicate overview-merge-requested overviewID=\(event.overviewID, privacy: .public) otherOverviewID=\(event.otherOverviewID, privacy: .public)"
                )
                return
            }

            guard event.overviewID != event.otherOverviewID,
                  let firstOverview = overviews.first(where: { $0.id == event.overviewID }),
                  let secondOverview = overviews.first(where: { $0.id == event.otherOverviewID }) else {
                pendingOverviewMergeKeys.remove(mergeKey)
                errorMessage = "Could not find both overviews to merge."
                broadcast()
                return
            }

            let activities = await activityActor.snapshot().activities
            let projectedActivities = activities.map { activity in
                (
                    activity,
                    localOverviewAssignments[activity.id] ?? activity.overviewID
                )
            }
            let sortedActivities = projectedActivities.sorted { $0.0.startTime < $1.0.startTime }
            let firstActivityIDs = sortedActivities.filter { $0.1 == event.overviewID }.map { $0.0.id }
            let secondActivityIDs = sortedActivities.filter { $0.1 == event.otherOverviewID }.map { $0.0.id }

            guard !firstActivityIDs.isEmpty, !secondActivityIDs.isEmpty else {
                pendingOverviewMergeKeys.remove(mergeKey)
                errorMessage = "Could not merge overviews without source activities."
                broadcast()
                return
            }

            await actorSystem.broadcast(
                from: nil,
                message: OverviewMergeComputationRequested(
                    mergedOverviewID: await identifierActor.makeIdentifier(),
                    firstOverview: firstOverview,
                    secondOverview: secondOverview,
                    firstDuration: effectiveDuration(
                        for: firstOverview,
                        activities: sortedActivities.map(\.0)
                    ),
                    secondDuration: effectiveDuration(
                        for: secondOverview,
                        activities: sortedActivities.map(\.0)
                    ),
                    activityIDs: firstActivityIDs + secondActivityIDs
                )
            )
        case let event as OverviewDayReloadRequested:
            guard let loadedDay,
                  Calendar(identifier: .gregorian).isDate(loadedDay, inSameDayAs: event.day) else {
                return
            }

            await load(for: event.day)
        case let event as OverviewMergeResolved:
            let mergeKey = [event.firstOverview.id, event.secondOverview.id].sorted().map(String.init).joined(separator: "-")
            logger.log(
                "overview-actor received overview-merge-resolved sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) firstOverviewID=\(event.firstOverview.id, privacy: .public) secondOverviewID=\(event.secondOverview.id, privacy: .public)"
            )
            pendingOverviewMergeKeys.remove(mergeKey)

            guard overviews.contains(where: { $0.id == event.firstOverview.id }),
                  overviews.contains(where: { $0.id == event.secondOverview.id }) else {
                return
            }

            let mergedOverview = LoadedOverview(
                id: event.mergedOverviewID,
                title: event.decision.title ?? event.firstOverview.title ?? event.secondOverview.title,
                summary: event.decision.summary ?? event.firstOverview.summary ?? event.secondOverview.summary,
                editedDuration: event.firstDuration + event.secondDuration,
                tagID: event.firstOverview.tagID == event.secondOverview.tagID ? event.firstOverview.tagID : nil
            )
            let sourceOverviewIDs = [event.firstOverview.id, event.secondOverview.id]
            overviews = overviews
                .filter { !sourceOverviewIDs.contains($0.id) }
                + [mergedOverview]
            event.activityIDs.forEach { activityID in
                localOverviewAssignments[activityID] = mergedOverview.id
            }
            errorMessage = nil
            broadcast()
        case let event as OverviewMergeFailed:
            let mergeKey = [event.firstOverviewID, event.secondOverviewID].sorted().map(String.init).joined(separator: "-")
            logger.error(
                "overview-actor received overview-merge-failed sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) firstOverviewID=\(event.firstOverviewID, privacy: .public) secondOverviewID=\(event.secondOverviewID, privacy: .public) error=\(event.errorMessage, privacy: .public)"
            )
            pendingOverviewMergeKeys.remove(mergeKey)
            errorMessage = "Could not merge the selected overviews."
            broadcast()
        default:
            return
        }
    }

    func load(for date: Date) async {
        do {
            loadedDay = Calendar(identifier: .gregorian).startOfDay(for: date)
            let loadedOverviews = try await overviewDatabaseActor.loadOverviews(for: date)
            overviews = loadedOverviews
            errorMessage = nil
            pendingOverviewMergeKeys = []
            localOverviewAssignments = [:]
            await identifierActor.observeExisting(loadedOverviews.map(\.id).max())
            logger.log("overview load succeeded date=\(date, privacy: .public) count=\(loadedOverviews.count, privacy: .public)")
            broadcast()
        } catch {
            errorMessage = "Could not load overviews for the selected day."
            logger.error("overview load failed date=\(date, privacy: .public) error=\(String(describing: error), privacy: .public)")
            broadcast()
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func broadcast() {
        revision += 1
        let state = snapshot()
        continuations.values.forEach { continuation in
            continuation.yield(state)
        }
    }

    private func effectiveDuration(
        for overview: LoadedOverview,
        activities: [ActivityActor.Activity]
    ) -> Int {
        if let editedDuration = overview.editedDuration {
            return editedDuration
        }

        return activities.enumerated().reduce(into: 0) { total, pair in
            let activity = pair.element

            let projectedOverviewID = localOverviewAssignments[activity.id] ?? activity.overviewID

            guard projectedOverviewID == overview.id, pair.offset < activities.count - 1 else {
                return
            }

            let duration = activities[pair.offset + 1].startTime.timeIntervalSince(activity.startTime)

            if duration > 0 {
                total += Int(duration.rounded())
            }
        }
    }

}
