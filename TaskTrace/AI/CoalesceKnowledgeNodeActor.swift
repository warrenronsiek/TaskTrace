//
//  CoalesceKnowledgeNodeActor.swift
//  TaskTrace
//
//  Created by Codex on 4/8/26.
//

import Foundation
import MLXLMCommon
import OSLog

actor CoalesceKnowledgeNodeActor: Receiver {
    nonisolated static let maxOutputTokens = 80

    nonisolated static let instructions =
        """
        You merge two markdown descriptions for the same knowledge graph node.
        Return markdown only.
        Use exactly this structure:

        Description: one short factual description

        Preserve concrete facts from both descriptions when they are compatible.
        Prefer a single concise description over a list.
        Do not mention that descriptions were merged.
        Do not invent new facts.
        """

    private let actorSystem: ActorSystem
    private var pendingRequests: [UUID: CoalesceKnowledgeNode] = [:]
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as CoalesceKnowledgeNode:
            logger.log(
                "coalesce-knowledge-node-actor received sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) nodeID=\(event.existingNode.id, privacy: .public) \(event.source.logDescription, privacy: .public)"
            )

            Task {
                await self.process(event)
            }
        case let event as ModelTextCompleted:
            await handleCompleted(event)
        case let event as ModelTextFailed:
            await handleFailed(event)
        default:
            return
        }
    }

    private func process(_ request: CoalesceKnowledgeNode) async {
        do {
            let modelRequest = try AIRecursivePromptReducer.makeRequest(
                source: "knowledge-node-coalesce",
                priority: .interactive,
                prompt: Self.prompt(request: request),
                instructions: Self.instructions,
                generateParameters: GenerateParameters(maxTokens: Self.maxOutputTokens, temperature: 0),
                additionalContext: ["enable_thinking": false]
            )
            pendingRequests[modelRequest.requestID] = request
            await actorSystem.broadcast(from: nil, message: modelRequest)
        } catch {
            logger.error(
                "coalesce-knowledge-node-actor failed nodeID=\(request.existingNode.id, privacy: .public) \(request.source.logDescription, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func handleCompleted(_ event: ModelTextCompleted) async {
        guard let request = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        let response = AITextUtilities.strippingThinkingBlocks(from: event.response)
        let mergedDescription = Self.parseDescription(response) ?? request.incomingNode.description ?? request.existingNode.description
        let updatedNode = KnowledgeNodeInput(
            id: request.existingNode.id,
            name: request.existingNode.name,
            normalizedName: request.existingNode.normalizedName,
            kind: request.existingNode.kind ?? request.incomingNode.kind,
            description: mergedDescription,
            sourceChunkID: request.incomingNode.sourceChunkID ?? request.existingNode.sourceChunkID,
            embedding: nil,
            createDate: request.existingNode.createDate
        )

        guard updatedNode.name != request.existingNode.name
                || updatedNode.kind != request.existingNode.kind
                || updatedNode.description != request.existingNode.description
                || updatedNode.sourceChunkID != request.existingNode.sourceChunkID else {
            return
        }

        logger.log(
            "coalesce-knowledge-node-actor broadcasting update-knowledge-node nodeID=\(updatedNode.id, privacy: .public) \(request.source.logDescription, privacy: .public)"
        )
        await actorSystem.broadcast(
            from: nil,
            message: UpdateKnowledgeNode(
                buildID: request.buildID,
                source: request.source,
                node: updatedNode
            )
        )
    }

    private func handleFailed(_ event: ModelTextFailed) async {
        guard let request = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        logger.error(
            "coalesce-knowledge-node-actor failed nodeID=\(request.existingNode.id, privacy: .public) \(request.source.logDescription, privacy: .public) error=\(event.message, privacy: .public)"
        )
    }

    nonisolated static func prompt(request: CoalesceKnowledgeNode) -> String {
        """
        NODE_NAME
        <<<
        \(request.existingNode.name)
        >>>

        EXISTING_DESCRIPTION
        <<<
        \(request.existingNode.description ?? "")
        >>>

        NEW_DESCRIPTION
        <<<
        \(request.incomingNode.description ?? "")
        >>>
        """
    }

    nonisolated static func parseDescription(_ response: String) -> String? {
        response
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix("Description:") })
            .map {
                let rawValue = String($0.dropFirst("Description:".count))
                return rawValue.hasPrefix(" ")
                    ? String(rawValue.dropFirst())
                    : rawValue
            }
    }
}
