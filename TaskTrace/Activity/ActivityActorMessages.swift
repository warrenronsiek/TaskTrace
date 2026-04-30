//
//  ActivityActorMessages.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation

struct DescribeImageRequest: Sendable {
    let screenshotID: Int64
    let image: Data
}

struct ImageDescribed: Sendable {
    let screenshotID: Int64
    let description: String
}

struct ReadScreenshotTextRequest: Sendable {
    let screenshotID: Int64
    let image: Data
}

struct ScreenshotTextRead: Sendable {
    let screenshotID: Int64
    let text: String
}

struct SummarizeScreenshot: Sendable {
    let screenshotID: Int64
    let description: String
    let text: String
}

struct ScreenshotSummarized: Sendable {
    let screenshotID: Int64
    let summary: String
}

struct ActivitySummaryRequested: Sendable {
    let activity: ActivityActor.Activity
}

struct ActivityCreated: Sendable {
    let activity: ActivityActor.Activity
}

struct ActivityUpdated: Sendable {
    let activity: ActivityActor.Activity
}

struct ActivityKeystrokesAppended: Sendable {
    let activityID: Int64
    let text: String
}

struct ActivityMicrophoneAppended: Sendable {
    let activityID: Int64
    let transcript: String
}

struct ActivitySummarized: Sendable {
    let activity: ActivityActor.Activity
}

struct ActivitySummaryEmbedded: Sendable {
    let activityID: Int64
    let vector: [Float]
}

struct ActivityUMAPed: Sendable {
    let activityID: Int64
    let vector: [Float]
}

struct ActivityTagAssigned: Sendable {
    let activityID: Int64
    let tagID: Int64
    let ontologyCandidateID: Int64?
}

struct ActivityTagSet: Sendable {
    let activityID: Int64
    let tagID: Int64?
}

struct ActivityDeleted: Sendable {
    let activityID: Int64
}

struct ActivityDayReloadRequested: Sendable {
    let day: Date
}

struct ActivityTagOntologyRefreshRequested: Sendable {}

struct ActivityTagOntologyRunPublished: Sendable {}

struct OntologyOverviewRebuildRequested: Sendable {}
