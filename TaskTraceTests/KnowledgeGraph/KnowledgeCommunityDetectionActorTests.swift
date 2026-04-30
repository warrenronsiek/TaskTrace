//
//  KnowledgeCommunityDetectionActorTests.swift
//  TaskTraceTests
//
//  Created by Codex on 4/8/26.
//

import Foundation
import Testing
@testable import TaskTrace

struct KnowledgeCommunityDetectionActorTests {
    actor GeneratedCommunitiesCollector: Receiver {
        private var events: [[Int64: Int64]] = []
        private var continuations: [UUID: AsyncStream<[Int64: Int64]>.Continuation] = [:]

        func receive(_ envelope: Envelope) async {
            guard let event = envelope.message as? CommunitiesGenerated else {
                return
            }

            events.append(event.communityByNodeID)
            continuations.values.forEach {
                $0.yield(event.communityByNodeID)
            }
        }

        func updates() -> AsyncStream<[Int64: Int64]> {
            let id = UUID()

            return AsyncStream { continuation in
                continuations[id] = continuation
                continuation.onTermination = { _ in
                    Task {
                        await self.removeContinuation(id)
                    }
                }
            }
        }

        func snapshot() -> [[Int64: Int64]] {
            events
        }

        private func removeContinuation(_ id: UUID) {
            continuations.removeValue(forKey: id)
        }
    }

    actor Storage {
        private var nodes: [KnowledgeNodeRecord] = []
        private var edges: [KnowledgeEdgeRecord] = []

        func setGraph(nodes: [KnowledgeNodeRecord], edges: [KnowledgeEdgeRecord] = []) {
            self.nodes = nodes
            self.edges = edges
        }

        func graph() -> ([KnowledgeNodeRecord], [KnowledgeEdgeRecord]) {
            (nodes, edges)
        }
    }

    @Test("community detector drops the stale queued request and keeps the newest one")
    func communityDetectorDropsTheStaleQueuedRequestAndKeepsTheNewestOne() async throws {
        let actorSystem = ActorSystem()
        let collector = GeneratedCommunitiesCollector()
        _ = await actorSystem.register(collector)
        let updates = await collector.updates()
        var updatesIterator = updates.makeAsyncIterator()
        let firstStarted = AsyncStream<Void>.makeStream()
        let firstMayFinish = AsyncStream<Void>.makeStream()
        let storage = Storage()
        let actor = KnowledgeCommunityDetectionActor(
            actorSystem: actorSystem,
            loadGraph: {
                await storage.graph()
            },
            computeCommunities: { nodes, _, _, _ in
                if nodes.contains(where: { $0.id == 1 }) {
                    firstStarted.continuation.yield()

                    for await _ in firstMayFinish.stream {
                        break
                    }
                }

                return Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.id) })
            }
        )

        let firstNodes = [KnowledgeNodeRecord(
            id: 1,
            name: "first",
            normalizedName: "first",
            kind: "product",
            description: nil,
            sourceChunkID: nil,
            embedding: nil,
            communityID: nil,
            createDate: .distantPast
        )]
        let secondNodes = [KnowledgeNodeRecord(
            id: 2,
            name: "second",
            normalizedName: "second",
            kind: "product",
            description: nil,
            sourceChunkID: nil,
            embedding: nil,
            communityID: nil,
            createDate: .distantPast
        )]
        let thirdNodes = [KnowledgeNodeRecord(
            id: 3,
            name: "third",
            normalizedName: "third",
            kind: "product",
            description: nil,
            sourceChunkID: nil,
            embedding: nil,
            communityID: nil,
            createDate: .distantPast
        )]

        await actor.receive(
            Envelope(
                sender: nil,
                message: KnowledgeNodeCreated(
                    source: .chunk(KnowledgeChunkInput(id: 1, anchorID: 1, ordinal: 0, hash: "first", text: "")),
                    node: KnowledgeNodeInput(
                        id: 1,
                        name: "first",
                        normalizedName: "first",
                        kind: "product",
                        description: nil,
                        sourceChunkID: nil,
                        embedding: nil,
                        createDate: .distantPast
                    )
                )
            )
        )
        await storage.setGraph(nodes: firstNodes)
        var firstStartedIterator = firstStarted.stream.makeAsyncIterator()
        _ = await firstStartedIterator.next()
        await storage.setGraph(nodes: secondNodes)
        await actor.receive(
            Envelope(
                sender: nil,
                message: KnowledgeNodeCreated(
                    source: .chunk(KnowledgeChunkInput(id: 2, anchorID: 1, ordinal: 0, hash: "second", text: "")),
                    node: KnowledgeNodeInput(
                        id: 2,
                        name: "second",
                        normalizedName: "second",
                        kind: "product",
                        description: nil,
                        sourceChunkID: nil,
                        embedding: nil,
                        createDate: .distantPast
                    )
                )
            )
        )
        await storage.setGraph(nodes: thirdNodes)
        await actor.receive(
            Envelope(
                sender: nil,
                message: KnowledgeNodeCreated(
                    source: .chunk(KnowledgeChunkInput(id: 3, anchorID: 1, ordinal: 0, hash: "third", text: "")),
                    node: KnowledgeNodeInput(
                        id: 3,
                        name: "third",
                        normalizedName: "third",
                        kind: "product",
                        description: nil,
                        sourceChunkID: nil,
                        embedding: nil,
                        createDate: .distantPast
                    )
                )
            )
        )

        firstMayFinish.continuation.yield()
        firstMayFinish.continuation.finish()
        let firstResult = try #require(await updatesIterator.next())
        let secondResult = try #require(await updatesIterator.next())

        #expect(firstResult.keys.sorted() == [1])
        #expect(secondResult.keys.sorted() == [3])
    }
}
