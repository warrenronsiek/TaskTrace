//
//  GoalsStore.swift
//  TaskTrace
//
//  Created by Codex on 5/7/26.
//

import Combine
import Foundation
import SwiftUI

nonisolated struct GoalTodoProgress: Equatable, Sendable {
    let duration: Int
    let target: Int?
    let targetMode: GoalTodoTargetMode
    let ratio: Double
    let overflowRatio: Double
}

@MainActor
final class GoalsStore: ObservableObject {
    @Published private(set) var snapshot: GoalsSnapshot
    @Published private(set) var isAddingGoal: Bool
    @Published private(set) var addingTodoGoalID: Int64?
    @Published private(set) var isAddingStandaloneTodo: Bool
    @Published private(set) var editingGoalID: Int64?
    @Published private(set) var editingTodoID: Int64?
    @Published var goalName: String
    @Published var goalDescription: String
    @Published var todoName: String
    @Published var todoRepeating: Bool
    @Published var todoHasDailyTarget: Bool
    @Published var todoDailyTargetMode: GoalTodoTargetMode
    @Published var todoDailyTargetMinutes: Double
    @Published private(set) var selectedDay: Date
    @Published private(set) var errorMessage: String?

    private let goalsDatabaseActor: GoalsDatabaseActor?
    private let actorSystem: ActorSystem?
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let identifierActor: IdentifierActor
    private var pendingSnapshots: [UUID: GoalsSnapshot]
    private var hasCenteredTimeline: Bool
    private var needsReloadAfterPendingMutations: Bool
    private var receiver: GoalsStoreEventReceiver?
    private var receiverID: UUID?

    init(
        goalsDatabaseActor: GoalsDatabaseActor,
        actorSystem: ActorSystem? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.goalsDatabaseActor = goalsDatabaseActor
        self.actorSystem = actorSystem
        self.now = now
        self.calendar = calendar
        self.identifierActor = .shared
        self.snapshot = GoalsSnapshot(
            goals: [],
            todos: [],
            goalRollups: [],
            todoRollups: [],
            dailyGoalDurations: [],
            dailyCompletedTodoCounts: []
        )
        self.isAddingGoal = false
        self.addingTodoGoalID = nil
        self.isAddingStandaloneTodo = false
        self.editingGoalID = nil
        self.editingTodoID = nil
        self.goalName = ""
        self.goalDescription = ""
        self.todoName = ""
        self.todoRepeating = false
        self.todoHasDailyTarget = false
        self.todoDailyTargetMode = .minimum
        self.todoDailyTargetMinutes = 30
        self.selectedDay = calendar.startOfDay(for: now())
        self.errorMessage = nil
        self.pendingSnapshots = [:]
        self.hasCenteredTimeline = false
        self.needsReloadAfterPendingMutations = false
        self.receiver = nil
        self.receiverID = nil

        startReceivingEvents()
    }

    convenience init(database: TaskTraceDatabase) {
        self.init(goalsDatabaseActor: GoalsDatabaseActor(database: database))
    }

    init(previewSnapshot: GoalsSnapshot) {
        self.goalsDatabaseActor = nil
        self.actorSystem = nil
        self.now = Date.init
        self.calendar = Calendar(identifier: .gregorian)
        self.identifierActor = .shared
        self.snapshot = previewSnapshot
        self.isAddingGoal = false
        self.addingTodoGoalID = nil
        self.isAddingStandaloneTodo = false
        self.editingGoalID = nil
        self.editingTodoID = nil
        self.goalName = ""
        self.goalDescription = ""
        self.todoName = ""
        self.todoRepeating = false
        self.todoHasDailyTarget = false
        self.todoDailyTargetMode = .minimum
        self.todoDailyTargetMinutes = 30
        self.selectedDay = Calendar(identifier: .gregorian).startOfDay(for: Date())
        self.errorMessage = nil
        self.pendingSnapshots = [:]
        self.hasCenteredTimeline = false
        self.needsReloadAfterPendingMutations = false
        self.receiver = nil
        self.receiverID = nil
    }

    deinit {
        guard let actorSystem, let receiverID else {
            return
        }

        Task {
            await actorSystem.unregister(receiverID)
        }
    }

    var openTodos: [GoalTodoRecord] {
        snapshot.todos.filter { todo in
            todo.status == .open
                && todo.deleteTs == nil
                && (
                    todo.goalID == nil
                    || snapshot.goals.contains { $0.id == todo.goalID && $0.doneTs == nil && $0.deleteTs == nil }
                )
        }
    }

    var openGoals: [GoalRecord] {
        snapshot.goals.filter { $0.doneTs == nil && $0.deleteTs == nil }
    }

    var visibleTimelineDays: [Date] {
        let bounds = visibleTimelineBounds()
        let dayCount = calendar.dateComponents([.day], from: bounds.start, to: bounds.end).day ?? 0

        return (0...max(dayCount, 0)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: bounds.start)
        }
    }

    var selectedDayTitle: String {
        selectedDay.formatted(date: .abbreviated, time: .omitted)
    }

    func load() async {
        guard let goalsDatabaseActor else {
            return
        }

        do {
            let bounds = visibleTimelineBounds()
            snapshot = try await goalsDatabaseActor.loadSnapshot(
                visibleStart: bounds.start,
                visibleEnd: bounds.end,
                selectedDay: selectedDay
            )
            errorMessage = nil
        } catch {
            errorMessage = "Could not load goals."
        }
    }

    func selectTimelineDay(_ day: Date) {
        let today = calendar.startOfDay(for: now())
        let requestedDay = calendar.startOfDay(for: day)

        guard requestedDay <= today else {
            return
        }

        selectedDay = requestedDay
        hasCenteredTimeline = true

        Task {
            await load()
        }
    }

    func isSelectedTimelineDay(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: selectedDay)
    }

    func isFutureTimelineDay(_ day: Date) -> Bool {
        calendar.startOfDay(for: day) > calendar.startOfDay(for: now())
    }

    func startAddingGoal() {
        isAddingGoal = true
        addingTodoGoalID = nil
        isAddingStandaloneTodo = false
        editingGoalID = nil
        editingTodoID = nil
        goalName = ""
        goalDescription = ""
        errorMessage = nil
    }

    func startEditingGoal(_ goal: GoalRecord) {
        isAddingGoal = false
        addingTodoGoalID = nil
        isAddingStandaloneTodo = false
        editingGoalID = goal.id
        editingTodoID = nil
        goalName = goal.name
        goalDescription = goal.description ?? ""
        errorMessage = nil
    }

    func cancelGoalEditor() {
        isAddingGoal = false
        editingGoalID = nil
        goalName = ""
        goalDescription = ""
        errorMessage = nil
    }

    func cancelAddingGoal() {
        cancelGoalEditor()
    }

    func saveCurrentGoal() async {
        let trimmedName = goalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = goalDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Goal name cannot be empty."
            return
        }

        let identifier = if let editingGoalID {
            editingGoalID
        } else {
            await identifierActor.makeIdentifier(
                minimum: (snapshot.goals.map(\.id).max() ?? 0) + 1
            )
        }
        let existing = snapshot.goals.first { $0.id == identifier }
        let goal = GoalRecord(
            id: identifier,
            name: trimmedName,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            createTs: existing?.createTs ?? now(),
            doneTs: existing?.doneTs,
            deleteTs: existing?.deleteTs
        )
        let input = GoalInput(
            id: goal.id,
            name: goal.name,
            description: goal.description,
            createTs: goal.createTs,
            doneTs: goal.doneTs
        )
        let mutationID = UUID()
        let previousSnapshot = snapshot

        snapshot = GoalsSnapshot(
            goals: ([goal] + snapshot.goals.filter { $0.id != goal.id })
                .sorted { lhs, rhs in
                    if (lhs.doneTs == nil) != (rhs.doneTs == nil) {
                        return lhs.doneTs == nil
                    }
                    if lhs.createTs != rhs.createTs {
                        return lhs.createTs > rhs.createTs
                    }
                    return lhs.id > rhs.id
                },
            todos: snapshot.todos,
            goalRollups: snapshot.goalRollups,
            todoRollups: snapshot.todoRollups,
            dailyGoalDurations: snapshot.dailyGoalDurations,
            dailyCompletedTodoCounts: snapshot.dailyCompletedTodoCounts
        )
        cancelGoalEditor()
        commit(
            mutationID: mutationID,
            previousSnapshot: previousSnapshot,
            message: GoalUpsertRequested(mutationID: mutationID, goal: input)
        )
    }

    func deleteEditingGoal() {
        guard let editingGoalID else {
            return
        }

        deleteGoal(id: editingGoalID)
        cancelGoalEditor()
    }

    func startAddingTodo(goalID: Int64) {
        addingTodoGoalID = goalID
        isAddingStandaloneTodo = false
        isAddingGoal = false
        editingGoalID = nil
        editingTodoID = nil
        todoName = ""
        todoRepeating = false
        todoHasDailyTarget = false
        todoDailyTargetMode = .minimum
        todoDailyTargetMinutes = 30
        errorMessage = nil
    }

    func startAddingStandaloneTodo() {
        addingTodoGoalID = nil
        isAddingStandaloneTodo = true
        isAddingGoal = false
        editingGoalID = nil
        editingTodoID = nil
        todoName = ""
        todoRepeating = false
        todoHasDailyTarget = false
        todoDailyTargetMode = .minimum
        todoDailyTargetMinutes = 30
        errorMessage = nil
    }

    func startEditingTodo(_ todo: GoalTodoRecord) {
        addingTodoGoalID = todo.goalID
        isAddingStandaloneTodo = todo.goalID == nil
        isAddingGoal = false
        editingGoalID = nil
        editingTodoID = todo.id
        todoName = todo.name
        todoRepeating = todo.repeating
        todoHasDailyTarget = todo.dailyTargetSeconds != nil
        todoDailyTargetMode = todo.dailyTargetMode
        todoDailyTargetMinutes = Double(todo.dailyTargetSeconds ?? 1_800) / 60
        errorMessage = nil
    }

    func cancelAddingTodo() {
        addingTodoGoalID = nil
        isAddingStandaloneTodo = false
        editingTodoID = nil
        todoName = ""
        todoRepeating = false
        todoHasDailyTarget = false
        todoDailyTargetMode = .minimum
        todoDailyTargetMinutes = 30
        errorMessage = nil
    }

    func saveCurrentTodo(goalID: Int64?) async {
        let trimmedName = todoName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Todo name cannot be empty."
            return
        }

        let identifier = if let editingTodoID {
            editingTodoID
        } else {
            await identifierActor.makeIdentifier(
                minimum: (snapshot.todos.map(\.id).max() ?? 0) + 1
            )
        }
        let existing = snapshot.todos.first { $0.id == identifier }
        let dailyTargetSeconds = todoHasDailyTarget ? Int(todoDailyTargetMinutes * 60) : nil
        let todo = GoalTodoRecord(
            id: identifier,
            goalID: goalID,
            name: trimmedName,
            createTs: existing?.createTs ?? now(),
            doneTs: existing?.doneTs,
            status: existing?.status ?? .open,
            statusTs: existing?.statusTs,
            repeating: todoRepeating,
            repeatTemplateID: existing?.repeatTemplateID,
            targetDate: existing?.targetDate,
            dailyTargetSeconds: dailyTargetSeconds,
            dailyTargetMode: todoHasDailyTarget ? todoDailyTargetMode : .minimum,
            embedding: existing?.embedding,
            deleteTs: existing?.deleteTs
        )
        let input = GoalTodoInput(
            id: todo.id,
            goalID: todo.goalID,
            name: todo.name,
            createTs: todo.createTs,
            status: todo.status,
            statusTs: todo.statusTs,
            repeating: todo.repeating,
            repeatTemplateID: todo.repeatTemplateID,
            targetDate: todo.targetDate,
            dailyTargetSeconds: todo.dailyTargetSeconds,
            dailyTargetMode: todo.dailyTargetMode
        )
        let mutationID = UUID()
        let previousSnapshot = snapshot

        snapshot = GoalsSnapshot(
            goals: snapshot.goals,
            todos: ([todo] + snapshot.todos.filter { $0.id != todo.id })
                .sorted { lhs, rhs in
                    if (lhs.targetDate == nil) != (rhs.targetDate == nil) {
                        return lhs.targetDate != nil
                    }
                    if let lhsDate = lhs.targetDate, let rhsDate = rhs.targetDate, lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                    if lhs.createTs != rhs.createTs {
                        return lhs.createTs > rhs.createTs
                    }
                    return lhs.id > rhs.id
                },
            goalRollups: snapshot.goalRollups,
            todoRollups: snapshot.todoRollups,
            dailyGoalDurations: snapshot.dailyGoalDurations,
            dailyCompletedTodoCounts: snapshot.dailyCompletedTodoCounts
        )
        cancelAddingTodo()
        commit(
            mutationID: mutationID,
            previousSnapshot: previousSnapshot,
            message: GoalTodoUpsertRequested(mutationID: mutationID, todo: input)
        )
    }

    func deleteEditingTodo() {
        guard let editingTodoID else {
            return
        }

        deleteTodo(id: editingTodoID)
        cancelAddingTodo()
    }

    func markGoal(
        id: Int64,
        done: Bool
    ) {
        let mutationID = UUID()
        let previousSnapshot = snapshot
        let timestamp = done ? now() : nil

        snapshot = GoalsSnapshot(
            goals: snapshot.goals.map { goal in
                guard goal.id == id else {
                    return goal
                }

                return GoalRecord(
                    id: goal.id,
                    name: goal.name,
                    description: goal.description,
                    createTs: goal.createTs,
                    doneTs: timestamp,
                    deleteTs: goal.deleteTs
                )
            },
            todos: snapshot.todos,
            goalRollups: snapshot.goalRollups,
            todoRollups: snapshot.todoRollups,
            dailyGoalDurations: snapshot.dailyGoalDurations,
            dailyCompletedTodoCounts: snapshot.dailyCompletedTodoCounts
        )
        commit(
            mutationID: mutationID,
            previousSnapshot: previousSnapshot,
            message: GoalDoneSetRequested(mutationID: mutationID, goalID: id, done: done)
        )
    }

    func setTodoStatus(
        id: Int64,
        status: GoalTodoStatus
    ) {
        let mutationID = UUID()
        let previousSnapshot = snapshot
        let timestamp = statusTimestampForSelectedDay()
        let existingTodo = snapshot.todos.first { $0.id == id }
        let updatedCompletedCounts = optimisticCompletedTodoCounts(
            oldTodo: existingTodo,
            newStatus: status,
            statusTs: timestamp
        )

        snapshot = GoalsSnapshot(
            goals: snapshot.goals,
            todos: snapshot.todos.map { todo in
                guard todo.id == id else {
                    return todo
                }

                return GoalTodoRecord(
                    id: todo.id,
                    goalID: todo.goalID,
                    name: todo.name,
                    createTs: todo.createTs,
                    doneTs: status == .done ? timestamp : nil,
                    status: status,
                    statusTs: timestamp,
                    repeating: todo.repeating,
                    repeatTemplateID: todo.repeatTemplateID,
                    targetDate: todo.targetDate,
                    dailyTargetSeconds: todo.dailyTargetSeconds,
                    dailyTargetMode: todo.dailyTargetMode,
                    embedding: todo.embedding,
                    deleteTs: todo.deleteTs
                )
            },
            goalRollups: snapshot.goalRollups,
            todoRollups: snapshot.todoRollups,
            dailyGoalDurations: snapshot.dailyGoalDurations,
            dailyCompletedTodoCounts: updatedCompletedCounts
        )
        commit(
            mutationID: mutationID,
            previousSnapshot: previousSnapshot,
            message: GoalTodoStatusSetRequested(
                mutationID: mutationID,
                todoID: id,
                status: status,
                statusTs: timestamp
            )
        )
    }

    func assignActivity(
        activityID: Int64,
        todoID: Int64?
    ) async {
        guard let actorSystem else {
            return
        }

        await actorSystem.broadcast(
            from: nil,
            message: ActivityGoalTodoSet(
                mutationID: UUID(),
                activityID: activityID,
                todoID: todoID
            )
        )
    }

    func todos(for goalID: Int64) -> [GoalTodoRecord] {
        snapshot.todos.filter { $0.goalID == goalID && $0.deleteTs == nil }
    }

    var standaloneTodos: [GoalTodoRecord] {
        snapshot.todos.filter { $0.goalID == nil && $0.deleteTs == nil }
    }

    func durationForGoal(id: Int64) -> Int {
        snapshot.goalRollups.first { $0.goalID == id }?.duration ?? 0
    }

    func durationForTodo(id: Int64) -> Int {
        snapshot.todoRollups.first { $0.todoID == id }?.duration ?? 0
    }

    func dailyDurationForGoal(
        id: Int64,
        day: Date
    ) -> Int {
        snapshot.dailyGoalDurations.first { rollup in
            rollup.goalID == id && calendar.isDate(rollup.day, inSameDayAs: day)
        }?.duration ?? 0
    }

    func completedTodoCount(on day: Date) -> Int {
        snapshot.dailyCompletedTodoCounts.filter { rollup in
            calendar.isDate(rollup.day, inSameDayAs: day)
        }.reduce(0) { total, rollup in
            total + rollup.completedCount
        }
    }

    func completedTodoCount(
        goalID: Int64?,
        on day: Date
    ) -> Int {
        snapshot.dailyCompletedTodoCounts.first { rollup in
            rollup.goalID == goalID && calendar.isDate(rollup.day, inSameDayAs: day)
        }?.completedCount ?? 0
    }

    func goalColor(_ goal: GoalRecord) -> Color {
        AppColors.analyticsTagColor(for: "goal-\(goal.id)-\(goal.name)")
    }

    var standaloneTodoColor: Color {
        AppColors.textSecondary
    }

    func todoProgress(id: Int64) -> GoalTodoProgress {
        let duration = durationForTodo(id: id)
        let todo = snapshot.todos.first { $0.id == id }
        let target = todo?.dailyTargetSeconds
        let targetMode = todo?.dailyTargetMode ?? .minimum

        guard let target, target > 0 else {
            return GoalTodoProgress(duration: duration, target: nil, targetMode: targetMode, ratio: 0, overflowRatio: 0)
        }

        return GoalTodoProgress(
            duration: duration,
            target: target,
            targetMode: targetMode,
            ratio: min(Double(duration) / Double(target), 1),
            overflowRatio: max(Double(duration - target) / Double(target), 0)
        )
    }

    func toggleTodoDone(_ todo: GoalTodoRecord) {
        setTodoStatus(id: todo.id, status: todo.status == .done ? .open : .done)
    }

    func selectedDayDurationForTodo(id: Int64) -> Int {
        durationForTodo(id: id)
    }

    func goalName(for goalID: Int64?) -> String? {
        guard let goalID else {
            return nil
        }

        return snapshot.goals.first { $0.id == goalID }?.name
    }

    func todoName(for todoID: Int64?) -> String? {
        guard let todoID else {
            return nil
        }

        return snapshot.todos.first { $0.id == todoID }?.name
    }

    func goalID(forTodoID todoID: Int64?) -> Int64? {
        guard let todoID else {
            return nil
        }

        return snapshot.todos.first { $0.id == todoID }?.goalID
    }

    private func deleteGoal(id: Int64) {
        let mutationID = UUID()
        let previousSnapshot = snapshot

        snapshot = GoalsSnapshot(
            goals: snapshot.goals.filter { $0.id != id },
            todos: snapshot.todos.filter { $0.goalID != id },
            goalRollups: snapshot.goalRollups.filter { $0.goalID != id },
            todoRollups: snapshot.todoRollups.filter { rollup in
                !snapshot.todos.contains { $0.id == rollup.todoID && $0.goalID == id }
            },
            dailyGoalDurations: snapshot.dailyGoalDurations.filter { $0.goalID != id },
            dailyCompletedTodoCounts: snapshot.dailyCompletedTodoCounts
        )
        commit(
            mutationID: mutationID,
            previousSnapshot: previousSnapshot,
            message: GoalDeleteRequested(mutationID: mutationID, goalID: id)
        )
    }

    private func deleteTodo(id: Int64) {
        let mutationID = UUID()
        let previousSnapshot = snapshot

        snapshot = GoalsSnapshot(
            goals: snapshot.goals,
            todos: snapshot.todos.filter { $0.id != id },
            goalRollups: snapshot.goalRollups,
            todoRollups: snapshot.todoRollups.filter { $0.todoID != id },
            dailyGoalDurations: snapshot.dailyGoalDurations,
            dailyCompletedTodoCounts: snapshot.dailyCompletedTodoCounts
        )
        commit(
            mutationID: mutationID,
            previousSnapshot: previousSnapshot,
            message: GoalTodoDeleteRequested(mutationID: mutationID, todoID: id)
        )
    }

    private func commit(
        mutationID: UUID,
        previousSnapshot: GoalsSnapshot,
        message: any Sendable
    ) {
        errorMessage = nil
        pendingSnapshots[mutationID] = previousSnapshot

        guard let actorSystem else {
            pendingSnapshots.removeValue(forKey: mutationID)
            return
        }

        Task {
            await actorSystem.broadcast(from: nil, message: message)
        }
    }

    private func optimisticCompletedTodoCounts(
        oldTodo: GoalTodoRecord?,
        newStatus: GoalTodoStatus,
        statusTs: Date
    ) -> [DailyCompletedTodoCount] {
        let oldDay = oldTodo.flatMap { completionDay(for: $0, status: $0.status, statusTs: $0.statusTs) }
        let newDay = oldTodo.flatMap { completionDay(for: $0, status: newStatus, statusTs: statusTs) }

        guard oldDay != newDay else {
            return snapshot.dailyCompletedTodoCounts
        }

        guard let oldTodo else {
            return snapshot.dailyCompletedTodoCounts
        }

        let updates = [
            oldDay.map { (calendar.startOfDay(for: $0), -1) },
            newDay.map { (calendar.startOfDay(for: $0), 1) }
        ]
        .compactMap { $0 }

        return updates.reduce(into: snapshot.dailyCompletedTodoCounts) { counts, update in
            let (day, delta) = update

            guard visibleTimelineDays.contains(where: { calendar.isDate($0, inSameDayAs: day) }) else {
                return
            }

            if let index = counts.firstIndex(where: { $0.goalID == oldTodo.goalID && calendar.isDate($0.day, inSameDayAs: day) }) {
                let nextCount = max(counts[index].completedCount + delta, 0)
                counts[index] = DailyCompletedTodoCount(goalID: counts[index].goalID, day: counts[index].day, completedCount: nextCount)
            } else if delta > 0 {
                counts.append(DailyCompletedTodoCount(goalID: oldTodo.goalID, day: day, completedCount: delta))
            }

            counts = counts
                .filter { $0.completedCount > 0 }
                .sorted { lhs, rhs in
                    if lhs.day != rhs.day {
                        return lhs.day < rhs.day
                    }
                    return (lhs.goalID ?? Int64.max) < (rhs.goalID ?? Int64.max)
                }
        }
    }

    private func completionDay(
        for todo: GoalTodoRecord,
        status: GoalTodoStatus,
        statusTs: Date?
    ) -> Date? {
        guard status == .done else {
            return nil
        }

        return todo.doneTs ?? statusTs
    }

    private func statusTimestampForSelectedDay() -> Date {
        let current = now()
        let today = calendar.startOfDay(for: current)

        guard selectedDay < today else {
            return current
        }

        return calendar.date(byAdding: .hour, value: 12, to: selectedDay) ?? selectedDay
    }

    private func visibleTimelineBounds() -> DateInterval {
        let today = calendar.startOfDay(for: now())

        if hasCenteredTimeline {
            let requestedEnd = calendar.date(byAdding: .day, value: 3, to: selectedDay) ?? selectedDay
            let end = min(requestedEnd, today)
            let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
            return DateInterval(start: start, end: end)
        }

        let start = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        return DateInterval(start: start, end: today)
    }

    private func startReceivingEvents() {
        guard let actorSystem else {
            return
        }

        let receiver = GoalsStoreEventReceiver { [weak self] envelope in
            await MainActor.run {
                self?.receive(envelope)
            }
        }
        self.receiver = receiver

        Task { [weak self, actorSystem, receiver] in
            let id = await actorSystem.register(receiver)
            await MainActor.run {
                self?.receiverID = id
            }
        }
    }

    private func receive(_ envelope: Envelope) {
        switch envelope.message {
        case let event as GoalMutationPersisted:
            pendingSnapshots.removeValue(forKey: event.mutationID)
            errorMessage = nil
            loadAfterPendingMutationsIfNeeded()
        case let event as GoalMutationFailed:
            if let previousSnapshot = pendingSnapshots.removeValue(forKey: event.mutationID) {
                snapshot = previousSnapshot
            }
            errorMessage = event.errorMessage.isEmpty ? "Could not save goals." : "Could not save goals: \(event.errorMessage)"
            loadAfterPendingMutationsIfNeeded()
        case _ as GoalsReloadRequested:
            reloadWhenNoMutationsArePending()
        default:
            return
        }
    }

    private func reloadWhenNoMutationsArePending() {
        guard pendingSnapshots.isEmpty else {
            needsReloadAfterPendingMutations = true
            return
        }

        needsReloadAfterPendingMutations = false
        Task {
            await load()
        }
    }

    private func loadAfterPendingMutationsIfNeeded() {
        guard pendingSnapshots.isEmpty, needsReloadAfterPendingMutations else {
            return
        }

        reloadWhenNoMutationsArePending()
    }

    private func weekInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(
            start: calendar.startOfDay(for: date),
            duration: 86_400 * 7
        )
    }
}

private actor GoalsStoreEventReceiver: Receiver {
    private let handler: @Sendable (Envelope) async -> Void

    init(handler: @escaping @Sendable (Envelope) async -> Void) {
        self.handler = handler
    }

    func receive(_ envelope: Envelope) async {
        await handler(envelope)
    }
}
