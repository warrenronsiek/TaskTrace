//
//  CoalesceKnowledgeEdgeActor.swift
//  TaskTrace
//
//  Created by Codex on 4/9/26.
//

import Foundation
import MLXLMCommon
import OSLog

actor CoalesceKnowledgeEdgeActor: Receiver {
    nonisolated static let maxOutputTokens = 80

    nonisolated static let instructions =
        """
        You merge two markdown descriptions for the same knowledge graph edge.
        Return markdown only.
        Use exactly this structure:

        Description: one short factual description

        Preserve concrete facts from both descriptions when they are compatible.
        Prefer a single concise description over a list.
        Do not mention that descriptions were merged.
        Do not invent new facts.
        """

    private let actorSystem: ActorSystem
    private var pendingRequests: [UUID: CoalesceKnowledgeEdge] = [:]
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as CoalesceKnowledgeEdge:
            logger.log(
                "coalesce-knowledge-edge-actor received sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) edgeID=\(event.existingEdge.id, privacy: .public) \(event.source.logDescription, privacy: .public)"
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

    private func process(_ request: CoalesceKnowledgeEdge) async {
        do {
            let modelRequest = try AIRecursivePromptReducer.makeRequest(
                source: "knowledge-edge-coalesce",
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
                "coalesce-knowledge-edge-actor failed edgeID=\(request.existingEdge.id, privacy: .public) \(request.source.logDescription, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func handleCompleted(_ event: ModelTextCompleted) async {
        guard let request = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        let response = AITextUtilities.strippingThinkingBlocks(from: event.response)
        let mergedDescription = Self.parseDescription(response) ?? request.incomingEdge.description
        let updatedEdge = KnowledgeEdgeInput(
            id: request.existingEdge.id,
            firstNodeID: request.existingEdge.firstNodeID,
            secondNodeID: request.existingEdge.secondNodeID,
            relationshipType: request.incomingEdge.relationshipType ?? request.existingEdge.relationshipType,
            description: mergedDescription,
            sourceChunkID: request.incomingEdge.sourceChunkID ?? request.existingEdge.sourceChunkID,
            createDate: request.existingEdge.createDate
        )

        guard updatedEdge.relationshipType != request.existingEdge.relationshipType
                || updatedEdge.description != request.existingEdge.description
                || updatedEdge.sourceChunkID != request.existingEdge.sourceChunkID else {
            return
        }

        logger.log(
            "coalesce-knowledge-edge-actor broadcasting update-knowledge-edge edgeID=\(updatedEdge.id, privacy: .public) \(request.source.logDescription, privacy: .public)"
        )
        await actorSystem.broadcast(
            from: nil,
            message: UpdateKnowledgeEdge(
                source: request.source,
                edge: updatedEdge
            )
        )
    }

    private func handleFailed(_ event: ModelTextFailed) async {
        guard let request = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        logger.error(
            "coalesce-knowledge-edge-actor failed edgeID=\(request.existingEdge.id, privacy: .public) \(request.source.logDescription, privacy: .public) error=\(event.message, privacy: .public)"
        )
    }

    nonisolated static func prompt(request: CoalesceKnowledgeEdge) -> String {
        """
        RELATIONSHIP_TYPE
        <<<
        \(request.existingEdge.relationshipType ?? "unknown")
        >>>

        EXISTING_DESCRIPTION
        <<<
        \(request.existingEdge.description)
        >>>

        NEW_DESCRIPTION
        <<<
        \(request.incomingEdge.description)
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
