//
//  TaskTraceNavigationStoreTests.swift
//  TaskTraceTests
//

import Testing
@testable import TaskTrace

@MainActor
struct TaskTraceNavigationStoreTests {
    @Test("routing to a conversation opens the agents page")
    func routingToAConversationOpensTheAgentsPage() {
        let navigationStore = TaskTraceNavigationStore()

        navigationStore.routeToAgentConversation("conversation-123", agentActions: [])

        #expect(navigationStore.selectedPage == .agents)
    }

    @Test("routing to a conversation opens the chat tab")
    func routingToAConversationOpensTheChatTab() {
        let navigationStore = TaskTraceNavigationStore()

        navigationStore.routeToAgentConversation("conversation-123", agentActions: [])

        #expect(navigationStore.selectedAgentsTab == .chat)
    }

    @Test("routing to a conversation activates the app")
    func routingToAConversationActivatesTheApp() {
        let navigationStore = TaskTraceNavigationStore()
        var activationCount = 0
        let router = TaskTraceNotificationRouter(
            navigationStore: navigationStore,
            activateApp: {
                activationCount += 1
            },
            agentActionsSnapshot: { [] }
        )

        router.handleNotificationResponse(
            userInfo: [
                TaskTraceAgentNotificationUserInfoKey.conversationID: "conversation-123"
            ]
        )

        #expect(activationCount == 1)
    }

    @Test("pending routed conversations resolve to the matching agent action")
    func pendingRoutedConversationsResolveToTheMatchingAgentAction() {
        let navigationStore = TaskTraceNavigationStore()

        navigationStore.routeToAgentConversation("conversation-123", agentActions: [])
        navigationStore.reconcileAgentSelection(
            agentActions: [
                AgentActionRecord(
                    id: 44,
                    instructions: "Handle urgent chat",
                    eventType: .activitySummarized,
                    conversationID: "conversation-123"
                )
            ]
        )

        #expect(navigationStore.selectedAgentActionID == 44)
    }

    @Test("invalid selected agent actions fall back to the first available action")
    func invalidSelectedAgentActionsFallBackToTheFirstAvailableAction() {
        let navigationStore = TaskTraceNavigationStore()

        navigationStore.selectAgentAction(99)
        navigationStore.reconcileAgentSelection(
            agentActions: [
                AgentActionRecord(
                    id: 11,
                    instructions: "First action",
                    eventType: .activitySummarized,
                    conversationID: "conversation-11"
                ),
                AgentActionRecord(
                    id: 12,
                    instructions: "Second action",
                    eventType: .activitySummarized,
                    conversationID: "conversation-12"
                )
            ]
        )

        #expect(navigationStore.selectedAgentActionID == 11)
    }
}
