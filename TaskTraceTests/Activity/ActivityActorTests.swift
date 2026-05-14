//
//  ActivityActorTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/12/26.
//

import AppKit
import Foundation
import MLXLMCommon
import Testing
@testable import TaskTrace

struct ActivityActorTests {
    @Test("application activation creates a described activity")
    func applicationActivationCreatesDescribedActivity() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            try await waitUntil {
                await actor.snapshot().activities.first?.screenshots.first?.description == "desc-3"
            }
            let state = await actor.snapshot()

            #expect((state.activities.count, state.activities.first?.screenshots.first?.description) == (1, "desc-3"))
        }
    }

    @Test("application activation populates screenshot text from OCR")
    func applicationActivationPopulatesScreenshotTextFromOCR() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            try await waitUntil {
                await actor.snapshot().activities.first?.screenshots.first?.text == "ocr-3"
            }
            let state = await actor.snapshot()

            #expect(state.activities.first?.screenshots.first?.text == "ocr-3")
        }
    }

    @Test("application activation persists screenshot description through the projection actor")
    func applicationActivationPersistsScreenshotDescriptionThroughTheProjectionActor() async throws {
        try await withActorAndDatabase { actor, database, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            let screenshotID = try #require(await actor.snapshot().activities.first?.screenshots.first?.id)
            try await waitUntil {
                let fetched = try await database.get(.screenshot(.id(screenshotID)))

                guard case let .screenshot(record?) = fetched else {
                    return false
                }

                return record.description == "desc-3"
            }
            let fetched = try await database.get(.screenshot(.id(screenshotID)))
            guard case let .screenshot(record?) = fetched else {
                Issue.record("expected screenshot record")
                return
            }

            #expect(record.description == "desc-3")
        }
    }

    @Test("application activation persists screenshot text through the projection actor")
    func applicationActivationPersistsScreenshotTextThroughTheProjectionActor() async throws {
        try await withActorAndDatabase { actor, database, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            let screenshotID = try #require(await actor.snapshot().activities.first?.screenshots.first?.id)
            try await waitUntil {
                let fetched = try await database.get(.screenshot(.id(screenshotID)))

                guard case let .screenshot(record?) = fetched else {
                    return false
                }

                return record.ocrText == "ocr-3"
            }
            let fetched = try await database.get(.screenshot(.id(screenshotID)))
            guard case let .screenshot(record?) = fetched else {
                Issue.record("expected screenshot record")
                return
            }

            #expect(record.ocrText == "ocr-3")
        }
    }

    @Test("application activation creates a screenshot summary")
    func applicationActivationCreatesAScreenshotSummary() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            try await waitUntil {
                await actor.snapshot().activities.first?.screenshots.first?.summary == "ocr-3 / desc-3"
            }
            let state = await actor.snapshot()

            #expect(state.activities.first?.screenshots.first?.summary == "ocr-3 / desc-3")
        }
    }

    @Test("application activation persists screenshot summary through the projection actor")
    func applicationActivationPersistsScreenshotSummaryThroughTheProjectionActor() async throws {
        try await withActorAndDatabase { actor, database, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            let screenshotID = try #require(await actor.snapshot().activities.first?.screenshots.first?.id)
            try await waitUntil {
                let fetched = try await database.get(.screenshot(.id(screenshotID)))

                guard case let .screenshot(record?) = fetched else {
                    return false
                }

                return record.summary == "ocr-3 / desc-3"
            }
            let fetched = try await database.get(.screenshot(.id(screenshotID)))
            guard case let .screenshot(record?) = fetched else {
                Issue.record("expected screenshot record")
                return
            }

            #expect(record.summary == "ocr-3 / desc-3")
        }
    }

    @Test("pending screenshot summary is not requeued during activity rescan")
    func pendingScreenshotSummaryIsNotRequeuedDuringActivityRescan() async throws {
        let recorder = ScreenshotSummaryRequestRecorder()
        let delayedSummarizer = DelayedScreenshotSummarizer(delay: .seconds(1))

        try await withActorAndDatabase(
            dependencies: makeSlowScreenshotWorkerDependencies(screenshotSummarizer: delayedSummarizer),
            registerAdditionalReceivers: { actorSystem in
                _ = await actorSystem.register(recorder)
            }
        ) { actor, _, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            try await waitUntil {
                await recorder.totalCount() == 1
            }
            let firstScreenshotID = try #require(await actor.snapshot().activities.first?.screenshots.first?.id)

            clock.current = date(hour: 9, minute: 0, second: 10)
            await actor.handle(.appMonitor(.init(appName: "com.apple.dt.Xcode", image: Data("second-image".utf8))))
            try await waitUntil {
                await actor.snapshot().activities.first?.screenshots.count == 2
            }
            let secondScreenshotID = try #require(await actor.snapshot().activities.first?.screenshots.last?.id)
            try await waitUntil {
                await recorder.count(for: secondScreenshotID) == 1
            }
            let counts = await recorder.counts(for: [firstScreenshotID, secondScreenshotID])

            #expect(counts == [firstScreenshotID: 1, secondScreenshotID: 1])
        }
    }

    @Test("current day load queues missing screenshot summaries")
    func currentDayLoadQueuesMissingScreenshotSummaries() async throws {
        try await withActorAndDatabase { actor, database, clock in
            clock.current = date(hour: 9, minute: 0)
            try await database.saveActivityRecord(ActivityInput(
                id: 10,
                startTime: date(hour: 9, minute: 0),
                application: "com.apple.dt.Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: nil,
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await database.saveScreenshotRecord(
                activityID: 10,
                screenshot: ScreenshotInput(
                    id: 11,
                    image: nil,
                    timestamp: date(hour: 9, minute: 1),
                    description: "loaded description",
                    text: "loaded ocr",
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            await actor.load(for: clock.current)
            try await waitUntil {
                await actor.snapshot().activities.first?.screenshots.first?.summary == "loaded ocr / loaded description"
            }
            let summary = await actor.snapshot().activities.first?.screenshots.first?.summary

            #expect(summary == "loaded ocr / loaded description")
        }
    }

    @Test("key release appends characters to the active activity")
    func keyReleaseAppendsCharactersToTheActiveActivity() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            await actor.handle(.keyPress(.init(keyCode: 12, modifiers: 0, characters: "a")))
            await actor.handle(.keyRelease(.init(keyCode: 12, modifiers: 0, characters: "a")))
            let state = await actor.snapshot()

            #expect(state.activities.first?.keystrokes == "a")
        }
    }

    @Test("microphone transcript appends to the active activity")
    func microphoneTranscriptAppendsToTheActiveActivity() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            await actor.handle(.microphone(.init(transcript: "hello world", timestamp: clock.current)))
            let state = await actor.snapshot()

            #expect(state.activities.first?.microphone == "hello world")
        }
    }

    @Test("app monitor for the same application appends a screenshot")
    func appMonitorForTheSameApplicationAppendsAScreenshot() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img-1".utf8))))
            clock.current = date(hour: 9, minute: 2)
            await actor.handle(.appMonitor(.init(appName: "com.apple.dt.Xcode", image: Data("img-2".utf8))))
            let state = await actor.snapshot()

            #expect(state.activities.first?.screenshots.count == 2)
        }
    }

    @Test("near-duplicate app monitor screenshots are dropped before processing and persistence")
    func nearDuplicateAppMonitorScreenshotsAreDroppedBeforeProcessingAndPersistence() async throws {
        try await withActorAndDatabase(
            dependencies: makeSlowScreenshotWorkerDependencies()
        ) { actor, database, clock in
            let imageData = try #require(makePNGData(red: 24, green: 96, blue: 180))

            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: imageData)))

            let initialScreenshotID = try #require(await actor.snapshot().activities.first?.screenshots.first?.id)

            clock.current = date(hour: 9, minute: 1)
            await actor.handle(.appMonitor(.init(appName: "com.apple.dt.Xcode", image: imageData)))

            let state = await actor.snapshot()
            #expect((state.activities.count, state.activities.first?.screenshots.count) == (1, 1))
            #expect(state.activities.first?.screenshots.first?.id == initialScreenshotID)

            let fetched = try await database.get(.screenshot(.all))
            guard case let .screenshots(records) = fetched else {
                Issue.record("expected screenshot records")
                return
            }

            #expect(records.count == 1)
        }
    }

    @Test("late-arrival app monitor screenshots are dropped before processing and persistence")
    func lateArrivalAppMonitorScreenshotsAreDroppedBeforeProcessingAndPersistence() async throws {
        try await withActorAndDatabase { actor, database, clock in
            clock.current = date(hour: 9, minute: 5)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img-1".utf8))))

            let initialScreenshotID = try #require(await actor.snapshot().activities.first?.screenshots.first?.id)

            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appMonitor(.init(appName: "com.apple.dt.Xcode", image: Data("img-older".utf8))))

            let state = await actor.snapshot()
            #expect((state.activities.count, state.activities.first?.screenshots.count) == (1, 1))
            #expect(state.activities.first?.screenshots.first?.id == initialScreenshotID)

            let fetched = try await database.get(.screenshot(.all))
            guard case let .screenshots(records) = fetched else {
                Issue.record("expected screenshot records")
                return
            }

            #expect(records.count == 1)
        }
    }

    @Test("app monitor for a different application starts a new activity")
    func appMonitorForADifferentApplicationStartsANewActivity() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img-1".utf8))))
            clock.current = date(hour: 9, minute: 2)
            await actor.handle(.appMonitor(.init(appName: "com.apple.TextEdit", image: Data("img-2".utf8))))
            let state = await actor.snapshot()

            #expect(state.activities.map(\.application) == ["com.apple.dt.Xcode", "com.apple.TextEdit"])
        }
    }

    @Test("short middle activities collapse back into the surrounding application activity")
    func shortMiddleActivitiesCollapseBackIntoTheSurroundingApplicationActivity() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0, second: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img-1".utf8))))
            clock.current = date(hour: 9, minute: 0, second: 40)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.TextEdit", image: Data("img-2".utf8))))
            clock.current = date(hour: 9, minute: 0, second: 50)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img-3".utf8))))
            let state = await actor.snapshot()

            #expect((state.activities.count, state.activities.first?.application) == (1, "com.apple.dt.Xcode"))
        }
    }

    @Test("lagged activity passes compute summaries and delete stored image payloads")
    func laggedActivityPassesComputeSummariesAndDeleteStoredImagePayloads() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "app.one", image: Data("img-1".utf8))))
            clock.current = date(hour: 9, minute: 2)
            await actor.handle(.appMonitor(.init(appName: "app.one", image: Data("img-2".utf8))))
            clock.current = date(hour: 9, minute: 10)
            await actor.handle(.appDidBecomeActive(.init(appName: "app.two", image: Data("img-3".utf8))))
            clock.current = date(hour: 9, minute: 20)
            await actor.handle(.appDidBecomeActive(.init(appName: "app.three", image: Data("img-4".utf8))))
            clock.current = date(hour: 9, minute: 30)
            await actor.handle(.appDidBecomeActive(.init(appName: "app.four", image: Data("img-5".utf8))))
            try await waitUntil {
                let state = await actor.snapshot()
                return (
                    state.activities.first?.summary,
                    state.activities.first?.screenshots.first?.image == nil
                ) == ("ocr-5 / desc-5 | ocr-5 / desc-5", true)
            }
            let state = await actor.snapshot()
            #expect((state.activities.first?.summary, state.activities.first?.screenshots.first?.image == nil) == ("ocr-5 / desc-5 | ocr-5 / desc-5", true))
        }
    }

    @Test("lagged activity passes leave summarized activities untagged when no ontology run exists")
    func laggedActivityPassesLeaveSummarizedActivitiesUntaggedWhenNoOntologyRunExists() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "app.one", image: Data("img-1".utf8))))
            clock.current = date(hour: 9, minute: 2)
            await actor.handle(.appMonitor(.init(appName: "app.one", image: Data("img-2".utf8))))
            clock.current = date(hour: 9, minute: 10)
            await actor.handle(.appDidBecomeActive(.init(appName: "app.two", image: Data("img-3".utf8))))
            clock.current = date(hour: 9, minute: 20)
            await actor.handle(.appDidBecomeActive(.init(appName: "app.three", image: Data("img-4".utf8))))
            clock.current = date(hour: 9, minute: 30)
            await actor.handle(.appDidBecomeActive(.init(appName: "app.four", image: Data("img-5".utf8))))

            try await waitUntil {
                !(await actor.snapshot().activities.first?.summary?.isEmpty ?? true)
            }

            let firstActivity = await actor.snapshot().activities.first
            #expect((firstActivity?.summary?.isEmpty == false, firstActivity?.tagID) == (true, nil))
        }
    }

    @Test("activity tag assignment events apply ontology metadata to untagged activities")
    func activityTagAssignmentEventsApplyOntologyMetadataToUntaggedActivities() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            let activityID = try #require(await actor.snapshot().activities.first?.id)

            await actor.receive(Envelope(
                sender: nil,
                message: ActivityTagAssigned(
                    activityID: activityID,
                    tagID: 77,
                    ontologyCandidateID: 88
                )
            ))

            let firstActivity = await actor.snapshot().activities.first
            #expect((firstActivity?.tagID, firstActivity?.tagAssignmentSource, firstActivity?.ontologyCandidateID) == (77, .ontology, 88))
        }
    }

    @Test("manual tag events preserve ontology candidate metadata while switching the source")
    func manualTagEventsPreserveOntologyCandidateMetadataWhileSwitchingTheSource() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            let activityID = try #require(await actor.snapshot().activities.first?.id)

            await actor.receive(Envelope(
                sender: nil,
                message: ActivityTagAssigned(
                    activityID: activityID,
                    tagID: 77,
                    ontologyCandidateID: 88
                )
            ))
            await actor.receive(Envelope(
                sender: nil,
                message: ActivityTagSet(
                    activityID: activityID,
                    tagID: 99
                )
            ))

            let firstActivity = await actor.snapshot().activities.first
            #expect((firstActivity?.tagID, firstActivity?.tagAssignmentSource, firstActivity?.ontologyCandidateID) == (99, .manual, 88))
        }
    }

    @Test("activity tag assignment events do not overwrite manual tags")
    func activityTagAssignmentEventsDoNotOverwriteManualTags() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            let activityID = try #require(await actor.snapshot().activities.first?.id)

            await actor.receive(Envelope(
                sender: nil,
                message: ActivityTagSet(
                    activityID: activityID,
                    tagID: 99
                )
            ))
            await actor.receive(Envelope(
                sender: nil,
                message: ActivityTagAssigned(
                    activityID: activityID,
                    tagID: 77,
                    ontologyCandidateID: 88
                )
            ))

            let firstActivity = await actor.snapshot().activities.first
            #expect((firstActivity?.tagID, firstActivity?.tagAssignmentSource, firstActivity?.ontologyCandidateID) == (99, .manual, nil))
        }
    }

    @Test("activity passes can summarize multiple activities concurrently")
    func activityPassesCanSummarizeMultipleActivitiesConcurrently() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
        let clock = MutableClock(current: date(hour: 9, minute: 0))
        let activityAI = ConcurrentTrackingActivityAI()

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: activityAI)
        let actorSystem = ActorSystem()
        let activityDatabaseActor = ActivityDatabaseActor(database: database)
        let actor = ActivityActor(
            activityDatabaseActor: activityDatabaseActor,
            actorSystem: actorSystem,
            now: { clock.current },
            nextIdentifier: 100
        )
        await ActivityScreenshotPipelineBootstrap.register(
            actorSystem: actorSystem,
            activityActor: actor,
            activityDatabaseActor: activityDatabaseActor,
            dependencies: ActivityWorkerDependencies(activityAI: activityAI)
        )

        for hour in 9...14 {
            clock.current = date(hour: hour, minute: 0)
            await actor.handle(
                .appDidBecomeActive(
                    .init(appName: "app.\(hour)", image: Data("img-\(hour)".utf8))
                )
            )
        }

        await actor.applyActivityPasses(offset: 0)

        #expect(await activityAI.peakConcurrentSummaries() > 1)
    }

    @Test("generated identifiers re-anchor to the current millisecond timestamp")
    func generatedIdentifiersReanchorToTheCurrentMillisecondTimestamp() async throws {
        try await withActor { actor, clock in
            clock.current = date(hour: 9, minute: 0, second: 0)
            await actor.handle(.appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))))
            let expectedBaseIdentifier = Int64(clock.current.timeIntervalSince1970 * 1_000)
            let state = await actor.snapshot()

            #expect((state.activities.first?.id, state.activities.first?.screenshots.first?.id) == (expectedBaseIdentifier, expectedBaseIdentifier + 1))
        }
    }

    @Test("default event sequence keeps the expected applications after compaction")
    func defaultEventSequenceKeepsTheExpectedApplicationsAfterCompaction() async throws {
        try await withActor { actor, clock in
            await run(events: defaultEventSequence(), against: actor, clock: clock)
            let state = await actor.snapshot()

            #expect(state.activities.map(\.application) == ["testapp1", "testapp3", "testapp1", "SLEEP", "testapp1", "testapp5", "testapp6"])
        }
    }

    @Test("default event sequence keeps the expected screenshot counts per activity")
    func defaultEventSequenceKeepsTheExpectedScreenshotCountsPerActivity() async throws {
        try await withActor { actor, clock in
            await run(events: defaultEventSequence(), against: actor, clock: clock)
            let state = await actor.snapshot()

            #expect(state.activities.map { $0.screenshots.count } == [3, 4, 1, 0, 3, 2, 1])
        }
    }

    @Test("default event sequence turns the first post-sleep monitor into a new activity")
    func defaultEventSequenceTurnsTheFirstPostSleepMonitorIntoANewActivity() async throws {
        try await withActor { actor, clock in
            await run(events: defaultEventSequence(), against: actor, clock: clock)
            let state = await actor.snapshot()
            let sleepIndex = state.activities.firstIndex { $0.application == "SLEEP" }

            #expect(sleepIndex.flatMap { state.activities.indices.contains($0 + 1) ? state.activities[$0 + 1].application : nil } == "testapp1")
        }
    }

    @Test("default event sequence incrementally fills summaries for older activities")
    func defaultEventSequenceIncrementallyFillsSummariesForOlderActivities() async throws {
        try await withActor { actor, clock in
            await run(events: defaultEventSequence(), against: actor, clock: clock)
            try await waitUntil(timeout: .seconds(5)) {
                let summaries = await actor.snapshot().activities.map(\.summary)
                return (
                    summaries.prefix(3).allSatisfy { !($0?.isEmpty ?? true) },
                    summaries.dropFirst(3).allSatisfy { $0 == nil }
                ) == (true, true)
            }
            let state = await actor.snapshot()

            #expect(
                (
                    state.activities.map(\.summary).prefix(3).allSatisfy { !($0?.isEmpty ?? true) },
                    state.activities.map(\.summary).dropFirst(3).allSatisfy { $0 == nil }
                ) == (true, true)
            )
        }
    }

    @Test("default event sequence trims all image payloads after screenshot passes finish")
    func defaultEventSequenceTrimsAllImagePayloadsAfterScreenshotPassesFinish() async throws {
        try await withActor { actor, clock in
            await run(events: defaultEventSequence(), against: actor, clock: clock)
            try await waitUntil(timeout: .seconds(5)) {
                await actor.snapshot().activities
                    .flatMap(\.screenshots)
                    .compactMap(\.image)
                    .count == 0
            }
            let remainingImageCount = await actor.snapshot().activities
                .flatMap(\.screenshots)
                .compactMap(\.image)
                .count

            #expect(remainingImageCount == 0)
        }
    }

    @Test("app monitor sequences never retain more than nine screenshots")
    func appMonitorSequencesNeverRetainMoreThanNineScreenshots() async throws {
        try await withActor { actor, clock in
            let events = [TimedCaptureEvent(
                timestamp: date(hour: 11, minute: 0),
                event: .appDidBecomeActive(.init(appName: "long.running.app", image: Data("seed".utf8)))
            )] + (1...10).map { index in
                TimedCaptureEvent(
                    timestamp: date(hour: 11, minute: index, second: 0),
                    event: .appMonitor(.init(appName: "long.running.app", image: Data("monitor-\(index)".utf8)))
                )
            }

            await run(events: events, against: actor, clock: clock)
            let screenshotCount = await actor.snapshot().activities.first?.screenshots.count

            #expect(screenshotCount == 9)
        }
    }

    @Test("screenshot images are released after dispatch before workers finish")
    func screenshotImagesAreReleasedAfterDispatchBeforeWorkersFinish() async throws {
        try await withActorAndDatabase(
            dependencies: makeSlowScreenshotWorkerDependencies()
        ) { actor, _, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(
                .appDidBecomeActive(
                    .init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))
                )
            )
            let image = await actor.snapshot().activities.first?.screenshots.first?.image

            #expect(image == nil)
        }
    }

    @Test("empty screenshot descriptions complete with the unavailable fallback")
    func emptyScreenshotDescriptionsCompleteWithUnavailableFallback() async throws {
        try await withActorAndDatabase(
            dependencies: makeSlowScreenshotWorkerDependencies(imageDescriber: EmptyImageDescriber())
        ) { actor, _, clock in
            clock.current = date(hour: 9, minute: 0)
            await actor.handle(
                .appDidBecomeActive(
                    .init(appName: "com.apple.dt.Xcode", image: Data("img".utf8))
                )
            )
            try await waitUntil {
                await actor.snapshot().activities.first?.screenshots.first?.description == "Image description unavailable."
            }
            let description = await actor.snapshot().activities.first?.screenshots.first?.description

            #expect(description == "Image description unavailable.")
        }
    }
}

private func withActor(
    _ block: (ActivityActor, MutableClock) async throws -> Void
) async throws {
    try await withActorAndDatabase { actor, _, clock in
        try await block(actor, clock)
    }
}

private func withActorAndDatabase(
    dependencies: ActivityWorkerDependencies? = nil,
    registerAdditionalReceivers: ((ActorSystem) async -> Void)? = nil,
    _ block: (ActivityActor, TaskTraceDatabase, MutableClock) async throws -> Void
) async throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
    let clock = MutableClock(current: date(hour: 9, minute: 0))

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

    let activityAI = FakeActivityAI()
    try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
    let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: activityAI)
    let actorSystem = ActorSystem()
    let activityDatabaseActor = ActivityDatabaseActor(database: database)
    let actor = ActivityActor(
        activityDatabaseActor: activityDatabaseActor,
        actorSystem: actorSystem,
        now: { clock.current },
        nextIdentifier: 100
    )

    await ActivityScreenshotPipelineBootstrap.register(
        actorSystem: actorSystem,
        activityActor: actor,
        activityDatabaseActor: activityDatabaseActor,
        dependencies: dependencies ?? ActivityWorkerDependencies(activityAI: activityAI)
    )
    if let registerAdditionalReceivers {
        await registerAdditionalReceivers(actorSystem)
    }

    try await block(actor, database, clock)
}

private func run(events: [TimedCaptureEvent], against actor: ActivityActor, clock: MutableClock) async {
    for event in events {
        clock.current = event.timestamp
        await actor.handle(event.event)
    }
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

private func defaultEventSequence() -> [TimedCaptureEvent] {
    [
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 1),
            event: .appDidBecomeActive(.init(appName: "testapp1", image: Data("base64 image tH0bJBFR9Q2".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 1, second: 30),
            event: .appMonitor(.init(appName: "testapp1", image: Data("base64 image tb2k2k9".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 2),
            event: .appDidBecomeActive(.init(appName: "testapp2", image: Data("base64 image 8KCD2Ib6VftsuCI9".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 2, second: Int(ActivityActor.minimumActivityDurationSeconds) - 1),
            event: .appDidBecomeActive(.init(appName: "testapp1", image: Data("base64 image xV".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 2, second: Int(ActivityActor.minimumActivityDurationSeconds) + 1),
            event: .appDidBecomeActive(.init(appName: "testapp3", image: Data("base64 image u10Sncx0E".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 3, second: 1),
            event: .appMonitor(.init(appName: "testapp3", image: Data("base64 image u10Sncx0Elalm2woA:LSK#".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 3, second: 2),
            event: .appMonitor(.init(appName: "testapp3", image: Data("base64 image u10Sncx0E".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 3, second: 3),
            event: .appMonitor(.init(appName: "testapp3", image: Data("base64 image u10Sncx0E".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 10),
            event: .appMonitor(.init(appName: "testapp1", image: Data("base64 image oKRQpS".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 11),
            event: .willSleep(.init(timestamp: date(hour: 1, minute: 11)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 12),
            event: .willSleep(.init(timestamp: date(hour: 1, minute: 12)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 30),
            event: .appMonitor(.init(appName: "testapp1", image: Data("base64 image u10Sncx0E3k3nsl)nqow".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 31),
            event: .appMonitor(.init(appName: "testapp1", image: Data("base64 image example1".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 32),
            event: .appMonitor(.init(appName: "testapp1", image: Data("base64 image example2".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 40),
            event: .appDidBecomeActive(.init(appName: "testapp5", image: Data("base64 image newImageXYZ".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 41),
            event: .appMonitor(.init(appName: "testapp5", image: Data("base64 image newMonitorImageABC".utf8)))
        ),
        TimedCaptureEvent(
            timestamp: date(hour: 1, minute: 42),
            event: .appDidBecomeActive(.init(appName: "testapp6", image: Data("base64 image newImageXYZ".utf8)))
        )
    ]
}

private func date(hour: Int, minute: Int, second: Int = 0) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 3, day: 12, hour: hour, minute: minute, second: second)
    ) ?? .distantPast
}

private func makePNGData(
    width: Int = 4,
    height: Int = 4,
    red: UInt8,
    green: UInt8,
    blue: UInt8
) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    ), let data = bitmap.bitmapData else {
        return nil
    }

    for offset in stride(from: 0, to: width * height * 4, by: 4) {
        data[offset] = red
        data[offset + 1] = green
        data[offset + 2] = blue
        data[offset + 3] = 255
    }

    return bitmap.representation(using: .png, properties: [:])
}

private func makeSlowScreenshotWorkerDependencies(
    imageDescriber: any ActivityImageDescribing = SlowImageDescriber(),
    screenshotTextRecognizer: any ActivityScreenshotTextRecognizing = SlowScreenshotTextRecognizer(),
    screenshotSummarizer: (any ActivityScreenshotSummarizing)? = nil
) -> ActivityWorkerDependencies {
    let activityAI = ConcurrentTrackingActivityAI()

    return ActivityWorkerDependencies(
        makeActivityEmbeddingActor: { actorSystem in
            ActivityEmbeddingActor(
                actorSystem: actorSystem,
                embeddingGenerator: activityAI
            )
        },
        makeDescribeImageActor: { actorSystem in
            DescribeImageActor(
                actorSystem: actorSystem,
                imageDescriber: imageDescriber
            )
        },
        makeReadScreenshotTextActor: { actorSystem in
            ReadScreenshotTextActor(
                actorSystem: actorSystem,
                screenshotTextRecognizer: screenshotTextRecognizer,
                visibleTextReader: EmptyActivityVisibleTextReader()
            )
        },
        makeSummarizeScreenshotActor: { actorSystem in
            if let screenshotSummarizer {
                return SummarizeScreenshotActor(actorSystem: actorSystem, screenshotSummarizer: screenshotSummarizer)
            }

            return SummarizeScreenshotActor(actorSystem: actorSystem, screenshotSummarizer: activityAI)
        },
        makeSummarizeActivityActor: { SummarizeActivityActor(actorSystem: $0, summarizer: activityAI) },
        makeActivityTagOntologyActor: { ActivityTagOntologyActor(actorSystem: $0, activityDatabaseActor: $1) },
        makeOntologyOverviewActor: {
            OntologyOverviewActor(
                actorSystem: $0,
                overviewDatabaseActor: $1,
                textResponder: nil
            )
        },
        makeMergeOverviewsActor: { MergeOverviewsActor(actorSystem: $0, overviewMerger: activityAI) }
    )
}

private struct TimedCaptureEvent {
    let timestamp: Date
    let event: TaskTraceCaptureMonitor.Event
}

final class MutableClock: @unchecked Sendable {
    var current: Date

    init(current: Date) {
        self.current = current
    }
}

private final class ConcurrentTrackingActivityAI: ActivityAIOperating, ActivityEmbeddingGenerating, @unchecked Sendable {
    private let tracker = ConcurrentSummaryTracker()

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
        await tracker.begin()
        try? await Task.sleep(for: .milliseconds(100))
        await tracker.end()
        return "summary-\(activity.id)"
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
            continuation.yield("concurrent-stream")
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

    func peakConcurrentSummaries() async -> Int {
        await tracker.snapshot().peak
    }
}

private actor ConcurrentSummaryTracker {
    private var active = 0
    private var peak = 0

    func begin() {
        active += 1
        peak = max(peak, active)
    }

    func end() {
        active = max(0, active - 1)
    }

    func snapshot() -> (active: Int, peak: Int) {
        (active, peak)
    }
}

private struct SlowImageDescriber: ActivityImageDescribing {
    func describeImage(_ image: Data) async -> String {
        try? await Task.sleep(for: .milliseconds(200))
        return "desc-\(image.count)"
    }
}

private struct EmptyImageDescriber: ActivityImageDescribing {
    func describeImage(_ image: Data) async -> String {
        ""
    }
}

private struct SlowScreenshotTextRecognizer: ActivityScreenshotTextRecognizing {
    func ocrImage(_ image: Data) async -> String {
        try? await Task.sleep(for: .milliseconds(200))
        return "ocr-\(image.count)"
    }
}

private actor ScreenshotSummaryRequestRecorder: Receiver {
    private var requestCounts: [Int64: Int] = [:]

    func receive(_ envelope: Envelope) async {
        guard let request = envelope.message as? SummarizeScreenshot else {
            return
        }

        requestCounts[request.screenshotID, default: 0] += 1
    }

    func count(for screenshotID: Int64) -> Int {
        requestCounts[screenshotID] ?? 0
    }

    func counts(for screenshotIDs: [Int64]) -> [Int64: Int] {
        Dictionary(uniqueKeysWithValues: screenshotIDs.map { ($0, requestCounts[$0] ?? 0) })
    }

    func totalCount() -> Int {
        requestCounts.values.reduce(0, +)
    }
}

private actor DelayedScreenshotSummarizer: ActivityScreenshotSummarizing {
    let delay: Duration

    init(delay: Duration) {
        self.delay = delay
    }

    func summarizeScreenshot(description: String, text: String) async -> String {
        try? await Task.sleep(for: delay)
        return [text, description]
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }
}
