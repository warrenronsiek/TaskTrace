//
//  KnowledgeNodeEmbeddingActor.swift
//  TaskTrace
//
//  Created by Codex on 4/7/26.
//

import Foundation
import OSLog

actor KnowledgeNodeEmbeddingActor: Receiver {
    typealias Request = (buildID: Int64?, nodeID: Int64, sourceLog: String, description: String)

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
        let request: Request? = switch envelope.message {
        case let event as KnowledgeNodeCreated:
            event.node.description.flatMap { !$0.isEmpty ? (event.buildID, event.node.id, event.source.logDescription, $0) : nil }
        case let event as UpdateKnowledgeNode:
            event.node.description.flatMap { !$0.isEmpty ? (event.buildID, event.node.id, event.source.logDescription, $0) : nil }
        default:
            nil
        }

        guard let request else {
            return
        }

        logger.log(
            "knowledge-node-embedding-actor received sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) nodeID=\(request.nodeID, privacy: .public) \(request.sourceLog, privacy: .public)"
        )
        Task {
            await self.process(request)
        }
    }

    private func process(_ request: Request) async {
        let vectors = await embeddingGenerator.generateVectors(
            for: [request.description],
            promptPrefix: nil,
            source: "knowledge-node-embedding"
        )
        let vector = vectors.first ?? []

        guard !vector.isEmpty else {
            logger.error(
                "knowledge-node-embedding-actor produced empty vector nodeID=\(request.nodeID, privacy: .public)"
            )
            return
        }

        logger.log(
            "knowledge-node-embedding-actor broadcasting knowledge-node-embedded nodeID=\(request.nodeID, privacy: .public) dimensions=\(vector.count, privacy: .public)"
        )
        await actorSystem.broadcast(
            from: nil,
            message: KnowledgeNodeEmbedded(
                buildID: request.buildID,
                nodeID: request.nodeID,
                vector: vector
            )
        )
    }
}
