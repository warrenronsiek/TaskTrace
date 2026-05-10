//
//  GoalMessages.swift
//  TaskTrace
//
//  Created by Codex on 5/7/26.
//

import Foundation

struct GoalUpsertRequested: Sendable {
    let mutationID: UUID
    let goal: GoalInput
}

struct GoalDeleteRequested: Sendable {
    let mutationID: UUID
    let goalID: Int64
}

struct GoalDoneSetRequested: Sendable {
    let mutationID: UUID
    let goalID: Int64
    let done: Bool
}

struct GoalTodoUpsertRequested: Sendable {
    let mutationID: UUID
    let todo: GoalTodoInput
}

struct GoalTodoDeleteRequested: Sendable {
    let mutationID: UUID
    let todoID: Int64
}

struct GoalTodoStatusSetRequested: Sendable {
    let mutationID: UUID
    let todoID: Int64
    let status: GoalTodoStatus
    let statusTs: Date
}

struct GoalMutationPersisted: Sendable {
    let mutationID: UUID
}

struct GoalMutationFailed: Sendable {
    let mutationID: UUID
    let errorMessage: String
}

struct GoalTodoAssigned: Sendable {
    let activityID: Int64
    let todoID: Int64
    let score: Double?
}

struct GoalTodoAssignmentDecided: Sendable {
    let activityID: Int64
    let todoID: Int64?
}

struct ActivityGoalTodoSet: Sendable {
    let mutationID: UUID
    let activityID: Int64
    let todoID: Int64?
}

struct ActivityGoalTodoPersistenceSucceeded: Sendable {
    let mutationID: UUID
    let activityID: Int64
    let todoID: Int64?
}

struct ActivityGoalTodoPersistenceFailed: Sendable {
    let mutationID: UUID
    let activityID: Int64
    let errorMessage: String
}

struct GoalsReloadRequested: Sendable {}
