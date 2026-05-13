//
//  TaskTracePushNotificationManager.swift
//  TaskTrace
//

import Foundation
import UserNotifications

nonisolated struct TaskTracePushNotificationResult: Codable, Equatable, Sendable {
    let title: String
    let message: String
    let source: String?
    let notificationID: String?
    let authorizationGranted: Bool
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

actor TaskTracePushNotificationManager {
    private let notificationCenter: any TaskTraceUserNotificationCenter

    init(
        notificationCenter: any TaskTraceUserNotificationCenter = TaskTraceSystemUserNotificationCenter()
    ) {
        self.notificationCenter = notificationCenter
    }

    func push(
        title: String?,
        message: String,
        source: String?
    ) async throws -> TaskTracePushNotificationResult {
        let resolvedTitle = {
            let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedTitle, !trimmedTitle.isEmpty {
                return trimmedTitle
            }
            return "TaskTrace"
        }()
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSource = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSource = trimmedSource?.isEmpty == false ? trimmedSource : nil
        let authorizationGranted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])

        guard authorizationGranted else {
            return TaskTracePushNotificationResult(
                title: resolvedTitle,
                message: trimmedMessage,
                source: resolvedSource,
                notificationID: nil,
                authorizationGranted: false
            )
        }

        let content = UNMutableNotificationContent()
        content.title = resolvedTitle
        content.body = trimmedMessage
        content.sound = .default

        if let resolvedSource {
            content.subtitle = resolvedSource
        }

        let notificationID = UUID().uuidString
        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: nil
        )
        try await notificationCenter.add(request)

        return TaskTracePushNotificationResult(
            title: resolvedTitle,
            message: trimmedMessage,
            source: resolvedSource,
            notificationID: notificationID,
            authorizationGranted: true
        )
    }
}
