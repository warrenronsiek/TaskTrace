//
//  OverviewCard.swift
//  TaskTrace
//
//  Created by Codex on 4/15/26.
//

import OSLog
import SwiftUI

private let overviewCardLogger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "overview-card")

@MainActor
struct OverviewCard: View {
    let overview: OverviewStore.Overview
    let isMergeModeActive: Bool
    let isMergeInFlight: Bool
    let isMergeSource: Bool
    let isMergeCandidate: Bool
    let isMergePending: Bool
    let tags: [TagRecord]
    let duration: Int
    let sourceActivities: [ActivityActor.Activity]
    let onSaveTitle: @MainActor @Sendable (String) async -> Void
    let onSaveSummary: @MainActor @Sendable (String) async -> Void
    let onSaveDuration: @MainActor @Sendable (Int) async -> Void
    let onSelectTag: @MainActor @Sendable (Int64) async -> Void
    let onBeginMerge: () -> Void
    let onCancelMerge: () -> Void
    let onSelectMergeTarget: () -> Void
    let onShowActivity: (Int64) -> Void
    let displayIndex: (Int64) -> Int?
    @State private var isEditingTitle = false
    @State private var isEditingSummary = false
    @State private var titleDraft = ""
    @State private var summaryDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 6) {
                if isEditingTitle {
                    TextField("Untitled Overview", text: $titleDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(Styles.Fonts.headline)
                        .foregroundStyle(AppColors.timelineDetailText)
                        .onSubmit {
                            saveTitle()
                        }
                } else {
                    Text(overview.title ?? "Untitled Overview")
                        .font(Styles.Fonts.headline)
                        .foregroundStyle(AppColors.timelineDetailText)
                }

                Button {
                    if isEditingTitle {
                        saveTitle()
                    } else {
                        titleDraft = overview.title ?? ""
                        isEditingTitle = true
                    }
                } label: {
                    Image(systemName: isEditingTitle ? "checkmark.circle.fill" : "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isEditingTitle ? AppColors.accent : AppColors.timelineDetailSecondaryText)
                        .frame(width: 26, height: 26)
                        .background(AppColors.timelineDetailChrome, in: Circle())
                }
                .buttonStyle(.plain)

                if !isMergeModeActive || isMergeSource {
                    Button {
                        if isMergeSource {
                            onCancelMerge()
                        } else {
                            onBeginMerge()
                        }
                    } label: {
                        Text(isMergeSource ? "Cancel Merge" : "Merge")
                            .font(Styles.Fonts.footnoteMonospacedDigit)
                            .foregroundStyle(AppColors.timelineDetailText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((isMergeSource ? AppColors.accent.opacity(0.18) : AppColors.timelineDetailChrome), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isMergeInFlight)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                if isEditingSummary {
                    HStack(alignment: .top, spacing: 6) {
                        TextField("Overview summary unavailable.", text: $summaryDraft, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .foregroundStyle(AppColors.timelineDetailText)
                            .lineLimit(3...8)

                        Button(action: saveSummary) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppColors.accent)
                                .frame(width: 26, height: 26)
                                .background(AppColors.timelineDetailChrome, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(alignment: .top, spacing: 6) {
                        Text(overview.summary ?? "Overview summary unavailable.")
                            .foregroundStyle(AppColors.timelineDetailSecondaryText)

                        Button {
                            summaryDraft = overview.summary ?? ""
                            isEditingSummary = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppColors.timelineDetailSecondaryText)
                                .frame(width: 26, height: 26)
                                .background(AppColors.timelineDetailChrome, in: Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Duration")
                            .font(Styles.Fonts.subheadlineSemibold)

                        Stepper(value: durationBinding, in: 0...86_400, step: 300) {
                            Text(Duration.seconds(duration).formatted(.units(width: .wide, maximumUnitCount: 2)))
                        }
                    }
                    .frame(width: 220, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Source Activities")
                            .font(Styles.Fonts.subheadlineSemibold)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(stride(from: 0, to: sourceActivities.count, by: 15)), id: \.self) { offset in
                                HStack(spacing: 8) {
                                    ForEach(Array(sourceActivities[offset..<min(offset + 15, sourceActivities.count)])) { activity in
                                        Button {
                                            onShowActivity(activity.id)
                                        } label: {
                                            Text(displayIndex(activity.id).map(String.init) ?? "?")
                                                .font(Styles.Fonts.footnoteMonospacedDigit)
                                                .foregroundStyle(AppColors.timelineDetailText)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(AppColors.timelineDetailChrome, in: Capsule())
                                                .fixedSize(horizontal: true, vertical: false)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tag")
                            .font(Styles.Fonts.subheadlineSemibold)

                        Picker("Tag", selection: tagBinding) {
                            ForEach(tags, id: \.id) { tag in
                                Text(tag.name ?? "Untitled Tag")
                                    .tag(Optional.some(tag.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 220, alignment: .leading)
                    }
                    .frame(width: 220, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Duration")
                            .font(Styles.Fonts.subheadlineSemibold)

                        Stepper(value: durationBinding, in: 0...86_400, step: 300) {
                            Text(Duration.seconds(duration).formatted(.units(width: .wide, maximumUnitCount: 2)))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Source Activities")
                            .font(Styles.Fonts.subheadlineSemibold)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(stride(from: 0, to: sourceActivities.count, by: 15)), id: \.self) { offset in
                                HStack(spacing: 8) {
                                    ForEach(Array(sourceActivities[offset..<min(offset + 15, sourceActivities.count)])) { activity in
                                        Button {
                                            onShowActivity(activity.id)
                                        } label: {
                                            Text(displayIndex(activity.id).map(String.init) ?? "?")
                                                .font(Styles.Fonts.footnoteMonospacedDigit)
                                                .foregroundStyle(AppColors.timelineDetailText)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(AppColors.timelineDetailChrome, in: Capsule())
                                                .fixedSize(horizontal: true, vertical: false)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tag")
                            .font(Styles.Fonts.subheadlineSemibold)

                        Picker("Tag", selection: tagBinding) {
                            ForEach(tags, id: \.id) { tag in
                                Text(tag.name ?? "Untitled Tag")
                                    .tag(Optional.some(tag.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .foregroundStyle(AppColors.timelineDetailText)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isMergePending ? 0.55 : 1)
        .overlay {
            Rectangle()
                .strokeBorder(
                    isMergeSource
                        ? AppColors.accent
                        : (isMergeCandidate ? AppColors.accent.opacity(0.7) : .clear),
                    lineWidth: isMergeSource || isMergeCandidate ? 2 : 0
                )
        }
        .overlay {
            if isMergePending {
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.08))

                    ProgressView()
                        .controlSize(.large)
                        .tint(AppColors.accent)
                }
            } else if isMergeCandidate {
                Button(action: onSelectMergeTarget) {
                    Rectangle()
                        .fill(AppColors.accent.opacity(0.08))
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            titleDraft = overview.title ?? ""
            summaryDraft = overview.summary ?? ""
        }
        .onChange(of: overview.title) { _, newValue in
            guard !isEditingTitle else {
                return
            }

            titleDraft = newValue ?? ""
        }
        .onChange(of: overview.summary) { _, newValue in
            guard !isEditingSummary else {
                return
            }

            summaryDraft = newValue ?? ""
        }
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: { max(duration, 0) },
            set: { newValue in
                Task { @MainActor in
                    await onSaveDuration(max(newValue, 0))
                }
            }
        )
    }

    private var tagBinding: Binding<Int64?> {
        Binding(
            get: {
                guard let tagID = overview.tagID else {
                    return nil
                }

                guard tags.contains(where: { $0.id == tagID }) else {
                    overviewCardLogger.error(
                        "overview-card invalid tag selection overviewID=\(overview.id, privacy: .public) tagID=\(overview.tagID?.description ?? "nil", privacy: .public) availableTags=\(tags.map(\.id.description).joined(separator: ","), privacy: .public) tagNames=\(tags.map { $0.name ?? "<nil>" }.joined(separator: "|"), privacy: .public) returning=nil"
                    )
                    return nil
                }

                return tagID
            },
            set: { newValue in
                overviewCardLogger.log(
                    "overview-card tag picker set overviewID=\(overview.id, privacy: .public) newTagID=\(newValue?.description ?? "nil", privacy: .public) currentTagID=\(overview.tagID?.description ?? "nil", privacy: .public)"
                )

                guard let newValue else {
                    return
                }

                Task { @MainActor in
                    await onSelectTag(newValue)
                }
            }
        )
    }

    private func saveTitle() {
        let nextTitle = titleDraft
        isEditingTitle = false
        Task { @MainActor in
            await onSaveTitle(nextTitle)
        }
    }

    private func saveSummary() {
        let nextSummary = summaryDraft
        isEditingSummary = false
        Task { @MainActor in
            await onSaveSummary(nextSummary)
        }
    }
}
