//
//  StatsView.swift
//  TaskTrace
//

import SwiftUI

struct StatsViewDisplayCopy: Equatable {
    let usesConsumerText: Bool

    init(bundleIdentifier: String = Vars.bundleIdentifier) {
        self.usesConsumerText = Vars.statsViewUsesConsumerText(forBundleIdentifier: bundleIdentifier)
    }

    var headerTitle: String {
        usesConsumerText ? "AI Processing" : "AI Scheduler Stats"
    }

    var headerSubtitle: String {
        usesConsumerText
            ? "How TaskTrace is handling screenshots, summaries, search, and other local AI work."
            : "Shared model queues, active batches, latency, throughput, memory estimates, and recent scheduler failures."
    }

    var appMemoryTitle: String {
        usesConsumerText ? "TaskTrace Memory" : "App Memory"
    }

    var unavailableTitle: String {
        usesConsumerText ? "Processing details are not available yet." : "Scheduler telemetry is not available."
    }

    var unavailableSubtitle: String {
        usesConsumerText
            ? "This page will update once TaskTrace starts processing local AI work."
            : "AI scheduler snapshots will appear here once the runtime starts reporting queue and batch state."
    }

    var queuedTitle: String {
        usesConsumerText ? "Waiting" : "Queued"
    }

    var rateTitle: String {
        usesConsumerText ? "Items/s" : "Records/s"
    }

    var activeTitle: String {
        usesConsumerText ? "Working" : "Admitted"
    }

    var lastMinuteTitle: String {
        usesConsumerText ? "Last Minute" : "60s Records"
    }

    var averageBatchTitle: String {
        usesConsumerText ? "Avg Group" : "Batch"
    }

    var memoryEstimateTitle: String {
        usesConsumerText ? "Memory Est." : "Estimate"
    }

    var memoryPressureTitle: String {
        usesConsumerText ? "AI memory in use" : "Admitted memory estimate"
    }

    var emptyBucketText: String {
        usesConsumerText ? "No waiting, active, or recently completed work" : "No queued, active, or recently processed requests"
    }

    var inFlightTitle: String {
        usesConsumerText ? "In Progress" : "In Flight"
    }

    var eventBreakdownTitle: String {
        usesConsumerText ? "Work Types" : "Event Kinds"
    }

    var workTypePrefix: String {
        usesConsumerText ? "Work type" : "Kind"
    }

    var sourcePrefix: String {
        usesConsumerText ? "Details" : "Source"
    }

    var processedTimelineTitle: String {
        usesConsumerText ? "Completed Items" : "Processed Records"
    }

    var windowSuffix: String {
        usesConsumerText ? "history" : "window"
    }

    var bucketSuffix: String {
        usesConsumerText ? "intervals" : "bins"
    }

    var averageWaitTitle: String {
        usesConsumerText ? "Avg Wait" : "Avg Wait"
    }

    var p95WaitTitle: String {
        usesConsumerText ? "Slow Wait" : "Wait P95"
    }

    var averageRunTitle: String {
        usesConsumerText ? "Avg Time" : "Avg Run"
    }

    var p95RunTitle: String {
        usesConsumerText ? "Slow Time" : "Run P95"
    }

    var failuresTitle: String {
        usesConsumerText ? "Errors" : "Failures"
    }

    func schedulerName(
        id: String,
        fallback: String
    ) -> String {
        guard usesConsumerText else {
            return fallback
        }

        return Self.schedulerLabels[id] ?? humanizedLabel(fallback)
    }

    func schedulerActiveRecordSummary(
        activeRecordCount: Int,
        activeRecordCap: Int?,
        activeBatchCount: Int
    ) -> String {
        guard usesConsumerText else {
            if let activeRecordCap {
                return "\(activeRecordCount)/\(activeRecordCap) admitted records in \(activeBatchCount) runtime batches"
            }

            return "\(activeRecordCount) admitted records in \(activeBatchCount) runtime batches"
        }

        if let activeRecordCap {
            return "\(activeRecordCount)/\(activeRecordCap) items being handled across \(activeBatchCount) groups"
        }

        return "\(activeRecordCount) items being handled across \(activeBatchCount) groups"
    }

    func activeRecordValue(
        activeRecordCount: Int,
        activeRecordCap: Int?
    ) -> String {
        guard let activeRecordCap else {
            return "\(activeRecordCount)"
        }

        return "\(activeRecordCount)/\(activeRecordCap)"
    }

    func bucketLabel(_ rawValue: String) -> String {
        guard usesConsumerText else {
            return rawValue
        }

        let parts = rawValue.components(separatedBy: "|")
        let base = parts.first ?? rawValue

        if let tokenLabel = Self.tokenBucketLabels[base] {
            return tokenLabel
        }

        if rawValue.contains("images:") {
            let imageCount = parts
                .first { $0.hasPrefix("images:") }
                .flatMap { Int($0.replacingOccurrences(of: "images:", with: "")) }
            let promptBucket = parts
                .first { $0.hasPrefix("promptTokens:") }
                .map { $0.replacingOccurrences(of: "promptTokens:", with: "") }
                .flatMap { Self.tokenBucketLabels[$0] }
            let imageText = imageCount.map { $0 == 1 ? "1 screenshot" : "\($0) screenshots" }

            let label = [imageText, promptBucket]
                .compactMap { $0 }
                .joined(separator: ", ")

            return label.isEmpty ? "Screenshot work" : label
        }

        return humanizedLabel(base)
    }

    func telemetryLabel(_ rawValue: String) -> String {
        guard usesConsumerText else {
            return rawValue
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Other work"
        }

        let pieces = trimmed.components(separatedBy: " +")
        let base = pieces.first ?? trimmed
        let label = Self.telemetryLabels[base] ?? humanizedLabel(base)

        guard pieces.count > 1,
              let countText = pieces.last,
              let count = Int(countText) else {
            return label
        }

        return "\(label) +\(count) more"
    }

    func activeBatchParameterLabels(
        modelName: String?,
        promptTokenEstimate: Int?,
        maxTokens: Int?,
        maxKVSize: Int?,
        kvBits: Int?,
        prefillStepSize: Int?
    ) -> [String] {
        if usesConsumerText {
            return [
                promptTokenEstimate.map { "Input size: \($0) tokens" },
                maxTokens.map { "Output limit: \($0) tokens" }
            ].compactMap { $0 }
        }

        return [
            modelName.map { "Model: \($0)" },
            promptTokenEstimate.map { "Prompt: \($0) tok" },
            maxTokens.map { "Max Tokens: \($0)" },
            maxKVSize.map { "Max KV: \($0)" },
            kvBits.map { "KV Bits: \($0)" },
            prefillStepSize.map { "Prefill: \($0)" }
        ].compactMap { $0 }
    }

    private func humanizedLabel(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map { word in
                let lowercased = word.lowercased()
                return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
            }
            .joined(separator: " ")
    }

    private static let schedulerLabels: [String: String] = [
        AIModelSchedulerKind.textSmall.rawValue: "Quick text processing",
        AIModelSchedulerKind.textBig.rawValue: "Detailed text processing",
        AIModelSchedulerKind.visual.rawValue: "Screenshot understanding",
        AIModelSchedulerKind.embedding.rawValue: "Search indexing",
        AIModelSchedulerKind.reranker.rawValue: "Search ranking",
        AIModelSchedulerKind.activityUMAP.rawValue: "Activity map"
    ]

    private static let tokenBucketLabels: [String: String] = [
        AITextTokenBucket.upTo512.rawValue: "Small work",
        AITextTokenBucket.upTo1024.rawValue: "Medium work",
        AITextTokenBucket.upTo2048.rawValue: "Large work",
        AITextTokenBucket.upTo4096.rawValue: "Extra large work",
        AITextTokenBucket.upTo8192.rawValue: "Very large work",
        AITextTokenBucket.over8192.rawValue: "Oversized work"
    ]

    private static let telemetryLabels: [String: String] = [
        "activity-summary": "Activity summaries",
        "activity-goal-todo-assignment": "Goal assignment",
        "activity-summary-embedding": "Activity search indexing",
        "activity-embedding": "Activity search indexing",
        "activity-reranking": "Activity search ranking",
        "activity-tag-ontology-summary": "Tag suggestions",
        "activity-umap": "Activity map updates",
        "direct-text": "Direct text requests",
        "direct-text-batch": "Direct text batches",
        "embedding": "Search indexing",
        "graph-rag-query-embedding": "Knowledge search indexing",
        "graph-rag-reranking": "Knowledge search ranking",
        "image-description": "Screenshot descriptions",
        "knowledge-chunk-graph": "Knowledge graph updates",
        "knowledge-claim-embedding": "Knowledge claim indexing",
        "knowledge-community-embedding": "Knowledge topic indexing",
        "knowledge-community-summary": "Knowledge topic summaries",
        "knowledge-edge-coalesce": "Knowledge relationship cleanup",
        "knowledge-node-coalesce": "Knowledge topic cleanup",
        "knowledge-node-embedding": "Knowledge topic indexing",
        "knowledge-obsidian-summary": "Obsidian note summaries",
        "ontology-overview-summary": "Timeline summaries",
        "overview-merge": "Timeline overview cleanup",
        "processed": "Completed work",
        "reranking": "Search ranking",
        "screenshot-summary": "Screenshot summaries",
        "search-reranking": "Search ranking",
        "skill-context-embedding": "Skill context indexing",
        "unknown": "Other work"
    ]
}

struct StatsView: View {
    @ObservedObject var statsStore: AIStatsStore
    private let copy: StatsViewDisplayCopy

    private let progressAnimation = Animation.easeInOut(duration: 0.28)

    init(
        statsStore: AIStatsStore,
        bundleIdentifier: String = Vars.bundleIdentifier
    ) {
        self.statsStore = statsStore
        self.copy = StatsViewDisplayCopy(bundleIdentifier: bundleIdentifier)
    }

    private struct SchedulerEventKindLegendItem: Identifiable, Equatable {
        let id: String
        let eventKind: String
        let queuedDepth: Int
        let activeRequestCount: Int
        let activeRecordCount: Int
        let oldestQueuedAgeSeconds: Double
        let processedRecordsLast60Seconds: Int
        let processedRecordsInWindow: Int
        let recordsPerSecond: Double
    }

    private var sortedSchedulerSnapshots: [AISchedulerStatsSnapshot] {
        statsStore.schedulerSnapshots.sorted { left, right in
            let leftPressure = left.queuedDepthByBucket.reduce(0) { $0 + $1.queuedDepth } + left.activeRecordCount
            let rightPressure = right.queuedDepthByBucket.reduce(0) { $0 + $1.queuedDepth } + right.activeRecordCount

            if leftPressure == rightPressure {
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }

            return leftPressure > rightPressure
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(copy.headerTitle)
                        .font(Styles.Fonts.title3Semibold)
                    Text(copy.headerSubtitle)
                        .font(Styles.Fonts.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack(spacing: 10) {
                    metricChip(
                        title: copy.appMemoryTitle,
                        value: statsStore.appMemoryFootprintBytes > 0
                            ? memoryLabel(Double(statsStore.appMemoryFootprintBytes))
                            : "-"
                    )
                    Spacer(minLength: 0)
                }

                if sortedSchedulerSnapshots.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(copy.unavailableTitle)
                            .font(Styles.Fonts.subheadlineSemibold)
                        Text(copy.unavailableSubtitle)
                            .font(Styles.Fonts.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground)
                } else {
                    ForEach(sortedSchedulerSnapshots) { snapshot in
                        schedulerCard(snapshot: snapshot)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Stats")
    }

    @ViewBuilder
    private func schedulerCard(
        snapshot: AISchedulerStatsSnapshot
    ) -> some View {
        let queuedDepth = snapshot.queuedDepthByBucket.reduce(0) { $0 + $1.queuedDepth }
        let maxQueuedDepth = max(snapshot.queuedDepthByBucket.map(\.queuedDepth).max() ?? 1, 1)

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.schedulerName(id: snapshot.id, fallback: snapshot.name))
                        .font(Styles.Fonts.title3Semibold)
                    Text(schedulerActiveRecordSummary(snapshot))
                        .font(Styles.Fonts.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    metricChip(
                        title: copy.queuedTitle,
                        value: "\(queuedDepth)"
                    )
                    metricChip(
                        title: copy.rateTitle,
                        value: String(format: "%.2f", snapshot.recordsPerSecond)
                    )
                    metricChip(
                        title: copy.activeTitle,
                        value: schedulerActiveRecordValue(snapshot)
                    )
                    metricChip(
                        title: copy.lastMinuteTitle,
                        value: "\(snapshot.processedRecordsLast60Seconds)"
                    )
                    metricChip(
                        title: copy.averageBatchTitle,
                        value: String(format: "%.1f avg", snapshot.averageBatchSize)
                    )
                    metricChip(
                        title: copy.memoryEstimateTitle,
                        value: memoryLabel(Double(snapshot.estimatedMemoryBytes))
                    )
                }
            }

            schedulerMemoryPressure(snapshot)

            VStack(alignment: .leading, spacing: 10) {
                if snapshot.queuedDepthByBucket.isEmpty {
                    Text(copy.emptyBucketText)
                        .font(Styles.Fonts.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    ForEach(snapshot.queuedDepthByBucket) { bucket in
                        schedulerBucketRow(
                            bucket: bucket,
                            maxQueuedDepth: maxQueuedDepth
                        )
                    }
                }
            }

            HStack(spacing: 10) {
                metricChip(
                    title: copy.averageWaitTitle,
                    value: String(format: "%.0f ms", snapshot.averageWaitMilliseconds)
                )
                metricChip(
                    title: copy.p95WaitTitle,
                    value: String(format: "%.0f ms", snapshot.p95WaitMilliseconds)
                )
                metricChip(
                    title: copy.averageRunTitle,
                    value: String(format: "%.0f ms", snapshot.averageRunMilliseconds)
                )
                metricChip(
                    title: copy.p95RunTitle,
                    value: String(format: "%.0f ms", snapshot.p95RunMilliseconds)
                )
                metricChip(
                    title: copy.failuresTitle,
                    value: "\(snapshot.recentFailures.count)"
                )
            }

            if !snapshot.recentFailures.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(copy.usesConsumerText ? "Recent Errors" : "Recent Failures")
                        .font(Styles.Fonts.footnoteSemibold)

                    ForEach(snapshot.recentFailures.prefix(3)) { failure in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(failure.message)
                                .font(Styles.Fonts.footnote)
                                .lineLimit(2)
                            Text(lastSeenLabel(failure.occurredAt))
                                .font(Styles.Fonts.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppColors.insetBackground)
                        )
                    }
                }
            }
        }
        .padding(22)
        .background(cardBackground)
    }

    @ViewBuilder
    private func schedulerMemoryPressure(
        _ snapshot: AISchedulerStatsSnapshot
    ) -> some View {
        if let capBytes = snapshot.estimatedMemoryCapBytes,
           capBytes > 0 {
            let activeBytes = max(snapshot.activeEstimatedMemoryBytes, 0)
            let pressure = Double(activeBytes) / Double(capBytes)
            let displayedPressure = min(max(pressure, 0), 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(copy.memoryPressureTitle)
                        .font(Styles.Fonts.footnoteSemibold)
                    Spacer(minLength: 0)
                    Text("\(memoryLabel(Double(activeBytes))) / \(memoryLabel(Double(capBytes)))")
                        .font(Styles.Fonts.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Text(String(format: "%.0f%%", (snapshot.capacityUtilization ?? pressure) * 100))
                        .font(Styles.Fonts.footnoteSemibold)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppColors.insetBackground)

                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(memoryPressureColor(pressure).opacity(0.9))
                            .frame(
                                width: max(
                                    activeBytes > 0 ? 6 : 0,
                                    proxy.size.width * CGFloat(displayedPressure)
                                )
                            )
                    }
                    .animation(progressAnimation, value: activeBytes)
                }
                .frame(height: 18)
            }
        }
    }

    @ViewBuilder
    private func schedulerBucketRow(
        bucket: AISchedulerBucketSnapshot,
        maxQueuedDepth: Int
    ) -> some View {
        let legendItems = eventKindLegendItems(for: bucket)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(copy.bucketLabel(bucket.id))
                    .font(Styles.Fonts.footnoteSemibold)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(
                    copy.usesConsumerText
                        ? "\(bucket.processedRecordsLast60Seconds) items / min"
                        : "\(bucket.processedRecordsLast60Seconds) records / 60s"
                )
                    .font(Styles.Fonts.footnoteSemibold)
                Text(String(format: "%.2f/s", bucket.recordsPerSecond))
                    .font(Styles.Fonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            HStack(alignment: .top, spacing: 14) {
                queueBarRow(
                    title: copy.queuedTitle,
                    value: bucket.queuedDepth,
                    maximum: maxQueuedDepth,
                    segments: legendItems
                )
                .frame(minWidth: 170)

                processedTimelineRow(
                    bucket.processedRecordsTimeline,
                    eventKindTimelines: bucket.processedRecordsTimelineByKind
                )
            }

            if !legendItems.isEmpty {
                eventKindBreakdownRow(legendItems)
            }

            if !bucket.activeBatches.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(copy.inFlightTitle)
                        .font(Styles.Fonts.footnoteSemibold)

                    ForEach(bucket.activeBatches) { batch in
                        activeBatchRow(batch)
                    }
                }
            }

            if bucket.oldestQueuedAgeSeconds > 0 {
                Text(
                    String(
                        format: copy.usesConsumerText ? "Longest wait %.1fs" : "Oldest queued %.1fs",
                        bucket.oldestQueuedAgeSeconds
                    )
                )
                    .font(Styles.Fonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.insetBackground.opacity(0.72))
        )
    }

    @ViewBuilder
    private func queueBarRow(
        title: String,
        value: Int,
        maximum: Int,
        segments: [SchedulerEventKindLegendItem]
    ) -> some View {
        let queuedSegments = segments.filter { $0.queuedDepth > 0 }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Styles.Fonts.footnoteSemibold)
                Spacer()
                Text("\(value)")
                    .font(Styles.Fonts.footnoteSemibold)
                Text(copy.usesConsumerText ? "items" : "events")
                    .font(Styles.Fonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            GeometryReader { proxy in
                let resolvedMaximum = max(maximum, 1)
                let ratio = min(CGFloat(value) / CGFloat(resolvedMaximum), 1)
                let minimumRatio = proxy.size.width > 0 && value > 0
                    ? min(6 / proxy.size.width, 1)
                    : 0
                let displayRatio = max(ratio, minimumRatio)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppColors.insetBackground)

                    if queuedSegments.isEmpty {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppColors.recordIdle.opacity(0.86))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .scaleEffect(x: displayRatio, y: 1, anchor: .leading)
                    } else {
                        HStack(spacing: 0) {
                            ForEach(queuedSegments) { segment in
                                Rectangle()
                                    .fill(eventKindColor(segment.eventKind).opacity(0.88))
                                    .frame(
                                        width: proxy.size.width
                                            * min(CGFloat(segment.queuedDepth) / CGFloat(resolvedMaximum), 1)
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .animation(progressAnimation, value: queuedSegments)
                .animation(progressAnimation, value: displayRatio)
            }
            .frame(height: 18)
        }
    }

    @ViewBuilder
    private func processedTimelineRow(
        _ timeline: AISchedulerProcessingTimeline,
        eventKindTimelines: [AISchedulerEventKindTimelineSnapshot]
    ) -> some View {
        let processedTint = AppColors.recordActive.opacity(0.86)
        let bucketCount = max(timeline.recordCounts.count, 1)
        let visibleTimelines = eventKindTimelines.filter {
            $0.timeline.recordCounts.reduce(0, +) > 0
        }
        let lineTimelines = visibleTimelines.isEmpty
            ? [
                AISchedulerEventKindTimelineSnapshot(
                    eventKind: "processed",
                    timeline: timeline
                )
            ]
            : visibleTimelines
        let chartMaxValue = max(
            timeline.recordCounts.max() ?? 0,
            visibleTimelines.flatMap { $0.timeline.recordCounts }.max() ?? 0,
            1
        )
        let axisValues = Array(Set([0, max(chartMaxValue / 2, 1), chartMaxValue])).sorted(by: >)
        let pointsForTimeline: (AISchedulerProcessingTimeline) -> [(value: Int, x: Double)] = { timeline in
            timeline.recordCounts.enumerated().map { pair in
                (
                    value: pair.element,
                    x: Double(pair.offset) + 0.5 - timeline.bucketProgress
                )
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(copy.processedTimelineTitle)
                    .font(Styles.Fonts.footnoteSemibold)
                Spacer(minLength: 0)
                Text("\(durationLabel(timeline.windowDuration)) \(copy.windowSuffix)")
                    .font(Styles.Fonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Text("\(durationLabel(timeline.bucketDuration)) \(copy.bucketSuffix)")
                    .font(Styles.Fonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(axisValues.enumerated()), id: \.offset) { pair in
                        Text("\(pair.element)")
                            .font(Styles.Fonts.caption2)
                            .foregroundStyle(AppColors.textSecondary)

                        if pair.offset < axisValues.count - 1 {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(width: 28, height: 72)

                GeometryReader { proxy in
                    let xPosition: (Double) -> CGFloat = { x in
                        CGFloat(min(max(x / Double(bucketCount), 0), 1)) * proxy.size.width
                    }
                    let yPosition: (Double) -> CGFloat = { value in
                        let ratio = chartMaxValue > 0 ? CGFloat(value) / CGFloat(chartMaxValue) : 0
                        return proxy.size.height - (ratio * proxy.size.height)
                    }
                    let pathForPoints: ([(value: Int, x: Double)]) -> Path = { points in
                        Path { path in
                            guard let firstPoint = points.first else {
                                return
                            }

                            let bucketWidth = proxy.size.width / CGFloat(bucketCount)
                            let leftEdge: (Double) -> CGFloat = { xPosition($0) - (bucketWidth / 2) }
                            let rightEdge: (Double) -> CGFloat = { xPosition($0) + (bucketWidth / 2) }

                            path.move(
                                to: CGPoint(
                                    x: leftEdge(firstPoint.x),
                                    y: yPosition(Double(firstPoint.value))
                                )
                            )
                            path.addLine(
                                to: CGPoint(
                                    x: rightEdge(firstPoint.x),
                                    y: yPosition(Double(firstPoint.value))
                                )
                            )

                            points.dropFirst().forEach { point in
                                path.addLine(
                                    to: CGPoint(
                                        x: leftEdge(point.x),
                                        y: yPosition(Double(point.value))
                                    )
                                )
                                path.addLine(
                                    to: CGPoint(
                                        x: rightEdge(point.x),
                                        y: yPosition(Double(point.value))
                                    )
                                )
                            }
                        }
                    }

                    ZStack {
                        ForEach(Array(axisValues.enumerated()), id: \.offset) { pair in
                            Path { path in
                                let y = yPosition(Double(pair.element))
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                            }
                            .stroke(AppColors.timelineGrid, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }

                        ForEach(lineTimelines) { eventKindTimeline in
                            pathForPoints(pointsForTimeline(eventKindTimeline.timeline))
                                .stroke(
                                    visibleTimelines.isEmpty
                                        ? processedTint
                                        : eventKindColor(eventKindTimeline.eventKind).opacity(0.92),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                                )
                        }
                    }
                    .clipped()
                }
                .frame(height: 72)
            }
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.insetBackground)
            )
            .animation(progressAnimation, value: timeline.bucketProgress)
            .animation(progressAnimation, value: timeline.recordCounts)
            .animation(progressAnimation, value: eventKindTimelines)

            timelineXAxis(windowDuration: timeline.windowDuration)
        }
    }

    @ViewBuilder
    private func eventKindBreakdownRow(
        _ breakdown: [SchedulerEventKindLegendItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(copy.eventBreakdownTitle)
                .font(Styles.Fonts.footnoteSemibold)

            ForEach(breakdown) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(eventKindColor(item.eventKind))
                        .frame(width: 8, height: 8)

                    Text(copy.telemetryLabel(item.eventKind))
                        .font(Styles.Fonts.caption)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if item.queuedDepth > 0 {
                        Text("\(copy.queuedTitle): \(item.queuedDepth)")
                            .font(Styles.Fonts.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    if item.activeRecordCount > 0 || item.activeRequestCount > 0 {
                        Text(
                            copy.usesConsumerText
                                ? "Working: \(item.activeRecordCount) items / \(item.activeRequestCount) tasks"
                                : "Active: \(item.activeRecordCount) records / \(item.activeRequestCount) requests"
                        )
                            .font(Styles.Fonts.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    if item.processedRecordsInWindow > 0 {
                        Text(
                            copy.usesConsumerText
                                ? "\(item.processedRecordsLast60Seconds) completed / min"
                                : "\(item.processedRecordsLast60Seconds) processed / 60s"
                        )
                            .font(Styles.Fonts.caption)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(String(format: "%.2f/s", item.recordsPerSecond))
                            .font(Styles.Fonts.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    if item.oldestQueuedAgeSeconds > 0 {
                        Text(String(format: copy.usesConsumerText ? "Longest wait: %.1fs" : "Oldest: %.1fs", item.oldestQueuedAgeSeconds))
                            .font(Styles.Fonts.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.cardBackground.opacity(0.72))
                )
            }
        }
    }

    @ViewBuilder
    private func activeBatchRow(
        _ batch: AISchedulerActiveBatchSnapshot
    ) -> some View {
        let memoryText = batch.estimatedMemoryBytes > 0
            ? "\(copy.usesConsumerText ? "Memory" : "Est"): \(memoryLabel(Double(batch.estimatedMemoryBytes)))"
            : nil
        let parameterLabels = copy.activeBatchParameterLabels(
            modelName: batch.modelName,
            promptTokenEstimate: batch.promptTokenEstimate,
            maxTokens: batch.maxTokens,
            maxKVSize: batch.maxKVSize,
            kvBits: batch.kvBits,
            prefillStepSize: batch.prefillStepSize
        )
        let memoryBreakdownLabels: [String] = {
            guard !copy.usesConsumerText else {
                return []
            }

            guard let breakdown = batch.memoryEstimateBreakdown else {
                return []
            }

            return [
                "Base \(memoryLabel(Double(breakdown.baseBytes)))",
                "Requests \(memoryLabel(Double(breakdown.requestOverheadBytes)))",
                "Prompt \(memoryLabel(Double(breakdown.promptWorkingBytes)))",
                "KV \(memoryLabel(Double(breakdown.kvCacheBytes)))",
                "Prefill \(memoryLabel(Double(breakdown.prefillAttentionBytes)))",
                String(format: "Safety %.1fx", breakdown.safetyMultiplier)
            ]
        }()

        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(eventKindColor(batch.eventKind))
                    .frame(width: 8, height: 8)

                Text("\(copy.workTypePrefix): \(copy.telemetryLabel(batch.eventKind))")
                    .font(Styles.Fonts.caption)
                    .lineLimit(1)

                if batch.source != batch.eventKind {
                    Text("\(copy.sourcePrefix): \(copy.telemetryLabel(batch.source))")
                        .font(Styles.Fonts.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(copy.usesConsumerText ? "Items: \(batch.recordCount)" : "Admitted Records: \(batch.recordCount)")
                    .font(Styles.Fonts.caption)
                Text(copy.usesConsumerText ? "Tasks: \(batch.requestCount)" : "Requests: \(batch.requestCount)")
                    .font(Styles.Fonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Text(copy.usesConsumerText ? "Group Size: \(batch.batchSize)" : "Batch Size: \(batch.batchSize)")
                    .font(Styles.Fonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
                if let memoryText {
                    Text(memoryText)
                        .font(Styles.Fonts.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Text(String(format: copy.usesConsumerText ? "Running: %.1fs" : "Runtime: %.1fs", batch.ageSeconds))
                    .font(Styles.Fonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            if !parameterLabels.isEmpty {
                Text(parameterLabels.joined(separator: " | "))
                    .font(Styles.Fonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }

            if !memoryBreakdownLabels.isEmpty {
                Text(memoryBreakdownLabels.joined(separator: " | "))
                    .font(Styles.Fonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.cardBackground.opacity(0.8))
        )
    }

    private func metricChip(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Styles.Fonts.caption)
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(Styles.Fonts.footnoteSemibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.insetBackground)
        )
    }

    private func schedulerActiveRecordSummary(
        _ snapshot: AISchedulerStatsSnapshot
    ) -> String {
        copy.schedulerActiveRecordSummary(
            activeRecordCount: snapshot.activeRecordCount,
            activeRecordCap: snapshot.activeRecordCap,
            activeBatchCount: snapshot.activeBatchCount
        )
    }

    private func schedulerActiveRecordValue(
        _ snapshot: AISchedulerStatsSnapshot
    ) -> String {
        copy.activeRecordValue(
            activeRecordCount: snapshot.activeRecordCount,
            activeRecordCap: snapshot.activeRecordCap
        )
    }

    private func eventKindLegendItems(
        for bucket: AISchedulerBucketSnapshot
    ) -> [SchedulerEventKindLegendItem] {
        let breakdownByKind: [String: AISchedulerEventKindSnapshot] = Dictionary(
            uniqueKeysWithValues: bucket.eventKindBreakdown.map { ($0.eventKind, $0) }
        )
        let timelinesByKind: [String: AISchedulerEventKindTimelineSnapshot] = Dictionary(
            uniqueKeysWithValues: bucket.processedRecordsTimelineByKind.map { ($0.eventKind, $0) }
        )
        let eventKinds = Array(Set(breakdownByKind.keys).union(timelinesByKind.keys))

        return eventKinds
            .map { eventKind in
                let breakdown = breakdownByKind[eventKind]
                let timeline = timelinesByKind[eventKind]
                let processedRecordsInWindow = timeline?.timeline.recordCounts.reduce(0, +) ?? 0

                return SchedulerEventKindLegendItem(
                    id: eventKind,
                    eventKind: eventKind,
                    queuedDepth: breakdown?.queuedDepth ?? 0,
                    activeRequestCount: breakdown?.activeRequestCount ?? 0,
                    activeRecordCount: breakdown?.activeRecordCount ?? 0,
                    oldestQueuedAgeSeconds: breakdown?.oldestQueuedAgeSeconds ?? 0,
                    processedRecordsLast60Seconds: timeline?.processedRecordsLast60Seconds ?? 0,
                    processedRecordsInWindow: processedRecordsInWindow,
                    recordsPerSecond: timeline?.recordsPerSecond ?? 0
                )
            }
            .filter {
                $0.queuedDepth > 0
                    || $0.activeRecordCount > 0
                    || $0.activeRequestCount > 0
                    || $0.processedRecordsInWindow > 0
            }
            .sorted { lhs, rhs in
                let lhsTotal = lhs.queuedDepth + lhs.activeRecordCount + lhs.processedRecordsInWindow
                let rhsTotal = rhs.queuedDepth + rhs.activeRecordCount + rhs.processedRecordsInWindow

                guard lhsTotal == rhsTotal else {
                    return lhsTotal > rhsTotal
                }

                return lhs.eventKind < rhs.eventKind
            }
    }

    private func eventKindColor(
        _ eventKind: String
    ) -> Color {
        AppColors.analyticsTagColor(for: "scheduler-\(eventKind)")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(AppColors.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }

    private func memoryLabel(
        _ bytes: Double
    ) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GiB", bytes / 1_073_741_824)
        }

        return String(format: "%.1f MiB", bytes / 1_048_576)
    }

    private func memoryPressureColor(
        _ pressure: Double
    ) -> Color {
        if pressure >= 0.9 {
            return AppColors.danger
        }

        if pressure >= 0.7 {
            return AppColors.recordIdle
        }

        return AppColors.success
    }

    private func lastSeenLabel(
        _ date: Date
    ) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func timelineXAxis(
        windowDuration: TimeInterval
    ) -> some View {
        HStack {
            Text(agoLabel(windowDuration))
                .font(Styles.Fonts.caption)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(agoLabel(windowDuration / 2))
                .font(Styles.Fonts.caption)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text("Now")
                .font(Styles.Fonts.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func durationLabel(
        _ seconds: TimeInterval
    ) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return String(format: "%.1fm", minutes)
        }

        return String(format: "%.1fh", minutes / 60)
    }

    private func agoLabel(
        _ seconds: TimeInterval
    ) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s ago"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return String(format: "%.1fm ago", minutes)
        }

        return String(format: "%.1fh ago", minutes / 60)
    }
}
