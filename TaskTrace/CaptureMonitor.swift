//
//  CaptureMonitor.swift
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
import ScreenCaptureKit
import Speech
import WebP

@MainActor
final class TaskTraceCaptureMonitor {
    struct ScreenshotCaptureResult: Equatable, Sendable {
        let image: Data?
        let failureDescription: String?
    }

    struct ApplicationEvent: Equatable, Sendable {
        let appName: String
        let image: Data
    }

    struct KeyEvent: Equatable, Sendable {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags.RawValue
        let characters: String
    }

    struct SleepEvent: Equatable, Sendable {
        let timestamp: Date
    }

    struct MicrophoneEvent: Equatable, Sendable {
        let transcript: String
        let timestamp: Date
    }

    struct OSErrorEvent: Equatable, Sendable {
        let name: String
        let message: String
        let description: String
    }

    enum Event: Equatable, Sendable {
        case appDidBecomeActive(ApplicationEvent)
        case keyPress(KeyEvent)
        case keyRelease(KeyEvent)
        case appMonitor(ApplicationEvent)
        case microphone(MicrophoneEvent)
        case willSleep(SleepEvent)
        case osError(OSErrorEvent)
    }

    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "capture")
    private let workspaceNotificationCenter: NotificationCenter
    private let now: () -> Date
    private let activeApplicationName: () -> String
    private let screenshotProvider: () async -> ScreenshotCaptureResult
    private let screenCaptureAccess: () -> Bool
    private let requestScreenCaptureAccess: () -> Bool
    private let accessibilityAccess: (Bool) -> Bool
    private let microphoneAccess: () -> Bool
    private let speechRecognitionAccess: () -> Bool
    private let timerInterval: TimeInterval
    private let timerStartDelay: TimeInterval
    private let timerQueue: DispatchQueue
    private let microphoneTranscriber: any MicrophoneTranscribing

    private var listeners: [UUID: (Event) -> Void] = [:]
    private var observers: [NSObjectProtocol] = []
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var screenshotTimer: DispatchSourceTimer?
    private var hasStarted = false
    private var hasReportedAccessibilityError = false
    private var hasReportedScreenCaptureError = false
    private var hasReportedMicrophoneError = false
    private var hasReportedSpeechRecognitionError = false
    private var microphoneCaptureEnabled = true
    private var screenCaptureDeniedAtRuntime = false

    init() {
        self.workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        self.now = Date.init
        self.activeApplicationName = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        }
        self.screenshotProvider = TaskTraceCaptureMonitor.takeScreenshot
        self.screenCaptureAccess = {
            if #available(macOS 10.15, *) {
                CGPreflightScreenCaptureAccess()
            } else {
                true
            }
        }
        self.requestScreenCaptureAccess = {
            if #available(macOS 10.15, *) {
                CGRequestScreenCaptureAccess()
            } else {
                true
            }
        }
        self.accessibilityAccess = TaskTraceCaptureMonitor.accessibilityEnabled
        self.microphoneAccess = {
            AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            || AVAudioApplication.shared.recordPermission == .granted
        }
        self.speechRecognitionAccess = {
            SFSpeechRecognizer.authorizationStatus() == .authorized
        }
        self.timerInterval = 60
        self.timerStartDelay = 60
        self.timerQueue = DispatchQueue(label: "com.tasktrace.capture.monitor", attributes: .concurrent)
        self.microphoneTranscriber = MicrophoneTranscriber()
    }

    init(
        now: @escaping () -> Date,
        screenshotProvider: @escaping () async -> ScreenshotCaptureResult,
        screenCaptureAccess: @escaping () -> Bool,
        requestScreenCaptureAccess: @escaping () -> Bool,
        accessibilityAccess: @escaping (Bool) -> Bool,
        microphoneAccess: @escaping () -> Bool,
        speechRecognitionAccess: @escaping () -> Bool,
        timerInterval: TimeInterval,
        timerStartDelay: TimeInterval,
        microphoneCaptureEnabled: Bool = true,
        microphoneTranscriber: any MicrophoneTranscribing,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        activeApplicationName: @escaping () -> String = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        }
    ) {
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.now = now
        self.activeApplicationName = activeApplicationName
        self.screenshotProvider = screenshotProvider
        self.screenCaptureAccess = screenCaptureAccess
        self.requestScreenCaptureAccess = requestScreenCaptureAccess
        self.accessibilityAccess = accessibilityAccess
        self.microphoneAccess = microphoneAccess
        self.speechRecognitionAccess = speechRecognitionAccess
        self.timerInterval = timerInterval
        self.timerStartDelay = timerStartDelay
        self.timerQueue = DispatchQueue(label: "com.tasktrace.capture.monitor", attributes: .concurrent)
        self.microphoneTranscriber = microphoneTranscriber
        self.microphoneCaptureEnabled = microphoneCaptureEnabled
    }

    @discardableResult
    func addListener(_ listener: @escaping (Event) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }

    func removeListener(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }

    func removeAllListeners() {
        listeners.removeAll()
    }

    func start() {
        guard !hasStarted else {
            return
        }

        screenCaptureDeniedAtRuntime = false
        logger.log("starting capture monitor: screenCaptureAccess=\(self.screenCaptureAccess(), privacy: .public) accessibilityAccess=\(self.accessibilityAccess(false), privacy: .public) microphoneAccess=\(self.microphoneAccess(), privacy: .public) speechRecognitionAccess=\(self.speechRecognitionAccess(), privacy: .public)")
        hasStarted = true
        installWorkspaceObservers()
        installKeyMonitors()
        installScreenshotTimer()
        installMicrophoneTranscriber()
    }

    func stop() {
        guard hasStarted else {
            return
        }

        logger.log("stopping capture monitor")
        observers.forEach(workspaceNotificationCenter.removeObserver)
        observers.removeAll()

        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }

        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
            self.keyUpMonitor = nil
        }

        screenshotTimer?.cancel()
        screenshotTimer = nil
        microphoneTranscriber.stop()
        hasStarted = false
    }

    func setMicrophoneCaptureEnabled(_ isEnabled: Bool) {
        logger.log("setting microphone capture enabled: \(isEnabled, privacy: .public)")
        microphoneCaptureEnabled = isEnabled

        guard hasStarted else {
            return
        }

        if isEnabled {
            installMicrophoneTranscriber()
        } else {
            microphoneTranscriber.stop()
        }
    }

    func emitAppDidBecomeActive(appName: String, image: Data? = nil) async {
        if screenCaptureDeniedAtRuntime {
            reportScreenCaptureError()
            return
        }

        let captureResult = if let image {
            ScreenshotCaptureResult(image: image, failureDescription: nil)
        } else {
            await screenshotProvider()
        }

        emitApplicationEvent(
            name: appName,
            captureResult: captureResult,
            kind: .appDidBecomeActive
        )
    }

    func emitAppMonitor(appName: String, image: Data? = nil) async {
        if screenCaptureDeniedAtRuntime {
            reportScreenCaptureError()
            return
        }

        let captureResult = if let image {
            ScreenshotCaptureResult(image: image, failureDescription: nil)
        } else {
            await screenshotProvider()
        }

        emitApplicationEvent(
            name: appName,
            captureResult: captureResult,
            kind: .appMonitor
        )
    }

    func emitKeyPress(keyCode: UInt16, modifiers: NSEvent.ModifierFlags.RawValue, characters: String) {
        emit(.keyPress(KeyEvent(keyCode: keyCode, modifiers: modifiers, characters: characters)))
    }

    func emitKeyRelease(keyCode: UInt16, modifiers: NSEvent.ModifierFlags.RawValue, characters: String) {
        emit(.keyRelease(KeyEvent(keyCode: keyCode, modifiers: modifiers, characters: characters)))
    }

    func emitWillSleep(at timestamp: Date? = nil) {
        if hasStarted {
            microphoneTranscriber.stop()
        }

        emit(.willSleep(SleepEvent(timestamp: timestamp ?? now())))
    }

    func emitDidWake(appName: String? = nil, image: Data? = nil) async {
        if hasStarted {
            microphoneTranscriber.stop()
            installMicrophoneTranscriber()
        }

        await emitAppDidBecomeActive(appName: appName ?? activeApplicationName(), image: image)
    }

    func emitMicrophoneTranscript(_ transcript: String, at timestamp: Date? = nil) {
        emit(.microphone(.init(transcript: transcript, timestamp: timestamp ?? now())))
    }

    private func installWorkspaceObservers() {
        observers = [
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else {
                        return
                    }

                    await self.emitAppDidBecomeActive(appName: self.activeApplicationName())
                }
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else {
                        return
                    }

                    self.emitWillSleep()
                }
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else {
                        return
                    }

                    self.emitWillSleep()
                }
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else {
                        return
                    }

                    self.emitWillSleep()
                }
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.willPowerOffNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else {
                        return
                    }

                    self.emitWillSleep()
                }
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else {
                        return
                    }

                    await self.emitDidWake()
                }
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else {
                        return
                    }

                    await self.emitDidWake()
                }
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else {
                        return
                    }

                    await self.emitDidWake()
                }
            }
        ]
    }

    private func installKeyMonitors() {
        let hasAccessibilityAccess = accessibilityAccess(false)
        logger.log("installing key monitors: accessibilityAccess=\(hasAccessibilityAccess, privacy: .public)")

        guard hasAccessibilityAccess else {
            reportAccessibilityError()
            return
        }

        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.emitKeyPress(
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags.rawValue,
                    characters: event.characters ?? "unknown"
                )
            }
        }

        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor in
                self?.emitKeyRelease(
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags.rawValue,
                    characters: event.characters ?? "unknown"
                )
            }
        }
    }

    private func installScreenshotTimer() {
        let hasScreenCaptureAccess = screenCaptureAccess()
        logger.log("installing screenshot timer: screenCaptureAccess=\(hasScreenCaptureAccess, privacy: .public)")

        if !hasScreenCaptureAccess {
            reportScreenCaptureError()
        }

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + timerStartDelay, repeating: timerInterval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                await self.emitAppMonitor(appName: self.activeApplicationName())
            }
        }
        timer.resume()
        screenshotTimer = timer
    }

    private func installMicrophoneTranscriber() {
        guard microphoneCaptureEnabled else {
            logger.log("skipping microphone transcriber because microphone capture is disabled")
            microphoneTranscriber.stop()
            return
        }

        let hasMicrophoneAccess = microphoneAccess()
        let hasSpeechRecognitionAccess = speechRecognitionAccess()
        logger.log("installing microphone transcriber: microphoneAccess=\(hasMicrophoneAccess, privacy: .public) speechRecognitionAccess=\(hasSpeechRecognitionAccess, privacy: .public)")

        guard hasMicrophoneAccess else {
            reportMicrophoneError()
            return
        }

        guard hasSpeechRecognitionAccess else {
            reportSpeechRecognitionError()
            return
        }

        microphoneTranscriber.start { [weak self] transcript in
            guard let self, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            MainActor.assumeIsolated {
                self.logger.log("microphone transcript received: \(transcript, privacy: .private)")
                self.emitMicrophoneTranscript(transcript)
            }
        } onFailure: { [weak self] name, message, description in
            guard let self else {
                return
            }

            MainActor.assumeIsolated {
                self.logger.error("microphone transcription failed: \(name, privacy: .public) \(description, privacy: .public)")
                guard self.hasStarted else {
                    self.emit(.osError(.init(name: name, message: message, description: description)))
                    return
                }

                self.microphoneTranscriber.stop()
                self.installMicrophoneTranscriber()
            }
        }
    }

    private func emitApplicationEvent(name appName: String, captureResult: ScreenshotCaptureResult, kind: ApplicationEventKind) {
        guard let image = captureResult.image else {
            let hasScreenCaptureAccess = screenCaptureAccess()
            let didDeclineScreenCaptureAtRuntime = {
                let description = (captureResult.failureDescription ?? "").lowercased()
                return description.contains("declined tcc")
                || description.contains("user declined")
                || description.contains("scstreamerrordomain code=-3801")
            }()
            logger.error(
                "screen capture failed for \(appName, privacy: .public): permissionGranted=\(hasScreenCaptureAccess, privacy: .public) failure=\(captureResult.failureDescription ?? "unknown", privacy: .public)"
            )

            if didDeclineScreenCaptureAtRuntime {
                logger.error("screen capture runtime denial detected, disabling further screenshot attempts until capture restarts")
                screenCaptureDeniedAtRuntime = true
                TaskTraceRuntimePermissionState.setScreenCaptureDenied(true)
                screenshotTimer?.cancel()
                screenshotTimer = nil
                reportScreenCaptureError()
            } else if hasScreenCaptureAccess {
                reportScreenCaptureFailure(captureResult.failureDescription)
            } else {
                reportScreenCaptureError()
            }

            return
        }

        TaskTraceRuntimePermissionState.setScreenCaptureDenied(false)
        let event = ApplicationEvent(appName: appName, image: image)

        switch kind {
        case .appDidBecomeActive:
            logger.log("appDidBecomeActive: \(appName, privacy: .public)")
            emit(.appDidBecomeActive(event))
        case .appMonitor:
            logger.log("appMonitor: \(appName, privacy: .public)")
            emit(.appMonitor(event))
        }
    }

    private func emit(_ event: Event) {
        listeners.values.forEach { $0(event) }
    }

    private func reportAccessibilityError() {
        guard !hasReportedAccessibilityError else {
            return
        }

        hasReportedAccessibilityError = true
        logger.error("reporting accessibility permission denial")
        emit(.osError(OSErrorEvent(
            name: "AccessibilityPermissionDenied",
            message: "Accessibility access is required to capture global keystrokes.",
            description: "Grant Accessibility access to TaskTrace in System Settings > Privacy & Security > Accessibility."
        )))
    }

    private func reportScreenCaptureError() {
        guard !hasReportedScreenCaptureError else {
            return
        }

        hasReportedScreenCaptureError = true
        logger.error("reporting screen capture permission denial")
        emit(.osError(OSErrorEvent(
            name: "ScreenCapturePermissionDenied",
            message: "Screen recording permission is required to capture screenshots.",
            description: "Grant screen recording access to TaskTrace in System Settings > Privacy & Security > Screen & System Audio Recording."
        )))
    }

    private func reportScreenCaptureFailure(_ failureDescription: String?) {
        guard !hasReportedScreenCaptureError else {
            return
        }

        hasReportedScreenCaptureError = true
        emit(.osError(OSErrorEvent(
            name: "ScreenCaptureFailed",
            message: "Screen capture failed even though screen recording permission appears granted.",
            description: failureDescription ?? "TaskTrace could not capture a screenshot. Check the console logs for ScreenCaptureKit details."
        )))
    }

    private func reportMicrophoneError() {
        guard !hasReportedMicrophoneError else {
            return
        }

        hasReportedMicrophoneError = true
        logger.error("reporting microphone permission denial")
        emit(.osError(OSErrorEvent(
            name: "MicrophonePermissionDenied",
            message: "Microphone permission is required to capture background audio.",
            description: "Grant microphone access to TaskTrace in System Settings > Privacy & Security > Microphone."
        )))
    }

    private func reportSpeechRecognitionError() {
        guard !hasReportedSpeechRecognitionError else {
            return
        }

        hasReportedSpeechRecognitionError = true
        logger.error("reporting speech recognition permission denial")
        emit(.osError(OSErrorEvent(
            name: "SpeechRecognitionPermissionDenied",
            message: "Speech recognition permission is required for live microphone transcription.",
            description: "Grant speech recognition access to TaskTrace in System Settings > Privacy & Security > Speech Recognition."
        )))
    }

    private enum ApplicationEventKind {
        case appDidBecomeActive
        case appMonitor
    }
}

extension TaskTraceCaptureMonitor {
    nonisolated private static func accessibilityEnabled(prompt: Bool) -> Bool {
        let promptValue = prompt ? kCFBooleanTrue : kCFBooleanFalse
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptValue] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    nonisolated private static func takeScreenshot() async -> ScreenshotCaptureResult {
        do {
            let displayID = displayIDForActiveWindow() ?? CGMainDisplayID()
            let shareableContent = try await SCShareableContent.current
            guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) ?? shareableContent.displays.first else {
                return ScreenshotCaptureResult(image: nil, failureDescription: "No shareable displays were available for screenshot capture.")
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )

            guard let imageData = await webPData(from: image) else {
                return ScreenshotCaptureResult(image: nil, failureDescription: "TaskTrace captured a frame but could not encode it as WebP.")
            }

            return ScreenshotCaptureResult(image: imageData, failureDescription: nil)
        } catch {
            return ScreenshotCaptureResult(image: nil, failureDescription: String(describing: error))
        }
    }

    nonisolated private static func displayIDForActiveWindow() -> CGDirectDisplayID? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let pid = frontApp.processIdentifier
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: AnyObject]]
        let appWindows = windowInfoList?.filter {
            guard let ownerPID = $0[kCGWindowOwnerPID as String] as? pid_t else {
                return false
            }

            return ownerPID == pid
        } ?? []

        let frontmostWindow = appWindows.sorted {
            let firstLayer = $0[kCGWindowLayer as String] as? Int ?? Int.max
            let secondLayer = $1[kCGWindowLayer as String] as? Int ?? Int.max
            return firstLayer < secondLayer
        }.first

        guard
            let window = frontmostWindow,
            let bounds = window[kCGWindowBounds as String] as? [String: Any],
            let x = bounds["X"] as? CGFloat,
            let y = bounds["Y"] as? CGFloat,
            let width = bounds["Width"] as? CGFloat,
            let height = bounds["Height"] as? CGFloat
        else {
            return nil
        }

        let windowRect = CGRect(x: x, y: y, width: width, height: height)
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)

        return displays.reduce(into: (display: Optional<CGDirectDisplayID>.none, area: CGFloat.zero)) { best, display in
            let intersection = windowRect.intersection(CGDisplayBounds(display))
            let area = intersection.width * intersection.height

            if area > best.area {
                best = (display: display, area: area)
            }
        }.display
    }

    nonisolated private static let screenshotMaxLongestEdge = 1920

    nonisolated static func webPData(
        from image: CGImage
    ) async -> Data? {
        let originalWidth = image.width
        let originalHeight = image.height
        let longestEdge = max(originalWidth, originalHeight)
        let scale = longestEdge > screenshotMaxLongestEdge
            ? Double(screenshotMaxLongestEdge) / Double(longestEdge)
            : 1.0
        let width = max(1, Int((Double(originalWidth) * scale).rounded()))
        let height = max(1, Int((Double(originalHeight) * scale).rounded()))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rgbaBytes = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &rgbaBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let configuration = WebPEncoderConfig.preset(.picture, quality: 80)
        let encoder = WebPEncoder()
        var mutableBytes = rgbaBytes

        return mutableBytes.withUnsafeMutableBytes { bytes in
            guard let rgba = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }

            return try? encoder.encode(
                RGBA: rgba,
                config: configuration,
                originWidth: width,
                originHeight: height,
                stride: bytesPerRow
            )
        }
    }
}
