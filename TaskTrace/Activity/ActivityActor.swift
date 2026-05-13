//
//  ActivityActor.swift
//  TaskTrace
//
//  Created by Codex on 3/12/26.
//

import Foundation
import OSLog


actor ActivityActor: Receiver {
    nonisolated static let minimumActivityDurationSeconds: TimeInterval = 30
    nonisolated private static let activationThrottleInterval: TimeInterval = 1
    nonisolated static let inactiveApplications = Set(["SLEEP", "PAUSED"])
    private let logger = Logger(subsystem: "com.tasktrace.Tasktrace", category: "general")

    struct Activity: Identifiable, Equatable, Sendable {
        let id: Int64
        var application: String
        var startTime: Date
        var keystrokes: String
        var microphone: String
        var summary: String?
        var overviewID: Int64?
        var overviewAssignmentSource: OverviewAssignmentSource? = nil
        var tagID: Int64?
        var tagAssignmentSource: ActivityTagAssignmentSource? = nil
        var ontologyCandidateID: Int64? = nil
        var goalTodoID: Int64? = nil
        var goalTodoAssignmentSource: GoalTodoAssignmentSource? = nil
        var goalTodoAssignmentScore: Double? = nil
        var screenshots: [Screenshot]
    }

    struct Screenshot: Identifiable, Equatable, Sendable {
        let id: Int64
        var image: Data?
        var timestamp: Date
        var description: String?
        var text: String?
        var summary: String?
        var ignoreReason: String?

        init(
            id: Int64,
            image: Data?,
            timestamp: Date,
            description: String?,
            text: String?,
            summary: String? = nil,
            ignoreReason: String?
        ) {
            self.id = id
            self.image = image
            self.timestamp = timestamp
            self.description = description
            self.text = text
            self.summary = summary
            self.ignoreReason = ignoreReason
        }
    }

    struct ActivityError: Equatable, Sendable {
        let name: String
        let message: String
        let description: String
    }

    struct State: Equatable, Sendable {
        var activities: [Activity]
        var error: ActivityError?

        init(
            activities: [Activity] = [],
            error: ActivityError? = nil
        ) {
            self.activities = activities
            self.error = error
        }
    }

    private let activityDatabaseActor: ActivityDatabaseActor
    private let actorSystem: ActorSystem
    private let identifierActor: IdentifierActor
    private let now: @Sendable () -> Date

    private var activities: [Activity]
    private var error: ActivityError?
    private var keyboard: [UInt16: TaskTraceCaptureMonitor.KeyEvent] = [:]
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
    private var lastApplicationActivationAt: Date?
    private var loadedDay: Date?
    private var pendingScreenshotSummaryIDs: Set<Int64> = []
    private var pendingGoalTodoAssignments: [UUID: (
        activityID: Int64,
        goalTodoID: Int64?,
        source: GoalTodoAssignmentSource?,
        score: Double?
    )] = [:]

    init(
        activityDatabaseActor: ActivityDatabaseActor,
        actorSystem: ActorSystem = ActorSystem()
    ) {
        self.activityDatabaseActor = activityDatabaseActor
        self.actorSystem = actorSystem
        self.identifierActor = .shared
        self.now = Date.init
        self.activities = []
        self.error = nil
    }

    init(
        activityDatabaseActor: ActivityDatabaseActor,
        actorSystem: ActorSystem = ActorSystem(),
        now: @escaping @Sendable () -> Date,
        identifierActor: IdentifierActor? = nil,
        nextIdentifier: Int64? = nil
    ) {
        self.activityDatabaseActor = activityDatabaseActor
        self.actorSystem = actorSystem
        self.identifierActor = identifierActor ?? IdentifierActor(
            now: now,
            latestIdentifier: (nextIdentifier ?? Int64(now().timeIntervalSince1970 * 1_000)) - 1
        )
        self.now = now
        self.activities = []
        self.error = nil
    }

    func updates() -> AsyncStream<State> {
        let id = UUID()

        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(snapshot())
            continuation.onTermination = { _ in
                Task {
                    await self.removeContinuation(id)
                }
            }
        }
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as ImageDescribed:
            logger.log(
                "activity-actor received image-described sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) screenshotID=\(event.screenshotID, privacy: .public) characters=\(event.description.count, privacy: .public)"
            )
            if let match = activities.enumerated().compactMap({ activityPair in
                activityPair.element.screenshots.firstIndex(where: { $0.id == event.screenshotID }).map {
                    (activityPair.offset, $0)
                }
            }).first,
               let activityIndex = Optional(match.0),
               let screenshotIndex = Optional(match.1),
               activities[activityIndex].screenshots[screenshotIndex].description == nil {
                activities[activityIndex].screenshots[screenshotIndex].description = event.description
                if activities[activityIndex].screenshots[screenshotIndex].text != nil {
                    activities[activityIndex].screenshots[screenshotIndex].image = nil
                }
                let activityID = activities[activityIndex].id
                broadcast()
                await enqueueScreenshotSummaries(activityIDs: Set([activityID]))
            }
        case let event as ScreenshotTextRead:
            logger.log(
                "activity-actor received screenshot-text-read sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) screenshotID=\(event.screenshotID, privacy: .public) characters=\(event.text.count, privacy: .public)"
            )
            if let match = activities.enumerated().compactMap({ activityPair in
                activityPair.element.screenshots.firstIndex(where: { $0.id == event.screenshotID }).map {
                    (activityPair.offset, $0)
                }
            }).first,
               let activityIndex = Optional(match.0),
               let screenshotIndex = Optional(match.1),
               activities[activityIndex].screenshots[screenshotIndex].text == nil {
                activities[activityIndex].screenshots[screenshotIndex].text = event.text
                if activities[activityIndex].screenshots[screenshotIndex].description != nil {
                    activities[activityIndex].screenshots[screenshotIndex].image = nil
                }
                let activityID = activities[activityIndex].id
                broadcast()
                await enqueueScreenshotSummaries(activityIDs: Set([activityID]))
            }
        case let event as ScreenshotSummarized:
            logger.log(
                "activity-actor received screenshot-summarized sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) screenshotID=\(event.screenshotID, privacy: .public) characters=\(event.summary.count, privacy: .public)"
            )
            pendingScreenshotSummaryIDs.remove(event.screenshotID)
            if let match = activities.enumerated().compactMap({ activityPair in
                activityPair.element.screenshots.firstIndex(where: { $0.id == event.screenshotID }).map {
                    (activityPair.offset, $0)
                }
            }).first,
               let activityIndex = Optional(match.0),
               let screenshotIndex = Optional(match.1),
               activities[activityIndex].screenshots[screenshotIndex].summary == nil {
                activities[activityIndex].screenshots[screenshotIndex].summary = event.summary
                broadcast()
                await applyActivityPasses()
            }
        case let event as ActivitySummarized:
            logger.log(
                "activity-actor received activity-summarized sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activity.id, privacy: .public)"
            )
            guard let activityIndex = activities.firstIndex(where: { $0.id == event.activity.id }),
                  activities[activityIndex].summary == nil else {
                return
            }

            activities[activityIndex].summary = event.activity.summary
            broadcast()

        case let event as ActivityTagAssigned:
            logger.log(
                "activity-actor received activity-tag-assigned sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public) tagID=\(event.tagID, privacy: .public)"
            )
            guard let activityIndex = activities.firstIndex(where: { $0.id == event.activityID }),
                  activities[activityIndex].tagAssignmentSource != .manual else {
                return
            }

            activities[activityIndex].tagID = event.tagID
            activities[activityIndex].tagAssignmentSource = .ontology
            activities[activityIndex].ontologyCandidateID = event.ontologyCandidateID
            broadcast()
        case let event as ActivityTagSet:
            logger.log(
                "activity-actor received activity-tag-set sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public) tagID=\(event.tagID.map(String.init) ?? "<nil>", privacy: .public)"
            )
            guard let activityIndex = activities.firstIndex(where: { $0.id == event.activityID }) else {
                return
            }

            activities[activityIndex].tagID = event.tagID
            activities[activityIndex].tagAssignmentSource = event.tagID == nil ? nil : .manual
            broadcast()
        case let event as GoalTodoAssigned:
            logger.log(
                "activity-actor received goal-todo-assigned sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public) todoID=\(event.todoID, privacy: .public)"
            )
            guard let activityIndex = activities.firstIndex(where: { $0.id == event.activityID }),
                  activities[activityIndex].goalTodoAssignmentSource != .manual else {
                return
            }

            activities[activityIndex].goalTodoID = event.todoID
            activities[activityIndex].goalTodoAssignmentSource = .automatic
            activities[activityIndex].goalTodoAssignmentScore = event.score
            broadcast()
        case let event as ActivityGoalTodoSet:
            logger.log(
                "activity-actor received activity-goal-todo-set sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public) todoID=\(event.todoID.map(String.init) ?? "<nil>", privacy: .public)"
            )
            guard let activityIndex = activities.firstIndex(where: { $0.id == event.activityID }) else {
                return
            }

            pendingGoalTodoAssignments[event.mutationID] = (
                activityID: event.activityID,
                goalTodoID: activities[activityIndex].goalTodoID,
                source: activities[activityIndex].goalTodoAssignmentSource,
                score: activities[activityIndex].goalTodoAssignmentScore
            )
            activities[activityIndex].goalTodoID = event.todoID
            activities[activityIndex].goalTodoAssignmentSource = event.todoID == nil ? nil : .manual
            activities[activityIndex].goalTodoAssignmentScore = nil
            broadcast()
        case let event as ActivityGoalTodoPersistenceSucceeded:
            pendingGoalTodoAssignments.removeValue(forKey: event.mutationID)
        case let event as ActivityGoalTodoPersistenceFailed:
            logger.log(
                "activity-actor received activity-goal-todo-persistence-failed sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public)"
            )
            guard let pending = pendingGoalTodoAssignments.removeValue(forKey: event.mutationID),
                  let activityIndex = activities.firstIndex(where: { $0.id == pending.activityID }) else {
                return
            }

            activities[activityIndex].goalTodoID = pending.goalTodoID
            activities[activityIndex].goalTodoAssignmentSource = pending.source
            activities[activityIndex].goalTodoAssignmentScore = pending.score
            broadcast()
        case let event as OverviewTagSetRequested:
            logger.log(
                "activity-actor received overview-tag-set-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) overviewID=\(event.overviewID, privacy: .public) tagID=\(event.tagID, privacy: .public)"
            )
            activities = activities.map { activity in
                guard activity.overviewID == event.overviewID else {
                    return activity
                }

                var activity = activity
                activity.tagID = event.tagID
                activity.tagAssignmentSource = .manual
                activity.overviewAssignmentSource = .manual
                return activity
            }
            broadcast()
        case let event as OverviewMergeResolved:
            logger.log(
                "activity-actor received overview-merge-resolved sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) mergedOverviewID=\(event.mergedOverviewID, privacy: .public) activityCount=\(event.activityIDs.count, privacy: .public)"
            )
            let mergedActivityIDs = Set(event.activityIDs)
            activities = activities.map { activity in
                guard mergedActivityIDs.contains(activity.id) else {
                    return activity
                }

                var activity = activity
                activity.overviewID = event.mergedOverviewID
                activity.overviewAssignmentSource = .manual
                return activity
            }
            broadcast()
        case let event as ActivityDayReloadRequested:
            guard let loadedDay,
                  Calendar(identifier: .gregorian).isDate(loadedDay, inSameDayAs: event.day) else {
                return
            }

            await load(for: event.day)
        case let event as ActivityDeleted:
            logger.log(
                "activity-actor received activity-deleted sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public)"
            )
            guard let activityIndex = activities.firstIndex(where: { $0.id == event.activityID }) else {
                return
            }

            activities.remove(at: activityIndex)
            broadcast()
        default:
            return
        }
    }

    func snapshot() -> State {
        State(
            activities: activities,
            error: error
        )
    }

    func load(for date: Date) async {
        do {
            loadedDay = Calendar(identifier: .gregorian).startOfDay(for: date)
            replaceLoadedActivities(try await activityDatabaseActor.loadActivities(for: date))

            let allIdentifiers = activities.reduce(into: [Int64]()) { identifiers, activity in
                identifiers.append(activity.id)
                identifiers.append(contentsOf: activity.screenshots.map(\.id))
            }
            await identifierActor.observeExisting(allIdentifiers.max())
            broadcast()

            if Calendar(identifier: .gregorian).isDate(date, inSameDayAs: now()) {
                await enqueueScreenshotSummaries()
                await applyActivityPasses()
            }
        } catch {
            recordLoadFailure(error)
            broadcast()
        }
    }

    func loadScreenshotImage(screenshotID: Int64) async -> Data? {
        try? await activityDatabaseActor.loadScreenshotImage(screenshotID: screenshotID)
    }

    func handle(_ event: TaskTraceCaptureMonitor.Event) async {
        switch event {
        case let .appDidBecomeActive(applicationEvent):
            let eventTime = now()

            if let lastApplicationActivationAt,
               eventTime.timeIntervalSince(lastApplicationActivationAt) < Self.activationThrottleInterval {
                return
            }

            lastApplicationActivationAt = eventTime
            await processNewActivity(application: applicationEvent.appName, image: applicationEvent.image, timestamp: eventTime)
        case let .keyPress(keyEvent):
            keyboard[keyEvent.keyCode] = keyEvent
        case let .keyRelease(keyEvent):
            guard keyboard.removeValue(forKey: keyEvent.keyCode) != nil else {
                return
            }

            guard let lastIndex = activities.indices.last,
                  !Self.inactiveApplications.contains(activities[lastIndex].application) else {
                return
            }

            activities[lastIndex].keystrokes.append(keyEvent.characters)
            let activityID = activities[lastIndex].id
            broadcast()
            await actorSystem.broadcast(
                from: nil,
                message: ActivityKeystrokesAppended(
                    activityID: activityID,
                    text: keyEvent.characters
                )
            )
        case let .microphone(microphoneEvent):
            guard let lastIndex = activities.indices.last,
                  !microphoneEvent.transcript.isEmpty,
                  !Self.inactiveApplications.contains(activities[lastIndex].application) else {
                return
            }

            let existingMicrophone = activities[lastIndex].microphone
            let nextTranscript = microphoneEvent.transcript
            activities[lastIndex].microphone =
                existingMicrophone.isEmpty
                ? nextTranscript
                : "\(existingMicrophone) \(nextTranscript)"
            let activityID = activities[lastIndex].id
            broadcast()
            await actorSystem.broadcast(
                from: nil,
                message: ActivityMicrophoneAppended(
                    activityID: activityID,
                    transcript: nextTranscript
                )
            )
        case let .appMonitor(applicationEvent):
            await processAppMonitor(application: applicationEvent.appName, image: applicationEvent.image, timestamp: now())
        case let .willSleep(sleepEvent):
            await appendPause(named: "SLEEP", timestamp: sleepEvent.timestamp)
            await applyScreenshotPass()
            await applyActivityPasses(offset: 1)
        case let .osError(errorEvent):
            error = ActivityError(
                name: errorEvent.name,
                message: errorEvent.message,
                description: errorEvent.description
            )
            broadcast()
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func processNewActivity(application: String, image: Data, timestamp: Date) async {
        guard !application.hasSuffix("loginwindow") else {
            return
        }

        if let lastActivity = activities.last, lastActivity.application == application {
            return
        }

        let (activityID, screenshotID) = await {
            (
                await identifierActor.makeIdentifier(),
                await identifierActor.makeIdentifier()
            )
        }()

        let newActivity = Activity(
            id: activityID,
            application: application,
            startTime: timestamp,
            keystrokes: "",
            microphone: "",
            summary: nil,
            overviewID: nil,
            tagID: nil,
            goalTodoID: nil,
            screenshots: [
                Screenshot(
                    id: screenshotID,
                    image: image,
                    timestamp: timestamp,
                    description: nil,
                    text: nil,
                    summary: nil,
                    ignoreReason: nil
                )
            ]
        )

        activities.append(newActivity)
        broadcast()
        await actorSystem.broadcast(
            from: nil,
            message: ActivityCreated(activity: newActivity)
        )
        await applyScreenshotPass(activityIDs: [newActivity.id])
        await applyActivityPasses()
    }

    private func processAppMonitor(application: String, image: Data, timestamp: Date) async {
        guard !application.hasSuffix("loginwindow") else {
            return
        }

        guard let lastIndex = activities.indices.last else {
            await processNewActivity(application: application, image: image, timestamp: timestamp)
            return
        }

        let lastActivity = activities[lastIndex]
        let lastActivityID = activities[lastIndex].id
        guard !Self.inactiveApplications.contains(lastActivity.application), lastActivity.application == application else {
            await processNewActivity(application: application, image: image, timestamp: timestamp)
            return
        }

        let lastScreenshot = lastActivity.screenshots.last
        let screenshotID = await identifierActor.makeIdentifier()
        let lastScreenshotImage: Data? = await {
            guard let lastScreenshot else {
                return nil
            }

            if let image = lastScreenshot.image {
                return image
            }

            return try? await activityDatabaseActor.loadScreenshotImage(screenshotID: lastScreenshot.id)
        }()
        let ignoreReason: String? = if ImageSimilarity.areNearDuplicates(lastScreenshotImage, image) {
            "too similar to last screenshot"
        } else if let lastScreenshot,
                  lastScreenshot.timestamp.timeIntervalSince(timestamp) > 120 {
            "late arrival"
        } else {
            nil
        }

        if let ignoreReason {
            logger.log(
                "dropping ignored screenshot activityID=\(lastActivityID, privacy: .public) screenshotID=\(screenshotID, privacy: .public) reason=\(ignoreReason, privacy: .public)"
            )
            return
        }

        let screenshot = Screenshot(
            id: screenshotID,
            image: image,
            timestamp: timestamp,
            description: nil,
            text: nil,
            summary: nil,
            ignoreReason: nil
        )
        
        guard let index = activities.firstIndex(where: { $0.id == lastActivityID }) else {
            return
        }

        activities[index].screenshots.append(screenshot)

        if activities[index].screenshots.count > 9 {
            let dropIndex = max(1, activities[index].screenshots.count / 2)
            activities[index].screenshots.remove(at: dropIndex)
        }

        let updatedActivityID = activities[index].id
        broadcast()
        await actorSystem.broadcast(
            from: nil,
            message: ActivityUpdated(activity: activities[index])
        )
        await applyScreenshotPass(activityIDs: [updatedActivityID])
        await applyActivityPasses()
    }

    func appendPause(named pauseName: String, timestamp: Date) async {
        guard activities.last?.application != pauseName else {
            return
        }

        let pauseActivity = Activity(
            id: await identifierActor.makeIdentifier(),
            application: pauseName,
            startTime: timestamp,
            keystrokes: "",
            microphone: "",
            summary: nil,
            overviewID: nil,
            tagID: nil,
            goalTodoID: nil,
            screenshots: []
        )
        activities.append(pauseActivity)
        broadcast()
        await actorSystem.broadcast(
            from: nil,
            message: ActivityCreated(activity: pauseActivity)
        )
    }

    func applyScreenshotPass(activityIDs: Set<Int64>? = nil) async {
        let targetLabel = activityIDs.map { "\($0.count)" } ?? "all"
        logger.log(
            "applyScreenshotPass started targetedActivities=\(targetLabel, privacy: .public)"
        )
        let targetActivities = activities.enumerated().filter { pair in
            activityIDs?.contains(pair.element.id) ?? true
        }
        let dispatchRequests = targetActivities.flatMap(\.element.screenshots).compactMap { screenshot -> (
            screenshotID: Int64,
            image: Data,
            needsDescription: Bool,
            needsText: Bool
        )? in
            guard let image = screenshot.image,
                  !image.isEmpty,
                  screenshot.ignoreReason == nil,
                  screenshot.description == nil || screenshot.text == nil else {
                return nil
            }

            return (
                screenshotID: screenshot.id,
                image: image,
                needsDescription: screenshot.description == nil,
                needsText: screenshot.text == nil
            )
        }

        await withTaskGroup(of: Void.self) { group in
            dispatchRequests.forEach { dispatchRequest in
                if dispatchRequest.needsDescription {
                    group.addTask {
                        await self.actorSystem.broadcast(
                            from: nil,
                            message: DescribeImageRequest(
                                screenshotID: dispatchRequest.screenshotID,
                                image: dispatchRequest.image
                            )
                        )
                    }
                }

                if dispatchRequest.needsText {
                    group.addTask {
                        await self.actorSystem.broadcast(
                            from: nil,
                            message: ReadScreenshotTextRequest(
                                screenshotID: dispatchRequest.screenshotID,
                                image: dispatchRequest.image
                            )
                        )
                    }
                }
            }
        }

        let dispatchedScreenshotIDs = Set(dispatchRequests.map(\.screenshotID))

        guard !dispatchedScreenshotIDs.isEmpty else {
            return
        }

        activities = activities.map { activity in
            var activity = activity
            activity.screenshots = activity.screenshots.map { screenshot in
                var screenshot = screenshot
                if dispatchedScreenshotIDs.contains(screenshot.id) {
                    screenshot.image = nil
                }
                return screenshot
            }
            return activity
        }
        broadcast()
    }

    func applyActivityPasses(offset: Int = 3) async {
        let previousActivities = activities
        let (compactedActivities, _) = compactActivities(self.activities)

        if compactedActivities != activities {
            activities = compactedActivities
            broadcast()
            let previousActivitiesByID = Dictionary(uniqueKeysWithValues: previousActivities.map { ($0.id, $0) })
            let retainedActivityIDs = Set(compactedActivities.map(\.id))
            let removedActivityIDs = previousActivities
                .map(\.id)
                .filter { !retainedActivityIDs.contains($0) }

            await withTaskGroup(of: Void.self) { group in
                compactedActivities.forEach { activity in
                    guard previousActivitiesByID[activity.id] != activity else {
                        return
                    }

                    group.addTask {
                        await self.actorSystem.broadcast(
                            from: nil,
                            message: ActivityUpdated(activity: activity)
                        )
                    }
                }

                removedActivityIDs.forEach { activityID in
                    group.addTask {
                        await self.actorSystem.broadcast(
                            from: nil,
                            message: ActivityDeleted(activityID: activityID)
                        )
                    }
                }
            }
        }

        let snapshotActivities = activities
        let totalActivities = snapshotActivities.count
        let resolvedOffset = max(offset, 0)
        let finalizableCount = max(totalActivities - resolvedOffset, 0)
        let finalizableActivities = snapshotActivities
            .prefix(finalizableCount)
            .filter {
                !Self.inactiveApplications.contains($0.application)
                    && !$0.screenshots.isEmpty
                    && $0.screenshots.allSatisfy { !($0.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
            }

        await withTaskGroup(of: Void.self) { group in
            finalizableActivities
                .filter { $0.summary?.isEmpty ?? true }
                .forEach { activity in
                    let summaryActivity = {
                        var activity = activity
                        activity.screenshots = activity.screenshots.map { screenshot in
                            var screenshot = screenshot
                            screenshot.image = nil
                            screenshot.description = nil
                            screenshot.text = nil
                            return screenshot
                        }
                        return activity
                    }()
                    group.addTask {
                        await self.actorSystem.broadcast(
                            from: nil,
                            message: ActivitySummaryRequested(activity: summaryActivity)
                        )
                    }
                }
        }
    }

    private func enqueueScreenshotSummaries(activityIDs: Set<Int64>? = nil) async {
        let requests = activities
            .filter { activity in
                activityIDs?.contains(activity.id) ?? true
            }
            .flatMap(\.screenshots)
            .compactMap { screenshot -> SummarizeScreenshot? in
                guard screenshot.ignoreReason == nil,
                      screenshot.summary == nil,
                      !pendingScreenshotSummaryIDs.contains(screenshot.id),
                      let description = screenshot.description,
                      let text = screenshot.text else {
                    return nil
                }

                return SummarizeScreenshot(
                    screenshotID: screenshot.id,
                    description: description,
                    text: text
                )
            }
        pendingScreenshotSummaryIDs.formUnion(requests.map(\.screenshotID))

        await withTaskGroup(of: Void.self) { group in
            requests.forEach { request in
                group.addTask {
                    await self.actorSystem.broadcast(from: nil, message: request)
                }
            }
        }
    }

    private func compactActivities(_ activities: [Activity]) -> ([Activity], [Int64]) {
        let filteredActivities = activities.enumerated().filter { index, activity in
            guard index > 0, index < activities.count - 1 else {
                return true
            }

            let nextActivity = activities[index + 1]
            return nextActivity.startTime.timeIntervalSince(activity.startTime) > Self.minimumActivityDurationSeconds
        }.map(\.element)

        let merged = filteredActivities.reduce(into: [Activity]()) { partialResult, activity in
            guard let lastIndex = partialResult.indices.last else {
                partialResult.append(activity)
                return
            }

            if partialResult[lastIndex].application == activity.application {
                partialResult[lastIndex].screenshots = Array(
                    Dictionary(
                        uniqueKeysWithValues: (partialResult[lastIndex].screenshots + activity.screenshots).map { ($0.id, $0) }
                    )
                    .values
                    .sorted { $0.timestamp < $1.timestamp }
                )
                return
            }

            partialResult.append(activity)
        }

        let retainedIdentifiers = Set(merged.map(\.id))
        let removedIdentifiers = activities.map(\.id).filter { !retainedIdentifiers.contains($0) }
        return (merged, removedIdentifiers)
    }

    private func broadcast() {
        continuations.values.forEach { continuation in
            continuation.yield(snapshot())
        }
    }

    private func replaceLoadedActivities(_ loadedActivities: [LoadedActivity]) {
        activities = loadedActivities.map { loadedActivity in
            Activity(
                id: loadedActivity.id,
                application: loadedActivity.application,
                startTime: loadedActivity.startTime,
                keystrokes: loadedActivity.keystrokes ?? "",
                microphone: loadedActivity.microphone ?? "",
                summary: loadedActivity.summary,
                overviewID: loadedActivity.overviewID,
                overviewAssignmentSource: loadedActivity.overviewAssignmentSource,
                tagID: loadedActivity.tagID,
                tagAssignmentSource: loadedActivity.tagAssignmentSource,
                ontologyCandidateID: loadedActivity.ontologyCandidateID,
                goalTodoID: loadedActivity.goalTodoID,
                goalTodoAssignmentSource: loadedActivity.goalTodoAssignmentSource,
                goalTodoAssignmentScore: loadedActivity.goalTodoAssignmentScore,
                screenshots: loadedActivity.screenshots.map { loadedScreenshot in
                    Screenshot(
                        id: loadedScreenshot.id,
                        image: loadedScreenshot.image,
                        timestamp: loadedScreenshot.timestamp,
                        description: loadedScreenshot.description,
                        text: loadedScreenshot.text,
                        summary: loadedScreenshot.summary,
                        ignoreReason: loadedScreenshot.ignoreReason
                    )
                }
            )
        }
        pendingScreenshotSummaryIDs = []
        error = nil
    }

    private func recordLoadFailure(_ loadError: any Error) {
        error = ActivityError(
            name: "DatabaseLoadFailure",
            message: "Could not load activity state for the selected day.",
            description: String(describing: loadError)
        )
    }

}
