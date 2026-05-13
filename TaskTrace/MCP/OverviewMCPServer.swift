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
        goalsDatabaseActor: GoalsDatabaseActor,
        actorSystem: ActorSystem,
        searchService: TaskTraceSearchService,
        graphRAGService: GraphRAGService
    ) {
        self.overviewStore = overviewStore
        self.activityStore = activityStore
        self.knowledgeGraphStore = knowledgeGraphStore
        self.settingsStore = settingsStore
        self.runtime = OverviewMCPServerRuntime(
            goalsDatabaseActor: goalsDatabaseActor,
            actorSystem: actorSystem,
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
        let todayTodosResourceEnabled: Bool
        let searchToolEnabled: Bool
        let graphSearchToolEnabled: Bool
        let addTodoToolEnabled: Bool
        let addGoalToolEnabled: Bool
        let pushMessageToolEnabled: Bool
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

    private struct TodayTodosDocument: Codable, Equatable, Sendable {
        let date: String
        let todos: [TodayTodoSnapshot]
    }

    private struct TodayTodoSnapshot: Codable, Equatable, Sendable {
        let id: Int64
        let name: String
        let status: String
        let createTime: String
        let statusTime: String?
        let repeating: Bool
        let targetDate: String?
        let dailyTargetSeconds: Int?
        let dailyTargetMode: String
        let durationSeconds: Int
        let goal: TodayTodoGoalSnapshot?
    }

    private struct TodayTodoGoalSnapshot: Codable, Equatable, Sendable {
        let id: Int64
        let name: String
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

    struct AddGoalToolResultDocument: Codable, Equatable, Sendable {
        let goal: AddedGoalSnapshot
    }

    struct AddedGoalSnapshot: Codable, Equatable, Sendable {
        let id: Int64
        let name: String
        let description: String?
        let createTime: String
    }

    struct AddTodoToolResultDocument: Codable, Equatable, Sendable {
        let todo: AddedTodoSnapshot
    }

    struct AddedTodoSnapshot: Codable, Equatable, Sendable {
        let id: Int64
        let name: String
        let status: String
        let createTime: String
        let repeating: Bool
        let targetDate: String?
        let dailyTargetSeconds: Int?
        let dailyTargetMode: String
        let goalID: Int64?
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
    private var todayTodosDocument = TodayTodosDocument(date: "", todos: [])
    private var screenshotResources: [String: ScreenshotResourceSnapshot] = [:]
    private var activeDay = Date()
    private var resourceConfiguration = ResourceConfiguration(
        overviewResourceEnabled: true,
        highLevelActivityResourceEnabled: true,
        detailedActivityResourceEnabled: false,
        todayTodosResourceEnabled: true,
        searchToolEnabled: true,
        graphSearchToolEnabled: true,
        addTodoToolEnabled: true,
        addGoalToolEnabled: true,
        pushMessageToolEnabled: true,
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
    private let goalsDatabaseActor: GoalsDatabaseActor?
    private let actorSystem: ActorSystem?
    private let identifierActor: IdentifierActor
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let searchService: TaskTraceSearchService?
    private let graphRAGService: GraphRAGService?
    private let pushNotificationManager: TaskTracePushNotificationManager
    
    init(
        goalsDatabaseActor: GoalsDatabaseActor? = nil,
        actorSystem: ActorSystem? = nil,
        identifierActor: IdentifierActor = .shared,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .gregorian),
        searchService: TaskTraceSearchService? = nil,
        graphRAGService: GraphRAGService? = nil,
        pushNotificationManager: TaskTracePushNotificationManager = TaskTracePushNotificationManager(),
        socketPath: String = Vars.mcpBrokerSocketPath
    ) {
        self.goalsDatabaseActor = goalsDatabaseActor
        self.actorSystem = actorSystem
        self.identifierActor = identifierActor
        self.now = now
        self.calendar = calendar
        self.searchService = searchService
        self.graphRAGService = graphRAGService
        self.pushNotificationManager = pushNotificationManager
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
            todayTodosResourceEnabled: configuration.todayTodosResourceEnabled,
            searchToolEnabled: configuration.searchToolEnabled,
            graphSearchToolEnabled: configuration.graphSearchToolEnabled,
            addTodoToolEnabled: configuration.addTodoToolEnabled,
            addGoalToolEnabled: configuration.addGoalToolEnabled,
            pushMessageToolEnabled: configuration.pushMessageToolEnabled,
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
        let nextTodayTodosDocument = await loadTodayTodosDocument(activeDay: activeDay)
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
                nextTodayTodosDocument != todayTodosDocument ? Vars.mcpTodayTodosResourceURI : nil,
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
            || nextConfiguration.todayTodosResourceEnabled != resourceConfiguration.todayTodosResourceEnabled
            || nextConfiguration.highLevelActivityCount != resourceConfiguration.highLevelActivityCount
            || nextConfiguration.detailedActivityCount != resourceConfiguration.detailedActivityCount
        let didChangeToolList =
            nextConfiguration.searchToolEnabled != resourceConfiguration.searchToolEnabled
            || nextConfiguration.graphSearchToolEnabled != resourceConfiguration.graphSearchToolEnabled
            || nextConfiguration.addTodoToolEnabled != resourceConfiguration.addTodoToolEnabled
            || nextConfiguration.addGoalToolEnabled != resourceConfiguration.addGoalToolEnabled
            || nextConfiguration.pushMessageToolEnabled != resourceConfiguration.pushMessageToolEnabled
        
        self.activeDay = activeDay
        document = nextDocument
        highLevelActivityDocument = nextHighLevelActivityDocument
        detailedActivityDocument = nextDetailedActivityDocument
        todayTodosDocument = nextTodayTodosDocument
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

    func resourceContents(uri: String) async -> [Resource.Content]? {
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
        case Vars.mcpTodayTodosResourceURI:
            try? encoder.encode(await loadTodayTodosDocument(activeDay: activeDay))
        default:
            nil
        }

        guard let data,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        return [.text(text, uri: uri, mimeType: "application/json")]
    }

    private func loadTodayTodosDocument(activeDay: Date) async -> TodayTodosDocument {
        guard let goalsDatabaseActor else {
            return TodayTodosDocument(date: dateFormatter.string(from: activeDay), todos: [])
        }

        guard let snapshot = try? await goalsDatabaseActor.loadSnapshot(
            visibleStart: activeDay,
            visibleEnd: activeDay,
            selectedDay: activeDay
        ) else {
            return TodayTodosDocument(date: dateFormatter.string(from: activeDay), todos: [])
        }

        let goalsByID = Dictionary(uniqueKeysWithValues: snapshot.goals.map { ($0.id, $0) })
        let durationsByTodoID = Dictionary(uniqueKeysWithValues: snapshot.todoRollups.map { ($0.todoID, $0.duration) })

        return TodayTodosDocument(
            date: dateFormatter.string(from: activeDay),
            todos: snapshot.todos.map { todo in
                let goal = todo.goalID.flatMap { goalsByID[$0] }

                return TodayTodoSnapshot(
                    id: todo.id,
                    name: todo.name,
                    status: todo.status.rawValue,
                    createTime: todo.createTs.ISO8601Format(),
                    statusTime: todo.statusTs?.ISO8601Format(),
                    repeating: todo.repeating,
                    targetDate: todo.targetDate.map { dateFormatter.string(from: $0) },
                    dailyTargetSeconds: todo.dailyTargetSeconds,
                    dailyTargetMode: todo.dailyTargetMode.rawValue,
                    durationSeconds: durationsByTodoID[todo.id] ?? 0,
                    goal: goal.map { TodayTodoGoalSnapshot(id: $0.id, name: $0.name) }
                )
            }
        )
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

    func callAddGoalTool(
        name: String,
        description: String? = nil
    ) async throws -> AddGoalToolResultDocument {
        guard resourceConfiguration.addGoalToolEnabled else {
            throw MCPError.invalidParams("TaskTrace add goal is disabled.")
        }

        guard let goalsDatabaseActor else {
            throw MCPError.internalError("TaskTrace goals runtime is unavailable")
        }

        let submittedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedName.isEmpty else {
            throw MCPError.invalidParams("Goal name is required.")
        }

        let submittedDescription = description?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let createTime = now()
        let goal = GoalInput(
            id: await identifierActor.makeIdentifier(),
            name: submittedName,
            description: submittedDescription?.isEmpty == false ? submittedDescription : nil,
            createTs: createTime,
            doneTs: nil
        )

        try await goalsDatabaseActor.saveGoal(goal)
        todayTodosDocument = await loadTodayTodosDocument(activeDay: activeDay)
        await actorSystem?.broadcast(from: nil, message: GoalsReloadRequested())
        await notifyResourceUpdated(Vars.mcpTodayTodosResourceURI)

        return AddGoalToolResultDocument(
            goal: AddedGoalSnapshot(
                id: goal.id,
                name: goal.name,
                description: goal.description,
                createTime: createTime.ISO8601Format()
            )
        )
    }

    func callAddTodoTool(
        name: String,
        goalID: Int64? = nil,
        repeating: Bool = false,
        targetDate: String? = nil,
        dailyTargetMinutes: Int? = nil,
        dailyTargetMode: String? = nil
    ) async throws -> AddTodoToolResultDocument {
        guard resourceConfiguration.addTodoToolEnabled else {
            throw MCPError.invalidParams("TaskTrace add todo is disabled.")
        }

        guard let goalsDatabaseActor else {
            throw MCPError.internalError("TaskTrace goals runtime is unavailable")
        }

        let submittedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedName.isEmpty else {
            throw MCPError.invalidParams("Todo name is required.")
        }

        let resolvedTargetDate = try {
            guard let targetDate else {
                return calendar.startOfDay(for: activeDay)
            }

            guard let date = dateFormatter.date(from: targetDate.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw MCPError.invalidParams("Todo target_date must use YYYY-MM-DD.")
            }

            return calendar.startOfDay(for: date)
        }()
        let resolvedTargetMode = try {
            guard let dailyTargetMode else {
                return GoalTodoTargetMode.minimum
            }

            guard let targetMode = GoalTodoTargetMode(rawValue: dailyTargetMode.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw MCPError.invalidParams("Todo daily_target_mode must be minimum or maximum.")
            }

            return targetMode
        }()
        let dailyTargetSeconds = dailyTargetMinutes.map { max($0, 1) * 60 }
        let createTime = now()
        let todo = GoalTodoInput(
            id: await identifierActor.makeIdentifier(),
            goalID: goalID,
            name: submittedName,
            createTs: createTime,
            status: .open,
            statusTs: nil,
            repeating: repeating,
            targetDate: resolvedTargetDate,
            dailyTargetSeconds: dailyTargetSeconds,
            dailyTargetMode: dailyTargetSeconds == nil ? .minimum : resolvedTargetMode
        )

        try await goalsDatabaseActor.saveTodo(todo)
        todayTodosDocument = await loadTodayTodosDocument(activeDay: activeDay)
        await actorSystem?.broadcast(from: nil, message: GoalsReloadRequested())
        await notifyResourceUpdated(Vars.mcpTodayTodosResourceURI)

        return AddTodoToolResultDocument(
            todo: AddedTodoSnapshot(
                id: todo.id,
                name: todo.name,
                status: todo.status.rawValue,
                createTime: createTime.ISO8601Format(),
                repeating: todo.repeating,
                targetDate: todo.targetDate.map { dateFormatter.string(from: $0) },
                dailyTargetSeconds: todo.dailyTargetSeconds,
                dailyTargetMode: todo.dailyTargetMode.rawValue,
                goalID: todo.goalID
            )
        )
    }

    func callPushMessageTool(
        message: String,
        title: String? = nil,
        source: String? = nil
    ) async throws -> TaskTracePushNotificationResult {
        guard resourceConfiguration.pushMessageToolEnabled else {
            throw MCPError.invalidParams("TaskTrace push message is disabled.")
        }

        let submittedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedMessage.isEmpty else {
            throw MCPError.invalidParams("Push message is required.")
        }

        return try await pushNotificationManager.push(
            title: title,
            message: submittedMessage,
            source: source
        )
    }
    
    private func makeServer(sessionID: UUID) async -> Server {
        let server = Server(
            name: Vars.mcpServerName,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
            title: Vars.mcpServerTitle,
            instructions: "Read the enabled TaskTrace resources to inspect active-day overviews, today's todos, lagging summary-only activity recaps, and the eager detailed activity feed. The todos feed is the best source for today's planned work and current todo status. The detailed feed exposes screenshot summaries, descriptions, OCR, and screenshot URIs instead of embedding image bytes. Use resources/read on those screenshot URIs to fetch the binary WebP image bytes. Use tasktrace_add_todo when the user asks you to create a todo, tasktrace_add_goal when the user asks you to create a goal, and tasktrace_push_message when the user or agent needs TaskTrace to show a macOS notification. Use the tasktrace_search tool when you need ranked search results for a natural-language query without asking TaskTrace to summarize them. Use the tasktrace_graph_search tool when you need structured graph retrieval over the configured TaskTrace knowledge sources instead of activity history. Subscribe to any enabled resource URI to receive update notifications whenever that feed changes.",
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
            case Vars.mcpAddTodoToolName:
                guard let name = params.arguments?["name"]?.stringValue else {
                    throw MCPError.invalidParams("Todo name is required.")
                }

                let response = try await self.callAddTodoTool(
                    name: name,
                    goalID: params.arguments?["goal_id"]?.intValue.map(Int64.init),
                    repeating: params.arguments?["repeating"]?.boolValue ?? false,
                    targetDate: params.arguments?["target_date"]?.stringValue,
                    dailyTargetMinutes: params.arguments?["daily_target_minutes"]?.intValue,
                    dailyTargetMode: params.arguments?["daily_target_mode"]?.stringValue
                )
                guard let data = try? self.encoder.encode(response),
                      let text = String(data: data, encoding: .utf8) else {
                    throw MCPError.internalError("TaskTrace add todo result could not be encoded.")
                }

                return .init(
                    content: [.text(text: text, annotations: nil, _meta: nil)],
                    isError: false
                )
            case Vars.mcpAddGoalToolName:
                guard let name = params.arguments?["name"]?.stringValue else {
                    throw MCPError.invalidParams("Goal name is required.")
                }

                let response = try await self.callAddGoalTool(
                    name: name,
                    description: params.arguments?["description"]?.stringValue
                )
                guard let data = try? self.encoder.encode(response),
                      let text = String(data: data, encoding: .utf8) else {
                    throw MCPError.internalError("TaskTrace add goal result could not be encoded.")
                }

                return .init(
                    content: [.text(text: text, annotations: nil, _meta: nil)],
                    isError: false
                )
            case Vars.mcpPushMessageToolName:
                guard let message = params.arguments?["message"]?.stringValue else {
                    throw MCPError.invalidParams("Push message is required.")
                }

                let response = try await self.callPushMessageTool(
                    message: message,
                    title: params.arguments?["title"]?.stringValue,
                    source: params.arguments?["source"]?.stringValue
                )
                guard let data = try? self.encoder.encode(response),
                      let text = String(data: data, encoding: .utf8) else {
                    throw MCPError.internalError("TaskTrace push message result could not be encoded.")
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

    private func notifyResourceUpdated(_ resourceURI: String) async {
        let subscribedSessionIDs = subscriptions
            .filter { $0.value.contains(resourceURI) }
            .map(\.key)

        for sessionID in subscribedSessionIDs {
            guard let session = sessions[sessionID] else {
                continue
            }

            try? await session.server.notify(ResourceUpdatedNotification.message(.init(uri: resourceURI)))
        }
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
            : nil,
            resourceConfiguration.todayTodosResourceEnabled
            ? Resource(
                name: "TaskTrace Today Todos",
                uri: Vars.mcpTodayTodosResourceURI,
                title: "TaskTrace Today Todos",
                description: "Use for questions about what the user needs to do today, which todos are open, done, failed, repeating, attached to goals, or have daily time targets. Returns the current day's visible todos with status, target date, goal linkage, daily target settings, and tracked duration. If the user wants to create new work items, use tasktrace_add_todo or tasktrace_add_goal instead of only reading this resource.",
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
            } : nil,
            resourceConfiguration.addTodoToolEnabled && goalsDatabaseActor != nil ? Tool(
                name: Vars.mcpAddTodoToolName,
                description: "Use only when the user asks you to create, add, or remember a concrete todo/task in TaskTrace. Creates an open todo for today's plan by default. Attach it to an existing goal with goal_id when the user specifies the goal or when you have just read today's todos and know the correct goal id. Use repeating for tasks that should be recreated on future days. Use daily_target_minutes and daily_target_mode for time-based minimum or maximum targets.",
                inputSchema: .object([
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "Short todo text to show in TaskTrace, such as 'Call the accountant' or 'Draft billing email'."
                        ],
                        "goal_id": [
                            "type": "number",
                            "description": "Optional existing TaskTrace goal id to attach this todo to. Omit for a standalone todo."
                        ],
                        "repeating": [
                            "type": "boolean",
                            "description": "Set true only when this todo should be recreated on future days. Defaults to false."
                        ],
                        "target_date": [
                            "type": "string",
                            "description": "Optional YYYY-MM-DD date for when the todo should appear. Defaults to today."
                        ],
                        "daily_target_minutes": [
                            "type": "number",
                            "description": "Optional daily time target in minutes. Omit when the todo has no time target."
                        ],
                        "daily_target_mode": [
                            "type": "string",
                            "enum": ["minimum", "maximum"],
                            "description": "Use minimum for tasks the user wants to spend at least this much time on, or maximum for things the user wants to limit."
                        ]
                    ],
                    "required": ["name"],
                    "additionalProperties": false
                ])
            ) : nil,
            resourceConfiguration.addGoalToolEnabled && goalsDatabaseActor != nil ? Tool(
                name: Vars.mcpAddGoalToolName,
                description: "Use only when the user asks you to create, add, or remember a broader TaskTrace goal. Goals group todos and represent ongoing objectives, projects, or habits. For a single concrete action, prefer tasktrace_add_todo.",
                inputSchema: .object([
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "Goal name to show in TaskTrace, such as 'Finish taxes' or 'Improve sleep routine'."
                        ],
                        "description": [
                            "type": "string",
                            "description": "Optional context, constraints, or success criteria for the goal."
                        ]
                    ],
                    "required": ["name"],
                    "additionalProperties": false
                ])
            ) : nil,
            resourceConfiguration.pushMessageToolEnabled ? Tool(
                name: Vars.mcpPushMessageToolName,
                description: "Use when an agent needs TaskTrace to immediately show the user a macOS notification. This is a direct push notification only; it does not create todos, goals, or persistent messages.",
                inputSchema: .object([
                    "type": "object",
                    "properties": [
                        "message": [
                            "type": "string",
                            "description": "Notification body to show to the user. Keep it concise and actionable."
                        ],
                        "title": [
                            "type": "string",
                            "description": "Optional notification title. Defaults to TaskTrace."
                        ],
                        "source": [
                            "type": "string",
                            "description": "Optional short source label, such as OpenClaw or the agent name."
                        ]
                    ],
                    "required": ["message"],
                    "additionalProperties": false
                ])
            ) : nil
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
        case Vars.mcpTodayTodosResourceURI:
            resourceConfiguration.todayTodosResourceEnabled
        default:
            resourceConfiguration.detailedActivityResourceEnabled && screenshotResources[uri] != nil
        }
    }
}
