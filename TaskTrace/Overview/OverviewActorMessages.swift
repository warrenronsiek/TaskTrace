//
//  OverviewActorMessages.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation

struct OverviewEditedDurationSetRequested: Sendable {
    let overviewID: Int64
    let duration: Int
}

struct OverviewTitleSetRequested: Sendable {
    let overviewID: Int64
    let title: String
}

struct OverviewSummarySetRequested: Sendable {
    let overviewID: Int64
    let summary: String
}

struct OverviewTagSetRequested: Sendable {
    let overviewID: Int64
    let tagID: Int64
}

struct OverviewMergeRequested: Sendable {
    let overviewID: Int64
    let otherOverviewID: Int64
}

struct OverviewMergeComputationRequested: Sendable {
    let mergedOverviewID: Int64
    let firstOverview: LoadedOverview
    let secondOverview: LoadedOverview
    let firstDuration: Int
    let secondDuration: Int
    let activityIDs: [Int64]
}

struct OverviewMergeResolved: Sendable {
    let mergedOverviewID: Int64
    let firstOverview: LoadedOverview
    let secondOverview: LoadedOverview
    let firstDuration: Int
    let secondDuration: Int
    let activityIDs: [Int64]
    let decision: ActivityOverviewMergeDecision
}

struct OverviewMergeFailed: Sendable {
    let firstOverviewID: Int64
    let secondOverviewID: Int64
    let errorMessage: String
}

struct OverviewDayReloadRequested: Sendable {
    let day: Date
}
