//
//  PermissionManagerTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/12/26.
//

import Foundation
import Testing
@testable import TaskTrace

struct TaskTracePermissionManagerTests {
    @Test("status reads the current permission grants without prompting")
    func statusReadsCurrentPermissionGrantsWithoutPrompting() {
        let system = FakePermissionSystem()
        system.screenRecordingGranted = true
        system.accessibilityGranted = false
        system.microphoneGranted = true
        system.speechRecognitionGranted = false
        let manager = TaskTracePermissionManager(
            userDefaults: testDefaults(),
            system: system
        )

        #expect(manager.status() == TaskTracePermissionStatus(
            accessibilityGranted: false,
            screenRecordingGranted: true,
            microphoneGranted: true,
            speechRecognitionGranted: false
        ))
    }

    @Test("requestMissingPermissionsIfNeeded prompts screen recording once")
    func requestMissingPermissionsIfNeededPromptsScreenRecordingOnce() async {
        let defaults = testDefaults()
        let system = FakePermissionSystem()
        system.screenRecordingGranted = false
        system.accessibilityGranted = true
        let manager = TaskTracePermissionManager(
            userDefaults: defaults,
            system: system
        )

        await manager.requestMissingPermissionsIfNeeded(includeMicrophoneCapture: true)
        await manager.requestMissingPermissionsIfNeeded(includeMicrophoneCapture: true)

        #expect(system.screenRecordingRequests == 1)
    }

    @Test("requestMissingPermissionsIfNeeded prompts accessibility once")
    func requestMissingPermissionsIfNeededPromptsAccessibilityOnce() async {
        let defaults = testDefaults()
        let system = FakePermissionSystem()
        system.screenRecordingGranted = true
        system.accessibilityGranted = false
        let manager = TaskTracePermissionManager(
            userDefaults: defaults,
            system: system
        )

        await manager.requestMissingPermissionsIfNeeded(includeMicrophoneCapture: true)
        await manager.requestMissingPermissionsIfNeeded(includeMicrophoneCapture: true)

        #expect(system.accessibilityPrompts == 1)
    }

    @Test("requestMissingPermissionsIfNeeded prompts microphone once")
    func requestMissingPermissionsIfNeededPromptsMicrophoneOnce() async {
        let defaults = testDefaults()
        let system = FakePermissionSystem()
        system.screenRecordingGranted = true
        system.accessibilityGranted = true
        system.microphoneGranted = false
        let manager = TaskTracePermissionManager(
            userDefaults: defaults,
            system: system
        )

        await manager.requestMissingPermissionsIfNeeded(includeMicrophoneCapture: true)
        await manager.requestMissingPermissionsIfNeeded(includeMicrophoneCapture: true)

        #expect(system.microphoneRequests == 1)
    }

    @Test("requestMissingPermissionsIfNeeded prompts speech recognition once")
    func requestMissingPermissionsIfNeededPromptsSpeechRecognitionOnce() async {
        let defaults = testDefaults()
        let system = FakePermissionSystem()
        system.screenRecordingGranted = true
        system.accessibilityGranted = true
        system.speechRecognitionGranted = false
        let manager = TaskTracePermissionManager(
            userDefaults: defaults,
            system: system
        )

        await manager.requestMissingPermissionsIfNeeded(includeMicrophoneCapture: true)
        await manager.requestMissingPermissionsIfNeeded(includeMicrophoneCapture: true)

        #expect(system.speechRecognitionRequests == 1)
    }

    @Test("requestMissingPermissionsIfNeeded skips audio prompts when microphone capture is disabled")
    func requestMissingPermissionsIfNeededSkipsAudioPromptsWhenMicrophoneCaptureIsDisabled() async {
        let defaults = testDefaults()
        let system = FakePermissionSystem()
        system.screenRecordingGranted = true
        system.accessibilityGranted = true
        system.microphoneGranted = false
        system.speechRecognitionGranted = false
        let manager = TaskTracePermissionManager(
            userDefaults: defaults,
            system: system
        )

        await manager.requestMissingPermissionsIfNeeded(includeMicrophoneCapture: false)

        #expect(system.microphoneRequests == 0 && system.speechRecognitionRequests == 0)
    }

    @Test("status treats runtime screen capture denial as missing permission")
    func statusTreatsRuntimeScreenCaptureDenialAsMissingPermission() {
        let defaults = testDefaults()
        let system = FakePermissionSystem()
        system.screenRecordingGranted = true
        TaskTraceRuntimePermissionState.setScreenCaptureDenied(true, userDefaults: defaults)
        let manager = TaskTracePermissionManager(
            userDefaults: defaults,
            system: system
        )

        #expect(manager.status().screenRecordingGranted == false)
    }

    @Test("requestMissingPermissionsIfNeeded skips screen recording prompt when runtime denial is latched")
    func requestMissingPermissionsIfNeededSkipsScreenRecordingPromptWhenRuntimeDenialIsLatched() async {
        let defaults = testDefaults()
        let system = FakePermissionSystem()
        system.screenRecordingGranted = true
        TaskTraceRuntimePermissionState.setScreenCaptureDenied(true, userDefaults: defaults)
        let manager = TaskTracePermissionManager(
            userDefaults: defaults,
            system: system
        )

        await manager.requestMissingPermissionsIfNeeded(includeMicrophoneCapture: true)

        #expect(system.screenRecordingRequests == 0)
    }

    @Test("openSystemSettings opens the accessibility privacy pane")
    func openSystemSettingsOpensAccessibilityPrivacyPane() {
        let system = FakePermissionSystem()
        let manager = TaskTracePermissionManager(
            userDefaults: testDefaults(),
            system: system
        )

        manager.openSystemSettings(for: .accessibility)

        #expect(system.openedURL == URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"))
    }
}

private func testDefaults() -> UserDefaults {
    let suiteName = "TaskTracePermissionManagerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
