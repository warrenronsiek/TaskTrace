//
//  SearchStore.swift
//  TaskTrace
//
//  Created by Codex on 3/26/26.
//

import Combine
import Foundation
import OSLog

nonisolated enum SearchProgressStage: CaseIterable, Hashable, Sendable {
    case firstPassKeywordize
    case firstPassSearch
    case secondPassKeywordize
    case secondPassSearch
    case reranking
    case searchSummary

    var title: String {
        switch self {
        case .firstPassKeywordize:
            "Extracting query keywords"
        case .firstPassSearch:
            "Searching indexed records"
        case .secondPassKeywordize:
            "Extracting match keywords"
        case .secondPassSearch:
            "Running expanded search"
        case .reranking:
            "Ranking matched nodes"
        case .searchSummary:
            "Summarizing results"
        }
    }
}

nonisolated enum SearchProgressStatus: Equatable, Sendable {
    case pending
    case active
    case completed
}

nonisolated struct SearchProgress: Equatable, Sendable {
    let activeStage: SearchProgressStage?
    let completedStages: Set<SearchProgressStage>

    static let idle = SearchProgress(activeStage: nil, completedStages: [])
    static let finished = SearchProgress(activeStage: nil, completedStages: Set(SearchProgressStage.allCases))

    var isVisible: Bool {
        activeStage != nil || !completedStages.isEmpty
    }

    func status(for stage: SearchProgressStage) -> SearchProgressStatus {
        if completedStages.contains(stage) {
            .completed
        } else if activeStage == stage {
            .active
        } else {
            .pending
        }
    }
}

@MainActor
final class SearchStore: ObservableObject {
    private static let uiSearchLimit = 5
    @Published var query: String
    @Published private(set) var results: [SearchResultTree]
    @Published private(set) var searchSummaryText: String?
    @Published private(set) var isSearching: Bool
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasSearched: Bool
    @Published private(set) var progress: SearchProgress
    
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "search")
    private let searchService: TaskTraceSearchService?
    private var summaryTask: Task<Void, Never>?
    private var summaryTaskID = UUID()

    init(
        searchService: TaskTraceSearchService
    ) {
        self.searchService = searchService
        self.query = ""
        self.results = []
        self.searchSummaryText = nil
        self.isSearching = false
        self.errorMessage = nil
        self.hasSearched = false
        self.progress = .idle
    }

    convenience init(
        database: TaskTraceDatabase,
        activityAI: any ActivityAIOperating,
        relevanceFloor: Double = -3
    ) {
        self.init(
            searchService: TaskTraceSearchService(
                database: database,
                activityAI: activityAI,
                relevanceFloor: relevanceFloor
            )
        )
    }

    init(previewResults: [SearchResultTree]) {
        self.searchService = nil
        self.query = ""
        self.results = previewResults
        self.searchSummaryText = nil
        self.isSearching = false
        self.errorMessage = nil
        self.hasSearched = !previewResults.isEmpty
        self.progress = .idle
    }

    func stop() {
        // Search summary generation runs in detached work, so cancel it explicitly
        // during app shutdown.
        summaryTask?.cancel()
        summaryTask = nil
        isSearching = false
    }

    func search() async {
        let submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        hasSearched = true
        errorMessage = nil

        guard !submittedQuery.isEmpty else {
            logger.log("search skipped empty query")
            summaryTask?.cancel()
            summaryTask = nil
            results = []
            searchSummaryText = nil
            progress = .idle
            return
        }

        guard let searchService else {
            logger.error("search failed because database is unavailable")
            summaryTask?.cancel()
            summaryTask = nil
            results = []
            searchSummaryText = nil
            progress = .idle
            return
        }

        summaryTask?.cancel()
        summaryTask = nil
        let summaryTaskID = UUID()
        self.summaryTaskID = summaryTaskID
        isSearching = true
        results = []
        searchSummaryText = nil

        do {
            let startedAt = Date()
            logger.log("search started submittedCharacters=\(submittedQuery.count, privacy: .public)")
            Task(priority: .utility) {
                await searchService.warmSummaryModel(traceStartedAt: startedAt)
            }

            let retrieval = try await searchService.retrieve(
                query: submittedQuery,
                limit: Self.uiSearchLimit,
                progress: { activeStage, completedStages in
                    await MainActor.run {
                        self.progress = SearchProgress(activeStage: activeStage, completedStages: completedStages)
                    }
                },
                publish: { snapshot in
                    await MainActor.run {
                        self.results = snapshot.results
                    }
                }
            )
            self.results = retrieval.results
            updateProgress(
                .searchSummary,
                [.firstPassKeywordize, .firstPassSearch, .secondPassKeywordize, .secondPassSearch, .reranking]
            )

            if !retrieval.rankedDocuments.isEmpty {
                let completedStages = Set(SearchProgressStage.allCases).subtracting([.searchSummary])
                self.searchSummaryText = nil
                self.summaryTask = Task.detached(priority: .userInitiated) { [logger] in
                    let summaryStartedAt = Date()
                    let rankedSummaryCharacterCount = retrieval.rankedDocuments.reduce(0) { $0 + $1.count }
                    logger.log(
                        "search summary stream started documents=\(retrieval.rankedDocuments.count, privacy: .public) totalCharacters=\(rankedSummaryCharacterCount, privacy: .public)"
                    )

                    do {
                        let summaryStreamRequestedAt = Date()
                        let summaryStream = await searchService.searchSummary(
                            query: submittedQuery,
                            rankedDocuments: retrieval.rankedDocuments,
                            traceStartedAt: startedAt
                        )
                        logger.log(
                            "search summary stream acquired elapsedMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) durationMs=\(Int(Date().timeIntervalSince(summaryStreamRequestedAt) * 1000), privacy: .public)"
                        )

                        var firstChunkDurationMs: Int?

                        for try await chunk in summaryStream {
                            let shouldContinue = await MainActor.run { [self] in
                                !Task.isCancelled && self.summaryTaskID == summaryTaskID
                            }

                            guard shouldContinue else {
                                return
                            }

                            if firstChunkDurationMs == nil {
                                firstChunkDurationMs = Int(Date().timeIntervalSince(summaryStartedAt) * 1000)
                                logger.log(
                                    "search summary first chunk received elapsedMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) durationMs=\(firstChunkDurationMs ?? 0, privacy: .public) chunkCharacters=\(chunk.count, privacy: .public)"
                                )
                            }

                            await MainActor.run { [self] in
                                self.searchSummaryText = (self.searchSummaryText ?? "") + chunk
                            }
                        }

                        let shouldFinish = await MainActor.run { [self] in
                            !Task.isCancelled && self.summaryTaskID == summaryTaskID
                        }

                        guard shouldFinish else {
                            return
                        }

                        let finalCharacterCount = await MainActor.run { [self] in
                            if let searchSummaryText = self.searchSummaryText {
                                self.searchSummaryText = AITextUtilities.normalizedNarration(searchSummaryText)
                            }
                            self.progress = .finished
                            self.summaryTask = nil
                            return (self.searchSummaryText ?? "").count
                        }
                        logger.log(
                            "search summary stream finished elapsedMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) durationMs=\(Int(Date().timeIntervalSince(summaryStartedAt) * 1000), privacy: .public) firstChunkDurationMs=\(firstChunkDurationMs ?? -1, privacy: .public) characters=\(finalCharacterCount, privacy: .public)"
                        )
                    } catch is CancellationError {
                        await MainActor.run { [self] in
                            if self.summaryTaskID == summaryTaskID {
                                self.summaryTask = nil
                            }
                        }
                        logger.log("search summary stream cancelled")
                    } catch {
                        let shouldHandleError = await MainActor.run { [self] in
                            self.summaryTaskID == summaryTaskID
                        }

                        guard shouldHandleError else {
                            return
                        }

                        logger.error(
                            "search summary stream failed error=\(String(describing: error), privacy: .public)"
                        )
                        await MainActor.run { [self] in
                            self.progress = SearchProgress(activeStage: nil, completedStages: completedStages)
                            self.summaryTask = nil
                        }
                    }
                }
            }
            logger.log("search finished totalDurationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public)")
        } catch {
            logger.error("search failed error=\(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
        }

        isSearching = false
        if errorMessage != nil {
            progress = .idle
        } else if summaryTask == nil {
            progress = .finished
        }
    }

    private func updateProgress(
        _ activeStage: SearchProgressStage?,
        _ completedStages: Set<SearchProgressStage>
    ) {
        progress = SearchProgress(activeStage: activeStage, completedStages: completedStages)
    }
}
