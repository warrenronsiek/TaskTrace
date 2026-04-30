//
//  AppNavigation.swift
//  TaskTrace
//

import AppKit
import Combine
import Foundation

@MainActor
enum TaskTraceWindowActivation {
    static func activateAppAndRaiseMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows
            .filter(\.canBecomeMain)
            .forEach { $0.makeKeyAndOrderFront(nil) }
    }
}

@MainActor
final class TaskTraceNavigationStore: ObservableObject {
    @Published var selectedPage: ContentView.AppPage? = .activity
    @Published var selectedAgentsTab: AgentsView.Tab = .chat
    @Published private(set) var selectedAgentActionID: Int64?

    private var pendingAgentConversationID: String?

    func selectAgentAction(_ agentActionID: Int64?) {
        selectedAgentActionID = agentActionID
        pendingAgentConversationID = nil
    }

    func routeToAgentConversation(
        _ conversationID: String,
        agentActions: [AgentActionRecord]
    ) {
        let normalizedConversationID = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedConversationID.isEmpty else {
            return
        }

        selectedPage = .agents
        selectedAgentsTab = .chat

        if let matchedAgentActionID = agentActions.first(where: { $0.conversationID == normalizedConversationID })?.id {
            selectedAgentActionID = matchedAgentActionID
            pendingAgentConversationID = nil
            return
        }

        pendingAgentConversationID = normalizedConversationID

        if agentActions.isEmpty {
            selectedAgentActionID = nil
            return
        }

        if !agentActions.map(\.id).contains(selectedAgentActionID ?? -1) {
            selectedAgentActionID = agentActions.first?.id
        }
    }

    func reconcileAgentSelection(agentActions: [AgentActionRecord]) {
        if let pendingAgentConversationID {
            if let matchedAgentActionID = agentActions.first(where: { $0.conversationID == pendingAgentConversationID })?.id {
                selectedAgentActionID = matchedAgentActionID
                self.pendingAgentConversationID = nil
                return
            }

            if !agentActions.isEmpty {
                self.pendingAgentConversationID = nil
            }
        }

        guard !agentActions.isEmpty else {
            selectedAgentActionID = nil
            return
        }

        if !agentActions.map(\.id).contains(selectedAgentActionID ?? -1) {
            selectedAgentActionID = agentActions.first?.id
        }
    }
}

@MainActor
final class TaskTraceNotificationRouter {
    private let navigationStore: TaskTraceNavigationStore
    private let activateApp: @MainActor @Sendable () -> Void
    private let agentActionsSnapshot: @MainActor @Sendable () -> [AgentActionRecord]

    init(
        navigationStore: TaskTraceNavigationStore,
        activateApp: @escaping @MainActor @Sendable () -> Void = TaskTraceWindowActivation.activateAppAndRaiseMainWindow,
        agentActionsSnapshot: @escaping @MainActor @Sendable () -> [AgentActionRecord]
    ) {
        self.navigationStore = navigationStore
        self.activateApp = activateApp
        self.agentActionsSnapshot = agentActionsSnapshot
    }

    func handleNotificationResponse(userInfo: [AnyHashable: Any]) {
        guard let conversationID = userInfo[TaskTraceAgentNotificationUserInfoKey.conversationID] as? String else {
            return
        }

        activateApp()
        navigationStore.routeToAgentConversation(
            conversationID,
            agentActions: agentActionsSnapshot()
        )
    }
}
