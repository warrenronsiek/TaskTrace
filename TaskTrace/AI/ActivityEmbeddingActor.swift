//
//  ActivityEmbeddingActor.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation
import OSLog

actor ActivityEmbeddingActor: Receiver, ActivityEmbeddingGenerating {
    private let actorSystem: ActorSystem?
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
        guard let request = envelope.message as? ActivitySummarized,
              !(request.activity.summary?.isEmpty ?? true) else {
            return
        }

        logger.log(
            "activity-embedding-actor received sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(request.activity.id, privacy: .public)"
        )
        Task {
            await self.process(request)
        }
    }

    private func process(_ request: ActivitySummarized) async {
        let vectors = await embeddingGenerator.generateVectors(
            for: [request.activity.summary ?? ""],
            promptPrefix: nil,
            source: "activity-summary-embedding"
        )
        let vector = vectors.first ?? []

        guard !vector.isEmpty else {
            logger.error(
                "activity-embedding-actor produced empty vector activityID=\(request.activity.id, privacy: .public)"
            )
            return
        }

        logger.log(
            "activity-embedding-actor broadcasting activity-summary-embedded activityID=\(request.activity.id, privacy: .public) dimensions=\(vector.count, privacy: .public)"
        )
        await actorSystem?.broadcast(
            from: nil,
            message: ActivitySummaryEmbedded(
                activityID: request.activity.id,
                vector: vector
            )
        )
    }

    func generateVectors(for texts: [String], promptPrefix: String?) async -> [[Float]] {
        await generateVectors(
            for: texts,
            promptPrefix: promptPrefix,
            source: "activity-embedding"
        )
    }

    func generateVectors(for texts: [String], promptPrefix: String?, source: String) async -> [[Float]] {
        await embeddingGenerator.generateVectors(
            for: texts,
            promptPrefix: promptPrefix,
            source: source
        )
    }
}
