//
//  GoalTodoActor.swift
//  TaskTrace
//
//  Created by Codex on 5/7/26.
//

import Foundation
import OSLog

actor GoalTodoActor: Receiver {
    private let goalsDatabaseActor: GoalsDatabaseActor
    private let actorSystem: ActorSystem
    private let now: @Sendable () -> Date
    private let minimumSimilarity: Double
    private let minimumMargin: Double
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "goals")

    init(
        goalsDatabaseActor: GoalsDatabaseActor,
        actorSystem: ActorSystem,
        now: @escaping @Sendable () -> Date = Date.init,
        minimumSimilarity: Double = 0.76,
        minimumMargin: Double = 0.05
    ) {
        self.goalsDatabaseActor = goalsDatabaseActor
        self.actorSystem = actorSystem
        self.now = now
        self.minimumSimilarity = minimumSimilarity
        self.minimumMargin = minimumMargin
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as GoalUpsertRequested:
            Task {
                await self.saveGoal(event)
            }
        case let event as GoalDeleteRequested:
            Task {
                await self.deleteGoal(event)
            }
        case let event as GoalDoneSetRequested:
            Task {
                await self.setGoalDone(event)
            }
        case let event as GoalTodoUpsertRequested:
            Task {
                await self.saveTodo(event)
            }
        case let event as GoalTodoDeleteRequested:
            Task {
                await self.deleteTodo(event)
            }
        case let event as GoalTodoStatusSetRequested:
            Task {
                await self.setTodoStatus(event)
            }
        case let event as ActivityGoalTodoSet:
            Task {
                await self.assignActivity(event)
            }
        case let event as GoalTodoEmbedded:
            Task {
                await self.persistEmbedding(event)
            }
        case let request as GoalEmbeddingRefreshRequested:
            Task {
                await self.requestGoalEmbeddings(goalID: request.goalID)
            }
        case let event as ActivitySummaryEmbedded:
            Task {
                await self.assign(event)
            }
        case let event as JobRunRequested where event.jobName == .goalTodoDailyMaintenance:
            Task {
                await self.runDailyMaintenance(event)
            }
        default:
            return
        }
    }

    private func saveGoal(_ event: GoalUpsertRequested) async {
        do {
            try await goalsDatabaseActor.saveGoal(event.goal)
            await actorSystem.broadcast(from: nil, message: GoalMutationPersisted(mutationID: event.mutationID))
            await requestGoalEmbeddings(goalID: event.goal.id)
            await actorSystem.broadcast(from: nil, message: GoalsReloadRequested())
        } catch {
            await failGoalMutation(event.mutationID, error)
        }
    }

    private func deleteGoal(_ event: GoalDeleteRequested) async {
        do {
            try await goalsDatabaseActor.softDeleteGoal(id: event.goalID, now: now())
            await actorSystem.broadcast(from: nil, message: GoalMutationPersisted(mutationID: event.mutationID))
            await actorSystem.broadcast(from: nil, message: GoalsReloadRequested())
        } catch {
            await failGoalMutation(event.mutationID, error)
        }
    }

    private func setGoalDone(_ event: GoalDoneSetRequested) async {
        do {
            try await goalsDatabaseActor.markGoal(id: event.goalID, done: event.done, now: now())
            await actorSystem.broadcast(from: nil, message: GoalMutationPersisted(mutationID: event.mutationID))
            await actorSystem.broadcast(from: nil, message: GoalsReloadRequested())
        } catch {
            await failGoalMutation(event.mutationID, error)
        }
    }

    private func saveTodo(_ event: GoalTodoUpsertRequested) async {
        do {
            try await goalsDatabaseActor.saveTodo(event.todo)
            await actorSystem.broadcast(from: nil, message: GoalMutationPersisted(mutationID: event.mutationID))
            await requestTodoEmbedding(todoID: event.todo.id)
            await actorSystem.broadcast(from: nil, message: GoalsReloadRequested())
        } catch {
            await failGoalMutation(event.mutationID, error)
        }
    }

    private func deleteTodo(_ event: GoalTodoDeleteRequested) async {
        do {
            try await goalsDatabaseActor.softDeleteTodo(id: event.todoID, now: now())
            await actorSystem.broadcast(from: nil, message: GoalMutationPersisted(mutationID: event.mutationID))
            await actorSystem.broadcast(from: nil, message: GoalsReloadRequested())
        } catch {
            await failGoalMutation(event.mutationID, error)
        }
    }

    private func setTodoStatus(_ event: GoalTodoStatusSetRequested) async {
        do {
            try await goalsDatabaseActor.setTodoStatus(id: event.todoID, status: event.status, statusTs: event.statusTs)
            await actorSystem.broadcast(from: nil, message: GoalMutationPersisted(mutationID: event.mutationID))
            await actorSystem.broadcast(from: nil, message: GoalsReloadRequested())
        } catch {
            await failGoalMutation(event.mutationID, error)
        }
    }

    private func assignActivity(_ event: ActivityGoalTodoSet) async {
        do {
            try await goalsDatabaseActor.assignActivity(
                activityID: event.activityID,
                todoID: event.todoID,
                source: .manual,
                score: nil,
                now: now()
            )
            await actorSystem.broadcast(
                from: nil,
                message: ActivityGoalTodoPersistenceSucceeded(
                    mutationID: event.mutationID,
                    activityID: event.activityID,
                    todoID: event.todoID
                )
            )
            await actorSystem.broadcast(from: nil, message: GoalsReloadRequested())
        } catch {
            logger.error(
                "goal-todo-actor failed operation=manual-assign activityID=\(event.activityID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            await actorSystem.broadcast(
                from: nil,
                message: ActivityGoalTodoPersistenceFailed(
                    mutationID: event.mutationID,
                    activityID: event.activityID,
                    errorMessage: String(describing: error)
                )
            )
        }
    }

    private func persistEmbedding(_ event: GoalTodoEmbedded) async {
        do {
            try await goalsDatabaseActor.saveTodoEmbedding(
                todoID: event.todoID,
                vector: event.vector
            )
        } catch {
            logger.error(
                "goal-todo-actor failed operation=save-embedding todoID=\(event.todoID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func requestGoalEmbeddings(goalID: Int64) async {
        do {
            for candidate in try await goalsDatabaseActor.loadTodoCandidates(goalID: goalID) {
                await actorSystem.broadcast(
                    from: nil,
                    message: GoalTodoEmbeddingRequested(
                        todoID: candidate.todo.id,
                        embeddingText: candidate.embeddingText
                    )
                )
            }
        } catch {
            logger.error(
                "goal-todo-actor failed operation=request-goal-embeddings goalID=\(goalID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func requestTodoEmbedding(todoID: Int64) async {
        do {
            guard let candidate = try await goalsDatabaseActor.loadTodoCandidate(id: todoID) else {
                return
            }

            await actorSystem.broadcast(
                from: nil,
                message: GoalTodoEmbeddingRequested(
                    todoID: candidate.todo.id,
                    embeddingText: candidate.embeddingText
                )
            )
        } catch {
            logger.error(
                "goal-todo-actor failed operation=request-todo-embedding todoID=\(todoID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func assign(_ event: ActivitySummaryEmbedded) async {
        do {
            guard let assignment = try await goalsDatabaseActor.assignBestOpenTodo(
                activityID: event.activityID,
                vector: event.vector,
                minimumSimilarity: minimumSimilarity,
                minimumMargin: minimumMargin,
                now: now()
            ) else {
                return
            }

            await actorSystem.broadcast(from: nil, message: assignment)
            await actorSystem.broadcast(from: nil, message: GoalsReloadRequested())
        } catch {
            logger.error(
                "goal-todo-actor failed operation=auto-assign activityID=\(event.activityID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func runDailyMaintenance(_ event: JobRunRequested) async {
        do {
            try await goalsDatabaseActor.runDailyMaintenance(now: event.startedAt)
            await actorSystem.broadcast(
                from: nil,
                message: JobRunSucceeded(
                    jobName: event.jobName,
                    finishedAt: now()
                )
            )
            await actorSystem.broadcast(from: nil, message: GoalsReloadRequested())
        } catch {
            logger.error(
                "goal-todo-actor failed operation=daily-maintenance error=\(String(describing: error), privacy: .public)"
            )
            await actorSystem.broadcast(
                from: nil,
                message: JobRunFailed(
                    jobName: event.jobName,
                    finishedAt: now(),
                    errorMessage: String(describing: error)
                )
            )
        }
    }

    private func failGoalMutation(_ mutationID: UUID, _ error: any Error) async {
        logger.error(
            "goal-todo-actor failed operation=goal-mutation mutationID=\(mutationID.uuidString, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
        await actorSystem.broadcast(
            from: nil,
            message: GoalMutationFailed(
                mutationID: mutationID,
                errorMessage: String(describing: error)
            )
        )
    }
}
