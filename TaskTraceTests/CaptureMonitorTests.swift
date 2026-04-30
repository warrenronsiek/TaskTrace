//
//  CaptureMonitorTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/12/26.
//

import AppKit
import Foundation
import Testing
@testable import TaskTrace

@MainActor
struct TaskTraceCaptureMonitorTests {
    @Test("app activation emits the active application and screenshot payload")
    func appActivationEmitsPayload() async {
        let image = Data("image-data".utf8)
        let monitor = TaskTraceCaptureMonitor(
            now: Date.init,
            screenshotProvider: { .init(image: image, failureDescription: nil) },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: FakeMicrophoneTranscriber()
        )
        var received: TaskTraceCaptureMonitor.Event?

        let listenerID = monitor.addListener { event in
            received = event
        }

        await monitor.emitAppDidBecomeActive(appName: "com.apple.dt.Xcode", image: image)
        monitor.removeListener(listenerID)

        #expect(received == .appDidBecomeActive(.init(
            appName: "com.apple.dt.Xcode",
            image: image
        )))
    }

    @Test("will sleep emits a timestamped sleep event")
    func willSleepEmitsTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let monitor = TaskTraceCaptureMonitor(
            now: { timestamp },
            screenshotProvider: { .init(image: Data("image-data".utf8), failureDescription: nil) },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: FakeMicrophoneTranscriber()
        )
        var received: TaskTraceCaptureMonitor.Event?

        _ = monitor.addListener { event in
            received = event
        }

        monitor.emitWillSleep()

        #expect(received == .willSleep(.init(timestamp: timestamp)))
    }

    @Test("missing screenshot data emits a single os error")
    func missingScreenshotEmitsOSError() async {
        let monitor = TaskTraceCaptureMonitor(
            now: Date.init,
            screenshotProvider: { .init(image: nil, failureDescription: "no image data") },
            screenCaptureAccess: { false },
            requestScreenCaptureAccess: { false },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: FakeMicrophoneTranscriber()
        )
        var received: [TaskTraceCaptureMonitor.Event] = []

        _ = monitor.addListener { event in
            received.append(event)
        }

        await monitor.emitAppMonitor(appName: "com.apple.TextEdit", image: nil)
        await monitor.emitAppDidBecomeActive(appName: "com.apple.TextEdit", image: nil)

        #expect(received == [
            .osError(.init(
                name: "ScreenCapturePermissionDenied",
                message: "Screen recording permission is required to capture screenshots.",
                description: "Grant screen recording access to TaskTrace in System Settings > Privacy & Security > Screen & System Audio Recording."
            ))
        ])
    }

    @Test("missing screenshot data with granted permission emits a capture failure")
    func missingScreenshotWithGrantedPermissionEmitsCaptureFailure() async {
        let monitor = TaskTraceCaptureMonitor(
            now: Date.init,
            screenshotProvider: { .init(image: nil, failureDescription: "screenshot manager returned nil") },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: FakeMicrophoneTranscriber()
        )
        var received: [TaskTraceCaptureMonitor.Event] = []

        _ = monitor.addListener { event in
            received.append(event)
        }

        await monitor.emitAppMonitor(appName: "com.apple.TextEdit", image: nil)

        #expect(received == [
            .osError(.init(
                name: "ScreenCaptureFailed",
                message: "Screen capture failed even though screen recording permission appears granted.",
                description: "screenshot manager returned nil"
            ))
        ])
    }

    @Test("screen capturekit tcc denial with granted preflight emits a permission denial")
    func screenCaptureKitTCCDenialEmitsPermissionDenial() async {
        let monitor = TaskTraceCaptureMonitor(
            now: Date.init,
            screenshotProvider: {
                .init(
                    image: nil,
                    failureDescription: #"Error Domain=com.apple.ScreenCaptureKit.SCStreamErrorDomain Code=-3801 "The user declined TCCs for application, window, display capture""#
                )
            },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: FakeMicrophoneTranscriber()
        )
        var received: [TaskTraceCaptureMonitor.Event] = []

        _ = monitor.addListener { event in
            received.append(event)
        }

        await monitor.emitAppMonitor(appName: "com.apple.TextEdit", image: nil)

        #expect(received == [
            .osError(.init(
                name: "ScreenCapturePermissionDenied",
                message: "Screen recording permission is required to capture screenshots.",
                description: "Grant screen recording access to TaskTrace in System Settings > Privacy & Security > Screen & System Audio Recording."
            ))
        ])
    }

    @Test("remove all listeners stops further delivery")
    func removeAllListenersStopsDelivery() {
        let monitor = TaskTraceCaptureMonitor(
            now: Date.init,
            screenshotProvider: { .init(image: Data("image-data".utf8), failureDescription: nil) },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: FakeMicrophoneTranscriber()
        )
        var received: [TaskTraceCaptureMonitor.Event] = []

        _ = monitor.addListener { event in
            received.append(event)
        }

        monitor.removeAllListeners()
        monitor.emitKeyPress(keyCode: 12, modifiers: NSEvent.ModifierFlags.command.rawValue, characters: "q")

        #expect(received.isEmpty)
    }

    @Test("microphone transcripts are emitted as capture events")
    func microphoneTranscriptsAreEmittedAsCaptureEvents() {
        let transcriber = FakeMicrophoneTranscriber()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_001)
        let monitor = TaskTraceCaptureMonitor(
            now: { timestamp },
            screenshotProvider: { .init(image: Data("image-data".utf8), failureDescription: nil) },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: transcriber
        )
        var received: TaskTraceCaptureMonitor.Event?

        _ = monitor.addListener { event in
            received = event
        }

        monitor.start()
        transcriber.emit("hello there")

        #expect(received == .microphone(.init(transcript: "hello there", timestamp: timestamp)))
    }

    @Test("disabled microphone capture does not start the microphone transcriber")
    func disabledMicrophoneCaptureDoesNotStartTheMicrophoneTranscriber() {
        let transcriber = FakeMicrophoneTranscriber()
        let monitor = TaskTraceCaptureMonitor(
            now: Date.init,
            screenshotProvider: { .init(image: Data("image-data".utf8), failureDescription: nil) },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneCaptureEnabled: false,
            microphoneTranscriber: transcriber
        )

        monitor.start()

        #expect(transcriber.startCount == 0)
    }

    @Test("disabling microphone capture while recording stops the microphone transcriber")
    func disablingMicrophoneCaptureWhileRecordingStopsTheMicrophoneTranscriber() {
        let transcriber = FakeMicrophoneTranscriber()
        let monitor = TaskTraceCaptureMonitor(
            now: Date.init,
            screenshotProvider: { .init(image: Data("image-data".utf8), failureDescription: nil) },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: transcriber
        )

        monitor.start()
        monitor.setMicrophoneCaptureEnabled(false)

        #expect(transcriber.stopCount == 1)
    }

    @Test("sleep stops the microphone transcriber while recording")
    func sleepStopsMicrophoneTranscriberWhileRecording() {
        let transcriber = FakeMicrophoneTranscriber()
        let monitor = TaskTraceCaptureMonitor(
            now: Date.init,
            screenshotProvider: { .init(image: Data("image-data".utf8), failureDescription: nil) },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: transcriber
        )

        monitor.start()
        monitor.emitWillSleep()

        #expect(transcriber.stopCount == 1)
    }

    @Test("wake restarts the microphone transcriber and emits activation")
    func wakeRestartsMicrophoneTranscriberAndEmitsActivation() async {
        let transcriber = FakeMicrophoneTranscriber()
        let image = Data("image-data".utf8)
        let monitor = TaskTraceCaptureMonitor(
            now: Date.init,
            screenshotProvider: { .init(image: image, failureDescription: nil) },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: transcriber
        )
        var received: TaskTraceCaptureMonitor.Event?

        _ = monitor.addListener { event in
            received = event
        }

        monitor.start()
        await monitor.emitDidWake(appName: "com.apple.dt.Xcode", image: image)

        #expect(transcriber.startCount == 2)
        #expect(received == .appDidBecomeActive(.init(
            appName: "com.apple.dt.Xcode",
            image: image
        )))
    }

    @Test("session resign active notifications emit sleep events")
    func sessionResignActiveNotificationsEmitSleepEvents() async {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_123)
        let center = NotificationCenter()
        let monitor = TaskTraceCaptureMonitor(
            now: { timestamp },
            screenshotProvider: { .init(image: Data("image-data".utf8), failureDescription: nil) },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: FakeMicrophoneTranscriber(),
            workspaceNotificationCenter: center
        )
        var received: TaskTraceCaptureMonitor.Event?

        _ = monitor.addListener { event in
            received = event
        }

        monitor.start()
        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        await flushMainQueue()

        #expect(received == .willSleep(.init(timestamp: timestamp)))
    }

    @Test("session become active notifications restart the microphone transcriber and emit activation")
    func sessionBecomeActiveNotificationsRestartTheMicrophoneTranscriberAndEmitActivation() async throws {
        let transcriber = FakeMicrophoneTranscriber()
        let image = Data("image-data".utf8)
        let center = NotificationCenter()
        let monitor = TaskTraceCaptureMonitor(
            now: Date.init,
            screenshotProvider: { .init(image: image, failureDescription: nil) },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: transcriber,
            workspaceNotificationCenter: center,
            activeApplicationName: { "com.apple.dt.Xcode" }
        )
        var received: TaskTraceCaptureMonitor.Event?

        _ = monitor.addListener { event in
            received = event
        }

        monitor.start()
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        try await waitUntil {
            received == .appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: image))
        }

        #expect((transcriber.startCount, received) == (
            2,
            .appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: image))
        ))
    }

    @Test("screen wake notifications restart the microphone transcriber and emit activation")
    func screenWakeNotificationsRestartTheMicrophoneTranscriberAndEmitActivation() async throws {
        let transcriber = FakeMicrophoneTranscriber()
        let image = Data("image-data".utf8)
        let center = NotificationCenter()
        let monitor = TaskTraceCaptureMonitor(
            now: Date.init,
            screenshotProvider: { .init(image: image, failureDescription: nil) },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: transcriber,
            workspaceNotificationCenter: center,
            activeApplicationName: { "com.apple.dt.Xcode" }
        )
        var received: TaskTraceCaptureMonitor.Event?

        _ = monitor.addListener { event in
            received = event
        }

        monitor.start()
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await waitUntil {
            received == .appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: image))
        }

        #expect((transcriber.startCount, received) == (
            2,
            .appDidBecomeActive(.init(appName: "com.apple.dt.Xcode", image: image))
        ))
    }

    @Test("microphone failures restart capture while recording")
    func microphoneFailuresRestartCaptureWhileRecording() {
        let transcriber = FakeMicrophoneTranscriber()
        let monitor = TaskTraceCaptureMonitor(
            now: Date.init,
            screenshotProvider: { .init(image: Data("image-data".utf8), failureDescription: nil) },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { true },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: transcriber
        )

        monitor.start()
        transcriber.emitFailure(
            name: "SpeechRecognitionFailed",
            message: "TaskTrace could not continue live speech recognition.",
            description: "simulated"
        )

        #expect(transcriber.startCount == 2)
    }

    @Test("missing microphone permission emits a single os error")
    func missingMicrophonePermissionEmitsOSError() {
        let monitor = TaskTraceCaptureMonitor(
            now: Date.init,
            screenshotProvider: { .init(image: Data("image-data".utf8), failureDescription: nil) },
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { true },
            accessibilityAccess: { _ in true },
            microphoneAccess: { false },
            speechRecognitionAccess: { true },
            timerInterval: 3600,
            timerStartDelay: 3600,
            microphoneTranscriber: FakeMicrophoneTranscriber()
        )
        var received: [TaskTraceCaptureMonitor.Event] = []

        _ = monitor.addListener { event in
            received.append(event)
        }

        monitor.start()
        monitor.stop()
        monitor.start()

        #expect(received == [
            .osError(.init(
                name: "MicrophonePermissionDenied",
                message: "Microphone permission is required to capture background audio.",
                description: "Grant microphone access to TaskTrace in System Settings > Privacy & Security > Microphone."
            ))
        ])
    }
}

@MainActor
private final class FakeMicrophoneTranscriber: MicrophoneTranscribing {
    private var onTranscript: ((String) -> Void)?
    private var onFailure: ((String, String, String) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(
        onTranscript: @escaping @Sendable (String) -> Void,
        onFailure: @escaping @Sendable (String, String, String) -> Void
    ) {
        self.onTranscript = onTranscript
        self.onFailure = onFailure
        startCount += 1
    }

    func stop() {
        onTranscript = nil
        onFailure = nil
        stopCount += 1
    }

    func emit(_ transcript: String) {
        onTranscript?(transcript)
    }

    func emitFailure(name: String, message: String, description: String) {
        onFailure?(name, message, description)
    }
}

@MainActor
private func flushMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(10),
    _ predicate: @escaping () async throws -> Bool
) async throws {
    let start = ContinuousClock.now

    while ContinuousClock.now - start < timeout {
        if try await predicate() {
            return
        }

        try await Task.sleep(for: pollInterval)
    }

    Issue.record("timed out waiting for asynchronous test condition")
}
