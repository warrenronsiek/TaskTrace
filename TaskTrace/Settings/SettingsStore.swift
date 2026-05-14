//
//  SettingsStore.swift
//  TaskTrace
//
//  Created by Codex on 3/12/26.
//

import Combine
import Foundation
import ServiceManagement
import os

nonisolated enum TaskTraceLaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    var isEnabled: Bool {
        self == .enabled || self == .requiresApproval
    }

    init(_ status: SMAppService.Status) {
        self = switch status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }
}

nonisolated protocol TaskTraceLaunchAtLoginControlling {
    func status() -> TaskTraceLaunchAtLoginStatus
    func setEnabled(_ isEnabled: Bool) throws -> TaskTraceLaunchAtLoginStatus
    func openSystemSettings()
}

nonisolated struct TaskTraceLaunchAtLoginController: TaskTraceLaunchAtLoginControlling {
    func status() -> TaskTraceLaunchAtLoginStatus {
        TaskTraceLaunchAtLoginStatus(SMAppService.mainApp.status)
    }

    func setEnabled(_ isEnabled: Bool) throws -> TaskTraceLaunchAtLoginStatus {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }

        return status()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    struct MCPConfiguration: Equatable, Sendable {
        var serverEnabled: Bool
        var overviewResourceEnabled: Bool
        var highLevelActivityResourceEnabled: Bool
        var detailedActivityResourceEnabled: Bool
        var todayTodosResourceEnabled: Bool
        var searchToolEnabled: Bool
        var graphSearchToolEnabled: Bool
        var addTodoToolEnabled: Bool
        var addGoalToolEnabled: Bool
        var pushMessageToolEnabled: Bool

        static let `default` = MCPConfiguration(
            serverEnabled: true,
            overviewResourceEnabled: true,
            highLevelActivityResourceEnabled: true,
            detailedActivityResourceEnabled: false,
            todayTodosResourceEnabled: true,
            searchToolEnabled: true,
            graphSearchToolEnabled: true,
            addTodoToolEnabled: true,
            addGoalToolEnabled: true,
            pushMessageToolEnabled: true
        )
    }

    @Published private(set) var permissionStatus: TaskTracePermissionStatus
    @Published private(set) var microphoneCaptureEnabled: Bool
    @Published private(set) var autoRecordOnLaunchEnabled: Bool
    @Published private(set) var mcpConfiguration: MCPConfiguration
    @Published private(set) var launchAtLoginStatus: TaskTraceLaunchAtLoginStatus

    private let settingsDatabaseActor: SettingsDatabaseActor?
    private let permissionManager: TaskTracePermissionManaging
    private let launchAtLoginController: TaskTraceLaunchAtLoginControlling
    private let notificationCenter: NotificationCenter
    private var permissionRuntimeObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "settings")

    init(
        settingsDatabaseActor: SettingsDatabaseActor? = nil,
        permissionManager: TaskTracePermissionManaging,
        launchAtLoginController: TaskTraceLaunchAtLoginControlling = TaskTraceLaunchAtLoginController(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.settingsDatabaseActor = settingsDatabaseActor
        self.permissionManager = permissionManager
        self.launchAtLoginController = launchAtLoginController
        self.notificationCenter = notificationCenter
        self.permissionStatus = permissionManager.status()
        self.microphoneCaptureEnabled = true
        self.autoRecordOnLaunchEnabled = false
        self.mcpConfiguration = .default
        self.launchAtLoginStatus = launchAtLoginController.status()
        self.permissionRuntimeObserver = notificationCenter.addObserver(
            forName: .taskTraceRuntimePermissionStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissions()
            }
        }
    }

    convenience init(
        database: TaskTraceDatabase,
        permissionManager: TaskTracePermissionManaging,
        launchAtLoginController: TaskTraceLaunchAtLoginControlling = TaskTraceLaunchAtLoginController(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            settingsDatabaseActor: SettingsDatabaseActor(database: database),
            permissionManager: permissionManager,
            launchAtLoginController: launchAtLoginController,
            notificationCenter: notificationCenter
        )
    }

    convenience init() {
        self.init(settingsDatabaseActor: nil, permissionManager: TaskTracePermissionManager())
    }

    deinit {
        if let permissionRuntimeObserver {
            notificationCenter.removeObserver(permissionRuntimeObserver)
        }
    }

    func refreshPermissions() {
        logger.log("refreshing permission status from settings view")
        permissionStatus = permissionManager.status()
    }

    func requestMissingPermissionsIfNeeded() async {
        logger.log("request missing permissions from settings store")
        await permissionManager.requestMissingPermissionsIfNeeded(includeMicrophoneCapture: microphoneCaptureEnabled)
        refreshPermissions()
    }

    func requestPermission(_ permission: TaskTracePermissionKind) async {
        logger.log("request permission from settings store: \(String(describing: permission), privacy: .public)")
        await permissionManager.requestPermission(permission)
        refreshPermissions()
    }

    func openSystemSettings(for permission: TaskTracePermissionKind) {
        permissionManager.openSystemSettings(for: permission)
    }

    var launchAtLoginEnabled: Bool {
        launchAtLoginStatus.isEnabled
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = launchAtLoginController.status()
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            launchAtLoginStatus = try launchAtLoginController.setEnabled(isEnabled)
        } catch {
            logger.error("could not update launch at login state enabled=\(isEnabled, privacy: .public) error=\(String(describing: error), privacy: .public)")
            refreshLaunchAtLoginStatus()
        }
    }

    func openLaunchAtLoginSystemSettings() {
        launchAtLoginController.openSystemSettings()
    }

    func loadPersistedSettings() async {
        guard let settingsDatabaseActor else {
            refreshLaunchAtLoginStatus()
            return
        }

        let serverEnabledValue = try? await settingsDatabaseActor.getSetting(named: "mcp.serverEnabled")
        let microphoneCaptureEnabledValue = try? await settingsDatabaseActor.getSetting(named: "capture.microphoneEnabled")
        let autoRecordOnLaunchEnabledValue = try? await settingsDatabaseActor.getSetting(named: "capture.autoRecordOnLaunchEnabled")
        let overviewEnabledValue = try? await settingsDatabaseActor.getSetting(named: "mcp.overviewResourceEnabled")
        let highLevelEnabledValue = try? await settingsDatabaseActor.getSetting(named: "mcp.highLevelActivityResourceEnabled")
        let detailedEnabledValue = try? await settingsDatabaseActor.getSetting(named: "mcp.detailedActivityResourceEnabled")
        let todayTodosEnabledValue = try? await settingsDatabaseActor.getSetting(named: "mcp.todayTodosResourceEnabled")
        let searchToolEnabledValue = try? await settingsDatabaseActor.getSetting(named: "mcp.searchToolEnabled")
        let graphSearchToolEnabledValue = try? await settingsDatabaseActor.getSetting(named: "mcp.graphSearchToolEnabled")
        let addTodoToolEnabledValue = try? await settingsDatabaseActor.getSetting(named: "mcp.addTodoToolEnabled")
        let addGoalToolEnabledValue = try? await settingsDatabaseActor.getSetting(named: "mcp.addGoalToolEnabled")
        let pushMessageToolEnabledValue = try? await settingsDatabaseActor.getSetting(named: "mcp.pushMessageToolEnabled")

        let valueForBool = { (value: String?, defaultValue: Bool) in
            value.flatMap(Bool.init) ?? defaultValue
        }
        microphoneCaptureEnabled = valueForBool(microphoneCaptureEnabledValue, true)
        autoRecordOnLaunchEnabled = valueForBool(autoRecordOnLaunchEnabledValue, false)
        mcpConfiguration = MCPConfiguration(
            serverEnabled: valueForBool(serverEnabledValue, true),
            overviewResourceEnabled: valueForBool(overviewEnabledValue, true),
            highLevelActivityResourceEnabled: valueForBool(highLevelEnabledValue, true),
            detailedActivityResourceEnabled: valueForBool(detailedEnabledValue, false),
            todayTodosResourceEnabled: valueForBool(todayTodosEnabledValue, true),
            searchToolEnabled: valueForBool(searchToolEnabledValue, true),
            graphSearchToolEnabled: valueForBool(graphSearchToolEnabledValue, true),
            addTodoToolEnabled: valueForBool(addTodoToolEnabledValue, true),
            addGoalToolEnabled: valueForBool(addGoalToolEnabledValue, true),
            pushMessageToolEnabled: valueForBool(pushMessageToolEnabledValue, true)
        )
        refreshLaunchAtLoginStatus()
    }

    func setServerEnabled(_ isEnabled: Bool) {
        var updatedConfiguration = mcpConfiguration
        updatedConfiguration.serverEnabled = isEnabled
        mcpConfiguration = updatedConfiguration
        persistSetting(named: "mcp.serverEnabled", value: String(isEnabled))
    }

    func setMicrophoneCaptureEnabled(_ isEnabled: Bool) {
        microphoneCaptureEnabled = isEnabled
        persistSetting(named: "capture.microphoneEnabled", value: String(isEnabled))
    }

    func setAutoRecordOnLaunchEnabled(_ isEnabled: Bool) {
        autoRecordOnLaunchEnabled = isEnabled
        persistSetting(named: "capture.autoRecordOnLaunchEnabled", value: String(isEnabled))
    }

    func setOverviewResourceEnabled(_ isEnabled: Bool) {
        var updatedConfiguration = mcpConfiguration
        updatedConfiguration.overviewResourceEnabled = isEnabled
        mcpConfiguration = updatedConfiguration
        persistSetting(named: "mcp.overviewResourceEnabled", value: String(isEnabled))
    }

    func setHighLevelActivityResourceEnabled(_ isEnabled: Bool) {
        var updatedConfiguration = mcpConfiguration
        updatedConfiguration.highLevelActivityResourceEnabled = isEnabled
        mcpConfiguration = updatedConfiguration
        persistSetting(named: "mcp.highLevelActivityResourceEnabled", value: String(isEnabled))
    }

    func setDetailedActivityResourceEnabled(_ isEnabled: Bool) {
        var updatedConfiguration = mcpConfiguration
        updatedConfiguration.detailedActivityResourceEnabled = isEnabled
        mcpConfiguration = updatedConfiguration
        persistSetting(named: "mcp.detailedActivityResourceEnabled", value: String(isEnabled))
    }

    func setTodayTodosResourceEnabled(_ isEnabled: Bool) {
        var updatedConfiguration = mcpConfiguration
        updatedConfiguration.todayTodosResourceEnabled = isEnabled
        mcpConfiguration = updatedConfiguration
        persistSetting(named: "mcp.todayTodosResourceEnabled", value: String(isEnabled))
    }

    func setSearchToolEnabled(_ isEnabled: Bool) {
        var updatedConfiguration = mcpConfiguration
        updatedConfiguration.searchToolEnabled = isEnabled
        mcpConfiguration = updatedConfiguration
        persistSetting(named: "mcp.searchToolEnabled", value: String(isEnabled))
    }

    func setGraphSearchToolEnabled(_ isEnabled: Bool) {
        var updatedConfiguration = mcpConfiguration
        updatedConfiguration.graphSearchToolEnabled = isEnabled
        mcpConfiguration = updatedConfiguration
        persistSetting(named: "mcp.graphSearchToolEnabled", value: String(isEnabled))
    }

    func setAddTodoToolEnabled(_ isEnabled: Bool) {
        var updatedConfiguration = mcpConfiguration
        updatedConfiguration.addTodoToolEnabled = isEnabled
        mcpConfiguration = updatedConfiguration
        persistSetting(named: "mcp.addTodoToolEnabled", value: String(isEnabled))
    }

    func setAddGoalToolEnabled(_ isEnabled: Bool) {
        var updatedConfiguration = mcpConfiguration
        updatedConfiguration.addGoalToolEnabled = isEnabled
        mcpConfiguration = updatedConfiguration
        persistSetting(named: "mcp.addGoalToolEnabled", value: String(isEnabled))
    }

    func setPushMessageToolEnabled(_ isEnabled: Bool) {
        var updatedConfiguration = mcpConfiguration
        updatedConfiguration.pushMessageToolEnabled = isEnabled
        mcpConfiguration = updatedConfiguration
        persistSetting(named: "mcp.pushMessageToolEnabled", value: String(isEnabled))
    }

    private func persistSetting(named name: String, value: String) {
        guard let settingsDatabaseActor else {
            return
        }

        Task {
            guard (try? await settingsDatabaseActor.setSetting(named: name, value: value)) != nil else {
                return
            }
        }
    }
}
