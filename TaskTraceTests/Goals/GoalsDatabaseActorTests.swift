import Foundation
import GRDB
import Testing
@testable import TaskTrace

@MainActor
struct GoalsDatabaseActorTests {
    @Test("migration sets the goal schema version")
    func migrationSetsTheGoalSchemaVersion() async throws {
        try await withGoalsDatabase { database, _ in
            let version = try database.getVersion()
            #expect(version == 46)
        }
    }

    @Test("daily maintenance creates one repeated todo instance for today")
    func dailyMaintenanceCreatesOneRepeatedTodoInstanceForToday() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            try await goalsDatabaseActor.saveGoal(
                GoalInput(
                    id: 1,
                    name: "Daily progress",
                    description: nil,
                    createTs: now,
                    doneTs: nil
                )
            )
            try await goalsDatabaseActor.saveTodo(
                GoalTodoInput(
                    id: 2,
                    goalID: 1,
                    name: "Write",
                    createTs: now,
                    status: .open,
                    statusTs: nil,
                    repeating: true,
                    repeatTemplateID: nil,
                    targetDate: nil,
                    dailyTargetSeconds: 1_800
                )
            )
            try await goalsDatabaseActor.runDailyMaintenance(now: now)
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let instanceCount = try database.read { db in
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*)
                        FROM goal_todos
                        WHERE repeat_template_id = 2
                        """
                ) ?? 0
            }

            #expect(instanceCount == 1)
        }
    }

    @Test("daily goal duration rollup sums assigned activity duration")
    func dailyGoalDurationRollupSumsAssignedActivityDuration() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, repeatTemplateID: nil, targetDate: nil, dailyTargetSeconds: nil))
            try await activityDatabaseActor.saveActivityRecord(ActivityInput(id: 3, startTime: now, application: "com.example.App", keystrokes: nil, microphone: nil, summary: "Start", tagID: nil, jsonProperties: nil, overviewID: nil))
            try await activityDatabaseActor.saveActivityRecord(ActivityInput(id: 4, startTime: now.addingTimeInterval(1_800), application: "com.example.App", keystrokes: nil, microphone: nil, summary: "Next", tagID: nil, jsonProperties: nil, overviewID: nil))
            try await goalsDatabaseActor.assignActivity(activityID: 3, todoID: 2, source: .manual, score: nil, now: now)

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: now.addingTimeInterval(-86_400),
                visibleEnd: now.addingTimeInterval(86_400),
                selectedDay: now
            )

            #expect(snapshot.dailyGoalDurations.first?.duration == 1_800)
        }
    }

    @Test("completed todo rollup counts status day")
    func completedTodoRollupCountsStatusDay() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let targetDate = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .done, statusTs: now, repeating: false, repeatTemplateID: nil, targetDate: targetDate, dailyTargetSeconds: 1_800))

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: targetDate.addingTimeInterval(-86_400),
                visibleEnd: now.addingTimeInterval(86_400),
                selectedDay: now
            )

            #expect(snapshot.dailyCompletedTodoCounts.contains { Calendar(identifier: .gregorian).isDate($0.day, inSameDayAs: now) })
        }
    }

    @Test("rewound snapshot hides todo deleted after selected day")
    func rewoundSnapshotHidesTodoDeletedAfterSelectedDay() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let deleteTs = now.addingTimeInterval(3_600)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, repeatTemplateID: nil, targetDate: nil, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.softDeleteTodo(id: 2, now: deleteTs)

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: now.addingTimeInterval(-86_400),
                visibleEnd: now.addingTimeInterval(86_400),
                selectedDay: now
            )

            #expect(snapshot.todos.isEmpty)
        }
    }

    @Test("rewound snapshot hides todos created after selected day")
    func rewoundSnapshotHidesTodosCreatedAfterSelectedDay() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let selectedDay = Date(timeIntervalSince1970: 1_765_000_000)
            let futureDay = selectedDay.addingTimeInterval(86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: selectedDay, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Future", createTs: futureDay, status: .open, statusTs: nil, repeating: false, repeatTemplateID: nil, targetDate: futureDay, dailyTargetSeconds: nil))

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: selectedDay.addingTimeInterval(-86_400),
                visibleEnd: futureDay,
                selectedDay: selectedDay
            )

            #expect(snapshot.todos.isEmpty)
        }
    }

    @Test("rewound snapshot carries forward undated open todo")
    func rewoundSnapshotCarriesForwardUndatedOpenTodo() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let selectedDay = Date(timeIntervalSince1970: 1_765_000_000)
            let pastDay = selectedDay.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: pastDay, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Carry", createTs: pastDay, status: .open, statusTs: nil, repeating: false, repeatTemplateID: nil, targetDate: nil, dailyTargetSeconds: nil))

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: pastDay,
                visibleEnd: selectedDay,
                selectedDay: selectedDay
            )

            #expect(snapshot.todos.first?.id == 2)
        }
    }

    @Test("rewound snapshot hides todo completed before selected day")
    func rewoundSnapshotHidesTodoCompletedBeforeSelectedDay() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let selectedDay = Date(timeIntervalSince1970: 1_765_000_000)
            let pastDay = selectedDay.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: pastDay, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Done", createTs: pastDay, status: .done, statusTs: pastDay, repeating: false, repeatTemplateID: nil, targetDate: nil, dailyTargetSeconds: nil))

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: pastDay,
                visibleEnd: selectedDay,
                selectedDay: selectedDay
            )

            #expect(snapshot.todos.isEmpty)
        }
    }

    @Test("daily maintenance fails historical todo below quota")
    func dailyMaintenanceFailsHistoricalTodoBelowQuota() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let targetDate = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, repeatTemplateID: nil, targetDate: targetDate, dailyTargetSeconds: 1_800))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let status = try database.read { db in
                try String.fetchOne(db, sql: "SELECT status FROM goal_todos WHERE id = 2")
            }

            #expect(status == GoalTodoStatus.failed.rawValue)
        }
    }

    @Test("daily maintenance completes historical todo that meets quota")
    func dailyMaintenanceCompletesHistoricalTodoThatMeetsQuota() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let targetDate = now.addingTimeInterval(-86_400)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, repeatTemplateID: nil, targetDate: targetDate, dailyTargetSeconds: 1_800))
            try await activityDatabaseActor.saveActivityRecord(ActivityInput(id: 3, startTime: targetDate, application: "com.example.App", keystrokes: nil, microphone: nil, summary: "Start", tagID: nil, jsonProperties: nil, overviewID: nil))
            try await activityDatabaseActor.saveActivityRecord(ActivityInput(id: 4, startTime: targetDate.addingTimeInterval(1_800), application: "com.example.App", keystrokes: nil, microphone: nil, summary: "Next", tagID: nil, jsonProperties: nil, overviewID: nil))
            try database.write { db in
                try db.execute(sql: "UPDATE activities SET goal_todo_id = 2 WHERE id = 3")
            }
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let status = try database.read { db in
                try String.fetchOne(db, sql: "SELECT status FROM goal_todos WHERE id = 2")
            }

            #expect(status == GoalTodoStatus.done.rawValue)
        }
    }

    @Test("manual activity assignment is not overwritten by automatic matching")
    func manualActivityAssignmentIsNotOverwrittenByAutomaticMatching() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Manual", createTs: now, status: .open, statusTs: nil, repeating: false, repeatTemplateID: nil, targetDate: nil, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 3, goalID: 1, name: "Auto", createTs: now, status: .open, statusTs: nil, repeating: false, repeatTemplateID: nil, targetDate: nil, dailyTargetSeconds: nil))
            try await activityDatabaseActor.saveActivityRecord(
                ActivityInput(
                    id: 4,
                    startTime: now,
                    application: "com.example.App",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "Working on a goal",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: nil
                )
            )
            try await goalsDatabaseActor.assignActivity(
                activityID: 4,
                todoID: 2,
                source: .manual,
                score: nil,
                now: now
            )
            try await goalsDatabaseActor.saveTodoEmbedding(todoID: 3, vector: [1, 0, 0])
            _ = try await goalsDatabaseActor.assignBestOpenTodo(
                activityID: 4,
                vector: [1, 0, 0],
                minimumSimilarity: 0.1,
                minimumMargin: 0,
                now: now
            )

            let assignedTodoID = try database.read { db in
                try Int64.fetchOne(
                    db,
                    sql: "SELECT goal_todo_id FROM activities WHERE id = 4"
                )
            }

            #expect(assignedTodoID == 2)
        }
    }

    @Test("automatic matching assigns an open todo")
    func automaticMatchingAssignsAnOpenTodo() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Auto", createTs: now, status: .open, statusTs: nil, repeating: false, repeatTemplateID: nil, targetDate: nil, dailyTargetSeconds: nil))
            try await activityDatabaseActor.saveActivityRecord(
                ActivityInput(
                    id: 3,
                    startTime: now,
                    application: "com.example.App",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "Working on a goal",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: nil
                )
            )
            try await goalsDatabaseActor.saveTodoEmbedding(todoID: 2, vector: [1, 0, 0])
            _ = try await goalsDatabaseActor.assignBestOpenTodo(
                activityID: 3,
                vector: [1, 0, 0],
                minimumSimilarity: 0.1,
                minimumMargin: 0,
                now: now
            )

            let assignedTodoID = try database.read { db in
                try Int64.fetchOne(
                    db,
                    sql: "SELECT goal_todo_id FROM activities WHERE id = 3"
                )
            }

            #expect(assignedTodoID == 2)
        }
    }

    @Test("manual assignment completes a todo when its daily target is reached")
    func manualAssignmentCompletesATodoWhenItsDailyTargetIsReached() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Target", createTs: now, status: .open, statusTs: nil, repeating: false, repeatTemplateID: nil, targetDate: now, dailyTargetSeconds: 1_800))
            try await activityDatabaseActor.saveActivityRecord(
                ActivityInput(
                    id: 3,
                    startTime: now,
                    application: "com.example.App",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "First activity",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: nil
                )
            )
            try await activityDatabaseActor.saveActivityRecord(
                ActivityInput(
                    id: 4,
                    startTime: now.addingTimeInterval(1_800),
                    application: "com.example.App",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "Second activity",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: nil
                )
            )
            try await goalsDatabaseActor.assignActivity(
                activityID: 3,
                todoID: 2,
                source: .manual,
                score: nil,
                now: now
            )

            let status = try database.read { db in
                try String.fetchOne(
                    db,
                    sql: "SELECT status FROM goal_todos WHERE id = 2"
                )
            }

            #expect(status == GoalTodoStatus.done.rawValue)
        }
    }

    @Test("soft deleting a goal hides the goal snapshot")
    func softDeletingAGoalHidesTheGoalSnapshot() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, repeatTemplateID: nil, targetDate: nil, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.softDeleteGoal(id: 1, now: now)

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: now.addingTimeInterval(-86_400),
                visibleEnd: now.addingTimeInterval(86_400),
                selectedDay: now
            )

            #expect(snapshot == GoalsSnapshot(goals: [], todos: [], goalRollups: [], todoRollups: [], dailyGoalDurations: [], dailyCompletedTodoCounts: []))
        }
    }

    @Test("rewound snapshot hides goal deleted after selected day")
    func rewoundSnapshotHidesGoalDeletedAfterSelectedDay() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, repeatTemplateID: nil, targetDate: nil, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.softDeleteGoal(id: 1, now: now.addingTimeInterval(3_600))

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: now.addingTimeInterval(-86_400),
                visibleEnd: now.addingTimeInterval(86_400),
                selectedDay: now
            )

            #expect(snapshot.goals.isEmpty)
        }
    }

    @Test("loading activity includes manual goal todo assignment")
    func loadingActivityIncludesManualGoalTodoAssignment() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, repeatTemplateID: nil, targetDate: nil, dailyTargetSeconds: nil))
            try await activityDatabaseActor.saveActivityRecord(
                ActivityInput(
                    id: 3,
                    startTime: now,
                    application: "com.example.App",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "Working on a goal",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: nil
                )
            )
            try await goalsDatabaseActor.assignActivity(
                activityID: 3,
                todoID: 2,
                source: .manual,
                score: nil,
                now: now
            )

            let loadedActivity = try await activityDatabaseActor.loadActivities(for: now).first

            #expect(loadedActivity?.goalTodoID == 2)
        }
    }
}

@MainActor
private func withGoalsDatabase(
    _ block: (TaskTraceDatabase, GoalsDatabaseActor) async throws -> Void
) async throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

    let database = try TaskTraceDatabase(databaseURL: databaseURL)
    let goalsDatabaseActor = GoalsDatabaseActor(database: database)

    try await block(database, goalsDatabaseActor)
}
