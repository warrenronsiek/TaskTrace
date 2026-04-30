//
//  KnowledgeCommunityEmbeddingActor.swift
//  TaskTrace
//

import Foundation
import OSLog

actor KnowledgeCommunityEmbeddingActor: Receiver {
    typealias Request = (buildID: Int64?, communityID: Int64, summary: String)

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
        guard let event = envelope.message as? CommunitySummarized else {
            return
        }

        Task {
            await self.process((event.buildID, event.communityID, event.summary))
        }
    }

    private func process(_ request: Request) async {
        let vectors = await embeddingGenerator.generateVectors(
            for: [request.summary],
            promptPrefix: nil,
            source: "knowledge-community-embedding"
        )
        let vector = vectors.first ?? []

        guard !vector.isEmpty else {
            return
        }

        await actorSystem.broadcast(
            from: nil,
            message: CommunityEmbedded(
                buildID: request.buildID,
                communityID: request.communityID,
                vector: vector
            )
        )
    }
}
