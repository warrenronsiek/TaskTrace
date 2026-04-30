//
//  AgentNotificationManager.swift
//  TaskTrace
//
//  Created by Codex on 4/2/26.
//

import Foundation
import UserNotifications

nonisolated enum TaskTraceAgentNotificationUserInfoKey {
    static let conversationID = "agentConversationID"
}

nonisolated protocol TaskTraceUserNotificationCenter {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

nonisolated struct TaskTraceSystemUserNotificationCenter: TaskTraceUserNotificationCenter {
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await notificationCenter.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await notificationCenter.add(request)
    }
}

actor AgentNotificationManager {
    private let notificationCenter: any TaskTraceUserNotificationCenter
    private var authorizationRequested: Bool
    private var authorizationGranted: Bool

    init(
        notificationCenter: any TaskTraceUserNotificationCenter = TaskTraceSystemUserNotificationCenter()
    ) {
        self.notificationCenter = notificationCenter
        self.authorizationRequested = false
        self.authorizationGranted = false
    }

    func notifyIfHighPriority(
        rawMessage: String,
        conversationID: String
    ) async {
        guard let parsedResponse = AgentChatMessageParser.parseStructuredResponse(rawMessage: rawMessage),
              parsedResponse.importance == "high",
              !parsedResponse.content.isEmpty else {
            return
        }

        if !authorizationRequested {
            authorizationRequested = true
            authorizationGranted = (try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }

        guard authorizationGranted else {
            return
        }

        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "TaskTrace Agent"
        notificationContent.body = parsedResponse.content
        notificationContent.sound = .default
        notificationContent.userInfo = [
            TaskTraceAgentNotificationUserInfoKey.conversationID: conversationID
        ]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: notificationContent,
            trigger: nil
        )

        try? await notificationCenter.add(request)
    }
}
