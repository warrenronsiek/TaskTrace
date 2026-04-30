//
//  App.swift
//  TaskTrace
//
//  Created by Warren Ronsiek on 3/11/26.
//

import AppKit
import Combine
import Darwin
import OSLog
import Sparkle
import SwiftUI
import UserNotifications

@MainActor
final class TaskTraceApplicationShutdownBridge {
    static let shared = TaskTraceApplicationShutdownBridge()

    // SwiftUI owns the shutdown dependencies, but AppKit asks an NSApplicationDelegate
    // whether termination may proceed.
    var controller: TaskTraceApplicationShutdownController?
}

@MainActor
final class TaskTraceApplicationShutdownState: ObservableObject {
    @Published private(set) var isShuttingDown = false
    @Published private(set) var showsOverlay = false

    func begin(showOverlay: Bool) {
        isShuttingDown = true
        showsOverlay = showOverlay
    }
}

@MainActor
final class TaskTraceApplicationShutdownController {
    private let shutdown: @MainActor @Sendable () async -> Void
    private let replyToApplicationShouldTerminate: @MainActor @Sendable (Bool) -> Void
    private let shutdownState: TaskTraceApplicationShutdownState
    private let shouldShowOverlay: @MainActor @Sendable () -> Bool
    private var hasPreparedForTermination = false

    init(
        shutdown: @escaping @MainActor @Sendable () async -> Void,
        shutdownState: TaskTraceApplicationShutdownState? = nil,
        shouldShowOverlay: @escaping @MainActor @Sendable () -> Bool = {
            NSApplication.shared.windows.contains {
                $0.canBecomeMain && $0.isVisible
            }
        },
        replyToApplicationShouldTerminate: @escaping @MainActor @Sendable (Bool) -> Void = { shouldTerminate in
            NSApplication.shared.reply(toApplicationShouldTerminate: shouldTerminate)
        }
    ) {
        self.shutdown = shutdown
        self.shutdownState = shutdownState ?? TaskTraceApplicationShutdownState()
        self.shouldShowOverlay = shouldShowOverlay
        self.replyToApplicationShouldTerminate = replyToApplicationShouldTerminate
    }

    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        guard !hasPreparedForTermination else {
            return .terminateLater
        }

        hasPreparedForTermination = true
        shutdownState.begin(showOverlay: shouldShowOverlay())
        Task { @MainActor in
            await shutdown()
            replyToApplicationShouldTerminate(true)
        }
        return .terminateLater
    }
}

struct TaskTraceSiblingProcess: Equatable, Sendable {
    let processIdentifier: Int32
    let bundleURL: URL?
}

protocol TaskTraceSiblingProcessListing {
    nonisolated func runningSiblingCandidates(bundleIdentifier: String) -> [TaskTraceSiblingProcess]
}

struct TaskTraceNSRunningApplicationSiblingProcessListing: TaskTraceSiblingProcessListing {
    nonisolated init() {}

    nonisolated func runningSiblingCandidates(bundleIdentifier: String) -> [TaskTraceSiblingProcess] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).map {
            TaskTraceSiblingProcess(
                processIdentifier: Int32($0.processIdentifier),
                bundleURL: $0.bundleURL
            )
        }
    }
}

protocol TaskTraceProcessKilling {
    nonisolated func forceKill(processIdentifier: Int32)
}

struct TaskTraceDarwinProcessKilling: TaskTraceProcessKilling {
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "shutdown")

    nonisolated init() {}

    nonisolated func forceKill(processIdentifier: Int32) {
        if Darwin.kill(processIdentifier, SIGKILL) == 0 || errno == ESRCH {
            return
        }

        logger.error(
            "force kill failed pid=\(processIdentifier, privacy: .public) errno=\(errno, privacy: .public)"
        )
    }
}

@MainActor
final class TaskTraceSiblingProcessController {
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "shutdown")
    private let bundleIdentifier: String?
    private let bundleURL: URL?
    private let currentProcessIdentifier: Int32
    private let processListing: any TaskTraceSiblingProcessListing
    private let processKilling: any TaskTraceProcessKilling
    private let pollIntervalNanoseconds: UInt64
    private let maxPollingPasses: Int
    private let sleep: @Sendable (UInt64) async -> Void
    private let protectedProcessIdentifiers: @MainActor @Sendable () -> Set<Int32>

    init(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        bundleURL: URL? = Bundle.main.bundleURL,
        currentProcessIdentifier: Int32 = Int32(ProcessInfo.processInfo.processIdentifier),
        processListing: (any TaskTraceSiblingProcessListing)? = nil,
        processKilling: (any TaskTraceProcessKilling)? = nil,
        pollIntervalNanoseconds: UInt64 = 50_000_000,
        maxPollingPasses: Int = 20,
        protectedProcessIdentifiers: @escaping @MainActor @Sendable () -> Set<Int32> = { [] },
        sleep: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.currentProcessIdentifier = currentProcessIdentifier
        self.processListing = processListing ?? TaskTraceNSRunningApplicationSiblingProcessListing()
        self.processKilling = processKilling ?? TaskTraceDarwinProcessKilling()
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.maxPollingPasses = maxPollingPasses
        self.protectedProcessIdentifiers = protectedProcessIdentifiers
        self.sleep = sleep
    }

    func forceKillSiblingProcessesImmediately() {
        siblingProcesses().forEach {
            processKilling.forceKill(processIdentifier: $0.processIdentifier)
        }
    }

    func forceKillSiblingProcesses() async {
        for pass in 0..<maxPollingPasses {
            let siblings = siblingProcesses()

            guard !siblings.isEmpty else {
                return
            }

            siblings.forEach {
                processKilling.forceKill(processIdentifier: $0.processIdentifier)
            }

            if pass + 1 < maxPollingPasses {
                await sleep(pollIntervalNanoseconds)
            }
        }

        let remainingSiblingProcessIdentifiers = siblingProcesses().map(\.processIdentifier)

        if !remainingSiblingProcessIdentifiers.isEmpty {
            logger.error(
                "sibling process cleanup timed out remainingPIDs=\(remainingSiblingProcessIdentifiers, privacy: .public)"
            )
        }
    }

    private func siblingProcesses() -> [TaskTraceSiblingProcess] {
        guard let bundleIdentifier else {
            return []
        }

        let protectedProcessIdentifiers = protectedProcessIdentifiers()

        return processListing
            .runningSiblingCandidates(bundleIdentifier: bundleIdentifier)
            .filter {
                $0.processIdentifier != currentProcessIdentifier
                && !protectedProcessIdentifiers.contains($0.processIdentifier)
                && (
                    bundleURL == nil
                    || $0.bundleURL == nil
                    || $0.bundleURL?.path == bundleURL?.path
                )
            }
    }
}

@MainActor
final class TaskTraceApplicationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var notificationRouter: TaskTraceNotificationRouter?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        TaskTraceApplicationShutdownBridge.shared.controller?.applicationShouldTerminate() ?? .terminateNow
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            notificationRouter?.handleNotificationResponse(
                userInfo: response.notification.request.content.userInfo
            )
        }
    }
}

@MainActor
struct TaskTraceApp: App {
    @NSApplicationDelegateAdaptor(TaskTraceApplicationDelegate.self) private var applicationDelegate

    let navigationStore: TaskTraceNavigationStore?
    let settingsStore: SettingsStore?
    let appUpdater: AppUpdater?
    let database: TaskTraceDatabase?
    let activityActor: ActivityActor?
    let overviewActor: OverviewActor?
    let activityStore: ActivityStore?
    let overviewStore: OverviewStore?
    let searchService: TaskTraceSearchService?
    let searchStore: SearchStore?
    let skillsStore: SkillsStore?
    let knowledgeGraphActor: KnowledgeGraphActor?
    let knowledgeGraphStore: KnowledgeGraphStore?
    let aiStatsStore: AIStatsStore?
    let calendarStore: CalendarStore?
    let tagsStore: TagsStore?
    let analyticsStore: AnalyticsStore?
    let agentActionActor: AgentActionActor?
    let agentChannelActor: AgentChannelActor?
    let agentActionsStore: AgentActionsStore?
    let jobsActor: JobsActor?
    let captureMonitor: TaskTraceCaptureMonitor?
    let overviewMCPServerController: OverviewMCPServerController?
    let browserPluginSocketController: BrowserPluginSocketController?
    let applicationShutdownController: TaskTraceApplicationShutdownController?
    let applicationShutdownState: TaskTraceApplicationShutdownState
    let statusItemController: TaskTraceStatusItemController?
    let microphoneCaptureObserver: AnyCancellable?
    let mcpStdioProxyController: TaskTraceMCPStdioProxyController?

    init() {
        let isUITesting = Self.isRunningUITests()
        let isRunningTests = Self.isRunningTests()
        let isRunningMCPStdioMode = Self.isRunningMCPStdioMode()
        let applicationShutdownState = TaskTraceApplicationShutdownState()

        if isRunningMCPStdioMode {
            NSApplication.shared.setActivationPolicy(.prohibited)
            let mcpStdioProxyController = TaskTraceMCPStdioProxyController()
            mcpStdioProxyController.start()

            self.navigationStore = nil
            self.settingsStore = nil
            self.appUpdater = nil
            self.database = nil
            self.activityActor = nil
            self.overviewActor = nil
            self.activityStore = nil
            self.overviewStore = nil
            self.searchService = nil
            self.searchStore = nil
            self.skillsStore = nil
            self.knowledgeGraphActor = nil
            self.knowledgeGraphStore = nil
            self.aiStatsStore = nil
            self.calendarStore = nil
            self.tagsStore = nil
            self.analyticsStore = nil
            self.agentActionActor = nil
            self.agentChannelActor = nil
            self.agentActionsStore = nil
            self.jobsActor = nil
            self.captureMonitor = nil
            self.overviewMCPServerController = nil
            self.browserPluginSocketController = nil
            self.applicationShutdownController = nil
            self.applicationShutdownState = applicationShutdownState
            self.statusItemController = nil
            self.microphoneCaptureObserver = nil
            self.mcpStdioProxyController = mcpStdioProxyController
            return
        }

        let actorSystem = ActorSystem()
        let rerankingActor = ActivityRerankingActor()
        let textGenerationActor = ActivityTextGenerationActor()
        let database: TaskTraceDatabase
        let knowledgeReadDatabase: KnowledgeReadDatabase
        
        do {
            let databaseURL = try TaskTraceDatabaseBootstrap.migrate(databaseURL: Self.databaseURLForLaunch())
            database = try TaskTraceDatabase(databaseURL: databaseURL)
            knowledgeReadDatabase = KnowledgeReadDatabase(database: database)
        } catch {
            fatalError("Could not create database: \(error)")
        }

        let settingsDatabaseActor = SettingsDatabaseActor(database: database)
        let tagsDatabaseActor = TagsDatabaseActor(database: database)
        let searchDatabaseActor = SearchDatabaseActor(database: database)
        let analyticsDatabaseActor = AnalyticsDatabaseActor(database: database)
        let calendarDatabaseActor = CalendarDatabaseActor(database: database)
        let agentActionsDatabaseActor = AgentActionsDatabaseActor(database: database)
        let jobsDatabaseActor = JobsDatabaseActor(database: database)
        let appUpdater = AppUpdater()
        let settingsStore = SettingsStore(
            settingsDatabaseActor: settingsDatabaseActor,
            permissionManager: TaskTracePermissionManager()
        )
        let activityDatabaseActor = ActivityDatabaseActor(database: database)
        let overviewDatabaseActor = OverviewDatabaseActor(database: database)
        let knowledgeDatabaseActor = KnowledgeDatabaseActor(database: database, actorSystem: actorSystem)
        let activityEmbeddingActor = ActivityEmbeddingActor(actorSystem: actorSystem)
        let activityUMAPActor = ActivityUMAPActor(
            actorSystem: actorSystem,
            activityDatabaseActor: activityDatabaseActor
        )
        let activityTagOntologyActor = ActivityTagOntologyActor(
            actorSystem: actorSystem,
            activityDatabaseActor: activityDatabaseActor
        )
        let describeImageActor = DescribeImageActor(actorSystem: actorSystem)
        let readScreenshotTextActor = ReadScreenshotTextActor(actorSystem: actorSystem)
        let summarizeScreenshotActor = SummarizeScreenshotActor(actorSystem: actorSystem)
        let summarizeActivityActor = SummarizeActivityActor(actorSystem: actorSystem)
        let ontologyOverviewActor = OntologyOverviewActor(
            actorSystem: actorSystem,
            overviewDatabaseActor: overviewDatabaseActor
        )
        let mergeOverviewsActor = MergeOverviewsActor(actorSystem: actorSystem)
        let knowledgeBuildTrackerActor = KnowledgeBuildTrackerActor(actorSystem: actorSystem)
        let knowledgeCommunityDetectionActor = KnowledgeCommunityDetectionActor(
            actorSystem: actorSystem,
            knowledgeDatabaseActor: knowledgeDatabaseActor
        )
        let knowledgeChunkGraphActor = KnowledgeChunkGraphActor(
            actorSystem: actorSystem,
            knowledgeDatabaseActor: knowledgeDatabaseActor,
            activityDatabaseActor: activityDatabaseActor
        )
        let coalesceKnowledgeNodeActor = CoalesceKnowledgeNodeActor(actorSystem: actorSystem)
        let coalesceKnowledgeEdgeActor = CoalesceKnowledgeEdgeActor(actorSystem: actorSystem)
        let knowledgeNodeEmbeddingActor = KnowledgeNodeEmbeddingActor(actorSystem: actorSystem)
        let knowledgeCommunitySummaryActor = KnowledgeCommunitySummaryActor(
            actorSystem: actorSystem,
            knowledgeDatabaseActor: knowledgeDatabaseActor
        )
        let knowledgeCommunityEmbeddingActor = KnowledgeCommunityEmbeddingActor(actorSystem: actorSystem)
        let knowledgeObsidianWriterActor = KnowledgeObsidianWriterActor(
            actorSystem: actorSystem,
            knowledgeDatabaseActor: knowledgeDatabaseActor
        )
        let knowledgeClaimEmbeddingActor = KnowledgeClaimEmbeddingActor(actorSystem: actorSystem)
        let activityWorkerDependencies = ActivityWorkerDependencies(
            makeActivityEmbeddingActor: { _ in activityEmbeddingActor },
            makeDescribeImageActor: { _ in describeImageActor },
            makeReadScreenshotTextActor: { _ in readScreenshotTextActor },
            makeSummarizeScreenshotActor: { _ in summarizeScreenshotActor },
            makeSummarizeActivityActor: { _ in summarizeActivityActor },
            makeActivityTagOntologyActor: { _, _ in activityTagOntologyActor },
            makeOntologyOverviewActor: { _, _ in ontologyOverviewActor },
            makeMergeOverviewsActor: { _ in mergeOverviewsActor }
        )
        let agentChannelActor = AgentChannelActor(notificationManager: AgentNotificationManager())
        let agentActionActor = AgentActionActor(agentActionsDatabaseActor: agentActionsDatabaseActor, channelSender: agentChannelActor)
        let jobsActor = JobsActor(
            jobsDatabaseActor: jobsDatabaseActor,
            actorSystem: actorSystem
        )
        let activityActor = ActivityActor(
            activityDatabaseActor: activityDatabaseActor,
            actorSystem: actorSystem,
            agentActionActor: agentActionActor
        )
        let captureMonitor = TaskTraceCaptureMonitor()
        let overviewActor = OverviewActor(
            overviewDatabaseActor: overviewDatabaseActor,
            activityActor: activityActor,
            actorSystem: actorSystem
        )
        let activityStore = ActivityStore(
            activityActor: activityActor,
            actorSystem: actorSystem,
            captureMonitor: captureMonitor
        )
        let overviewStore = OverviewStore(overviewActor: overviewActor, actorSystem: actorSystem, activityStore: activityStore)
        let searchService = TaskTraceSearchService(
            searchDatabaseActor: searchDatabaseActor,
            rerankingGenerator: rerankingActor,
            searchSummaryGenerator: textGenerationActor
        )
        let skillGenerationService = SkillGenerationService(
            searchDatabaseActor: searchDatabaseActor,
            embeddingGenerator: activityEmbeddingActor,
            procedureGenerator: textGenerationActor
        )
        let skillObsidianWriter = SkillObsidianWriter(
            knowledgeDatabaseActor: knowledgeDatabaseActor
        )
        let graphRAGService = GraphRAGService(
            knowledgeReadDatabase: knowledgeReadDatabase,
            embeddingGenerator: activityEmbeddingActor,
            rerankingGenerator: rerankingActor,
            textStreamingGenerator: textGenerationActor
        )
        let searchStore = SearchStore(searchService: searchService)
        let skillsStore = SkillsStore(
            skillGenerationService: skillGenerationService,
            obsidianWriter: skillObsidianWriter
        )
        let knowledgeGraphActor = KnowledgeGraphActor(
            activityDatabaseActor: activityDatabaseActor,
            knowledgeDatabaseActor: knowledgeDatabaseActor,
            actorSystem: actorSystem
        )
        let knowledgeGraphStore = KnowledgeGraphStore(
            actorSystem: actorSystem,
            knowledgeGraphActor: knowledgeGraphActor,
            knowledgeReadDatabase: knowledgeReadDatabase,
            graphRAGService: graphRAGService,
            activityStore: activityStore,
            overviewStore: overviewStore
        )
        let aiStatsStore = AIStatsStore(
            schedulerReporter: AISchedulerRegistry.shared
        )
        let calendarStore = CalendarStore(calendarDatabaseActor: calendarDatabaseActor, activityStore: activityStore, overviewStore: overviewStore, now: Date.init, calendar: Calendar(identifier: .gregorian))
        let tagsStore = TagsStore(tagsDatabaseActor: tagsDatabaseActor)
        let analyticsStore = AnalyticsStore(analyticsDatabaseActor: analyticsDatabaseActor, now: Date.init, calendar: Calendar(identifier: .gregorian))
        let agentActionsStore = AgentActionsStore(agentActionsDatabaseActor: agentActionsDatabaseActor, agentChannelActor: agentChannelActor)
        let navigationStore = TaskTraceNavigationStore()
        let notificationRouter = TaskTraceNotificationRouter(
            navigationStore: navigationStore,
            agentActionsSnapshot: {
                agentActionsStore.agentActions
            }
        )
        let overviewMCPServerController = OverviewMCPServerController(
            overviewStore: overviewStore,
            activityStore: activityStore,
            knowledgeGraphStore: knowledgeGraphStore,
            settingsStore: settingsStore,
            searchService: searchService,
            graphRAGService: graphRAGService
        )
        let browserPluginSocketController = BrowserPluginSocketController()
        let siblingProcessController = TaskTraceSiblingProcessController(
            protectedProcessIdentifiers: {
                TaskTraceMCPHelperProcessRegistry.shared.snapshot()
            }
        )
        let stopLocalRuntimes = { @MainActor @Sendable () async in
            captureMonitor.stop()
            searchStore.stop()
            skillsStore.stop()
            knowledgeGraphStore.stop()
            aiStatsStore.stop()
            await overviewMCPServerController.stop()
            await agentChannelActor.stop()
            await jobsActor.stop()
            await browserPluginSocketController.stop()
                AgentChannelActor.removeSocketFileIfPresent(at: Vars.openClawChannelSocketPath)
                BrowserPluginSocketService.removeSocketFileIfPresent(at: Vars.browserPluginSocketPath)
                OverviewMCPServerRuntime.removeSocketFileIfPresent()
            }
        let configureAgentChannel = { @MainActor @Sendable () async in
            if settingsStore.agentsEnabled {
                await agentChannelActor.start()
            } else {
                await agentChannelActor.setEnabled(false)
            }
        }
        let loadForegroundStores = { @MainActor @Sendable () async in
            await tagsStore.load()
            await activityStore.loadActiveDay()
            await overviewStore.loadActiveDay()
            await calendarStore.loadAvailableDates()
            await analyticsStore.load()
        }
        let applicationShutdownController = TaskTraceApplicationShutdownController(
            shutdown: {
                await activityStore.stopRecordingForApplicationQuit()
                await stopLocalRuntimes()
                await AISchedulerRegistry.shared.shutdownAll()

                if isRunningMCPStdioMode {
                    return
                }

                siblingProcessController.forceKillSiblingProcessesImmediately()
            },
            shutdownState: applicationShutdownState
        )
        TaskTraceApplicationShutdownBridge.shared.controller = applicationShutdownController

        self.activityActor = activityActor
        self.overviewActor = overviewActor
        self.navigationStore = navigationStore
        self.activityStore = activityStore
        self.overviewStore = overviewStore
        self.database = database
        self.searchService = searchService
        self.searchStore = searchStore
        self.skillsStore = skillsStore
        self.knowledgeGraphActor = knowledgeGraphActor
        self.knowledgeGraphStore = knowledgeGraphStore
        self.aiStatsStore = aiStatsStore
        self.calendarStore = calendarStore
        self.tagsStore = tagsStore
        self.analyticsStore = analyticsStore
        self.agentActionActor = agentActionActor
        self.agentChannelActor = agentChannelActor
        self.agentActionsStore = agentActionsStore
        self.jobsActor = jobsActor
        self.captureMonitor = captureMonitor
        self.settingsStore = settingsStore
        self.appUpdater = appUpdater
        self.overviewMCPServerController = overviewMCPServerController
        self.browserPluginSocketController = browserPluginSocketController
        self.applicationShutdownController = applicationShutdownController
        self.applicationShutdownState = applicationShutdownState
        self.mcpStdioProxyController = nil
        self.microphoneCaptureObserver = settingsStore.$microphoneCaptureEnabled.sink { isEnabled in
            captureMonitor.setMicrophoneCaptureEnabled(isEnabled)
        }
        self.statusItemController = isRunningMCPStdioMode || isUITesting
            ? nil
            : TaskTraceStatusItemController(
                activityStore: activityStore,
                settingsStore: settingsStore,
                agentActionsStore: agentActionsStore,
                onToggleRecording: {
                    Task {
                        await TaskTraceApp.handleRecordingToggle(
                            activityStore: activityStore,
                            overviewStore: overviewStore,
                            settingsStore: settingsStore
                        )
                    }
                },
                onSetAgentsEnabled: { isEnabled in
                    settingsStore.setAgentsEnabled(isEnabled)
                    Task {
                        await agentChannelActor.setEnabled(isEnabled)
                    }
                }
            )
        applicationDelegate.notificationRouter = notificationRouter
        UNUserNotificationCenter.current().delegate = applicationDelegate

        if !isUITesting && !isRunningMCPStdioMode {
            _ = captureMonitor.addListener { event in
                activityStore.handleCaptureEvent(event)
            }
        }

        if !isUITesting && !isRunningTests && !isRunningMCPStdioMode {
            do {
                try BrowserPluginNativeHostInstaller.install()
            } catch {
                Logger(subsystem: "com.tasktrace.TaskTrace", category: "browser-plugin").error(
                    "browser plugin native host install failed error=\(String(describing: error), privacy: .public)"
                )
            }

            Task {
                await browserPluginSocketController.start()
            }
        }

        let bootstrapActorSystem = actorSystem
        let bootstrapActivityActor = activityActor
        let bootstrapOverviewActor = overviewActor
        let bootstrapKnowledgeGraphActor = knowledgeGraphActor
        let bootstrapKnowledgeGraphStore = knowledgeGraphStore
        let bootstrapActivityDatabaseActor = activityDatabaseActor
        let bootstrapOverviewDatabaseActor = overviewDatabaseActor
        let bootstrapKnowledgeDatabaseActor = knowledgeDatabaseActor
        let bootstrapDependencies = activityWorkerDependencies
        let bootstrapKnowledgeCommunityDetectionActor = knowledgeCommunityDetectionActor
        let bootstrapKnowledgeBuildTrackerActor = knowledgeBuildTrackerActor
        let bootstrapKnowledgeChunkGraphActor = knowledgeChunkGraphActor
        let bootstrapCoalesceKnowledgeNodeActor = coalesceKnowledgeNodeActor
        let bootstrapCoalesceKnowledgeEdgeActor = coalesceKnowledgeEdgeActor
        let bootstrapKnowledgeNodeEmbeddingActor = knowledgeNodeEmbeddingActor
        let bootstrapKnowledgeCommunitySummaryActor = knowledgeCommunitySummaryActor
        let bootstrapKnowledgeCommunityEmbeddingActor = knowledgeCommunityEmbeddingActor
        let bootstrapKnowledgeObsidianWriterActor = knowledgeObsidianWriterActor
        let bootstrapKnowledgeClaimEmbeddingActor = knowledgeClaimEmbeddingActor
        let bootstrapActivityUMAPActor = activityUMAPActor
        let bootstrapJobsActor = jobsActor
        let runCurrentDayOntologyCatchUp = { @MainActor @Sendable () async in
            let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ontology-startup")

            do {
                let snapshot = try await activityDatabaseActor.loadActivityOntologyCatchUpSnapshot(
                    day: activityStore.activeDay
                )
                logger.log(
                    "ontology startup catch-up day=\(activityStore.activeDay.formatted(TaskTraceDatabase.sqlDateStyle), privacy: .public) latestRunExists=\((snapshot.latestRunID != nil), privacy: .public) missingEmbeddings=\(snapshot.activitiesMissingEmbeddings.count, privacy: .public) missingTags=\(snapshot.activityIDsMissingTags.count, privacy: .public) missingOverviews=\(snapshot.activityIDsMissingOverviews.count, privacy: .public)"
                )

                for activity in snapshot.activitiesMissingEmbeddings {
                    await actorSystem.broadcast(
                        from: nil,
                        message: ActivitySummarized(activity: activity)
                    )
                }

                let appliedAssignments = if snapshot.latestRunID != nil {
                    try await activityDatabaseActor.applyLatestOntologyAssignments(
                        activityIDs: snapshot.activityIDsMissingTags
                    )
                } else {
                    [ActivityOntologyAssignment]()
                }
                for assignment in appliedAssignments {
                    await actorSystem.broadcast(
                        from: nil,
                        message: ActivityTagAssigned(
                            activityID: assignment.activityID,
                            tagID: assignment.tagID,
                            ontologyCandidateID: assignment.ontologyCandidateID
                        )
                    )
                }

                let shouldRefreshOntology = (snapshot.latestRunID == nil
                    && (!snapshot.activityIDsMissingTags.isEmpty || !snapshot.activitiesMissingEmbeddings.isEmpty))
                    || (snapshot.latestRunID != nil
                        && appliedAssignments.count < snapshot.activityIDsMissingTags.count)

                if shouldRefreshOntology {
                    await actorSystem.broadcast(
                        from: nil,
                        message: ActivityTagOntologyRefreshRequested()
                    )
                }

                if !snapshot.activityIDsMissingOverviews.isEmpty {
                    await actorSystem.broadcast(
                        from: nil,
                        message: OntologyOverviewRebuildRequested()
                    )
                }
            } catch {
                logger.error(
                    "ontology startup catch-up failed error=\(String(describing: error), privacy: .public)"
                )
            }
        }
        let pipelineRegistrationTask: Task<Void, Never>? = {
            guard !isUITesting && !isRunningMCPStdioMode && !isRunningTests else {
                return nil
            }

            return Task {
                await AISchedulerRegistry.shared.register(on: bootstrapActorSystem)
                await ActivityScreenshotPipelineBootstrap.register(
                    actorSystem: bootstrapActorSystem,
                    activityActor: bootstrapActivityActor,
                    activityDatabaseActor: bootstrapActivityDatabaseActor,
                    dependencies: bootstrapDependencies
                )
                await OverviewPipelineBootstrap.register(
                    actorSystem: bootstrapActorSystem,
                    overviewActor: bootstrapOverviewActor,
                    overviewDatabaseActor: bootstrapOverviewDatabaseActor,
                    dependencies: bootstrapDependencies
                )
                await KnowledgePipelineBootstrap.register(
                    actorSystem: bootstrapActorSystem,
                    knowledgeGraphActor: bootstrapKnowledgeGraphActor,
                    knowledgeDatabaseActor: bootstrapKnowledgeDatabaseActor,
                    knowledgeBuildTrackerActor: bootstrapKnowledgeBuildTrackerActor,
                    knowledgeCommunityDetectionActor: bootstrapKnowledgeCommunityDetectionActor,
                    knowledgeChunkGraphActor: bootstrapKnowledgeChunkGraphActor,
                    coalesceKnowledgeNodeActor: bootstrapCoalesceKnowledgeNodeActor,
                    coalesceKnowledgeEdgeActor: bootstrapCoalesceKnowledgeEdgeActor,
                    knowledgeNodeEmbeddingActor: bootstrapKnowledgeNodeEmbeddingActor,
                    knowledgeCommunitySummaryActor: bootstrapKnowledgeCommunitySummaryActor,
                    knowledgeCommunityEmbeddingActor: bootstrapKnowledgeCommunityEmbeddingActor,
                    knowledgeObsidianWriterActor: bootstrapKnowledgeObsidianWriterActor,
                    knowledgeClaimEmbeddingActor: bootstrapKnowledgeClaimEmbeddingActor
                )
                _ = await bootstrapActorSystem.register(bootstrapActivityUMAPActor)
                _ = await bootstrapActorSystem.register(bootstrapJobsActor)
                await bootstrapJobsActor.start()
            }
        }()
        let applicationBootstrapTask: Task<Void, Never>? = {
            guard let pipelineRegistrationTask else {
                return nil
            }

            return Task {
                await pipelineRegistrationTask.value
                await bootstrapKnowledgeGraphStore.load()
                await MainActor.run {
                    aiStatsStore.start()
                }
            }
        }()

        if isUITesting {
            Task {
                await settingsStore.loadPersistedSettings()
            }
        } else if !isRunningTests {
            Task {
                await pipelineRegistrationTask?.value
                await settingsStore.loadPersistedSettings()
                await settingsStore.requestMissingPermissionsIfNeeded()
                await loadForegroundStores()
                await configureAgentChannel()
                await overviewMCPServerController.start()
                try? await Task.sleep(nanoseconds: 500_000_000)
                await siblingProcessController.forceKillSiblingProcesses()
                _ = applicationBootstrapTask
                await runCurrentDayOntologyCatchUp()
                if settingsStore.autoRecordOnLaunchEnabled && !activityStore.isRecording {
                    await Self.handleRecordingToggle(
                        activityStore: activityStore,
                        overviewStore: overviewStore,
                        settingsStore: settingsStore
                    )
                }
            }
        } else {
            Task {
                await loadForegroundStores()
                await configureAgentChannel()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let activityStore,
                   let overviewStore,
                   let searchStore,
                   let skillsStore,
                   let knowledgeGraphStore,
                   let aiStatsStore,
                   let calendarStore,
                   let analyticsStore,
                   let agentActionsStore,
                   let tagsStore,
                   let settingsStore,
                   let appUpdater,
                   let navigationStore {
                    ContentView(
                        navigationStore: navigationStore,
                        activityStore: activityStore,
                        overviewStore: overviewStore,
                        searchStore: searchStore,
                        skillsStore: skillsStore,
                        knowledgeGraphStore: knowledgeGraphStore,
                        aiStatsStore: aiStatsStore,
                        calendarStore: calendarStore,
                        analyticsStore: analyticsStore,
                        agentActionsStore: agentActionsStore,
                        tagsStore: tagsStore,
                        settingsStore: settingsStore,
                        shutdownState: applicationShutdownState,
                        appUpdater: appUpdater,
                        onToggleRecording: toggleRecordingFromControls
                    )
                } else {
                    EmptyView()
                }
            }
        }
        // Helper runtimes are headless. Suppressing the default launch behavior keeps
        // LaunchServices from reopening them as blank windowed apps.
        .defaultLaunchBehavior(Self.isRunningMCPStdioMode() ? .suppressed : .automatic)
        .commands {
            CommandGroup(after: .appInfo) {
                if let appUpdater {
                    CheckForUpdatesButton(appUpdater: appUpdater)
                }
            }
        }
    }
}

extension TaskTraceApp {
    private func toggleRecordingFromControls() {
        guard let activityStore,
              let overviewStore,
              let settingsStore else {
            return
        }

        Task {
            await Self.handleRecordingToggle(
                activityStore: activityStore,
                overviewStore: overviewStore,
                settingsStore: settingsStore
            )
        }
    }

    private static func handleRecordingToggle(
        activityStore: ActivityStore,
        overviewStore: OverviewStore,
        settingsStore: SettingsStore
    ) async {
        let wasRecording = activityStore.isRecording

        if !wasRecording {
            settingsStore.refreshPermissions()

            if !settingsStore.permissionStatus.accessibilityGranted {
                await settingsStore.requestPermission(.accessibility)
            }

            if !settingsStore.permissionStatus.screenRecordingGranted {
                await settingsStore.requestPermission(.screenRecording)
            }

            if settingsStore.microphoneCaptureEnabled {
                if !settingsStore.permissionStatus.microphoneGranted {
                    await settingsStore.requestPermission(.microphone)
                }

                if !settingsStore.permissionStatus.speechRecognitionGranted {
                    await settingsStore.requestPermission(.speechRecognition)
                }
            }
        }

        await activityStore.toggleRecording()

        if wasRecording {
            await overviewStore.loadActiveDay()
        }
    }

    private static func databaseURLForLaunch() -> URL? {
        guard isRunningTests() else {
            return nil
        }

        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TaskTraceTests-\(ProcessInfo.processInfo.processIdentifier).sqlite")
    }

    private static func isRunningTests() -> Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func isRunningUITests() -> Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    private static func isRunningMCPStdioMode() -> Bool {
        ProcessInfo.processInfo.arguments.contains(Vars.mcpStdioLaunchArgument)
    }
}

@MainActor
final class TaskTraceStatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(
        activityStore: ActivityStore,
        settingsStore: SettingsStore,
        agentActionsStore: AgentActionsStore,
        onToggleRecording: @escaping () -> Void,
        onSetAgentsEnabled: @escaping (Bool) -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.popover = NSPopover()

        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = TaskTraceGlassPopoverController(
            rootView: AgentStatusPopoverView(
                activityStore: activityStore,
                settingsStore: settingsStore,
                agentActionsStore: agentActionsStore,
                onToggleRecording: onToggleRecording,
                onSetAgentsEnabled: onSetAgentsEnabled,
                onOpenTaskTrace: { [weak self] in
                    self?.openTaskTrace()
                },
                onQuitTaskTrace: { [weak self] in
                    self?.quitTaskTrace()
                }
            )
        )

        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleProportionallyDown
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp])
        applyStatusItemImage()
    }

    @objc private func openTaskTrace() {
        TaskTraceWindowActivation.activateAppAndRaiseMainWindow()
    }

    @objc private func quitTaskTrace() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }

    private func applyStatusItemImage() {
        let trayImage = NSImage(
            named: "TrayIcon"
        ) ?? NSImage(
            systemSymbolName: "record.circle",
            accessibilityDescription: "TaskTrace"
        )
        trayImage?.isTemplate = true
        statusItem.button?.image = trayImage
    }
}

@MainActor
private final class TaskTraceGlassPopoverController<Content: View>: NSViewController {
    private let hostingController: NSHostingController<Content>

    init(rootView: Content) {
        self.hostingController = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 26
        effectView.layer?.masksToBounds = true
        effectView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor

        let contentView = hostingController.view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: effectView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        self.view = effectView
    }
}
