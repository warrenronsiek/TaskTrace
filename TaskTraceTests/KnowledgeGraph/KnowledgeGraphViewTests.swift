//
//  KnowledgeGraphViewTests.swift
//  TaskTraceTests
//

import Foundation
import Testing
@testable import TaskTrace

struct KnowledgeGraphViewTests {
    private func makeObsidianFile() -> KnowledgeFileSystemEntry {
        KnowledgeFileSystemEntry(
            id: 1,
            directoryID: 101,
            sourceSlot: .obsidianVault,
            path: "Vault/Project.md",
            title: "Project",
            byteCount: 120,
            totalChunks: 1,
            processedChunks: 1,
            totalNodeEmbeddings: 1,
            embeddedNodeCount: 1
        )
    }

    private func makeIngestFile() -> KnowledgeFileSystemEntry {
        KnowledgeFileSystemEntry(
            id: 2,
            directoryID: 202,
            sourceSlot: .taskTraceIngest,
            path: "BrowserPlugin/Capture.md",
            title: "Capture",
            byteCount: 140,
            totalChunks: 1,
            processedChunks: 1,
            totalNodeEmbeddings: 1,
            embeddedNodeCount: 1
        )
    }

    private func makeKnowledgeNode() -> KnowledgeGraphNodeEntry {
        KnowledgeGraphNodeEntry(
            id: 10,
            name: "Structured notes",
            kind: "concept",
            description: "Summarized capture content",
            communityID: 77,
            sourcePath: nil
        )
    }

    private func makeCommunity() -> KnowledgeCommunityRecord {
        KnowledgeCommunityRecord(
            id: 77,
            name: "Capture cluster",
            summary: "Connected capture ideas",
            summaryInputHash: nil,
            embedding: nil
        )
    }

    private func makeOverview() -> KnowledgeGraphOverviewEntry {
        KnowledgeGraphOverviewEntry(
            id: 20,
            title: "Afternoon overview",
            summary: "Working through a browser capture flow"
        )
    }

    private func makeActivity() -> KnowledgeGraphActivityEntry {
        KnowledgeGraphActivityEntry(
            id: 30,
            overviewID: 20,
            application: "Google Chrome",
            summary: "Reading and capturing a page",
            startTime: Date(timeIntervalSince1970: 1_775_000_000)
        )
    }

    private func makeCommunityLinks() -> [KnowledgeCommunityLinkRecord] {
        [
            KnowledgeCommunityLinkRecord(communityID: 77, nodeID: 10)
        ]
    }

    private func makeSnapshot() -> KnowledgeGraphDirectorySnapshot {
        KnowledgeGraphDirectorySnapshot(
            knowledgeNodes: [makeKnowledgeNode()],
            communities: [makeCommunity()],
            overviews: [makeOverview()],
            activities: [makeActivity()]
        )
    }

    private func makePayload() -> TaskTraceKnowledgeGraphRenderPayload {
        KnowledgeGraphView.knowledgeGraphPayload(
            fileSystemEntries: [makeObsidianFile(), makeIngestFile()],
            graphSnapshot: makeSnapshot(),
            selectedNodeID: nil,
            graphRAGRetrieval: nil,
            communityLinks: makeCommunityLinks(),
            bridgeLinks: [],
            claims: []
        )
    }

    private func makeGraphRAGRetrieval() -> GraphRAGRetrievalResult {
        GraphRAGRetrievalResult(
            query: "capture",
            hits: [
                GraphRAGHit(
                    entityType: .community,
                    entityID: 77,
                    nodeID: nil,
                    communityID: 77,
                    title: "Capture cluster",
                    description: "Connected capture ideas",
                    hybridScore: 0.9,
                    rerankScore: 0.8
                ),
                GraphRAGHit(
                    entityType: .node,
                    entityID: 10,
                    nodeID: 10,
                    communityID: 77,
                    title: "Structured notes",
                    description: "Summarized capture content",
                    hybridScore: 0.8,
                    rerankScore: 0.7
                ),
                GraphRAGHit(
                    entityType: .claim,
                    entityID: 99,
                    nodeID: 10,
                    communityID: 77,
                    title: "Claim",
                    description: "A capture-specific claim",
                    hybridScore: 0.7,
                    rerankScore: 0.6
                )
            ],
            context: GraphRAGContext()
        )
    }

    @Test("obsidian markdown files stay on the markdown pane")
    func obsidianMarkdownFilesStayOnTheMarkdownPane() {
        let payload = makePayload()
        let node = payload.nodes.first(where: { $0.id == "knowledge-file:1" })

        #expect(node?.layer == 0)
    }

    @Test("tasktrace ingest files render on the ingest pane")
    func taskTraceIngestFilesRenderOnTheIngestPane() {
        let payload = makePayload()
        let node = payload.nodes.first(where: { $0.id == "knowledge-file:2" })

        #expect(node?.layer == 4)
    }

    @Test("overview nodes stay on the activity overview pane")
    func overviewNodesStayOnTheActivityOverviewPane() {
        let payload = makePayload()
        let node = payload.nodes.first(where: { $0.id == "knowledge-overview:20" })

        #expect(node?.layer == 1)
    }

    @Test("activity nodes stay on the activity overview pane")
    func activityNodesStayOnTheActivityOverviewPane() {
        let payload = makePayload()
        let node = payload.nodes.first(where: { $0.id == "knowledge-activity:30" })

        #expect(node?.layer == 1)
    }

    @Test("community nodes render inside the center knowledge layer")
    func communityNodesRenderInsideTheCenterKnowledgeLayer() {
        let payload = makePayload()
        let node = payload.nodes.first(where: { $0.id == "knowledge-community:77" })

        #expect(node?.layer == 2)
    }

    @Test("community node size input counts attached knowledge edges")
    func communityNodeSizeInputCountsAttachedKnowledgeEdges() {
        let payload = makePayload()
        let node = payload.nodes.first(where: { $0.id == "knowledge-community:77" })

        #expect(node?.linkCount == 1)
    }

    @Test("community relationships are part of the main graph payload")
    func communityRelationshipsArePartOfTheMainGraphPayload() {
        let payload = makePayload()
        let hasCommunityLink = payload.links.contains(where: { link in
            link.kind == "community"
                && link.sourceID == "knowledge-community:77"
                && link.targetID == "knowledge-node:10"
        })

        #expect(hasCommunityLink)
    }

    @Test("knowledge nodes connected to visible graph seeds stay in the graph payload")
    func connectedKnowledgeNodesStayInTheGraphPayload() {
        let payload = KnowledgeGraphView.knowledgeGraphPayload(
            fileSystemEntries: [makeObsidianFile(), makeIngestFile()],
            graphSnapshot: KnowledgeGraphDirectorySnapshot(
                knowledgeNodes: [
                    makeKnowledgeNode(),
                    KnowledgeGraphNodeEntry(
                        id: 11,
                        name: "Connected concept",
                        kind: "concept",
                        description: "Reachable through the visible graph",
                        communityID: nil,
                        sourcePath: nil
                    )
                ],
                knowledgeEdges: [
                    KnowledgeEdgeRecord(
                        id: 50,
                        firstNodeID: 10,
                        secondNodeID: 11,
                        relationshipType: "relates_to",
                        description: "Detached edge",
                        sourceChunkID: nil,
                        createDate: Date(timeIntervalSince1970: 1_775_000_000)
                    )
                ],
                communities: [makeCommunity()],
                overviews: [makeOverview()],
                activities: [makeActivity()]
            ),
            selectedNodeID: nil,
            graphRAGRetrieval: nil,
            communityLinks: makeCommunityLinks(),
            bridgeLinks: [],
            claims: []
        )

        #expect(payload.nodes.contains(where: { $0.id == "knowledge-node:11" }))
    }

    @Test("knowledge islands disconnected from visible graph seeds are omitted from the graph payload")
    func disconnectedKnowledgeIslandsAreOmittedFromTheGraphPayload() {
        let payload = KnowledgeGraphView.knowledgeGraphPayload(
            fileSystemEntries: [makeObsidianFile(), makeIngestFile()],
            graphSnapshot: KnowledgeGraphDirectorySnapshot(
                knowledgeNodes: [
                    makeKnowledgeNode(),
                    KnowledgeGraphNodeEntry(
                        id: 11,
                        name: "Detached concept",
                        kind: "concept",
                        description: "Not reachable from files or communities",
                        communityID: nil,
                        sourcePath: nil
                    )
                ],
                communities: [makeCommunity()],
                overviews: [makeOverview()],
                activities: [makeActivity()]
            ),
            selectedNodeID: nil,
            graphRAGRetrieval: nil,
            communityLinks: makeCommunityLinks(),
            bridgeLinks: [],
            claims: []
        )

        #expect(payload.nodes.contains(where: { $0.id == "knowledge-node:11" }) == false)
    }

    @Test("graph search reintroduces detached knowledge nodes into the graph payload")
    func graphSearchReintroducesDetachedKnowledgeNodesIntoTheGraphPayload() {
        let payload = KnowledgeGraphView.knowledgeGraphPayload(
            fileSystemEntries: [makeObsidianFile(), makeIngestFile()],
            graphSnapshot: KnowledgeGraphDirectorySnapshot(
                knowledgeNodes: [
                    makeKnowledgeNode(),
                    KnowledgeGraphNodeEntry(
                        id: 11,
                        name: "Detached concept",
                        kind: "concept",
                        description: "Only present as a graph hit",
                        communityID: nil,
                        sourcePath: nil
                    )
                ],
                communities: [makeCommunity()],
                overviews: [makeOverview()],
                activities: [makeActivity()]
            ),
            selectedNodeID: nil,
            graphRAGRetrieval: GraphRAGRetrievalResult(
                query: "detached",
                hits: [
                    GraphRAGHit(
                        entityType: .node,
                        entityID: 11,
                        nodeID: 11,
                        communityID: nil,
                        title: "Detached concept",
                        description: "Only present as a graph hit",
                        hybridScore: 0.9,
                        rerankScore: 0.9
                    )
                ],
                context: GraphRAGContext()
            ),
            communityLinks: makeCommunityLinks(),
            bridgeLinks: [],
            claims: []
        )

        #expect(payload.nodes.contains(where: { $0.id == "knowledge-node:11" }))
    }

    @Test("graph search reintroduces detached community nodes into the graph payload")
    func graphSearchReintroducesDetachedCommunityNodesIntoTheGraphPayload() {
        let payload = KnowledgeGraphView.knowledgeGraphPayload(
            fileSystemEntries: [makeObsidianFile(), makeIngestFile()],
            graphSnapshot: KnowledgeGraphDirectorySnapshot(
                knowledgeNodes: [],
                communities: [
                    KnowledgeCommunityRecord(
                        id: 88,
                        name: "Detached cluster",
                        summary: "Only present as a search hit",
                        summaryInputHash: nil,
                        embedding: nil
                    )
                ],
                overviews: [makeOverview()],
                activities: [makeActivity()]
            ),
            selectedNodeID: nil,
            graphRAGRetrieval: GraphRAGRetrievalResult(
                query: "cluster",
                hits: [
                    GraphRAGHit(
                        entityType: .community,
                        entityID: 88,
                        nodeID: nil,
                        communityID: 88,
                        title: "Detached cluster",
                        description: "Only present as a search hit",
                        hybridScore: 0.9,
                        rerankScore: 0.9
                    )
                ],
                context: GraphRAGContext()
            ),
            communityLinks: [],
            bridgeLinks: [],
            claims: []
        )

        #expect(payload.nodes.contains(where: { $0.id == "knowledge-community:88" }))
    }

    @Test("community relationships are excluded from the overlay payload")
    func communityRelationshipsAreExcludedFromTheOverlayPayload() {
        let overlayLinks = KnowledgeGraphView.graphOverlayLinks(
            graphSnapshot: makeSnapshot(),
            communityLinks: makeCommunityLinks(),
            activityLinks: [],
            overviewLinks: []
        )

        #expect(overlayLinks.isEmpty)
    }

    @Test("graph search highlights community hits in the graph payload")
    func graphSearchHighlightsCommunityHitsInTheGraphPayload() {
        let payload = KnowledgeGraphView.knowledgeGraphPayload(
            fileSystemEntries: [makeObsidianFile(), makeIngestFile()],
            graphSnapshot: makeSnapshot(),
            selectedNodeID: nil,
            graphRAGRetrieval: makeGraphRAGRetrieval(),
            communityLinks: makeCommunityLinks(),
            bridgeLinks: [],
            claims: []
        )
        let node = payload.nodes.first(where: { $0.id == "knowledge-community:77" })

        #expect(node?.searchHitRank == 0)
    }

    @Test("graph search highlights node hits in the graph payload")
    func graphSearchHighlightsNodeHitsInTheGraphPayload() {
        let payload = KnowledgeGraphView.knowledgeGraphPayload(
            fileSystemEntries: [makeObsidianFile(), makeIngestFile()],
            graphSnapshot: makeSnapshot(),
            selectedNodeID: nil,
            graphRAGRetrieval: makeGraphRAGRetrieval(),
            communityLinks: makeCommunityLinks(),
            bridgeLinks: [],
            claims: []
        )
        let node = payload.nodes.first(where: { $0.id == "knowledge-node:10" })

        #expect(node?.searchHitRank == 1)
    }

    @Test("claim hits fall back to highlighting their parent knowledge node")
    func claimHitsFallBackToHighlightingTheirParentKnowledgeNode() {
        let payload = KnowledgeGraphView.knowledgeGraphPayload(
            fileSystemEntries: [makeObsidianFile(), makeIngestFile()],
            graphSnapshot: makeSnapshot(),
            selectedNodeID: nil,
            graphRAGRetrieval: GraphRAGRetrievalResult(
                query: "claim",
                hits: [
                    GraphRAGHit(
                        entityType: .claim,
                        entityID: 99,
                        nodeID: 10,
                        communityID: 77,
                        title: "Claim",
                        description: "A capture-specific claim",
                        hybridScore: 0.7,
                        rerankScore: 0.6
                    )
                ],
                context: GraphRAGContext()
            ),
            communityLinks: makeCommunityLinks(),
            bridgeLinks: [],
            claims: []
        )
        let node = payload.nodes.first(where: { $0.id == "knowledge-node:10" })

        #expect(node?.searchHitRank == 0)
    }
}
