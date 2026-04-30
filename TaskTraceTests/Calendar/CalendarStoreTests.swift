//
//  CalendarStoreTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/13/26.
//

import Foundation
import Testing
@testable import TaskTrace

@MainActor
struct CalendarStoreTests {
    @Test("loading calendar dates includes stored activity days")
    func loadingCalendarDatesIncludesStoredActivityDays() async throws {
        try await withStore { database, calendarStore, _, _ in
            try await database.saveActivityRecord(ActivityInput(
                id: 100,
                startTime: testDate(day: 12, hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: "",
                microphone: nil,
                summary: "Worked in Xcode.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            await calendarStore.loadAvailableDates()

            #expect(calendarStore.availableDates.contains(testDate(day: 12, hour: 0, minute: 0)))
        }
    }

    @Test("loading calendar dates includes historical activity days beyond one year")
    func loadingCalendarDatesIncludesHistoricalActivityDaysBeyondOneYear() async throws {
        try await withStore { database, calendarStore, _, _ in
            try await database.saveActivityRecord(ActivityInput(
                id: 100,
                startTime: testDate(year: 2024, month: 10, day: 5, hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: "",
                microphone: nil,
                summary: "Worked in Xcode.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            await calendarStore.loadAvailableDates()

            #expect(calendarStore.availableDates.contains(testDate(year: 2024, month: 10, day: 5, hour: 0, minute: 0)))
        }
    }

    @Test("loading calendar dates tracks the earliest visible month with activity")
    func loadingCalendarDatesTracksTheEarliestVisibleMonthWithActivity() async throws {
        try await withStore { database, calendarStore, _, _ in
            try await database.saveActivityRecord(ActivityInput(
                id: 100,
                startTime: testDate(year: 2024, month: 10, day: 5, hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: "",
                microphone: nil,
                summary: "Worked in Xcode.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 101,
                startTime: testDate(day: 12, hour: 9, minute: 0),
                application: "com.apple.Safari",
                keystrokes: "",
                microphone: nil,
                summary: "Browsed docs.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            await calendarStore.loadAvailableDates()

            #expect(calendarStore.earliestVisibleMonth == testDate(year: 2024, month: 10, day: 1, hour: 0, minute: 0))
        }
    }

    @Test("selecting a day loads that day's activity and overview state")
    func selectingADayLoadsThatDaysActivityAndOverviewState() async throws {
        try await withStore { database, calendarStore, activityStore, overviewStore in
            try await database.saveOverviewRecord(OverviewInput(
                id: 200,
                title: "Development",
                summary: "Worked in Xcode.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 100,
                startTime: testDate(day: 12, hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: "",
                microphone: nil,
                summary: "Worked in Xcode.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 200
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 101,
                startTime: testDate(day: 13, hour: 9, minute: 0),
                application: "com.apple.Safari",
                keystrokes: "",
                microphone: nil,
                summary: "Browsed docs.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            await calendarStore.loadAvailableDates()
            await calendarStore.setSelectedDate(testDate(day: 12, hour: 0, minute: 0))

            #expect((activityStore.activeDay, activityStore.state.activities.first?.id, overviewStore.overviews.first?.id) == (testDate(day: 12, hour: 0, minute: 0), 100, 200))
        }
    }

    @Test("timeline blocks merge adjacent activities with the same overview")
    func timelineBlocksMergeAdjacentActivitiesWithTheSameOverview() async throws {
        try await withStore { database, calendarStore, _, _ in
            try await database.saveOverviewRecord(OverviewInput(
                id: 200,
                title: "Development",
                summary: "Worked in Xcode.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 100,
                startTime: testDate(day: 13, hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: "",
                microphone: nil,
                summary: "Worked in Xcode.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 200
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 101,
                startTime: testDate(day: 13, hour: 10, minute: 0),
                application: "com.apple.Terminal",
                keystrokes: "",
                microphone: nil,
                summary: "Worked in Xcode.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 200
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 102,
                startTime: testDate(day: 13, hour: 11, minute: 0),
                application: "com.apple.Safari",
                keystrokes: "",
                microphone: nil,
                summary: "Browsed docs.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            await calendarStore.loadAvailableDates()
            await calendarStore.setSelectedDate(testDate(day: 13, hour: 0, minute: 0))

            #expect(calendarStore.timelineBlocks.map(\.activityIDs) == [[100, 101], [102]])
        }
    }

    @Test("dates without stored activity stay unavailable")
    func datesWithoutStoredActivityStayUnavailable() async throws {
        try await withStore { database, calendarStore, _, _ in
            try await database.saveActivityRecord(ActivityInput(
                id: 100,
                startTime: testDate(day: 12, hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: "",
                microphone: nil,
                summary: "Worked in Xcode.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            await calendarStore.loadAvailableDates()

            #expect(calendarStore.isAvailable(testDate(day: 11, hour: 0, minute: 0)) == false)
        }
    }

    @Test("today stays available without stored activity")
    func todayStaysAvailableWithoutStoredActivity() async throws {
        try await withStore { _, calendarStore, _, _ in
            await calendarStore.loadAvailableDates()

            #expect(calendarStore.isAvailable(testDate(day: 13, hour: 0, minute: 0)))
        }
    }
}

@MainActor
private func withStore(
    _ block: (TaskTraceDatabase, CalendarStore, ActivityStore, OverviewStore) async throws -> Void
) async throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
    let clock = CalendarStoreTestClock(current: testDate(day: 13, hour: 12, minute: 0))
    let monitor = CalendarStoreCaptureMonitor()

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

    let activityAI = FakeActivityAI()
    try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
    let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: activityAI)
    let actorSystem = ActorSystem()
    let activityDatabaseActor = ActivityDatabaseActor(database: database)
    let overviewDatabaseActor = OverviewDatabaseActor(database: database)
    let activityActor = ActivityActor(
        activityDatabaseActor: activityDatabaseActor,
        actorSystem: actorSystem,
        now: { clock.current }
    )
    await ActivityScreenshotPipelineBootstrap.register(
        actorSystem: actorSystem,
        activityActor: activityActor,
        activityDatabaseActor: activityDatabaseActor,
        dependencies: ActivityWorkerDependencies(activityAI: activityAI)
    )
    let overviewActor = OverviewActor(
        overviewDatabaseActor: overviewDatabaseActor,
        activityActor: activityActor,
        actorSystem: actorSystem,
        now: { clock.current }
    )
    await OverviewPipelineBootstrap.register(
        actorSystem: actorSystem,
        overviewActor: overviewActor,
        overviewDatabaseActor: overviewDatabaseActor,
        dependencies: ActivityWorkerDependencies(activityAI: activityAI)
    )
    let activityStore = ActivityStore(
        activityActor: activityActor,
        actorSystem: actorSystem,
        captureMonitor: monitor,
        initialState: .init(),
        activeDay: clock.current,
        isRecording: false,
        now: { clock.current },
        calendar: Calendar(identifier: .gregorian)
    )
    let overviewStore = OverviewStore(overviewActor: overviewActor, actorSystem: actorSystem, activityStore: activityStore)
    let calendarStore = CalendarStore(
        calendarDatabaseActor: CalendarDatabaseActor(database: database),
        activityStore: activityStore,
        overviewStore: overviewStore,
        now: { clock.current },
        calendar: Calendar(identifier: .gregorian)
    )

    try await block(database, calendarStore, activityStore, overviewStore)
}

@MainActor
private final class CalendarStoreCaptureMonitor: CaptureMonitoring {
    func start() {}
    func stop() {}
}

private final class CalendarStoreTestClock: @unchecked Sendable {
    var current: Date

    init(current: Date) {
        self.current = current
    }
}

private func testDate(day: Int, hour: Int, minute: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute)
    ) ?? .distantPast
}

private func testDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    ) ?? .distantPast
}
