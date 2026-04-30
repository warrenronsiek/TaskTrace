//
//  JobMessages.swift
//  TaskTrace
//
//  Created by Codex on 4/15/26.
//

import Foundation

nonisolated struct JobRunRequested: Sendable {
    let jobName: TaskTraceJobName
    let startedAt: Date
    let leaseUntil: Date
}

nonisolated struct JobRunSucceeded: Sendable {
    let jobName: TaskTraceJobName
    let finishedAt: Date
}

nonisolated struct JobRunDeferred: Sendable {
    let jobName: TaskTraceJobName
    let finishedAt: Date
}

nonisolated struct JobRunFailed: Sendable {
    let jobName: TaskTraceJobName
    let finishedAt: Date
    let errorMessage: String?
}
