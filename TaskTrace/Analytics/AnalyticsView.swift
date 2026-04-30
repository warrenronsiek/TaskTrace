//
//  AnalyticsView.swift
//  TaskTrace
//
//  Created by Codex on 3/13/26.
//

import SwiftUI

struct AnalyticsView: View {
    private let tagSectionPadding: CGFloat = 20
    private let tagFlowInset: CGFloat = 4
    @ObservedObject var analyticsStore: AnalyticsStore
    @State private var tagFlowWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding(24)
                .frame(width: geometry.size.width, alignment: .leading)
            }
        }
        .navigationTitle("Analytics")
        .task {
            await analyticsStore.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if analyticsStore.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        } else if analyticsStore.timeline.isEmpty {
            Text("No Data")
                .font(Styles.Fonts.title3Semibold)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 60)
        } else {
            summarySection
            heatmapSection
            recentBarsSection
            tagFilterSection
        }
    }

    private var tagFilterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags")
                .font(Styles.Fonts.headline)

            if tagFlowWidth > 0 {
                TagTileFlowLayout(horizontalSpacing: 10, verticalSpacing: 10) {
                    selectorButton(
                        title: "All",
                        icon: "tray.full",
                        tint: AppColors.analyticsTagColor(for: "All"),
                        isSelected: analyticsStore.selectedTags.isEmpty
                    ) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            analyticsStore.clearTagFilters()
                        }
                    }

                    ForEach(analyticsStore.availableTags, id: \.self) { tag in
                        selectorButton(
                            title: tag,
                            icon: "tag",
                            tint: AppColors.analyticsTagColor(for: tag),
                            isSelected: analyticsStore.selectedTags.contains(tag)
                        ) {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                                analyticsStore.toggleTagFilter(tag)
                            }
                        }
                    }
                }
                .frame(width: max(tagFlowWidth - (tagSectionPadding * 2) - (tagFlowInset * 2), 0), alignment: .leading)
                .padding(tagFlowInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(tagSectionPadding)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        tagFlowWidth = geometry.size.width
                    }
                    .onChange(of: geometry.size.width) { _, nextWidth in
                        tagFlowWidth = nextWidth
                    }
            }
        }
    }

    private var summarySection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(analyticsStore.summaryMetrics.trackedPercentage * 100, specifier: "%.1f")%")
                    .font(Styles.Fonts.analyticsMetricValue)
                Text("Tracked")
                    .font(Styles.Fonts.headline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 8) {
                Text("\(analyticsStore.summaryMetrics.taggedPercentage * 100, specifier: "%.1f")%")
                    .font(Styles.Fonts.analyticsMetricValue)
                Text("Tagged")
                    .font(Styles.Fonts.headline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Last 365 Days")
                .font(Styles.Fonts.headline)

            AnalyticsHeatmap(
                days: analyticsStore.heatmapDays,
                selectedTags: analyticsStore.selectedTags
            )
        }
        .padding(20)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var recentBarsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Last 14 Days")
                .font(Styles.Fonts.headline)

            if analyticsStore.barSegments.contains(where: { $0.duration > 0 }) {
                AnalyticsRecentBars(
                    segments: analyticsStore.barSegments,
                    availableTags: analyticsStore.barSegmentsTags
                )
            } else {
                Text("No recent tracked time.")
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(20)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 20))
    }

    private func selectorButton(
        title: String,
        icon: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolVariant(.fill)
                    .foregroundStyle(isSelected ? tint : tint.opacity(0.94))
                Text(title)
                    .font(Styles.Fonts.sidebarSecondaryAction)
                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.chipBackground)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tint.opacity(0.12))
                    }
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected ? tint.opacity(0.85) : tint.opacity(0.28),
                            lineWidth: isSelected ? 1.3 : 0.9
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }

}

private struct TagTileFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat = 8, verticalSpacing: CGFloat = 8) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxLineWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        let availableWidth = proposal.width ?? 0

        for subview in subviews {
            let chipSize = subview.sizeThatFits(.unspecified)
            let spacing = x == 0 ? 0 : horizontalSpacing
            let wrapped = availableWidth > 0 && x + spacing + chipSize.width > availableWidth

            if wrapped {
                maxLineWidth = max(maxLineWidth, x)
                x = 0
                y += currentRowHeight + verticalSpacing
                currentRowHeight = 0
            }

            x += spacing + chipSize.width
            currentRowHeight = max(currentRowHeight, chipSize.height)
            maxLineWidth = max(maxLineWidth, x)
        }

        return CGSize(
            width: availableWidth > 0 ? availableWidth : maxLineWidth,
            height: y + currentRowHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        let availableWidth = bounds.width

        for subview in subviews {
            let chipSize = subview.sizeThatFits(.unspecified)
            let spacing = x == 0 ? 0 : horizontalSpacing
            let wrapped = x + spacing + chipSize.width > availableWidth

            if wrapped && !x.isZero {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: bounds.minX + x + spacing, y: bounds.minY + y),
                proposal: ProposedViewSize(chipSize)
            )

            x += spacing + chipSize.width
            rowHeight = max(rowHeight, chipSize.height)
        }
    }
}

private struct AnalyticsHeatmap: View {
    struct WeekColumn: Identifiable {
        let index: Int
        let monthLabel: String
        let days: [AnalyticsStore.HeatmapDay?]

        var id: Int { index }
    }

    let days: [AnalyticsStore.HeatmapDay]
    let selectedTags: Set<String>

    @State private var hoveredDay: AnalyticsStore.HeatmapDay?

    private let calendar = Calendar(identifier: .gregorian)
    private let cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 6
    private let weekdayLabelWidth: CGFloat = 36
    private let monthLabelHeight: CGFloat = 14

    private var weekColumns: [WeekColumn] {
        guard
            let firstDate = days.map(\.date).min().map(calendar.startOfDay(for:)),
            let lastDate = days.map(\.date).max().map(calendar.startOfDay(for:)),
            let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: firstDate)?.start,
            let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: lastDate)?.start
        else {
            return []
        }

        let dayLookup = Dictionary(
            uniqueKeysWithValues: days.map { (calendar.startOfDay(for: $0.date), $0) }
        )
        let weekCount = calendar.dateComponents([.weekOfYear], from: firstWeekStart, to: lastWeekStart).weekOfYear ?? 0

        return (0...weekCount).compactMap { index in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: index, to: firstWeekStart) else {
                return nil
            }

            let columnDays = (0..<7).map { offset in
                calendar.date(byAdding: .day, value: offset, to: weekStart)
                    .map(calendar.startOfDay(for:))
                    .flatMap { dayLookup[$0] }
            }
            let inRangeDays = columnDays.compactMap { $0 }
            let monthLabel =
                if index == 0 {
                    inRangeDays.first.map { Self.monthFormatter.string(from: $0.date) } ?? ""
                } else if let boundaryDay = inRangeDays.first(where: { calendar.component(.day, from: $0.date) == 1 }) {
                    Self.monthFormatter.string(from: boundaryDay.date)
                } else {
                    ""
                }

            return WeekColumn(
                index: index,
                monthLabel: monthLabel,
                days: columnDays
            )
        }
    }

    private var maxDuration: Int {
        max(days.map(\.duration).max() ?? 0, 1)
    }

    private var weekContentWidth: CGFloat {
        CGFloat(weekColumns.count) * cellSize + CGFloat(max(weekColumns.count - 1, 0)) * cellSpacing
    }

    private var heatmapGridHeight: CGFloat {
        CGFloat(7) * cellSize + CGFloat(6) * cellSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hoverText)
                .font(Styles.Fonts.captionSemibold)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { weekday in
                        Text(weekday)
                            .font(Styles.Fonts.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(height: cellSize, alignment: .center)
                    }
                }
                .frame(width: weekdayLabelWidth, alignment: .leading)

                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .bottom, spacing: cellSpacing) {
                                    ForEach(weekColumns) { column in
                                        Color.clear
                                            .frame(width: cellSize, height: monthLabelHeight)
                                            .overlay(alignment: .leading) {
                                                if !column.monthLabel.isEmpty {
                                                    Text(column.monthLabel)
                                                        .font(Styles.Fonts.caption2Semibold)
                                                        .foregroundStyle(AppColors.textSecondary)
                                                        .fixedSize(horizontal: true, vertical: false)
                                                }
                                            }
                                    }
                                }

                                HStack(alignment: .top, spacing: cellSpacing) {
                                    ForEach(weekColumns) { column in
                                        VStack(spacing: cellSpacing) {
                                            ForEach(Array(column.days.enumerated()), id: \.offset) { entry in
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(color(for: entry.element))
                                                    .frame(width: cellSize, height: cellSize)
                                                    .help(entry.element.map {
                                                        "\(Self.dayFormatter.string(from: $0.date)): \(Self.durationFormatter.string(from: TimeInterval($0.duration)) ?? "0m")"
                                                    } ?? "")
                                                    .onHover { isHovering in
                                                        hoveredDay = isHovering ? entry.element : (hoveredDay?.id == entry.element?.id ? nil : hoveredDay)
                                                    }
                                            }
                                        }
                                        .id(column.id)
                                    }
                                }
                            }
                            .frame(width: max(weekContentWidth, geometry.size.width), alignment: .trailing)
                        }
                        .onAppear {
                            guard let lastColumnID = weekColumns.last?.id else {
                                return
                            }

                            DispatchQueue.main.async {
                                proxy.scrollTo(lastColumnID, anchor: .trailing)
                            }
                        }
                        .onChange(of: weekColumns.last?.id) { _, nextID in
                            guard let nextID else {
                                return
                            }

                            DispatchQueue.main.async {
                                proxy.scrollTo(nextID, anchor: .trailing)
                            }
                        }
                    }
                }
                .frame(height: heatmapGridHeight + monthLabelHeight + 10)
            }
        }
    }

    private func color(for day: AnalyticsStore.HeatmapDay?) -> Color {
        guard let day else {
            return AppColors.insetBackground
        }

        guard day.duration > 0 else {
            return AppColors.insetBackground
        }

        let intensity = min(Double(day.duration) / Double(maxDuration), 1)
        return AppColors.analyticsTagColor(for: selectedTags.count == 1 ? selectedTags.first ?? "All" : "All")
            .opacity(0.28 + intensity * 0.72)
    }

    private var hoverText: String {
        guard let hoveredDay else {
            return "Hover a day to inspect tracked time."
        }

        let duration = Self.durationFormatter.string(from: TimeInterval(hoveredDay.duration)) ?? "0m"
        return "\(Self.dayFormatter.string(from: hoveredDay.date)) • \(duration)"
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLL"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()
}

private struct AnalyticsRecentBars: View {
    struct DayColumn: Identifiable {
        let date: Date
        let segments: [AnalyticsStore.BarSegment]

        var id: Date { date }
    }

    let segments: [AnalyticsStore.BarSegment]
    let availableTags: [String]
    private let axisWidth: CGFloat = 44
    private let chartSpacing: CGFloat = 10
    private let xAxisLabelHeight: CGFloat = 18
    private let gridStepDuration = 7_200

    private var groupedDays: [DayColumn] {
        Dictionary(grouping: segments, by: \.date)
            .map { date, value in
                DayColumn(
                    date: date,
                    segments: value.sorted { lhs, rhs in
                        let lhsIndex = availableTags.firstIndex(of: lhs.tag) ?? 0
                        let rhsIndex = availableTags.firstIndex(of: rhs.tag) ?? 0
                        return lhsIndex < rhsIndex
                    }
                )
            }
            .sorted { $0.date < $1.date }
    }

    private var maxDuration: Int {
        max(
            groupedDays.map { day in
                day.segments.reduce(into: 0) { total, segment in
                    total += segment.duration
                }
            }.max() ?? 0,
            1
        )
    }

    private var axisTicks: [Int] {
        stride(from: chartMaxDuration, through: 0, by: -gridStepDuration).map { $0 }
    }

    private var chartMaxDuration: Int {
        max(
            ((maxDuration + gridStepDuration - 1) / gridStepDuration) * gridStepDuration,
            gridStepDuration
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GeometryReader { geometry in
                let chartHeight = max(geometry.size.height - xAxisLabelHeight, 1)
                let chartWidth = max(geometry.size.width - axisWidth - chartSpacing, 1)
                let barWidth = max(
                    (chartWidth - CGFloat(max(groupedDays.count - 1, 0)) * 10) / CGFloat(max(groupedDays.count, 1)),
                    24
                )

                HStack(alignment: .top, spacing: chartSpacing) {
                    ZStack(alignment: .leading) {
                        ForEach(axisTicks, id: \.self) { tick in
                            let yPosition =
                                chartMaxDuration > 0
                                ? chartHeight - CGFloat(tick) / CGFloat(chartMaxDuration) * chartHeight
                                : chartHeight

                            Text(axisLabel(for: tick))
                                .font(Styles.Fonts.caption2)
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(width: axisWidth, alignment: .trailing)
                                .position(x: axisWidth / 2, y: yPosition)
                        }
                    }
                    .frame(width: axisWidth, height: chartHeight)

                    ZStack(alignment: .topLeading) {
                        ForEach(axisTicks, id: \.self) { tick in
                            let yPosition =
                                chartMaxDuration > 0
                                ? chartHeight - CGFloat(tick) / CGFloat(chartMaxDuration) * chartHeight
                                : chartHeight

                            Rectangle()
                                .fill(AppColors.textSecondary.opacity(tick == 0 ? 0.28 : 0.12))
                                .frame(height: 1)
                                .offset(y: yPosition)
                        }

                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(groupedDays, id: \.date) { day in
                                VStack(spacing: 0) {
                                    VStack(spacing: 0) {
                                        Spacer(minLength: 0)

                                        ForEach(day.segments) { segment in
                                            Rectangle()
                                                .fill(AppColors.analyticsTagColor(for: segment.tag))
                                                .frame(
                                                    width: barWidth,
                                                    height: max(
                                                        CGFloat(segment.duration) / CGFloat(chartMaxDuration) * chartHeight,
                                                        segment.duration > 0 ? 6 : 0
                                                    )
                                                )
                                        }
                                    }
                                    .frame(height: chartHeight, alignment: .bottom)
                                    .frame(width: barWidth)
                                    .clipShape(
                                        UnevenRoundedRectangle(
                                            cornerRadii: .init(
                                                topLeading: 10,
                                                bottomLeading: 0,
                                                bottomTrailing: 0,
                                                topTrailing: 10
                                            ),
                                            style: .continuous
                                        )
                                    )

                                    Text(day.date, format: .dateTime.month(.abbreviated).day())
                                        .font(Styles.Fonts.caption2)
                                        .foregroundStyle(AppColors.textSecondary)
                                        .frame(height: xAxisLabelHeight, alignment: .bottom)
                                }
                            }
                        }
                    }
                    .frame(width: chartWidth, height: geometry.size.height, alignment: .bottomLeading)
                }
            }
            .frame(height: 240)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: segments)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: availableTags)
    }

    private func axisLabel(for duration: Int) -> String {
        Self.durationFormatter.string(from: TimeInterval(duration)) ?? "0m"
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()
}
