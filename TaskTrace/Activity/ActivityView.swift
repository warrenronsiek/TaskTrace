//
//  ActivityView.swift
//  TaskTrace
//
//  Created by Codex on 3/12/26.
//

import AppKit
import OSLog
import SwiftUI

private let activityViewLogger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "activity-view")

private struct ActivityTagChoice: Identifiable {
    let id: Int64?
    let title: String
}

struct ActivityView: View {
    @ObservedObject var activityStore: ActivityStore
    @ObservedObject var tagsStore: TagsStore
    let onShowTimelineForActivity: (Int64, Date) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let error = activityStore.state.error {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(error.name)
                                .font(Styles.Fonts.headline)
                            Text(error.message)
                            Text(error.description)
                                .font(Styles.Fonts.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.errorBackground, in: RoundedRectangle(cornerRadius: 12))
                    }

                    if activityStore.state.activities.isEmpty {
                        Text("No activities yet.")
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 48)
                    } else {
                        ForEach(renderedActivities) { activity in
                            ActivityCard(
                                activity: activity,
                                tagName: tagName(for: activity.tagID),
                                tagChoices: activityTagChoices,
                                endTime: endTime(for: activity.id),
                                duration: duration(for: activity.id),
                                onShowTimelineForActivity: onShowTimelineForActivity,
                                loadScreenshotImage: { screenshotID in
                                    await activityStore.loadScreenshotImage(screenshotID: screenshotID)
                                },
                                onSelectTag: { tagID in
                                    await activityStore.setTag(activityID: activity.id, tagID: tagID)
                                },
                                onDelete: {
                                    await activityStore.deleteActivity(activityID: activity.id)
                                }
                            )
                            .id(activity.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                }
                .padding(20)
            }
            .task(id: activityStore.focusedActivityID) {
                guard let focusedActivityID = activityStore.focusedActivityID else {
                    return
                }

                await Task.yield()

                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                    proxy.scrollTo(focusedActivityID, anchor: .center)
                }

                activityStore.clearFocusedActivity(activityID: focusedActivityID)
            }
        }
        .navigationTitle("Activity")
        .animation(.spring(response: 0.30, dampingFraction: 0.84), value: renderedActivities.map(\.id))
    }

    private var renderedActivities: [ActivityActor.Activity] {
        activityStore.state.activities.sorted { $0.startTime > $1.startTime }
    }

    private func endTime(for activityID: Int64) -> Date? {
        let ascending = activityStore.state.activities.sorted { $0.startTime < $1.startTime }
        guard let index = ascending.firstIndex(where: { $0.id == activityID }), index < ascending.count - 1 else {
            return nil
        }

        return ascending[index + 1].startTime
    }

    private func duration(for activityID: Int64) -> TimeInterval? {
        guard let endTime = endTime(for: activityID),
              let startTime = activityStore.state.activities.first(where: { $0.id == activityID })?.startTime else {
            return nil
        }

        return endTime.timeIntervalSince(startTime)
    }

    private func tagName(for tagID: Int64?) -> String? {
        guard let tagID else {
            return nil
        }

        return activityTagChoices.first(where: { $0.id == tagID })?.title
    }

    private var activityTagChoices: [ActivityTagChoice] {
        let userTagChoices = tagsStore.tags
            .filter { !SystemTags.isProtected($0.id) }
            .compactMap { tag in
                tag.name.map { ActivityTagChoice(id: tag.id, title: $0) }
            }

        return [
            ActivityTagChoice(id: nil, title: "No Tag"),
            ActivityTagChoice(id: SystemTags.inactiveID, title: SystemTags.inactiveName),
            ActivityTagChoice(id: SystemTags.taggingFailureID, title: SystemTags.taggingFailureName)
        ] + userTagChoices
    }
}

private struct ActivityCard: View {
    private enum Panel: String, CaseIterable, Hashable {
        case summary = "Summary"
        case keystrokes = "Keystrokes"
        case microphone = "Microphone"
        case screenshots = "Screenshots"

        var systemImage: String {
            switch self {
            case .summary:
                "text.alignleft"
            case .keystrokes:
                "keyboard"
            case .microphone:
                "mic"
            case .screenshots:
                "display"
            }
        }
    }

    let activity: ActivityActor.Activity
    let tagName: String?
    let tagChoices: [ActivityTagChoice]
    let endTime: Date?
    let duration: TimeInterval?
    let onShowTimelineForActivity: (Int64, Date) -> Void
    let loadScreenshotImage: @MainActor @Sendable (Int64) async -> Data?
    let onSelectTag: @MainActor @Sendable (Int64?) async -> Void
    let onDelete: @MainActor @Sendable () async -> Void
    @State private var selectedPanel: Panel = .summary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBar

            if !availablePanels.isEmpty {
                HStack(alignment: .top, spacing: 18) {
                    panelSelector
                    panelContent
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .backgroundExtensionEffect()
    }

    @ViewBuilder
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.application.split(separator: ".").last.map(String.init) ?? activity.application)
                    .font(Styles.Fonts.headline)
                    .help(activity.application)
                if let duration {
                    Label(formattedDuration(duration), systemImage: "timer")
                        .font(Styles.Fonts.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: activity.tagID == nil ? "tag" : "tag.fill")
                    .font(Styles.Fonts.subheadlineSemibold)
                    .foregroundStyle(activity.tagID == nil ? AppColors.textSecondary : AppColors.textPrimary)
                    .help(tagName ?? "No Tag")

                if let overviewID = activity.overviewID {
                    Button {
                        onShowTimelineForActivity(activity.id, activity.startTime)
                    } label: {
                        Image(systemName: "clock")
                            .font(Styles.Fonts.subheadlineSemibold)
                            .foregroundStyle(AppColors.timelineColor(for: overviewID))
                            .help("Open overview in Timeline")
                    }
                    .buttonStyle(.plain)
                }

                Picker("Tag", selection: tagBinding) {
                    ForEach(tagChoices) { tagChoice in
                        Text(tagChoice.title)
                            .tag(tagChoice.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 172, alignment: .leading)
                .help(tagName ?? "No Tag")

                VStack(alignment: .trailing, spacing: 2) {
                    Text(activity.startTime.formatted(date: .omitted, time: .shortened))
                    if let endTime {
                        Text(endTime.formatted(date: .omitted, time: .shortened))
                            .font(Styles.Fonts.footnote)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                Button {
                    Task {
                        await onDelete()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(Styles.Fonts.footnoteSemibold)
                        .foregroundStyle(AppColors.recordActive.opacity(0.8))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var panelSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(availablePanels, id: \.self) { panel in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        selectedPanel = panel
                    }
                } label: {
                    PanelSelectorRow(
                        title: panel.rawValue,
                        systemImage: panel.systemImage,
                        isSelected: panel == resolvedPanel
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 180, alignment: .topLeading)
    }

    @ViewBuilder
    private var panelContent: some View {
        Group {
            switch resolvedPanel {
            case .summary:
                ScrollView {
                    Text(activity.summary ?? "No summary available.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            case .keystrokes:
                ScrollView {
                    Text(activity.keystrokes)
                        .font(Styles.Fonts.bodyMonospaced)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            case .microphone:
                ScrollView {
                    Text(activity.microphone)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            case .screenshots:
                ScreenshotBrowser(
                    screenshots: activity.screenshots.sorted { $0.timestamp < $1.timestamp },
                    loadScreenshotImage: { screenshotID in
                        await loadScreenshotImage(screenshotID)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.insetBackground)
        )
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        Duration.seconds(duration).formatted(.units(width: .wide, maximumUnitCount: 2))
    }

    private var tagBinding: Binding<Int64?> {
        Binding(
            get: {
                guard let tagID = activity.tagID else {
                    return nil
                }

                guard tagChoices.contains(where: { $0.id == tagID }) else {
                    let tagChoiceIDs = tagChoices.map { $0.id?.description ?? "nil" }.joined(separator: ",")
                    let tagChoiceTitles = tagChoices.map(\.title).joined(separator: "|")
                    activityViewLogger.error(
                        "activity-card invalid tag selection activityID=\(activity.id, privacy: .public) tagID=\(tagID, privacy: .public) tagChoices=\(tagChoiceIDs, privacy: .public) titles=\(tagChoiceTitles, privacy: .public)"
                    )
                    return nil
                }

                return tagID
            },
            set: { newValue in
                let newTagDescription = newValue?.description ?? "nil"
                let currentTagDescription = activity.tagID?.description ?? "nil"
                activityViewLogger.log(
                    "activity-card tag picker set activityID=\(activity.id, privacy: .public) newTagID=\(newTagDescription, privacy: .public) currentTagID=\(currentTagDescription, privacy: .public)"
                )
                Task {
                    await onSelectTag(newValue)
                }
            }
        )
    }

    private var availablePanels: [Panel] {
        [
            activity.summary.flatMap { !$0.isEmpty ? .summary : nil },
            activity.keystrokes.isEmpty ? nil : .keystrokes,
            activity.microphone.isEmpty ? nil : .microphone,
            activity.screenshots.isEmpty ? nil : .screenshots
        ].compactMap { $0 }
    }

    private var resolvedPanel: Panel {
        if availablePanels.contains(selectedPanel) {
            return selectedPanel
        }

        if availablePanels.contains(.summary) {
            return .summary
        }

        return availablePanels.first ?? .summary
    }
}

private struct PanelSelectorRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let textColor: Color = isSelected ? AppColors.textPrimary : AppColors.textSecondary
        let backgroundColor: Color = isSelected
            ? AppColors.recordIdle.opacity(0.24)
            : AppColors.insetBackground
        let strokeColor: Color = isSelected
            ? AppColors.recordActive.opacity(0.22)
            : Color.white.opacity(0.06)

        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 16)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(Styles.Fonts.subheadlineSemibold)
        .foregroundStyle(textColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 180, alignment: .leading)
        .background(shape.fill(backgroundColor))
        .overlay(shape.stroke(strokeColor, lineWidth: 1))
    }
}

private struct ScreenshotRowLabel: View {
    let screenshot: ActivityActor.Screenshot
    let isSelected: Bool

    var body: some View {
        let rowShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let rowBackground: Color = isSelected
            ? AppColors.recordIdle.opacity(0.24)
            : AppColors.cardBackground.opacity(0.65)
        let rowStrokeColor: Color = isSelected
            ? AppColors.recordActive.opacity(0.22)
            : Color.white.opacity(0.06)
        let textColor: Color = isSelected ? AppColors.textPrimary : AppColors.textSecondary

        VStack(alignment: .leading, spacing: 6) {
            Text(screenshot.timestamp.formatted(date: .omitted, time: .shortened))
                .font(Styles.Fonts.subheadlineSemibold)
            HStack(spacing: 8) {
                if screenshot.summary != nil {
                    Image(systemName: "text.badge.checkmark")
                }
                if screenshot.description != nil {
                    Image(systemName: "text.alignleft")
                }
                if screenshot.text != nil {
                    Image(systemName: "doc.text.viewfinder")
                }
                Image(systemName: "photo")
            }
            .font(.caption)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowShape.fill(rowBackground))
        .overlay(rowShape.stroke(rowStrokeColor, lineWidth: 1))
    }
}

private struct ScreenshotBrowser: View {
    let screenshots: [ActivityActor.Screenshot]
    let loadScreenshotImage: @MainActor @Sendable (Int64) async -> Data?
    @State private var selectedScreenshotID: Int64?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(screenshots) { screenshot in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                selectedScreenshotID = screenshot.id
                            }
                        } label: {
                            ScreenshotRowLabel(
                                screenshot: screenshot,
                                isSelected: selectedScreenshot?.id == screenshot.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 140)

            if let selectedScreenshot {
                ScreenshotDetail(
                    screenshot: selectedScreenshot,
                    loadScreenshotImage: { screenshotID in
                        await loadScreenshotImage(screenshotID)
                    }
                )
            } else {
                Text("No screenshot selected.")
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
        .frame(minHeight: 480)
        .onAppear {
            if selectedScreenshotID == nil {
                selectedScreenshotID = screenshots.first?.id
            }
        }
        .onChange(of: screenshots.map(\.id)) { _, _ in
            if selectedScreenshot == nil {
                selectedScreenshotID = screenshots.first?.id
            }
        }
    }

    private var selectedScreenshot: ActivityActor.Screenshot? {
        screenshots.first(where: { $0.id == selectedScreenshotID }) ?? screenshots.first
    }
}

private struct ScreenshotDetail: View {
    private enum Panel: String, CaseIterable, Hashable {
        case summary = "Summary"
        case description = "Description"
        case ocr = "OCR Text"
        case image = "Image"

        var systemImage: String {
            switch self {
            case .summary:
                "text.badge.checkmark"
            case .description:
                "text.alignleft"
            case .ocr:
                "doc.text.viewfinder"
            case .image:
                "photo"
            }
        }
    }

    let screenshot: ActivityActor.Screenshot
    let loadScreenshotImage: @MainActor @Sendable (Int64) async -> Data?
    @State private var selectedPanel: Panel = .summary
    @State private var imageLoadState = ScreenshotDetailImageLoadState()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(availablePanels, id: \.self) { panel in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            selectedPanel = panel
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: panel.systemImage)
                                .frame(width: 16)
                            Text(panel.rawValue)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(Styles.Fonts.subheadlineSemibold)
                        .foregroundStyle(panel == resolvedPanel ? AppColors.textPrimary : AppColors.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(width: 170, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(panel == resolvedPanel ? AppColors.recordIdle.opacity(0.24) : AppColors.cardBackground.opacity(0.65))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(panel == resolvedPanel ? AppColors.recordActive.opacity(0.22) : Color.white.opacity(0.06), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 170, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        screenshot.timestamp.formatted(date: .omitted, time: .shortened),
                        systemImage: resolvedPanel.systemImage
                    )
                    .font(Styles.Fonts.subheadlineSemibold)

                    Spacer()
                }

                Group {
                    switch resolvedPanel {
                    case .summary:
                        ScrollView {
                            Text(screenshot.summary ?? "No summary available.")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.bottom, 4)
                        }
                    case .description:
                        ScrollView {
                            Text(screenshot.description ?? "No description available.")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.bottom, 4)
                        }
                    case .ocr:
                        ScrollView {
                            Text(screenshot.text ?? "No OCR text available.")
                                .font(Styles.Fonts.bodyMonospaced)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.bottom, 4)
                        }
                    case .image:
                        if let imageData = imageLoadState.displayedImageData(for: screenshot.id),
                           let nsImage = NSImage(data: imageData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                        } else if imageLoadState.isLoading(screenshotID: screenshot.id) {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Text("Image not available.")
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: resolvedPanel == .image ? 420 : .infinity)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: resolvedPanel == .image ? screenshot.id : nil) {
            guard resolvedPanel == .image,
                  imageLoadState.needsLoad(screenshotID: screenshot.id) else {
                return
            }

            let screenshotID = screenshot.id
            imageLoadState.startLoading(screenshotID: screenshotID)
            let imageData = await loadScreenshotImage(screenshotID)
            imageLoadState.finishLoading(screenshotID: screenshotID, imageData: imageData)
        }
    }

    private var availablePanels: [Panel] {
        [
            screenshot.summary.flatMap { !$0.isEmpty ? .summary : nil },
            screenshot.description.flatMap { !$0.isEmpty ? .description : nil },
            screenshot.text.flatMap { !$0.isEmpty ? .ocr : nil },
            .image
        ].compactMap { $0 }
    }

    private var resolvedPanel: Panel {
        availablePanels.contains(selectedPanel) ? selectedPanel : (availablePanels.first ?? .description)
    }
}

nonisolated struct ScreenshotDetailImageLoadState: Equatable {
    private(set) var loadedScreenshotID: Int64?
    private(set) var loadedImageData: Data?
    private(set) var loadingScreenshotID: Int64?

    func displayedImageData(for screenshotID: Int64) -> Data? {
        loadedScreenshotID == screenshotID ? loadedImageData : nil
    }

    func isLoading(screenshotID: Int64) -> Bool {
        loadingScreenshotID == screenshotID
    }

    func needsLoad(screenshotID: Int64) -> Bool {
        loadingScreenshotID != screenshotID && loadedScreenshotID != screenshotID
    }

    mutating func startLoading(screenshotID: Int64) {
        guard loadedScreenshotID != screenshotID else {
            loadingScreenshotID = nil
            return
        }

        loadedScreenshotID = nil
        loadedImageData = nil
        loadingScreenshotID = screenshotID
    }

    mutating func finishLoading(screenshotID: Int64, imageData: Data?) {
        guard loadingScreenshotID == screenshotID else {
            return
        }

        loadedScreenshotID = screenshotID
        loadedImageData = imageData
        loadingScreenshotID = nil
    }
}
