//
//  GoalTodoEmbeddingActor.swift
//  TaskTrace
//
//  Created by Codex on 5/7/26.
//

import Foundation
import OSLog

actor GoalTodoEmbeddingActor: Receiver {
    private let actorSystem: ActorSystem
    private let embeddingGenerator: any ActivityEmbeddingGenerating
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init(
        actorSystem: ActorSystem,
        embeddingGenerator: (any ActivityEmbeddingGenerating)? = nil
    ) {
        self.actorSystem = actorSystem
        self.embeddingGenerator = embeddingGenerator ?? AISchedulerClient.shared
    }

    func receive(_ envelope: Envelope) async {
        guard let request = envelope.message as? GoalTodoEmbeddingRequested,
              !request.embeddingText.isEmpty else {
            return
        }

        logger.log(
            "goal-todo-embedding-actor received sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) todoID=\(request.todoID, privacy: .public)"
        )
        Task {
            await self.process(request)
        }
    }

    private func process(_ request: GoalTodoEmbeddingRequested) async {
        let vectors = await embeddingGenerator.generateVectors(
            for: [request.embeddingText],
            promptPrefix: nil,
            source: "goal-todo-embedding"
        )
        let vector = vectors.first ?? []

        guard !vector.isEmpty else {
            logger.error(
                "goal-todo-embedding-actor produced empty vector todoID=\(request.todoID, privacy: .public)"
            )
            return
        }

        logger.log(
            "goal-todo-embedding-actor broadcasting goal-todo-embedded todoID=\(request.todoID, privacy: .public) dimensions=\(vector.count, privacy: .public)"
        )
        await actorSystem.broadcast(
            from: nil,
            message: GoalTodoEmbedded(
                todoID: request.todoID,
                vector: vector
            )
        )
    }
}
