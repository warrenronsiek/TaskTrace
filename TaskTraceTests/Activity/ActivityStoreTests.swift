//
//  ActivityStoreTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/12/26.
//

import Foundation
import MLXLMCommon
import Testing
@testable import TaskTrace

@MainActor
struct ActivityStoreTests {
    @Test("recording starts when toggled on for today")
    func recordingStartsWhenToggledOnForToday() async throws {
        try await withStore { store, _, _, monitor in
            await store.toggleRecording()

            #expect((store.isRecording, monitor.startCount) == (true, 1))
        }
    }

    @Test("manual stop appends a paused activity for today")
    func manualStopAppendsAPausedActivityForToday() async throws {
        try await withStore { store, actor, _, _ in
            await store.toggleRecording()
            await store.toggleRecording()
            let applications = await actor.snapshot().activities.map(\.application)

            #expect(applications == ["PAUSED"])
        }
    }

    @Test("application quit appends a paused activity while recording")
    func applicationQuitAppendsAPausedActivityWhileRecording() async throws {
        try await withStore { store, actor, _, _ in
            await store.toggleRecording()
            await store.stopRecordingForApplicationQuit()
            let applications = await actor.snapshot().activities.map(\.application)

            #expect(applications == ["PAUSED"])
        }
    }

    @Test("application quit does not append a pause activity when already stopped")
    func applicationQuitDoesNotAppendAPauseActivityWhenAlreadyStopped() async throws {
        try await withStore { store, actor, _, _ in
            await store.stopRecordingForApplicationQuit()

            #expect(await actor.snapshot().activities.isEmpty)
        }
    }

    @Test("manual stop preserves already-processed enrichment")
    func manualStopPreservesAlreadyProcessedEnrichment() async throws {
        try await withStore(
            setup: { database, activityDatabaseActor, clock, activityAI in
                let seedVector = await (activityAI as? any ActivityEmbeddingGenerating)?
                    .generateVectors(for: ["ocr-3 / desc-3"], promptPrefix: nil)
                    .first ?? []

                try await database.saveActivityRecord(ActivityInput(
                    id: 9_001,
                    startTime: date(year: 2026, month: 3, day: 11, hour: 16, minute: 0),
                    application: "SeedApp",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "Seed ontology member.",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: nil
                ))
                try await activityDatabaseActor.persistActivitySummaryVector(
                    activityID: 9_001,
                    vector: seedVector
                )
                try await activityDatabaseActor.publishActivityTagOntologyRun(
                    ActivityTagOntologyRunInput(
                        runID: 9_100,
                        createdAt: clock.current,
                        previousRunID: nil,
                        candidates: [
                            ActivityTagOntologyCandidateInput(
                                candidateID: 9_101,
                                tagID: 55,
                                predecessorCandidateID: nil,
                                name: "work",
                                summary: "Work cluster",
                                centroidVector: seedVector.withUnsafeBytes { Data($0) },
                                memberActivityIDs: [9_001],
                                centralityScoreByActivityID: [9_001: 1],
                                memberOverlap: nil,
                                centroidSimilarity: nil,
                                continuitySimilarity: nil
                            )
                        ],
                        kNeighbors: ActivityTagOntologyDefaults.neighborCount,
                        leidenResolution: ActivityTagOntologyDefaults.leidenResolution,
                        leidenTheta: ActivityTagOntologyDefaults.leidenTheta,
                        continuityAlpha: ActivityTagOntologyDefaults.continuityAlpha,
                        continuityBeta: ActivityTagOntologyDefaults.continuityBeta,
                        continuityGamma: ActivityTagOntologyDefaults.continuityGamma
                    ),
                    tags: []
                )
            }
        ) { store, actor, clock, _ in
            await actor.load(for: clock.current)
            await store.toggleRecording()
            store.handleCaptureEvent(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            try await waitUntil {
                await actor.snapshot().activities.count == 1
            }
            await store.toggleRecording()
            try await waitUntil(timeout: .seconds(5)) {
                let firstActivity = await actor.snapshot().activities.first
                return (
                    firstActivity?.summary != nil,
                    firstActivity?.tagID,
                    firstActivity?.overviewID != nil
                ) == (true, 55, true)
            }
            let firstActivity = await actor.snapshot().activities.first

            #expect((firstActivity?.summary != nil, firstActivity?.tagID, firstActivity?.overviewID != nil) == (true, 55, true))
        }
    }

    @Test("manual stop immediately becomes non-recording")
    func manualStopImmediatelyBecomesNonRecording() async throws {
        try await withStore { store, _, _, _ in
            await store.toggleRecording()
            await store.toggleRecording()

            #expect(store.isRecording == false)
        }
    }

    @Test("capture events are ignored after recording stops")
    func captureEventsAreIgnoredAfterRecordingStops() async throws {
        try await withStore { store, actor, _, _ in
            await store.toggleRecording()
            store.handleCaptureEvent(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            try await waitUntil {
                await actor.snapshot().activities.count == 1
            }
            await store.toggleRecording()
            store.handleCaptureEvent(.appDidBecomeActive(.init(appName: "com.apple.Safari", image: Data("new".utf8))))

            #expect(await actor.snapshot().activities.map(\.application) == ["com.apple.dt.Xcode", "PAUSED"])
        }
    }

    @Test("play stop button disables when the active day is not today")
    func playStopButtonDisablesWhenTheActiveDayIsNotToday() async throws {
        try await withStore { store, _, _, _ in
            await store.setActiveDay(date(year: 2026, month: 3, day: 11, hour: 9, minute: 0))

            #expect((store.playStopButtonDisabled, store.activeDay) == (true, date(year: 2026, month: 3, day: 11, hour: 0, minute: 0)))
        }
    }

    @Test("moving to a past day stops recording without appending pause")
    func movingToAPastDayStopsRecordingWithoutAppendingPause() async throws {
        try await withStore { store, actor, _, monitor in
            await store.toggleRecording()
            await store.setActiveDay(date(year: 2026, month: 3, day: 11, hour: 9, minute: 0))
            let applications = await actor.snapshot().activities.map(\.application)

            #expect((store.isRecording, monitor.stopCount, applications.isEmpty) == (false, 1, true))
        }
    }

    @Test("toggle recording does not start capture when the button is disabled")
    func toggleRecordingDoesNotStartCaptureWhenTheButtonIsDisabled() async throws {
        try await withStore { store, _, _, monitor in
            await store.setActiveDay(date(year: 2026, month: 3, day: 11, hour: 9, minute: 0))
            await store.toggleRecording()

            #expect((store.isRecording, monitor.startCount) == (false, 0))
        }
    }

    @Test("capture events are ignored while stopped")
    func captureEventsAreIgnoredWhileStopped() async throws {
        try await withStore { store, actor, _, _ in
            store.handleCaptureEvent(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            let state = await actor.snapshot()

            #expect(state.activities.count == 0)
        }
    }

    @Test("capture events are forwarded while recording")
    func captureEventsAreForwardedWhileRecording() async throws {
        try await withStore { store, actor, _, _ in
            await store.toggleRecording()
            store.handleCaptureEvent(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            try await waitUntil {
                await actor.snapshot().activities.count == 1
            }
            let state = await actor.snapshot()

            #expect(state.activities.count == 1)
        }
    }

    @Test("sleep capture events append a sleep activity while recording")
    func sleepCaptureEventsAppendASleepActivityWhileRecording() async throws {
        try await withStore { store, actor, clock, _ in
            await store.toggleRecording()
            store.handleCaptureEvent(.willSleep(.init(timestamp: clock.current)))
            try await waitUntil {
                await actor.snapshot().activities.map(\.application) == ["SLEEP"]
            }

            #expect(await actor.snapshot().activities.map(\.application) == ["SLEEP"])
        }
    }

    @Test("sleep capture events are ignored while stopped")
    func sleepCaptureEventsAreIgnoredWhileStopped() async throws {
        try await withStore { store, actor, clock, _ in
            store.handleCaptureEvent(.willSleep(.init(timestamp: clock.current)))

            #expect(await actor.snapshot().activities.isEmpty)
        }
    }

    @Test("repeated sleep capture events do not create duplicate sleep activities")
    func repeatedSleepCaptureEventsDoNotCreateDuplicateSleepActivities() async throws {
        try await withStore { store, actor, clock, _ in
            await store.toggleRecording()
            store.handleCaptureEvent(.willSleep(.init(timestamp: clock.current)))
            store.handleCaptureEvent(.willSleep(.init(timestamp: clock.current.addingTimeInterval(1))))
            try await waitUntil {
                await actor.snapshot().activities.map(\.application) == ["SLEEP"]
            }

            #expect(await actor.snapshot().activities.map(\.application) == ["SLEEP"])
        }
    }

    @Test("setting an activity tag updates the underlying activity")
    func settingAnActivityTagUpdatesTheUnderlyingActivity() async throws {
        try await withStore { store, actor, _, _ in
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            let activityID = await actor.snapshot().activities.first?.id

            await store.setTag(activityID: activityID ?? -1, tagID: 55)

            #expect(await actor.snapshot().activities.first?.tagID == 55)
        }
    }

    @Test("deleting an activity removes it from state and the database")
    func deletingAnActivityRemovesItFromStateAndTheDatabase() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
        let clock = StoreTestClock(current: date(year: 2026, month: 3, day: 12, hour: 9, minute: 0))
        let monitor = FakeCaptureMonitor()

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let actorSystem = ActorSystem()
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
            dependencies: ActivityWorkerDependencies(activityAI: FakeActivityAI())
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
            dependencies: ActivityWorkerDependencies(activityAI: FakeActivityAI())
        )
        let store = ActivityStore(
            activityActor: actor,
            actorSystem: actorSystem,
            captureMonitor: monitor,
            initialState: .init(),
            activeDay: clock.current,
            isRecording: false,
            now: { clock.current },
            calendar: Calendar(identifier: .gregorian)
        )

        await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
        let activityID = await actor.snapshot().activities.first?.id ?? -1

        await store.deleteActivity(activityID: activityID)

        let persistedActivity: ActivityRecord? = switch try await database.get(.activity(.id(activityID))) {
        case let .activity(activity):
            activity
        default:
            nil
        }

        #expect((await actor.snapshot().activities.isEmpty, persistedActivity == nil) == (true, true))
    }
}

@MainActor
private func withStore(
    activityAI: any ActivityAIOperating = FakeActivityAI(),
    setup: ((TaskTraceDatabase, ActivityDatabaseActor, StoreTestClock, any ActivityAIOperating) async throws -> Void)? = nil,
    _ block: (ActivityStore, ActivityActor, StoreTestClock, FakeCaptureMonitor) async throws -> Void
) async throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
    let clock = StoreTestClock(current: date(year: 2026, month: 3, day: 12, hour: 9, minute: 0))
    let monitor = FakeCaptureMonitor()

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

    try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
    let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: activityAI)
    try await database.save(.tag(.record(TagInput(
        id: 55,
        name: "work",
        description: "Work",
        createDate: clock.current,
        deleteDate: nil,
        jsonProperties: nil
    ))))
    let actorSystem = ActorSystem()
    let activityDatabaseActor = ActivityDatabaseActor(database: database)
    let overviewDatabaseActor = OverviewDatabaseActor(database: database)
    let actor = ActivityActor(
        activityDatabaseActor: activityDatabaseActor,
        actorSystem: actorSystem,
        now: { clock.current },
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
        dependencies: ActivityWorkerDependencies(activityAI: activityAI)
    )
    try await setup?(database, activityDatabaseActor, clock, activityAI)
    let store = ActivityStore(
        activityActor: actor,
        actorSystem: actorSystem,
        captureMonitor: monitor,
        initialState: .init(),
        activeDay: clock.current,
        isRecording: false,
        now: { clock.current },
        calendar: Calendar(identifier: .gregorian)
    )

    try await block(store, actor, clock, monitor)
}

@MainActor
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

@MainActor final class SlowFakeActivityAI: ActivityAIOperating, ActivityEmbeddingGenerating, @unchecked Sendable {
    nonisolated init() {}
    func describeImage(_ image: Data) async -> String {
        "desc-\(image.count)"
    }

    func ocrImage(_ image: Data) async -> String {
        "ocr-\(image.count)"
    }

    func summarizeScreenshot(description: String, text: String) async -> String {
        [text, description]
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    func summarizeActivity(_ activity: ActivityActor.Activity) async -> String {
        try? await Task.sleep(for: .milliseconds(150))
        return "slow-summary"
    }

    func mergeOverviews(
        _ firstOverview: ActivityOverviewMergeOption,
        _ secondOverview: ActivityOverviewMergeOption
    ) async throws -> ActivityOverviewMergeDecision {
        ActivityOverviewMergeDecision(
            title: "Merged Overview",
            summary: "Merged overview summary."
        )
    }

    func generateVectors(for texts: [String], promptPrefix: String?) async -> [[Float]] {
        texts.map { _ in
            Array(
                repeating: 1,
                count: TaskTraceDatabaseBootstrap.activityEmbeddingDimension
            )
        }
    }

    func generateRerankings(
        query: String,
        documents: [String],
        instruction: String
    ) async -> [ActivityAIReranking] {
        documents.enumerated().map { index, _ in
            ActivityAIReranking(documentIndex: index, score: Float(documents.count - index))
        }
    }

    func warmSearchSummaryModel(traceStartedAt: Date?) async {}

    func streamResponse(
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("slow-stream")
            continuation.finish()
        }
    }

    func searchSummary(
        query: String,
        rankedDocuments: [String],
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        await streamResponse(prompt: query, instructions: "", generateParameters: GenerateParameters(), traceStartedAt: traceStartedAt)
    }

    func skillProcedure(
        prompt: String,
        instructions: String,
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        await streamResponse(prompt: prompt, instructions: instructions, generateParameters: GenerateParameters(), traceStartedAt: traceStartedAt)
    }
}

@MainActor
private final class FakeCaptureMonitor: CaptureMonitoring {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }
}

final class StoreTestClock: @unchecked Sendable {
    var current: Date

    init(current: Date) {
        self.current = current
    }
}

private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    ) ?? .distantPast
}
