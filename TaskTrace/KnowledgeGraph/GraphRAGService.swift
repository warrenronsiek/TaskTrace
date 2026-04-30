//
//  GraphRAGService.swift
//  TaskTrace
//

import Foundation
import MLXLMCommon
import OSLog

enum GraphRAGError: LocalizedError {
    case emptyQuery
    case missingQueryEmbedding

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "Graph search query cannot be empty."
        case .missingQueryEmbedding:
            "Graph search could not generate a query embedding."
        }
    }
}

final class GraphRAGService: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "graph-rag")
    private let knowledgeReadDatabase: KnowledgeReadDatabase
    private let embeddingGenerator: any ActivityEmbeddingGenerating
    private let rerankingGenerator: any ActivityRerankingGenerating
    private let textStreamingGenerator: any ActivityTextStreamingGenerating

    init(
        knowledgeReadDatabase: KnowledgeReadDatabase,
        embeddingGenerator: any ActivityEmbeddingGenerating,
        rerankingGenerator: any ActivityRerankingGenerating,
        textStreamingGenerator: any ActivityTextStreamingGenerating
    ) {
        self.knowledgeReadDatabase = knowledgeReadDatabase
        self.embeddingGenerator = embeddingGenerator
        self.rerankingGenerator = rerankingGenerator
        self.textStreamingGenerator = textStreamingGenerator
    }

    func retrieve(
        query: String,
        directoryID: Int64?,
        topN: Int = Vars.graphRAGSummaryHitLimit
    ) async throws -> GraphRAGRetrievalResult {
        let submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTopN = max(1, min(topN, 10))
        let candidateLimit = Vars.graphRAGHybridCandidateLimit
        let perSourceLimit = Vars.graphRAGPerSourceCandidateLimit

        guard !submittedQuery.isEmpty else {
            throw GraphRAGError.emptyQuery
        }

        logger.log(
            "graph-rag retrieval started queryCharacters=\(submittedQuery.count, privacy: .public) directoryID=\(directoryID.map(String.init) ?? "<all>", privacy: .public) topN=\(resolvedTopN, privacy: .public) perSourceLimit=\(perSourceLimit, privacy: .public) candidateLimit=\(candidateLimit, privacy: .public)"
        )

        let embeddingStartedAt = Date()
        let queryVector = await embeddingGenerator.generateVectors(
            for: [submittedQuery],
            promptPrefix: nil,
            source: "graph-rag-query-embedding"
        ).first ?? []

        guard !queryVector.isEmpty else {
            logger.error("graph-rag retrieval failed missing query embedding")
            throw GraphRAGError.missingQueryEmbedding
        }

        let queryVectorJSONString = String(
            decoding: try JSONEncoder().encode(queryVector),
            as: UTF8.self
        )
        logger.log(
            "graph-rag query embedding finished durationMs=\(Int(Date().timeIntervalSince(embeddingStartedAt) * 1000), privacy: .public) dimensions=\(queryVector.count, privacy: .public)"
        )

        let keywordizedQuery = SearchKeywordizer.keywordize(submittedQuery)
        let retrievalStartedAt = Date()
        let candidateTask = Task.detached(priority: .userInitiated) {
            try self.knowledgeReadDatabase.loadGraphRAGCandidates(
                directoryID: directoryID,
                ftsQuery: keywordizedQuery.isEmpty ? submittedQuery : keywordizedQuery,
                queryVectorJSONString: queryVectorJSONString,
                perSourceLimit: perSourceLimit,
                totalLimit: candidateLimit
            )
        }
        let candidates = try await candidateTask.value
        logger.log(
            "graph-rag candidate retrieval finished durationMs=\(Int(Date().timeIntervalSince(retrievalStartedAt) * 1000), privacy: .public) candidateCount=\(candidates.count, privacy: .public)"
        )

        guard !candidates.isEmpty else {
            return GraphRAGRetrievalResult(
                query: submittedQuery,
                hits: [],
                context: GraphRAGContext()
            )
        }

        let rerankStartedAt = Date()
        let rerankDocuments = candidates.map { candidate in
            let title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = candidate.description.trimmingCharacters(in: .whitespacesAndNewlines)

            if description.isEmpty {
                return title
            }

            if title.isEmpty {
                return description
            }

            return "\(title)\n\(description)"
        }
        let rerankings = await rerankingGenerator.generateRerankings(
            query: submittedQuery,
            documents: rerankDocuments,
            instruction: Vars.graphRAGRetrievalInstruction,
            source: "graph-rag-reranking"
        )
        let rerankScoreByIndex = rerankings.reduce(into: [Int: Float]()) { partial, reranking in
            partial[reranking.documentIndex] = reranking.score
        }
        logger.log(
            "graph-rag reranking finished durationMs=\(Int(Date().timeIntervalSince(rerankStartedAt) * 1000), privacy: .public) rerankingCount=\(rerankings.count, privacy: .public)"
        )

        let topHits = candidates.enumerated()
            .compactMap { index, candidate -> GraphRAGHit? in
                guard let entityType = GraphRAGEntityType(rawValue: candidate.entityType) else {
                    return nil
                }

                return GraphRAGHit(
                    entityType: entityType,
                    entityID: candidate.entityID,
                    nodeID: candidate.nodeID,
                    communityID: candidate.communityID,
                    title: candidate.title,
                    description: candidate.description,
                    hybridScore: candidate.hybridScore,
                    rerankScore: rerankScoreByIndex[index] ?? 0
                )
            }
            .sorted {
                if $0.rerankScore == $1.rerankScore {
                    if $0.hybridScore == $1.hybridScore {
                        if $0.entityType == $1.entityType {
                            return $0.entityID < $1.entityID
                        }

                        return $0.entityType.rawValue < $1.entityType.rawValue
                    }

                    return $0.hybridScore > $1.hybridScore
                }

                return $0.rerankScore > $1.rerankScore
            }
            .prefix(resolvedTopN)

        let selectedCommunityIDs = Array(
            Set(
                topHits.compactMap {
                    switch $0.entityType {
                    case .community:
                        $0.entityID
                    case .node, .claim:
                        $0.communityID
                    }
                }
            )
        ).sorted()
        let selectedNodeIDs: [Int64] = Array(
            Set(
                topHits.compactMap { hit -> Int64? in
                    switch hit.entityType {
                    case .community:
                        nil
                    case .node:
                        hit.entityID
                    case .claim:
                        hit.nodeID
                    }
                }
            )
        ).sorted()

        let contextTask = Task.detached(priority: .userInitiated) {
            try self.knowledgeReadDatabase.loadGraphRAGContext(
                directoryID: directoryID,
                communityIDs: selectedCommunityIDs,
                seedNodeIDs: selectedNodeIDs,
                nodeLimit: Vars.graphRAGSummaryNodeLimit,
                edgeLimit: Vars.graphRAGSummaryEdgeLimit,
                claimLimit: Vars.graphRAGSummaryClaimLimit
            )
        }
        let context = try await contextTask.value

        logger.log(
            "graph-rag context load finished communities=\(context.communities.count, privacy: .public) nodes=\(context.nodes.count, privacy: .public) edges=\(context.edges.count, privacy: .public) claims=\(context.claims.count, privacy: .public)"
        )

        return GraphRAGRetrievalResult(
            query: submittedQuery,
            hits: Array(topHits),
            context: context
        )
    }

    func summarize(
        retrieval: GraphRAGRetrievalResult,
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        guard !retrieval.query.isEmpty,
              !retrieval.hits.isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        return await textStreamingGenerator.streamResponse(
            prompt: Self.summaryPrompt(for: retrieval),
            instructions: Self.summaryInstructions,
            generateParameters: GenerateParameters(maxTokens: 420, temperature: 0),
            traceStartedAt: traceStartedAt
        )
    }

    private nonisolated static let summaryInstructions =
        """
        You are answering a question using TaskTrace graph retrieval context.
        Use only the provided graph context.
        Prefer concrete entities, claims, and relationships over vague generalities.
        If the context is thin or mixed, say so briefly.
        Start directly with the answer or synthesis. Do not preamble.
        """

    private nonisolated static func summaryPrompt(
        for retrieval: GraphRAGRetrievalResult
    ) -> String {
        let hits = retrieval.hits.enumerated().map { index, hit in
            """
            <hit rank="\(index + 1)" type="\(hit.entityType.rawValue)" hybrid_score="\(String(format: "%.4f", hit.hybridScore))" rerank_score="\(String(format: "%.4f", hit.rerankScore))">
            <title>\(AITextUtilities.xmlEscaped(hit.title))</title>
            <description>\(AITextUtilities.xmlEscaped(hit.description))</description>
            <node_id>\(hit.nodeID.map(String.init) ?? "none")</node_id>
            <community_id>\(hit.communityID.map(String.init) ?? "none")</community_id>
            </hit>
            """
        }.joined(separator: "\n")
        let communities = retrieval.context.communities.map { community in
            """
            <community id="\(community.id)">
            <name>\(AITextUtilities.xmlEscaped(community.name))</name>
            <summary>\(AITextUtilities.xmlEscaped(community.summary))</summary>
            </community>
            """
        }.joined(separator: "\n")
        let nodes = retrieval.context.nodes.map { node in
            """
            <node id="\(node.id)" community_id="\(node.communityID.map(String.init) ?? "none")">
            <name>\(AITextUtilities.xmlEscaped(node.name))</name>
            <kind>\(AITextUtilities.xmlEscaped(node.kind))</kind>
            <description>\(AITextUtilities.xmlEscaped(node.description))</description>
            </node>
            """
        }.joined(separator: "\n")
        let edges = retrieval.context.edges.map { edge in
            """
            <edge id="\(edge.id)" first_node_id="\(edge.firstNodeID)" second_node_id="\(edge.secondNodeID)">
            <relationship_type>\(AITextUtilities.xmlEscaped(edge.relationshipType))</relationship_type>
            <description>\(AITextUtilities.xmlEscaped(edge.description))</description>
            </edge>
            """
        }.joined(separator: "\n")
        let claims = retrieval.context.claims.map { claim in
            """
            <claim id="\(claim.id)" node_id="\(claim.nodeID)">
            \(AITextUtilities.xmlEscaped(claim.text))
            </claim>
            """
        }.joined(separator: "\n")

        return """
        <graph_rag_request>
        <query>\(AITextUtilities.xmlEscaped(retrieval.query))</query>
        <top_hits>
        \(hits)
        </top_hits>
        <communities>
        \(communities)
        </communities>
        <nodes>
        \(nodes)
        </nodes>
        <edges>
        \(edges)
        </edges>
        <claims>
        \(claims)
        </claims>
        <task>
        Answer the query using the graph context above. Tie the answer back to the most relevant communities, knowledge nodes, and claims.
        </task>
        </graph_rag_request>
        """
    }
}
