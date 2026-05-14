//
//  SettingsStoreTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/12/26.
//

import Foundation
import Testing
@testable import TaskTrace

@MainActor
struct SettingsStoreTests {
    private func withStore(
        permissionStatus: TaskTracePermissionStatus = TaskTracePermissionStatus(
            accessibilityGranted: false,
            screenRecordingGranted: false,
            microphoneGranted: false,
            speechRecognitionGranted: false
        ),
        launchAtLoginController: TaskTraceLaunchAtLoginControlling = FakeLaunchAtLoginController(),
        _ block: (SettingsStore) -> Void
    ) {
        let settingsStore = SettingsStore(
            permissionManager: FakePermissionManager(currentStatus: permissionStatus),
            launchAtLoginController: launchAtLoginController
        )
        block(settingsStore)
    }

    @Test("initialization loads the current permission status")
    func initializationLoadsCurrentPermissionStatus() {
        withStore(permissionStatus: TaskTracePermissionStatus(
            accessibilityGranted: true,
            screenRecordingGranted: false,
            microphoneGranted: true,
            speechRecognitionGranted: false
        )) { settingsStore in
            #expect(settingsStore.permissionStatus == TaskTracePermissionStatus(
                accessibilityGranted: true,
                screenRecordingGranted: false,
                microphoneGranted: true,
                speechRecognitionGranted: false
            ))
        }
    }

    @Test("the detailed MCP feed defaults to disabled")
    func detailedMCPFeedDefaultsToDisabled() {
        withStore { settingsStore in
            #expect(settingsStore.mcpConfiguration.detailedActivityResourceEnabled == false)
        }
    }

    @Test("the MCP search tool defaults to enabled")
    func mcpSearchToolDefaultsToEnabled() {
        withStore { settingsStore in
            #expect(settingsStore.mcpConfiguration.searchToolEnabled == true)
        }
    }

    @Test("the MCP graph search tool defaults to enabled")
    func mcpGraphSearchToolDefaultsToEnabled() {
        withStore { settingsStore in
            #expect(settingsStore.mcpConfiguration.graphSearchToolEnabled == true)
        }
    }

    @Test("the MCP today todos resource defaults to enabled")
    func mcpTodayTodosResourceDefaultsToEnabled() {
        withStore { settingsStore in
            #expect(settingsStore.mcpConfiguration.todayTodosResourceEnabled == true)
        }
    }

    @Test("the MCP add todo tool defaults to enabled")
    func mcpAddTodoToolDefaultsToEnabled() {
        withStore { settingsStore in
            #expect(settingsStore.mcpConfiguration.addTodoToolEnabled == true)
        }
    }

    @Test("the MCP add goal tool defaults to enabled")
    func mcpAddGoalToolDefaultsToEnabled() {
        withStore { settingsStore in
            #expect(settingsStore.mcpConfiguration.addGoalToolEnabled == true)
        }
    }

    @Test("the MCP push message tool defaults to enabled")
    func mcpPushMessageToolDefaultsToEnabled() {
        withStore { settingsStore in
            #expect(settingsStore.mcpConfiguration.pushMessageToolEnabled == true)
        }
    }

    @Test("microphone capture defaults to enabled")
    func microphoneCaptureDefaultsToEnabled() {
        withStore { settingsStore in
            #expect(settingsStore.microphoneCaptureEnabled == true)
        }
    }

    @Test("auto record on launch defaults to disabled")
    func autoRecordOnLaunchDefaultsToDisabled() {
        withStore { settingsStore in
            #expect(settingsStore.autoRecordOnLaunchEnabled == false)
        }
    }

    @Test("launch at login defaults to disabled when the system service is not registered")
    func launchAtLoginDefaultsToDisabledWhenUnregistered() {
        withStore(
            launchAtLoginController: FakeLaunchAtLoginController(
                statusProvider: { .notRegistered }
            )
        ) { settingsStore in
            #expect(settingsStore.launchAtLoginEnabled == false)
        }
    }

    @Test("launch at login reflects an enabled system service")
    func launchAtLoginReflectsAnEnabledSystemService() {
        withStore(
            launchAtLoginController: FakeLaunchAtLoginController(
                statusProvider: { .enabled }
            )
        ) { settingsStore in
            #expect(settingsStore.launchAtLoginEnabled == true)
        }
    }

    @Test("enabling launch at login registers the service")
    func enablingLaunchAtLoginRegistersTheService() {
        var recordedValue: Bool?

        withStore(
            launchAtLoginController: FakeLaunchAtLoginController(
                setEnabledHandler: { isEnabled in
                    recordedValue = isEnabled
                    return .enabled
                }
            )
        ) { settingsStore in
            settingsStore.setLaunchAtLoginEnabled(true)
            #expect(recordedValue == true)
        }
    }

    @Test("disabling launch at login unregisters the service")
    func disablingLaunchAtLoginUnregistersTheService() {
        var recordedValue: Bool?

        withStore(
            launchAtLoginController: FakeLaunchAtLoginController(
                statusProvider: { .enabled },
                setEnabledHandler: { isEnabled in
                    recordedValue = isEnabled
                    return .notRegistered
                }
            )
        ) { settingsStore in
            settingsStore.setLaunchAtLoginEnabled(false)
            #expect(recordedValue == false)
        }
    }

    @Test("enabling launch at login updates the store to enabled")
    func enablingLaunchAtLoginUpdatesTheStoreToEnabled() {
        withStore(
            launchAtLoginController: FakeLaunchAtLoginController(
                setEnabledHandler: { _ in
                    .enabled
                }
            )
        ) { settingsStore in
            settingsStore.setLaunchAtLoginEnabled(true)
            #expect(settingsStore.launchAtLoginStatus == .enabled)
        }
    }

    @Test("launch at login refresh picks up approval-required state")
    func launchAtLoginRefreshPicksUpApprovalRequiredState() {
        var status = TaskTraceLaunchAtLoginStatus.notRegistered

        withStore(
            launchAtLoginController: FakeLaunchAtLoginController(
                statusProvider: { status }
            )
        ) { settingsStore in
            status = .requiresApproval
            settingsStore.refreshLaunchAtLoginStatus()
            #expect(settingsStore.launchAtLoginStatus == .requiresApproval)
        }
    }

    @Test("launch at login failures leave the store disabled")
    func launchAtLoginFailuresLeaveTheStoreDisabled() {
        enum FakeError: Error {
            case failed
        }

        withStore(
            launchAtLoginController: FakeLaunchAtLoginController(
                setEnabledHandler: { _ in
                    throw FakeError.failed
                }
            )
        ) { settingsStore in
            settingsStore.setLaunchAtLoginEnabled(true)
            #expect(settingsStore.launchAtLoginEnabled == false)
        }
    }

    @Test("disabling the MCP server persists a disabled server setting")
    func disablingTheMCPServerPersistsADisabledServerSetting() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            settingsStore.setServerEnabled(false)
            try? await Task.sleep(for: .milliseconds(50))
            let persistedSetting = try await database.getSetting(named: "mcp.serverEnabled")
            #expect(persistedSetting == "false")
        }
    }

    @Test("loading persisted settings restores the disabled MCP server state")
    func loadingPersistedSettingsRestoresTheDisabledMCPServerState() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            try await database.setSetting(named: "mcp.serverEnabled", value: "false")
            await settingsStore.loadPersistedSettings()
            #expect(settingsStore.mcpConfiguration.serverEnabled == false)
        }
    }

    @Test("disabling the MCP search tool persists a disabled tool setting")
    func disablingTheMCPSearchToolPersistsADisabledToolSetting() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            settingsStore.setSearchToolEnabled(false)
            try? await Task.sleep(for: .milliseconds(50))
            let persistedSetting = try await database.getSetting(named: "mcp.searchToolEnabled")
            #expect(persistedSetting == "false")
        }
    }

    @Test("loading persisted settings restores the disabled MCP search tool state")
    func loadingPersistedSettingsRestoresTheDisabledMCPSearchToolState() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            try await database.setSetting(named: "mcp.searchToolEnabled", value: "false")
            await settingsStore.loadPersistedSettings()
            #expect(settingsStore.mcpConfiguration.searchToolEnabled == false)
        }
    }

    @Test("disabling the MCP graph search tool persists a disabled tool setting")
    func disablingTheMCPGraphSearchToolPersistsADisabledToolSetting() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            settingsStore.setGraphSearchToolEnabled(false)
            try? await Task.sleep(for: .milliseconds(50))
            let persistedSetting = try await database.getSetting(named: "mcp.graphSearchToolEnabled")
            #expect(persistedSetting == "false")
        }
    }

    @Test("loading persisted settings restores the disabled MCP graph search tool state")
    func loadingPersistedSettingsRestoresTheDisabledMCPGraphSearchToolState() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            try await database.setSetting(named: "mcp.graphSearchToolEnabled", value: "false")
            await settingsStore.loadPersistedSettings()
            #expect(settingsStore.mcpConfiguration.graphSearchToolEnabled == false)
        }
    }

    @Test("loading persisted settings restores the disabled MCP today todos resource state")
    func loadingPersistedSettingsRestoresTheDisabledMCPTodayTodosResourceState() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            try await database.setSetting(named: "mcp.todayTodosResourceEnabled", value: "false")
            await settingsStore.loadPersistedSettings()
            #expect(settingsStore.mcpConfiguration.todayTodosResourceEnabled == false)
        }
    }

    @Test("loading persisted settings restores the disabled MCP add todo tool state")
    func loadingPersistedSettingsRestoresTheDisabledMCPAddTodoToolState() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            try await database.setSetting(named: "mcp.addTodoToolEnabled", value: "false")
            await settingsStore.loadPersistedSettings()
            #expect(settingsStore.mcpConfiguration.addTodoToolEnabled == false)
        }
    }

    @Test("loading persisted settings restores the disabled MCP add goal tool state")
    func loadingPersistedSettingsRestoresTheDisabledMCPAddGoalToolState() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            try await database.setSetting(named: "mcp.addGoalToolEnabled", value: "false")
            await settingsStore.loadPersistedSettings()
            #expect(settingsStore.mcpConfiguration.addGoalToolEnabled == false)
        }
    }

    @Test("loading persisted settings restores the disabled MCP push message tool state")
    func loadingPersistedSettingsRestoresTheDisabledMCPPushMessageToolState() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            try await database.setSetting(named: "mcp.pushMessageToolEnabled", value: "false")
            await settingsStore.loadPersistedSettings()
            #expect(settingsStore.mcpConfiguration.pushMessageToolEnabled == false)
        }
    }

    @Test("disabling the MCP push message tool persists a disabled tool setting")
    func disablingTheMCPPushMessageToolPersistsADisabledToolSetting() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            settingsStore.setPushMessageToolEnabled(false)
            try? await Task.sleep(for: .milliseconds(50))
            let persistedSetting = try await database.getSetting(named: "mcp.pushMessageToolEnabled")
            #expect(persistedSetting == "false")
        }
    }

    @Test("disabling microphone capture persists the disabled setting")
    func disablingMicrophoneCapturePersistsTheDisabledSetting() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            settingsStore.setMicrophoneCaptureEnabled(false)
            try? await Task.sleep(for: .milliseconds(50))
            let persistedSetting = try await database.getSetting(named: "capture.microphoneEnabled")
            #expect(persistedSetting == "false")
        }
    }

    @Test("loading persisted settings restores disabled microphone capture")
    func loadingPersistedSettingsRestoresDisabledMicrophoneCapture() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            try await database.setSetting(named: "capture.microphoneEnabled", value: "false")
            await settingsStore.loadPersistedSettings()
            #expect(settingsStore.microphoneCaptureEnabled == false)
        }
    }

    @Test("enabling auto record on launch persists the enabled setting")
    func enablingAutoRecordOnLaunchPersistsTheEnabledSetting() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            settingsStore.setAutoRecordOnLaunchEnabled(true)
            try? await Task.sleep(for: .milliseconds(50))
            let persistedSetting = try await database.getSetting(named: "capture.autoRecordOnLaunchEnabled")
            #expect(persistedSetting == "true")
        }
    }

    @Test("loading persisted settings restores enabled auto record on launch")
    func loadingPersistedSettingsRestoresEnabledAutoRecordOnLaunch() async throws {
        try await withStoreWithDatabase { settingsStore, database in
            try await database.setSetting(named: "capture.autoRecordOnLaunchEnabled", value: "true")
            await settingsStore.loadPersistedSettings()
            #expect(settingsStore.autoRecordOnLaunchEnabled == true)
        }
    }
}

private struct FakePermissionManager: TaskTracePermissionManaging {
    let currentStatus: TaskTracePermissionStatus

    func status() -> TaskTracePermissionStatus {
        currentStatus
    }

    func requestMissingPermissionsIfNeeded(includeMicrophoneCapture: Bool) async {}

    func requestPermission(_ permission: TaskTracePermissionKind) async {}

    func openSystemSettings(for permission: TaskTracePermissionKind) {}
}

private struct FakeLaunchAtLoginController: TaskTraceLaunchAtLoginControlling {
    var statusProvider: () -> TaskTraceLaunchAtLoginStatus = { .notRegistered }
    var setEnabledHandler: (Bool) throws -> TaskTraceLaunchAtLoginStatus = { isEnabled in
        isEnabled ? .enabled : .notRegistered
    }
    var openSystemSettingsHandler: () -> Void = {}

    func status() -> TaskTraceLaunchAtLoginStatus {
        statusProvider()
    }

    func setEnabled(_ isEnabled: Bool) throws -> TaskTraceLaunchAtLoginStatus {
        try setEnabledHandler(isEnabled)
    }

    func openSystemSettings() {
        openSystemSettingsHandler()
    }
}

@MainActor
private func withStoreWithDatabase(
    permissionStatus: TaskTracePermissionStatus = TaskTracePermissionStatus(
        accessibilityGranted: false,
        screenRecordingGranted: false,
        microphoneGranted: false,
        speechRecognitionGranted: false
    ),
    _ block: (SettingsStore, TaskTraceDatabase) async throws -> Void
) async throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

    try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
    let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
    let settingsStore = SettingsStore(
        database: database,
        permissionManager: FakePermissionManager(currentStatus: permissionStatus),
        launchAtLoginController: FakeLaunchAtLoginController()
    )

    try await block(settingsStore, database)
}
