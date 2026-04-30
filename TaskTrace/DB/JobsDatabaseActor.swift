//
//  JobsDatabaseActor.swift
//  TaskTrace
//
//  Created by Codex on 4/15/26.
//

import Foundation
import GRDB
import OSLog

actor JobsDatabaseActor {
    private let database: TaskTraceDatabase
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "jobs-db")

    init(database: TaskTraceDatabase) {
        self.database = database

        do {
            try database.write { db in
                try TaskTraceJobName.allCases
                    .map(\.definition)
                    .map(JobInput.init(definition:))
                    .forEach {
                        try saveJob(
                            $0,
                            db: db,
                            preserveEnabled: true
                        )
                    }
            }
        } catch {
            logger.fault(
                "jobs-database-actor failed operation=seed-known-jobs error=\(String(describing: error), privacy: .public)"
            )
            preconditionFailure("Could not seed jobs: \(error)")
        }
    }

    func reconcileJobDefinitions(_ definitions: [JobDefinition]) async throws {
        try database.write { db in
            for definition in definitions {
                try saveJob(
                    JobInput(definition: definition),
                    db: db,
                    preserveEnabled: true
                )
            }
        }
    }

    func saveJob(_ job: JobInput) async throws {
        try database.write { db in
            try saveJob(job, db: db, preserveEnabled: false)
        }
    }

    func loadJobs() async throws -> [JobRecord] {
        try database.read { db in
            try JobRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM jobs
                    ORDER BY name ASC
                    """
            )
        }
    }

    func loadJob(named name: TaskTraceJobName) async throws -> JobRecord? {
        try database.read { db in
            try JobRecord.fetchOne(
                db,
                sql: """
                    SELECT *
                    FROM jobs
                    WHERE name = ?
                    """,
                arguments: [name.rawValue]
            )
        }
    }

    func claimDueJobs(
        now: Date,
        leaseDuration: TimeInterval
    ) async throws -> [JobRecord] {
        try database.write { db in
            let nowSQL = now.formatted(TaskTraceDatabase.sqlTimestampStyle)
            let leaseUntil = now.addingTimeInterval(leaseDuration)
            let leaseUntilSQL = leaseUntil.formatted(TaskTraceDatabase.sqlTimestampStyle)
            let candidates = try JobRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM jobs
                    WHERE enabled = 1
                      AND (lease_until IS NULL OR lease_until <= ?)
                    ORDER BY name ASC
                    """,
                arguments: [nowSQL]
            )

            var claimed: [JobRecord] = []

            for job in candidates {
                guard try isDue(job, now: now) else {
                    continue
                }

                try db.execute(
                    sql: """
                        UPDATE jobs
                        SET last_started_at = ?,
                            lease_until = ?
                        WHERE name = ?
                          AND enabled = 1
                          AND (lease_until IS NULL OR lease_until <= ?)
                        """,
                    arguments: [nowSQL, leaseUntilSQL, job.name, nowSQL]
                )

                let updatedRowCount = try Int.fetchOne(db, sql: "SELECT changes()") ?? 0

                guard updatedRowCount > 0 else {
                    continue
                }

                claimed.append(
                    JobRecord(
                        name: job.name,
                        scheduleType: job.scheduleType,
                        intervalSeconds: job.intervalSeconds,
                        dailyPolicyJSON: job.dailyPolicyJSON,
                        lastSuccessAt: job.lastSuccessAt,
                        lastStartedAt: now,
                        leaseUntil: leaseUntil,
                        enabled: job.enabled
                    )
                )
            }

            return claimed
        }
    }

    func markJobSucceeded(
        name: TaskTraceJobName,
        finishedAt: Date
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE jobs
                    SET last_success_at = ?,
                        lease_until = NULL
                    WHERE name = ?
                    """,
                arguments: [
                    finishedAt.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    name.rawValue
                ]
            )
        }
    }

    func markJobFailed(name: TaskTraceJobName) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE jobs
                    SET lease_until = NULL
                    WHERE name = ?
                    """,
                arguments: [name.rawValue]
            )
        }
    }

    func markJobDeferred(name: TaskTraceJobName) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE jobs
                    SET lease_until = NULL
                    WHERE name = ?
                    """,
                arguments: [name.rawValue]
            )
        }
    }

    nonisolated private func saveJob(
        _ job: JobInput,
        db: Database,
        preserveEnabled: Bool
    ) throws {
        let scheduleType: String
        let intervalSeconds: Int?
        let dailyPolicyJSON: String?

        switch job.schedule {
        case let .interval(seconds):
            scheduleType = JobScheduleStorageType.interval.rawValue
            intervalSeconds = seconds
            dailyPolicyJSON = nil
        case let .daily(policy):
            scheduleType = JobScheduleStorageType.daily.rawValue
            intervalSeconds = nil
            dailyPolicyJSON = String(
                decoding: try JSONEncoder().encode(policy),
                as: UTF8.self
            )
        }

        let upsertSQL = preserveEnabled
            ? """
                INSERT INTO jobs (
                    name,
                    schedule_type,
                    interval_seconds,
                    daily_policy_json,
                    last_success_at,
                    last_started_at,
                    lease_until,
                    enabled
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(name) DO UPDATE SET
                    schedule_type = excluded.schedule_type,
                    interval_seconds = excluded.interval_seconds,
                    daily_policy_json = excluded.daily_policy_json
                """
            : """
                INSERT INTO jobs (
                    name,
                    schedule_type,
                    interval_seconds,
                    daily_policy_json,
                    last_success_at,
                    last_started_at,
                    lease_until,
                    enabled
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(name) DO UPDATE SET
                    schedule_type = excluded.schedule_type,
                    interval_seconds = excluded.interval_seconds,
                    daily_policy_json = excluded.daily_policy_json,
                    last_success_at = excluded.last_success_at,
                    last_started_at = excluded.last_started_at,
                    lease_until = excluded.lease_until,
                    enabled = excluded.enabled
                """

        try db.execute(
            sql: upsertSQL,
            arguments: [
                job.name.rawValue,
                scheduleType,
                intervalSeconds,
                dailyPolicyJSON,
                job.lastSuccessAt?.formatted(TaskTraceDatabase.sqlTimestampStyle),
                job.lastStartedAt?.formatted(TaskTraceDatabase.sqlTimestampStyle),
                job.leaseUntil?.formatted(TaskTraceDatabase.sqlTimestampStyle),
                job.enabled
            ]
        )
    }

    private func isDue(
        _ job: JobRecord,
        now: Date
    ) throws -> Bool {
        switch try job.decodedSchedule() {
        case let .interval(seconds):
            guard seconds > 0 else {
                return false
            }

            return (job.lastSuccessAt ?? .distantPast).addingTimeInterval(TimeInterval(seconds)) <= now
        case let .daily(policy):
            let timeZone = TimeZone(identifier: policy.timeZoneIdentifier) ?? .current
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let currentDay = calendar.dateComponents([.year, .month, .day], from: now)
            let scheduledToday = calendar.date(
                from: DateComponents(
                    timeZone: timeZone,
                    year: currentDay.year,
                    month: currentDay.month,
                    day: currentDay.day,
                    hour: policy.hour,
                    minute: policy.minute
                )
            )
            let latestScheduledRun = scheduledToday.map {
                $0 <= now ? $0 : (calendar.date(byAdding: .day, value: -1, to: $0) ?? $0)
            }

            return (job.lastSuccessAt ?? .distantPast) < (latestScheduledRun ?? .distantFuture)
        }
    }
}
