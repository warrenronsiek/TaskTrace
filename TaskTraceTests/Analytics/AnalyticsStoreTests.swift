//
//  AnalyticsStoreTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/13/26.
//

import Foundation
import Testing
@testable import TaskTrace

@MainActor
struct AnalyticsStoreTests {
    @Test("loading analytics builds day buckets and available tags")
    func loadingAnalyticsBuildsDayBucketsAndAvailableTags() async throws {
        try await withAnalyticsStore { database, analyticsStore in
            try await database.save(.tag(.record(TagInput(
                id: 1,
                name: "Work",
                description: "Billable work.",
                createDate: testAnalyticsDate(day: 1, hour: 0, minute: 0),
                deleteDate: nil,
                jsonProperties: nil
            ))))
            try await seedAnalyticsDay(
                database: database,
                day: 12,
                applications: [
                    (100, 9, 0, "com.apple.dt.Xcode", 1),
                    (101, 10, 0, "com.apple.Safari", nil),
                    (102, 12, 0, "PAUSED", 0)
                ]
            )

            await analyticsStore.load()

            #expect(
                analyticsStore.timeline == [
                    AnalyticsStore.TimelineEntry(
                        date: testAnalyticsDate(day: 12, hour: 0, minute: 0),
                        tags: ["Work": 3_600, AnalyticsStore.untaggedName: 7_200]
                    )
                ] && analyticsStore.availableTags == ["Work", AnalyticsStore.untaggedName]
            )
        }
    }

    @Test("summary metrics match tracked and tagged percentages")
    func summaryMetricsMatchTrackedAndTaggedPercentages() async throws {
        try await withAnalyticsStore { database, analyticsStore in
            try await database.save(.tag(.record(TagInput(
                id: 1,
                name: "Work",
                description: "Billable work.",
                createDate: testAnalyticsDate(day: 1, hour: 0, minute: 0),
                deleteDate: nil,
                jsonProperties: nil
            ))))
            try await seedAnalyticsDay(
                database: database,
                day: 7,
                applications: [
                    (100, 9, 0, "com.apple.dt.Xcode", 1),
                    (101, 17, 0, "PAUSED", 0)
                ]
            )
            try await seedAnalyticsDay(
                database: database,
                day: 13,
                applications: [
                    (102, 9, 0, "com.apple.Safari", nil),
                    (103, 11, 0, "PAUSED", 0)
                ]
            )

            await analyticsStore.load()

            #expect(analyticsStore.summaryMetrics == .init(trackedPercentage: 0.25, taggedPercentage: 0.8))
        }
    }

    @Test("selected tags narrows heatmap and bar durations")
    func selectedTagsNarrowsHeatmapAndBarDurations() async throws {
        try await withAnalyticsStore { database, analyticsStore in
            try await database.save(.tag(.record(TagInput(
                id: 1,
                name: "Work",
                description: "Billable work.",
                createDate: testAnalyticsDate(day: 1, hour: 0, minute: 0),
                deleteDate: nil,
                jsonProperties: nil
            ))))
            try await database.save(.tag(.record(TagInput(
                id: 2,
                name: "Research",
                description: "Research work.",
                createDate: testAnalyticsDate(day: 1, hour: 0, minute: 0),
                deleteDate: nil,
                jsonProperties: nil
            ))))
            try await seedAnalyticsDay(
                database: database,
                day: 13,
                applications: [
                    (100, 9, 0, "com.apple.dt.Xcode", 1),
                    (101, 10, 0, "com.apple.Safari", 2),
                    (102, 11, 0, "PAUSED", 0)
                ]
            )

            await analyticsStore.load()
            analyticsStore.toggleTagFilter("Work")
            analyticsStore.toggleTagFilter("Research")

            let barsByTag = analyticsStore.barSegments.reduce(into: [String: Int]()) { result, segment in
                result[segment.tag, default: 0] += segment.duration
            }

            #expect(
                analyticsStore.heatmapDays.last?.duration == 7_200
                    && barsByTag == ["Work": 3_600, "Research": 3_600]
            )
        }
    }

    @Test("bar chart tags exclude untagged")
    func barChartTagsExcludeUntagged() async throws {
        try await withAnalyticsStore { database, analyticsStore in
            try await database.save(.tag(.record(TagInput(
                id: 1,
                name: "Work",
                description: "Billable work.",
                createDate: testAnalyticsDate(day: 1, hour: 0, minute: 0),
                deleteDate: nil,
                jsonProperties: nil
            ))))
            try await seedAnalyticsDay(
                database: database,
                day: 13,
                applications: [
                    (100, 9, 0, "com.apple.dt.Xcode", 1),
                    (101, 10, 0, "com.apple.Safari", nil)
                ]
            )

            await analyticsStore.load()

            #expect(analyticsStore.barChartTags == ["Work"])
        }
    }

    @Test("bar chart tags exclude inactive")
    func barChartTagsExcludeInactive() async throws {
        try await withAnalyticsStore { database, analyticsStore in
            try await database.save(.tag(.record(TagInput(
                id: 2,
                name: "Work",
                description: "Billable work.",
                createDate: testAnalyticsDate(day: 1, hour: 0, minute: 0),
                deleteDate: nil,
                jsonProperties: nil
            ))))
            try await seedAnalyticsDay(
                database: database,
                day: 13,
                applications: [
                    (100, 9, 0, "com.apple.dt.Xcode", SystemTags.inactiveID),
                    (101, 10, 0, "com.apple.Safari", 2)
                ]
            )

            await analyticsStore.load()

            #expect(analyticsStore.barChartTags == ["Work"])
        }
    }
}

@MainActor
private func withAnalyticsStore(
    _ block: (TaskTraceDatabase, AnalyticsStore) async throws -> Void
) async throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
    let clock = AnalyticsStoreTestClock(current: testAnalyticsDate(day: 13, hour: 12, minute: 0))

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

    try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
    let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
    let analyticsStore = AnalyticsStore(
        database: database,
        now: { clock.current },
        calendar: Calendar(identifier: .gregorian)
    )

    try await block(database, analyticsStore)
}

private func seedAnalyticsDay(
    database: TaskTraceDatabase,
    day: Int,
    applications: [(Int64, Int, Int, String, Int64?)]
) async throws {
    try await applications.asyncForEach { item in
        try await database.saveActivityRecord(ActivityInput(
            id: item.0,
            startTime: testAnalyticsDate(day: day, hour: item.1, minute: item.2),
            application: item.3,
            keystrokes: "",
            microphone: nil,
            summary: "Activity",
            tagID: item.4,
            jsonProperties: nil,
            overviewID: nil
        ))
    }
}

private final class AnalyticsStoreTestClock: @unchecked Sendable {
    var current: Date

    init(current: Date) {
        self.current = current
    }
}

private func testAnalyticsDate(day: Int, hour: Int, minute: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute)
    ) ?? .distantPast
}

private extension Sequence {
    func asyncForEach(
        _ operation: (Element) async throws -> Void
    ) async throws {
        for element in self {
            try await operation(element)
        }
    }
}
