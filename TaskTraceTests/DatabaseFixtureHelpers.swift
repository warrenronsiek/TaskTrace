import Foundation
@testable import TaskTrace

extension TaskTraceDatabase {
    func saveActivityRecord(_ activity: ActivityInput) async throws {
        try await ActivityDatabaseActor(database: self).saveActivityRecord(activity)
    }

    func saveScreenshotRecord(
        activityID: Int64,
        screenshot: ScreenshotInput
    ) async throws {
        try await ActivityDatabaseActor(database: self).saveScreenshotRecord(
            activityID: activityID,
            screenshot: screenshot
        )
    }

    func saveOverviewRecord(_ overview: OverviewInput) async throws {
        try await OverviewDatabaseActor(database: self).saveOverviewRecord(overview)
    }
}
