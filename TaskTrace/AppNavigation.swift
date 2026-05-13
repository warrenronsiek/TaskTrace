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
    @Published var selectedAgentsTab: AgentsView.Tab = .skills
}

@MainActor
final class TaskTraceNotificationRouter {
    private let navigationStore: TaskTraceNavigationStore
    private let activateApp: @MainActor @Sendable () -> Void

    init(
        navigationStore: TaskTraceNavigationStore,
        activateApp: @escaping @MainActor @Sendable () -> Void = TaskTraceWindowActivation.activateAppAndRaiseMainWindow
    ) {
        self.navigationStore = navigationStore
        self.activateApp = activateApp
    }

    func handleNotificationResponse(userInfo: [AnyHashable: Any]) {
        activateApp()
        _ = userInfo
        _ = navigationStore
    }
}
