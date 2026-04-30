//
//  AnalyticsStore.swift
//  TaskTrace
//
//  Created by Codex on 3/13/26.
//

import Combine
import Foundation

@MainActor
final class AnalyticsStore: ObservableObject {
    static let untaggedName = "Untagged"
    private static let excludedBarChartTags = [untaggedName, SystemTags.inactiveName]

    struct TimelineEntry: Identifiable, Equatable {
        let date: Date
        let tags: [String: Int]

        var id: Date { date }
    }

    struct SummaryMetrics: Equatable {
        let trackedPercentage: Double
        let taggedPercentage: Double
    }

    struct HeatmapDay: Identifiable, Equatable {
        let date: Date
        let duration: Int

        var id: Date { date }
    }

    struct BarSegment: Identifiable, Equatable {
        let date: Date
        let tag: String
        let duration: Int

        var id: String {
            "\(date.timeIntervalSinceReferenceDate)-\(tag)"
        }
    }

    @Published private(set) var timeline: [TimelineEntry]
    @Published private(set) var availableTags: [String]
    @Published private(set) var selectedTags: Set<String>
    @Published private(set) var isLoading: Bool
    @Published private(set) var errorMessage: String?

    private let analyticsDatabaseActor: AnalyticsDatabaseActor?
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        analyticsDatabaseActor: AnalyticsDatabaseActor?,
        now: @escaping @Sendable () -> Date,
        calendar: Calendar
    ) {
        self.analyticsDatabaseActor = analyticsDatabaseActor
        self.timeline = []
        self.availableTags = []
        self.selectedTags = []
        self.isLoading = false
        self.errorMessage = nil
        self.now = now
        self.calendar = calendar
    }

    convenience init(database: TaskTraceDatabase) {
        self.init(
            analyticsDatabaseActor: AnalyticsDatabaseActor(database: database),
            now: Date.init,
            calendar: Calendar(identifier: .gregorian)
        )
    }

    convenience init(
        database: TaskTraceDatabase,
        now: @escaping @Sendable () -> Date,
        calendar: Calendar
    ) {
        self.init(
            analyticsDatabaseActor: AnalyticsDatabaseActor(database: database),
            now: now,
            calendar: calendar
        )
    }

    init(previewTimeline: [TimelineEntry], selectedTags: Set<String> = []) {
        let availableTags = Array(
            Set(previewTimeline.flatMap { $0.tags.keys })
        ).sorted(using: KeyPathComparator(\.self))

        self.analyticsDatabaseActor = nil
        self.timeline = previewTimeline.sorted { $0.date < $1.date }
        self.availableTags = availableTags
        self.isLoading = false
        self.errorMessage = nil
        self.selectedTags = Set(availableTags).intersection(selectedTags)
        self.now = Date.init
        self.calendar = Calendar(identifier: .gregorian)
    }

    func load() async {
        guard let analyticsDatabaseActor else {
            return
        }

        isLoading = true

        do {
            let endDate = calendar.startOfDay(for: now())
            let startDate = calendar.date(byAdding: .day, value: -364, to: endDate) ?? endDate
            let rows = try await analyticsDatabaseActor.activityAggregation(startDate: startDate, endDate: endDate)

            let timeline = try rows.reduce(into: [Date: [String: Int]]()) { result, row in
                let date = try Self.sqlDateParser.parse(row.date)
                let tagName = row.tagName ?? Self.untaggedName
                result[date, default: [:]][tagName] = row.duration ?? 0
            }

            self.timeline = timeline
                .map { TimelineEntry(date: $0.key, tags: $0.value) }
                .sorted { $0.date < $1.date }
            self.availableTags = Array(
                Set(rows.map { $0.tagName ?? Self.untaggedName })
            ).sorted { lhs, rhs in
                if lhs == Self.untaggedName {
                    return false
                }

                if rhs == Self.untaggedName {
                    return true
                }

                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            self.errorMessage = nil

            self.selectedTags = Set(self.selectedTags).intersection(Set(availableTags))
        } catch {
            timeline = []
            availableTags = []
            selectedTags = []
            errorMessage = "Could not load analytics."
        }

        isLoading = false
    }

    func toggleTagFilter(_ tag: String) {
        var updatedTags = selectedTags
        if updatedTags.contains(tag) {
            updatedTags.remove(tag)
        } else {
            updatedTags.insert(tag)
        }

        selectedTags = updatedTags
    }

    func clearTagFilters() {
        selectedTags.removeAll()
    }

    var summaryMetrics: SummaryMetrics {
        guard let firstDate = timeline.first?.date, let lastDate = timeline.last?.date else {
            return SummaryMetrics(trackedPercentage: 0, taggedPercentage: 0)
        }

        let totalTrackedSeconds = timeline.reduce(into: 0) { total, entry in
            total += entry.tags.values.reduce(0, +)
        }
        let totalUnknownSeconds = timeline.reduce(into: 0) { total, entry in
            total += entry.tags[Self.untaggedName] ?? 0
        }
        let daySpan = calendar.dateComponents([.day], from: firstDate, to: lastDate).day ?? 0
        let weeksInRange = max(Double(daySpan + 1) / 7, 1)
        let trackedPercentage = Double(totalTrackedSeconds) / (weeksInRange * 40 * 3_600)
        let taggedPercentage =
            totalTrackedSeconds > 0
            ? 1 - Double(totalUnknownSeconds) / Double(totalTrackedSeconds)
            : 0

        return SummaryMetrics(
            trackedPercentage: trackedPercentage,
            taggedPercentage: taggedPercentage
        )
    }

    var heatmapDays: [HeatmapDay] {
        let endDate = calendar.startOfDay(for: now())
        let startDate = calendar.date(byAdding: .day, value: -364, to: endDate) ?? endDate
        let timelineLookup = Dictionary(uniqueKeysWithValues: timeline.map { ($0.date, $0) })

        return (0..<365).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }

            let duration = {
                if selectedTags.isEmpty {
                    return timelineLookup[date]?.tags.values.reduce(0, +) ?? 0
                }

                return timelineLookup[date]?
                    .tags
                    .filter { selectedTags.contains($0.key) }
                    .values
                    .reduce(0, +) ?? 0
            }()

            return HeatmapDay(date: date, duration: duration)
        }
    }

    var barSegments: [BarSegment] {
        guard let startDate = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now())) else {
            return []
        }

        let tagsToUse = barSegmentsTags

        return timeline
            .filter { $0.date >= startDate }
            .flatMap { entry in
                tagsToUse.map { tag in
                    BarSegment(
                        date: entry.date,
                        tag: tag,
                        duration: entry.tags[tag] ?? 0
                    )
                }
            }
    }

    var barChartTags: [String] {
        availableTags.filter { tag in
            !Self.excludedBarChartTags.contains {
                $0.localizedCaseInsensitiveCompare(tag) == .orderedSame
            }
        }
    }

    var barSegmentsTags: [String] {
        guard !selectedTags.isEmpty else {
            return barChartTags
        }

        return availableTags.filter { selectedTags.contains($0) }
    }

    private static let sqlDateParser = Date.ParseStrategy(
        format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: .current,
        calendar: Calendar(identifier: .gregorian)
    )
}
