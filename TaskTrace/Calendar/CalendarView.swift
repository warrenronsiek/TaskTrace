//
//  CalendarView.swift
//  TaskTrace
//
//  Created by Codex on 3/13/26.
//

import MijickCalendarView
import SwiftUI

@MainActor
struct CalendarView: View {
    @ObservedObject var calendarStore: CalendarStore
    @ObservedObject var activityStore: ActivityStore
    @ObservedObject var overviewStore: OverviewStore
    @ObservedObject var tagsStore: TagsStore
    @Binding var revealedActivityID: Int64?
    @Binding var timelineFocusDate: Date?
    @Binding var selectedPage: ContentView.AppPage?
    @State private var selectedDate: Date?
    @State private var selectedRange: MDateRange?
    @State private var hoveredBlockID: Int64?
    @State private var mergeSourceBlockID: Int64?
    @State private var mergeSourceOverviewID: Int64?
    @State private var mergingOverviewIDs: Set<Int64> = []
    @State private var measuredBlockHeights: [Int64: CGFloat] = [:]
    @State private var areAllBlocksExpanded = false
    private let calendarWidth: CGFloat = 360
    private let hourHeight: CGFloat = 90
    private let timeLabelWidth: CGFloat = 44
    private let timelineInset: CGFloat = 48

    var body: some View {
        let calendarID = "\(calendarStore.startMonth.timeIntervalSinceReferenceDate)-\(selectedDate?.timeIntervalSinceReferenceDate ?? -1)"

        HStack(alignment: .top, spacing: 24) {
            MCalendarView(
                selectedDate: Binding(
                    get: { selectedDate },
                    set: { newValue in
                        selectedDate = newValue

                        guard let newValue else {
                            return
                        }

                        Task {
                            await calendarStore.setSelectedDate(newValue)
                            selectedDate = calendarStore.selectedDate
                        }
                    }
                ),
                selectedRange: $selectedRange,
                configBuilder: {
                    $0
                        .startMonth(calendarStore.startMonth)
                        .scrollTo(date: selectedDate ?? calendarStore.selectedDate)
                        .monthLabel { CalendarMonthLabel(month: $0) }
                        .weekdaysView { CalendarWeekdaysView() }
                        .dayView { date, isCurrentMonth, selectedDate, selectedRange in
                            CalendarDayView(
                                date: date,
                                isCurrentMonth: isCurrentMonth,
                                selectedDate: selectedDate,
                                selectedRange: selectedRange,
                                isAvailable: calendarStore.isAvailable(date)
                            )
                        }
                }
            )
            .id(calendarID)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(AppColors.recordIdle.opacity(0.08))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                    }
                    .shadow(color: AppColors.recordIdle.opacity(0.10), radius: 20, y: 8)
            )
            .frame(width: calendarWidth, alignment: .topLeading)
            .frame(minHeight: 420, alignment: .topLeading)

            expandAllButton

            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage = overviewStore.errorMessage {
                    Text(errorMessage)
                        .font(Styles.Fonts.footnote)
                        .foregroundStyle(AppColors.danger)
                }

                GeometryReader { geometry in
                    let timelineWidth = max(geometry.size.width - timeLabelWidth - 12 - timelineInset - 16, 320)

                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            hourAnnotations(width: timelineWidth)
                            timelineBlocks(width: timelineWidth)
                        }
                        .frame(maxWidth: .infinity, minHeight: stretchedYOffset(for: 24 * 3600, width: timelineWidth), alignment: .topLeading)
                        .padding(.leading, timeLabelWidth + 12)
                    }
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .navigationTitle("Timeline")
        .overlay {
            if calendarStore.isLoading {
                ProgressView()
            }
        }
        .task {
            selectedDate = calendarStore.selectedDate
            await calendarStore.loadAvailableDates()
        }
        .onAppear {
            selectedDate = calendarStore.selectedDate
        }
        .onChange(of: timelineFocusDate) { _, focusDate in
            guard let focusDate else {
                return
            }

            Task {
                await calendarStore.setSelectedDate(focusDate)
                await MainActor.run {
                    timelineFocusDate = nil
                }
            }
        }
        .onChange(of: calendarStore.selectedDate) { _, newValue in
            selectedDate = newValue
            resetInlineOverviewState()
        }
        .onChange(of: calendarStore.timelineBlocks) { _, newBlocks in
            reconcileInlineOverviewState(with: newBlocks)
        }
    }

    private var expandAllButton: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 120)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    if areAllBlocksExpanded || revealedActivityID != nil {
                        areAllBlocksExpanded = false
                        revealedActivityID = nil
                    } else {
                        areAllBlocksExpanded = true
                    }
                }
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: (areAllBlocksExpanded || revealedActivityID != nil) ? "arrow.down" : "arrow.up")
                        .font(.system(size: 12, weight: .semibold))

                    Rectangle()
                        .fill(AppColors.timelineGrid)
                        .frame(width: 1, height: 28)

                    Image(systemName: (areAllBlocksExpanded || revealedActivityID != nil) ? "arrow.up" : "arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 38, height: 92)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                        }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .frame(width: 38)
        .frame(maxHeight: .infinity)
    }

    private func hourAnnotations(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(0...23), id: \.self) { hour in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("\(hour):00")
                            .font(Styles.Fonts.footnote)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: timeLabelWidth, alignment: .leading)
                        Rectangle()
                            .fill(AppColors.timelineGrid)
                            .frame(height: 1)
                    }
                    .offset(y: stretchedYOffset(for: hour * 3600, width: width))
                }
            }
        }
    }

    private func timelineBlocks(width: CGFloat) -> some View {
        let availableTags = tagsStore.tags.filter { !SystemTags.isProtected($0.id) }
        let blocks = calendarStore.timelineBlocks

        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: width + timelineInset, height: stretchedYOffset(for: 24 * 3600, width: width))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard mergingOverviewIDs.isEmpty else {
                        return
                    }

                    mergeSourceBlockID = nil
                    mergeSourceOverviewID = nil
                }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.indices), id: \.self) { index in
                    let block = blocks[index]
                    let previousEnd = index > 0 ? blocks[index - 1].endSecond : 0
                    let gapHeight = max(CGFloat(block.startSecond - previousEnd) * secondHeight, 0)
                    let overview = block.overviewID.flatMap { overviewID in
                        overviewStore.overviews.first { $0.id == overviewID }
                    }
                    let overviewID = overview?.id
                    let displayHeight = displayedHeight(
                        for: block,
                        width: width,
                        sourceActivityCount: overviewID.map { overviewStore.sourceActivities(for: $0).count } ?? 0
                    )

                    if gapHeight > 0 {
                        Color.clear
                            .frame(height: gapHeight)
                    }

                    TimelineOverviewBlock(
                        block: block,
                        width: width,
                        displayHeight: displayHeight,
                        overview: overview,
                        tags: availableTags,
                        duration: overviewID.map { overviewStore.effectiveDuration(for: $0) } ?? 0,
                        sourceActivities: overviewID.map { overviewStore.sourceActivities(for: $0) } ?? [],
                        isExpanded: overviewID != nil && isBlockExpanded(block: block),
                        isMergeModeActive: mergeSourceOverviewID != nil,
                        isMergeInFlight: !mergingOverviewIDs.isEmpty,
                        isMergeSource: mergeSourceBlockID == block.id,
                        isMergeCandidate: mergeSourceOverviewID != nil && overviewID != nil && overviewID != mergeSourceOverviewID,
                        isMergePending: overviewID.map { mergingOverviewIDs.contains($0) } ?? false,
                        onHover: { isHovering in
                            guard overviewID != nil else {
                                return
                            }

                            if isHovering {
                                hoveredBlockID = block.id
                            } else if hoveredBlockID == block.id {
                                hoveredBlockID = nil
                            }
                        },
                        onSaveTitle: { newTitle in
                            guard let overviewID else {
                                return
                            }

                            await overviewStore.setTitle(overviewID: overviewID, title: newTitle)
                        },
                        onSaveSummary: { newSummary in
                            guard let overviewID else {
                                return
                            }

                            await overviewStore.setSummary(overviewID: overviewID, summary: newSummary)
                        },
                        onSaveDuration: { newDuration in
                            guard let overviewID else {
                                return
                            }

                            await overviewStore.setEditedDuration(overviewID: overviewID, duration: newDuration)
                        },
                        onSelectTag: { newTagID in
                            guard let overviewID else {
                                return
                            }

                            await overviewStore.setTag(overviewID: overviewID, tagID: newTagID)
                        },
                        onBeginMerge: {
                            guard let overviewID else {
                                return
                            }

                            mergeSourceBlockID = block.id
                            mergeSourceOverviewID = overviewID
                        },
                        onCancelMerge: {
                            mergeSourceBlockID = nil
                            mergeSourceOverviewID = nil
                            mergingOverviewIDs = []
                        },
                        onSelectMergeTarget: {
                            guard let mergeSourceOverviewID, let overviewID, mergeSourceOverviewID != overviewID else {
                                return
                            }

                            Task {
                                await MainActor.run {
                                    hoveredBlockID = nil
                                    mergingOverviewIDs = [mergeSourceOverviewID, overviewID]
                                }

                                await overviewStore.mergeOverviews(overviewID: mergeSourceOverviewID, with: overviewID)

                                await MainActor.run {
                                    mergeSourceBlockID = nil
                                    self.mergeSourceOverviewID = nil
                                    mergingOverviewIDs = []
                                }
                            }
                        },
                        onShowActivity: { activityID in
                            activityStore.focusActivity(activityID: activityID)
                            selectedPage = .activity
                        },
                        displayIndex: { activityID in
                            overviewStore.displayIndex(for: activityID)
                        },
                        onMeasureHeight: { height in
                            let roundedHeight = height.rounded(.up)

                            guard roundedHeight > 0 else {
                                return
                            }

                            if measuredBlockHeights[block.id] != roundedHeight {
                                measuredBlockHeights[block.id] = roundedHeight
                            }
                        }
                    )
                    .padding(.leading, timelineInset)
                }

                Color.clear
                    .frame(
                        height: max(
                            CGFloat((24 * 3600) - (blocks.last?.endSecond ?? 0)) * secondHeight,
                            0
                        )
                    )
            }
            .frame(width: width + timelineInset, alignment: .topLeading)
        }
    }

    private var secondHeight: CGFloat {
        hourHeight / 3600
    }

    private func collapsedHeight(for block: CalendarStore.TimelineBlock) -> CGFloat {
        max(CGFloat(block.endSecond - block.startSecond) * secondHeight, 8)
    }

    private func displayedHeight(
        for block: CalendarStore.TimelineBlock,
        width: CGFloat,
        sourceActivityCount: Int
    ) -> CGFloat {
        let collapsedHeight = collapsedHeight(for: block)

        guard block.overviewID != nil,
              isBlockExpanded(block: block) else {
            return collapsedHeight
        }

        let measuredHeight = measuredBlockHeights[block.id] ?? estimatedExpandedHeight(
            width: width,
            sourceActivityCount: sourceActivityCount
        )

        return max(collapsedHeight, measuredHeight)
    }

    private func estimatedExpandedHeight(width: CGFloat, sourceActivityCount: Int) -> CGFloat {
        let sourceRowCount = max(Int(ceil(Double(max(sourceActivityCount, 1)) / 15.0)), 1)
        let stackedHeight = CGFloat(272 + max(sourceRowCount - 1, 0) * 32)
        let inlineHeight = CGFloat(176 + max(sourceRowCount - 1, 0) * 32)

        return width < 520 ? stackedHeight : inlineHeight
    }

    private func stretchedYOffset(for second: Int, width: CGFloat) -> CGFloat {
        let clampedSecond = max(0, min(second, 24 * 3600))
        let baseOffset = CGFloat(clampedSecond) * secondHeight
        let extraOffset = calendarStore.timelineBlocks.reduce(into: CGFloat.zero) { partial, block in
            let extraHeight = displayedHeight(
                for: block,
                width: width,
                sourceActivityCount: block.overviewID.map { overviewStore.sourceActivities(for: $0).count } ?? 0
            ) - collapsedHeight(for: block)

            guard extraHeight > 0 else {
                return
            }

            if clampedSecond >= block.endSecond {
                partial += extraHeight
                return
            }

            guard clampedSecond > block.startSecond else {
                return
            }

            let duration = max(block.endSecond - block.startSecond, 1)
            let progress = CGFloat(clampedSecond - block.startSecond) / CGFloat(duration)
            partial += extraHeight * progress
        }

        return baseOffset + extraOffset
    }

    private func isBlockExpanded(block: CalendarStore.TimelineBlock) -> Bool {
        if let revealedActivityID,
           block.activityIDs.contains(revealedActivityID) {
            return true
        }

        if mergeSourceBlockID == block.id {
            return true
        }

        if let overviewID = block.overviewID, mergingOverviewIDs.contains(overviewID) {
            return true
        }

        if areAllBlocksExpanded {
            return block.overviewID != nil
        }

        if mergeSourceOverviewID != nil {
            return hoveredBlockID == block.id
        }

        return hoveredBlockID == block.id
    }

    private func resetInlineOverviewState() {
        hoveredBlockID = nil
        mergeSourceBlockID = nil
        mergeSourceOverviewID = nil
        mergingOverviewIDs = []
        measuredBlockHeights = [:]
    }

    private func reconcileInlineOverviewState(with blocks: [CalendarStore.TimelineBlock]) {
        let blockIDs = Set(blocks.map(\.id))
        let overviewIDs = Set(blocks.compactMap(\.overviewID))

        if let hoveredBlockID, !blockIDs.contains(hoveredBlockID) {
            self.hoveredBlockID = nil
        }

        if let mergeSourceBlockID, !blockIDs.contains(mergeSourceBlockID) {
            self.mergeSourceBlockID = nil
        }

        if let mergeSourceOverviewID, !overviewIDs.contains(mergeSourceOverviewID) {
            self.mergeSourceOverviewID = nil
        }

        mergingOverviewIDs = mergingOverviewIDs.intersection(overviewIDs)
        measuredBlockHeights = Dictionary(
            uniqueKeysWithValues: measuredBlockHeights.filter { blockIDs.contains($0.key) }
        )
    }
}

@MainActor
private struct TimelineOverviewBlock: View {
    let block: CalendarStore.TimelineBlock
    let width: CGFloat
    let displayHeight: CGFloat
    let overview: OverviewStore.Overview?
    let tags: [TagRecord]
    let duration: Int
    let sourceActivities: [ActivityActor.Activity]
    let isExpanded: Bool
    let isMergeModeActive: Bool
    let isMergeInFlight: Bool
    let isMergeSource: Bool
    let isMergeCandidate: Bool
    let isMergePending: Bool
    let onHover: (Bool) -> Void
    let onSaveTitle: @MainActor @Sendable (String) async -> Void
    let onSaveSummary: @MainActor @Sendable (String) async -> Void
    let onSaveDuration: @MainActor @Sendable (Int) async -> Void
    let onSelectTag: @MainActor @Sendable (Int64) async -> Void
    let onBeginMerge: () -> Void
    let onCancelMerge: () -> Void
    let onSelectMergeTarget: () -> Void
    let onShowActivity: (Int64) -> Void
    let displayIndex: (Int64) -> Int?
    let onMeasureHeight: (CGFloat) -> Void

    var body: some View {
        let timelineColor = AppColors.timelineColor(for: block.overviewID)

        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(timelineColor)
                .overlay {
                    Rectangle()
                        .strokeBorder(
                            isExpanded || isMergeSource || isMergeCandidate
                                ? Color.white.opacity(0.28)
                                : Color.white.opacity(0.10),
                            lineWidth: isExpanded || isMergeSource || isMergeCandidate ? 1 : 0.5
                        )
                }

            if let overview, isExpanded {
                OverviewCard(
                    overview: overview,
                    isMergeModeActive: isMergeModeActive,
                    isMergeInFlight: isMergeInFlight,
                    isMergeSource: isMergeSource,
                    isMergeCandidate: isMergeCandidate,
                    isMergePending: isMergePending,
                    tags: tags,
                    duration: duration,
                    sourceActivities: sourceActivities,
                    onSaveTitle: onSaveTitle,
                    onSaveSummary: onSaveSummary,
                    onSaveDuration: onSaveDuration,
                    onSelectTag: onSelectTag,
                    onBeginMerge: onBeginMerge,
                    onCancelMerge: onCancelMerge,
                    onSelectMergeTarget: onSelectMergeTarget,
                    onShowActivity: onShowActivity,
                    displayIndex: displayIndex
                )
                .padding(8)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                onMeasureHeight(geometry.size.height + 16)
                            }
                            .onChange(of: geometry.size.height) { _, newValue in
                                onMeasureHeight(newValue + 16)
                            }
                    }
                }
                .transition(.opacity)
            } else if displayHeight > 20 {
                Text(block.title.isEmpty ? "Unassigned" : block.title)
                    .font(Styles.Fonts.footnoteSemibold)
                    .foregroundStyle(AppColors.timelineOverlayText)
                    .lineLimit(displayHeight > 52 ? 3 : 1)
                    .multilineTextAlignment(displayHeight > 52 ? .center : .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: displayHeight, alignment: displayHeight > 52 ? .center : .topLeading)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .frame(height: displayHeight, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isExpanded)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isMergePending)
    }
}

private struct CalendarMonthLabel: MonthLabel {
    let month: Date

    func createContent() -> AnyView {
        Text(getString(format: "MMMM y"))
            .font(Styles.Fonts.calendarMonthLabel)
            .foregroundStyle(AppColors.textPrimary)
            .erased()
    }
}

private struct CalendarWeekdaysView: WeekdaysView {
    func createWeekdayLabel(_ weekday: MWeekday) -> AnyWeekdayLabel {
        CalendarWeekdayLabel(weekday: weekday).erased()
    }
}

private struct CalendarWeekdayLabel: WeekdayLabel {
    let weekday: MWeekday

    func createContent() -> AnyView {
        Text(getString(with: .veryShort))
            .font(Styles.Fonts.calendarWeekdayLabel)
            .foregroundStyle(AppColors.textSecondary)
            .erased()
    }
}

private struct CalendarDayView: DayView {
    let date: Date
    let isCurrentMonth: Bool
    let selectedDate: Binding<Date?>?
    let selectedRange: Binding<MDateRange?>?
    let isAvailable: Bool
    private let calendar = Calendar(identifier: .gregorian)

    func createContent() -> AnyView {
        ZStack {
            if isSelectableAndSelected {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .fill(AppColors.recordIdle.opacity(0.24))
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.38), lineWidth: 0.8)
                    }
                    .shadow(color: AppColors.recordIdle.opacity(0.22), radius: 12, y: 5)
                    .scaleEffect(isSelectableAndSelected ? 1 : 0.82)
                    .opacity(isSelectableAndSelected ? 1 : 0)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
            }

            Text(getStringFromDay(format: "d"))
                .font(Styles.Fonts.calendarDay(isSelected: isSelectableAndSelected))
                .foregroundStyle(labelColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Circle())
        .opacity(isAvailable ? 1 : 0.35)
        .animation(.spring(response: 0.26, dampingFraction: 0.84), value: isSelectableAndSelected)
        .erased()
    }

    func onSelection() {
        guard isAvailable else {
            return
        }

        selectedDate?.wrappedValue = date
    }

    private var isSelectableAndSelected: Bool {
        guard isAvailable, let selectedDate = selectedDate?.wrappedValue else {
            return false
        }

        return calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private var labelColor: Color {
        if isSelectableAndSelected {
            return AppColors.textPrimary
        }

        return isAvailable ? AppColors.textPrimary : AppColors.textSecondary
    }
}
