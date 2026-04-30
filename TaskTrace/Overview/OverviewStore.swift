//
//  OverviewStore.swift
//  TaskTrace
//
//  Created by Codex on 3/13/26.
//

import Combine
import Foundation

@MainActor
final class OverviewStore: ObservableObject {
    struct Overview: Identifiable, Equatable {
        let id: Int64
        var title: String?
        var summary: String?
        var editedDuration: Int?
        var tagID: Int64?
    }

    @Published private(set) var overviews: [Overview]
    @Published private(set) var errorMessage: String?

    private let overviewActor: OverviewActor?
    private let actorSystem: ActorSystem?
    private let activityStore: ActivityStore?
    private var updatesTask: Task<Void, Never>?
    private var latestAppliedRevision: Int

    init(overviewActor: OverviewActor, actorSystem: ActorSystem, activityStore: ActivityStore) {
        self.overviewActor = overviewActor
        self.actorSystem = actorSystem
        self.activityStore = activityStore
        self.overviews = []
        self.errorMessage = nil
        self.latestAppliedRevision = -1
        self.updatesTask = Task { @MainActor in
            let updates = await overviewActor.updates()

            for await state in updates {
                self.applyOverviewState(state)
            }
        }
    }

    init(previewOverviews: [Overview]) {
        self.overviewActor = nil
        self.actorSystem = nil
        self.activityStore = nil
        self.overviews = previewOverviews
        self.errorMessage = nil
        self.updatesTask = nil
        self.latestAppliedRevision = -1
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadActiveDay() async {
        guard let overviewActor, let activityStore else {
            return
        }

        await overviewActor.load(for: activityStore.activeDay)
        applyOverviewState(await overviewActor.snapshot())
    }

    func refresh() async {
        await loadActiveDay()
    }

    func setEditedDuration(overviewID: Int64, duration: Int) async {
        guard let actorSystem else {
            return
        }

        await actorSystem.broadcast(
            from: nil,
            message: OverviewEditedDurationSetRequested(
                overviewID: overviewID,
                duration: duration
            )
        )
    }

    func setTitle(overviewID: Int64, title: String) async {
        guard let actorSystem else {
            return
        }

        await actorSystem.broadcast(
            from: nil,
            message: OverviewTitleSetRequested(
                overviewID: overviewID,
                title: title
            )
        )
    }

    func setSummary(overviewID: Int64, summary: String) async {
        guard let actorSystem else {
            return
        }

        await actorSystem.broadcast(
            from: nil,
            message: OverviewSummarySetRequested(
                overviewID: overviewID,
                summary: summary
            )
        )
    }

    func setTag(overviewID: Int64, tagID: Int64) async {
        guard let actorSystem else {
            return
        }

        await actorSystem.broadcast(
            from: nil,
            message: OverviewTagSetRequested(
                overviewID: overviewID,
                tagID: tagID
            )
        )
    }

    func mergeOverviews(overviewID: Int64, with otherOverviewID: Int64) async {
        guard let overviewActor, let actorSystem else {
            return
        }

        await actorSystem.broadcast(
            from: nil,
            message: OverviewMergeRequested(
                overviewID: overviewID,
                otherOverviewID: otherOverviewID
            )
        )

        let sourceOverviewIDs = Set([overviewID, otherOverviewID])

        while errorMessage == nil {
            let state = await overviewActor.snapshot()
            applyOverviewState(state)

            let hasActorSourceOverview = state.overviews.contains { sourceOverviewIDs.contains($0.id) }
            let hasPublishedSourceOverview = overviews.contains { sourceOverviewIDs.contains($0.id) }
            let hasPublishedSourceActivity = activityStore?.state.activities.contains { activity in
                guard let overviewID = activity.overviewID else {
                    return false
                }

                return sourceOverviewIDs.contains(overviewID)
            } == true

            guard hasActorSourceOverview || hasPublishedSourceOverview || hasPublishedSourceActivity else {
                return
            }

            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func sourceActivities(for overviewID: Int64) -> [ActivityActor.Activity] {
        activityStore?.state.activities
            .filter { $0.overviewID == overviewID }
            .sorted { $0.startTime > $1.startTime } ?? []
    }

    func displayIndex(for activityID: Int64) -> Int? {
        activityStore?.state.activities
            .sorted { $0.startTime > $1.startTime }
            .firstIndex(where: { $0.id == activityID })
            .map { $0 + 1 }
    }

    func effectiveDuration(for overviewID: Int64) -> Int {
        guard let overview = overviews.first(where: { $0.id == overviewID }) else {
            return 0
        }

        if let editedDuration = overview.editedDuration {
            return editedDuration
        }

        let activities = activityStore?.state.activities.sorted { $0.startTime < $1.startTime } ?? []
        return activities.enumerated().reduce(into: 0) { total, pair in
            let activity = pair.element

            guard activity.overviewID == overviewID, pair.offset < activities.count - 1 else {
                return
            }

            let duration = activities[pair.offset + 1].startTime.timeIntervalSince(activity.startTime)

            if duration > 0 {
                total += Int(duration.rounded())
            }
        }
    }

    private func applyOverviewState(_ state: OverviewActor.State) {
        guard state.revision >= latestAppliedRevision else {
            return
        }

        latestAppliedRevision = state.revision
        overviews = state.overviews.map { overview in
            Overview(
                id: overview.id,
                title: overview.title,
                summary: overview.summary,
                editedDuration: overview.editedDuration,
                tagID: overview.tagID
            )
        }
        errorMessage = state.errorMessage
    }
}
