//
//  KnowledgeGraphBuildProgress.swift
//  TaskTrace
//

import Foundation

nonisolated struct KnowledgeGraphBuildProgress: Equatable, Sendable {
    let totalChunks: Int
    let processedChunks: Int
    let totalActivities: Int
    let processedActivities: Int
    let totalOverviews: Int
    let processedOverviews: Int

    nonisolated init(
        totalChunks: Int = 0,
        processedChunks: Int = 0,
        totalActivities: Int = 0,
        processedActivities: Int = 0,
        totalOverviews: Int = 0,
        processedOverviews: Int = 0
    ) {
        self.totalChunks = totalChunks
        self.processedChunks = processedChunks
        self.totalActivities = totalActivities
        self.processedActivities = processedActivities
        self.totalOverviews = totalOverviews
        self.processedOverviews = processedOverviews
    }

    nonisolated var fileFraction: Double {
        totalChunks > 0
            ? Double(processedChunks) / Double(totalChunks)
            : 0
    }

    nonisolated var filesLabel: String {
        "\(processedChunks)/\(totalChunks)"
    }

    nonisolated var activityFraction: Double {
        totalActivities > 0
            ? Double(processedActivities) / Double(totalActivities)
            : 0
    }

    nonisolated var activitiesLabel: String {
        "\(processedActivities)/\(totalActivities)"
    }

    nonisolated var overviewFraction: Double {
        totalOverviews > 0
            ? Double(processedOverviews) / Double(totalOverviews)
            : 0
    }

    nonisolated var overviewsLabel: String {
        "\(processedOverviews)/\(totalOverviews)"
    }
}
