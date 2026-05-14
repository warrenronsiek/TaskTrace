//
//  TaskTracePushNotificationManagerTests.swift
//  TaskTraceTests
//

import Foundation
import Testing
import UserNotifications
@testable import TaskTrace

struct TaskTracePushNotificationManagerTests {
    @Test("push message creates a notification")
    func pushMessageCreatesANotification() async throws {
        let notificationCenter = FakeTaskTraceUserNotificationCenter()
        let manager = TaskTracePushNotificationManager(notificationCenter: notificationCenter)

        _ = try await manager.push(title: "OpenClaw", message: "Review the failing build.", source: "Agent")

        #expect(await notificationCenter.requestCount() == 1)
    }

    @Test("push result reports denied notification authorization")
    func pushResultReportsDeniedNotificationAuthorization() async throws {
        let notificationCenter = FakeTaskTraceUserNotificationCenter(authorizationGranted: false)
        let manager = TaskTracePushNotificationManager(notificationCenter: notificationCenter)

        let result = try await manager.push(title: nil, message: "Review the failing build.", source: nil)

        #expect(result.authorizationGranted == false)
    }
}

private actor FakeTaskTraceUserNotificationCenter: TaskTraceUserNotificationCenter {
    private let authorizationGranted: Bool
    private var requests: [UNNotificationRequest] = []

    init(authorizationGranted: Bool = true) {
        self.authorizationGranted = authorizationGranted
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationGranted
    }

    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
    }

    func requestCount() -> Int {
        requests.count
    }
}
