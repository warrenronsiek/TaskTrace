//
//  SkillsTests.swift
//  TaskTraceTests
//
//  Created by Codex on 4/21/26.
//

import Foundation
import Testing
@testable import TaskTrace

struct SkillsTests {
    private func withDatabase(
        _ block: (TaskTraceDatabase) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())

        try await block(database)
    }

    @Test("skill context retrieval is current day and chronological")
    func skillContextRetrievalIsCurrentDayAndChronological() async throws {
        try await withDatabase { database in
            let activityDatabaseActor = ActivityDatabaseActor(database: database)

            try await database.saveActivityRecord(ActivityInput(
                id: 2,
                startTime: localDate(dayOffset: 0, hour: 10),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Build the importer.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 1,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Plan the importer.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 3,
                startTime: localDate(dayOffset: -1, hour: 9),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Yesterday importer work.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await activityDatabaseActor.persistActivitySummaryVector(activityID: 1, vector: activityEmbedding(activatedDimension: 0))
            try await activityDatabaseActor.persistActivitySummaryVector(activityID: 2, vector: activityEmbedding(activatedDimension: 0))
            try await activityDatabaseActor.persistActivitySummaryVector(activityID: 3, vector: activityEmbedding(activatedDimension: 0))

            let context = try await SearchDatabaseActor(database: database).skillContext(
                ftsQuery: "",
                queryVectorJSONString: try vectorJSONString(activityEmbedding(activatedDimension: 0)),
                day: localDate(dayOffset: 0, hour: 12)
            )

            #expect(context.map(\.id) == [1, 2])
        }
    }

    @Test("skill context retrieval includes screenshot FTS matches")
    func skillContextRetrievalIncludesScreenshotFTSMatches() async throws {
        try await withDatabase { database in
            try await database.saveActivityRecord(ActivityInput(
                id: 10,
                startTime: localDate(dayOffset: 0, hour: 11),
                application: "Safari",
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
                    id: 20,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 11, minute: 5),
                    description: "Receivables aging table",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            let context = try await SearchDatabaseActor(database: database).skillContext(
                ftsQuery: "\"receivables\"",
                queryVectorJSONString: try vectorJSONString(activityEmbedding(activatedDimension: 0)),
                day: localDate(dayOffset: 0, hour: 12)
            )

            #expect(context.first?.screenshots.map(\.description) == ["Receivables aging table"])
        }
    }

    @Test("skill context retrieval does not cap matching activity rows")
    func skillContextRetrievalDoesNotCapMatchingActivityRows() async throws {
        try await withDatabase { database in
            for index in 1...6 {
                try await database.saveActivityRecord(ActivityInput(
                    id: Int64(index),
                    startTime: localDate(dayOffset: 0, hour: 8 + index),
                    application: "Notes",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "cake recipe step \(index)",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: nil
                ))
            }

            let context = try await SearchDatabaseActor(database: database).skillContext(
                ftsQuery: "\"cake\"",
                queryVectorJSONString: try vectorJSONString(activityEmbedding(activatedDimension: 0)),
                day: localDate(dayOffset: 0, hour: 18)
            )

            #expect(context.count == 6)
        }
    }

    @Test("skill thinking parser discards completed thinking")
    func skillThinkingParserDiscardsCompletedThinking() {
        let parsed = SkillThinkingParser.parse("<think>inspect context</think># Procedure")
        #expect(parsed == SkillThinkingParseResult(markdown: "# Procedure", activeThinkingText: ""))
    }

    @Test("skill thinking parser exposes active thinking")
    func skillThinkingParserExposesActiveThinking() {
        let parsed = SkillThinkingParser.parse("<think>still reasoning")
        #expect(parsed.activeThinkingText == "still reasoning")
    }

    @Test("skill prompt renders markdown evidence")
    func skillPromptRendersMarkdownEvidence() throws {
        let prompt = try SkillGenerationService.prompt(query: "Build importer", context: [promptContextActivity()])
        #expect(prompt.contains("# Evidence\n\nThe following activity array is in chronological order.\n\n- Activity:"))
    }

    @Test("skill prompt excludes activity ids")
    func skillPromptExcludesActivityIDs() throws {
        let prompt = try SkillGenerationService.prompt(query: "Build importer", context: [promptContextActivity()])
        #expect(!prompt.contains("987654321"))
    }

    @Test("skill prompt excludes XML activity tags")
    func skillPromptExcludesXMLActivityTags() throws {
        let prompt = try SkillGenerationService.prompt(query: "Build importer", context: [promptContextActivity()])
        #expect(!prompt.contains("<activity"))
    }

    @Test("skill Obsidian writer writes under TaskTrace Skills")
    func skillObsidianWriterWritesUnderTaskTraceSkills() async throws {
        try await withDatabase { database in
            let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let knowledgeDatabaseActor = KnowledgeDatabaseActor(database: database)
            try await knowledgeDatabaseActor.saveKnowledgeDirectory(KnowledgeDirectoryInput(
                id: 1,
                slot: .obsidianVault,
                path: rootURL.path,
                bookmarkData: nil,
                createdAt: localDate(dayOffset: 0, hour: 8)
            ))
            let writer = SkillObsidianWriter(knowledgeDatabaseActor: knowledgeDatabaseActor)
            let target = try await #require(writer.createTarget(
                query: "Build importer",
                createdAt: localDate(dayOffset: 0, hour: 9)
            ))

            try await writer.write(markdown: "# Build importer", target: target)

            #expect(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("TaskTrace/Skills").path))
        }
    }

    private func localDate(dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let base = calendar.startOfDay(for: Date())
        return calendar.date(
            byAdding: DateComponents(day: dayOffset, hour: hour, minute: minute),
            to: base
        ) ?? base
    }

    private func activityEmbedding(activatedDimension: Int) -> [Float] {
        (0..<TaskTraceDatabaseBootstrap.activityEmbeddingDimension).map {
            $0 == activatedDimension ? 1 : 0
        }
    }

    private func vectorJSONString(_ vector: [Float]) throws -> String {
        String(
            decoding: try JSONEncoder().encode(vector),
            as: UTF8.self
        )
    }

    private func promptContextActivity() -> SkillContextActivity {
        SkillContextActivity(
            id: 987654321,
            startTime: localDate(dayOffset: 0, hour: 9),
            application: "Xcode",
            keystrokes: "swift build",
            microphone: "I am building the importer by validating the source file first.",
            summary: "Built an importer.",
            screenshots: [
                SkillContextScreenshot(
                    timestamp: localDate(dayOffset: 0, hour: 9, minute: 5),
                    summary: "Checking importer validation.",
                    description: "The importer validation screen is open."
                )
            ]
        )
    }
}
