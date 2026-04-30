//
//  KnowledgeGraphStore.swift
//  TaskTrace
//
//  Created by Codex on 4/3/26.
//

import Combine
import Foundation

@MainActor
final class KnowledgeGraphStore: ObservableObject {
    @Published var graphRAGQuery: String
    @Published private(set) var directories: [KnowledgeDirectoryRecord]
    @Published private(set) var selectedDirectoryID: Int64?
    @Published private(set) var fileSystemEntries: [KnowledgeFileSystemEntry]
    @Published private(set) var graphSnapshot: KnowledgeGraphDirectorySnapshot
    @Published private(set) var graphBuildProgress: KnowledgeGraphBuildProgress
    @Published private(set) var activeBuildID: Int64?
    @Published private(set) var lastCompletedBuildID: Int64?
    @Published private(set) var isBuilding: Bool
    @Published private(set) var isGraphLoading: Bool
    @Published private(set) var isSelectedFileLoading: Bool
    @Published private(set) var selectedGraphNodeID: String?
    @Published private(set) var knowledgeBridgeLinks: [KnowledgeBridgeLinkRecord]
    @Published private(set) var knowledgeCommunityLinks: [KnowledgeCommunityLinkRecord]
    @Published private(set) var knowledgeActivityLinks: [KnowledgeActivityLinkRecord]
    @Published private(set) var knowledgeOverviewLinks: [KnowledgeOverviewLinkRecord]
    @Published private(set) var selectedNodeClaims: [KnowledgeClaimRecord]
    @Published private(set) var selectedFileID: Int64?
    @Published private(set) var selectedFilePath: String?
    @Published private(set) var selectedFilePreview: KnowledgeFilePreview?
    @Published private(set) var selectedFileIndex: KnowledgeFileIndexSummary?
    @Published private(set) var graphRAGRetrieval: GraphRAGRetrievalResult?
    @Published private(set) var graphRAGSummaryText: String?
    @Published private(set) var isGraphRAGSearching: Bool
    @Published private(set) var isGraphRAGSummarizing: Bool
    @Published private(set) var graphRAGErrorMessage: String?
    @Published private(set) var errorMessage: String?

    private let actorSystem: ActorSystem?
    private let knowledgeGraphActor: KnowledgeGraphActor?
    private let knowledgeReadDatabase: KnowledgeReadDatabase?
    private let graphRAGService: GraphRAGService?
    private let activityStore: ActivityStore?
    private let overviewStore: OverviewStore?
    private let identifierActor: IdentifierActor
    private let now: @Sendable () -> Date
    private let taskTraceIngestDirectoryURL: @Sendable () throws -> URL
    private let browserPluginIngestSignal: any BrowserPluginIngestChangeSignaling
    private var updatesTask: Task<Void, Never>?
    private var fileSystemTask: Task<Void, Never>?
    private var graphTask: Task<Void, Never>?
    private var graphProgressTask: Task<Void, Never>?
    private var selectedFileIndexTask: Task<Void, Never>?
    private var selectedFilePreviewTask: Task<Void, Never>?
    private var projectionReloadTask: Task<Void, Never>?
    private var selectedFileReloadTask: Task<Void, Never>?
    private var selectedGraphNodeTask: Task<Void, Never>?
    private var graphRAGSummaryTask: Task<Void, Never>?
    private var activityStateCancellable: AnyCancellable?
    private var activityDayCancellable: AnyCancellable?
    private var overviewsCancellable: AnyCancellable?
    private var browserPluginIngestObserver: NSObjectProtocol?
    private var graphRAGTaskID = UUID()
    private var latestRevision: Int64
    private var latestDataRevision: Int64

    init(
        actorSystem: ActorSystem,
        knowledgeGraphActor: KnowledgeGraphActor,
        knowledgeReadDatabase: KnowledgeReadDatabase,
        graphRAGService: GraphRAGService? = nil,
        activityStore: ActivityStore? = nil,
        overviewStore: OverviewStore? = nil,
        identifierActor: IdentifierActor = .shared,
        now: @escaping @Sendable () -> Date = Date.init,
        taskTraceIngestDirectoryURL: @escaping @Sendable () throws -> URL = { try BrowserPluginIngestLocation.directoryURL() },
        browserPluginIngestSignal: any BrowserPluginIngestChangeSignaling = DistributedBrowserPluginIngestChangeSignal()
    ) {
        self.actorSystem = actorSystem
        self.knowledgeGraphActor = knowledgeGraphActor
        self.knowledgeReadDatabase = knowledgeReadDatabase
        self.graphRAGService = graphRAGService
        self.activityStore = activityStore
        self.overviewStore = overviewStore
        self.identifierActor = identifierActor
        self.graphRAGQuery = ""
        self.directories = []
        self.selectedDirectoryID = nil
        self.fileSystemEntries = []
        self.graphSnapshot = KnowledgeGraphDirectorySnapshot()
        self.graphBuildProgress = KnowledgeGraphBuildProgress()
        self.activeBuildID = nil
        self.lastCompletedBuildID = nil
        self.isBuilding = false
        self.isGraphLoading = false
        self.isSelectedFileLoading = false
        self.selectedGraphNodeID = nil
        self.knowledgeBridgeLinks = []
        self.knowledgeCommunityLinks = []
        self.knowledgeActivityLinks = []
        self.knowledgeOverviewLinks = []
        self.selectedNodeClaims = []
        self.selectedFileID = nil
        self.selectedFilePath = nil
        self.selectedFilePreview = nil
        self.selectedFileIndex = nil
        self.graphRAGRetrieval = nil
        self.graphRAGSummaryText = nil
        self.isGraphRAGSearching = false
        self.isGraphRAGSummarizing = false
        self.graphRAGErrorMessage = nil
        self.errorMessage = nil
        self.latestRevision = 0
        self.latestDataRevision = 0
        self.now = now
        self.taskTraceIngestDirectoryURL = taskTraceIngestDirectoryURL
        self.browserPluginIngestSignal = browserPluginIngestSignal
        self.activityStateCancellable = activityStore?.$state
            .map { state in
                state.activities.map {
                    [
                        String($0.id),
                        String($0.overviewID ?? -1),
                        $0.application,
                        $0.summary ?? "",
                        String($0.startTime.timeIntervalSince1970)
                    ].joined(separator: "|")
                }.joined(separator: ";")
            }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reloadGraph()
                self?.reloadGraphProgress()
            }
        self.activityDayCancellable = activityStore?.$activeDay.sink { [weak self] _ in
            guard let self else {
                return
            }

            self.knowledgeBridgeLinks = []
            self.knowledgeCommunityLinks = []
            self.knowledgeActivityLinks = []
            self.knowledgeOverviewLinks = []

            if Self.graphKnowledgeActivityID(from: self.selectedGraphNodeID) != nil
                || Self.graphKnowledgeOverviewID(from: self.selectedGraphNodeID) != nil {
                self.selectedGraphNodeID = nil
                self.selectedNodeClaims = []
            }

            self.reloadGraph(force: true)
            self.reloadGraphProgress(force: true)
        }
        self.overviewsCancellable = overviewStore?.$overviews
            .map { overviews in
                overviews.map {
                    [
                        String($0.id),
                        $0.title ?? "",
                        $0.summary ?? "",
                        String($0.editedDuration ?? -1),
                        String($0.tagID ?? -1)
                    ].joined(separator: "|")
                }.joined(separator: ";")
            }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reloadGraph()
                self?.reloadGraphProgress()
            }
        self.updatesTask = Task { @MainActor in
            let updates = await knowledgeGraphActor.updates()

            for await state in updates {
                self.applyState(state)
            }
        }
        self.browserPluginIngestObserver = browserPluginIngestSignal.addDirectoryDidChangeObserver { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                await self.ensureTaskTraceIngestSource(forceRescan: true)
            }
        }
    }

    init(
        previewDirectories: [KnowledgeDirectoryRecord] = [],
        previewFiles: [KnowledgeFileRecord] = [],
        previewSelectedFilePreview: KnowledgeFilePreview? = nil,
        previewSelectedFileIndex: KnowledgeFileIndexSummary? = nil
    ) {
        self.actorSystem = nil
        self.knowledgeGraphActor = nil
        self.knowledgeReadDatabase = nil
        self.graphRAGService = nil
        self.activityStore = nil
        self.overviewStore = nil
        self.graphRAGQuery = ""
        self.directories = previewDirectories
        self.selectedDirectoryID = nil
        self.fileSystemEntries = previewFiles.map { file in
            KnowledgeFileSystemEntry(
                id: file.id,
                directoryID: file.directoryID,
                sourceSlot: previewDirectories.first(where: { $0.id == file.directoryID })?.slot ?? .obsidianVault,
                path: file.path,
                title: file.title,
                byteCount: file.byteCount,
                totalChunks: previewSelectedFilePreview?.path == file.path ? (previewSelectedFileIndex?.chunkCount ?? 0) : 0,
                processedChunks: previewSelectedFilePreview?.path == file.path ? (previewSelectedFileIndex?.chunkCount ?? 0) : 0,
                totalNodeEmbeddings: 0,
                embeddedNodeCount: 0
            )
        }
        self.graphSnapshot = KnowledgeGraphDirectorySnapshot()
        self.graphBuildProgress = KnowledgeGraphBuildProgress()
        self.activeBuildID = nil
        self.lastCompletedBuildID = nil
        self.isBuilding = false
        self.isGraphLoading = false
        self.isSelectedFileLoading = false
        self.selectedGraphNodeID = nil
        self.knowledgeBridgeLinks = []
        self.knowledgeCommunityLinks = []
        self.knowledgeActivityLinks = []
        self.knowledgeOverviewLinks = []
        self.selectedNodeClaims = []
        self.selectedFileID = previewFiles.first(where: {
            $0.path == previewSelectedFilePreview?.path
        })?.id
        self.selectedFilePath = previewSelectedFilePreview?.path
        self.selectedFilePreview = previewSelectedFilePreview
        self.selectedFileIndex = previewSelectedFileIndex
        self.graphRAGRetrieval = nil
        self.graphRAGSummaryText = nil
        self.isGraphRAGSearching = false
        self.isGraphRAGSummarizing = false
        self.graphRAGErrorMessage = nil
        self.errorMessage = nil
        self.latestRevision = 0
        self.latestDataRevision = 0
        self.identifierActor = .shared
        self.now = Date.init
        self.taskTraceIngestDirectoryURL = { try BrowserPluginIngestLocation.directoryURL() }
        self.browserPluginIngestSignal = DistributedBrowserPluginIngestChangeSignal()
        self.updatesTask = nil
        self.fileSystemTask = nil
        self.graphTask = nil
        self.graphProgressTask = nil
        self.selectedFileIndexTask = nil
        self.selectedFilePreviewTask = nil
        self.projectionReloadTask = nil
        self.selectedFileReloadTask = nil
        self.selectedGraphNodeTask = nil
        self.graphRAGSummaryTask = nil
        self.activityStateCancellable = nil
        self.activityDayCancellable = nil
        self.overviewsCancellable = nil
        self.browserPluginIngestObserver = nil
    }

    deinit {
        if let browserPluginIngestObserver {
            browserPluginIngestSignal.removeObserver(browserPluginIngestObserver)
        }

        updatesTask?.cancel()
        fileSystemTask?.cancel()
        graphTask?.cancel()
        graphProgressTask?.cancel()
        selectedFileIndexTask?.cancel()
        selectedFilePreviewTask?.cancel()
        projectionReloadTask?.cancel()
        selectedFileReloadTask?.cancel()
        selectedGraphNodeTask?.cancel()
        graphRAGSummaryTask?.cancel()
    }

    func stop() {
        // This store owns long-lived tasks and subscriptions that can restart graph
        // work in response to UI changes, so shutdown has to turn all of them off.
        updatesTask?.cancel()
        updatesTask = nil
        fileSystemTask?.cancel()
        fileSystemTask = nil
        graphTask?.cancel()
        graphTask = nil
        graphProgressTask?.cancel()
        graphProgressTask = nil
        selectedFileIndexTask?.cancel()
        selectedFileIndexTask = nil
        selectedFilePreviewTask?.cancel()
        selectedFilePreviewTask = nil
        projectionReloadTask?.cancel()
        projectionReloadTask = nil
        selectedFileReloadTask?.cancel()
        selectedFileReloadTask = nil
        selectedGraphNodeTask?.cancel()
        selectedGraphNodeTask = nil
        graphRAGSummaryTask?.cancel()
        graphRAGSummaryTask = nil
        activityStateCancellable?.cancel()
        activityStateCancellable = nil
        activityDayCancellable?.cancel()
        activityDayCancellable = nil
        overviewsCancellable?.cancel()
        overviewsCancellable = nil
        isBuilding = false
        isGraphLoading = false
        isSelectedFileLoading = false
        isGraphRAGSearching = false
        isGraphRAGSummarizing = false
    }

    func load() async {
        guard let knowledgeGraphActor else {
            return
        }

        await knowledgeGraphActor.receive(
            Envelope(
                sender: nil,
                message: KnowledgeLoadRequested(
                    activeDay: Calendar(identifier: .gregorian).startOfDay(
                        for: activityStore?.activeDay ?? now()
                    )
                )
            )
        )
        applyState(await knowledgeGraphActor.snapshot())
        await ensureTaskTraceIngestSource()
    }

    func connectObsidianVault(url: URL) async {
        guard let actorSystem, let knowledgeGraphActor else {
            return
        }

        guard directories.contains(where: { $0.slot == .obsidianVault }) == false else {
            errorMessage = "Delete the current Obsidian vault before adding a new one."
            return
        }

        let bookmarkData = (
            try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        ) ?? (
            try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        )
        let identifier = await identifierActor.makeIdentifier(minimum: (directories.map(\.id).max() ?? 0) + 1)

        await actorSystem.broadcast(
            from: nil,
            message: KnowledgeDirectoryCreated(
                directory: KnowledgeDirectoryRecord(
                    id: identifier,
                    slot: .obsidianVault,
                    path: url.path,
                    bookmarkData: bookmarkData,
                    createdAt: now()
                )
            )
        )
        applyState(await knowledgeGraphActor.snapshot())
        reloadKnowledgeData()
    }

    func addDirectory(url: URL) async {
        await connectObsidianVault(url: url)
    }

    private func ensureTaskTraceIngestSource(
        forceRescan: Bool = false
    ) async {
        guard let actorSystem, let knowledgeGraphActor else {
            return
        }

        do {
            let ingestDirectoryURL = try taskTraceIngestDirectoryURL()
            try FileManager.default.createDirectory(
                at: ingestDirectoryURL,
                withIntermediateDirectories: true
            )

            let existingDirectory = directories.first(where: { $0.slot == .taskTraceIngest })
            let directoryID = if let existingDirectory {
                existingDirectory.id
            } else {
                await identifierActor.makeIdentifier(
                    minimum: (directories.map(\.id).max() ?? 0) + 1
                )
            }
            let directory = KnowledgeDirectoryRecord(
                id: directoryID,
                slot: .taskTraceIngest,
                path: ingestDirectoryURL.path,
                bookmarkData: nil,
                createdAt: existingDirectory?.createdAt ?? now()
            )

            guard existingDirectory?.path != ingestDirectoryURL.path || existingDirectory == nil else {
                guard forceRescan else {
                    return
                }

                await knowledgeGraphActor.receive(
                    Envelope(
                        sender: nil,
                        message: KnowledgeDirectorySyncRequested(directoryID: directory.id)
                    )
                )
                return
            }

            await actorSystem.broadcast(
                from: nil,
                message: KnowledgeDirectoryCreated(directory: directory)
            )
            applyState(await knowledgeGraphActor.snapshot())
        } catch {
            errorMessage = "Could not prepare TaskTrace browser ingest."
        }
    }

    func removeSource(slot: KnowledgeSourceSlot) async {
        guard let directory = directories.first(where: { $0.slot == slot }) else {
            return
        }

        await removeDirectory(id: directory.id)
    }

    func removeDirectory(id: Int64) async {
        guard let actorSystem, let knowledgeGraphActor else {
            return
        }

        await actorSystem.broadcast(
            from: nil,
            message: KnowledgeDirectoryDeleted(directoryID: id)
        )
        applyState(await knowledgeGraphActor.snapshot())
        reloadKnowledgeData()
    }

    func deleteFile(id fileID: Int64) async {
        guard
            let file = fileSystemEntries.first(where: { $0.id == fileID }),
            let directory = directories.first(where: { $0.id == file.directoryID }),
            let actorSystem,
            let knowledgeGraphActor
        else {
            return
        }

        if file.sourceSlot == .taskTraceIngest {
            let fileURL = URL(fileURLWithPath: directory.path)
                .appendingPathComponent(file.path)

            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                let cocoaError = error as NSError
                if cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == CocoaError.fileNoSuchFile.rawValue {
                    // If the file was already removed externally, proceed with index-driven cleanup.
                } else {
                    errorMessage = "Could not delete plugin file."
                    return
                }
            }
        }

        let retainingPaths = Set(
            fileSystemEntries.filter {
                $0.directoryID == directory.id && $0.id != fileID
            }.map(\.path)
        )

        await actorSystem.broadcast(
            from: nil,
            message: KnowledgeDirectoryScanCompleted(
                buildID: await identifierActor.makeIdentifier(),
                directoryID: directory.id,
                retainingPaths: retainingPaths,
                deletedAt: now()
            )
        )
        applyState(await knowledgeGraphActor.snapshot())
        reloadKnowledgeData()
    }

    func selectDirectory(id: Int64) async {
        guard let knowledgeGraphActor else {
            return
        }

        await knowledgeGraphActor.receive(
            Envelope(
                sender: nil,
                message: KnowledgeDirectorySyncRequested(directoryID: id)
            )
        )
    }

    func selectFile(path: String) async {
        guard let fileID = fileSystemEntries.first(where: { $0.path == path })?.id else {
            return
        }

        await selectFile(id: fileID)
    }

    func selectFile(id: Int64) async {
        selectedFileReloadTask?.cancel()
        selectedFileID = id
        selectedFilePath = fileSystemEntries.first(where: { $0.id == id })?.path
        selectedFilePreview = nil
        selectedFileIndex = nil
        isSelectedFileLoading = true
        errorMessage = nil
        reloadSelectedFilePreview()
        reloadSelectedFileIndex(force: true, showLoading: true)

        guard let actorSystem else {
            return
        }

        await actorSystem.broadcast(
            from: nil,
            message: KnowledgeFileAccessed(
                fileID: id,
                lastAccessed: now()
            )
        )
    }

    private func clearGraphSelectionState() {
        selectedGraphNodeID = nil
        knowledgeBridgeLinks = []
        knowledgeCommunityLinks = []
        knowledgeActivityLinks = []
        knowledgeOverviewLinks = []
        selectedNodeClaims = []
        graphRAGSummaryTask?.cancel()
        graphRAGRetrieval = nil
        graphRAGSummaryText = nil
        graphRAGErrorMessage = nil
        isGraphRAGSearching = false
        isGraphRAGSummarizing = false
    }

    func rebuildKnowledge() async {
        await rebuildSourceKnowledge(slot: .obsidianVault)
    }

    func rebuildSourceKnowledge(
        slot: KnowledgeSourceSlot
    ) async {
        guard let actorSystem, let knowledgeGraphActor else {
            return
        }

        if slot == .taskTraceIngest {
            await ensureTaskTraceIngestSource()
        }

        let directoryIDs = directories
            .filter { $0.slot == slot }
            .map(\.id)

        guard !directoryIDs.isEmpty else {
            return
        }

        clearGraphSelectionState()

        for directoryID in directoryIDs {
            await actorSystem.broadcast(
                from: nil,
                message: RebuildKnowledge(directoryID: directoryID)
            )
            await knowledgeGraphActor.receive(
                Envelope(
                    sender: nil,
                    message: KnowledgeDirectorySyncRequested(directoryID: directoryID)
                )
            )
        }
    }

    func rebuildActivityKnowledge() async {
        guard let actorSystem else {
            return
        }

        let activeDay = Calendar(identifier: .gregorian).startOfDay(
            for: activityStore?.activeDay ?? now()
        )

        clearGraphSelectionState()

        await actorSystem.broadcast(
            from: nil,
            message: RebuildActivityKnowledge(activeDay: activeDay)
        )
    }

    func runGraphRAG() async {
        let submittedQuery = graphRAGQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        graphRAGSummaryTask?.cancel()
        graphRAGTaskID = UUID()
        graphRAGErrorMessage = nil
        graphRAGSummaryText = nil
        isGraphRAGSearching = false
        isGraphRAGSummarizing = false

        guard !submittedQuery.isEmpty else {
            graphRAGRetrieval = nil
            return
        }

        guard let graphRAGService else {
            graphRAGRetrieval = nil
            graphRAGErrorMessage = "Graph retrieval is unavailable."
            return
        }

        let taskID = graphRAGTaskID
        isGraphRAGSearching = true
        graphRAGRetrieval = nil

        do {
            let startedAt = Date()
            let retrieval = try await graphRAGService.retrieve(
                query: submittedQuery,
                directoryID: nil,
                topN: Vars.graphRAGSummaryHitLimit
            )

            guard graphRAGTaskID == taskID else {
                return
            }

            graphRAGRetrieval = retrieval
            isGraphRAGSearching = false

            guard !retrieval.hits.isEmpty else {
                graphRAGSummaryText = nil
                return
            }

            isGraphRAGSummarizing = true
            graphRAGSummaryTask = Task { @MainActor [graphRAGService, retrieval, startedAt, taskID] in
                do {
                    let stream = await graphRAGService.summarize(
                        retrieval: retrieval,
                        traceStartedAt: startedAt
                    )

                    for try await chunk in stream {
                        guard self.graphRAGTaskID == taskID, !Task.isCancelled else {
                            return
                        }

                        self.graphRAGSummaryText = (self.graphRAGSummaryText ?? "") + chunk
                    }

                    guard self.graphRAGTaskID == taskID else {
                        return
                    }

                    if let graphRAGSummaryText = self.graphRAGSummaryText {
                        self.graphRAGSummaryText = AITextUtilities.normalizedNarration(graphRAGSummaryText)
                    }
                    self.isGraphRAGSummarizing = false
                    self.graphRAGSummaryTask = nil
                } catch is CancellationError {
                    guard self.graphRAGTaskID == taskID else {
                        return
                    }

                    self.isGraphRAGSummarizing = false
                    self.graphRAGSummaryTask = nil
                } catch {
                    guard self.graphRAGTaskID == taskID else {
                        return
                    }

                    self.graphRAGErrorMessage = "Could not summarize graph retrieval."
                    self.isGraphRAGSummarizing = false
                    self.graphRAGSummaryTask = nil
                }
            }
        } catch is CancellationError {
            guard graphRAGTaskID == taskID else {
                return
            }

            isGraphRAGSearching = false
        } catch {
            guard graphRAGTaskID == taskID else {
                return
            }

            graphRAGRetrieval = nil
            graphRAGErrorMessage = error.localizedDescription
            isGraphRAGSearching = false
            isGraphRAGSummarizing = false
        }
    }

    func selectGraphNode(id: String?) async {
        selectedGraphNodeID = id

        selectedGraphNodeTask?.cancel()

        guard let knowledgeReadDatabase else {
            knowledgeBridgeLinks = []
            knowledgeCommunityLinks = []
            knowledgeActivityLinks = []
            knowledgeOverviewLinks = []
            selectedNodeClaims = []
            return
        }

        guard let id else {
            knowledgeBridgeLinks = []
            knowledgeCommunityLinks = []
            knowledgeActivityLinks = []
            knowledgeOverviewLinks = []
            selectedNodeClaims = []
            return
        }

        selectedGraphNodeTask = Task { [weak self] in
            do {
                let selectedDirectoryID = self?.selectedDirectoryID
                let activeDay = Calendar(identifier: .gregorian).startOfDay(
                    for: self?.activityStore?.activeDay ?? self?.now() ?? Date()
                )
                let resolved = try await {
                    if let fileID = Self.graphFileID(from: id) {
                        return try await Task.detached(priority: .userInitiated) {
                            (
                                try knowledgeReadDatabase.loadKnowledgeBridgeLinks(
                                    directoryID: selectedDirectoryID,
                                    fileID: fileID
                                ),
                                [KnowledgeCommunityLinkRecord](),
                                [KnowledgeActivityLinkRecord](),
                                [KnowledgeOverviewLinkRecord](),
                                [KnowledgeClaimRecord]()
                            )
                        }.value
                    }

                    if let nodeID = Self.graphKnowledgeNodeID(from: id) {
                        return try await Task.detached(priority: .userInitiated) {
                            (
                                try knowledgeReadDatabase.loadKnowledgeBridgeLinks(
                                    directoryID: selectedDirectoryID,
                                    nodeID: nodeID
                                ),
                                [KnowledgeCommunityLinkRecord](),
                                [KnowledgeActivityLinkRecord](),
                                [KnowledgeOverviewLinkRecord](),
                                try knowledgeReadDatabase.loadKnowledgeClaims(nodeID: nodeID)
                            )
                        }.value
                    }

                    if let communityID = Self.graphKnowledgeCommunityID(from: id) {
                        return try await Task.detached(priority: .userInitiated) {
                            (
                                [KnowledgeBridgeLinkRecord](),
                                try knowledgeReadDatabase.loadKnowledgeCommunityLinks(
                                    directoryID: selectedDirectoryID,
                                    activeDay: activeDay,
                                    communityID: communityID
                                ),
                                [KnowledgeActivityLinkRecord](),
                                [KnowledgeOverviewLinkRecord](),
                                [KnowledgeClaimRecord]()
                            )
                        }.value
                    }

                    if let activityID = Self.graphKnowledgeActivityID(from: id) {
                        return try await Task.detached(priority: .userInitiated) {
                            (
                                [KnowledgeBridgeLinkRecord](),
                                [KnowledgeCommunityLinkRecord](),
                                try knowledgeReadDatabase.loadKnowledgeActivityLinks(
                                    activityID: activityID
                                ),
                                [KnowledgeOverviewLinkRecord](),
                                [KnowledgeClaimRecord]()
                            )
                        }.value
                    }

                    if let overviewID = Self.graphKnowledgeOverviewID(from: id) {
                        return try await Task.detached(priority: .userInitiated) {
                            (
                                [KnowledgeBridgeLinkRecord](),
                                [KnowledgeCommunityLinkRecord](),
                                [KnowledgeActivityLinkRecord](),
                                try knowledgeReadDatabase.loadKnowledgeOverviewLinks(
                                    overviewID: overviewID,
                                    activeDay: activeDay
                                ),
                                [KnowledgeClaimRecord]()
                            )
                        }.value
                    }

                    return (
                        [KnowledgeBridgeLinkRecord](),
                        [KnowledgeCommunityLinkRecord](),
                        [KnowledgeActivityLinkRecord](),
                        [KnowledgeOverviewLinkRecord](),
                        [KnowledgeClaimRecord]()
                    )
                }()

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard self?.selectedGraphNodeID == id else {
                        return
                    }

                    self?.knowledgeBridgeLinks = resolved.0
                    self?.knowledgeCommunityLinks = resolved.1
                    self?.knowledgeActivityLinks = resolved.2
                    self?.knowledgeOverviewLinks = resolved.3
                    self?.selectedNodeClaims = resolved.4
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard self?.selectedGraphNodeID == id else {
                        return
                    }

                    self?.errorMessage = "Could not load graph links."
                    self?.knowledgeBridgeLinks = []
                    self?.knowledgeCommunityLinks = []
                    self?.knowledgeActivityLinks = []
                    self?.knowledgeOverviewLinks = []
                    self?.selectedNodeClaims = []
                }
            }
        }
    }

    private func applyState(_ state: KnowledgeGraphActor.State) {
        guard state.revision >= latestRevision else {
            return
        }

        let previousDirectories = directories
        let previousDataRevision = latestDataRevision

        latestRevision = state.revision
        latestDataRevision = state.dataRevision
        directories = state.directories
        selectedDirectoryID = nil
        activeBuildID = state.activeBuildID
        lastCompletedBuildID = state.lastCompletedBuildID
        isBuilding = state.isBuilding
        errorMessage = state.errorMessage

        if previousDirectories != state.directories {
            knowledgeBridgeLinks = []
            knowledgeCommunityLinks = []
            knowledgeActivityLinks = []
            knowledgeOverviewLinks = []
            selectedNodeClaims = []
            graphRAGSummaryTask?.cancel()
            graphRAGRetrieval = nil
            graphRAGSummaryText = nil
            graphRAGErrorMessage = nil
            isGraphRAGSearching = false
            isGraphRAGSummarizing = false
            projectionReloadTask?.cancel()
            selectedFileReloadTask?.cancel()
            reloadKnowledgeData(force: true)
            return
        }

        if previousDataRevision != state.dataRevision {
            scheduleProjectionReload()
            scheduleSelectedFileReload()
        }
    }

    private func reloadKnowledgeData(force: Bool = false) {
        reloadFileSystem(force: force)
        reloadGraph(force: force)
        reloadGraphProgress(force: force)
    }

    private func reloadFileSystem(force: Bool = false) {
        guard let knowledgeReadDatabase else {
            fileSystemTask?.cancel()
            fileSystemEntries = []
            return
        }

        fileSystemTask?.cancel()
        fileSystemTask = Task { [weak self] in
            if !force {
                try? await Task.sleep(for: .milliseconds(120))
            }

            guard let self else {
                return
            }

            do {
                let priority = Task.currentPriority
                let entries = try await Task.detached(priority: priority) {
                    try knowledgeReadDatabase.loadKnowledgeFileSystemEntries(directoryID: nil)
                }.value
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.fileSystemEntries = entries

                    if let selectedFileID = self.selectedFileID,
                       entries.contains(where: { $0.id == selectedFileID }) == false {
                        self.clearSelectedFileState()
                    } else if let selectedFileID = self.selectedFileID {
                        self.selectedFilePath = entries.first(where: { $0.id == selectedFileID })?.path
                    }
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
            }
        }
    }

    private func reloadGraph(force: Bool = false) {
        guard let knowledgeReadDatabase else {
            graphTask?.cancel()
            graphSnapshot = KnowledgeGraphDirectorySnapshot()
            isGraphLoading = false
            return
        }

        graphTask?.cancel()
        isGraphLoading = true
        graphTask = Task { [weak self] in
            if !force {
                try? await Task.sleep(for: .milliseconds(160))
            }

            guard let self else {
                return
            }

            do {
                let activeDay = Calendar(identifier: .gregorian).startOfDay(
                    for: self.activityStore?.activeDay ?? self.now()
                )
                let priority = Task.currentPriority
                let snapshot = try await Task.detached(priority: priority) {
                    try knowledgeReadDatabase.loadKnowledgeGraphDirectorySnapshot(
                        directoryID: nil,
                        activeDay: activeDay
                    )
                }.value
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    let currentDay = Calendar(identifier: .gregorian).startOfDay(
                        for: self.activityStore?.activeDay ?? self.now()
                    )
                    guard currentDay == activeDay else {
                        return
                    }

                    self.graphSnapshot = snapshot
                    self.isGraphLoading = false
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.isGraphLoading = false
                }
            }
        }
    }

    private func reloadGraphProgress(force: Bool = false) {
        guard let knowledgeReadDatabase else {
            graphProgressTask?.cancel()
            graphBuildProgress = KnowledgeGraphBuildProgress()
            return
        }

        graphProgressTask?.cancel()
        graphProgressTask = Task { [weak self] in
            if !force {
                try? await Task.sleep(for: .milliseconds(120))
            }

            guard let self else {
                return
            }

            do {
                let activeDay = Calendar(identifier: .gregorian).startOfDay(
                    for: self.activityStore?.activeDay ?? self.now()
                )
                let priority = Task.currentPriority
                let progress = try await Task.detached(priority: priority) {
                    try knowledgeReadDatabase.loadKnowledgeGraphBuildProgress(
                        directoryID: nil,
                        activeDay: activeDay
                    )
                }.value
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    let currentDay = Calendar(identifier: .gregorian).startOfDay(
                        for: self.activityStore?.activeDay ?? self.now()
                    )
                    guard currentDay == activeDay else {
                        return
                    }

                    self.graphBuildProgress = progress
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.graphBuildProgress = KnowledgeGraphBuildProgress()
                }
            }
        }
    }

    private func reloadSelectedFilePreview() {
        guard let selectedFileID,
              let selectedFile = fileSystemEntries.first(where: { $0.id == selectedFileID }),
              let directory = directories.first(where: { $0.id == selectedFile.directoryID }) else {
            selectedFilePreviewTask?.cancel()
            selectedFilePreview = nil
            return
        }

        selectedFilePreviewTask?.cancel()
        selectedFilePreviewTask = Task { [weak self] in
            do {
                let preview = try await Task.detached(priority: .userInitiated) {
                    let directoryURL = try {
                        if let bookmarkData = directory.bookmarkData {
                            var isStale = false

                            if let scopedURL = try? URL(
                                resolvingBookmarkData: bookmarkData,
                                options: [.withSecurityScope],
                                relativeTo: nil,
                                bookmarkDataIsStale: &isStale
                            ) {
                                return scopedURL
                            }

                            return try URL(
                                resolvingBookmarkData: bookmarkData,
                                options: [],
                                relativeTo: nil,
                                bookmarkDataIsStale: &isStale
                            )
                        }

                        return URL(fileURLWithPath: directory.path, isDirectory: true)
                    }()
                    let startedAccessing = directoryURL.startAccessingSecurityScopedResource()
                    defer {
                        if startedAccessing {
                            directoryURL.stopAccessingSecurityScopedResource()
                        }
                    }

                    let fileURL = directoryURL.appendingPathComponent(selectedFile.path)
                    let data = try Data(contentsOf: fileURL)
                    let previewData = data.prefix(200_000)

                    if let content = String(data: previewData, encoding: .utf8) {
                        return KnowledgeFilePreview(
                            path: selectedFile.path,
                            byteCount: Int64(data.count),
                            content: content,
                            isTruncated: data.count > previewData.count
                        )
                    }

                    return KnowledgeFilePreview(
                        path: selectedFile.path,
                        byteCount: Int64(data.count),
                        content: "TaskTrace can see this file, but it is not UTF-8 text, so it cannot be previewed yet.",
                        isTruncated: false
                    )
                }.value
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard self?.selectedFileID == selectedFileID else {
                        return
                    }

                    self?.selectedFilePreview = preview
                    self?.selectedFilePreviewTask = nil
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard self?.selectedFileID == selectedFileID else {
                        return
                    }

                    self?.selectedFilePreview = nil
                    self?.errorMessage = "Could not read the selected file."
                    self?.selectedFilePreviewTask = nil
                }
            }
        }
    }

    private func reloadSelectedFileIndex(force: Bool = false, showLoading: Bool = false) {
        guard let knowledgeReadDatabase, let selectedFileID else {
            selectedFileIndexTask?.cancel()
            selectedFileIndex = nil
            isSelectedFileLoading = false
            return
        }

        selectedFileIndexTask?.cancel()
        if showLoading {
            isSelectedFileLoading = true
        }
        selectedFileIndexTask = Task { [weak self] in
            if !force {
                try? await Task.sleep(for: .milliseconds(90))
            }

            guard let self else {
                return
            }

            do {
                let priority = Task.currentPriority
                let index = try await Task.detached(priority: priority) {
                    try knowledgeReadDatabase.loadKnowledgeFileDetail(fileID: selectedFileID)
                }.value
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard self.selectedFileID == selectedFileID else {
                        return
                    }

                    self.selectedFileIndex = index
                    self.isSelectedFileLoading = false
                    self.selectedFileIndexTask = nil
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard self.selectedFileID == selectedFileID else {
                        return
                    }

                    if showLoading {
                        self.selectedFileIndex = nil
                    }
                    self.isSelectedFileLoading = false
                    self.selectedFileIndexTask = nil
                }
            }
        }
    }

    private func clearSelectedFileState() {
        selectedFileReloadTask?.cancel()
        selectedFileIndexTask?.cancel()
        selectedFilePreviewTask?.cancel()
        selectedFileID = nil
        selectedFilePath = nil
        selectedFilePreview = nil
        selectedFileIndex = nil
        isSelectedFileLoading = false
    }

    private func scheduleProjectionReload() {
        projectionReloadTask?.cancel()
        projectionReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else {
                return
            }

            self.reloadKnowledgeData(force: true)
            self.projectionReloadTask = nil
        }
    }

    private func scheduleSelectedFileReload() {
        guard selectedFileID != nil else {
            selectedFileReloadTask?.cancel()
            return
        }

        guard !isSelectedFileLoading else {
            return
        }

        selectedFileReloadTask?.cancel()
        selectedFileReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else {
                return
            }

            guard !self.isSelectedFileLoading else {
                self.selectedFileReloadTask = nil
                return
            }

            self.reloadSelectedFileIndex(force: true, showLoading: false)
            self.selectedFileReloadTask = nil
        }
    }

    private nonisolated static func graphFileID(from value: String) -> Int64? {
        guard value.hasPrefix("knowledge-file:") else {
            return nil
        }

        return Int64(value.dropFirst("knowledge-file:".count))
    }

    private nonisolated static func graphKnowledgeNodeID(from value: String) -> Int64? {
        guard value.hasPrefix("knowledge-node:") else {
            return nil
        }

        return Int64(value.dropFirst("knowledge-node:".count))
    }

    private nonisolated static func graphKnowledgeCommunityID(from value: String) -> Int64? {
        guard value.hasPrefix("knowledge-community:") else {
            return nil
        }

        return Int64(value.dropFirst("knowledge-community:".count))
    }

    private nonisolated static func graphKnowledgeActivityID(from value: String?) -> Int64? {
        guard let value, value.hasPrefix("knowledge-activity:") else {
            return nil
        }

        return Int64(value.dropFirst("knowledge-activity:".count))
    }

    private nonisolated static func graphKnowledgeOverviewID(from value: String?) -> Int64? {
        guard let value, value.hasPrefix("knowledge-overview:") else {
            return nil
        }

        return Int64(value.dropFirst("knowledge-overview:".count))
    }
}
