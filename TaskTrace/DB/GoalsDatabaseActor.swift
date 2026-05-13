//
//  GoalsDatabaseActor.swift
//  TaskTrace
//
//  Created by Codex on 5/7/26.
//

import Foundation
import GRDB

actor GoalsDatabaseActor {
    private let database: TaskTraceDatabase
    private let calendar: Calendar

    init(
        database: TaskTraceDatabase,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.database = database
        self.calendar = calendar
    }

    func loadSnapshot(
        visibleStart: Date,
        visibleEnd: Date,
        selectedDay: Date
    ) async throws -> GoalsSnapshot {
        let visibleStartSQL = calendar.startOfDay(for: visibleStart).formatted(TaskTraceDatabase.sqlDateStyle)
        let visibleEndSQL = calendar.startOfDay(for: visibleEnd).formatted(TaskTraceDatabase.sqlDateStyle)
        let selectedDaySQL = calendar.startOfDay(for: selectedDay).formatted(TaskTraceDatabase.sqlDateStyle)

        return try database.read { db in
            let goals = try GoalRecord.fetchAll(
                db,
                sql: """
                    SELECT
                        id,
                        name,
                        description,
                        create_ts,
                        CASE
                            WHEN done_ts IS NOT NULL AND DATE(done_ts) > DATE(?) THEN NULL
                            ELSE done_ts
                        END AS done_ts,
                        delete_ts
                    FROM goals
                    WHERE DATE(create_ts) <= DATE(?)
                      AND (done_ts IS NULL OR DATE(done_ts) >= DATE(?))
                      AND delete_ts IS NULL
                    ORDER BY done_ts IS NOT NULL ASC, create_ts DESC, id DESC
                    """,
                arguments: [
                    selectedDaySQL,
                    selectedDaySQL,
                    selectedDaySQL
                ]
            )
            let todos = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        goal_todos.id,
                        goal_todos.goal_id,
                        goal_todos.name,
                        goal_todos.create_ts,
                        CASE
                            WHEN goal_todos.done_ts IS NOT NULL AND DATE(goal_todos.done_ts) > DATE(?) THEN NULL
                            ELSE goal_todos.done_ts
                        END AS done_ts,
                        CASE
                            WHEN goal_todos.status <> ? AND goal_todos.status_ts IS NOT NULL AND DATE(goal_todos.status_ts) > DATE(?) THEN ?
                            ELSE goal_todos.status
                        END AS status,
                        CASE
                            WHEN goal_todos.status_ts IS NOT NULL AND DATE(goal_todos.status_ts) > DATE(?) THEN NULL
                            ELSE goal_todos.status_ts
                        END AS status_ts,
                        goal_todos.repeating,
                        goal_todos.target_date,
                        goal_todos.daily_target_seconds,
                        goal_todos.daily_target_mode,
                        goal_todos.embedding,
                        goal_todos.delete_ts
                    FROM goal_todos
                    LEFT JOIN goals ON goals.id = goal_todos.goal_id
                    WHERE (
                          goal_todos.goal_id IS NULL
                          OR (
                              DATE(goals.create_ts) <= DATE(?)
                              AND (goals.done_ts IS NULL OR DATE(goals.done_ts) >= DATE(?))
                              AND goals.delete_ts IS NULL
                          )
                      )
                      AND DATE(goal_todos.create_ts) <= DATE(?)
                      AND (goal_todos.target_date IS NULL OR DATE(goal_todos.target_date) = DATE(?))
                      AND (goal_todos.status = ? OR goal_todos.status_ts IS NULL OR DATE(goal_todos.status_ts) >= DATE(?))
                      AND goal_todos.delete_ts IS NULL
                    ORDER BY goal_todos.target_date IS NULL ASC, goal_todos.target_date DESC, goal_todos.create_ts DESC, goal_todos.id DESC
                    """,
                arguments: [
                    selectedDaySQL,
                    GoalTodoStatus.open.rawValue,
                    selectedDaySQL,
                    GoalTodoStatus.open.rawValue,
                    selectedDaySQL,
                    selectedDaySQL,
                    selectedDaySQL,
                    selectedDaySQL,
                    selectedDaySQL,
                    GoalTodoStatus.open.rawValue,
                    selectedDaySQL
                ]
            ).map { row in
                let doneTs: Date? = if let value = row["done_ts"] as String? {
                    try TaskTraceDatabase.date(fromSQLTimestamp: value)
                } else {
                    nil
                }
                let statusTs: Date? = if let value = row["status_ts"] as String? {
                    try TaskTraceDatabase.date(fromSQLTimestamp: value)
                } else {
                    nil
                }
                let targetDate: Date? = if let value = row["target_date"] as String? {
                    try TaskTraceDatabase.date(fromSQLDate: value)
                } else {
                    nil
                }
                let deleteTs: Date? = if let value = row["delete_ts"] as String? {
                    try TaskTraceDatabase.date(fromSQLTimestamp: value)
                } else {
                    nil
                }

                return GoalTodoRecord(
                    id: row["id"],
                    goalID: row["goal_id"] as Int64?,
                    name: row["name"],
                    createTs: try TaskTraceDatabase.date(fromSQLTimestamp: row["create_ts"]),
                    doneTs: doneTs,
                    status: GoalTodoStatus(rawValue: row["status"] as String) ?? .open,
                    statusTs: statusTs,
                    repeating: row["repeating"],
                    targetDate: targetDate,
                    dailyTargetSeconds: row["daily_target_seconds"],
                    dailyTargetMode: GoalTodoTargetMode(rawValue: row["daily_target_mode"] as String? ?? "") ?? .minimum,
                    embedding: row["embedding"],
                    deleteTs: deleteTs
                )
            }
            let goalRollups = try GoalRollup.fetchAll(
                db,
                sql: """
                    WITH leads AS (
                        SELECT
                            activities.start_time,
                            activities.application,
                            activities.goal_todo_id,
                            CAST((
                                strftime('%s', LEAD(activities.start_time)
                                    OVER (PARTITION BY DATE(activities.start_time) ORDER BY activities.start_time)
                                ) - strftime('%s', activities.start_time)
                            ) AS INTEGER) AS duration
                        FROM activities
                        WHERE DATE(activities.start_time) = DATE(?)
                    )
                    SELECT
                        goal_todos.goal_id AS goal_id,
                        COALESCE(SUM(leads.duration), 0) AS duration
                    FROM leads
                    JOIN goal_todos ON goal_todos.id = leads.goal_todo_id
                    JOIN goals ON goals.id = goal_todos.goal_id
                    WHERE leads.application <> 'PAUSED'
                      AND leads.application <> 'SLEEP'
                      AND DATE(goal_todos.create_ts) <= DATE(?)
                      AND DATE(goals.create_ts) <= DATE(?)
                      AND goal_todos.delete_ts IS NULL
                      AND goals.delete_ts IS NULL
                      AND (goals.done_ts IS NULL OR DATE(goals.done_ts) >= DATE(?))
                    GROUP BY goal_todos.goal_id
                    ORDER BY goal_todos.goal_id ASC
                    """,
                arguments: [
                    selectedDaySQL,
                    selectedDaySQL,
                    selectedDaySQL,
                    selectedDaySQL
                ]
            )
            let todoRollups = try GoalTodoRollup.fetchAll(
                db,
                sql: """
                    WITH leads AS (
                        SELECT
                            start_time,
                            application,
                            goal_todo_id,
                            CAST((
                                strftime('%s', LEAD(start_time)
                                    OVER (PARTITION BY DATE(start_time) ORDER BY start_time)
                                ) - strftime('%s', start_time)
                            ) AS INTEGER) AS duration
                        FROM activities
                        WHERE DATE(start_time) = DATE(?)
                    )
                    SELECT
                        leads.goal_todo_id AS todo_id,
                        COALESCE(SUM(duration), 0) AS duration
                    FROM leads
                    JOIN goal_todos ON goal_todos.id = leads.goal_todo_id
                    LEFT JOIN goals ON goals.id = goal_todos.goal_id
                    WHERE leads.goal_todo_id IS NOT NULL
                      AND application <> 'PAUSED'
                      AND application <> 'SLEEP'
                      AND DATE(goal_todos.create_ts) <= DATE(?)
                      AND goal_todos.delete_ts IS NULL
                      AND (
                          goal_todos.goal_id IS NULL
                          OR (
                              DATE(goals.create_ts) <= DATE(?)
                              AND goals.delete_ts IS NULL
                              AND (goals.done_ts IS NULL OR DATE(goals.done_ts) >= DATE(?))
                          )
                      )
                    GROUP BY leads.goal_todo_id
                    ORDER BY leads.goal_todo_id ASC
                    """,
                arguments: [
                    selectedDaySQL,
                    selectedDaySQL,
                    selectedDaySQL,
                    selectedDaySQL
                ]
            )
            let dailyGoalDurations = try DailyGoalDuration.fetchAll(
                db,
                sql: """
                    WITH leads AS (
                        SELECT
                            DATE(start_time) AS day,
                            application,
                            goal_todo_id,
                            CAST((
                                strftime('%s', LEAD(start_time)
                                    OVER (PARTITION BY DATE(start_time) ORDER BY start_time)
                                ) - strftime('%s', start_time)
                            ) AS INTEGER) AS duration
                        FROM activities
                        WHERE DATE(start_time) BETWEEN DATE(?) AND DATE(?)
                    )
                    SELECT
                        goal_todos.goal_id AS goal_id,
                        leads.day || ' 12:00:00' AS day,
                        COALESCE(SUM(leads.duration), 0) AS duration
                    FROM leads
                    JOIN goal_todos ON goal_todos.id = leads.goal_todo_id
                    JOIN goals ON goals.id = goal_todos.goal_id
                    WHERE leads.goal_todo_id IS NOT NULL
                      AND leads.application <> 'PAUSED'
                      AND leads.application <> 'SLEEP'
                      AND DATE(goal_todos.create_ts) <= DATE(leads.day)
                      AND DATE(goals.create_ts) <= DATE(leads.day)
                      AND goal_todos.delete_ts IS NULL
                      AND goals.delete_ts IS NULL
                      AND (goals.done_ts IS NULL OR DATE(goals.done_ts) >= DATE(leads.day))
                    GROUP BY goal_todos.goal_id, leads.day
                    ORDER BY leads.day ASC, goal_todos.goal_id ASC
                    """,
                arguments: [
                    visibleStartSQL,
                    visibleEndSQL
                ]
            )
            let dailyTodoOutcomeCounts = try DailyTodoOutcomeCount.fetchAll(
                db,
                sql: """
                    WITH outcomes AS (
                        SELECT
                            goal_todos.id,
                            goal_todos.goal_id,
                            goal_todos.status,
                            DATE(COALESCE(goal_todos.done_ts, goal_todos.status_ts)) AS day
                        FROM goal_todos
                        LEFT JOIN goals ON goals.id = goal_todos.goal_id
                        WHERE goal_todos.status IN (?, ?)
                          AND goal_todos.delete_ts IS NULL
                          AND (
                              goal_todos.goal_id IS NULL
                              OR goals.delete_ts IS NULL
                          )
                    )
                    SELECT
                        goal_id,
                        day || ' 12:00:00' AS day,
                        SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) AS completed_count,
                        SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) AS failed_count
                    FROM outcomes
                    WHERE day IS NOT NULL
                      AND DATE(day) BETWEEN DATE(?) AND DATE(?)
                    GROUP BY goal_id, day
                    ORDER BY day ASC, goal_id ASC
                    """,
                arguments: [
                    GoalTodoStatus.done.rawValue,
                    GoalTodoStatus.failed.rawValue,
                    GoalTodoStatus.done.rawValue,
                    GoalTodoStatus.failed.rawValue,
                    visibleStartSQL,
                    visibleEndSQL
                ]
            )

            return GoalsSnapshot(
                goals: goals,
                todos: todos,
                goalRollups: goalRollups,
                todoRollups: todoRollups,
                dailyGoalDurations: dailyGoalDurations,
                dailyTodoOutcomeCounts: dailyTodoOutcomeCounts
            )
        }
    }

    func saveGoal(_ goal: GoalInput) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO goals (
                        id,
                        name,
                        description,
                        create_ts,
                        done_ts
                    )
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        description = excluded.description,
                        create_ts = COALESCE(goals.create_ts, excluded.create_ts),
                        done_ts = excluded.done_ts,
                        delete_ts = goals.delete_ts
                    """,
                arguments: [
                    goal.id,
                    goal.name,
                    goal.description,
                    (goal.createTs ?? Date()).formatted(TaskTraceDatabase.sqlTimestampStyle),
                    goal.doneTs?.formatted(TaskTraceDatabase.sqlTimestampStyle)
                ]
            )
        }
    }

    func saveTodo(_ todo: GoalTodoInput) async throws {
        try database.write { db in
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
                        target_date,
                        daily_target_seconds,
                        daily_target_mode
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        goal_id = excluded.goal_id,
                        name = excluded.name,
                        create_ts = COALESCE(goal_todos.create_ts, excluded.create_ts),
                        done_ts = excluded.done_ts,
                        status = excluded.status,
                        status_ts = excluded.status_ts,
                        repeating = excluded.repeating,
                        target_date = excluded.target_date,
                        daily_target_seconds = excluded.daily_target_seconds,
                        daily_target_mode = excluded.daily_target_mode,
                        delete_ts = goal_todos.delete_ts
                    """,
                arguments: [
                    todo.id,
                    todo.goalID,
                    todo.name,
                    (todo.createTs ?? Date()).formatted(TaskTraceDatabase.sqlTimestampStyle),
                    todo.status == .done ? (todo.statusTs ?? Date()).formatted(TaskTraceDatabase.sqlTimestampStyle) : nil,
                    todo.status.rawValue,
                    todo.statusTs?.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    todo.repeating,
                    todo.targetDate?.formatted(TaskTraceDatabase.sqlDateStyle),
                    todo.dailyTargetSeconds,
                    todo.dailyTargetMode.rawValue
                ]
            )
        }
    }

    func markGoal(
        id: Int64,
        done: Bool,
        now: Date
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE goals
                    SET done_ts = ?
                    WHERE id = ?
                      AND delete_ts IS NULL
                    """,
                arguments: [
                    done ? now.formatted(TaskTraceDatabase.sqlTimestampStyle) : nil,
                    id
                ]
            )
        }
    }

    func softDeleteGoal(
        id: Int64,
        now: Date
    ) async throws {
        try database.write { db in
            let deleteTimestamp = now.formatted(TaskTraceDatabase.sqlTimestampStyle)
            try db.execute(
                sql: """
                    UPDATE goals
                    SET delete_ts = ?
                    WHERE id = ?
                    """,
                arguments: [deleteTimestamp, id]
            )
            try db.execute(
                sql: """
                    UPDATE goal_todos
                    SET delete_ts = ?
                    WHERE goal_id = ?
                      AND delete_ts IS NULL
                    """,
                arguments: [deleteTimestamp, id]
            )
        }
    }

    func setTodoStatus(
        id: Int64,
        status: GoalTodoStatus,
        statusTs: Date
    ) async throws {
        try database.write { db in
            try Self.setTodoStatus(
                id: id,
                status: status,
                now: statusTs,
                db: db
            )
        }
    }

    func softDeleteTodo(
        id: Int64,
        now: Date
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE goal_todos
                    SET delete_ts = ?
                    WHERE id = ?
                    """,
                arguments: [
                    now.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    id
                ]
            )
        }
    }

    func assignActivity(
        activityID: Int64,
        todoID: Int64?,
        source: GoalTodoAssignmentSource,
        score: Double?,
        now: Date
    ) async throws {
        try database.write { db in
            if let todoID {
                let todoIsAssignable = try Bool.fetchOne(
                    db,
                    sql: """
                        SELECT EXISTS (
                            SELECT 1
                            FROM goal_todos
                            LEFT JOIN goals ON goals.id = goal_todos.goal_id
                            WHERE goal_todos.id = ?
                              AND goal_todos.delete_ts IS NULL
                              AND (
                                  goal_todos.goal_id IS NULL
                                  OR (
                                      goals.delete_ts IS NULL
                                      AND goals.done_ts IS NULL
                                  )
                              )
                        )
                        """,
                    arguments: [todoID]
                ) ?? false

                guard todoIsAssignable else {
                    return
                }
            }

            try db.execute(
                sql: """
                    UPDATE activities
                    SET goal_todo_id = ?,
                        goal_todo_assignment_source = ?,
                        goal_todo_assignment_score = ?
                    WHERE id = ?
                    """,
                arguments: [
                    todoID,
                    todoID == nil ? nil : source.rawValue,
                    todoID == nil ? nil : score,
                    activityID
                ]
            )

            if let todoID {
                let activityDay = try String.fetchOne(
                    db,
                    sql: "SELECT DATE(start_time) FROM activities WHERE id = ?",
                    arguments: [activityID]
                )
                try Self.completeMinimumTodoIfTargetReached(
                    id: todoID,
                    targetDaySQL: activityDay,
                    now: now,
                    db: db
                )
            }
        }
    }

    func assignActivityAutomatically(
        activityID: Int64,
        todoID: Int64,
        now: Date
    ) async throws -> Bool {
        try database.write { db in
            guard let activity = try Row.fetchOne(
                db,
                sql: """
                    SELECT goal_todo_assignment_source, start_time, DATE(start_time) AS activity_day
                    FROM activities
                    WHERE id = ?
                    """,
                arguments: [activityID]
            ) else {
                return false
            }

            let activityAssignmentSource = activity["goal_todo_assignment_source"] as String?
            guard activityAssignmentSource != GoalTodoAssignmentSource.manual.rawValue else {
                return false
            }

            let activityDay: String = activity["activity_day"]
            let activityStart: String = activity["start_time"]
            let todoIsAssignable = try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS (
                        SELECT 1
                        FROM goal_todos
                        LEFT JOIN goals ON goals.id = goal_todos.goal_id
                        WHERE goal_todos.id = ?
                          AND (
                              goal_todos.goal_id IS NULL
                              OR (
                                  goals.create_ts <= ?
                                  AND (goals.done_ts IS NULL OR goals.done_ts > ?)
                                  AND goals.delete_ts IS NULL
                              )
                          )
                          AND goal_todos.create_ts <= ?
                          AND (goal_todos.target_date IS NULL OR DATE(goal_todos.target_date) = DATE(?))
                          AND (
                              goal_todos.status = ?
                              OR COALESCE(goal_todos.status_ts, goal_todos.done_ts) > ?
                          )
                          AND goal_todos.delete_ts IS NULL
                    )
                    """,
                arguments: [
                    todoID,
                    activityStart,
                    activityStart,
                    activityStart,
                    activityDay,
                    GoalTodoStatus.open.rawValue,
                    activityStart
                ]
            ) ?? false

            guard todoIsAssignable else {
                return false
            }

            try db.execute(
                sql: """
                    UPDATE activities
                    SET goal_todo_id = ?,
                        goal_todo_assignment_source = ?,
                        goal_todo_assignment_score = ?
                    WHERE id = ?
                      AND (
                          goal_todo_assignment_source IS NULL
                          OR goal_todo_assignment_source <> ?
                      )
                    """,
                arguments: [
                    todoID,
                    GoalTodoAssignmentSource.automatic.rawValue,
                    Optional<Double>.none,
                    activityID,
                    GoalTodoAssignmentSource.manual.rawValue
                ]
            )

            let didAssign = (try Int.fetchOne(db, sql: "SELECT changes()") ?? 0) > 0

            guard didAssign else {
                return false
            }

            try Self.completeMinimumTodoIfTargetReached(
                id: todoID,
                targetDaySQL: activityDay,
                now: now,
                db: db
            )

            return true
        }
    }

    func loadOpenTodoCandidates(forActivityStart activityStart: Date) async throws -> [GoalTodoCandidate] {
        let activityDaySQL = calendar.startOfDay(for: activityStart).formatted(TaskTraceDatabase.sqlDateStyle)
        let activityStartSQL = activityStart.formatted(TaskTraceDatabase.sqlTimestampStyle)

        return try database.read { db in
            try Self.loadCandidates(
                sql: """
                    SELECT
                        goal_todos.*,
                        goals.id AS g_id,
                        goals.name AS g_name,
                        goals.description AS g_description,
                        goals.create_ts AS g_create_ts,
                        goals.done_ts AS g_done_ts,
                        goals.delete_ts AS g_delete_ts
                    FROM goal_todos
                    LEFT JOIN goals ON goals.id = goal_todos.goal_id
                    WHERE (
                          goal_todos.goal_id IS NULL
                          OR (
                              goals.create_ts <= ?
                              AND (goals.done_ts IS NULL OR goals.done_ts > ?)
                              AND goals.delete_ts IS NULL
                          )
                      )
                      AND goal_todos.create_ts <= ?
                      AND (goal_todos.target_date IS NULL OR DATE(goal_todos.target_date) = DATE(?))
                      AND goal_todos.delete_ts IS NULL
                      AND (
                          goal_todos.status = ?
                          OR COALESCE(goal_todos.status_ts, goal_todos.done_ts) > ?
                      )
                    ORDER BY goal_todos.goal_id IS NULL ASC, goals.create_ts DESC, goals.id DESC, goal_todos.create_ts DESC, goal_todos.id ASC
                    """,
                arguments: [
                    activityStartSQL,
                    activityStartSQL,
                    activityStartSQL,
                    activityDaySQL,
                    GoalTodoStatus.open.rawValue,
                    activityStartSQL
                ],
                db: db
            )
        }
    }

    func runDailyMaintenance(now: Date) async throws {
        let today = calendar.startOfDay(for: now)
        let todaySQL = today.formatted(TaskTraceDatabase.sqlDateStyle)
        let yesterdaySQL = calendar.date(byAdding: .day, value: -1, to: today)?.formatted(TaskTraceDatabase.sqlDateStyle) ?? todaySQL
        let nowSQL = now.formatted(TaskTraceDatabase.sqlTimestampStyle)

        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO goal_todos (
                        goal_id,
                        name,
                        create_ts,
                        status,
                        status_ts,
                        repeating,
                        target_date,
                        daily_target_seconds,
                        daily_target_mode,
                        embedding
                    )
                    SELECT
                        source.goal_id,
                        source.name,
                        ?,
                        ?,
                        NULL,
                        1,
                        ?,
                        source.daily_target_seconds,
                        source.daily_target_mode,
                        NULL
                    FROM goal_todos source
                    LEFT JOIN goals ON goals.id = source.goal_id
                    WHERE (
                          source.goal_id IS NULL
                          OR (
                              goals.done_ts IS NULL
                              AND goals.delete_ts IS NULL
                          )
                      )
                      AND source.delete_ts IS NULL
                      AND source.repeating = 1
                      AND source.target_date IS NOT NULL
                      AND DATE(source.target_date) = DATE(?)
                      AND NOT EXISTS (
                          SELECT 1
                          FROM goal_todos existing
                          WHERE existing.repeating = 1
                            AND DATE(existing.target_date) = DATE(?)
                            AND COALESCE(existing.goal_id, -1) = COALESCE(source.goal_id, -1)
                            AND existing.name = source.name
                            AND COALESCE(existing.daily_target_seconds, -1) = COALESCE(source.daily_target_seconds, -1)
                            AND existing.daily_target_mode = source.daily_target_mode
                      )
                    """,
                arguments: [
                    nowSQL,
                    GoalTodoStatus.open.rawValue,
                    todaySQL,
                    yesterdaySQL,
                    todaySQL
                ]
            )

            let dueRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT goal_todos.id, goal_todos.target_date
                    FROM goal_todos
                    LEFT JOIN goals ON goals.id = goal_todos.goal_id
                    WHERE status = ?
                      AND goal_todos.delete_ts IS NULL
                      AND (
                          goal_todos.goal_id IS NULL
                          OR (
                              goals.delete_ts IS NULL
                              AND goals.done_ts IS NULL
                          )
                      )
                      AND goal_todos.daily_target_seconds IS NOT NULL
                      AND goal_todos.target_date IS NOT NULL
                      AND DATE(goal_todos.target_date) < DATE(?)
                    ORDER BY goal_todos.target_date ASC, goal_todos.id ASC
                    """,
                arguments: [
                    GoalTodoStatus.open.rawValue,
                    todaySQL
                ]
            )

            try dueRows.forEach { row in
                let todoID: Int64 = row["id"]
                let targetDate: String = row["target_date"]
                try Self.resolveHistoricalTodoTarget(
                    id: todoID,
                    targetDaySQL: targetDate,
                    now: now,
                    db: db
                )
            }
        }
    }

    private nonisolated static func loadCandidates(
        sql: String,
        arguments: StatementArguments,
        db: Database
    ) throws -> [GoalTodoCandidate] {
        try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
            let todoDoneTs: Date? = if let value = row["done_ts"] as String? {
                try TaskTraceDatabase.date(fromSQLTimestamp: value)
            } else {
                nil
            }
            let todoDeleteTs: Date? = if let value = row["delete_ts"] as String? {
                try TaskTraceDatabase.date(fromSQLTimestamp: value)
            } else {
                nil
            }
            let todoStatusTs: Date? = if let value = row["status_ts"] as String? {
                try TaskTraceDatabase.date(fromSQLTimestamp: value)
            } else {
                nil
            }
            let todoTargetDate: Date? = if let value = row["target_date"] as String? {
                try TaskTraceDatabase.date(fromSQLDate: value)
            } else {
                nil
            }
            let goalID = row["g_id"] as Int64?
            let goalDoneTs: Date? = if let value = row["g_done_ts"] as String? {
                try TaskTraceDatabase.date(fromSQLTimestamp: value)
            } else {
                nil
            }
            let goalDeleteTs: Date? = if let value = row["g_delete_ts"] as String? {
                try TaskTraceDatabase.date(fromSQLTimestamp: value)
            } else {
                nil
            }
            let goal = try goalID.map { id in
                GoalRecord(
                    id: id,
                    name: row["g_name"],
                    description: row["g_description"],
                    createTs: try TaskTraceDatabase.date(fromSQLTimestamp: row["g_create_ts"]),
                    doneTs: goalDoneTs,
                    deleteTs: goalDeleteTs
                )
            }

            return GoalTodoCandidate(
                todo: GoalTodoRecord(
                    id: row["id"],
                    goalID: row["goal_id"] as Int64?,
                    name: row["name"],
                    createTs: try TaskTraceDatabase.date(fromSQLTimestamp: row["create_ts"]),
                    doneTs: todoDoneTs,
                    status: GoalTodoStatus(rawValue: row["status"] as String) ?? .open,
                    statusTs: todoStatusTs,
                    repeating: row["repeating"],
                    targetDate: todoTargetDate,
                    dailyTargetSeconds: row["daily_target_seconds"],
                    dailyTargetMode: GoalTodoTargetMode(rawValue: row["daily_target_mode"] as String? ?? "") ?? .minimum,
                    embedding: row["embedding"],
                    deleteTs: todoDeleteTs
                ),
                goal: goal
            )
        }
    }

    private nonisolated static func setTodoStatus(
        id: Int64,
        status: GoalTodoStatus,
        now: Date,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                UPDATE goal_todos
                SET status = ?,
                    status_ts = ?,
                    done_ts = ?
                WHERE id = ?
                  AND delete_ts IS NULL
                """,
            arguments: [
                status.rawValue,
                now.formatted(TaskTraceDatabase.sqlTimestampStyle),
                status == .done ? now.formatted(TaskTraceDatabase.sqlTimestampStyle) : nil,
                id
            ]
        )
    }

    private nonisolated static func completeMinimumTodoIfTargetReached(
        id: Int64,
        targetDaySQL: String?,
        now: Date,
        db: Database
    ) throws {
        let target = try Row.fetchOne(
            db,
            sql: """
                SELECT daily_target_seconds, daily_target_mode
                FROM goal_todos
                WHERE id = ?
                  AND status = ?
                  AND delete_ts IS NULL
                  AND daily_target_seconds IS NOT NULL
                """,
            arguments: [id, GoalTodoStatus.open.rawValue]
        )

        guard let target,
              let targetSeconds = target["daily_target_seconds"] as Int?,
              (GoalTodoTargetMode(rawValue: target["daily_target_mode"] as String? ?? "") ?? .minimum) == .minimum else {
            return
        }

        let duration = try todoTargetDuration(id: id, targetDaySQL: targetDaySQL, db: db)

        if duration >= targetSeconds {
            try setTodoStatus(
                id: id,
                status: .done,
                now: now,
                db: db
            )
        }
    }

    private nonisolated static func resolveHistoricalTodoTarget(
        id: Int64,
        targetDaySQL: String,
        now: Date,
        db: Database
    ) throws {
        guard let target = try Row.fetchOne(
            db,
            sql: """
                SELECT daily_target_seconds, daily_target_mode
                FROM goal_todos
                WHERE id = ?
                  AND status = ?
                  AND delete_ts IS NULL
                  AND daily_target_seconds IS NOT NULL
                """,
            arguments: [id, GoalTodoStatus.open.rawValue]
        ),
              let targetSeconds = target["daily_target_seconds"] as Int? else {
            return
        }

        let mode = GoalTodoTargetMode(rawValue: target["daily_target_mode"] as String? ?? "") ?? .minimum
        let duration = try todoTargetDuration(id: id, targetDaySQL: targetDaySQL, db: db)
        let status: GoalTodoStatus = switch mode {
        case .minimum:
            duration >= targetSeconds ? .done : .failed
        case .maximum:
            duration <= targetSeconds ? .done : .failed
        }

        try setTodoStatus(
            id: id,
            status: status,
            now: now,
            db: db
        )
    }

    private nonisolated static func todoTargetDuration(
        id: Int64,
        targetDaySQL: String?,
        db: Database
    ) throws -> Int {
        let todoTargetDate = try String.fetchOne(
            db,
            sql: "SELECT target_date FROM goal_todos WHERE id = ?",
            arguments: [id]
        )
        let resolvedTargetDaySQL = todoTargetDate ?? targetDaySQL

        guard let resolvedTargetDaySQL else {
            return 0
        }

        return try Int.fetchOne(
            db,
            sql: """
                WITH leads AS (
                    SELECT
                        start_time,
                        application,
                        goal_todo_id,
                        CAST((
                            strftime('%s', LEAD(start_time)
                                OVER (PARTITION BY DATE(start_time) ORDER BY start_time)
                            ) - strftime('%s', start_time)
                        ) AS INTEGER) AS duration
                    FROM activities
                    WHERE DATE(start_time) = DATE(?)
                )
                SELECT COALESCE(SUM(duration), 0)
                FROM leads
                WHERE goal_todo_id = ?
                  AND application <> 'PAUSED'
                  AND application <> 'SLEEP'
            """,
            arguments: [resolvedTargetDaySQL, id]
        ) ?? 0
    }
}
