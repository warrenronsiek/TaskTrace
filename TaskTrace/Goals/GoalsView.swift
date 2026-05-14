//
//  GoalsView.swift
//  TaskTrace
//
//  Created by Codex on 5/7/26.
//

import Foundation
import SwiftUI

struct GoalsView: View {
    @ObservedObject var goalsStore: GoalsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let errorMessage = goalsStore.errorMessage {
                    Text(errorMessage)
                        .font(Styles.Fonts.footnote)
                        .foregroundStyle(AppColors.danger)
                }

                GoalsWeeklyChart(goalsStore: goalsStore)

                goalsList
            }
            .padding(24)
            .frame(maxWidth: 1160)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Goals")
        .sheet(
            isPresented: Binding(
                get: { goalsStore.isAddingGoal || goalsStore.editingGoalID != nil },
                set: { isPresented in
                    if !isPresented {
                        goalsStore.cancelGoalEditor()
                    }
                }
            )
        ) {
            goalForm
                .padding(24)
                .frame(width: 520)
        }
        .sheet(
            isPresented: Binding(
                get: { goalsStore.addingTodoGoalID != nil || goalsStore.isAddingStandaloneTodo || goalsStore.editingTodoID != nil },
                set: { isPresented in
                    if !isPresented {
                        goalsStore.cancelAddingTodo()
                    }
                }
            )
        ) {
            todoForm(goalID: goalsStore.addingTodoGoalID)
                .padding(24)
                .frame(width: 520)
        }
        .task {
            await goalsStore.load()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Goals")
                    .font(Styles.Fonts.title3Semibold)

                Text("Plan work, attach activity, and track time by outcome.")
                    .font(Styles.Fonts.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Button {
                goalsStore.startAddingGoal()
            } label: {
                Label("Add Goal", systemImage: "plus")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(goalsStore.isAddingGoal || goalsStore.editingGoalID != nil)

            Button {
                goalsStore.startAddingStandaloneTodo()
            } label: {
                Label("Add Todo", systemImage: "checklist")
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .disabled(goalsStore.isAddingGoal || goalsStore.editingGoalID != nil)
        }
    }

    private var goalForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Goal name", text: $goalsStore.goalName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            TextField("Description", text: $goalsStore.goalDescription, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 10) {
                Button(goalsStore.editingGoalID == nil ? "Save Goal" : "Save Changes") {
                    Task { await goalsStore.saveCurrentGoal() }
                }
                .buttonStyle(.borderedProminent)

                if goalsStore.editingGoalID != nil {
                    Button("Delete", role: .destructive) {
                        goalsStore.deleteEditingGoal()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Cancel") {
                    goalsStore.cancelGoalEditor()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .backgroundExtensionEffect()
    }

    private var goalsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Available on \(goalsStore.selectedDayTitle)")
                    .font(Styles.Fonts.headline)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, goalsStore.snapshot.goals.isEmpty ? 0 : 4)

            if goalsStore.snapshot.goals.isEmpty {
                Text("No goals were available on this day.")
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
            } else {
                ForEach(goalsStore.snapshot.goals) { goal in
                    goalSection(goal)

                    if goal.id != goalsStore.snapshot.goals.last?.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }

            if !goalsStore.snapshot.goals.isEmpty {
                Divider().padding(.horizontal, 16)
            }

            standaloneSection
        }
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .backgroundExtensionEffect()
    }

    private func goalSection(_ goal: GoalRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(goalsStore.goalColor(goal))
                            .frame(width: 9, height: 9)

                        Text(goal.name)
                            .font(Styles.Fonts.headline)

                        statusBadge(goal.doneTs == nil ? "Open" : "Done")
                    }

                    if let description = goal.description {
                        Text(description)
                            .font(Styles.Fonts.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                Spacer()

                Text(formatDuration(goalsStore.durationForGoal(id: goal.id)))
                    .font(Styles.Fonts.subheadlineSemibold)
                    .foregroundStyle(AppColors.accent)

                Button {
                    goalsStore.markGoal(id: goal.id, done: goal.doneTs == nil)
                } label: {
                    Image(systemName: goal.doneTs == nil ? "checkmark.circle" : "arrow.uturn.backward.circle")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .help(goal.doneTs == nil ? "Mark done" : "Reopen")

                Button {
                    goalsStore.startEditingGoal(goal)
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("Edit goal")
            }

            let todos = goalsStore.todos(for: goal.id)

            if todos.isEmpty {
                Text("No todos yet.")
                    .font(Styles.Fonts.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(todos) { todo in
                        todoRow(todo)
                    }
                }
            }

            if goal.doneTs == nil {
                Button {
                    goalsStore.startAddingTodo(goalID: goal.id)
                } label: {
                    Label("Add Todo", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
    }

    private func todoRow(_ todo: GoalTodoRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            TodoCompletionButton(
                status: todo.status,
                action: {
                    goalsStore.toggleTodoDone(todo)
                }
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(todo.name)
                        .font(Styles.Fonts.subheadlineSemibold)

                    statusBadge(todo.status.rawValue.capitalized)
                }

                HStack(spacing: 8) {
                    if todo.repeating {
                        Label("Repeats", systemImage: "repeat")
                    }

                    if let targetDate = todo.targetDate {
                        Label(targetDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }

                    if let target = todo.dailyTargetSeconds {
                        Label(todoTargetLabel(todo.dailyTargetMode, target), systemImage: "timer")
                    }
                }
                .font(Styles.Fonts.footnote)
                .foregroundStyle(AppColors.textSecondary)

                TodoProgressBar(progress: goalsStore.todoProgress(id: todo.id))
            }

            Spacer(minLength: 8)

            Button {
                goalsStore.startEditingTodo(todo)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Edit todo")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var standaloneSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(goalsStore.standaloneTodoColor)
                        .frame(width: 9, height: 9)

                    Text("Standalone Todos")
                        .font(Styles.Fonts.headline)
                }

                Spacer()
            }

            if goalsStore.standaloneTodos.isEmpty {
                Text("No standalone todos yet.")
                    .font(Styles.Fonts.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(goalsStore.standaloneTodos) { todo in
                        todoRow(todo)
                    }
                }
            }

            Button {
                goalsStore.startAddingStandaloneTodo()
            } label: {
                Label("Add Todo", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
    }

    private func todoForm(goalID: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Todo name", text: $goalsStore.todoName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Toggle("Repeat daily until deleted", isOn: $goalsStore.todoRepeating)

            Toggle("Daily time target", isOn: $goalsStore.todoHasDailyTarget)

            if goalsStore.todoHasDailyTarget {
                Picker("Target mode", selection: $goalsStore.todoDailyTargetMode) {
                    Text("At least").tag(GoalTodoTargetMode.minimum)
                    Text("At most").tag(GoalTodoTargetMode.maximum)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    Slider(value: $goalsStore.todoDailyTargetMinutes, in: 5...480, step: 5)
                    Text("\(Int(goalsStore.todoDailyTargetMinutes)) min")
                        .font(Styles.Fonts.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 64, alignment: .trailing)
                }
            }

            HStack(spacing: 10) {
                Button(goalsStore.editingTodoID == nil ? "Save Todo" : "Save Changes") {
                    Task { await goalsStore.saveCurrentTodo(goalID: goalID) }
                }
                .buttonStyle(.borderedProminent)

                if goalsStore.editingTodoID != nil {
                    Button("Delete", role: .destructive) {
                        goalsStore.deleteEditingTodo()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Cancel") {
                    goalsStore.cancelAddingTodo()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(AppColors.insetBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusBadge(_ text: String) -> some View {
        Text(text)
            .font(Styles.Fonts.footnote)
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppColors.insetBackground, in: Capsule(style: .continuous))
    }

    private func formatDuration(_ seconds: Int) -> String {
        formatGoalDuration(seconds)
    }

    private func todoTargetLabel(_ mode: GoalTodoTargetMode, _ seconds: Int) -> String {
        switch mode {
        case .minimum:
            return "At least \(formatDuration(seconds))"
        case .maximum:
            return "At most \(formatDuration(seconds))"
        }
    }
}

private struct GoalsWeeklyChart: View {
    @ObservedObject var goalsStore: GoalsStore

    private var goals: [GoalRecord] {
        goalsStore.snapshot.goals
    }

    private var days: [Date] {
        goalsStore.visibleTimelineDays
    }

    private var maxDuration: Int {
        max(
            goals.flatMap { goal in
                days.map { goalsStore.dailyDurationForGoal(id: goal.id, day: $0) }
            }.max() ?? 0,
            3_600
        )
    }

    private var maxOutcomeCount: Int {
        max(
            days.map { max(goalsStore.completedTodoCount(on: $0), goalsStore.failedTodoCount(on: $0)) }.max() ?? 0,
            1
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Timeline")
                    .font(Styles.Fonts.headline)

                Spacer()

                Text(goalsStore.selectedDayTitle)
                    .font(Styles.Fonts.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            }

            legend

            GeometryReader { proxy in
                let chartHeight = max(proxy.size.height - 24, 1)
                let chartWidth = max(proxy.size.width - 84, 1)
                let geometry = GoalsTimelineGeometry(height: chartHeight, maxDuration: maxDuration)

                HStack(alignment: .top, spacing: 8) {
                    yAxis(
                        top: formatGoalDuration(maxDuration),
                        zero: "0m",
                        width: 44,
                        height: chartHeight,
                        zeroY: geometry.zeroY
                    )

                    VStack(spacing: 6) {
                        chartCanvas(width: chartWidth, height: chartHeight)

                        HStack(spacing: 0) {
                            ForEach(days, id: \.self) { day in
                                dayLabel(day)
                            }
                        }
                    }
                    .frame(width: chartWidth)

                    yAxis(
                        top: "\(maxOutcomeCount)",
                        zero: "0",
                        bottom: "-\(maxOutcomeCount)",
                        width: 24,
                        height: chartHeight,
                        zeroY: geometry.zeroY
                    )
                }
            }
            .frame(height: 232)
        }
        .padding(16)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .backgroundExtensionEffect()
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(goals) { goal in
                HStack(spacing: 6) {
                    Circle()
                        .fill(goalsStore.goalColor(goal))
                        .frame(width: 8, height: 8)

                    Text(goal.name)
                        .font(Styles.Fonts.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func chartCanvas(
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let geometry = GoalsTimelineGeometry(height: height, maxDuration: maxDuration)

        return ZStack(alignment: .topLeading) {
            ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                Rectangle()
                    .fill(AppColors.timelineGrid)
                    .frame(height: 1)
                    .offset(y: height - height * fraction)
            }

            Rectangle()
                .fill(AppColors.textSecondary.opacity(0.26))
                .frame(height: 1)
                .offset(y: geometry.zeroY)

            ForEach(Array(days.enumerated()), id: \.offset) { pair in
                let barWidth = max(width / CGFloat(max(days.count, 1)) * 0.34, 8)

                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        ForEach(completedBarSegments(on: pair.element).reversed()) { segment in
                            Rectangle()
                                .fill(segment.color.opacity(0.58))
                                .frame(
                                    width: barWidth,
                                    height: geometry.completedBarHeight(count: segment.count, maxOutcomeCount: maxOutcomeCount)
                                )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .frame(width: barWidth, height: geometry.zeroY, alignment: .bottom)
                    .offset(y: 0)

                    VStack(spacing: 0) {
                        ForEach(failedBarSegments(on: pair.element)) { segment in
                            Rectangle()
                                .fill(segment.color.opacity(0.72))
                                .frame(
                                    width: barWidth,
                                    height: geometry.failedBarHeight(count: segment.count, maxOutcomeCount: maxOutcomeCount)
                                )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .frame(width: barWidth, height: height - geometry.zeroY, alignment: .top)
                    .offset(y: geometry.zeroY)
                }
                .frame(width: barWidth, height: height, alignment: .top)
                .position(
                    x: xPosition(index: pair.offset, width: width),
                    y: height / 2
                )
            }

            ForEach(goals) { goal in
                linePath(goal: goal, width: width, height: height)
                    .stroke(
                        goalsStore.goalColor(goal),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )

                ForEach(Array(days.enumerated()), id: \.offset) { pair in
                    let duration = goalsStore.dailyDurationForGoal(id: goal.id, day: pair.element)

                    if duration > 0 {
                        Circle()
                            .fill(goalsStore.goalColor(goal))
                            .frame(width: 6, height: 6)
                            .position(
                                x: xPosition(index: pair.offset, width: width),
                                y: yPosition(duration: duration, height: height)
                            )
                    }
                }
            }

            ForEach(Array(days.enumerated()), id: \.offset) { pair in
                if !goalsStore.isFutureTimelineDay(pair.element) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .frame(
                            width: max(width / CGFloat(max(days.count, 1)), 28),
                            height: height
                        )
                        .position(
                            x: xPosition(index: pair.offset, width: width),
                            y: height / 2
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                                goalsStore.selectTimelineDay(pair.element)
                            }
                        }
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private func dayLabelColor(_ day: Date) -> Color {
        if goalsStore.isFutureTimelineDay(day) {
            return AppColors.textSecondary.opacity(0.34)
        }

        return goalsStore.isSelectedTimelineDay(day) ? AppColors.accent : AppColors.textSecondary
    }

    private func dayLabel(_ day: Date) -> some View {
        Text(day, format: .dateTime.weekday(.narrow))
            .font(Styles.Fonts.caption2)
            .foregroundStyle(dayLabelColor(day))
            .frame(width: 22, height: 22)
            .background {
                if goalsStore.isSelectedTimelineDay(day) {
                    Circle()
                        .fill(AppColors.accent.opacity(0.16))
                        .shadow(color: AppColors.accent.opacity(0.64), radius: 8)
                        .overlay {
                            Circle()
                                .strokeBorder(AppColors.accent.opacity(0.44), lineWidth: 1)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !goalsStore.isFutureTimelineDay(day) else {
                    return
                }

                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    goalsStore.selectTimelineDay(day)
                }
            }
    }

    private func completedBarSegments(on day: Date) -> [CompletedTodoBarSegment] {
        let goalSegments = goals.compactMap { goal in
            let count = goalsStore.completedTodoCount(goalID: goal.id, on: day)
            return count > 0 ? CompletedTodoBarSegment(id: "goal-\(goal.id)", color: goalsStore.goalColor(goal), count: count) : nil
        }
        let standaloneCount = goalsStore.completedTodoCount(goalID: nil, on: day)

        return goalSegments + [
            standaloneCount > 0
                ? CompletedTodoBarSegment(id: "standalone", color: goalsStore.standaloneTodoColor, count: standaloneCount)
                : nil
        ].compactMap { $0 }
    }

    private func failedBarSegments(on day: Date) -> [CompletedTodoBarSegment] {
        let goalSegments = goals.compactMap { goal in
            let count = goalsStore.failedTodoCount(goalID: goal.id, on: day)
            return count > 0 ? CompletedTodoBarSegment(id: "failed-goal-\(goal.id)", color: AppColors.danger, count: count) : nil
        }
        let standaloneCount = goalsStore.failedTodoCount(goalID: nil, on: day)

        return goalSegments + [
            standaloneCount > 0
                ? CompletedTodoBarSegment(id: "failed-standalone", color: AppColors.danger, count: standaloneCount)
                : nil
        ].compactMap { $0 }
    }

    private func yAxis(
        top: String,
        zero: String,
        bottom: String? = nil,
        width: CGFloat,
        height: CGFloat,
        zeroY: CGFloat
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Text(top)
                .frame(width: width, height: height, alignment: .topTrailing)

            Text(zero)
                .frame(width: width, height: 12, alignment: .trailing)
                .offset(y: min(max(zeroY - 6, 0), max(height - 12, 0)))

            if let bottom {
                Text(bottom)
                    .frame(width: width, height: height, alignment: .bottomTrailing)
            }
        }
        .font(Styles.Fonts.caption2)
        .foregroundStyle(AppColors.textSecondary)
        .frame(width: width, height: height, alignment: .trailing)
    }

    private func linePath(
        goal: GoalRecord,
        width: CGFloat,
        height: CGFloat
    ) -> Path {
        Path { path in
            days.enumerated().forEach { index, day in
                let point = CGPoint(
                    x: xPosition(index: index, width: width),
                    y: yPosition(
                        duration: goalsStore.dailyDurationForGoal(id: goal.id, day: day),
                        height: height
                    )
                )

                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func xPosition(
        index: Int,
        width: CGFloat
    ) -> CGFloat {
        let dayWidth = width / CGFloat(max(days.count, 1))
        return dayWidth * (CGFloat(index) + 0.5)
    }

    private func yPosition(
        duration: Int,
        height: CGFloat
    ) -> CGFloat {
        GoalsTimelineGeometry(height: height, maxDuration: maxDuration).timeY(duration: duration)
    }

}

private struct CompletedTodoBarSegment: Identifiable {
    let id: String
    let color: Color
    let count: Int
}

private struct TodoCompletionButton: View {
    let status: GoalTodoStatus
    let action: () -> Void

    @State private var isChecking = false

    private var isDone: Bool {
        status == .done
    }

    var body: some View {
        Button {
            if !isDone {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
                    isChecking = true
                }
                Task {
                    try? await Task.sleep(nanoseconds: 620_000_000)
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.18)) {
                            isChecking = false
                        }
                    }
                }
            }

            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fillColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(strokeColor, lineWidth: 1.4)
                    }

                Image(systemName: status == .failed ? "xmark" : "checkmark")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(iconColor)
                    .scaleEffect(isChecking ? 1.28 : 1)

                if isChecking {
                    Text("CHECK")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(AppColors.textOnAccent)
                        .offset(y: 23)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .help(isDone ? "Reopen todo" : "Mark todo done")
    }

    private var fillColor: Color {
        if isDone || isChecking {
            return AppColors.success
        }

        if status == .failed {
            return AppColors.danger.opacity(0.18)
        }

        return AppColors.insetBackground
    }

    private var strokeColor: Color {
        if isDone || isChecking {
            return AppColors.success
        }

        if status == .failed {
            return AppColors.danger.opacity(0.72)
        }

        return AppColors.textSecondary.opacity(0.28)
    }

    private var iconColor: Color {
        if isDone || isChecking {
            return AppColors.textOnAccent
        }

        if status == .failed {
            return AppColors.danger
        }

        return .clear
    }
}

private struct TodoProgressBar: View {
    let progress: GoalTodoProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let target = progress.target {
                GeometryReader { proxy in
                    let width = max(proxy.size.width, 1)
                    let fillWidth = width * progress.ratio
                    let tickerX = min(max(fillWidth, 3), width - 3)
                    let fillColor = switch progress.targetMode {
                    case .minimum:
                        progress.duration >= target ? AppColors.success.opacity(0.72) : AppColors.accent.opacity(0.72)
                    case .maximum:
                        progress.duration <= target ? AppColors.success.opacity(0.72) : AppColors.danger.opacity(0.72)
                    }

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(AppColors.chipBackground)

                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(fillColor)
                            .frame(width: max(fillWidth, progress.duration > 0 ? 4 : 0))

                        Rectangle()
                            .fill(AppColors.textPrimary.opacity(0.72))
                            .frame(width: 2)
                            .offset(x: tickerX)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text(formatGoalDuration(progress.duration))

                    if progress.overflowRatio > 0 {
                        Text("+\(formatGoalDuration(max(progress.duration - target, 0)))")
                            .foregroundStyle(progress.targetMode == .maximum ? AppColors.danger : AppColors.success)
                    }

                    Spacer()

                    Text(progress.targetMode == .maximum ? "limit \(formatGoalDuration(target))" : "target \(formatGoalDuration(target))")
                }
                .font(Styles.Fonts.caption2)
                .foregroundStyle(AppColors.textSecondary)
            } else {
                Text("\(formatGoalDuration(progress.duration)) tracked")
                    .font(Styles.Fonts.caption2)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

private func formatGoalDuration(_ seconds: Int) -> String {
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60

    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
}
