//
//  SearchStoreTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/26/26.
//

import Foundation
import Testing
@testable import TaskTrace

@MainActor
struct SearchStoreTests {
    private let softRelevanceFloor = 1_000.0

    private func withStore(
        _ block: (SearchStore, TaskTraceDatabase, FakeActivityAI) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
        let activityAI = FakeActivityAI()
        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: activityAI)
        let store = SearchStore(database: database, activityAI: activityAI, relevanceFloor: softRelevanceFloor)

        try await block(store, database, activityAI)
    }

    @Test("search expands keywords from first pass results before the second pass")
    func searchExpandsKeywordsFromFirstPassResultsBeforeTheSecondPass() async throws {
        try await withStore { store, database, _ in
            try await database.saveOverviewRecord(OverviewInput(
                id: 1,
                title: "Quarterly approvals",
                summary: "Reviewing quarterly invoice approvals for billing export work.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 10,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Prepared the billing export approval.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 1
            ))
            try await database.saveScreenshotRecord(
                activityID: 10,
                screenshot: ScreenshotInput(
                    id: 11,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9, minute: 5),
                    description: "Approval modal",
                    text: "Approve quarterly invoice",
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )
            try await database.saveOverviewRecord(OverviewInput(
                id: 2,
                title: "Follow up",
                summary: "Billing export follow up.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 20,
                startTime: localDate(dayOffset: 0, hour: 10),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Investigated the billing export failure.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 2
            ))
            try await database.saveScreenshotRecord(
                activityID: 20,
                screenshot: ScreenshotInput(
                    id: 21,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 10, minute: 5),
                    description: "Billing export follow up",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            store.query = "quarterly"
            await store.search()

            let overviewIDs = Set(store.results.map(\.id))
            #expect(overviewIDs == Set<Int64>([1, 2]))
        }
    }

    @Test("db search keeps distinct overview matches even when one overview has many descendants")
    func dbSearchKeepsDistinctOverviewMatchesEvenWhenOneOverviewHasManyDescendants() async throws {
        try await withStore { _, database, _ in
            let searchDatabaseActor = SearchDatabaseActor(database: database)

            try await database.saveOverviewRecord(OverviewInput(
                id: 1,
                title: "Needle strong",
                summary: "needle",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 10,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Context only",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 1
            ))
            try await database.saveScreenshotRecord(
                activityID: 10,
                screenshot: ScreenshotInput(
                    id: 11,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9, minute: 1),
                    description: "Context one",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )
            try await database.saveScreenshotRecord(
                activityID: 10,
                screenshot: ScreenshotInput(
                    id: 12,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9, minute: 2),
                    description: "Context two",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )
            try await database.saveScreenshotRecord(
                activityID: 10,
                screenshot: ScreenshotInput(
                    id: 13,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9, minute: 3),
                    description: "Context three",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            try await database.saveOverviewRecord(OverviewInput(
                id: 2,
                title: "Needle weak",
                summary: "needle with extra filler words that should rank lower",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 20,
                startTime: localDate(dayOffset: 0, hour: 10),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Other context",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 2
            ))
            try await database.saveScreenshotRecord(
                activityID: 20,
                screenshot: ScreenshotInput(
                    id: 21,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 10, minute: 1),
                    description: "Context four",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            let searchResults = try await searchDatabaseActor.dbSearch(
                query: SearchKeywordizer.keywordize("needle"),
                limit: 2,
                relevanceFloor: softRelevanceFloor
            )

            #expect(searchResults.trees.map(\.id) == [1, 2])
            #expect(searchResults.trees.allSatisfy { $0.activities.isEmpty })
        }
    }

    @Test("db search caps matching activities per overview at three")
    func dbSearchCapsMatchingActivitiesPerOverviewAtThree() async throws {
        try await withStore { _, database, _ in
            let searchDatabaseActor = SearchDatabaseActor(database: database)

            try await database.saveOverviewRecord(OverviewInput(
                id: 1,
                title: "Cake work",
                summary: "Overview summary",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))

            for index in 1...6 {
                try await database.saveActivityRecord(ActivityInput(
                    id: Int64(index),
                    startTime: localDate(dayOffset: 0, hour: 8 + index),
                    application: "Safari",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "cake activity \(index)",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: 1
                ))
                try await database.saveScreenshotRecord(
                    activityID: Int64(index),
                    screenshot: ScreenshotInput(
                        id: Int64(index * 100),
                        image: nil,
                        timestamp: localDate(dayOffset: 0, hour: 8 + index, minute: 5),
                        description: "cake screenshot \(index)",
                        text: nil,
                        ignoreReason: nil,
                        jsonProperties: nil
                    )
                )
            }

            let searchResults = try await searchDatabaseActor.dbSearch(
                query: SearchKeywordizer.keywordize("cake"),
                limit: 3,
                relevanceFloor: softRelevanceFloor
            )

            #expect(searchResults.trees.first?.activities.count == 3)
        }
    }

    @Test("search second pass only expands from directly matched nodes")
    func searchSecondPassOnlyExpandsFromDirectlyMatchedNodes() async throws {
        try await withStore { store, database, _ in
            try await database.saveOverviewRecord(OverviewInput(
                id: 1,
                title: "Quarterly planning",
                summary: "Quarterly planning for renewals",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 10,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Meeting notes",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 1
            ))
            try await database.saveScreenshotRecord(
                activityID: 10,
                screenshot: ScreenshotInput(
                    id: 11,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9, minute: 5),
                    description: "Rabbit artifact",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            try await database.saveOverviewRecord(OverviewInput(
                id: 2,
                title: "Rabbit research",
                summary: "Rabbit burrow analysis",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 20,
                startTime: localDate(dayOffset: 0, hour: 10),
                application: "Notes",
                keystrokes: nil,
                microphone: nil,
                summary: "Animal notes",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 2
            ))
            try await database.saveScreenshotRecord(
                activityID: 20,
                screenshot: ScreenshotInput(
                    id: 21,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 10, minute: 5),
                    description: "Rabbit summary",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            store.query = "quarterly"
            await store.search()

            #expect(store.results.map(\.id) == [1])
        }
    }

    @Test("search store may return three globally when both capped passes collapse after dedupe")
    func searchStoreMayReturnThreeGloballyWhenBothCappedPassesCollapseAfterDedupe() async throws {
        try await withStore { store, database, _ in
            for index in 1...6 {
                try await database.saveOverviewRecord(OverviewInput(
                    id: Int64(index),
                    title: "Cake \(index)",
                    summary: "cake result \(index)",
                    jsonProperties: nil,
                    editedDuration: nil,
                    tagID: nil
                ))
                try await database.saveActivityRecord(ActivityInput(
                    id: Int64(index * 10),
                    startTime: localDate(dayOffset: 0, hour: 8 + index),
                    application: "Safari",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "cake activity \(index)",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: Int64(index)
                ))
                try await database.saveScreenshotRecord(
                    activityID: Int64(index * 10),
                    screenshot: ScreenshotInput(
                        id: Int64(index * 100),
                        image: nil,
                        timestamp: localDate(dayOffset: 0, hour: 8 + index, minute: 5),
                        description: "cake screenshot \(index)",
                        text: nil,
                        ignoreReason: nil,
                        jsonProperties: nil
                    )
                )
            }

            store.query = "cake"
            await store.search()

            #expect(store.results.count == 3)
        }
    }

    @Test("search requests summary model warmup eagerly")
    func searchRequestsSummaryModelWarmupEagerly() async throws {
        try await withStore { store, database, activityAI in
            try await database.saveOverviewRecord(OverviewInput(
                id: 1,
                title: "Quarterly approvals",
                summary: "Reviewing invoice approvals for billing export work.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 10,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Prepared the billing export approval.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 1
            ))
            try await database.saveScreenshotRecord(
                activityID: 10,
                screenshot: ScreenshotInput(
                    id: 11,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9, minute: 5),
                    description: "Approval modal",
                    text: "Approve quarterly invoice",
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            store.query = "quarterly"
            await store.search()
            await Task.yield()

            #expect(await activityAI.currentSearchSummaryWarmupCallCount() == 1)
        }
    }

    @Test("retrieval publishes first pass results before reranking finishes")
    func retrievalPublishesFirstPassResultsBeforeRerankingFinishes() async throws {
        try await withStore { store, database, activityAI in
            actor SnapshotProbe {
                private(set) var firstIntermediateSnapshot: SearchRetrievalSnapshot?

                func record(_ snapshot: SearchRetrievalSnapshot) {
                    if firstIntermediateSnapshot == nil
                        && !snapshot.results.isEmpty
                        && snapshot.results.allSatisfy { tree in
                            tree.score == nil
                                && tree.activities.allSatisfy { activity in
                                    activity.score == nil
                                        && activity.screenshots.allSatisfy { $0.score == nil }
                                }
                        } {
                        firstIntermediateSnapshot = snapshot
                    }
                }
            }

            let probe = SnapshotProbe()
            let searchService = TaskTraceSearchService(
                database: database,
                activityAI: activityAI,
                relevanceFloor: softRelevanceFloor
            )

            await activityAI.setRerankingDelayNanoseconds(2_000_000_000)

            try await database.saveOverviewRecord(OverviewInput(
                id: 1,
                title: "Quarterly approvals",
                summary: "Reviewing invoice approvals for billing export work.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 10,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Prepared the billing export approval.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 1
            ))
            try await database.saveScreenshotRecord(
                activityID: 10,
                screenshot: ScreenshotInput(
                    id: 11,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9, minute: 5),
                    description: "Approval modal",
                    text: "Approve quarterly invoice",
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            _ = store
            let retrievalTask = Task {
                try await searchService.retrieve(
                    query: "quarterly",
                    publish: { snapshot in
                        await probe.record(snapshot)
                    }
                )
            }

            for _ in 0..<100 where await probe.firstIntermediateSnapshot == nil {
                try? await Task.sleep(for: .milliseconds(20))
            }

            #expect(await probe.firstIntermediateSnapshot?.results.map(\.id) == [1])

            _ = try await retrievalTask.value
        }
    }

    @Test("second pass keywordization still extracts meaningful words from noisy descriptions")
    func secondPassKeywordizationStillExtractsMeaningfulWordsFromNoisyDescriptions() async {
        let secondPassSourceText = [
            "Quarterly billing follow-up",
            "Reviewed invoice approval workflow",
            "xxq__ 77%% inv0ice invoice qqq ### apprvl ~~ ledger"
        ]
        let secondPassKeywords = SearchKeywordizer.keywords(in: secondPassSourceText)
        let secondPassQuery = SearchKeywordizer.query(from: secondPassKeywords)

        #expect(secondPassQuery.contains("\"invoice\""))
    }

    @Test("search returns the expected overview tree for a screenshot seeded query")
    func searchReturnsTheExpectedOverviewTreeForAScreenshotSeededQuery() async throws {
        try await withStore { store, database, _ in
            try await database.saveOverviewRecord(OverviewInput(
                id: 5,
                title: "Collections",
                summary: "Accounts receivable work for monthly collections.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 50,
                startTime: localDate(dayOffset: 0, hour: 14),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Reviewed overdue receivables.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 5
            ))
            try await database.saveScreenshotRecord(
                activityID: 50,
                screenshot: ScreenshotInput(
                    id: 51,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 14, minute: 5),
                    description: "Collections dashboard",
                    text: "Receivables aging report",
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            store.query = "aging"
            await store.search()

            let recoveredTree = try #require(store.results.first.map {
                ($0.id, $0.activities.map(\.id), $0.activities.flatMap(\.screenshots).map(\.id))
            })
            #expect(recoveredTree == (5, [50], [51]))
        }
    }

    @Test("search expansion remains bounded by the top three first pass trees")
    func searchExpansionRemainsBoundedByTheTopThreeFirstPassTrees() async throws {
        try await withStore { store, database, _ in
            try await database.saveOverviewRecord(OverviewInput(
                id: 1,
                title: "One",
                summary: "Alpha bravo",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 101,
                startTime: localDate(dayOffset: 0, hour: 13),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Alpha bravo",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 1
            ))
            try await database.saveScreenshotRecord(
                activityID: 101,
                screenshot: ScreenshotInput(
                    id: 201,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 13, minute: 5),
                    description: "Alpha bravo",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )
            try await database.saveOverviewRecord(OverviewInput(
                id: 2,
                title: "Two",
                summary: "Alpha charlie",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 102,
                startTime: localDate(dayOffset: 0, hour: 12),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Alpha charlie",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 2
            ))
            try await database.saveScreenshotRecord(
                activityID: 102,
                screenshot: ScreenshotInput(
                    id: 202,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 12, minute: 5),
                    description: "Alpha charlie",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )
            try await database.saveOverviewRecord(OverviewInput(
                id: 3,
                title: "Three",
                summary: "Alpha delta",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 103,
                startTime: localDate(dayOffset: 0, hour: 11),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Alpha delta",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 3
            ))
            try await database.saveScreenshotRecord(
                activityID: 103,
                screenshot: ScreenshotInput(
                    id: 203,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 11, minute: 5),
                    description: "Alpha delta",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )
            try await database.saveOverviewRecord(OverviewInput(
                id: 4,
                title: "Four",
                summary: "Alpha epsilon",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 104,
                startTime: localDate(dayOffset: 0, hour: 10),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Alpha epsilon",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 4
            ))
            try await database.saveScreenshotRecord(
                activityID: 104,
                screenshot: ScreenshotInput(
                    id: 204,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 10, minute: 5),
                    description: "Alpha epsilon",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )
            try await database.saveOverviewRecord(OverviewInput(
                id: 5,
                title: "Five",
                summary: "Epsilon follow up work",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 105,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Epsilon follow up work",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 5
            ))
            try await database.saveScreenshotRecord(
                activityID: 105,
                screenshot: ScreenshotInput(
                    id: 205,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9, minute: 5),
                    description: "Epsilon follow up work",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            store.query = "alpha"
            await store.search()

            #expect(Set(store.results.map(\.id)) == Set<Int64>([1, 2, 3]))
        }
    }

    @Test("search publishes normalized reranking scores for node glow")
    func searchPublishesNormalizedRerankingScoresForNodeGlow() async throws {
        try await withStore { store, database, activityAI in
            try await database.saveOverviewRecord(OverviewInput(
                id: 8,
                title: "Tax prep",
                summary: "Tax preparation overview summary.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 80,
                startTime: localDate(dayOffset: 0, hour: 16),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Reviewed tax forms for filing.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 8
            ))
            try await database.saveScreenshotRecord(
                activityID: 80,
                screenshot: ScreenshotInput(
                    id: 81,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 16, minute: 5),
                    description: "Tax filing checklist on screen.",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )
            await activityAI.setRerankingScoresByDocument([
                "Tax preparation overview summary.": 0.2,
                "Reviewed tax forms for filing.": 0.9,
                "Tax filing checklist on screen.": 0.5
            ])

            store.query = "tax filing"
            await store.search()

            #expect(store.results.first?.activities.first?.score == 1)
        }
    }

    @Test("search streams a search summary from the top ranked contexts")
    func searchStreamsASearchSummaryFromTheTopRankedContexts() async throws {
        try await withStore { store, database, activityAI in
            try await database.saveOverviewRecord(OverviewInput(
                id: 9,
                title: "Invoice prep",
                summary: "Preparing invoice materials for filing.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 90,
                startTime: localDate(dayOffset: 0, hour: 17),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Reviewed invoice backup and filing steps.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 9
            ))
            try await database.saveScreenshotRecord(
                activityID: 90,
                screenshot: ScreenshotInput(
                    id: 91,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 17, minute: 5),
                    description: "Invoice backup checklist.",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )
            await activityAI.setStreamedResponseChunks(["Top ", "ranked ", "summary."])

            store.query = "invoice"
            await store.search()

            for _ in 0..<50 where store.searchSummaryText != "Top ranked summary." {
                try await Task.sleep(for: .milliseconds(10))
            }

            #expect(store.searchSummaryText == "Top ranked summary.")
        }
    }
}

private func localDate(dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
    let calendar = Calendar(identifier: .gregorian)
    let baseDay = calendar.startOfDay(for: Date())
    let shiftedDay = calendar.date(byAdding: .day, value: dayOffset, to: baseDay) ?? baseDay
    return calendar.date(byAdding: .minute, value: hour * 60 + minute, to: shiftedDay) ?? shiftedDay
}
