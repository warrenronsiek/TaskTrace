import Foundation
import GRDB
import MLXLMCommon
import Testing
@testable import TaskTrace

@MainActor
struct GoalTodoAssignmentActorTests {
    @Test("goal todo assignment instructions prefer nil for weak matches")
    func goalTodoAssignmentInstructionsPreferNilForWeakMatches() {
        #expect(GoalTodoAssignmentActor.instructions.contains("Return nil when no todo is a direct semantic match"))
    }

    @Test("goal todo assignment prompt uses zero indexed todo candidates")
    func goalTodoAssignmentPromptUsesZeroIndexedTodoCandidates() async throws {
        try await withFixture(response: "0") { fixture in
            try await fixture.seedOpenTodo(id: 42, name: "Leetcode", goalName: "Algorithms")
            await fixture.actorSystem.broadcast(from: nil, message: ActivitySummarized(activity: fixture.activity()))
            try await waitUntil {
                await fixture.textResponder.firstPrompt()?.contains("0. goal: Algorithms\n  todo: Leetcode") == true
            }
            let prompt = await fixture.textResponder.firstPrompt()

            #expect(prompt?.contains("0. goal: Algorithms\n  todo: Leetcode") == true)
        }
    }

    @Test("goal todo assignment prompt includes standalone todos")
    func goalTodoAssignmentPromptIncludesStandaloneTodos() async throws {
        try await withFixture(response: "0") { fixture in
            try await fixture.seedStandaloneTodo(id: 42, name: "Leetcode")
            await fixture.actorSystem.broadcast(from: nil, message: ActivitySummarized(activity: fixture.activity()))
            try await waitUntil {
                await fixture.textResponder.firstPrompt()?.contains("0. standalone todo\n  todo: Leetcode") == true
            }
            let prompt = await fixture.textResponder.firstPrompt()

            #expect(prompt?.contains("0. standalone todo\n  todo: Leetcode") == true)
        }
    }

    @Test("goal todo assignment maps model index to todo id")
    func goalTodoAssignmentMapsModelIndexToTodoID() async throws {
        try await withFixture(response: "0") { fixture in
            try await fixture.seedOpenTodo(id: 42, name: "Study", goalName: "Learning")
            try await fixture.seedOpenTodo(id: 84, name: "Leetcode", goalName: "Algorithms")
            await fixture.actorSystem.broadcast(from: nil, message: ActivitySummarized(activity: fixture.activity()))
            try await waitUntil {
                await fixture.collector.decisions().first?.todoID == 84
            }
            let decision = await fixture.collector.decisions().first

            #expect(decision?.todoID == 84)
        }
    }

    @Test("goal todo assignment nil response emits nil todo id")
    func goalTodoAssignmentNilResponseEmitsNilTodoID() async throws {
        try await withFixture(response: "nil") { fixture in
            try await fixture.seedOpenTodo(id: 42, name: "Study", goalName: "Learning")
            await fixture.actorSystem.broadcast(from: nil, message: ActivitySummarized(activity: fixture.activity()))
            try await waitUntil {
                await fixture.collector.decisions().first != nil
            }
            let decision = await fixture.collector.decisions().first

            #expect(decision?.todoID == nil)
        }
    }

    @Test("goal todo assignment invalid response emits nil todo id")
    func goalTodoAssignmentInvalidResponseEmitsNilTodoID() async throws {
        try await withFixture(response: "not sure") { fixture in
            try await fixture.seedOpenTodo(id: 42, name: "Study", goalName: "Learning")
            await fixture.actorSystem.broadcast(from: nil, message: ActivitySummarized(activity: fixture.activity()))
            try await waitUntil {
                await fixture.collector.decisions().first != nil
            }
            let decision = await fixture.collector.decisions().first

            #expect(decision?.todoID == nil)
        }
    }

    @Test("goal todo assignment out of range response emits nil todo id")
    func goalTodoAssignmentOutOfRangeResponseEmitsNilTodoID() async throws {
        try await withFixture(response: "2") { fixture in
            try await fixture.seedOpenTodo(id: 42, name: "Study", goalName: "Learning")
            await fixture.actorSystem.broadcast(from: nil, message: ActivitySummarized(activity: fixture.activity()))
            try await waitUntil {
                await fixture.collector.decisions().first != nil
            }
            let decision = await fixture.collector.decisions().first

            #expect(decision?.todoID == nil)
        }
    }

    @Test("goal todo assignment persists automatic assignment")
    func goalTodoAssignmentPersistsAutomaticAssignment() async throws {
        try await withFixture(response: "0", registersGoalActor: true) { fixture in
            try await fixture.seedOpenTodo(id: 42, name: "Leetcode", goalName: "Algorithms")
            try await fixture.activityDatabaseActor.saveActivityRecord(fixture.activityInput())
            await fixture.actorSystem.broadcast(from: nil, message: ActivitySummarized(activity: fixture.activity()))
            try await waitUntil {
                try await fixture.assignedTodoID(activityID: 100) == 42
            }
            let assignedTodoID = try await fixture.assignedTodoID(activityID: 100)

            #expect(assignedTodoID == 42)
        }
    }

    @Test("goal todo assignment does not overwrite manual assignment")
    func goalTodoAssignmentDoesNotOverwriteManualAssignment() async throws {
        try await withFixture(response: "1", registersGoalActor: true) { fixture in
            try await fixture.seedOpenTodo(id: 42, name: "Leetcode", goalName: "Algorithms")
            try await fixture.seedOpenTodo(id: 84, name: "Study", goalName: "Learning")
            try await fixture.activityDatabaseActor.saveActivityRecord(fixture.activityInput())
            try await fixture.goalsDatabaseActor.assignActivity(
                activityID: 100,
                todoID: 84,
                source: .manual,
                score: nil,
                now: fixture.now
            )
            await fixture.actorSystem.broadcast(from: nil, message: ActivitySummarized(activity: fixture.activity()))
            try await Task.sleep(for: .milliseconds(80))
            let assignedTodoID = try await fixture.assignedTodoID(activityID: 100)

            #expect(assignedTodoID == 84)
        }
    }

    private struct Fixture {
        let now = Date(timeIntervalSince1970: 1_765_000_000)
        let database: TaskTraceDatabase
        let actorSystem: ActorSystem
        let goalsDatabaseActor: GoalsDatabaseActor
        let activityDatabaseActor: ActivityDatabaseActor
        let textResponder: GoalAssignmentTextResponder
        let collector: GoalAssignmentDecisionCollector

        func activity(goalTodoID: Int64? = nil) -> ActivityActor.Activity {
            ActivityActor.Activity(
                id: 100,
                application: "com.apple.dt.Xcode",
                startTime: now,
                keystrokes: "",
                microphone: "",
                summary: "Solved a dynamic programming Leetcode problem in Swift.",
                overviewID: nil,
                tagID: nil,
                goalTodoID: goalTodoID,
                goalTodoAssignmentSource: goalTodoID == nil ? nil : .manual,
                screenshots: [
                    ActivityActor.Screenshot(
                        id: 101,
                        image: nil,
                        timestamp: now,
                        description: nil,
                        text: nil,
                        summary: "Leetcode dynamic programming editor and tests.",
                        ignoreReason: nil
                    )
                ]
            )
        }

        func activityInput() -> ActivityInput {
            ActivityInput(
                id: 100,
                startTime: now,
                application: "com.apple.dt.Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Solved a dynamic programming Leetcode problem in Swift.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            )
        }

        func seedOpenTodo(id: Int64, name: String, goalName: String) async throws {
            try await goalsDatabaseActor.saveGoal(
                GoalInput(
                    id: id * 10,
                    name: goalName,
                    description: nil,
                    createTs: now,
                    doneTs: nil
                )
            )
            try await goalsDatabaseActor.saveTodo(
                GoalTodoInput(
                    id: id,
                    goalID: id * 10,
                    name: name,
                    createTs: now,
                    status: .open,
                    statusTs: nil,
                    repeating: false,
                    repeatTemplateID: nil,
                    targetDate: now,
                    dailyTargetSeconds: nil
                )
            )
        }

        func seedStandaloneTodo(id: Int64, name: String) async throws {
            try await goalsDatabaseActor.saveTodo(
                GoalTodoInput(
                    id: id,
                    goalID: nil,
                    name: name,
                    createTs: now,
                    status: .open,
                    statusTs: nil,
                    repeating: false,
                    repeatTemplateID: nil,
                    targetDate: now,
                    dailyTargetSeconds: nil
                )
            )
        }

        func assignedTodoID(activityID: Int64) async throws -> Int64? {
            try database.read { db in
                try Int64.fetchOne(
                    db,
                    sql: "SELECT goal_todo_id FROM activities WHERE id = ?",
                    arguments: [activityID]
                )
            }
        }
    }

    private func withFixture(
        response: String,
        registersGoalActor: Bool = false,
        _ block: (Fixture) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL)
        let actorSystem = ActorSystem()
        let goalsDatabaseActor = GoalsDatabaseActor(database: database)
        let textResponder = GoalAssignmentTextResponder(actorSystem: actorSystem, response: response)
        let collector = GoalAssignmentDecisionCollector()
        let assignmentActor = GoalTodoAssignmentActor(
            actorSystem: actorSystem,
            goalsDatabaseActor: goalsDatabaseActor
        )

        _ = await actorSystem.register(textResponder)
        _ = await actorSystem.register(collector)
        _ = await actorSystem.register(assignmentActor)

        if registersGoalActor {
            _ = await actorSystem.register(
                GoalTodoActor(
                    goalsDatabaseActor: goalsDatabaseActor,
                    actorSystem: actorSystem,
                    now: { Date(timeIntervalSince1970: 1_765_000_000) }
                )
            )
        }

        try await block(
            Fixture(
                database: database,
                actorSystem: actorSystem,
                goalsDatabaseActor: goalsDatabaseActor,
                activityDatabaseActor: ActivityDatabaseActor(database: database),
                textResponder: textResponder,
                collector: collector
            )
        )
    }
}

private actor GoalAssignmentTextResponder: Receiver {
    private let actorSystem: ActorSystem
    private let response: String
    private var prompts: [String] = []

    init(actorSystem: ActorSystem, response: String) {
        self.actorSystem = actorSystem
        self.response = response
    }

    func receive(_ envelope: Envelope) async {
        guard let request = envelope.message as? ModelTextRequest,
              request.source == "activity-goal-todo-assignment" else {
            return
        }

        prompts.append(request.prompt)
        let now = Date()
        await actorSystem.broadcast(
            from: nil,
            message: ModelTextCompleted(
                requestID: request.requestID,
                response: response,
                schedulerMetadata: AISchedulerMetadata(
                    scheduler: .textSmall,
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

    func firstPrompt() -> String? {
        prompts.first
    }
}

private actor GoalAssignmentDecisionCollector: Receiver {
    private var records: [GoalTodoAssignmentDecided] = []

    func receive(_ envelope: Envelope) async {
        guard let decision = envelope.message as? GoalTodoAssignmentDecided else {
            return
        }

        records.append(decision)
    }

    func decisions() -> [GoalTodoAssignmentDecided] {
        records
    }
}

private func waitUntil(
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(10),
    _ condition: @escaping () async throws -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout

    while ContinuousClock.now < deadline {
        if try await condition() {
            return
        }

        try await Task.sleep(for: pollInterval)
    }

    Issue.record("condition not met before timeout")
}
