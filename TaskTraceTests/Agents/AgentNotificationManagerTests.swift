//
//  AgentNotificationManagerTests.swift
//  TaskTraceTests
//

import Foundation
import Testing
import UserNotifications
@testable import TaskTrace

struct AgentNotificationManagerTests {
    @Test("high priority notifications include the conversation route")
    func highPriorityNotificationsIncludeTheConversationRoute() async {
        let notificationCenter = FakeTaskTraceUserNotificationCenter()
        let manager = AgentNotificationManager(notificationCenter: notificationCenter)

        await manager.notifyIfHighPriority(
            rawMessage: #"{"importance":"high","content":"Open the failing agent chat."}"#,
            conversationID: "conversation-123"
        )

        #expect(await notificationCenter.firstConversationID() == "conversation-123")
    }

    @Test("non-high priority notifications are not created")
    func nonHighPriorityNotificationsAreNotCreated() async {
        let notificationCenter = FakeTaskTraceUserNotificationCenter()
        let manager = AgentNotificationManager(notificationCenter: notificationCenter)

        await manager.notifyIfHighPriority(
            rawMessage: #"{"importance":"normal","content":"Background update."}"#,
            conversationID: "conversation-123"
        )

        #expect(await notificationCenter.requestCount() == 0)
    }
}

private actor FakeTaskTraceUserNotificationCenter: TaskTraceUserNotificationCenter {
    private var requests: [UNNotificationRequest] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
    }

    func firstConversationID() -> String? {
        requests.first?.content.userInfo[TaskTraceAgentNotificationUserInfoKey.conversationID] as? String
    }

    func requestCount() -> Int {
        requests.count
    }
}
