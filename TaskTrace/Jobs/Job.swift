//
//  Job.swift
//  TaskTrace
//
//  Created by Codex on 4/15/26.
//

import Foundation
import GRDB

nonisolated enum TaskTraceJobName: String, CaseIterable, Codable, Sendable {
    case activityUMAP = "ActivityUMAP"
    case activityTagOntologyRefresh = "ActivityTagOntologyRefresh"
    case goalTodoDailyMaintenance = "GoalTodoDailyMaintenance"

    var definition: JobDefinition {
        switch self {
        case .activityUMAP:
            JobDefinition(
                name: self,
                schedule: .daily(
                    JobDailyPolicy(
                        hour: 0,
                        minute: 0
                    )
                ),
                enabled: true
            )
        case .activityTagOntologyRefresh:
            JobDefinition(
                name: self,
                schedule: .daily(
                    JobDailyPolicy(
                        hour: 0,
                        minute: 10
                    )
                ),
                enabled: true
            )
        case .goalTodoDailyMaintenance:
            JobDefinition(
                name: self,
                schedule: .daily(
                    JobDailyPolicy(
                        hour: 0,
                        minute: 20
                    )
                ),
                enabled: true
            )
        }
    }
}

nonisolated enum JobSchedule: Equatable, Sendable {
    case interval(seconds: Int)
    case daily(JobDailyPolicy)
}

nonisolated struct JobDailyPolicy: Codable, Equatable, Sendable {
    let hour: Int
    let minute: Int
    let timeZoneIdentifier: String

    init(
        hour: Int,
        minute: Int,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.hour = hour
        self.minute = minute
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

nonisolated struct JobDefinition: Equatable, Sendable {
    let name: TaskTraceJobName
    let schedule: JobSchedule
    let enabled: Bool
}

nonisolated struct JobInput: Equatable, Sendable {
    let name: TaskTraceJobName
    let schedule: JobSchedule
    let lastSuccessAt: Date?
    let lastStartedAt: Date?
    let leaseUntil: Date?
    let enabled: Bool

    init(
        name: TaskTraceJobName,
        schedule: JobSchedule,
        lastSuccessAt: Date? = nil,
        lastStartedAt: Date? = nil,
        leaseUntil: Date? = nil,
        enabled: Bool
    ) {
        self.name = name
        self.schedule = schedule
        self.lastSuccessAt = lastSuccessAt
        self.lastStartedAt = lastStartedAt
        self.leaseUntil = leaseUntil
        self.enabled = enabled
    }
}

extension JobInput {
    nonisolated init(definition: JobDefinition) {
        self.init(
            name: definition.name,
            schedule: definition.schedule,
            enabled: definition.enabled
        )
    }
}

nonisolated struct JobRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "jobs"

    let name: String
    let scheduleType: String
    let intervalSeconds: Int?
    let dailyPolicyJSON: String?
    let lastSuccessAt: Date?
    let lastStartedAt: Date?
    let leaseUntil: Date?
    let enabled: Bool

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case scheduleType = "schedule_type"
        case intervalSeconds = "interval_seconds"
        case dailyPolicyJSON = "daily_policy_json"
        case lastSuccessAt = "last_success_at"
        case lastStartedAt = "last_started_at"
        case leaseUntil = "lease_until"
        case enabled
    }

    init(
        name: String,
        scheduleType: String,
        intervalSeconds: Int?,
        dailyPolicyJSON: String?,
        lastSuccessAt: Date?,
        lastStartedAt: Date?,
        leaseUntil: Date?,
        enabled: Bool
    ) {
        self.name = name
        self.scheduleType = scheduleType
        self.intervalSeconds = intervalSeconds
        self.dailyPolicyJSON = dailyPolicyJSON
        self.lastSuccessAt = lastSuccessAt
        self.lastStartedAt = lastStartedAt
        self.leaseUntil = leaseUntil
        self.enabled = enabled
    }

    init(row: Row) {
        let decodeTimestamp = { (column: String) -> Date? in
            guard let value = row[column] as String? else {
                return nil
            }

            return try? TaskTraceDatabase.date(fromSQLTimestamp: value)
        }

        self.name = row["name"]
        self.scheduleType = row["schedule_type"]
        self.intervalSeconds = row["interval_seconds"]
        self.dailyPolicyJSON = row["daily_policy_json"]
        self.lastSuccessAt = decodeTimestamp("last_success_at")
        self.lastStartedAt = decodeTimestamp("last_started_at")
        self.leaseUntil = decodeTimestamp("lease_until")
        self.enabled = row["enabled"]
    }
}

nonisolated enum JobScheduleStorageType: String, Codable, Sendable {
    case interval
    case daily
}

nonisolated enum JobScheduleStorageError: Error {
    case invalidScheduleType(String)
    case missingIntervalSeconds(String)
    case missingDailyPolicy(String)
    case invalidDailyPolicy(String)
}

extension JobRecord {
    func decodedSchedule() throws -> JobSchedule {
        switch JobScheduleStorageType(rawValue: scheduleType) {
        case .interval:
            guard let intervalSeconds else {
                throw JobScheduleStorageError.missingIntervalSeconds(name)
            }

            return .interval(seconds: intervalSeconds)
        case .daily:
            guard let dailyPolicyJSON else {
                throw JobScheduleStorageError.missingDailyPolicy(name)
            }

            guard let dailyPolicyData = dailyPolicyJSON.data(using: .utf8) else {
                throw JobScheduleStorageError.invalidDailyPolicy(name)
            }

            return .daily(try JSONDecoder().decode(JobDailyPolicy.self, from: dailyPolicyData))
        case nil:
            throw JobScheduleStorageError.invalidScheduleType(scheduleType)
        }
    }
}
