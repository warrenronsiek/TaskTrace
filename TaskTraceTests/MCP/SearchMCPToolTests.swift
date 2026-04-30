//
//  SearchMCPToolTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/28/26.
//

import Foundation
import MCP
import Testing
@testable import TaskTrace

@MainActor
struct SearchMCPToolTests {
    private let softRelevanceFloor = 1_000.0

    private func withRuntime(
        _ block: (OverviewMCPServerRuntime, TaskTraceDatabase, FakeActivityAI) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
        let activityAI = FakeActivityAI()
        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: activityAI)
        let searchService = TaskTraceSearchService(
            database: database,
            activityAI: activityAI,
            relevanceFloor: softRelevanceFloor
        )
        let runtime = OverviewMCPServerRuntime(searchService: searchService)

        try await block(runtime, database, activityAI)
    }

    @Test("tool list includes the search tool when search is configured")
    func toolListIncludesTheSearchToolWhenSearchIsConfigured() async throws {
        try await withRuntime { runtime, _, _ in
            await runtime.update(
                activeDay: Date(timeIntervalSince1970: 0),
                overviews: [],
                activities: [],
                configuration: .default
            )
            #expect((await runtime.toolNames()).contains(Vars.mcpSearchToolName))
        }
    }

    @Test("search tool calls are rejected when the tool is disabled")
    func searchToolCallsAreRejectedWhenTheToolIsDisabled() async throws {
        try await withRuntime { runtime, _, _ in
            var configuration = SettingsStore.MCPConfiguration.default
            configuration.searchToolEnabled = false

            await runtime.update(
                activeDay: Date(timeIntervalSince1970: 0),
                overviews: [],
                activities: [],
                configuration: configuration
            )

            await #expect(throws: MCPError.self) {
                _ = try await runtime.callSearchTool(query: "invoice", limit: 10)
            }
        }
    }

    @Test("search tool returns ranked results without summary warmup")
    func searchToolReturnsRankedResultsWithoutSummaryWarmup() async throws {
        try await withRuntime { runtime, database, activityAI in
            await runtime.update(
                activeDay: Date(timeIntervalSince1970: 0),
                overviews: [],
                activities: [],
                configuration: .default
            )
            try await database.saveOverviewRecord(OverviewInput(
                id: 1,
                title: "Invoices",
                summary: "Preparing invoices for the billing run.",
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
                summary: "Reviewed invoice filing steps.",
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
                    description: "Invoice checklist",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )
            try await database.saveOverviewRecord(OverviewInput(
                id: 2,
                title: "Taxes",
                summary: "Preparing tax packets.",
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
                summary: "Reviewed invoice reconciliation code.",
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
                    description: "Invoice reconciliation notes",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )
            await activityAI.setRerankingScoresByDocument([
                "Preparing invoices for the billing run.": 0.2,
                "Reviewed invoice filing steps.": 0.4,
                "Invoice checklist": 0.1,
                "Preparing tax packets.": 0.3,
                "Reviewed invoice reconciliation code.": 0.9,
                "Invoice reconciliation notes": 0.7
            ])

            let response = try await runtime.callSearchTool(query: "invoice", limit: 10)

            #expect(response.results.first?.result.id == 2)
            #expect(response.results.first?.rank == 1)
            #expect(response.results.first?.score == 1)
            #expect(await activityAI.currentSearchSummaryWarmupCallCount() == 0)
        }
    }
}

private func localDate(dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
    let calendar = Calendar(identifier: .gregorian)
    let baseDay = calendar.startOfDay(for: Date())
    let shiftedDay = calendar.date(byAdding: .day, value: dayOffset, to: baseDay) ?? baseDay
    return calendar.date(byAdding: .minute, value: hour * 60 + minute, to: shiftedDay) ?? shiftedDay
}
