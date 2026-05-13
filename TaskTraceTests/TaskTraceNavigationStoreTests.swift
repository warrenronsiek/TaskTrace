//
//  TaskTraceNavigationStoreTests.swift
//  TaskTraceTests
//

import Testing
@testable import TaskTrace

@MainActor
struct TaskTraceNavigationStoreTests {
    @Test("notification response activates the app")
    func notificationResponseActivatesTheApp() {
        let navigationStore = TaskTraceNavigationStore()
        var activationCount = 0
        let router = TaskTraceNotificationRouter(
            navigationStore: navigationStore,
            activateApp: {
                activationCount += 1
            }
        )

        router.handleNotificationResponse(userInfo: [:])

        #expect(activationCount == 1)
    }

    @Test("agents tab defaults to skills")
    func agentsTabDefaultsToSkills() {
        let navigationStore = TaskTraceNavigationStore()

        #expect(navigationStore.selectedAgentsTab == .skills)
    }
}
