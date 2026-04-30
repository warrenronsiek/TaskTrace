//
//  KnowledgeClaimEmbeddingActor.swift
//  TaskTrace
//

import Foundation
import OSLog

actor KnowledgeClaimEmbeddingActor: Receiver {
    typealias Request = (claimID: Int64, text: String)

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
        guard let event = envelope.message as? KnowledgeClaimCreated,
              !event.claim.text.isEmpty else {
            return
        }

        logger.log(
            "knowledge-claim-embedding-actor received sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) claimID=\(event.claim.id, privacy: .public) nodeID=\(event.claim.nodeID, privacy: .public)"
        )
        Task {
            await self.process((claimID: event.claim.id, text: event.claim.text))
        }
    }

    private func process(_ request: Request) async {
        let vectors = await embeddingGenerator.generateVectors(
            for: [request.text],
            promptPrefix: nil,
            source: "knowledge-claim-embedding"
        )
        let vector = vectors.first ?? []

        guard !vector.isEmpty else {
            logger.error(
                "knowledge-claim-embedding-actor produced empty vector claimID=\(request.claimID, privacy: .public)"
            )
            return
        }

        logger.log(
            "knowledge-claim-embedding-actor broadcasting knowledge-claim-embedded claimID=\(request.claimID, privacy: .public) dimensions=\(vector.count, privacy: .public)"
        )
        await actorSystem.broadcast(
            from: nil,
            message: KnowledgeClaimEmbedded(
                claimID: request.claimID,
                vector: vector
            )
        )
    }
}
