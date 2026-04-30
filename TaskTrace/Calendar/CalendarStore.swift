//
//  CalendarStore.swift
//  TaskTrace
//
//  Created by Codex on 3/13/26.
//

import Combine
import Foundation

@MainActor
final class CalendarStore: ObservableObject {
    struct TimelineBlock: Identifiable, Equatable {
        let id: Int64
        let title: String
        let overviewID: Int64?
        let activityIDs: [Int64]
        let startSecond: Int
        let endSecond: Int
    }

    @Published private(set) var availableDates: [Date]
    @Published private(set) var earliestVisibleMonth: Date?
    @Published private(set) var isLoading: Bool

    private let calendarDatabaseActor: CalendarDatabaseActor?
    private let activityStore: ActivityStore?
    private let overviewStore: OverviewStore?
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    convenience init(database: TaskTraceDatabase, activityStore: ActivityStore, overviewStore: OverviewStore) {
        self.init(
            calendarDatabaseActor: CalendarDatabaseActor(database: database),
            activityStore: activityStore,
            overviewStore: overviewStore,
            now: Date.init,
            calendar: Calendar(identifier: .gregorian)
        )
    }

    init(
        calendarDatabaseActor: CalendarDatabaseActor?,
        activityStore: ActivityStore?,
        overviewStore: OverviewStore?,
        now: @escaping @Sendable () -> Date,
        calendar: Calendar
    ) {
        self.calendarDatabaseActor = calendarDatabaseActor
        self.activityStore = activityStore
        self.overviewStore = overviewStore
        self.availableDates = []
        self.earliestVisibleMonth = nil
        self.isLoading = false
        self.now = now
        self.calendar = calendar
    }

    init(
        previewAvailableDates: [Date],
        activityStore: ActivityStore,
        overviewStore: OverviewStore
    ) {
        self.calendarDatabaseActor = nil
        self.activityStore = activityStore
        self.overviewStore = overviewStore
        self.availableDates = previewAvailableDates
        self.earliestVisibleMonth = previewAvailableDates
            .min()
            .flatMap { Calendar(identifier: .gregorian).dateInterval(of: .month, for: $0)?.start }
        self.isLoading = false
        self.now = Date.init
        self.calendar = Calendar(identifier: .gregorian)
    }

    var activeDay: Date {
        activityStore?.activeDay ?? calendar.startOfDay(for: now())
    }

    var selectedDate: Date {
        activeDay
    }

    var startMonth: Date {
        earliestVisibleMonth
            ?? calendar.dateInterval(of: .month, for: now())?.start
            ?? calendar.startOfDay(for: now())
    }

    var timelineBlocks: [TimelineBlock] {
        guard let activityStore else {
            return []
        }

        let activities = activityStore.state.activities.sorted { $0.startTime < $1.startTime }
        let overviewLookup = Dictionary(
            uniqueKeysWithValues: (overviewStore?.overviews ?? []).map { overview in
                (overview.id, overview)
            }
        )

        let rawBlocks = activities.enumerated().compactMap { index, activity -> TimelineBlock? in
            guard activity.application != "SLEEP" else {
                return nil
            }

            let startSecond = secondsSinceStartOfDay(activity.startTime)
            let endDate =
                index < activities.count - 1
                ? activities[index + 1].startTime
                : min(now(), calendar.date(byAdding: .day, value: 1, to: activeDay) ?? now())
            let endSecond = secondsSinceStartOfDay(endDate)

            guard !startSecond.isNaN, !endSecond.isNaN else {
                return nil
            }

            return TimelineBlock(
                id: activity.id,
                title: activity.overviewID.flatMap { overviewLookup[$0]?.title } ?? "",
                overviewID: activity.overviewID,
                activityIDs: [activity.id],
                startSecond: max(0, Int(startSecond)),
                endSecond: max(0, Int(endSecond))
            )
        }

        return rawBlocks.reduce(into: [TimelineBlock]()) { result, block in
            if let last = result.last,
               last.overviewID == block.overviewID,
               last.endSecond == block.startSecond {
                result[result.count - 1] = TimelineBlock(
                    id: last.id,
                    title: last.title.isEmpty ? block.title : last.title,
                    overviewID: last.overviewID,
                    activityIDs: last.activityIDs + block.activityIDs,
                    startSecond: last.startSecond,
                    endSecond: block.endSecond
                )
            } else {
                result.append(block)
            }
        }
    }

    func loadAvailableDates() async {
        guard let calendarDatabaseActor else {
            return
        }

        isLoading = true

        do {
            let renderingData = try await calendarDatabaseActor.loadRenderingData(referenceDate: now())
            availableDates = renderingData.availableDates.sorted()
            earliestVisibleMonth = renderingData.earliestVisibleMonth
        } catch {
            availableDates = [calendar.startOfDay(for: now())]
            earliestVisibleMonth = nil
        }

        isLoading = false
    }

    func setSelectedDate(_ date: Date) async {
        let targetDate = calendar.startOfDay(for: date)

        guard availableDates.contains(targetDate) || calendar.isDate(targetDate, inSameDayAs: now()) else {
            return
        }

        isLoading = true
        await activityStore?.setActiveDay(targetDate)
        await overviewStore?.loadActiveDay()
        isLoading = false
    }

    func isAvailable(_ date: Date) -> Bool {
        let normalizedDate = calendar.startOfDay(for: date)
        return availableDates.contains(normalizedDate) || calendar.isDate(normalizedDate, inSameDayAs: now())
    }

    private func secondsSinceStartOfDay(_ date: Date) -> Double {
        date.timeIntervalSince(calendar.startOfDay(for: date))
    }
}
