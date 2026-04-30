//
//  ActivityStore.swift
//  TaskTrace
//
//  Created by Codex on 3/12/26.
//

import Combine
import Foundation
import os

@MainActor
protocol CaptureMonitoring: AnyObject {
    func start()
    func stop()
}

extension TaskTraceCaptureMonitor: CaptureMonitoring {}

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var state: ActivityActor.State
    @Published private(set) var isRecording: Bool
    @Published private(set) var playStopButtonDisabled: Bool
    @Published private(set) var activeDay: Date
    @Published private(set) var focusedActivityID: Int64?

    private let activityActor: ActivityActor?
    private let actorSystem: ActorSystem?
    private let captureMonitor: (any CaptureMonitoring)?
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "playstop")
    private var updatesTask: Task<Void, Never>?

    init(
        activityActor: ActivityActor,
        actorSystem: ActorSystem,
        captureMonitor: any CaptureMonitoring
    ) {
        self.activityActor = activityActor
        self.actorSystem = actorSystem
        self.captureMonitor = captureMonitor
        self.state = .init()
        self.isRecording = false
        self.now = Date.init
        self.calendar = .current
        self.activeDay = Calendar.current.startOfDay(for: Date())
        self.playStopButtonDisabled = false
        self.focusedActivityID = nil
        self.updatesTask = Task {
            let updates = await activityActor.updates()

            for await state in updates {
                self.state = state
            }
        }
    }

    init(
        activityActor: ActivityActor,
        actorSystem: ActorSystem,
        captureMonitor: any CaptureMonitoring,
        initialState: ActivityActor.State,
        activeDay: Date,
        isRecording: Bool,
        now: @escaping @Sendable () -> Date,
        calendar: Calendar
    ) {
        let resolvedActiveDay = calendar.startOfDay(for: activeDay)

        self.activityActor = activityActor
        self.actorSystem = actorSystem
        self.captureMonitor = captureMonitor
        self.state = initialState
        self.now = now
        self.calendar = calendar
        self.activeDay = resolvedActiveDay
        self.isRecording = isRecording
        self.playStopButtonDisabled = !calendar.isDate(resolvedActiveDay, inSameDayAs: now())
        self.focusedActivityID = nil
        self.updatesTask = Task {
            let updates = await activityActor.updates()

            for await state in updates {
                self.state = state
            }
        }
    }

    init(previewState: ActivityActor.State) {
        let activeDay = Calendar.current.startOfDay(for: Date())

        self.activityActor = nil
        self.actorSystem = nil
        self.captureMonitor = nil
        self.state = previewState
        self.isRecording = false
        self.now = Date.init
        self.calendar = .current
        self.activeDay = activeDay
        self.playStopButtonDisabled = false
        self.focusedActivityID = nil
        self.updatesTask = nil
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadActiveDay() async {
        logger.log("loading active day: \(self.activeDay, privacy: .public)")
        await activityActor?.load(for: activeDay)
        await refreshPlayButtonStatus()
    }

    func setActiveDay(_ date: Date) async {
        activeDay = calendar.startOfDay(for: date)
        logger.log("setting active day: \(self.activeDay, privacy: .public)")
        await activityActor?.load(for: activeDay)
        await refreshPlayButtonStatus()
    }

    func refreshPlayButtonStatus() async {
        let nextDisabledState = !calendar.isDate(activeDay, inSameDayAs: now())
        logger.log(
            "refreshing play button status: activeDay=\(self.activeDay, privacy: .public) currentTime=\(self.now(), privacy: .public) disabled=\(nextDisabledState, privacy: .public) isRecording=\(self.isRecording, privacy: .public)"
        )
        playStopButtonDisabled = nextDisabledState

        if nextDisabledState, isRecording {
            logger.log("stopping capture because active day no longer matches today")
            captureMonitor?.stop()
            isRecording = false
        }
    }

    func toggleRecording() async {
        logger.log("toggle recording requested: current=\(self.isRecording, privacy: .public)")

        await refreshPlayButtonStatus()
        await setRecording(to: !isRecording, shouldAppendPause: true)
    }

    func stopRecordingForApplicationQuit() async {
        logger.log("application quit requested while recording=\(self.isRecording, privacy: .public)")
        await setRecording(to: false, shouldAppendPause: true)
    }

    func handleCaptureEvent(_ event: TaskTraceCaptureMonitor.Event) {
        guard isRecording, !playStopButtonDisabled else {
            logger.log("ignoring capture event because recording is inactive or disabled")
            return
        }

        logger.log("forwarding capture event while recording")
        guard let activityActor else {
            return
        }

        switch event {
        case .willSleep:
            Task.detached(priority: .high) {
                await activityActor.handle(event)
            }
        default:
            Task {
                await activityActor.handle(event)
            }
        }
    }

    func setTag(activityID: Int64, tagID: Int64?) async {
        logger.log("setting tag for activity: activityID=\(activityID, privacy: .public) tagID=\(String(describing: tagID), privacy: .public)")
        guard let actorSystem else {
            return
        }

        await actorSystem.broadcast(
            from: nil,
            message: ActivityTagSet(activityID: activityID, tagID: tagID)
        )
    }

    func deleteActivity(activityID: Int64) async {
        logger.log("deleting activity: activityID=\(activityID, privacy: .public)")
        if let actorSystem {
            await actorSystem.broadcast(
                from: nil,
                message: ActivityDeleted(activityID: activityID)
            )
            return
        }
    }

    func focusActivity(activityID: Int64) {
        focusedActivityID = activityID
    }

    func clearFocusedActivity(activityID: Int64) {
        guard focusedActivityID == activityID else {
            return
        }

        focusedActivityID = nil
    }

    func loadScreenshotImage(screenshotID: Int64) async -> Data? {
        await activityActor?.loadScreenshotImage(screenshotID: screenshotID)
    }

    private func setRecording(to nextRecordingState: Bool, shouldAppendPause: Bool) async {
        let nextResolvedState = nextRecordingState && !playStopButtonDisabled
        logger.log(
            "setting recording state: requested=\(nextRecordingState, privacy: .public) resolved=\(nextResolvedState, privacy: .public) disabled=\(self.playStopButtonDisabled, privacy: .public)"
        )

        if !nextResolvedState, isRecording {
            captureMonitor?.stop()
            isRecording = false

            if shouldAppendPause, calendar.isDate(activeDay, inSameDayAs: now()) {
                await activityActor?.appendPause(named: "PAUSED", timestamp: now())
                await activityActor?.applyActivityPasses(offset: 1)
            }

            await refreshPlayButtonStatus()
            return
        }

        if nextResolvedState, !isRecording {
            captureMonitor?.start()
            isRecording = true
            await refreshPlayButtonStatus()
            return
        }
    }
}
