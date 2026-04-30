//
//  KnowledgeCommunities.swift
//  TaskTrace
//
//  Created by Codex on 4/8/26.
//

import Foundation

struct KnowledgeCommunityDetection {
    struct Edge: Equatable, Sendable {
        let firstNodeID: Int64
        let secondNodeID: Int64
        let weight: Double

        nonisolated init(firstNodeID: Int64, secondNodeID: Int64, weight: Double = 1) {
            self.firstNodeID = firstNodeID
            self.secondNodeID = secondNodeID
            self.weight = weight
        }
    }

    nonisolated static func communities(
        nodeIDs: [Int64],
        edges: [Edge],
        resolution: Double = 0.05,
        theta: Double = 0.01
    ) -> [Int64: Int64] {
        let normalizedNodeIDs = Array(Set(nodeIDs)).sorted()

        guard !normalizedNodeIDs.isEmpty else {
            return [:]
        }

        let normalizedEdges = edges.reduce(into: [KnowledgeEdgePair: Double]()) { partial, edge in
            guard edge.firstNodeID != edge.secondNodeID, edge.weight > 0 else {
                return
            }

            partial[KnowledgeEdgePair(firstNodeID: edge.firstNodeID, secondNodeID: edge.secondNodeID), default: 0] += edge.weight
        }
        let graph = Graph(
            nodeIDs: normalizedNodeIDs,
            nodeSizeByID: Dictionary(uniqueKeysWithValues: normalizedNodeIDs.map { ($0, 1) }),
            adjacency: normalizedEdges.reduce(into: [Int64: [Int64: Double]]()) { partial, pair in
                partial[pair.key.firstNodeID, default: [:]][pair.key.secondNodeID] = pair.value
                partial[pair.key.secondNodeID, default: [:]][pair.key.firstNodeID] = pair.value
            },
            originalNodeIDsByNodeID: Dictionary(uniqueKeysWithValues: normalizedNodeIDs.map { ($0, [$0]) })
        )
        let partition = leidenPartition(
            graph: graph,
            initialPartition: Dictionary(uniqueKeysWithValues: normalizedNodeIDs.map { ($0, $0) }),
            resolution: resolution,
            theta: theta,
            depth: 0
        )

        return Dictionary(
            uniqueKeysWithValues: Dictionary(grouping: partition.keys, by: {
                partition[$0] ?? $0
            })
            .values
            .filter { $0.count >= 2 }
            .flatMap { communityNodeIDs in
                let stableCommunityID = communityNodeIDs.min() ?? 0
                return communityNodeIDs.map { ($0, stableCommunityID) }
            }
        )
    }

    nonisolated static func communities(
        nodes: [KnowledgeNodeRecord],
        edges: [KnowledgeEdgeRecord],
        resolution: Double = 0.05,
        theta: Double = 0.01
    ) -> [Int64: Int64] {
        communities(
            nodeIDs: nodes.map(\.id),
            edges: edges.map {
                Edge(
                    firstNodeID: $0.firstNodeID,
                    secondNodeID: $0.secondNodeID
                )
            },
            resolution: resolution,
            theta: theta
        )
    }

    private struct Graph: Sendable {
        let nodeIDs: [Int64]
        let nodeSizeByID: [Int64: Int]
        let adjacency: [Int64: [Int64: Double]]
        let originalNodeIDsByNodeID: [Int64: [Int64]]
    }

    private struct CandidateCommunity: Sendable {
        let communityID: Int64
        let delta: Double
    }

    private nonisolated static let epsilon = 0.000_000_1
    private nonisolated static let maximumAggregationDepth = 64

    private nonisolated static func leidenPartition(
        graph: Graph,
        initialPartition: [Int64: Int64],
        resolution: Double,
        theta: Double,
        depth: Int
    ) -> [Int64: Int64] {
        let movedPartition = localMovePartition(
            graph: graph,
            initialPartition: initialPartition,
            resolution: resolution
        )
        let refinedPartition = refinedPartition(
            graph: graph,
            partition: movedPartition,
            resolution: resolution,
            theta: theta
        )

        guard depth < maximumAggregationDepth else {
            return flattenPartition(
                refinedPartition,
                from: graph.originalNodeIDsByNodeID
            )
        }

        let refinedCommunities = Dictionary(grouping: graph.nodeIDs, by: {
            refinedPartition[$0] ?? $0
        })
        guard refinedCommunities.count < graph.nodeIDs.count else {
            return flattenPartition(
                movedPartition,
                from: graph.originalNodeIDsByNodeID
            )
        }

        let aggregatedGraph = aggregateGraph(
            graph: graph,
            refinedPartition: refinedPartition
        )
        let aggregateInitialPartition = aggregatedGraph.nodeIDs.reduce(into: [Int64: Int64]()) { partial, nodeID in
            guard let representativeNodeID = aggregatedGraph.originalNodeIDsByNodeID[nodeID]?.first,
                  let originalCommunityID = movedPartition[representativeNodeID] else {
                partial[nodeID] = nodeID
                return
            }

            partial[nodeID] = originalCommunityID
        }
        let aggregatedPartition = leidenPartition(
            graph: aggregatedGraph,
            initialPartition: aggregateInitialPartition,
            resolution: resolution,
            theta: theta,
            depth: depth + 1
        )

        return aggregatedPartition
    }

    private nonisolated static func localMovePartition(
        graph: Graph,
        initialPartition: [Int64: Int64],
        resolution: Double
    ) -> [Int64: Int64] {
        let normalizedInitialPartition = graph.nodeIDs.reduce(into: [Int64: Int64]()) { partial, nodeID in
            partial[nodeID] = initialPartition[nodeID] ?? nodeID
        }
        let (communityByNode, _) = graph.nodeIDs.reduce(
            into: (
                communityByNode: normalizedInitialPartition,
                communityTotalSizeByID: Dictionary(grouping: graph.nodeIDs, by: {
                    normalizedInitialPartition[$0] ?? $0
                })
                .mapValues {
                    $0.reduce(0) { $0 + (graph.nodeSizeByID[$1] ?? 1) }
                }
            )
        ) { state, _ in
            var didMove = true

            while didMove {
                didMove = false

                graph.nodeIDs.forEach { nodeID in
                    let nodeSize = graph.nodeSizeByID[nodeID] ?? 1
                    let currentCommunityID = state.communityByNode[nodeID] ?? nodeID
                    state.communityTotalSizeByID[currentCommunityID, default: 0] -= nodeSize

                    let weightByCommunity = graph.adjacency[nodeID, default: [:]].reduce(into: [Int64: Double]()) { partial, pair in
                        let neighborCommunityID = state.communityByNode[pair.key] ?? pair.key
                        partial[neighborCommunityID, default: 0] += pair.value
                    }
                    let currentScore = weightByCommunity[currentCommunityID, default: 0]
                        - (resolution * Double(nodeSize * max(state.communityTotalSizeByID[currentCommunityID] ?? 0, 0)))
                    let bestCommunityID = ([currentCommunityID] + Array(weightByCommunity.keys))
                        .sorted()
                        .reduce(into: (communityID: currentCommunityID, score: currentScore)) { partial, candidateCommunityID in
                            let candidateScore = weightByCommunity[candidateCommunityID, default: 0]
                                - (resolution * Double(nodeSize * (state.communityTotalSizeByID[candidateCommunityID] ?? 0)))

                            guard candidateScore > partial.score + epsilon else {
                                return
                            }

                            partial = (candidateCommunityID, candidateScore)
                        }

                    state.communityByNode[nodeID] = bestCommunityID.communityID
                    state.communityTotalSizeByID[bestCommunityID.communityID, default: 0] += nodeSize
                    didMove = didMove || bestCommunityID.communityID != currentCommunityID
                }
            }
        }

        return communityByNode
    }

    private nonisolated static func refinedPartition(
        graph: Graph,
        partition: [Int64: Int64],
        resolution: Double,
        theta: Double
    ) -> [Int64: Int64] {
        Dictionary(grouping: graph.nodeIDs, by: {
            partition[$0] ?? $0
        })
        .values
        .reduce(into: [Int64: Int64]()) { partial, communityNodeIDs in
            let originalCommunity = Set(communityNodeIDs)
            var refinedCommunityByNode = Dictionary(uniqueKeysWithValues: communityNodeIDs.map { ($0, $0) })
            var refinedCommunityMembersByID = Dictionary(uniqueKeysWithValues: communityNodeIDs.map { ($0, Set([$0])) })
            var refinedCommunityTotalSizeByID = Dictionary(uniqueKeysWithValues: communityNodeIDs.map {
                ($0, graph.nodeSizeByID[$0] ?? 1)
            })

            communityNodeIDs.forEach { nodeID in
                guard refinedCommunityMembersByID[nodeID] == Set([nodeID]) else {
                    return
                }

                let nodeSize = graph.nodeSizeByID[nodeID] ?? 1
                let nodeConnectivityToCommunity = graph.adjacency[nodeID, default: [:]]
                    .filter { originalCommunity.contains($0.key) && $0.key != nodeID }
                    .values
                    .reduce(0, +)

                guard nodeConnectivityToCommunity + epsilon >= resolution * Double(nodeSize * max(communityNodeIDs.count - 1, 0)) else {
                    return
                }

                let candidates = {
                    let candidateCommunityIDs = Array(Set(graph.adjacency[nodeID, default: [:]]
                        .keys
                        .filter { originalCommunity.contains($0) }
                        .compactMap { refinedCommunityByNode[$0] }))
                        .sorted()
                    var candidates: [CandidateCommunity] = []

                    candidateCommunityIDs.forEach { candidateCommunityID in
                        guard candidateCommunityID != nodeID,
                              let candidateMembers = refinedCommunityMembersByID[candidateCommunityID] else {
                            return
                        }

                        let candidateSize = refinedCommunityTotalSizeByID[candidateCommunityID] ?? 0
                        let nodeConnectivityToCandidate = candidateMembers.reduce(0.0) {
                            $0 + (graph.adjacency[nodeID, default: [:]][$1] ?? 0)
                        }
                        guard nodeConnectivityToCandidate > 0 else {
                            return
                        }

                        let candidateConnectivityToCommunity = {
                            var totalWeight = 0.0

                            candidateMembers.forEach { memberNodeID in
                                let memberBoundaryWeight = graph.adjacency[memberNodeID, default: [:]]
                                    .reduce(0.0) { currentWeight, pair in
                                        let isWithinOriginalCommunity = originalCommunity.contains(pair.key)
                                        let isOutsideCandidateCommunity = !candidateMembers.contains(pair.key)

                                        guard isWithinOriginalCommunity, isOutsideCandidateCommunity else {
                                            return currentWeight
                                        }

                                        return currentWeight + pair.value
                                    }

                                totalWeight += memberBoundaryWeight
                            }

                            return totalWeight / 2
                        }()
                        let remainingCommunitySize = max(originalCommunity.count - candidateMembers.count, 0)
                        let minimumConnectivity = resolution * Double(candidateSize * remainingCommunitySize)

                        guard candidateConnectivityToCommunity + epsilon >= minimumConnectivity else {
                            return
                        }

                        let delta = nodeConnectivityToCandidate - (resolution * Double(nodeSize * candidateSize))
                        guard delta > epsilon else {
                            return
                        }

                        candidates.append(CandidateCommunity(
                            communityID: candidateCommunityID,
                            delta: delta
                        ))
                    }

                    return candidates
                }()

                guard let selectedCommunityID = selectCommunity(
                    candidates: candidates,
                    theta: theta,
                    salt: Int(truncatingIfNeeded: nodeID)
                ) else {
                    return
                }

                refinedCommunityByNode[nodeID] = selectedCommunityID
                refinedCommunityMembersByID[selectedCommunityID, default: []].insert(nodeID)
                refinedCommunityTotalSizeByID[selectedCommunityID, default: 0] += nodeSize
                refinedCommunityMembersByID[nodeID] = []
                refinedCommunityTotalSizeByID[nodeID] = 0
            }

            communityNodeIDs.forEach {
                partial[$0] = refinedCommunityByNode[$0] ?? $0
            }
        }
    }

    private nonisolated static func aggregateGraph(
        graph: Graph,
        refinedPartition: [Int64: Int64]
    ) -> Graph {
        let communities = Dictionary(grouping: graph.nodeIDs, by: {
            refinedPartition[$0] ?? $0
        })
        let aggregatedNodeIDs = communities.keys.sorted()

        return Graph(
            nodeIDs: aggregatedNodeIDs,
            nodeSizeByID: aggregatedNodeIDs.reduce(into: [Int64: Int]()) { partial, communityID in
                partial[communityID] = communities[communityID, default: []].reduce(0) {
                    $0 + (graph.nodeSizeByID[$1] ?? 1)
                }
            },
            adjacency: graph.adjacency.reduce(into: [Int64: [Int64: Double]]()) { partial, pair in
                let sourceCommunityID = refinedPartition[pair.key] ?? pair.key

                pair.value.forEach { neighborID, weight in
                    let targetCommunityID = refinedPartition[neighborID] ?? neighborID

                    guard sourceCommunityID != targetCommunityID else {
                        return
                    }

                    partial[sourceCommunityID, default: [:]][targetCommunityID, default: 0] += weight
                }
            },
            originalNodeIDsByNodeID: aggregatedNodeIDs.reduce(into: [Int64: [Int64]]()) { partial, communityID in
                partial[communityID] = communities[communityID, default: []]
                    .flatMap { graph.originalNodeIDsByNodeID[$0] ?? [$0] }
                    .sorted()
            }
        )
    }

    private nonisolated static func flattenPartition(
        _ partition: [Int64: Int64],
        from originalNodeIDsByNodeID: [Int64: [Int64]]
    ) -> [Int64: Int64] {
        Dictionary(
            uniqueKeysWithValues: Dictionary(grouping: partition.keys, by: {
                partition[$0] ?? $0
            })
            .values
            .flatMap { communityNodeIDs in
                let originalNodeIDs = communityNodeIDs
                    .flatMap { originalNodeIDsByNodeID[$0] ?? [$0] }
                    .sorted()
                let stableCommunityID = originalNodeIDs.min() ?? 0

                return originalNodeIDs.map { ($0, stableCommunityID) }
            }
        )
    }

    private nonisolated static func selectCommunity(
        candidates: [CandidateCommunity],
        theta: Double,
        salt: Int
    ) -> Int64? {
        guard !candidates.isEmpty else {
            return nil
        }

        let clampedTheta = max(theta, 0.000_001)
        let scaledWeights = candidates.map {
            exp($0.delta / clampedTheta)
        }
        let totalWeight = scaledWeights.reduce(0, +)

        guard totalWeight > 0 else {
            return candidates.max(by: { $0.delta < $1.delta })?.communityID
        }

        let threshold = deterministicUnitInterval(salt: salt) * totalWeight
        let selectedCommunityID = zip(candidates, scaledWeights)
            .reduce(into: (runningWeight: 0.0, communityID: candidates.last?.communityID)) { partial, pair in
                guard partial.communityID == candidates.last?.communityID else {
                    return
                }

                partial.runningWeight += pair.1

                if partial.runningWeight >= threshold {
                    partial.communityID = pair.0.communityID
                }
            }
            .communityID

        return selectedCommunityID
    }

    private nonisolated static func deterministicUnitInterval(salt: Int) -> Double {
        let mixed = UInt64(bitPattern: Int64(salt))
            &* 2862933555777941757
            &+ 3037000493
        return Double(mixed % 1_000_000) / 1_000_000
    }
}
