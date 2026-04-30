//
//  KnowledgeCommunitiesTests.swift
//  TaskTraceTests
//
//  Created by Codex on 4/8/26.
//

import Testing
@testable import TaskTrace

struct KnowledgeCommunitiesTests {
    @Test("disconnected cliques form separate communities")
    func disconnectedCliquesFormSeparateCommunities() {
        let mapping = KnowledgeCommunityDetection.communities(
            nodeIDs: [1, 2, 3, 4, 5, 6],
            edges: [
                .init(firstNodeID: 1, secondNodeID: 2),
                .init(firstNodeID: 1, secondNodeID: 3),
                .init(firstNodeID: 2, secondNodeID: 3),
                .init(firstNodeID: 4, secondNodeID: 5),
                .init(firstNodeID: 4, secondNodeID: 6),
                .init(firstNodeID: 5, secondNodeID: 6)
            ]
        )

        #expect(mapping[1] == mapping[2])
        #expect(mapping[2] == mapping[3])
        #expect(mapping[4] == mapping[5])
        #expect(mapping[5] == mapping[6])
        #expect(mapping[1] != mapping[4])
    }

    @Test("a weak bridge between dense groups still leaves two communities")
    func weakBridgeBetweenDenseGroupsStillLeavesTwoCommunities() {
        let mapping = KnowledgeCommunityDetection.communities(
            nodeIDs: [1, 2, 3, 4, 5, 6, 7, 8],
            edges: [
                .init(firstNodeID: 1, secondNodeID: 2),
                .init(firstNodeID: 1, secondNodeID: 3),
                .init(firstNodeID: 1, secondNodeID: 4),
                .init(firstNodeID: 2, secondNodeID: 3),
                .init(firstNodeID: 2, secondNodeID: 4),
                .init(firstNodeID: 3, secondNodeID: 4),
                .init(firstNodeID: 5, secondNodeID: 6),
                .init(firstNodeID: 5, secondNodeID: 7),
                .init(firstNodeID: 5, secondNodeID: 8),
                .init(firstNodeID: 6, secondNodeID: 7),
                .init(firstNodeID: 6, secondNodeID: 8),
                .init(firstNodeID: 7, secondNodeID: 8),
                .init(firstNodeID: 4, secondNodeID: 5)
            ],
            resolution: 0.5
        )

        #expect(mapping[1] == mapping[2])
        #expect(mapping[2] == mapping[3])
        #expect(mapping[3] == mapping[4])
        #expect(mapping[5] == mapping[6])
        #expect(mapping[6] == mapping[7])
        #expect(mapping[7] == mapping[8])
        #expect(mapping[1] != mapping[5])
    }

    @Test("isolated nodes are omitted from the returned communities mapping")
    func isolatedNodesAreOmittedFromTheReturnedCommunitiesMapping() {
        let mapping = KnowledgeCommunityDetection.communities(
            nodeIDs: [10, 11, 12],
            edges: []
        )

        #expect(mapping.isEmpty)
    }

    @Test("community identifiers stabilize to the smallest node id in each community")
    func communityIdentifiersStabilizeToSmallestNodeID() {
        let mapping = KnowledgeCommunityDetection.communities(
            nodeIDs: [21, 22, 30, 31],
            edges: [
                .init(firstNodeID: 21, secondNodeID: 22),
                .init(firstNodeID: 30, secondNodeID: 31)
            ]
        )

        #expect(mapping[21] == 21)
        #expect(mapping[22] == 21)
        #expect(mapping[30] == 30)
        #expect(mapping[31] == 30)
    }

    @Test("connected activities still form a community when most nodes are isolated")
    func connectedActivitiesStillFormACommunityWhenMostNodesAreIsolated() {
        let mapping = KnowledgeCommunityDetection.communities(
            nodeIDs: Array(1...1_411).map(Int64.init),
            edges: [
                .init(firstNodeID: 1, secondNodeID: 2, weight: 0.82),
                .init(firstNodeID: 1, secondNodeID: 3, weight: 0.79),
                .init(firstNodeID: 2, secondNodeID: 3, weight: 0.81)
            ]
        )

        #expect(mapping == [1: 1, 2: 1, 3: 1])
    }
}
