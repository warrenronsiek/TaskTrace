//
//  PermissionManager.swift
//  TaskTrace
//
//  Created by Codex on 3/12/26.
//

import AppKit
import ApplicationServices
import AVFoundation
import AVFAudio
import CoreGraphics
import Foundation
import os
import Speech

extension Notification.Name {
    static let taskTraceRuntimePermissionStateDidChange = Notification.Name("TaskTraceRuntimePermissionStateDidChange")
}

enum TaskTraceRuntimePermissionState {
    private static let screenCaptureDeniedKey = "settings.permissions.screenCaptureDeniedAtRuntime"

    static func screenCaptureDenied(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: screenCaptureDeniedKey)
    }

    static func setScreenCaptureDenied(_ denied: Bool, userDefaults: UserDefaults = .standard) {
        guard userDefaults.bool(forKey: screenCaptureDeniedKey) != denied else {
            return
        }

        userDefaults.set(denied, forKey: screenCaptureDeniedKey)
        NotificationCenter.default.post(name: .taskTraceRuntimePermissionStateDidChange, object: nil)
    }
}

struct TaskTracePermissionStatus: Equatable {
    let accessibilityGranted: Bool
    let screenRecordingGranted: Bool
    let microphoneGranted: Bool
    let speechRecognitionGranted: Bool
}

enum TaskTracePermissionKind: Equatable {
    case accessibility
    case screenRecording
    case microphone
    case speechRecognition
}

protocol TaskTracePermissionManaging {
    func status() -> TaskTracePermissionStatus
    func requestMissingPermissionsIfNeeded(includeMicrophoneCapture: Bool) async
    func requestPermission(_ permission: TaskTracePermissionKind) async
    func openSystemSettings(for permission: TaskTracePermissionKind)
}

protocol TaskTracePermissionSystemOperating {
    func screenCaptureAccess() -> Bool
    func requestScreenCaptureAccess() -> Bool
    func accessibilityAccess(prompt: Bool) -> Bool
    func microphoneAccess() -> Bool
    func requestMicrophoneAccess() async -> Bool
    func speechRecognitionAccess() -> Bool
    func requestSpeechRecognitionAccess() async -> Bool
    func openURL(_ url: URL) -> Bool
}

struct TaskTracePermissionSystem: TaskTracePermissionSystemOperating {
    func screenCaptureAccess() -> Bool {
        if #available(macOS 10.15, *) {
            CGPreflightScreenCaptureAccess()
        } else {
            true
        }
    }

    func requestScreenCaptureAccess() -> Bool {
        if #available(macOS 10.15, *) {
            CGRequestScreenCaptureAccess()
        } else {
            true
        }
    }

    func accessibilityAccess(prompt: Bool) -> Bool {
        let promptValue = prompt ? kCFBooleanTrue : kCFBooleanFalse
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptValue] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func microphoneAccess() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        || AVAudioApplication.shared.recordPermission == .granted
    }

    func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            let resume: @Sendable (Bool) -> Void = { granted in
                continuation.resume(
                    returning: granted
                    || AVAudioApplication.shared.recordPermission == .granted
                    || AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                )
            }

            if #available(macOS 14.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    resume(granted)
                }
            } else {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    resume(granted)
                }
            }
        }
    }

    func speechRecognitionAccess() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestSpeechRecognitionAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func openURL(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

final class TaskTracePermissionManager: TaskTracePermissionManaging {
    private enum DefaultsKey {
        static let accessibilityPrompted = "settings.permissions.accessibilityPrompted"
        static let screenRecordingPrompted = "settings.permissions.screenRecordingPrompted"
        static let microphonePrompted = "settings.permissions.microphonePrompted"
        static let speechRecognitionPrompted = "settings.permissions.speechRecognitionPrompted"
    }

    private let userDefaults: UserDefaults
    private let system: any TaskTracePermissionSystemOperating
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "permissions")

    init() {
        self.userDefaults = .standard
        self.system = TaskTracePermissionSystem()
    }

    init(
        userDefaults: UserDefaults,
        system: any TaskTracePermissionSystemOperating
    ) {
        self.userDefaults = userDefaults
        self.system = system
    }

    func status() -> TaskTracePermissionStatus {
        let runtimeScreenCaptureDenied = TaskTraceRuntimePermissionState.screenCaptureDenied(userDefaults: userDefaults)
        let currentStatus = TaskTracePermissionStatus(
            accessibilityGranted: system.accessibilityAccess(prompt: false),
            screenRecordingGranted: system.screenCaptureAccess() && !runtimeScreenCaptureDenied,
            microphoneGranted: system.microphoneAccess(),
            speechRecognitionGranted: system.speechRecognitionAccess()
        )

        logger.log(
            "permission status checked: accessibilityGranted=\(currentStatus.accessibilityGranted, privacy: .public) screenRecordingGranted=\(currentStatus.screenRecordingGranted, privacy: .public) runtimeScreenCaptureDenied=\(runtimeScreenCaptureDenied, privacy: .public) microphoneGranted=\(currentStatus.microphoneGranted, privacy: .public) speechRecognitionGranted=\(currentStatus.speechRecognitionGranted, privacy: .public)"
        )
        return currentStatus
    }

    func requestMissingPermissionsIfNeeded(includeMicrophoneCapture: Bool) async {
        logger.log("requesting missing permissions if needed")

        if !system.screenCaptureAccess() && !userDefaults.bool(forKey: DefaultsKey.screenRecordingPrompted) {
            logger.log("requesting screen recording permission prompt")
            userDefaults.set(true, forKey: DefaultsKey.screenRecordingPrompted)
            _ = system.requestScreenCaptureAccess()
        } else if TaskTraceRuntimePermissionState.screenCaptureDenied(userDefaults: userDefaults) {
            logger.log("skipping automatic screen recording prompt because runtime capture remains denied despite preflight grant")
        }

        if !system.accessibilityAccess(prompt: false) && !userDefaults.bool(forKey: DefaultsKey.accessibilityPrompted) {
            logger.log("requesting accessibility permission prompt")
            userDefaults.set(true, forKey: DefaultsKey.accessibilityPrompted)
            _ = system.accessibilityAccess(prompt: true)
        }

        if includeMicrophoneCapture && !system.microphoneAccess() && !userDefaults.bool(forKey: DefaultsKey.microphonePrompted) {
            logger.log("requesting microphone permission prompt")
            userDefaults.set(true, forKey: DefaultsKey.microphonePrompted)
            _ = await system.requestMicrophoneAccess()
        }

        if includeMicrophoneCapture && !system.speechRecognitionAccess() && !userDefaults.bool(forKey: DefaultsKey.speechRecognitionPrompted) {
            logger.log("requesting speech recognition permission prompt")
            userDefaults.set(true, forKey: DefaultsKey.speechRecognitionPrompted)
            _ = await system.requestSpeechRecognitionAccess()
        }
    }

    func requestPermission(_ permission: TaskTracePermissionKind) async {
        logger.log("requesting permission explicitly: \(String(describing: permission), privacy: .public)")

        switch permission {
        case .screenRecording:
            userDefaults.set(true, forKey: DefaultsKey.screenRecordingPrompted)

            if !system.screenCaptureAccess() {
                _ = system.requestScreenCaptureAccess()
            } else {
                logger.log("skipping screen recording permission prompt because preflight access is already granted; open System Settings to resolve runtime capture denial")
            }
        case .accessibility:
            userDefaults.set(true, forKey: DefaultsKey.accessibilityPrompted)

            if !system.accessibilityAccess(prompt: false) {
                _ = system.accessibilityAccess(prompt: true)
            }
        case .microphone:
            userDefaults.set(true, forKey: DefaultsKey.microphonePrompted)

            if !system.microphoneAccess() {
                _ = await system.requestMicrophoneAccess()
            }
        case .speechRecognition:
            userDefaults.set(true, forKey: DefaultsKey.speechRecognitionPrompted)

            if !system.speechRecognitionAccess() {
                _ = await system.requestSpeechRecognitionAccess()
            }
        }
    }

    func openSystemSettings(for permission: TaskTracePermissionKind) {
        guard let url = permission.settingsURL else {
            return
        }

        logger.log("opening system settings for permission: \(String(describing: permission), privacy: .public)")
        _ = system.openURL(url)
    }
}

private extension TaskTracePermissionKind {
    var settingsURL: URL? {
        switch self {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechRecognition:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        }
    }
}
