//
//  FakePermissionSystem.swift
//  TaskTraceTests
//
//  Created by Codex on 3/13/26.
//

import Foundation
@testable import TaskTrace

final class FakePermissionSystem: TaskTracePermissionSystemOperating {
    var screenRecordingGranted = true
    var accessibilityGranted = true
    var microphoneGranted = true
    var speechRecognitionGranted = true
    var screenRecordingRequests = 0
    var accessibilityPrompts = 0
    var microphoneRequests = 0
    var speechRecognitionRequests = 0
    var openedURL: URL?

    func screenCaptureAccess() -> Bool {
        screenRecordingGranted
    }

    func requestScreenCaptureAccess() -> Bool {
        screenRecordingRequests += 1
        return screenRecordingGranted
    }

    func accessibilityAccess(prompt: Bool) -> Bool {
        if prompt {
            accessibilityPrompts += 1
        }

        return accessibilityGranted
    }

    func microphoneAccess() -> Bool {
        microphoneGranted
    }

    func requestMicrophoneAccess() async -> Bool {
        microphoneRequests += 1
        return microphoneGranted
    }

    func speechRecognitionAccess() -> Bool {
        speechRecognitionGranted
    }

    func requestSpeechRecognitionAccess() async -> Bool {
        speechRecognitionRequests += 1
        return speechRecognitionGranted
    }

    func openURL(_ url: URL) -> Bool {
        openedURL = url
        return true
    }
}
