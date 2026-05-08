//
//  ContentView.swift
//  TaskTrace
//
//  Created by Warren Ronsiek on 3/11/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedAnalyticsSection: AnalyticsSection = .charts
    @State private var selectedKnowledgeMode: KnowledgeGraphView.Mode = .graph
    @State private var timelineActivityIDToReveal: Int64?
    @State private var timelineFocusDate: Date?
    @ObservedObject var navigationStore: TaskTraceNavigationStore
    @ObservedObject var activityStore: ActivityStore
    @ObservedObject var overviewStore: OverviewStore
    @ObservedObject var searchStore: SearchStore
    @ObservedObject var skillsStore: SkillsStore
    @ObservedObject var knowledgeGraphStore: KnowledgeGraphStore
    @ObservedObject var aiStatsStore: AIStatsStore
    @ObservedObject var calendarStore: CalendarStore
    @ObservedObject var analyticsStore: AnalyticsStore
    @ObservedObject var goalsStore: GoalsStore
    @ObservedObject var agentActionsStore: AgentActionsStore
    @ObservedObject var tagsStore: TagsStore
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var shutdownState: TaskTraceApplicationShutdownState
    @ObservedObject var appUpdater: AppUpdater
    let onToggleRecording: () -> Void
    @Namespace private var navigationSelectionNamespace
    private let supportContacts: [(id: String, value: String, systemImage: String?, assetImage: String?, link: URL?)] = [
        ("phone", "(510) 883-4346", "phone", nil, nil),
        ("x", "@warrenronsiek", nil, "XIcon", URL(string: "https://x.com/warrenronsiek")),
        ("email", "warren@tasktrace.com", "envelope", nil, nil),
        ("docs", "tasktrace.com/docs", "book", nil, URL(string: "https://tasktrace.com/docs")),
        ("discord", "discord.gg/gWkVenJudm", nil, "DiscordIcon", URL(string: "https://discord.gg/gWkVenJudm"))
    ]

    var body: some View {
        ZStack {
            NavigationSplitView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .center, spacing: 10) {
                        Button {
                            onToggleRecording()
                        } label: {
                            Image(systemName: activityStore.isRecording ? "stop.fill" : "play.fill")
                                .font(Styles.Fonts.recordButtonIcon)
                            .frame(width: 88, height: 88)
                            .opacity(activityStore.playStopButtonDisabled ? 0.45 : 1)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(activityStore.isRecording ? AppColors.recordActive : AppColors.recordIdle)
                        .disabled(activityStore.playStopButtonDisabled)
                        .frame(maxWidth: .infinity)

                        Text(activityStore.isRecording ? "Recording" : "Stopped")
                            .font(Styles.Fonts.subheadlineSemibold)

                        if activityStore.playStopButtonDisabled {
                            Text("Recording is only available for today. Use the Calendar to change the date.")
                                .font(Styles.Fonts.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(AppPage.sidebarPages) { page in
                            sidebarButton(for: page)
                        }
                    }

                    Spacer(minLength: 0)

                    sidebarSupportCard
                }
                .padding(.horizontal, 12)
                .navigationTitle("TaskTrace")
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            } detail: {
                switch navigationStore.selectedPage ?? .activity {
                case .activity:
                    ActivityView(
                        activityStore: activityStore,
                        tagsStore: tagsStore,
                        goalsStore: goalsStore,
                        onShowTimelineForActivity: { activityID, activityDate in
                            timelineActivityIDToReveal = activityID
                            timelineFocusDate = activityDate
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                navigationStore.selectedPage = .calendar
                            }
                        }
                    )
                case .search:
                    SearchView(searchStore: searchStore)
                case .calendar:
                    CalendarView(
                        calendarStore: calendarStore,
                        activityStore: activityStore,
                        overviewStore: overviewStore,
                        tagsStore: tagsStore,
                        revealedActivityID: $timelineActivityIDToReveal,
                        timelineFocusDate: $timelineFocusDate,
                        selectedPage: $navigationStore.selectedPage
                    )
                case .analytics:
                    if selectedAnalyticsSection == .charts {
                        AnalyticsView(analyticsStore: analyticsStore)
                    } else {
                        TagsView(tagsStore: tagsStore)
                    }
                case .goals:
                    GoalsView(goalsStore: goalsStore)
                case .knowledge:
                    KnowledgeGraphView(
                        knowledgeGraphStore: knowledgeGraphStore,
                        mode: selectedKnowledgeMode
                    )
                case .stats:
                    StatsView(statsStore: aiStatsStore)
                case .agents:
                    AgentsView(
                        navigationStore: navigationStore,
                        agentActionsStore: agentActionsStore,
                        settingsStore: settingsStore,
                        skillsStore: skillsStore,
                        onShowTimelineForActivity: { activityID, activityDate in
                            timelineActivityIDToReveal = activityID
                            timelineFocusDate = activityDate
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                navigationStore.selectedPage = .calendar
                            }
                        }
                    )
                case .settings:
                    SettingsView(settingsStore: settingsStore, appUpdater: appUpdater)
                }
            }
            .frame(minWidth: 760, minHeight: 480)
            .allowsHitTesting(!(shutdownState.isShuttingDown && shutdownState.showsOverlay))
            .onChange(of: navigationStore.selectedPage) { _, nextPage in
                if nextPage == .analytics {
                    selectedAnalyticsSection = .charts
                }

                if nextPage != .calendar {
                    timelineActivityIDToReveal = nil
                    timelineFocusDate = nil
                }
            }

            if shutdownState.isShuttingDown && shutdownState.showsOverlay {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)

                    Text("Shutting Down AI Models...")
                        .font(Styles.Fonts.subheadlineSemibold)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 20, y: 10)
            }
        }
    }

    private var sidebarSupportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(supportContacts, id: \.id) { contact in
                HStack(alignment: .top, spacing: 10) {
                    Group {
                        if let assetImage = contact.assetImage {
                            Image(assetImage)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                        } else if let systemImage = contact.systemImage {
                            Image(systemName: systemImage)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 16, height: 16)

                    if let link = contact.link {
                        Link(contact.value, destination: link)
                            .font(Styles.Fonts.caption2)
                            .foregroundStyle(AppColors.accent)
                    } else {
                        Text(contact.value)
                            .font(Styles.Fonts.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer(minLength: 0)
                }
            }
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 8)
        .padding(.bottom, 16)
    }

    private func sidebarButton(for page: AppPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                    if page == .analytics {
                        selectedAnalyticsSection = .charts
                    }
                    navigationStore.selectedPage = page
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: page.systemImage)
                        .font(Styles.Fonts.sidebarIcon)
                    Text(page.title)
                    Spacer()
                }
                .font(Styles.Fonts.sidebarLabel)
                .foregroundStyle(navigationStore.selectedPage == page ? AppColors.textPrimary : AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    if navigationStore.selectedPage == page {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppColors.recordIdle.opacity(0.20))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.38), lineWidth: 0.8)
                            }
                            .shadow(color: AppColors.recordIdle.opacity(0.16), radius: 16, y: 6)
                            .matchedGeometryEffect(id: "sidebar-selection", in: navigationSelectionNamespace)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            if page == .knowledge, navigationStore.selectedPage == .knowledge {
                Group {
                    sidebarSubButton(
                        title: KnowledgeGraphView.Mode.fileSystem.rawValue,
                        systemImage: "folder",
                        isSelected: selectedKnowledgeMode == .fileSystem
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            selectedKnowledgeMode = .fileSystem
                        }
                    }

                    sidebarSubButton(
                        title: KnowledgeGraphView.Mode.graph.rawValue,
                        systemImage: "network",
                        isSelected: selectedKnowledgeMode == .graph
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            selectedKnowledgeMode = .graph
                        }
                    }
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if page == .analytics, navigationStore.selectedPage == .analytics {
                Group {
                    sidebarSubButton(
                        title: AnalyticsSection.charts.title,
                        systemImage: AnalyticsSection.charts.systemImage,
                        isSelected: selectedAnalyticsSection == .charts
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            selectedAnalyticsSection = .charts
                        }
                    }

                    sidebarSubButton(
                        title: AnalyticsSection.tags.title,
                        systemImage: AnalyticsSection.tags.systemImage,
                        isSelected: selectedAnalyticsSection == .tags
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            selectedAnalyticsSection = .tags
                        }
                    }
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if page == .agents, navigationStore.selectedPage == .agents {
                Group {
                    ForEach(AgentsView.Tab.allCases) { tab in
                        let subIcon: String = switch tab {
                        case .chat:
                            "bubble.left"
                        case .skills:
                            "wand.and.stars"
                        case .connection:
                            "link"
                        case .setup:
                            "gearshape"
                        case .mcp:
                            "terminal"
                        }

                        sidebarSubButton(
                            title: tab.title,
                            systemImage: subIcon,
                            isSelected: navigationStore.selectedAgentsTab == tab
                        ) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                navigationStore.selectedAgentsTab = tab
                            }
                        }
                    }
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: navigationStore.selectedPage)
    }

    private func sidebarSubButton(
        title: String,
        systemImage: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))

                Text(title)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .font(Styles.Fonts.sidebarSecondaryAction)
            .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(AppColors.recordIdle.opacity(0.18))
                            : AnyShapeStyle(.ultraThinMaterial)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.white.opacity(0.34) : Color.white.opacity(0.22),
                                lineWidth: 0.8
                            )
                    }
            )
        }
        .buttonStyle(.plain)
    }
}

extension ContentView {
    private enum AnalyticsSection: String {
        case charts
        case tags

        var title: String {
            switch self {
            case .charts:
                "Charts"
            case .tags:
                "Tags"
            }
        }

        var systemImage: String {
            switch self {
            case .charts:
                "chart.bar.xaxis"
            case .tags:
                "tag"
            }
        }
    }

    enum AppPage: String, Identifiable {
        case activity
        case calendar
        case analytics
        case goals
        case stats
        case search
        case knowledge
        case agents
        case settings

        var id: String { rawValue }

        static var sidebarPages: [AppPage] {
            sidebarPages(bundleIdentifier: Vars.bundleIdentifier)
        }

        static func sidebarPages(bundleIdentifier: String) -> [AppPage] {
            [.activity, .calendar, .goals, .analytics, .stats, .search, .knowledge, .agents, .settings]
        }

        var title: String {
            switch self {
            case .activity:
                "Activity"
            case .agents:
                "Agents"
            case .search:
                "Search"
            case .knowledge:
                "Knowledge"
            case .calendar:
                "Timeline"
            case .analytics:
                "Analytics"
            case .goals:
                "Goals"
            case .stats:
                "Stats"
            case .settings:
                "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .activity:
                "stopwatch"
            case .agents:
                "person.2"
            case .search:
                "magnifyingglass"
            case .knowledge:
                "brain"
            case .calendar:
                "clock.arrow.circlepath"
            case .analytics:
                "chart.bar.xaxis"
            case .goals:
                "target"
            case .stats:
                "waveform.path.ecg.rectangle"
            case .settings:
                "gearshape"
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        return ContentView(
            navigationStore: TaskTraceNavigationStore(),
            activityStore: ActivityStore(previewState: .init(activities: [
                ActivityActor.Activity(
                    id: 1,
                    application: "com.apple.dt.Xcode",
                    startTime: Date(),
                    keystrokes: "let preview = true",
                    microphone: "explaining the preview build",
                    summary: "Placeholder activity summary.",
                    overviewID: nil,
                    tagID: nil,
                    screenshots: [
                        ActivityActor.Screenshot(
                            id: 2,
                            image: nil,
                            timestamp: Date(),
                            description: "Placeholder screenshot description.",
                            text: "Placeholder OCR text.",
                            ignoreReason: nil
                        )
                    ]
                )
            ])),
            overviewStore: OverviewStore(previewOverviews: [
                OverviewStore.Overview(
                    id: 11,
                    title: "Developing TaskTrace",
                    summary: "Worked through screenshot capture, summarization, and overview generation in Xcode.",
                    editedDuration: 3_600,
                    tagID: 1
                )
            ]),
            searchStore: SearchStore(previewResults: []),
            skillsStore: SkillsStore(),
            knowledgeGraphStore: KnowledgeGraphStore(
                previewDirectories: [
                    KnowledgeDirectoryRecord(
                        id: 1,
                        slot: .obsidianVault,
                        path: "/Users/warrenronsiek/Documents/Notes",
                        bookmarkData: nil,
                        createdAt: Date()
                    )
                ],
                previewFiles: [
                    KnowledgeFileRecord(
                        id: 1,
                        directoryID: 1,
                        path: "TaskTrace/Architecture.md",
                        title: "TaskTrace Architecture",
                        hash: "abc123def456",
                        modifiedAt: Date(),
                        createDate: Date(),
                        lastAccessed: Date(),
                        metadataJSON: #"{"title":"TaskTrace Architecture","aliases":["Architecture"]}"#,
                        deletedAt: nil,
                        byteCount: 2048
                    )
                ],
                previewSelectedFilePreview: KnowledgeFilePreview(
                    path: "TaskTrace/Architecture.md",
                    byteCount: 2048,
                    content: "# TaskTrace Architecture\n\n## Capture Pipeline\n\nTaskTrace records screenshots and keystrokes, then pushes them through the local indexing pipeline.",
                    isTruncated: false
                ),
                previewSelectedFileIndex: KnowledgeFileIndexSummary(
                    aliases: ["Architecture", "TaskTrace Architecture"],
                    anchors: [
                        KnowledgeScannedAnchor(
                            anchorType: "document",
                            anchorKey: "document",
                            headingText: "TaskTrace Architecture",
                            blockID: nil,
                            startLine: 1,
                            endLine: 8,
                            textHash: "preview-document",
                            chunks: [
                                KnowledgeScannedChunk(
                                    ordinal: 0,
                                    hash: "preview-document-chunk",
                                    text: "TaskTrace records screenshots and keystrokes, then pushes them through the local indexing pipeline."
                                )
                            ]
                        ),
                        KnowledgeScannedAnchor(
                            anchorType: "heading",
                            anchorKey: "capture-pipeline",
                            headingText: "Capture Pipeline",
                            blockID: "capture-pipeline",
                            startLine: 3,
                            endLine: 8,
                            textHash: "preview-heading",
                            chunks: [
                                KnowledgeScannedChunk(
                                    ordinal: 0,
                                    hash: "preview-heading-chunk",
                                    text: "TaskTrace records screenshots and keystrokes, then pushes them through the local indexing pipeline."
                                )
                            ]
                        )
                    ],
                    links: [
                        KnowledgeScannedLink(
                            srcAnchorKey: "capture-pipeline",
                            dstPathCandidate: "TaskTrace/Capture.md",
                            dstAnchorHint: "vision",
                            linkText: "Capture internals",
                            linkType: "markdown"
                        )
                    ]
                )
            ),
            aiStatsStore: AIStatsStore(
                schedulerReporter: nil,
                previewSchedulerSnapshots: [
                    AISchedulerStatsSnapshot(
                        id: "preview-text",
                        name: "Text",
                        queuedDepthByBucket: [
                            AISchedulerBucketSnapshot(
                                id: "1025...2048",
                                queuedDepth: 5,
                                oldestQueuedAgeSeconds: 4.2,
                                activeBatches: [
                                    AISchedulerActiveBatchSnapshot(
                                        id: UUID(),
                                        bucket: "1025...2048",
                                        source: "activity-summary",
                                        requestCount: 4,
                                        recordCount: 4,
                                        batchSize: 4,
                                        ageSeconds: 2.1,
                                        estimatedMemoryBytes: 8_800_000_000
                                    )
                                ],
                                eventKindBreakdown: [
                                    AISchedulerEventKindSnapshot(
                                        id: "activity-summary",
                                        eventKind: "activity-summary",
                                        queuedDepth: 3,
                                        activeRequestCount: 4,
                                        activeRecordCount: 4,
                                        oldestQueuedAgeSeconds: 4.2
                                    ),
                                    AISchedulerEventKindSnapshot(
                                        id: "knowledge-chunk-graph",
                                        eventKind: "knowledge-chunk-graph",
                                        queuedDepth: 2,
                                        activeRequestCount: 0,
                                        activeRecordCount: 0,
                                        oldestQueuedAgeSeconds: 2.6
                                    )
                                ],
                                processedRecordsLast60Seconds: 25,
                                recordsPerSecond: 0.42,
                                processedRecordsTimeline: AISchedulerProcessingTimeline(
                                    bucketDuration: 15,
                                    windowDuration: 450,
                                    bucketProgress: 0.45,
                                    recordCounts: [0, 0, 2, 1, 0, 3, 4, 0, 0, 5, 2, 1, 0, 3, 1, 0, 0, 4, 5, 1, 0, 2, 3, 1, 0, 4, 2, 1, 3, 2],
                                    batchCounts: [0, 0, 1, 1, 0, 1, 1, 0, 0, 2, 1, 1, 0, 1, 1, 0, 0, 1, 2, 1, 0, 1, 1, 1, 0, 2, 1, 1, 1, 1]
                                ),
                                processedRecordsTimelineByKind: [
                                    AISchedulerEventKindTimelineSnapshot(
                                        eventKind: "activity-summary",
                                        processedRecordsLast60Seconds: 14,
                                        recordsPerSecond: 0.23,
                                        timeline: AISchedulerProcessingTimeline(
                                            bucketDuration: 15,
                                            windowDuration: 450,
                                            bucketProgress: 0.45,
                                            recordCounts: [0, 0, 1, 1, 0, 2, 3, 0, 0, 3, 1, 1, 0, 2, 1, 0, 0, 3, 4, 1, 0, 1, 2, 1, 0, 2, 2, 1, 2, 1],
                                            batchCounts: [0, 0, 1, 1, 0, 1, 1, 0, 0, 1, 1, 1, 0, 1, 1, 0, 0, 1, 2, 1, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1]
                                        )
                                    ),
                                    AISchedulerEventKindTimelineSnapshot(
                                        eventKind: "knowledge-chunk-graph",
                                        processedRecordsLast60Seconds: 11,
                                        recordsPerSecond: 0.18,
                                        timeline: AISchedulerProcessingTimeline(
                                            bucketDuration: 15,
                                            windowDuration: 450,
                                            bucketProgress: 0.45,
                                            recordCounts: [0, 0, 1, 0, 0, 1, 1, 0, 0, 2, 1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 2, 0, 0, 1, 1],
                                            batchCounts: [0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 1, 1]
                                        )
                                    )
                                ]
                            )
                        ],
                        activeBatchCount: 1,
                        activeRecordCount: 4,
                        oldestQueuedAgeSeconds: 4.2,
                        processedRecordsLast60Seconds: 25,
                        recordsPerSecond: 0.42,
                        averageWaitMilliseconds: 118,
                        p95WaitMilliseconds: 410,
                        averageRunMilliseconds: 1_260,
                        p95RunMilliseconds: 2_100,
                        averageBatchSize: 2.4,
                        estimatedMemoryBytes: 8_800_000_000,
                        activeEstimatedMemoryBytes: 8_800_000_000,
                        estimatedMemoryCapBytes: 12 * 1024 * 1024 * 1024,
                        recentFailures: []
                    ),
                    AISchedulerStatsSnapshot(
                        id: "preview-visual",
                        name: "Visual",
                        queuedDepthByBucket: [
                            AISchedulerBucketSnapshot(
                                id: "bytes:18",
                                queuedDepth: 2,
                                oldestQueuedAgeSeconds: 7.8,
                                activeBatches: [
                                    AISchedulerActiveBatchSnapshot(
                                        id: UUID(),
                                        bucket: "bytes:18",
                                        source: "image-description",
                                        requestCount: 2,
                                        recordCount: 2,
                                        batchSize: 2,
                                        ageSeconds: 5.4,
                                        estimatedMemoryBytes: 0
                                    )
                                ],
                                eventKindBreakdown: [
                                    AISchedulerEventKindSnapshot(
                                        id: "image-description",
                                        eventKind: "image-description",
                                        queuedDepth: 2,
                                        activeRequestCount: 2,
                                        activeRecordCount: 2,
                                        oldestQueuedAgeSeconds: 7.8
                                    )
                                ],
                                processedRecordsLast60Seconds: 11,
                                recordsPerSecond: 0.18,
                                processedRecordsTimeline: AISchedulerProcessingTimeline(
                                    bucketDuration: 15,
                                    windowDuration: 450,
                                    bucketProgress: 0.45,
                                    recordCounts: [0, 1, 0, 0, 2, 1, 0, 1, 0, 0, 2, 0, 1, 0, 1, 0, 0, 2, 1, 0, 1, 0, 0, 2, 0, 1, 0, 1, 0, 1],
                                    batchCounts: [0, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 1]
                                )
                            )
                        ],
                        activeBatchCount: 1,
                        activeRecordCount: 2,
                        oldestQueuedAgeSeconds: 7.8,
                        processedRecordsLast60Seconds: 11,
                        recordsPerSecond: 0.18,
                        averageWaitMilliseconds: 260,
                        p95WaitMilliseconds: 680,
                        averageRunMilliseconds: 2_400,
                        p95RunMilliseconds: 3_900,
                        averageBatchSize: 1,
                        estimatedMemoryBytes: 0,
                        activeEstimatedMemoryBytes: 1_300_000_000,
                        estimatedMemoryCapBytes: 10 * 1024 * 1024 * 1024,
                        recentFailures: []
                    )
                ],
                previewAppMemoryFootprintBytes: 5_200_000_000
            ),
            calendarStore: CalendarStore(
                previewAvailableDates: [Calendar.current.startOfDay(for: Date())],
                activityStore: ActivityStore(previewState: .init(activities: [
                    ActivityActor.Activity(
                        id: 1,
                        application: "com.apple.dt.Xcode",
                        startTime: Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date(),
                        keystrokes: "preview",
                        microphone: "",
                        summary: "Preview activity.",
                        overviewID: 11,
                        tagID: 1,
                        screenshots: []
                    ),
                    ActivityActor.Activity(
                        id: 2,
                        application: "com.apple.Safari",
                        startTime: Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date(),
                        keystrokes: "",
                        microphone: "",
                        summary: "Preview browsing activity.",
                        overviewID: nil,
                        tagID: nil,
                        screenshots: []
                    )
                ])),
                overviewStore: OverviewStore(previewOverviews: [
                    OverviewStore.Overview(
                        id: 11,
                        title: "Developing TaskTrace",
                        summary: "Worked through screenshot capture, summarization, and overview generation in Xcode.",
                        editedDuration: 3_600,
                        tagID: 1
                    )
                ])
            ),
            analyticsStore: AnalyticsStore(
                previewTimeline: [
                    AnalyticsStore.TimelineEntry(
                        date: Calendar.current.date(byAdding: .day, value: -2, to: Calendar.current.startOfDay(for: Date())) ?? Date(),
                        tags: ["Work": 28_800, AnalyticsStore.untaggedName: 3_600]
                    ),
                    AnalyticsStore.TimelineEntry(
                        date: Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) ?? Date(),
                        tags: ["Work": 21_600, "Research": 7_200]
                    ),
                    AnalyticsStore.TimelineEntry(
                        date: Calendar.current.startOfDay(for: Date()),
                        tags: ["Research": 10_800]
                    )
                ],
                selectedTags: []
            ),
            goalsStore: GoalsStore(
                previewSnapshot: GoalsSnapshot(
                    goals: [
                        GoalRecord(
                            id: 1,
                            name: "Ship open source release",
                            description: "Finish the public repo cutover and release checks.",
                            createTs: Date(),
                            doneTs: nil,
                            deleteTs: nil
                        )
                    ],
                    todos: [
                        GoalTodoRecord(
                            id: 1,
                            goalID: 1,
                            name: "Review release blockers",
                            createTs: Date(),
                            doneTs: nil,
                            status: .open,
                            statusTs: nil,
                            repeating: false,
                            repeatTemplateID: nil,
                            targetDate: nil,
                            dailyTargetSeconds: 3_600,
                            embedding: nil,
                            deleteTs: nil
                        )
                    ],
                    goalRollups: [GoalRollup(goalID: 1, duration: 2_400)],
                    todoRollups: [GoalTodoRollup(todoID: 1, duration: 2_400)],
                    dailyGoalDurations: [
                        DailyGoalDuration(
                            goalID: 1,
                            day: Calendar.current.startOfDay(for: Date()),
                            duration: 2_400
                        )
                    ],
                    dailyCompletedTodoCounts: [
                        DailyCompletedTodoCount(
                            goalID: 1,
                            day: Calendar.current.startOfDay(for: Date()),
                            completedCount: 1
                        )
                    ]
                )
            ),
            agentActionsStore: AgentActionsStore(
                previewAgentActions: [
                    AgentActionRecord(
                        id: 1,
                        instructions: "Review newly summarized activities and decide what needs follow-up.",
                        eventType: .activitySummarized,
                        conversationID: "preview-conversation-1"
                    ),
                    AgentActionRecord(
                        id: 2,
                        instructions: "Check whether this activity should be queued for review.",
                        eventType: .activitySummarized,
                        conversationID: "preview-conversation-2"
                    )
                ]
            ),
            tagsStore: TagsStore(previewTags: [
                TagRecord(
                    id: 1,
                    name: "Work",
                    createDate: Date(),
                    description: "Programming and AI work.",
                    deleteDate: nil,
                    jsonProperties: nil
                )
            ]),
            settingsStore: SettingsStore(permissionManager: PreviewPermissionManager()),
            shutdownState: TaskTraceApplicationShutdownState(),
            appUpdater: AppUpdater(),
            onToggleRecording: {}
        )
    }
}

private struct PreviewPermissionManager: TaskTracePermissionManaging {
    func status() -> TaskTracePermissionStatus {
        TaskTracePermissionStatus(
            accessibilityGranted: true,
            screenRecordingGranted: false,
            microphoneGranted: true,
            speechRecognitionGranted: true
        )
    }

    func requestMissingPermissionsIfNeeded(includeMicrophoneCapture: Bool) async {}

    func requestPermission(_ permission: TaskTracePermissionKind) async {}

    func openSystemSettings(for permission: TaskTracePermissionKind) {}
}
