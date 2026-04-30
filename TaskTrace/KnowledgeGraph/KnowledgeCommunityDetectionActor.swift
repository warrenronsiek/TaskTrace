//
//  KnowledgeCommunityDetectionActor.swift
//  TaskTrace
//
//  Created by Codex on 4/8/26.
//

import Foundation
import OSLog

actor KnowledgeCommunityDetectionActor: Receiver {
    private struct Request: Sendable {
        let buildID: Int64?
        let resolution: Double
        let theta: Double
    }

    private let actorSystem: ActorSystem?
    private let loadGraph: @Sendable () async throws -> ([KnowledgeNodeRecord], [KnowledgeEdgeRecord])
    private let computeCommunities: @Sendable ([KnowledgeNodeRecord], [KnowledgeEdgeRecord], Double, Double) async -> [Int64: Int64]
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "knowledge")
    private var currentRequest = Request(buildID: nil, resolution: 0.05, theta: 0.01)
    private var queuedRequest: Request?
    private var isProcessing = false

    init(
        actorSystem: ActorSystem? = nil,
        knowledgeDatabaseActor: KnowledgeDatabaseActor,
        computeCommunities: @escaping @Sendable ([KnowledgeNodeRecord], [KnowledgeEdgeRecord], Double, Double) async -> [Int64: Int64] = { nodes, edges, resolution, theta in
            KnowledgeCommunityDetection.communities(
                nodes: nodes,
                edges: edges,
                resolution: resolution,
                theta: theta
            )
        }
    ) {
        self.actorSystem = actorSystem
        self.loadGraph = {
            (
                try await knowledgeDatabaseActor.loadKnowledgeNodes(),
                try await knowledgeDatabaseActor.loadKnowledgeEdges()
            )
        }
        self.computeCommunities = computeCommunities
    }

    init(
        actorSystem: ActorSystem? = nil,
        loadGraph: @escaping @Sendable () async throws -> ([KnowledgeNodeRecord], [KnowledgeEdgeRecord]),
        computeCommunities: @escaping @Sendable ([KnowledgeNodeRecord], [KnowledgeEdgeRecord], Double, Double) async -> [Int64: Int64] = { nodes, edges, resolution, theta in
            KnowledgeCommunityDetection.communities(
                nodes: nodes,
                edges: edges,
                resolution: resolution,
                theta: theta
            )
        }
    ) {
        self.actorSystem = actorSystem
        self.loadGraph = loadGraph
        self.computeCommunities = computeCommunities
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as KnowledgeNodeCreated:
            logger.log(
                "knowledge-community-detection-actor received knowledge-node-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) nodeID=\(event.node.id, privacy: .public)"
            )
            currentRequest = Request(
                buildID: event.buildID,
                resolution: currentRequest.resolution,
                theta: currentRequest.theta
            )
            enqueueCurrentRequest()
        case let event as KnowledgeEdgeCreated:
            logger.log(
                "knowledge-community-detection-actor received knowledge-edge-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) edgeID=\(event.edge.id, privacy: .public)"
            )
            currentRequest = Request(
                buildID: event.buildID,
                resolution: currentRequest.resolution,
                theta: currentRequest.theta
            )
            enqueueCurrentRequest()
        case let event as RebuildCommunities:
            logger.log(
                "knowledge-community-detection-actor received rebuild-communities sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) resolution=\(event.resolution, privacy: .public) theta=\(event.theta, privacy: .public)"
            )
            currentRequest = Request(
                buildID: nil,
                resolution: event.resolution,
                theta: event.theta
            )
            enqueueCurrentRequest()
        default:
            return
        }
    }

    private func enqueueCurrentRequest() {
        if isProcessing {
            queuedRequest = currentRequest
            return
        }

        isProcessing = true
        let request = currentRequest
        Task {
            await self.drainQueue(startingWith: request)
        }
    }

    private func drainQueue(startingWith initialRequest: Request) async {
        var request: Request? = initialRequest

        while let activeRequest = request {
            do {
                let (nodes, edges) = try await loadGraph()
                let communityByNodeID = await computeCommunities(
                    nodes,
                    edges,
                    activeRequest.resolution,
                    activeRequest.theta
                )

                logger.log(
                    "knowledge-community-detection-actor broadcasting communities-generated communityCount=\(Set(communityByNodeID.values).count, privacy: .public) nodeCount=\(communityByNodeID.count, privacy: .public) edgeCount=\(edges.count, privacy: .public) resolution=\(activeRequest.resolution, privacy: .public) theta=\(activeRequest.theta, privacy: .public)"
                )
                await actorSystem?.broadcast(
                    from: nil,
                    message: CommunitiesGenerated(
                        buildID: activeRequest.buildID,
                        communityByNodeID: communityByNodeID
                    )
                )
            } catch {
                logger.error(
                    "knowledge-community-detection-actor failed loading graph error=\(String(describing: error), privacy: .public)"
                )
            }

            request = queuedRequest
            queuedRequest = nil
        }

        isProcessing = false
    }
}
