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
            let todos = try GoalTodoRecord.fetchAll(
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
                        goal_todos.repeat_template_id,
                        goal_todos.target_date,
                        goal_todos.daily_target_seconds,
                        goal_todos.embedding,
                        goal_todos.delete_ts
                    FROM goal_todos
                    JOIN goals ON goals.id = goal_todos.goal_id
                    WHERE DATE(goals.create_ts) <= DATE(?)
                      AND (goals.done_ts IS NULL OR DATE(goals.done_ts) >= DATE(?))
                      AND goals.delete_ts IS NULL
                      AND DATE(goal_todos.create_ts) <= DATE(?)
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
                    GoalTodoStatus.open.rawValue,
                    selectedDaySQL
                ]
            )
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
                    JOIN goals ON goals.id = goal_todos.goal_id
                    WHERE leads.goal_todo_id IS NOT NULL
                      AND application <> 'PAUSED'
                      AND application <> 'SLEEP'
                      AND DATE(goal_todos.create_ts) <= DATE(?)
                      AND DATE(goals.create_ts) <= DATE(?)
                      AND goal_todos.delete_ts IS NULL
                      AND goals.delete_ts IS NULL
                      AND (goals.done_ts IS NULL OR DATE(goals.done_ts) >= DATE(?))
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
            let dailyCompletedTodoCounts = try DailyCompletedTodoCount.fetchAll(
                db,
                sql: """
                    WITH completions AS (
                        SELECT
                            goal_todos.id,
                            goal_todos.goal_id,
                            DATE(COALESCE(goal_todos.done_ts, goal_todos.status_ts)) AS day
                        FROM goal_todos
                        JOIN goals ON goals.id = goal_todos.goal_id
                        WHERE goal_todos.status = ?
                          AND goal_todos.delete_ts IS NULL
                          AND goals.delete_ts IS NULL
                    )
                    SELECT
                        goal_id,
                        day || ' 12:00:00' AS day,
                        COUNT(*) AS completed_count
                    FROM completions
                    WHERE day IS NOT NULL
                      AND DATE(day) BETWEEN DATE(?) AND DATE(?)
                    GROUP BY goal_id, day
                    ORDER BY day ASC, goal_id ASC
                    """,
                arguments: [
                    GoalTodoStatus.done.rawValue,
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
                dailyCompletedTodoCounts: dailyCompletedTodoCounts
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
                        repeat_template_id,
                        target_date,
                        daily_target_seconds
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
                        repeat_template_id = excluded.repeat_template_id,
                        target_date = excluded.target_date,
                        daily_target_seconds = excluded.daily_target_seconds,
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
                    todo.repeatTemplateID,
                    todo.targetDate?.formatted(TaskTraceDatabase.sqlDateStyle),
                    todo.dailyTargetSeconds
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
                            JOIN goals ON goals.id = goal_todos.goal_id
                            WHERE goal_todos.id = ?
                              AND goal_todos.delete_ts IS NULL
                              AND goals.delete_ts IS NULL
                              AND goals.done_ts IS NULL
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
                try Self.completeTodoIfTargetReached(
                    id: todoID,
                    targetDaySQL: activityDay,
                    now: now,
                    db: db
                )
            }
        }
    }

    func assignBestOpenTodo(
        activityID: Int64,
        vector: [Float],
        minimumSimilarity: Double,
        minimumMargin: Double,
        now: Date
    ) async throws -> GoalTodoAssigned? {
        try database.vectorAwareWrite { db in
            let activityAssignmentSource = try String.fetchOne(
                db,
                sql: "SELECT goal_todo_assignment_source FROM activities WHERE id = ?",
                arguments: [activityID]
            )

            guard activityAssignmentSource != GoalTodoAssignmentSource.manual.rawValue else {
                return nil
            }

            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        goal_todos.id AS todo_id,
                        MAX(0.0, 1.0 - vector_distance(goal_todos.embedding, vector_as_f32(?), 'cosine')) AS score
                    FROM goal_todos
                    JOIN goals ON goals.id = goal_todos.goal_id
                    WHERE goals.done_ts IS NULL
                      AND goals.delete_ts IS NULL
                      AND goal_todos.delete_ts IS NULL
                      AND goal_todos.status = ?
                      AND goal_todos.embedding IS NOT NULL
                    ORDER BY score DESC, goal_todos.id ASC
                    LIMIT 2
                    """,
                arguments: [
                    try Self.vectorJSONString(vector),
                    GoalTodoStatus.open.rawValue
                ]
            )

            guard let best = rows.first,
                  let bestTodoID = best["todo_id"] as Int64?,
                  let bestScore = best["score"] as Double?,
                  bestScore >= minimumSimilarity else {
                return nil
            }

            let nextScore = rows.dropFirst().first.flatMap { $0["score"] as Double? } ?? 0

            guard bestScore - nextScore >= minimumMargin else {
                return nil
            }

            try db.execute(
                sql: """
                    UPDATE activities
                    SET goal_todo_id = ?,
                        goal_todo_assignment_source = ?,
                        goal_todo_assignment_score = ?
                    WHERE id = ?
                      AND goal_todo_id IS NULL
                    """,
                arguments: [
                    bestTodoID,
                    GoalTodoAssignmentSource.automatic.rawValue,
                    bestScore,
                    activityID
                ]
            )

            let didAssign = (try Int.fetchOne(db, sql: "SELECT changes()") ?? 0) > 0

            guard didAssign else {
                return nil
            }

            let activityDay = try String.fetchOne(
                db,
                sql: "SELECT DATE(start_time) FROM activities WHERE id = ?",
                arguments: [activityID]
            )
            try Self.completeTodoIfTargetReached(
                id: bestTodoID,
                targetDaySQL: activityDay,
                now: now,
                db: db
            )

            return GoalTodoAssigned(
                activityID: activityID,
                todoID: bestTodoID,
                score: bestScore
            )
        }
    }

    func loadOpenTodoCandidates() async throws -> [GoalTodoCandidate] {
        try database.read { db in
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
                    JOIN goals ON goals.id = goal_todos.goal_id
                    WHERE goals.done_ts IS NULL
                      AND goals.delete_ts IS NULL
                      AND goal_todos.delete_ts IS NULL
                      AND goal_todos.status = ?
                    ORDER BY goals.create_ts DESC, goal_todos.create_ts DESC
                    """,
                arguments: [GoalTodoStatus.open.rawValue],
                db: db
            )
        }
    }

    func loadTodoCandidate(id: Int64) async throws -> GoalTodoCandidate? {
        try database.read { db in
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
                    JOIN goals ON goals.id = goal_todos.goal_id
                    WHERE goal_todos.id = ?
                      AND goal_todos.delete_ts IS NULL
                      AND goals.delete_ts IS NULL
                    """,
                arguments: [id],
                db: db
            ).first
        }
    }

    func loadTodoCandidates(goalID: Int64) async throws -> [GoalTodoCandidate] {
        try database.read { db in
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
                    JOIN goals ON goals.id = goal_todos.goal_id
                    WHERE goals.id = ?
                      AND goals.delete_ts IS NULL
                      AND goal_todos.delete_ts IS NULL
                      AND goal_todos.status = ?
                    """,
                arguments: [goalID, GoalTodoStatus.open.rawValue],
                db: db
            )
        }
    }

    func saveTodoEmbedding(
        todoID: Int64,
        vector: [Float]
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE goal_todos
                    SET embedding = vector_as_f32(?)
                    WHERE id = ?
                      AND delete_ts IS NULL
                    """,
                arguments: [
                    try Self.vectorJSONString(vector),
                    todoID
                ]
            )
        }
    }

    func runDailyMaintenance(now: Date) async throws {
        let todaySQL = calendar.startOfDay(for: now).formatted(TaskTraceDatabase.sqlDateStyle)
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
                        repeat_template_id,
                        target_date,
                        daily_target_seconds,
                        embedding
                    )
                    SELECT
                        templates.goal_id,
                        templates.name,
                        ?,
                        ?,
                        NULL,
                        0,
                        templates.id,
                        ?,
                        templates.daily_target_seconds,
                        templates.embedding
                    FROM goal_todos templates
                    JOIN goals ON goals.id = templates.goal_id
                    WHERE goals.done_ts IS NULL
                      AND goals.delete_ts IS NULL
                      AND templates.delete_ts IS NULL
                      AND templates.repeating = 1
                      AND templates.status = ?
                      AND NOT EXISTS (
                          SELECT 1
                          FROM goal_todos existing
                          WHERE existing.repeat_template_id = templates.id
                            AND DATE(existing.target_date) = DATE(?)
                      )
                    """,
                arguments: [
                    nowSQL,
                    GoalTodoStatus.open.rawValue,
                    todaySQL,
                    GoalTodoStatus.open.rawValue,
                    todaySQL
                ]
            )

            let dueRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT goal_todos.id, goal_todos.target_date
                    FROM goal_todos
                    JOIN goals ON goals.id = goal_todos.goal_id
                    WHERE status = ?
                      AND goal_todos.delete_ts IS NULL
                      AND goals.delete_ts IS NULL
                      AND goals.done_ts IS NULL
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
                try Self.completeTodoIfTargetReached(
                    id: todoID,
                    targetDaySQL: targetDate,
                    now: now,
                    db: db
                )

                let status = try String.fetchOne(
                    db,
                    sql: "SELECT status FROM goal_todos WHERE id = ?",
                    arguments: [todoID]
                )

                if status == GoalTodoStatus.open.rawValue {
                    try Self.setTodoStatus(
                        id: todoID,
                        status: .failed,
                        now: now,
                        db: db
                    )
                }
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

            return GoalTodoCandidate(
                todo: GoalTodoRecord(
                    id: row["id"],
                    goalID: row["goal_id"],
                    name: row["name"],
                    createTs: try TaskTraceDatabase.date(fromSQLTimestamp: row["create_ts"]),
                    doneTs: todoDoneTs,
                    status: GoalTodoStatus(rawValue: row["status"] as String) ?? .open,
                    statusTs: todoStatusTs,
                    repeating: row["repeating"],
                    repeatTemplateID: row["repeat_template_id"],
                    targetDate: todoTargetDate,
                    dailyTargetSeconds: row["daily_target_seconds"],
                    embedding: row["embedding"],
                    deleteTs: todoDeleteTs
                ),
                goal: GoalRecord(
                    id: row["g_id"],
                    name: row["g_name"],
                    description: row["g_description"],
                    createTs: try TaskTraceDatabase.date(fromSQLTimestamp: row["g_create_ts"]),
                    doneTs: goalDoneTs,
                    deleteTs: goalDeleteTs
                )
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

    private nonisolated static func completeTodoIfTargetReached(
        id: Int64,
        targetDaySQL: String?,
        now: Date,
        db: Database
    ) throws {
        let targetSeconds = try Int.fetchOne(
            db,
            sql: """
                SELECT daily_target_seconds
                FROM goal_todos
                WHERE id = ?
                  AND status = ?
                  AND delete_ts IS NULL
                  AND daily_target_seconds IS NOT NULL
                """,
            arguments: [id, GoalTodoStatus.open.rawValue]
        )

        guard let targetSeconds else {
            return
        }

        let todoTargetDate = try String.fetchOne(
            db,
            sql: "SELECT target_date FROM goal_todos WHERE id = ?",
            arguments: [id]
        )
        let resolvedTargetDaySQL = todoTargetDate ?? targetDaySQL

        guard let resolvedTargetDaySQL else {
            return
        }

        let duration = try Int.fetchOne(
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

        if duration >= targetSeconds {
            try setTodoStatus(
                id: id,
                status: .done,
                now: now,
                db: db
            )
        }
    }

    private nonisolated static func vectorJSONString(_ vector: [Float]) throws -> String {
        String(
            decoding: try JSONEncoder().encode(vector),
            as: UTF8.self
        )
    }
}
