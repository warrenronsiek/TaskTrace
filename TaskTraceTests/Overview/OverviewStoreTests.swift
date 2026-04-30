//
//  OverviewStoreTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/13/26.
//

import Foundation
import GRDB
import MLXLMCommon
import Testing
@testable import TaskTrace

@MainActor
struct OverviewStoreTests {
    @Test("activity tag assignment writes the overview link before generated text completes")
    func activityTagAssignmentWritesTheOverviewLinkBeforeGeneratedTextCompletes() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
        let actorSystem = ActorSystem()
        let textResponder = DelayedOverviewTextResponder(delay: .seconds(1))

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let overviewDatabaseActor = OverviewDatabaseActor(database: database)
        let overviewActor = OntologyOverviewActor(
            actorSystem: actorSystem,
            overviewDatabaseActor: overviewDatabaseActor,
            textResponder: textResponder,
            debounceNanoseconds: 0
        )
        let day = testDate(hour: 9, minute: 0)

        try await database.save(.tag(.record(TagInput(
            id: 55,
            name: "work",
            description: "Work",
            createDate: testDate(hour: 0, minute: 0),
            deleteDate: nil,
            jsonProperties: nil
        ))))
        try await database.saveActivityRecord(ActivityInput(
            id: 700,
            startTime: day,
            application: "com.apple.dt.Xcode",
            keystrokes: nil,
            microphone: nil,
            summary: "Reviewed the linked activities for the daily overview.",
            tagID: 55,
            jsonProperties: nil,
            overviewID: nil
        ))

        _ = await actorSystem.register(overviewActor)

        await actorSystem.broadcast(
            from: nil,
            message: ActivityTagAssigned(activityID: 700, tagID: 55, ontologyCandidateID: 900)
        )

        try await waitUntil {
            let row = try database.read { db in
                try Row.fetchOne(
                    db,
                    sql: """
                        SELECT overview_id, generated_title
                        FROM activities
                        JOIN overviews ON overviews.id = activities.overview_id
                        WHERE activities.id = ?
                        """,
                    arguments: [700]
                )
            }

            return ((row?["overview_id"] as Int64?) != nil)
                && ((row?["generated_title"] as String?) == nil)
        }
    }

    @Test("loading the active day exposes persisted overviews")
    func loadingTheActiveDayExposesPersistedOverviews() async throws {
        try await withStore { database, activityStore, overviewStore, _, _, _ in
            try await database.saveOverviewRecord(OverviewInput(
                id: 200,
                title: "Development",
                summary: "Worked in Xcode.",
                jsonProperties: nil,
                editedDuration: 600,
                tagID: 1
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 100,
                startTime: testDate(hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: "abc",
                microphone: nil,
                summary: "Worked in Xcode.",
                tagID: 1,
                jsonProperties: nil,
                overviewID: 200
            ))

            await activityStore.loadActiveDay()
            await overviewStore.loadActiveDay()

            #expect(overviewStore.overviews.first?.title == "Development")
        }
    }

    @Test("refresh reloads newly persisted overviews")
    func refreshReloadsNewlyPersistedOverviews() async throws {
        try await withStore { database, activityStore, overviewStore, _, _, _ in
            try await database.saveActivityRecord(ActivityInput(
                id: 100,
                startTime: testDate(hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: "abc",
                microphone: nil,
                summary: "Worked in Xcode.",
                tagID: 1,
                jsonProperties: nil,
                overviewID: nil
            ))

            await activityStore.loadActiveDay()
            await overviewStore.loadActiveDay()
            try await database.saveOverviewRecord(OverviewInput(
                id: 200,
                title: "Development",
                summary: "Worked in Xcode.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: 1
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 100,
                startTime: testDate(hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: "abc",
                microphone: nil,
                summary: "Worked in Xcode.",
                tagID: 1,
                jsonProperties: nil,
                overviewID: 200
            ))

            await overviewStore.refresh()

            #expect(overviewStore.overviews.map(\.title) == ["Development"])
        }
    }

    @Test("refresh preserves existing overview assignments from the database")
    func refreshPreservesExistingOverviewAssignmentsFromTheDatabase() async throws {
        try await withStore { database, activityStore, overviewStore, _, _, _ in
            try await database.saveOverviewRecord(OverviewInput(
                id: 200,
                title: "Development",
                summary: "Worked in Xcode.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: 1
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 90,
                startTime: testDate(hour: 8, minute: 0),
                application: "com.apple.Terminal",
                keystrokes: "",
                microphone: nil,
                summary: "Worked in Xcode.",
                tagID: 1,
                jsonProperties: nil,
                overviewID: 200
            ))

            await activityStore.loadActiveDay()
            await overviewStore.refresh()

            #expect(overviewStore.overviews.map(\.id) == [200])
        }
    }

    @Test("refresh does not synthesize overviews for unsummarized activities")
    func refreshDoesNotSynthesizeOverviewsForUnsummarizedActivities() async throws {
        try await withStore { database, activityStore, overviewStore, _, _, _ in
            try await database.saveActivityRecord(ActivityInput(
                id: 100,
                startTime: testDate(hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: "abc",
                microphone: nil,
                summary: nil,
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await database.saveScreenshotRecord(activityID: 100, screenshot: ScreenshotInput(
                id: 101,
                image: Data("img".utf8),
                timestamp: testDate(hour: 9, minute: 0),
                description: nil,
                text: nil,
                ignoreReason: nil,
                jsonProperties: nil
            ))

            await activityStore.loadActiveDay()
            await overviewStore.refresh()

            #expect(overviewStore.overviews.isEmpty)
        }
    }

    @Test("setting an overview tag updates all linked activities")
    func settingAnOverviewTagUpdatesAllLinkedActivities() async throws {
        try await withStore { database, activityStore, overviewStore, _, _, _ in
            try await database.saveOverviewRecord(OverviewInput(
                id: 200,
                title: "Development",
                summary: "Worked in Xcode.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: 1
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 100,
                startTime: testDate(hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: "abc",
                microphone: nil,
                summary: "Worked in Xcode.",
                tagID: 1,
                jsonProperties: nil,
                overviewID: 200
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 110,
                startTime: testDate(hour: 10, minute: 0),
                application: "com.apple.TextEdit",
                keystrokes: "def",
                microphone: nil,
                summary: "Worked in Xcode.",
                tagID: 1,
                jsonProperties: nil,
                overviewID: 200
            ))

            await activityStore.loadActiveDay()
            await overviewStore.loadActiveDay()
            await overviewStore.setTag(overviewID: 200, tagID: 55)

            let tagIDs = try await database.loadState(for: testDate(hour: 0, minute: 0)).activity.map(\.tagID)
            #expect(tagIDs == [55, 55])
        }
    }

    @Test("merging two overviews creates one merged overview and reassigns their activities")
    func mergingTwoOverviewsCreatesOneMergedOverviewAndReassignsTheirActivities() async throws {
        try await withStore { database, activityStore, overviewStore, _, _, textScheduler in
            await textScheduler.setResponse(
                source: "overview-merge",
                response: """
                TITLE: TaskTrace product work
                SUMMARY: Built and refined TaskTrace work across desktop and analytics.
                """
            )
            try await database.saveOverviewRecord(OverviewInput(
                id: 200,
                title: "TaskTrace desktop development",
                summary: "Built desktop recording flows.",
                jsonProperties: nil,
                editedDuration: 600,
                tagID: 1
            ))
            try await database.saveOverviewRecord(OverviewInput(
                id: 300,
                title: "TaskTrace analytics polish",
                summary: "Refined analytics and overview summaries.",
                jsonProperties: nil,
                editedDuration: 900,
                tagID: 1
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 100,
                startTime: testDate(hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: "abc",
                microphone: nil,
                summary: "Built desktop recording flows.",
                tagID: 1,
                jsonProperties: nil,
                overviewID: 200
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 110,
                startTime: testDate(hour: 10, minute: 0),
                application: "com.apple.TextEdit",
                keystrokes: "def",
                microphone: nil,
                summary: "Refined analytics and overview summaries.",
                tagID: 1,
                jsonProperties: nil,
                overviewID: 300
            ))

            await activityStore.loadActiveDay()
            await overviewStore.loadActiveDay()
            try await waitUntil {
                overviewStore.overviews.count == 2
                    && activityStore.state.activities.count == 2
            }
            await overviewStore.mergeOverviews(overviewID: 200, with: 300)

            let mergedOverview = try #require(overviewStore.overviews.first)

            #expect(overviewStore.overviews.count == 1)
            #expect(mergedOverview.title == "TaskTrace product work")
            #expect(mergedOverview.editedDuration == 1500)
            #expect(Set(activityStore.state.activities.compactMap(\.overviewID)) == Set([mergedOverview.id]))
        }
    }

    @Test("reloading after merging overviews preserves the merged overview and all child assignments")
    func reloadingAfterMergingOverviewsPreservesTheMergedOverviewAndAllChildAssignments() async throws {
        try await withStore { database, activityStore, overviewStore, _, _, textScheduler in
            await textScheduler.setResponse(
                source: "overview-merge",
                response: """
                TITLE: TaskTrace product work
                SUMMARY: Built and refined TaskTrace work across desktop and analytics.
                """
            )
            try await database.saveOverviewRecord(OverviewInput(
                id: 200,
                title: "TaskTrace desktop development",
                summary: "Built desktop recording flows.",
                jsonProperties: nil,
                editedDuration: 600,
                tagID: 1
            ))
            try await database.saveOverviewRecord(OverviewInput(
                id: 300,
                title: "TaskTrace analytics polish",
                summary: "Refined analytics and overview summaries.",
                jsonProperties: nil,
                editedDuration: 900,
                tagID: 1
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 100,
                startTime: testDate(hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: "abc",
                microphone: nil,
                summary: "Built desktop recording flows.",
                tagID: 1,
                jsonProperties: nil,
                overviewID: 200
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 110,
                startTime: testDate(hour: 10, minute: 0),
                application: "com.apple.TextEdit",
                keystrokes: "def",
                microphone: nil,
                summary: "Refined analytics and overview summaries.",
                tagID: 1,
                jsonProperties: nil,
                overviewID: 300
            ))

            await activityStore.loadActiveDay()
            await overviewStore.loadActiveDay()
            try await waitUntil {
                overviewStore.overviews.count == 2
                    && activityStore.state.activities.count == 2
            }
            await overviewStore.mergeOverviews(overviewID: 200, with: 300)
            for _ in 0..<100 {
                let state = try await database.loadState(for: testDate(hour: 0, minute: 0))
                if state.overview.count == 1,
                   let mergedOverviewID = state.overview.first?.id,
                   Set(state.activity.compactMap(\.overviewID)) == Set([mergedOverviewID]) {
                    break
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            await activityStore.loadActiveDay()
            await overviewStore.loadActiveDay()

            let mergedOverview = try #require(overviewStore.overviews.first)
            let state = try await database.loadState(for: testDate(hour: 0, minute: 0))

            #expect((overviewStore.overviews.count, Set(state.activity.compactMap(\.overviewID)), Set(state.overview.map(\.id))) == (1, Set([mergedOverview.id]), Set([mergedOverview.id])))
        }
    }
}

@MainActor
private func withStore(
    _ block: (
        TaskTraceDatabase,
        ActivityStore,
        OverviewStore,
        FakeActivityAI,
        FakeCaptureMonitor,
        FakeOverviewTextScheduler
    ) async throws -> Void
) async throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
    let clock = OverviewStoreTestClock(current: testDate(hour: 12, minute: 0))
    let monitor = FakeCaptureMonitor()

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

    let activityAI = FakeActivityAI()
    try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
    let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: activityAI)
    try await database.save(.tag(.record(TagInput(
        id: 1,
        name: "work",
        description: "Work",
        createDate: testDate(hour: 0, minute: 0),
        deleteDate: nil,
        jsonProperties: nil
    ))))
    try await database.save(.tag(.record(TagInput(
        id: 55,
        name: "finance",
        description: "Finance",
        createDate: testDate(hour: 0, minute: 0),
        deleteDate: nil,
        jsonProperties: nil
    ))))
    let actorSystem = ActorSystem()
    let textScheduler = FakeOverviewTextScheduler(actorSystem: actorSystem)
    let activityDatabaseActor = ActivityDatabaseActor(database: database)
    let overviewDatabaseActor = OverviewDatabaseActor(database: database)
    let actor = ActivityActor(
        activityDatabaseActor: activityDatabaseActor,
        actorSystem: actorSystem,
        now: { clock.current }
    )
    await ActivityScreenshotPipelineBootstrap.register(
        actorSystem: actorSystem,
        activityActor: actor,
        activityDatabaseActor: activityDatabaseActor,
        dependencies: ActivityWorkerDependencies(activityAI: activityAI)
    )
    let overviewActor = OverviewActor(
        overviewDatabaseActor: overviewDatabaseActor,
        activityActor: actor,
        actorSystem: actorSystem,
        now: { clock.current }
    )
    await OverviewPipelineBootstrap.register(
        actorSystem: actorSystem,
        overviewActor: overviewActor,
        overviewDatabaseActor: overviewDatabaseActor,
        dependencies: ActivityWorkerDependencies(
            makeActivityEmbeddingActor: { actorSystem in
                ActivityEmbeddingActor(
                    actorSystem: actorSystem,
                    embeddingGenerator: activityAI
                )
            },
            makeDescribeImageActor: { DescribeImageActor(actorSystem: $0, imageDescriber: activityAI) },
            makeReadScreenshotTextActor: { ReadScreenshotTextActor(actorSystem: $0, screenshotTextRecognizer: activityAI) },
            makeSummarizeScreenshotActor: { SummarizeScreenshotActor(actorSystem: $0, screenshotSummarizer: activityAI) },
            makeSummarizeActivityActor: { SummarizeActivityActor(actorSystem: $0, summarizer: activityAI) },
            makeActivityTagOntologyActor: { ActivityTagOntologyActor(actorSystem: $0, activityDatabaseActor: $1) },
            makeOntologyOverviewActor: { OntologyOverviewActor(actorSystem: $0, overviewDatabaseActor: $1) },
            makeMergeOverviewsActor: { MergeOverviewsActor(actorSystem: $0) }
        )
    )
    _ = await actorSystem.register(textScheduler)
    let activityStore = ActivityStore(
        activityActor: actor,
        actorSystem: actorSystem,
        captureMonitor: monitor,
        initialState: .init(),
        activeDay: clock.current,
        isRecording: false,
        now: { clock.current },
        calendar: Calendar(identifier: .gregorian)
    )
    let overviewStore = OverviewStore(overviewActor: overviewActor, actorSystem: actorSystem, activityStore: activityStore)

    try await block(database, activityStore, overviewStore, activityAI, monitor, textScheduler)
}

private func testDate(hour: Int, minute: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 3, day: 13, hour: hour, minute: minute)
    ) ?? .distantPast
}

private func waitUntil(
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(10),
    _ predicate: @escaping () async throws -> Bool
) async throws {
    let start = ContinuousClock.now

    while ContinuousClock.now - start < timeout {
        if try await predicate() {
            return
        }

        try await Task.sleep(for: pollInterval)
    }

    Issue.record("timed out waiting for asynchronous test condition")
}

@MainActor
private final class FakeCaptureMonitor: CaptureMonitoring {
    func start() {}
    func stop() {}
}

private actor FakeOverviewTextScheduler: Receiver {
    private let actorSystem: ActorSystem
    private var responsesBySource = [
        "overview-merge": """
        TITLE: Merged Overview
        SUMMARY: Merged overview summary.
        """,
        "ontology-overview-summary": """
        Title: Generated Overview
        Summary: Generated overview summary.
        """
    ]

    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    func setResponse(source: String, response: String) {
        responsesBySource[source] = response
    }

    func receive(_ envelope: Envelope) async {
        guard let request = envelope.message as? ModelTextRequest else {
            return
        }

        let now = Date()
        await actorSystem.broadcast(
            from: nil,
            message: ModelTextCompleted(
                requestID: request.requestID,
                response: responsesBySource[request.source] ?? "",
                schedulerMetadata: AISchedulerMetadata(
                    scheduler: .textBig,
                    bucket: "test",
                    batchSize: 1,
                    source: request.source
                ),
                timing: AISchedulerTiming(
                    queuedAt: now,
                    startedAt: now,
                    finishedAt: now
                )
            )
        )
    }
}

private actor DelayedOverviewTextResponder: AITextResponding {
    private let delay: Duration

    init(delay: Duration) {
        self.delay = delay
    }

    func respond(
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        additionalContext: [String: any Sendable]?
    ) async throws -> String {
        try await Task.sleep(for: delay)

        return """
        Title: Delayed Overview
        Summary: Delayed overview summary.
        """
    }
}

private final class OverviewStoreTestClock: @unchecked Sendable {
    var current: Date

    init(current: Date) {
        self.current = current
    }
}
