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
            #expect(version == 50)
        }
    }

    @Test("migration removes repeat template id from goal todos")
    func migrationRemovesRepeatTemplateIDFromGoalTodos() async throws {
        try await withLegacyRepeatTemplateDatabase { database in
            let hasRepeatTemplateColumn = try database.read { db in
                try db.columns(in: "goal_todos").contains { $0.name == "repeat_template_id" }
            }

            #expect(hasRepeatTemplateColumn == false)
        }
    }

    @Test("migration converts legacy repeat instances into repeating todos")
    func migrationConvertsLegacyRepeatInstancesIntoRepeatingTodos() async throws {
        try await withLegacyRepeatTemplateDatabase { database in
            let isRepeating = try database.read { db in
                try Bool.fetchOne(db, sql: "SELECT repeating FROM goal_todos WHERE id = 2") ?? false
            }

            #expect(isRepeating == true)
        }
    }

    @Test("snapshot includes standalone todos")
    func snapshotIncludesStandaloneTodos() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Standalone", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: nil, dailyTargetSeconds: nil))

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: now.addingTimeInterval(-86_400),
                visibleEnd: now.addingTimeInterval(86_400),
                selectedDay: now
            )

            #expect(snapshot.todos.first?.goalID == nil)
        }
    }

    @Test("completed standalone todo counts without a goal id")
    func completedStandaloneTodoCountsWithoutAGoalID() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Standalone", createTs: now, status: .done, statusTs: now, repeating: false, targetDate: now, dailyTargetSeconds: nil))

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: now.addingTimeInterval(-86_400),
                visibleEnd: now.addingTimeInterval(86_400),
                selectedDay: now
            )

            #expect(snapshot.dailyTodoOutcomeCounts.first?.goalID == nil)
        }
    }

    @Test("target failure counts without a goal id")
    func targetFailureCountsWithoutAGoalID() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let targetDate = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Standalone", createTs: targetDate, status: .open, statusTs: nil, repeating: false, targetDate: targetDate, dailyTargetSeconds: 1_800))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: targetDate,
                visibleEnd: now,
                selectedDay: targetDate
            )

            #expect(snapshot.dailyTodoOutcomeCounts.first?.failedCount == 1)
        }
    }

    @Test("standalone todo duration rollup is available")
    func standaloneTodoDurationRollupIsAvailable() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Standalone", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: nil, dailyTargetSeconds: nil))
            try await activityDatabaseActor.saveActivityRecord(ActivityInput(id: 3, startTime: now, application: "com.example.App", keystrokes: nil, microphone: nil, summary: "Start", tagID: nil, jsonProperties: nil, overviewID: nil))
            try await activityDatabaseActor.saveActivityRecord(ActivityInput(id: 4, startTime: now.addingTimeInterval(1_800), application: "com.example.App", keystrokes: nil, microphone: nil, summary: "Next", tagID: nil, jsonProperties: nil, overviewID: nil))
            try await goalsDatabaseActor.assignActivity(activityID: 3, todoID: 2, source: .manual, score: nil, now: now)

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: now.addingTimeInterval(-86_400),
                visibleEnd: now.addingTimeInterval(86_400),
                selectedDay: now
            )

            #expect(snapshot.todoRollups.first?.duration == 1_800)
        }
    }

    @Test("standalone todo activity does not create goal duration")
    func standaloneTodoActivityDoesNotCreateGoalDuration() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Standalone", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: nil, dailyTargetSeconds: nil))
            try await activityDatabaseActor.saveActivityRecord(ActivityInput(id: 3, startTime: now, application: "com.example.App", keystrokes: nil, microphone: nil, summary: "Start", tagID: nil, jsonProperties: nil, overviewID: nil))
            try await activityDatabaseActor.saveActivityRecord(ActivityInput(id: 4, startTime: now.addingTimeInterval(1_800), application: "com.example.App", keystrokes: nil, microphone: nil, summary: "Next", tagID: nil, jsonProperties: nil, overviewID: nil))
            try await goalsDatabaseActor.assignActivity(activityID: 3, todoID: 2, source: .manual, score: nil, now: now)

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: now.addingTimeInterval(-86_400),
                visibleEnd: now.addingTimeInterval(86_400),
                selectedDay: now
            )

            #expect(snapshot.dailyGoalDurations.isEmpty)
        }
    }

    @Test("daily maintenance creates today todo from yesterday repeating todo")
    func dailyMaintenanceCreatesTodayTodoFromYesterdayRepeatingTodo() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let yesterday = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Standalone", createTs: yesterday, status: .open, statusTs: nil, repeating: true, targetDate: yesterday, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let instanceCount = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM goal_todos WHERE repeating = 1 AND DATE(target_date) = DATE(?)", arguments: [now.formatted(TaskTraceDatabase.sqlDateStyle)]) ?? 0
            }

            #expect(instanceCount == 1)
        }
    }

    @Test("daily maintenance is idempotent for today's repeated todo")
    func dailyMaintenanceIsIdempotentForTodaysRepeatedTodo() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let yesterday = now.addingTimeInterval(-86_400)
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
                    createTs: yesterday,
                    status: .open,
                    statusTs: nil,
                    repeating: true,
                    targetDate: yesterday,
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
                        WHERE repeating = 1
                          AND goal_id = 1
                          AND name = 'Write'
                          AND DATE(target_date) = DATE(?)
                        """,
                    arguments: [now.formatted(TaskTraceDatabase.sqlDateStyle)]
                ) ?? 0
            }

            #expect(instanceCount == 1)
        }
    }

    @Test("daily maintenance copies maximum target mode to today's repeated todo")
    func dailyMaintenanceCopiesMaximumTargetModeToTodaysRepeatedTodo() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let yesterday = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Daily limit", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Avoid social media", createTs: yesterday, status: .open, statusTs: nil, repeating: true, targetDate: yesterday, dailyTargetSeconds: 1_800, dailyTargetMode: .maximum))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let targetMode = try database.read { db in
                try String.fetchOne(db, sql: "SELECT daily_target_mode FROM goal_todos WHERE DATE(target_date) = DATE(?)", arguments: [now.formatted(TaskTraceDatabase.sqlDateStyle)])
            }

            #expect(targetMode == GoalTodoTargetMode.maximum.rawValue)
        }
    }

    @Test("daily maintenance repeats a completed yesterday todo")
    func dailyMaintenanceRepeatsACompletedYesterdayTodo() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let yesterday = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Repeat done", createTs: yesterday, status: .done, statusTs: yesterday, repeating: true, targetDate: yesterday, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let status = try database.read { db in
                try String.fetchOne(db, sql: "SELECT status FROM goal_todos WHERE DATE(target_date) = DATE(?) AND id <> 2", arguments: [now.formatted(TaskTraceDatabase.sqlDateStyle)])
            }

            #expect(status == GoalTodoStatus.open.rawValue)
        }
    }

    @Test("daily maintenance repeats a failed yesterday todo")
    func dailyMaintenanceRepeatsAFailedYesterdayTodo() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let yesterday = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Repeat failed", createTs: yesterday, status: .open, statusTs: nil, repeating: true, targetDate: yesterday, dailyTargetSeconds: 1_800))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let status = try database.read { db in
                try String.fetchOne(db, sql: "SELECT status FROM goal_todos WHERE DATE(target_date) = DATE(?) AND id <> 2", arguments: [now.formatted(TaskTraceDatabase.sqlDateStyle)])
            }

            #expect(status == GoalTodoStatus.open.rawValue)
        }
    }

    @Test("daily maintenance skips deleted yesterday repeating todo")
    func dailyMaintenanceSkipsDeletedYesterdayRepeatingTodo() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let yesterday = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Deleted repeat", createTs: yesterday, status: .open, statusTs: nil, repeating: true, targetDate: yesterday, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.softDeleteTodo(id: 2, now: yesterday)
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let instanceCount = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM goal_todos WHERE DATE(target_date) = DATE(?)", arguments: [now.formatted(TaskTraceDatabase.sqlDateStyle)]) ?? 0
            }

            #expect(instanceCount == 0)
        }
    }

    @Test("daily maintenance backfills missed repeating days")
    func dailyMaintenanceBackfillsMissedRepeatingDays() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let twoDaysAgo = now.addingTimeInterval(-172_800)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Old repeat", createTs: twoDaysAgo, status: .open, statusTs: nil, repeating: true, targetDate: twoDaysAgo, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let instanceCount = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM goal_todos WHERE repeating = 1 AND name = 'Old repeat'") ?? 0
            }

            #expect(instanceCount == 3)
        }
    }

    @Test("daily maintenance is idempotent for backfilled repeating days")
    func dailyMaintenanceIsIdempotentForBackfilledRepeatingDays() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let twoDaysAgo = now.addingTimeInterval(-172_800)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Old repeat", createTs: twoDaysAgo, status: .open, statusTs: nil, repeating: true, targetDate: twoDaysAgo, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let instanceCount = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM goal_todos WHERE repeating = 1 AND name = 'Old repeat'") ?? 0
            }

            #expect(instanceCount == 3)
        }
    }

    @Test("daily maintenance resolves backfilled historical target")
    func dailyMaintenanceResolvesBackfilledHistoricalTarget() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let twoDaysAgo = now.addingTimeInterval(-172_800)
            let yesterday = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Old repeat", createTs: twoDaysAgo, status: .open, statusTs: nil, repeating: true, targetDate: twoDaysAgo, dailyTargetSeconds: 1_800))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let status = try database.read { db in
                try String.fetchOne(db, sql: "SELECT status FROM goal_todos WHERE name = 'Old repeat' AND DATE(target_date) = DATE(?)", arguments: [yesterday.formatted(TaskTraceDatabase.sqlDateStyle)])
            }

            #expect(status == GoalTodoStatus.failed.rawValue)
        }
    }

    @Test("daily goal duration rollup sums assigned activity duration")
    func dailyGoalDurationRollupSumsAssignedActivityDuration() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: nil, dailyTargetSeconds: nil))
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
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .done, statusTs: now, repeating: false, targetDate: targetDate, dailyTargetSeconds: 1_800))

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: targetDate.addingTimeInterval(-86_400),
                visibleEnd: now.addingTimeInterval(86_400),
                selectedDay: now
            )

            #expect(snapshot.dailyTodoOutcomeCounts.contains { Calendar(identifier: .gregorian).isDate($0.day, inSameDayAs: now) })
        }
    }

    @Test("rewound snapshot hides todo deleted after selected day")
    func rewoundSnapshotHidesTodoDeletedAfterSelectedDay() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let deleteTs = now.addingTimeInterval(3_600)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: nil, dailyTargetSeconds: nil))
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
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Future", createTs: futureDay, status: .open, statusTs: nil, repeating: false, targetDate: futureDay, dailyTargetSeconds: nil))

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: selectedDay.addingTimeInterval(-86_400),
                visibleEnd: futureDay,
                selectedDay: selectedDay
            )

            #expect(snapshot.todos.isEmpty)
        }
    }

    @Test("snapshot hides dated todos from earlier days")
    func snapshotHidesDatedTodosFromEarlierDays() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let selectedDay = Date(timeIntervalSince1970: 1_765_000_000)
            let pastDay = selectedDay.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: pastDay, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Past", createTs: pastDay, status: .open, statusTs: nil, repeating: false, targetDate: pastDay, dailyTargetSeconds: nil))

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: pastDay,
                visibleEnd: selectedDay,
                selectedDay: selectedDay
            )

            #expect(snapshot.todos.isEmpty)
        }
    }

    @Test("snapshot decodes todo target date as selected local day")
    func snapshotDecodesTodoTargetDateAsSelectedLocalDay() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let selectedDay = Date(timeIntervalSince1970: 1_765_000_000)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: selectedDay, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Today", createTs: selectedDay, status: .open, statusTs: nil, repeating: false, targetDate: selectedDay, dailyTargetSeconds: nil))

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: selectedDay.addingTimeInterval(-86_400),
                visibleEnd: selectedDay,
                selectedDay: selectedDay
            )

            #expect(snapshot.todos.first?.targetDate?.formatted(date: .abbreviated, time: .omitted) == selectedDay.formatted(date: .abbreviated, time: .omitted))
        }
    }

    @Test("rewound snapshot carries forward undated open todo")
    func rewoundSnapshotCarriesForwardUndatedOpenTodo() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let selectedDay = Date(timeIntervalSince1970: 1_765_000_000)
            let pastDay = selectedDay.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: pastDay, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Carry", createTs: pastDay, status: .open, statusTs: nil, repeating: false, targetDate: nil, dailyTargetSeconds: nil))

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
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Done", createTs: pastDay, status: .done, statusTs: pastDay, repeating: false, targetDate: nil, dailyTargetSeconds: nil))

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
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: targetDate, dailyTargetSeconds: 1_800))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let status = try database.read { db in
                try String.fetchOne(db, sql: "SELECT status FROM goal_todos WHERE id = 2")
            }

            #expect(status == GoalTodoStatus.failed.rawValue)
        }
    }

    @Test("daily maintenance records target failure on the target date")
    func dailyMaintenanceRecordsTargetFailureOnTheTargetDate() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let targetDate = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: targetDate, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: targetDate, status: .open, statusTs: nil, repeating: false, targetDate: targetDate, dailyTargetSeconds: 1_800))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: targetDate,
                visibleEnd: now,
                selectedDay: targetDate
            )

            #expect(snapshot.dailyTodoOutcomeCounts.contains { Calendar(identifier: .gregorian).isDate($0.day, inSameDayAs: targetDate) && $0.failedCount == 1 })
        }
    }

    @Test("daily maintenance does not record target failure on the job date")
    func dailyMaintenanceDoesNotRecordTargetFailureOnTheJobDate() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let targetDate = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: targetDate, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: targetDate, status: .open, statusTs: nil, repeating: false, targetDate: targetDate, dailyTargetSeconds: 1_800))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: targetDate,
                visibleEnd: now,
                selectedDay: now
            )

            #expect(snapshot.dailyTodoOutcomeCounts.contains { Calendar(identifier: .gregorian).isDate($0.day, inSameDayAs: now) && $0.failedCount > 0 } == false)
        }
    }

    @Test("daily maintenance recomputes completed historical target below quota")
    func dailyMaintenanceRecomputesCompletedHistoricalTargetBelowQuota() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let targetDate = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: targetDate, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: targetDate, status: .done, statusTs: targetDate, repeating: false, targetDate: targetDate, dailyTargetSeconds: 1_800))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let status = try database.read { db in
                try String.fetchOne(db, sql: "SELECT status FROM goal_todos WHERE id = 2")
            }

            #expect(status == GoalTodoStatus.failed.rawValue)
        }
    }

    @Test("daily maintenance does not fail non target todo")
    func dailyMaintenanceDoesNotFailNonTargetTodo() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let targetDate = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Todo", createTs: targetDate, status: .open, statusTs: nil, repeating: false, targetDate: targetDate, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let status = try database.read { db in
                try String.fetchOne(db, sql: "SELECT status FROM goal_todos WHERE id = 2")
            }

            #expect(status == GoalTodoStatus.open.rawValue)
        }
    }

    @Test("public todo status mutation cannot set failed")
    func publicTodoStatusMutationCannotSetFailed() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: now, dailyTargetSeconds: nil))

            await #expect(throws: GoalTodoStatusValidationError.self) {
                try await goalsDatabaseActor.setTodoStatus(id: 2, status: .failed, statusTs: now)
            }
        }
    }

    @Test("public todo save cannot create failed")
    func publicTodoSaveCannotCreateFailed() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)

            await #expect(throws: GoalTodoStatusValidationError.self) {
                try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Todo", createTs: now, status: .failed, statusTs: now, repeating: false, targetDate: now, dailyTargetSeconds: nil))
            }
        }
    }

    @Test("daily maintenance completes historical todo that meets quota")
    func dailyMaintenanceCompletesHistoricalTodoThatMeetsQuota() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let targetDate = now.addingTimeInterval(-86_400)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: targetDate, dailyTargetSeconds: 1_800))
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

    @Test("daily maintenance completes maximum target below quota")
    func dailyMaintenanceCompletesMaximumTargetBelowQuota() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let targetDate = now.addingTimeInterval(-86_400)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Avoid", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: targetDate, dailyTargetSeconds: 1_800, dailyTargetMode: .maximum))
            try await activityDatabaseActor.saveActivityRecord(ActivityInput(id: 3, startTime: targetDate, application: "com.example.App", keystrokes: nil, microphone: nil, summary: "Start", tagID: nil, jsonProperties: nil, overviewID: nil))
            try await activityDatabaseActor.saveActivityRecord(ActivityInput(id: 4, startTime: targetDate.addingTimeInterval(1_200), application: "com.example.App", keystrokes: nil, microphone: nil, summary: "Next", tagID: nil, jsonProperties: nil, overviewID: nil))
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

    @Test("daily maintenance completes maximum target at quota")
    func dailyMaintenanceCompletesMaximumTargetAtQuota() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let targetDate = now.addingTimeInterval(-86_400)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Avoid", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: targetDate, dailyTargetSeconds: 1_800, dailyTargetMode: .maximum))
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

    @Test("daily maintenance fails maximum target over quota")
    func dailyMaintenanceFailsMaximumTargetOverQuota() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let targetDate = now.addingTimeInterval(-86_400)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Avoid", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: targetDate, dailyTargetSeconds: 1_800, dailyTargetMode: .maximum))
            try await activityDatabaseActor.saveActivityRecord(ActivityInput(id: 3, startTime: targetDate, application: "com.example.App", keystrokes: nil, microphone: nil, summary: "Start", tagID: nil, jsonProperties: nil, overviewID: nil))
            try await activityDatabaseActor.saveActivityRecord(ActivityInput(id: 4, startTime: targetDate.addingTimeInterval(1_801), application: "com.example.App", keystrokes: nil, microphone: nil, summary: "Next", tagID: nil, jsonProperties: nil, overviewID: nil))
            try database.write { db in
                try db.execute(sql: "UPDATE activities SET goal_todo_id = 2 WHERE id = 3")
            }
            try await goalsDatabaseActor.runDailyMaintenance(now: now)

            let status = try database.read { db in
                try String.fetchOne(db, sql: "SELECT status FROM goal_todos WHERE id = 2")
            }

            #expect(status == GoalTodoStatus.failed.rawValue)
        }
    }

    @Test("manual activity assignment is not overwritten by automatic assignment")
    func manualActivityAssignmentIsNotOverwrittenByAutomaticAssignment() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Manual", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: nil, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 3, goalID: 1, name: "Auto", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: nil, dailyTargetSeconds: nil))
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
            _ = try await goalsDatabaseActor.assignActivityAutomatically(
                activityID: 4,
                todoID: 3,
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

    @Test("automatic assignment assigns an open todo")
    func automaticAssignmentAssignsAnOpenTodo() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Auto", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: nil, dailyTargetSeconds: nil))
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
            _ = try await goalsDatabaseActor.assignActivityAutomatically(
                activityID: 3,
                todoID: 2,
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

    @Test("automatic assignment assigns a standalone todo")
    func automaticAssignmentAssignsAStandaloneTodo() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Standalone", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: nil, dailyTargetSeconds: nil))
            try await activityDatabaseActor.saveActivityRecord(
                ActivityInput(
                    id: 3,
                    startTime: now,
                    application: "com.example.App",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "Working on standalone todo",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: nil
                )
            )
            _ = try await goalsDatabaseActor.assignActivityAutomatically(
                activityID: 3,
                todoID: 2,
                now: now
            )

            let assignedTodoID = try database.read { db in
                try Int64.fetchOne(db, sql: "SELECT goal_todo_id FROM activities WHERE id = 3")
            }

            #expect(assignedTodoID == 2)
        }
    }

    @Test("automatic assignment excludes todo completed before activity start")
    func automaticAssignmentExcludesTodoCompletedBeforeActivityStart() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityStart = now.addingTimeInterval(1_200)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Done", createTs: now, status: .done, statusTs: now.addingTimeInterval(600), repeating: false, targetDate: activityStart, dailyTargetSeconds: nil))
            try await activityDatabaseActor.saveActivityRecord(
                ActivityInput(
                    id: 3,
                    startTime: activityStart,
                    application: "com.example.App",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "Working after completion",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: nil
                )
            )
            let didAssign = try await goalsDatabaseActor.assignActivityAutomatically(
                activityID: 3,
                todoID: 2,
                now: activityStart
            )

            #expect(didAssign == false)
        }
    }

    @Test("activity day candidates exclude future todos")
    func activityDayCandidatesExcludeFutureTodos() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let selectedDay = Date(timeIntervalSince1970: 1_765_000_000)
            let futureDay = selectedDay.addingTimeInterval(86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: selectedDay, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Future", createTs: futureDay, status: .open, statusTs: nil, repeating: false, targetDate: futureDay, dailyTargetSeconds: nil))

            let candidates = try await goalsDatabaseActor.loadOpenTodoCandidates(forActivityStart: selectedDay)

            #expect(candidates.isEmpty)
        }
    }

    @Test("activity day candidates exclude past dated todos")
    func activityDayCandidatesExcludePastDatedTodos() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let activityDay = Date(timeIntervalSince1970: 1_765_000_000)
            let pastDay = activityDay.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: pastDay, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Past", createTs: pastDay, status: .open, statusTs: nil, repeating: false, targetDate: pastDay, dailyTargetSeconds: nil))

            let candidates = try await goalsDatabaseActor.loadOpenTodoCandidates(forActivityStart: activityDay)

            #expect(candidates.isEmpty)
        }
    }

    @Test("activity day candidates include standalone todos")
    func activityDayCandidatesIncludeStandaloneTodos() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let activityDay = Date(timeIntervalSince1970: 1_765_000_000)
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: nil, name: "Standalone", createTs: activityDay, status: .open, statusTs: nil, repeating: false, targetDate: activityDay, dailyTargetSeconds: nil))

            let candidates = try await goalsDatabaseActor.loadOpenTodoCandidates(forActivityStart: activityDay)

            #expect(candidates.first?.goal == nil)
        }
    }

    @Test("activity start candidates use deterministic ordering for equal timestamps")
    func activityStartCandidatesUseDeterministicOrderingForEqualTimestamps() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let activityStart = Date(timeIntervalSince1970: 1_765_000_000)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Older id", description: nil, createTs: activityStart, doneTs: nil))
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 2, name: "Newer id", description: nil, createTs: activityStart, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 11, goalID: 1, name: "B", createTs: activityStart, status: .open, statusTs: nil, repeating: false, targetDate: activityStart, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 10, goalID: 1, name: "A", createTs: activityStart, status: .open, statusTs: nil, repeating: false, targetDate: activityStart, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 21, goalID: 2, name: "D", createTs: activityStart, status: .open, statusTs: nil, repeating: false, targetDate: activityStart, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 20, goalID: 2, name: "C", createTs: activityStart, status: .open, statusTs: nil, repeating: false, targetDate: activityStart, dailyTargetSeconds: nil))
            let candidates = try await goalsDatabaseActor.loadOpenTodoCandidates(forActivityStart: activityStart)

            #expect(candidates.map(\.todo.id) == [20, 21, 10, 11])
        }
    }

    @Test("activity day candidates include todo completed after activity day")
    func activityDayCandidatesIncludeTodoCompletedAfterActivityDay() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let activityDay = Date(timeIntervalSince1970: 1_765_000_000)
            let completedDay = activityDay.addingTimeInterval(86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: activityDay, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Done later", createTs: activityDay, status: .done, statusTs: completedDay, repeating: false, targetDate: activityDay, dailyTargetSeconds: nil))

            let candidates = try await goalsDatabaseActor.loadOpenTodoCandidates(forActivityStart: activityDay)

            #expect(candidates.first?.todo.id == 2)
        }
    }

    @Test("activity start candidates include todo completed after activity start")
    func activityStartCandidatesIncludeTodoCompletedAfterActivityStart() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityStart = now.addingTimeInterval(600)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Done later", createTs: now, status: .done, statusTs: now.addingTimeInterval(1_200), repeating: false, targetDate: activityStart, dailyTargetSeconds: nil))
            let candidates = try await goalsDatabaseActor.loadOpenTodoCandidates(forActivityStart: activityStart)

            #expect(candidates.first?.todo.id == 2)
        }
    }

    @Test("activity day candidates exclude todo completed before activity day")
    func activityDayCandidatesExcludeTodoCompletedBeforeActivityDay() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let activityDay = Date(timeIntervalSince1970: 1_765_000_000)
            let completedDay = activityDay.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: completedDay, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Done", createTs: completedDay, status: .done, statusTs: completedDay, repeating: false, targetDate: completedDay, dailyTargetSeconds: nil))

            let candidates = try await goalsDatabaseActor.loadOpenTodoCandidates(forActivityStart: activityDay)

            #expect(candidates.isEmpty)
        }
    }

    @Test("activity start candidates exclude todo completed before activity start")
    func activityStartCandidatesExcludeTodoCompletedBeforeActivityStart() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityStart = now.addingTimeInterval(1_200)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Done", createTs: now, status: .done, statusTs: now.addingTimeInterval(600), repeating: false, targetDate: activityStart, dailyTargetSeconds: nil))
            let candidates = try await goalsDatabaseActor.loadOpenTodoCandidates(forActivityStart: activityStart)

            #expect(candidates.isEmpty)
        }
    }

    @Test("activity start candidates exclude failed todo before activity start")
    func activityStartCandidatesExcludeFailedTodoBeforeActivityStart() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let targetDate = now.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: targetDate, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Failed", createTs: targetDate, status: .open, statusTs: nil, repeating: false, targetDate: targetDate, dailyTargetSeconds: 1_800))
            try await goalsDatabaseActor.runDailyMaintenance(now: now)
            let candidates = try await goalsDatabaseActor.loadOpenTodoCandidates(forActivityStart: now)

            #expect(candidates.isEmpty)
        }
    }

    @Test("activity day candidates exclude deleted todos")
    func activityDayCandidatesExcludeDeletedTodos() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let activityDay = Date(timeIntervalSince1970: 1_765_000_000)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: activityDay, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Deleted", createTs: activityDay, status: .open, statusTs: nil, repeating: false, targetDate: activityDay, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.softDeleteTodo(id: 2, now: activityDay.addingTimeInterval(86_400))

            let candidates = try await goalsDatabaseActor.loadOpenTodoCandidates(forActivityStart: activityDay)

            #expect(candidates.isEmpty)
        }
    }

    @Test("activity day candidates exclude deleted goals")
    func activityDayCandidatesExcludeDeletedGoals() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let activityDay = Date(timeIntervalSince1970: 1_765_000_000)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Deleted Goal", description: nil, createTs: activityDay, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: activityDay, status: .open, statusTs: nil, repeating: false, targetDate: activityDay, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.softDeleteGoal(id: 1, now: activityDay.addingTimeInterval(86_400))

            let candidates = try await goalsDatabaseActor.loadOpenTodoCandidates(forActivityStart: activityDay)

            #expect(candidates.isEmpty)
        }
    }

    @Test("activity day candidates exclude goal completed before activity day")
    func activityDayCandidatesExcludeGoalCompletedBeforeActivityDay() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let activityDay = Date(timeIntervalSince1970: 1_765_000_000)
            let completedDay = activityDay.addingTimeInterval(-86_400)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Done Goal", description: nil, createTs: completedDay, doneTs: completedDay))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: completedDay, status: .open, statusTs: nil, repeating: false, targetDate: completedDay, dailyTargetSeconds: nil))

            let candidates = try await goalsDatabaseActor.loadOpenTodoCandidates(forActivityStart: activityDay)

            #expect(candidates.isEmpty)
        }
    }

    @Test("manual assignment completes a todo when its daily target is reached")
    func manualAssignmentCompletesATodoWhenItsDailyTargetIsReached() async throws {
        try await withGoalsDatabase { database, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Target", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: now, dailyTargetSeconds: 1_800))
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
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: nil, dailyTargetSeconds: nil))
            try await goalsDatabaseActor.softDeleteGoal(id: 1, now: now)

            let snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: now.addingTimeInterval(-86_400),
                visibleEnd: now.addingTimeInterval(86_400),
                selectedDay: now
            )

            #expect(snapshot == GoalsSnapshot(goals: [], todos: [], goalRollups: [], todoRollups: [], dailyGoalDurations: [], dailyTodoOutcomeCounts: []))
        }
    }

    @Test("rewound snapshot hides goal deleted after selected day")
    func rewoundSnapshotHidesGoalDeletedAfterSelectedDay() async throws {
        try await withGoalsDatabase { _, goalsDatabaseActor in
            let now = Date(timeIntervalSince1970: 1_765_000_000)
            try await goalsDatabaseActor.saveGoal(GoalInput(id: 1, name: "Goal", description: nil, createTs: now, doneTs: nil))
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: nil, dailyTargetSeconds: nil))
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
            try await goalsDatabaseActor.saveTodo(GoalTodoInput(id: 2, goalID: 1, name: "Todo", createTs: now, status: .open, statusTs: nil, repeating: false, targetDate: nil, dailyTargetSeconds: nil))
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

@MainActor
private func withLegacyRepeatTemplateDatabase(
    _ block: (TaskTraceDatabase) async throws -> Void
) async throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

    do {
        let queue = try DatabaseQueue(
            path: databaseURL.path,
            configuration: TaskTraceDatabaseBootstrap.makeConfiguration(
                label: "TaskTraceLegacyRepeatTemplateTests",
                extensionSet: .migrator
            )
        )
        try await queue.write { db in
            try db.execute(sql: "ALTER TABLE goal_todos ADD COLUMN repeat_template_id INTEGER")
            try db.execute(
                sql: """
                    INSERT INTO goal_todos (
                        id,
                        goal_id,
                        name,
                        create_ts,
                        done_ts,
                        status,
                        status_ts,
                        repeating,
                        repeat_template_id,
                        target_date,
                        daily_target_seconds,
                        daily_target_mode,
                        embedding,
                        delete_ts
                    )
                    VALUES
                        (1, NULL, 'Legacy template', '2026-05-11 08:00:00', NULL, 'open', NULL, 1, NULL, NULL, NULL, 'minimum', NULL, NULL),
                        (2, NULL, 'Legacy template', '2026-05-12 08:00:00', NULL, 'open', NULL, 0, 1, '2026-05-12', NULL, 'minimum', NULL, NULL)
                    """
            )
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v49_remove_goal_todo_repeat_templates'")
            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (48)")
        }
    }

    try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
    let database = try TaskTraceDatabase(databaseURL: databaseURL)

    try await block(database)
}
