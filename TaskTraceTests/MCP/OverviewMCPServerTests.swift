//
//  OverviewMCPServerTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/21/26.
//

import Foundation
import MCP
import Testing
import UserNotifications
@testable import TaskTrace

@MainActor
struct OverviewMCPServerTests {
    @Test("tool list includes the search tool when it is enabled")
    func toolListIncludesTheSearchToolWhenItIsEnabled() async {
        let runtime = OverviewMCPServerRuntime(searchService: makeSearchService())
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.searchToolEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect((await runtime.toolNames()).contains(Vars.mcpSearchToolName))
    }

    @Test("tool list omits the search tool when it is disabled")
    func toolListOmitsTheSearchToolWhenItIsDisabled() async {
        let runtime = OverviewMCPServerRuntime(searchService: makeSearchService())
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.searchToolEnabled = false

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect(!((await runtime.toolNames()).contains(Vars.mcpSearchToolName)))
    }

    @Test("resource list includes the overview feed when it is enabled")
    func resourceListIncludesTheOverviewFeedWhenItIsEnabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.overviewResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect((await runtime.resourceURIs()).contains(Vars.mcpOverviewResourceURI))
    }

    @Test("resource list omits the overview feed when it is disabled")
    func resourceListOmitsTheOverviewFeedWhenItIsDisabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.overviewResourceEnabled = false

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect(!((await runtime.resourceURIs()).contains(Vars.mcpOverviewResourceURI)))
    }

    @Test("resource list includes the high level feed when it is enabled")
    func resourceListIncludesTheHighLevelFeedWhenItIsEnabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.highLevelActivityResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect((await runtime.resourceURIs()).contains(Vars.mcpHighLevelActivityResourceURI))
    }

    @Test("the high level feed includes every summarized activity")
    func theHighLevelFeedIncludesEverySummarizedActivity() async {
        let runtime = OverviewMCPServerRuntime()
        let activities = (1...6).map { index in
            makeActivity(
                id: Int64(index),
                startTime: Date(timeIntervalSince1970: Double(index * 60)),
                summary: index == 1 ? "Oldest summarized activity" : "Summarized activity \(index)"
            )
        }

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: activities,
            configuration: .default
        )

        let highLevelFeedText = await runtime.resourceContents(uri: Vars.mcpHighLevelActivityResourceURI)?.first?.text ?? ""
        #expect(highLevelFeedText.contains("Oldest summarized activity"))
    }

    @Test("resource list omits the detailed feed when it is disabled")
    func resourceListOmitsTheDetailedFeedWhenItIsDisabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = false

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect(!((await runtime.resourceURIs()).contains(Vars.mcpDetailedActivityResourceURI)))
    }

    @Test("resource list includes the today todos feed by default")
    func resourceListIncludesTheTodayTodosFeedByDefault() async {
        let runtime = OverviewMCPServerRuntime()

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: .default
        )

        #expect((await runtime.resourceURIs()).contains(Vars.mcpTodayTodosResourceURI))
    }

    @Test("resource list omits the today todos feed when it is disabled")
    func resourceListOmitsTheTodayTodosFeedWhenItIsDisabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.todayTodosResourceEnabled = false

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect(!((await runtime.resourceURIs()).contains(Vars.mcpTodayTodosResourceURI)))
    }

    @Test("resource list includes the detailed feed when it is enabled")
    func resourceListIncludesTheDetailedFeedWhenItIsEnabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect((await runtime.resourceURIs()).contains(Vars.mcpDetailedActivityResourceURI))
    }

    @Test("the detailed feed includes every activity")
    func theDetailedFeedIncludesEveryActivity() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true
        let activities = (1...6).map { index in
            makeActivity(
                id: Int64(index),
                startTime: Date(timeIntervalSince1970: Double(index * 60)),
                keystrokes: index == 1 ? "oldest keystrokes" : "keystrokes \(index)",
                summary: nil
            )
        }

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: activities,
            configuration: configuration
        )

        let detailedFeedText = await runtime.resourceContents(uri: Vars.mcpDetailedActivityResourceURI)?.first?.text ?? ""
        #expect(detailedFeedText.contains("oldest keystrokes"))
    }

    @Test("resource template list includes the screenshot template when the detailed feed is enabled")
    func resourceTemplateListIncludesTheScreenshotTemplateWhenTheDetailedFeedIsEnabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect((await runtime.resourceTemplateURIs()).contains(Vars.mcpActivityScreenshotResourceTemplateURI))
    }

    @Test("resource template list omits the screenshot template when the detailed feed is disabled")
    func resourceTemplateListOmitsTheScreenshotTemplateWhenTheDetailedFeedIsDisabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = false

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect(!((await runtime.resourceTemplateURIs()).contains(Vars.mcpActivityScreenshotResourceTemplateURI)))
    }

    @Test("the detailed feed exposes screenshot URIs")
    func theDetailedFeedExposesScreenshotURIs() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true
        let screenshotData = Data("fake-webp-data".utf8)
        let expectedURI = Vars.mcpActivityScreenshotResourceURI(activityId: 123, screenshotId: 17)

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [
                makeActivity(
                    summary: nil,
                    screenshots: [
                        makeScreenshot(image: screenshotData)
                    ]
                )
            ],
            configuration: configuration
        )

        let detailedFeedText = await runtime.resourceContents(uri: Vars.mcpDetailedActivityResourceURI)?.first?.text ?? ""
        #expect(detailedFeedText.contains(expectedURI))
    }

    @Test("the detailed feed exposes screenshot descriptions")
    func theDetailedFeedExposesScreenshotDescriptions() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [
                makeActivity(
                    summary: nil,
                    screenshots: [
                        makeScreenshot()
                    ]
                )
            ],
            configuration: configuration
        )

        let detailedFeedText = await runtime.resourceContents(uri: Vars.mcpDetailedActivityResourceURI)?.first?.text ?? ""
        #expect(detailedFeedText.contains("VS Code showing MCP server code"))
    }

    @Test("the detailed feed exposes screenshot OCR")
    func theDetailedFeedExposesScreenshotOCR() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [
                makeActivity(
                    summary: nil,
                    screenshots: [
                        makeScreenshot()
                    ]
                )
            ],
            configuration: configuration
        )

        let detailedFeedText = await runtime.resourceContents(uri: Vars.mcpDetailedActivityResourceURI)?.first?.text ?? ""
        #expect(detailedFeedText.contains("resource template implementation"))
    }

    @Test("the detailed feed exposes screenshot summaries")
    func theDetailedFeedExposesScreenshotSummaries() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [
                makeActivity(
                    summary: nil,
                    screenshots: [
                        makeScreenshot()
                    ]
                )
            ],
            configuration: configuration
        )

        let detailedFeedText = await runtime.resourceContents(uri: Vars.mcpDetailedActivityResourceURI)?.first?.text ?? ""
        #expect(detailedFeedText.contains("Implementing the MCP resource template."))
    }

    @Test("the detailed feed omits embedded screenshot blobs")
    func theDetailedFeedOmitsEmbeddedScreenshotBlobs() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true
        let screenshotData = Data("fake-webp-data".utf8)

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [
                makeActivity(
                    summary: nil,
                    screenshots: [
                        makeScreenshot(image: screenshotData)
                    ]
                )
            ],
            configuration: configuration
        )

        let detailedFeedText = await runtime.resourceContents(uri: Vars.mcpDetailedActivityResourceURI)?.first?.text ?? ""
        #expect(!detailedFeedText.contains(screenshotData.base64EncodedString()))
    }

    @Test("reading a screenshot URI returns binary screenshot bytes")
    func readingAScreenshotURIReturnsBinaryScreenshotBytes() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true
        let screenshotData = Data("fake-webp-data".utf8)
        let screenshotURI = Vars.mcpActivityScreenshotResourceURI(activityId: 123, screenshotId: 17)

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [
                makeActivity(
                    summary: nil,
                    screenshots: [
                        makeScreenshot(image: screenshotData)
                    ]
                )
            ],
            configuration: configuration
        )

        let screenshotBlob = await runtime.resourceContents(uri: screenshotURI)?.first?.blob
        #expect(screenshotBlob == screenshotData.base64EncodedString())
    }

    @Test("the today todos feed exposes todo names")
    func theTodayTodosFeedExposesTodoNames() async throws {
        try await withGoalsRuntime { runtime, goalsDatabaseActor, _, _ in
            let today = localMCPDate(hour: 9)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Call accountant", createTs: today, status: .open, statusTs: nil, repeating: false, targetDate: today, dailyTargetSeconds: nil))

            await runtime.update(activeDay: today, overviews: [], activities: [], configuration: .default)

            let text = await runtime.resourceContents(uri: Vars.mcpTodayTodosResourceURI)?.first?.text ?? ""
            #expect(text.contains("Call accountant"))
        }
    }

    @Test("the today todos feed exposes goal names")
    func theTodayTodosFeedExposesGoalNames() async throws {
        try await withGoalsRuntime { runtime, goalsDatabaseActor, _, _ in
            let today = localMCPDate(hour: 9)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Finance", description: nil, createTs: today, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Call accountant", createTs: today, status: .open, statusTs: nil, repeating: false, targetDate: today, dailyTargetSeconds: nil))

            await runtime.update(activeDay: today, overviews: [], activities: [], configuration: .default)

            let text = await runtime.resourceContents(uri: Vars.mcpTodayTodosResourceURI)?.first?.text ?? ""
            #expect(text.contains("Finance"))
        }
    }

    @Test("tool list includes the add todo tool when goals are configured")
    func toolListIncludesTheAddTodoToolWhenGoalsAreConfigured() async throws {
        try await withGoalsRuntime { runtime, _, _, _ in
            await runtime.update(activeDay: localMCPDate(hour: 9), overviews: [], activities: [], configuration: .default)

            #expect((await runtime.toolNames()).contains(Vars.mcpAddTodoToolName))
        }
    }

    @Test("tool list includes the add goal tool when goals are configured")
    func toolListIncludesTheAddGoalToolWhenGoalsAreConfigured() async throws {
        try await withGoalsRuntime { runtime, _, _, _ in
            await runtime.update(activeDay: localMCPDate(hour: 9), overviews: [], activities: [], configuration: .default)

            #expect((await runtime.toolNames()).contains(Vars.mcpAddGoalToolName))
        }
    }

    @Test("tool list includes the push message tool by default")
    func toolListIncludesThePushMessageToolByDefault() async {
        let runtime = OverviewMCPServerRuntime()

        await runtime.update(activeDay: localMCPDate(hour: 9), overviews: [], activities: [], configuration: .default)

        #expect((await runtime.toolNames()).contains(Vars.mcpPushMessageToolName))
    }

    @Test("tool list omits the add todo tool when it is disabled")
    func toolListOmitsTheAddTodoToolWhenItIsDisabled() async throws {
        try await withGoalsRuntime { runtime, _, _, _ in
            var configuration = SettingsStore.MCPConfiguration.default
            configuration.addTodoToolEnabled = false

            await runtime.update(activeDay: localMCPDate(hour: 9), overviews: [], activities: [], configuration: configuration)

            #expect(!((await runtime.toolNames()).contains(Vars.mcpAddTodoToolName)))
        }
    }

    @Test("tool list omits the add goal tool when it is disabled")
    func toolListOmitsTheAddGoalToolWhenItIsDisabled() async throws {
        try await withGoalsRuntime { runtime, _, _, _ in
            var configuration = SettingsStore.MCPConfiguration.default
            configuration.addGoalToolEnabled = false

            await runtime.update(activeDay: localMCPDate(hour: 9), overviews: [], activities: [], configuration: configuration)

            #expect(!((await runtime.toolNames()).contains(Vars.mcpAddGoalToolName)))
        }
    }

    @Test("tool list omits the push message tool when it is disabled")
    func toolListOmitsThePushMessageToolWhenItIsDisabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.pushMessageToolEnabled = false

        await runtime.update(activeDay: localMCPDate(hour: 9), overviews: [], activities: [], configuration: configuration)

        #expect(!((await runtime.toolNames()).contains(Vars.mcpPushMessageToolName)))
    }

    @Test("add todo tool persists a todo")
    func addTodoToolPersistsATodo() async throws {
        try await withGoalsRuntime { runtime, goalsDatabaseActor, _, _ in
            let today = localMCPDate(hour: 9)
            await runtime.update(activeDay: today, overviews: [], activities: [], configuration: .default)

            _ = try await runtime.callAddTodoTool(name: "Send invoice")
            let snapshot = try await goalsDatabaseActor.loadSnapshot(visibleStart: today, visibleEnd: today, selectedDay: today)

            #expect(snapshot.todos.contains { $0.name == "Send invoice" })
        }
    }

    @Test("add todo tool attaches a todo to a goal")
    func addTodoToolAttachesATodoToAGoal() async throws {
        try await withGoalsRuntime { runtime, goalsDatabaseActor, _, _ in
            let today = localMCPDate(hour: 9)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Finance", description: nil, createTs: today, doneTs: nil))
            await runtime.update(activeDay: today, overviews: [], activities: [], configuration: .default)

            _ = try await runtime.callAddTodoTool(name: "Send invoice", goalID: 1)
            let snapshot = try await goalsDatabaseActor.loadSnapshot(visibleStart: today, visibleEnd: today, selectedDay: today)

            #expect(snapshot.todos.first { $0.name == "Send invoice" }?.goalID == 1)
        }
    }

    @Test("add todo tool is rejected when disabled")
    func addTodoToolIsRejectedWhenDisabled() async throws {
        try await withGoalsRuntime { runtime, _, _, _ in
            var configuration = SettingsStore.MCPConfiguration.default
            configuration.addTodoToolEnabled = false
            await runtime.update(activeDay: localMCPDate(hour: 9), overviews: [], activities: [], configuration: configuration)

            await #expect(throws: MCPError.self) {
                _ = try await runtime.callAddTodoTool(name: "Send invoice")
            }
        }
    }

    @Test("add goal tool persists a goal")
    func addGoalToolPersistsAGoal() async throws {
        try await withGoalsRuntime { runtime, goalsDatabaseActor, _, _ in
            let today = localMCPDate(hour: 9)
            await runtime.update(activeDay: today, overviews: [], activities: [], configuration: .default)

            _ = try await runtime.callAddGoalTool(name: "Finish taxes")
            let snapshot = try await goalsDatabaseActor.loadSnapshot(visibleStart: today, visibleEnd: today, selectedDay: today)

            #expect(snapshot.goals.contains { $0.name == "Finish taxes" })
        }
    }

    @Test("add goal tool is rejected when disabled")
    func addGoalToolIsRejectedWhenDisabled() async throws {
        try await withGoalsRuntime { runtime, _, _, _ in
            var configuration = SettingsStore.MCPConfiguration.default
            configuration.addGoalToolEnabled = false
            await runtime.update(activeDay: localMCPDate(hour: 9), overviews: [], activities: [], configuration: configuration)

            await #expect(throws: MCPError.self) {
                _ = try await runtime.callAddGoalTool(name: "Finish taxes")
            }
        }
    }

    @Test("push message tool creates a notification")
    func pushMessageToolCreatesANotification() async throws {
        let notificationCenter = FakeMCPNotificationCenter()
        let runtime = OverviewMCPServerRuntime(
            pushNotificationManager: TaskTracePushNotificationManager(notificationCenter: notificationCenter)
        )
        await runtime.update(activeDay: localMCPDate(hour: 9), overviews: [], activities: [], configuration: .default)

        _ = try await runtime.callPushMessageTool(message: "Review the failing build.", title: "OpenClaw", source: "Agent")

        #expect(await notificationCenter.requestCount() == 1)
    }

    @Test("push message tool rejects empty messages")
    func pushMessageToolRejectsEmptyMessages() async {
        let runtime = OverviewMCPServerRuntime()
        await runtime.update(activeDay: localMCPDate(hour: 9), overviews: [], activities: [], configuration: .default)

        await #expect(throws: MCPError.self) {
            _ = try await runtime.callPushMessageTool(message: " ")
        }
    }

    @Test("add todo tool broadcasts a goals reload")
    func addTodoToolBroadcastsAGoalsReload() async throws {
        try await withGoalsRuntime { runtime, _, _, receiver in
            await runtime.update(activeDay: localMCPDate(hour: 9), overviews: [], activities: [], configuration: .default)

            _ = try await runtime.callAddTodoTool(name: "Send invoice")

            #expect(await receiver.reloadCount() == 1)
        }
    }

    @Test("starting the broker creates the socket")
    func startingTheBrokerCreatesTheSocket() async {
        let socketPath = "/tmp/tasktrace-mcp-\(UUID().uuidString).sock"
        let runtime = OverviewMCPServerRuntime(socketPath: socketPath)

        await runtime.start()

        #expect(FileManager.default.fileExists(atPath: socketPath))
        await runtime.stop()
    }

    @Test("stopping the broker removes the socket")
    func stoppingTheBrokerRemovesTheSocket() async {
        let socketPath = "/tmp/tasktrace-mcp-\(UUID().uuidString).sock"
        let runtime = OverviewMCPServerRuntime(socketPath: socketPath)

        await runtime.start()
        await runtime.stop()

        #expect(!FileManager.default.fileExists(atPath: socketPath))
    }

}

private func makeActivity(
    id: Int64 = 123,
    startTime: Date = Date(timeIntervalSince1970: 60),
    application: String = "Xcode",
    keystrokes: String = "git push",
    microphone: String = "Discussed MCP changes",
    summary: String? = "Implemented the MCP server refactor",
    screenshots: [ActivityActor.Screenshot] = []
) -> ActivityActor.Activity {
    ActivityActor.Activity(
        id: id,
        application: application,
        startTime: startTime,
        keystrokes: keystrokes,
        microphone: microphone,
        summary: summary,
        overviewID: 99,
        tagID: 7,
        screenshots: screenshots
    )
}

private func makeSearchService() -> TaskTraceSearchService {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
    let activityAI = FakeActivityAI()

    try! FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

    return TaskTraceSearchService(
        database: try! TaskTraceDatabase(
            databaseURL: try! TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL),
            activityAI: activityAI
        ),
        activityAI: activityAI
    )
}

private func withGoalsRuntime(
    _ block: (OverviewMCPServerRuntime, GoalsDatabaseActor, TaskTraceDatabase, RecordingGoalsReceiver) async throws -> Void
) async throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let databaseURLAfterMigration = try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
    let database = try TaskTraceDatabase(databaseURL: databaseURLAfterMigration, activityAI: FakeActivityAI())
    let goalsDatabaseActor = GoalsDatabaseActor(database: database)
    let actorSystem = ActorSystem()
    let receiver = RecordingGoalsReceiver()
    _ = await actorSystem.register(receiver)
    let runtime = OverviewMCPServerRuntime(
        goalsDatabaseActor: goalsDatabaseActor,
        actorSystem: actorSystem,
        identifierActor: IdentifierActor(now: { localMCPDate(hour: 12) }, latestIdentifier: 10_000)
    )

    try await block(runtime, goalsDatabaseActor, database, receiver)
}

private actor RecordingGoalsReceiver: Receiver {
    private var count = 0

    func receive(_ envelope: Envelope) async {
        if envelope.message is GoalsReloadRequested {
            count += 1
        }
    }

    func reloadCount() -> Int {
        count
    }
}

private actor FakeMCPNotificationCenter: TaskTraceUserNotificationCenter {
    private var requests: [UNNotificationRequest] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
    }

    func requestCount() -> Int {
        requests.count
    }
}

private func localMCPDate(hour: Int, minute: Int = 0) -> Date {
    let calendar = Calendar(identifier: .gregorian)
    let components = DateComponents(
        calendar: calendar,
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2026,
        month: 5,
        day: 13,
        hour: hour,
        minute: minute
    )
    return components.date ?? Date(timeIntervalSince1970: 0)
}

private func makeScreenshot(
    id: Int64 = 17,
    image: Data? = Data("fake-webp-data".utf8),
    timestamp: Date = Date(timeIntervalSince1970: 90),
    description: String? = "VS Code showing MCP server code",
    text: String? = "resource template implementation",
    summary: String? = "Implementing the MCP resource template."
) -> ActivityActor.Screenshot {
    ActivityActor.Screenshot(
        id: id,
        image: image,
        timestamp: timestamp,
        description: description,
        text: text,
        summary: summary,
        ignoreReason: nil
    )
}
