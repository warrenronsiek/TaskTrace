//
//  OverviewMCPServer.swift
//  TaskTrace
//
//  Created by Codex on 3/15/26.
//

import Combine
import Darwin
import Foundation
import ImageIO
import MCP
import OSLog
import System

@MainActor
final class OverviewMCPServerController {
    private let overviewStore: OverviewStore
    private let activityStore: ActivityStore
    private let knowledgeGraphStore: KnowledgeGraphStore
    private let settingsStore: SettingsStore
    private let runtime: OverviewMCPServerRuntime
    private var cancellables: Set<AnyCancellable> = []
    private var isStarted = false

    init(
        overviewStore: OverviewStore,
        activityStore: ActivityStore,
        knowledgeGraphStore: KnowledgeGraphStore,
        settingsStore: SettingsStore,
        searchService: TaskTraceSearchService,
        graphRAGService: GraphRAGService
    ) {
        self.overviewStore = overviewStore
        self.activityStore = activityStore
        self.knowledgeGraphStore = knowledgeGraphStore
        self.settingsStore = settingsStore
        self.runtime = OverviewMCPServerRuntime(
            searchService: searchService,
            graphRAGService: graphRAGService
        )
        
        Publishers.CombineLatest4(
            overviewStore.$overviews,
            activityStore.$state,
            activityStore.$activeDay,
            settingsStore.$mcpConfiguration
        )
        .sink { [weak self] _, _, _, _ in
            guard let self else {
                return
            }
            
            let snapshot = self.overviewStore.overviews.map { overview in
                OverviewMCPServerRuntime.OverviewSnapshot(
                    id: overview.id,
                    title: overview.title ?? "Untitled Overview",
                    summary: overview.summary ?? "Overview summary unavailable.",
                    durationSeconds: self.overviewStore.effectiveDuration(for: overview.id)
                )
            }
            let configuration = self.settingsStore.mcpConfiguration
            let shouldDriveRuntime = self.isStarted
            
            Task {
                await self.runtime.update(
                    activeDay: self.activityStore.activeDay,
                    overviews: snapshot,
                    activities: self.activityStore.state.activities,
                    configuration: configuration
                )
                
                guard shouldDriveRuntime else {
                    return
                }

                if configuration.serverEnabled {
                    await self.runtime.start()
                } else {
                    await self.runtime.stop()
                }
            }
        }
        .store(in: &cancellables)
    }
    
    func start() async {
        isStarted = true
        let snapshot = overviewStore.overviews.map { overview in
            OverviewMCPServerRuntime.OverviewSnapshot(
                id: overview.id,
                title: overview.title ?? "Untitled Overview",
                summary: overview.summary ?? "Overview summary unavailable.",
                durationSeconds: overviewStore.effectiveDuration(for: overview.id)
            )
        }
        
        await runtime.update(
            activeDay: activityStore.activeDay,
            overviews: snapshot,
            activities: activityStore.state.activities,
            configuration: settingsStore.mcpConfiguration
        )
        
        if settingsStore.mcpConfiguration.serverEnabled {
            await runtime.start()
        } else {
            await runtime.stop()
        }
    }
    
    func stop() async {
        isStarted = false
        await runtime.stop()
    }
}

actor OverviewMCPServerRuntime {
    struct OverviewSnapshot: Codable, Equatable, Sendable {
        let id: Int64
        let title: String
        let summary: String
        let durationSeconds: Int
    }
    
    struct ResourceConfiguration: Equatable, Sendable {
        let overviewResourceEnabled: Bool
        let highLevelActivityResourceEnabled: Bool
        let detailedActivityResourceEnabled: Bool
        let searchToolEnabled: Bool
        let graphSearchToolEnabled: Bool
        let highLevelActivityCount: Int?
        let detailedActivityCount: Int?
    }
    
    private struct OverviewDocument: Codable, Equatable, Sendable {
        let date: String
        let overviews: [OverviewSnapshot]
    }
    
    private struct HighLevelActivityDocument: Codable, Equatable, Sendable {
        let date: String
        let activities: [HighLevelActivitySnapshot]
    }
    
    private struct HighLevelActivitySnapshot: Codable, Equatable, Sendable {
        let id: Int64
        let application: String
        let startTime: String
        let durationSeconds: Int
        let summary: String
        let tagID: Int64?
        let overviewID: Int64?
    }
    
    private struct DetailedActivityDocument: Codable, Equatable, Sendable {
        let date: String
        let activities: [DetailedActivitySnapshot]
    }
    
    private struct DetailedActivitySnapshot: Codable, Equatable, Sendable {
        let activityId: String
        let application: String
        let startTime: String
        let durationSeconds: Int
        let keystrokes: String
        let transcript: String
        let summary: String?
        let tagId: Int64?
        let overviewId: Int64?
        let screenshots: [DetailedScreenshotSnapshot]
    }
    
    private struct DetailedScreenshotSnapshot: Codable, Equatable, Sendable {
        let screenshotId: Int64
        let uri: String?
        let mimeType: String?
        let timestamp: String
        let width: Int?
        let height: Int?
        let size: Int?
        let description: String?
        let ocr: String?
        let summary: String?
        let ignoreReason: String?
    }

    private struct ScreenshotResourceSnapshot: Equatable, Sendable {
        let uri: String
        let mimeType: String
        let data: Data
    }

    struct SearchToolResultDocument: Codable, Equatable, Sendable {
        let query: String
        let limit: Int
        let results: [RankedSearchResult]
    }

    struct RankedSearchResult: Codable, Equatable, Sendable {
        let rank: Int
        let score: Float
        let result: SearchResultTree
    }
    
    private let encoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
    private let dateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
    
    private var document = OverviewDocument(date: "", overviews: [])
    private var highLevelActivityDocument = HighLevelActivityDocument(date: "", activities: [])
    private var detailedActivityDocument = DetailedActivityDocument(date: "", activities: [])
    private var screenshotResources: [String: ScreenshotResourceSnapshot] = [:]
    private var resourceConfiguration = ResourceConfiguration(
        overviewResourceEnabled: true,
        highLevelActivityResourceEnabled: true,
        detailedActivityResourceEnabled: false,
        searchToolEnabled: true,
        graphSearchToolEnabled: true,
        highLevelActivityCount: 5,
        detailedActivityCount: 5
    )
    private struct ServerSession: Sendable {
        let server: Server
        let fileDescriptor: Int32
        let processIdentifier: Int32?
        let completionTask: Task<Void, Never>
    }

    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "mcp")
    private let socketPath: String
    private let listenerQueue = DispatchQueue(label: "com.tasktrace.mcp.broker")
    private var listenerFileDescriptor: Int32?
    private var listenerSource: DispatchSourceRead?
    private var sessions: [UUID: ServerSession] = [:]
    private var subscriptions: [UUID: Set<String>] = [:]
    private let searchService: TaskTraceSearchService?
    private let graphRAGService: GraphRAGService?
    
    init(
        searchService: TaskTraceSearchService? = nil,
        graphRAGService: GraphRAGService? = nil,
        socketPath: String = Vars.mcpBrokerSocketPath
    ) {
        self.searchService = searchService
        self.graphRAGService = graphRAGService
        self.socketPath = socketPath
    }

    nonisolated static func removeSocketFileIfPresent(at socketPath: String = Vars.mcpBrokerSocketPath) {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            return
        }

        do {
            try FileManager.default.removeItem(atPath: socketPath)
        } catch {
            Logger(subsystem: "com.tasktrace.TaskTrace", category: "mcp").error(
                "mcp broker remove socket file failed path=\(socketPath, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func removeSocketFileIfPresent() {
        Self.removeSocketFileIfPresent(at: socketPath)
    }

    func start() async {
        guard listenerFileDescriptor == nil else {
            return
        }

        removeSocketFileIfPresent()

        let result: (Int32, DispatchSourceRead)? = {
            let listenerFileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)

            guard listenerFileDescriptor >= 0 else {
                return nil
            }

            let currentFlags = Darwin.fcntl(listenerFileDescriptor, F_GETFL)
            if currentFlags >= 0 {
                _ = Darwin.fcntl(listenerFileDescriptor, F_SETFL, currentFlags | O_NONBLOCK)
            }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.stride)
            let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)

            guard socketPath.utf8.count < maxPathLength else {
                Darwin.close(listenerFileDescriptor)
                return nil
            }

            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                destination.initializeMemory(as: CChar.self, repeating: 0)
                _ = socketPath.withCString { source in
                    strncpy(
                        destination.baseAddress?.assumingMemoryBound(to: CChar.self),
                        source,
                        maxPathLength - 1
                    )
                }
            }

            let bindDidSucceed = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(listenerFileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.stride))
                }
            } == 0

            guard bindDidSucceed else {
                Darwin.close(listenerFileDescriptor)
                return nil
            }

            _ = socketPath.withCString {
                Darwin.chmod($0, mode_t(S_IRUSR | S_IWUSR))
            }

            guard Darwin.listen(listenerFileDescriptor, SOMAXCONN) == 0 else {
                Darwin.close(listenerFileDescriptor)
                removeSocketFileIfPresent()
                return nil
            }

            let listenerSource = DispatchSource.makeReadSource(
                fileDescriptor: listenerFileDescriptor,
                queue: listenerQueue
            )
            listenerSource.setEventHandler { [weak self] in
                guard let self else {
                    return
                }

                Task {
                    await self.acceptPendingConnections()
                }
            }
            listenerSource.setCancelHandler {
                Darwin.close(listenerFileDescriptor)
            }

            return (listenerFileDescriptor, listenerSource)
        }()

        guard let result else {
            logger.error("mcp broker listener start failed path=\(self.socketPath, privacy: .public) errno=\(errno, privacy: .public)")
            return
        }

        listenerFileDescriptor = result.0
        listenerSource = result.1
        result.1.resume()
        logger.log("mcp broker listener ready path=\(self.socketPath, privacy: .public)")
    }
    
    func stop() async {
        listenerSource?.cancel()
        listenerSource = nil
        listenerFileDescriptor = nil
        removeSocketFileIfPresent()

        let stoppedSessions = sessions
        sessions = [:]
        subscriptions = [:]

        for session in stoppedSessions.values {
            session.completionTask.cancel()
            await session.server.stop()
            Darwin.close(session.fileDescriptor)

            if let processIdentifier = session.processIdentifier {
                Task { @MainActor in
                    TaskTraceMCPHelperProcessRegistry.shared.unregister(processIdentifier)
                }
            }
        }

        logger.log("mcp broker listener stopped")
    }

    private func acceptPendingConnections() async {
        guard let listenerFileDescriptor else {
            return
        }

        while true {
            let acceptedFileDescriptor = Darwin.accept(listenerFileDescriptor, nil, nil)

            if acceptedFileDescriptor < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    return
                }

                logger.error("mcp broker accept failed errno=\(errno, privacy: .public)")
                return
            }

            var noSigPipe: Int32 = 1
            setsockopt(
                acceptedFileDescriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSigPipe,
                socklen_t(MemoryLayout<Int32>.size)
            )

            let sessionID = UUID()
            let peerProcessIdentifier = peerProcessIdentifier(fileDescriptor: acceptedFileDescriptor)
            let server = await makeServer(sessionID: sessionID)
            let transport = StdioTransport(
                input: FileDescriptor(rawValue: acceptedFileDescriptor),
                output: FileDescriptor(rawValue: acceptedFileDescriptor)
            )

            do {
                try await server.start(transport: transport)
            } catch {
                Darwin.close(acceptedFileDescriptor)
                logger.error("mcp broker session start failed error=\(String(describing: error), privacy: .public)")
                continue
            }

            if let peerProcessIdentifier {
                Task { @MainActor in
                    TaskTraceMCPHelperProcessRegistry.shared.register(peerProcessIdentifier)
                }
            }

            let completionTask = Task {
                await server.waitUntilCompleted()
                self.clearSession(sessionID)
            }
            sessions[sessionID] = ServerSession(
                server: server,
                fileDescriptor: acceptedFileDescriptor,
                processIdentifier: peerProcessIdentifier,
                completionTask: completionTask
            )
            logger.log(
                "mcp broker accepted session id=\(sessionID.uuidString, privacy: .public) pid=\((peerProcessIdentifier ?? -1), privacy: .public)"
            )
        }
    }

    private func clearSession(_ sessionID: UUID) {
        guard let session = sessions.removeValue(forKey: sessionID) else {
            return
        }

        subscriptions[sessionID] = nil
        Darwin.close(session.fileDescriptor)

        if let processIdentifier = session.processIdentifier {
            Task { @MainActor in
                TaskTraceMCPHelperProcessRegistry.shared.unregister(processIdentifier)
            }
        }

        logger.log(
            "mcp broker closed session id=\(sessionID.uuidString, privacy: .public) pid=\((session.processIdentifier ?? -1), privacy: .public)"
        )
    }

    private func peerProcessIdentifier(fileDescriptor: Int32) -> Int32? {
        var processIdentifier: pid_t = 0
        var processIdentifierLength = socklen_t(MemoryLayout<pid_t>.size)

        let result = withUnsafeMutablePointer(to: &processIdentifier) { pointer in
            Darwin.getsockopt(
                fileDescriptor,
                SOL_LOCAL,
                LOCAL_PEERPID,
                pointer,
                &processIdentifierLength
            )
        }

        return result == 0 ? Int32(processIdentifier) : nil
    }
    
    func update(
        activeDay: Date,
        overviews: [OverviewSnapshot],
        activities: [ActivityActor.Activity],
        configuration: SettingsStore.MCPConfiguration
    ) async {
        let nextConfiguration = ResourceConfiguration(
            overviewResourceEnabled: configuration.overviewResourceEnabled,
            highLevelActivityResourceEnabled: configuration.highLevelActivityResourceEnabled,
            detailedActivityResourceEnabled: configuration.detailedActivityResourceEnabled,
            searchToolEnabled: configuration.searchToolEnabled,
            graphSearchToolEnabled: configuration.graphSearchToolEnabled,
            highLevelActivityCount: configuration.highLevelActivityCount,
            detailedActivityCount: configuration.detailedActivityCount
        )
        let nextDocument = OverviewDocument(
            date: dateFormatter.string(from: activeDay),
            overviews: overviews
        )
        let activityDurations = activities.enumerated().map { index, activity in
            let nextStartTime = activities.indices.contains(index + 1)
            ? activities[index + 1].startTime
            : (activity.screenshots.last?.timestamp ?? activity.startTime)
            return max(Int(nextStartTime.timeIntervalSince(activity.startTime)), 0)
        }
        let nextHighLevelActivityDocument = HighLevelActivityDocument(
            date: dateFormatter.string(from: activeDay),
            activities: Array(
                activities.enumerated()
                    .filter {
                        !($0.element.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    }
                    .suffix(nextConfiguration.highLevelActivityCount ?? activities.count)
            )
            .reversed()
            .map { index, activity in
                HighLevelActivitySnapshot(
                    id: activity.id,
                    application: activity.application,
                    startTime: activity.startTime.ISO8601Format(),
                    durationSeconds: activityDurations[index],
                    summary: activity.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    tagID: activity.tagID,
                    overviewID: activity.overviewID
                )
            }
        )
        let nextDetailedActivityDocument = DetailedActivityDocument(
            date: dateFormatter.string(from: activeDay),
            activities: Array(
                activities.enumerated()
                    .suffix(nextConfiguration.detailedActivityCount ?? activities.count)
            )
            .reversed()
            .map { index, activity in
                DetailedActivitySnapshot(
                    activityId: Vars.mcpActivityIdentifier(activity.id),
                    application: activity.application,
                    startTime: activity.startTime.ISO8601Format(),
                    durationSeconds: activityDurations[index],
                    keystrokes: activity.keystrokes,
                    transcript: activity.microphone,
                    summary: activity.summary,
                    tagId: activity.tagID,
                    overviewId: activity.overviewID,
                    screenshots: activity.screenshots.map { screenshot in
                        let screenshotDimensions: (width: Int?, height: Int?)? = if let image = screenshot.image,
                            let imageSource = CGImageSourceCreateWithData(image as CFData, nil),
                            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
                            (
                                width: properties[kCGImagePropertyPixelWidth] as? Int,
                                height: properties[kCGImagePropertyPixelHeight] as? Int
                            )
                        } else {
                            nil
                        }
                        let screenshotURI = screenshot.image == nil
                        ? nil
                        : Vars.mcpActivityScreenshotResourceURI(activityId: activity.id, screenshotId: screenshot.id)

                        return DetailedScreenshotSnapshot(
                            screenshotId: screenshot.id,
                            uri: screenshotURI,
                            mimeType: screenshot.image == nil ? nil : Vars.mcpScreenshotMimeType,
                            timestamp: screenshot.timestamp.ISO8601Format(),
                            width: screenshotDimensions?.width,
                            height: screenshotDimensions?.height,
                            size: screenshot.image?.count,
                            description: screenshot.description,
                            ocr: screenshot.text,
                            summary: screenshot.summary,
                            ignoreReason: screenshot.ignoreReason
                        )
                    }
                )
            }
        )
        let nextScreenshotResources = activities
            .suffix(nextConfiguration.detailedActivityCount ?? activities.count)
            .reduce(into: [String: ScreenshotResourceSnapshot]()) { partialResult, activity in
                activity.screenshots.forEach { screenshot in
                    guard let image = screenshot.image else {
                        return
                    }

                    let uri = Vars.mcpActivityScreenshotResourceURI(activityId: activity.id, screenshotId: screenshot.id)
                    partialResult[uri] = ScreenshotResourceSnapshot(
                        uri: uri,
                        mimeType: Vars.mcpScreenshotMimeType,
                        data: image
                    )
                }
            }
        let changedResourceURIs = Set(
            [
                nextDocument != document ? Vars.mcpOverviewResourceURI : nil,
                nextHighLevelActivityDocument != highLevelActivityDocument ? Vars.mcpHighLevelActivityResourceURI : nil,
                nextDetailedActivityDocument != detailedActivityDocument ? Vars.mcpDetailedActivityResourceURI : nil,
            ]
            .compactMap { $0 }
            +
            Set(screenshotResources.keys)
                .union(nextScreenshotResources.keys)
                .compactMap { screenshotResources[$0] != nextScreenshotResources[$0] ? $0 : nil }
        )
        let didChangeResourceList =
            nextConfiguration.overviewResourceEnabled != resourceConfiguration.overviewResourceEnabled
            || nextConfiguration.highLevelActivityResourceEnabled != resourceConfiguration.highLevelActivityResourceEnabled
            || nextConfiguration.detailedActivityResourceEnabled != resourceConfiguration.detailedActivityResourceEnabled
            || nextConfiguration.highLevelActivityCount != resourceConfiguration.highLevelActivityCount
            || nextConfiguration.detailedActivityCount != resourceConfiguration.detailedActivityCount
        let didChangeToolList =
            nextConfiguration.searchToolEnabled != resourceConfiguration.searchToolEnabled
            || nextConfiguration.graphSearchToolEnabled != resourceConfiguration.graphSearchToolEnabled
        
        document = nextDocument
        highLevelActivityDocument = nextHighLevelActivityDocument
        detailedActivityDocument = nextDetailedActivityDocument
        screenshotResources = nextScreenshotResources
        resourceConfiguration = nextConfiguration
        
        guard !sessions.isEmpty,
              !changedResourceURIs.isEmpty || didChangeResourceList || didChangeToolList else {
            return
        }

        let currentSessions = sessions

        if didChangeResourceList {
            for session in currentSessions.values {
                try? await session.server.notify(ResourceListChangedNotification.message())
            }
        }

        if didChangeToolList {
            for session in currentSessions.values {
                try? await session.server.notify(ToolListChangedNotification.message())
            }
        }
        
        for resourceURI in changedResourceURIs {
            let subscribedSessionIDs = subscriptions
                .filter { $0.value.contains(resourceURI) }
                .map(\.key)

            for sessionID in subscribedSessionIDs {
                guard let session = currentSessions[sessionID] else {
                    continue
                }

                try? await session.server.notify(ResourceUpdatedNotification.message(.init(uri: resourceURI)))
            }
        }
    }
    
    func resourceURIs() -> [String] {
        currentResources().map(\.uri)
    }

    func resourceTemplateURIs() -> [String] {
        currentResourceTemplates().map(\.uriTemplate)
    }

    func toolNames() -> [String] {
        currentTools().map(\.name)
    }

    func resourceContents(uri: String) -> [Resource.Content]? {
        if let screenshotResource = screenshotResources[uri],
           resourceConfiguration.detailedActivityResourceEnabled {
            return [.binary(screenshotResource.data, uri: uri, mimeType: screenshotResource.mimeType)]
        }

        let data: Data? = switch uri {
        case Vars.mcpOverviewResourceURI:
            try? encoder.encode(document)
        case Vars.mcpHighLevelActivityResourceURI:
            try? encoder.encode(highLevelActivityDocument)
        case Vars.mcpDetailedActivityResourceURI:
            try? encoder.encode(detailedActivityDocument)
        default:
            nil
        }

        guard let data,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        return [.text(text, uri: uri, mimeType: "application/json")]
    }

    func callSearchTool(query: String, limit: Int = 10) async throws -> SearchToolResultDocument {
        guard resourceConfiguration.searchToolEnabled else {
            throw MCPError.invalidParams("TaskTrace search is disabled.")
        }

        guard let searchService else {
            throw MCPError.internalError("TaskTrace search runtime is unavailable")
        }

        let submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLimit = max(1, min(limit, 50))
        let retrieval = try await searchService.retrieve(query: submittedQuery, limit: resolvedLimit)

        return SearchToolResultDocument(
            query: submittedQuery,
            limit: resolvedLimit,
            results: retrieval.results.enumerated().map { offset, result in
                RankedSearchResult(
                    rank: offset + 1,
                    score: result.score ?? 0,
                    result: result
                )
            }
        )
    }

    func callGraphRAGTool(
        query: String,
        limit: Int = Vars.graphRAGSummaryHitLimit
    ) async throws -> GraphRAGRetrievalResult {
        guard resourceConfiguration.graphSearchToolEnabled else {
            throw MCPError.invalidParams("TaskTrace graph retrieval is disabled.")
        }

        guard let graphRAGService else {
            throw MCPError.internalError("TaskTrace graph retrieval runtime is unavailable")
        }

        let submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLimit = max(1, min(limit, 10))

        return try await graphRAGService.retrieve(
            query: submittedQuery,
            directoryID: nil,
            topN: resolvedLimit
        )
    }
    
    private func makeServer(sessionID: UUID) async -> Server {
        let server = Server(
            name: Vars.mcpServerName,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
            title: Vars.mcpServerTitle,
            instructions: "Read the enabled TaskTrace resources to inspect active-day overviews, lagging summary-only activity recaps, and the eager detailed activity feed. The detailed feed exposes screenshot summaries, descriptions, OCR, and screenshot URIs instead of embedding image bytes. Use resources/read on those screenshot URIs to fetch the binary WebP image bytes. Use the tasktrace_search tool when you need ranked search results for a natural-language query without asking TaskTrace to summarize them. Use the tasktrace_graph_search tool when you need structured graph retrieval over the configured TaskTrace knowledge sources instead of activity history. Subscribe to any enabled resource URI to receive update notifications whenever that feed changes.",
            capabilities: .init(
                resources: .init(subscribe: true, listChanged: true),
                tools: .init(listChanged: true)
            )
        )
        
        await server.withMethodHandler(ListResources.self) { [weak self] _ in
            guard let self else {
                return .init(resources: [])
            }
            
            return .init(resources: await self.currentResources())
        }

        await server.withMethodHandler(ListResourceTemplates.self) { [weak self] _ in
            guard let self else {
                return .init(templates: [])
            }

            return .init(templates: await self.currentResourceTemplates())
        }
        
        await server.withMethodHandler(ReadResource.self) { [weak self] params in
            guard let self else {
                throw MCPError.internalError("Overview MCP runtime is unavailable")
            }
            
            guard await self.isResourceEnabled(uri: params.uri),
                  let contents = await self.resourceContents(uri: params.uri) else {
                throw MCPError.invalidParams("Unknown or disabled resource URI: \(params.uri)")
            }
            
            return .init(contents: contents)
        }
        
        await server.withMethodHandler(ResourceSubscribe.self) { [weak self] params in
            guard let self else {
                throw MCPError.internalError("Overview MCP runtime is unavailable")
            }
            
            guard await self.isResourceEnabled(uri: params.uri) else {
                throw MCPError.invalidParams("Unknown or disabled resource URI: \(params.uri)")
            }
            
            await self.subscribe(uri: params.uri, sessionID: sessionID)
            return Empty()
        }
        
        await server.withMethodHandler(ResourceUnsubscribe.self) { [weak self] params in
            guard let self else {
                throw MCPError.internalError("Overview MCP runtime is unavailable")
            }
            
            await self.unsubscribe(uri: params.uri, sessionID: sessionID)
            return Empty()
        }

        await server.withMethodHandler(ListTools.self) { [weak self] _ in
            guard let self else {
                return .init(tools: [])
            }

            return .init(tools: await self.currentTools())
        }

        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else {
                throw MCPError.internalError("Overview MCP runtime is unavailable")
            }

            switch params.name {
            case Vars.mcpSearchToolName:
                guard let query = params.arguments?["query"]?.stringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !query.isEmpty else {
                    throw MCPError.invalidParams("Search query is required.")
                }

                let response = try await self.callSearchTool(
                    query: query,
                    limit: params.arguments?["limit"]?.intValue ?? 10
                )
                guard let data = try? self.encoder.encode(response),
                      let text = String(data: data, encoding: .utf8) else {
                    throw MCPError.internalError("TaskTrace search results could not be encoded.")
                }

                return .init(
                    content: [.text(text: text, annotations: nil, _meta: nil)],
                    isError: false
                )
            case Vars.mcpGraphRAGToolName:
                guard let query = params.arguments?["query"]?.stringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !query.isEmpty else {
                    throw MCPError.invalidParams("Graph search query is required.")
                }

                let response = try await self.callGraphRAGTool(
                    query: query,
                    limit: params.arguments?["limit"]?.intValue ?? 3
                )
                guard let data = try? self.encoder.encode(response),
                      let text = String(data: data, encoding: .utf8) else {
                    throw MCPError.internalError("TaskTrace graph retrieval results could not be encoded.")
                }

                return .init(
                    content: [.text(text: text, annotations: nil, _meta: nil)],
                    isError: false
                )
            default:
                throw MCPError.invalidParams("Unknown tool: \(params.name)")
            }
        }
        
        return server
    }
    
    private func subscribe(uri: String, sessionID: UUID) {
        subscriptions[sessionID, default: []].insert(uri)
    }
    
    private func unsubscribe(uri: String, sessionID: UUID) {
        subscriptions[sessionID]?.remove(uri)
    }
    
    private func currentResources() -> [Resource] {
        [
            resourceConfiguration.overviewResourceEnabled
            ? Resource(
                name: "TaskTrace Active Day Overviews",
                uri: Vars.mcpOverviewResourceURI,
                title: "TaskTrace Active Day Overviews",
                description: "Best starting point for questions about today or the current workday, such as 'what did I do today?', 'what have I been working on?', or 'summarize today's work'. Returns today's work grouped into broader tasks/projects with titles, summaries, and durations. For questions about arbitrary past work outside the current day, prefer tasktrace_search.",
                mimeType: "application/json"
            )
            : nil,
            resourceConfiguration.highLevelActivityResourceEnabled
            ? Resource(
                name: "TaskTrace High Level Activities",
                uri: Vars.mcpHighLevelActivityResourceURI,
                title: "TaskTrace High Level Activities",
                description: "Use for a chronological recap of recent completed work from today/current context, such as 'what did I work on this afternoon?', 'what was I doing before this?', or 'list my recent tasks'. Returns recent completed activities with concise summaries only. This feed lags behind capture because activities appear here after summarization finishes. For general historical lookup or questions about older work, prefer tasktrace_search.",
                mimeType: "application/json"
            )
            : nil,
            resourceConfiguration.detailedActivityResourceEnabled
            ? Resource(
                name: "TaskTrace Detailed Activities",
                uri: Vars.mcpDetailedActivityResourceURI,
                title: "TaskTrace Detailed Activities",
                description: "Use when the agent needs exact current or very recent evidence instead of a summary, such as 'what am I doing right now?', 'what did I type?', 'what did the meeting say?', or 'what was on screen?'. Returns the eager recent-activity feed for today/current context, including incomplete activities, keystrokes, transcript text, summary when available, and screenshot metadata such as description and OCR. Screenshot bytes are fetched separately by reading the screenshot URIs referenced in this feed. For older historical investigation, prefer tasktrace_search.",
                mimeType: "application/json"
            )
            : nil
        ]
            .compactMap { $0 }
    }

    private func currentResourceTemplates() -> [Resource.Template] {
        resourceConfiguration.detailedActivityResourceEnabled
        ? [
            Resource.Template(
                uriTemplate: Vars.mcpActivityScreenshotResourceTemplateURI,
                name: "TaskTrace Activity Screenshot",
                title: "TaskTrace Activity Screenshot",
                description: "Use after reading the detailed activity feed when you need the actual screenshot image for a referenced current/recent moment, such as checking what code, UI, document, or error was visible on screen. Returns binary WebP bytes for screenshot URIs exposed by the detailed activity feed.",
                mimeType: Vars.mcpScreenshotMimeType
            )
        ]
        : []
    }

    private func currentTools() -> [Tool] {
        return [
            resourceConfiguration.searchToolEnabled ? searchService.map { _ in
                Tool(
                    name: Vars.mcpSearchToolName,
                    description: "Preferred tool for natural-language lookup across TaskTrace history, especially for arbitrary past work or broader historical questions such as 'when was I editing the landing page?', 'find work about OAuth', or 'what have I done related to billing over the last month?'. Use this instead of today's resources when the user is asking about general history rather than current/today context. Returns ranked matches across overviews, activities, and screenshots without generating a summary.",
                    inputSchema: .object([
                        "type": "object",
                        "properties": [
                            "query": [
                                "type": "string",
                                "description": "Natural-language question or topic to retrieve from TaskTrace history, especially for arbitrary past or broad historical lookup, such as 'find work about invoices', 'when was I working in Xcode on search?', or 'what have I done for client X this month?'."
                            ],
                            "limit": [
                                "type": "number",
                                "description": "Maximum number of ranked overview result trees to return. Increase for broader historical questions that may span many moments or days. Defaults to 10 and is clamped to 50."
                            ]
                        ],
                        "required": ["query"],
                        "additionalProperties": false
                    ])
                )
            } : nil,
            resourceConfiguration.graphSearchToolEnabled ? graphRAGService.map { _ in
                Tool(
                    name: Vars.mcpGraphRAGToolName,
                    description: "Use for structured graph search when you want communities, knowledge nodes, claims, and their internal graph context for the knowledge directory currently selected in TaskTrace instead of activity history. Runs hybrid vector plus FTS retrieval, reranks the matched graph entities, keeps the strongest hits, and returns the surrounding communities, nodes, edges, and claims without generating a summary.",
                    inputSchema: .object([
                        "type": "object",
                        "properties": [
                            "query": [
                                "type": "string",
                                "description": "Natural-language question or graph lookup query, such as 'what communities relate to billing retries?', 'find claims about OAuth token refresh', or 'what does the graph know about PDF parsing?'."
                            ],
                            "limit": [
                                "type": "number",
                                "description": "Maximum number of reranked graph hits to keep. Defaults to 3 and is clamped to 10."
                            ]
                        ],
                        "required": ["query"],
                        "additionalProperties": false
                    ])
                )
            } : nil
        ]
        .compactMap { $0 }
    }
    
    private func isResourceEnabled(uri: String) -> Bool {
        switch uri {
        case Vars.mcpOverviewResourceURI:
            resourceConfiguration.overviewResourceEnabled
        case Vars.mcpHighLevelActivityResourceURI:
            resourceConfiguration.highLevelActivityResourceEnabled
        case Vars.mcpDetailedActivityResourceURI:
            resourceConfiguration.detailedActivityResourceEnabled
        default:
            resourceConfiguration.detailedActivityResourceEnabled && screenshotResources[uri] != nil
        }
    }
}
