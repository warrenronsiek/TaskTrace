//
//  TaskTraceSearchService.swift
//  TaskTrace
//
//  Created by Codex on 3/28/26.
//

import Foundation
import OSLog

enum TaskTraceSearchError: LocalizedError {
    case emptyQuery

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "Search query cannot be empty."
        }
    }
}

nonisolated struct SearchRetrievalResult: Equatable, Sendable {
    let results: [SearchResultTree]
    let rankedDocuments: [String]
}

nonisolated struct SearchRetrievalSnapshot: Equatable, Sendable {
    let results: [SearchResultTree]
}

final class TaskTraceSearchService: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "search")
    private let searchDatabaseActor: SearchDatabaseActor
    private let rerankingGenerator: any ActivityRerankingGenerating
    private let searchSummaryGenerator: any SearchSummaryGenerating
    private let relevanceFloor: Double

    init(
        searchDatabaseActor: SearchDatabaseActor,
        rerankingGenerator: any ActivityRerankingGenerating,
        searchSummaryGenerator: any SearchSummaryGenerating,
        relevanceFloor: Double = -3
    ) {
        self.searchDatabaseActor = searchDatabaseActor
        self.rerankingGenerator = rerankingGenerator
        self.searchSummaryGenerator = searchSummaryGenerator
        self.relevanceFloor = relevanceFloor
    }

    convenience init(
        database: TaskTraceDatabase,
        rerankingGenerator: any ActivityRerankingGenerating,
        searchSummaryGenerator: any SearchSummaryGenerating,
        relevanceFloor: Double = -3
    ) {
        self.init(
            searchDatabaseActor: SearchDatabaseActor(database: database),
            rerankingGenerator: rerankingGenerator,
            searchSummaryGenerator: searchSummaryGenerator,
            relevanceFloor: relevanceFloor
        )
    }

    convenience init(
        database: TaskTraceDatabase,
        activityAI: any ActivityAIOperating,
        relevanceFloor: Double = -3
    ) {
        self.init(
            database: database,
            rerankingGenerator: activityAI,
            searchSummaryGenerator: activityAI,
            relevanceFloor: relevanceFloor
        )
    }

    func warmSummaryModel(traceStartedAt: Date?) async {
        await searchSummaryGenerator.warmSearchSummaryModel(traceStartedAt: traceStartedAt)
    }

    func searchSummary(
        query: String,
        rankedDocuments: [String],
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        await searchSummaryGenerator.searchSummary(
            query: query,
            rankedDocuments: rankedDocuments,
            traceStartedAt: traceStartedAt
        )
    }

    func retrieve(
        query: String,
        limit: Int = 5,
        progress: @escaping @Sendable (SearchProgressStage?, Set<SearchProgressStage>) async -> Void = { _, _ in },
        publish: @escaping @Sendable (SearchRetrievalSnapshot) async -> Void = { _ in }
    ) async throws -> SearchRetrievalResult {
        let resolvedLimit = max(1, min(limit, 50))
        let perPassLimit = max(1, min(3, resolvedLimit))

        guard !query.isEmpty else {
            logger.log("search retrieval skipped empty query")
            throw TaskTraceSearchError.emptyQuery
        }

        let startedAt = Date()
        logger.log(
            "search retrieval started submittedCharacters=\(query.count, privacy: .public) limit=\(resolvedLimit, privacy: .public)"
        )

        await progress(.firstPassKeywordize, [])
        let firstPassKeywordizeStartedAt = Date()
        let firstPassQuery = SearchKeywordizer.keywordize(query)
        logger.log(
            "search firstPass keywordize finished durationMs=\(Int(Date().timeIntervalSince(firstPassKeywordizeStartedAt) * 1000), privacy: .public) queryCharacters=\(firstPassQuery.count, privacy: .public)"
        )

        await progress(.firstPassSearch, [.firstPassKeywordize])
        let firstPassSearchStartedAt = Date()
        logger.log("search firstPass dbSearch started")
        let firstPassSearchResults = try await searchDatabaseActor.dbSearch(
            query: firstPassQuery,
            limit: perPassLimit,
            relevanceFloor: relevanceFloor
        )
        let firstPassResults = firstPassSearchResults.trees
        logger.log(
            "search firstPass dbSearch finished durationMs=\(Int(Date().timeIntervalSince(firstPassSearchStartedAt) * 1000), privacy: .public) resultCount=\(firstPassResults.count, privacy: .public) matchedNodeCount=\(firstPassSearchResults.matchedNodes.count, privacy: .public) perPassLimit=\(perPassLimit, privacy: .public)"
        )
        await publish(SearchRetrievalSnapshot(results: firstPassResults))

        let secondPassSourceText = {
            let nodeTextByID = firstPassResults.reduce(into: ([Int64: String](), [Int64: String](), [Int64: String]())) { partialResult, tree in
                if let summary = tree.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                    partialResult.0[tree.id] = summary
                }

                tree.activities.forEach { activity in
                    if let summary = activity.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                        partialResult.1[activity.id] = summary
                    }

                    activity.screenshots.forEach { screenshot in
                        let detail = (screenshot.summary ?? screenshot.description ?? screenshot.ocrText)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        if let detail, !detail.isEmpty {
                            partialResult.2[screenshot.id] = detail
                        }
                    }
                }
            }

            return firstPassSearchResults.matchedNodes.reduce(into: ([String](), Set<String>())) { partialResult, matchedNode in
                let sourceText: String? = switch matchedNode.kind {
                case .overview:
                    nodeTextByID.0[matchedNode.id]
                case .activity:
                    nodeTextByID.1[matchedNode.id]
                case .screenshot:
                    nodeTextByID.2[matchedNode.id]
                }

                guard let sourceText,
                      partialResult.1.insert(sourceText).inserted
                else {
                    return
                }

                partialResult.0.append(sourceText)
            }.0
        }()

        await progress(.secondPassKeywordize, [.firstPassKeywordize, .firstPassSearch])
        let secondPassKeywordizeStartedAt = Date()
        let secondPassKeywords = SearchKeywordizer.keywords(in: secondPassSourceText)
        let secondPassQuery = SearchKeywordizer.query(from: secondPassKeywords)
        logger.log(
            "search secondPass keywordize finished durationMs=\(Int(Date().timeIntervalSince(secondPassKeywordizeStartedAt) * 1000), privacy: .public) sourceFragments=\(secondPassSourceText.count, privacy: .public) keywordCount=\(secondPassKeywords.count, privacy: .public) queryCharacters=\(secondPassQuery.count, privacy: .public)"
        )

        await progress(.secondPassSearch, [.firstPassKeywordize, .firstPassSearch, .secondPassKeywordize])
        let secondPassResults: [SearchResultTree] = try await {
            if secondPassQuery.isEmpty {
                logger.log("search secondPass dbSearch skipped empty expanded query")
                return []
            }

            let secondPassSearchStartedAt = Date()
            logger.log("search secondPass dbSearch started")
            let results = try await searchDatabaseActor.dbSearch(
                query: secondPassQuery,
                limit: perPassLimit,
                relevanceFloor: relevanceFloor
            )
            logger.log(
                "search secondPass dbSearch finished durationMs=\(Int(Date().timeIntervalSince(secondPassSearchStartedAt) * 1000), privacy: .public) resultCount=\(results.trees.count, privacy: .public) matchedNodeCount=\(results.matchedNodes.count, privacy: .public) perPassLimit=\(perPassLimit, privacy: .public)"
            )
            return results.trees
        }()

        let combinedResults = (firstPassResults + secondPassResults).reduce(into: ([SearchResultTree](), Set<Int64>())) { partialResult, tree in
            if partialResult.1.insert(tree.id).inserted {
                partialResult.0.append(tree)
            }
        }.0
        logger.log("search combined resultCount=\(combinedResults.count, privacy: .public)")
        await publish(SearchRetrievalSnapshot(results: Array(combinedResults.prefix(resolvedLimit))))

        await progress(
            .reranking,
            [.firstPassKeywordize, .firstPassSearch, .secondPassKeywordize, .secondPassSearch]
        )
        let rerankingStartedAt = Date()
        let rerankingInputs = combinedResults.reduce(into: [(String, String)]()) { partialResult, tree in
            if let summary = tree.summary, !summary.isEmpty {
                partialResult.append(("overview:\(tree.id)", summary))
            }

            tree.activities.forEach { activity in
                if let summary = activity.summary, !summary.isEmpty {
                    partialResult.append(("activity:\(activity.id)", summary))
                }

                activity.screenshots.forEach { screenshot in
                    if let summary = screenshot.summary, !summary.isEmpty {
                        partialResult.append(("screenshot:\(screenshot.id)", summary))
                    }
                }
            }
        }
        let rerankings = await rerankingGenerator.generateRerankings(
            query: query,
            documents: rerankingInputs.map(\.1),
            instruction: Vars.retrievalInstruction,
            source: "search-reranking"
        )
        let scoresByNodeID = {
            guard !rerankingInputs.isEmpty, !rerankings.isEmpty else {
                return [String: Float]()
            }

            let scoresByNodeID = rerankings.reduce(into: [String: Float]()) { partialResult, reranking in
                guard reranking.documentIndex >= 0, reranking.documentIndex < rerankingInputs.count else {
                    return
                }

                partialResult[rerankingInputs[reranking.documentIndex].0] = reranking.score
            }
            let scoreRange = scoresByNodeID.values.reduce(into: (Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)) { partialResult, score in
                partialResult.0 = min(partialResult.0, score)
                partialResult.1 = max(partialResult.1, score)
            }

            guard scoreRange.0.isFinite, scoreRange.1.isFinite else {
                return [:]
            }

            if scoreRange.0 == scoreRange.1 {
                return scoresByNodeID.reduce(into: [String: Float]()) { partialResult, entry in
                    partialResult[entry.key] = 1
                }
            }

            return scoresByNodeID.reduce(into: [String: Float]()) { partialResult, entry in
                partialResult[entry.key] = (entry.value - scoreRange.0) / (scoreRange.1 - scoreRange.0)
            }
        }()
        logger.log(
            "search reranking finished durationMs=\(Int(Date().timeIntervalSince(rerankingStartedAt) * 1000), privacy: .public) rankedNodeCount=\(scoresByNodeID.count, privacy: .public)"
        )

        let rankedResults = combinedResults.enumerated()
            .map { offset, tree in
                let rankedActivities = tree.activities.map { activity in
                    let rankedScreenshots = activity.screenshots.map { screenshot in
                        SearchResultScreenshot(
                            id: screenshot.id,
                            image: screenshot.image,
                            ts: screenshot.ts,
                            description: screenshot.description,
                            ocrText: screenshot.ocrText,
                            summary: screenshot.summary,
                            descriptionVector: screenshot.descriptionVector,
                            ignoreReason: screenshot.ignoreReason,
                            jsonProperties: screenshot.jsonProperties,
                            activityID: screenshot.activityID,
                            score: scoresByNodeID["screenshot:\(screenshot.id)"]
                        )
                    }
                    let activityScore =
                        ([scoresByNodeID["activity:\(activity.id)"]] + rankedScreenshots.map(\.score))
                        .compactMap { $0 }
                        .max()

                    return SearchResultActivity(
                        id: activity.id,
                        startTime: activity.startTime,
                        application: activity.application,
                        keystrokes: activity.keystrokes,
                        microphone: activity.microphone,
                        summary: activity.summary,
                        tagID: activity.tagID,
                        jsonProperties: activity.jsonProperties,
                        overviewID: activity.overviewID,
                        score: activityScore,
                        screenshots: rankedScreenshots
                    )
                }
                let treeScore =
                    ([scoresByNodeID["overview:\(tree.id)"]] + rankedActivities.map(\.score))
                    .compactMap { $0 }
                    .max()

                return (
                    offset,
                    SearchResultTree(
                        id: tree.id,
                        title: tree.title,
                        summary: tree.summary,
                        jsonProperties: tree.jsonProperties,
                        editedDuration: tree.editedDuration,
                        tagID: tree.tagID,
                        score: treeScore,
                        activities: rankedActivities
                    )
                )
            }
            .sorted { lhs, rhs in
                let lhsScore = lhs.1.score ?? 0
                let rhsScore = rhs.1.score ?? 0

                if lhsScore == rhsScore {
                    return lhs.0 < rhs.0
                }

                return lhsScore > rhsScore
            }
            .map(\.1)
            .prefix(resolvedLimit)
            .map { (tree: SearchResultTree) in
                tree
            }
        let rankedDocuments: [String] = rerankings.compactMap { (reranking: ActivityAIReranking) -> String? in
                guard reranking.documentIndex >= 0, reranking.documentIndex < rerankingInputs.count else {
                    return nil
                }

                return rerankingInputs[reranking.documentIndex].1
            }
            .prefix(resolvedLimit)
            .map { (document: String) in
                document
            }

        logger.log(
            "search retrieval finished totalDurationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) resultCount=\(rankedResults.count, privacy: .public)"
        )
        await publish(SearchRetrievalSnapshot(results: rankedResults))
        return SearchRetrievalResult(
            results: rankedResults,
            rankedDocuments: rankedDocuments
        )
    }
}
