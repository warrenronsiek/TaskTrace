//
//  SkillsView.swift
//  TaskTrace
//
//  Created by Codex on 4/21/26.
//

import SwiftUI

struct SkillsView: View {
    @ObservedObject var skillsStore: SkillsStore
    let onShowTimelineForActivity: (Int64, Date) -> Void
    @State private var expandedActivityIDs: Set<Int64> = []

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    queryCard
                    statusCard
                    editorCard
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                matchedActivitiesSidebar
                    .frame(width: 340)
                    .frame(maxHeight: .infinity)
            }
            .padding(24)
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var queryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skills")
                .font(Styles.Fonts.title3Semibold)

            Text("TaskTrace looks at what you did today and will create a step-by-step procedural explanation of how to accomplish it. Quality of the result is greatly improved if you narrate what you do when you do it.")
                .font(Styles.Fonts.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                TextField("What do you want a skill about?", text: $skillsStore.query)
                    .textFieldStyle(.plain)
                    .font(Styles.Fonts.subheadline)
                    .onSubmit {
                        skillsStore.generate()
                    }
                    .disabled(skillsStore.isGenerating)

                Button {
                    skillsStore.generate()
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(Styles.Fonts.subheadlineSemibold)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(AppColors.chipBackground, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(skillsStore.isGenerating)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(20)
        .background(cardBackground)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if skillsStore.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(skillsStore.phase.title)
                    .font(Styles.Fonts.subheadlineSemibold)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer(minLength: 0)

                if let obsidianFilePath = skillsStore.obsidianFilePath {
                    Text(obsidianFilePath)
                        .font(Styles.Fonts.footnoteMonospaced)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            if let errorMessage = skillsStore.errorMessage {
                Text(errorMessage)
                    .font(Styles.Fonts.footnote)
                    .foregroundStyle(AppColors.danger)
            } else if !skillsStore.thinkingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(skillsStore.thinkingText)
                    .font(Styles.Fonts.footnoteMonospaced)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 0)

                Text(skillsStore.isGenerating ? "Locked while TaskTrace writes" : "Editable")
                    .font(Styles.Fonts.footnoteSemibold)
                    .foregroundStyle(AppColors.textSecondary)
            }

            TextEditor(text: Binding(
                get: { skillsStore.markdown },
                set: { skillsStore.userEditedMarkdown($0) }
            ))
            .font(Styles.Fonts.bodyMonospaced)
            .scrollContentBackground(.hidden)
            .foregroundStyle(AppColors.textPrimary)
            .disabled(skillsStore.isGenerating)
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
            .padding(12)
            .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if skillsStore.markdown.isEmpty && !skillsStore.isGenerating {
                    Text("Generated Markdown will stream here.")
                        .font(Styles.Fonts.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(20)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private var matchedActivitiesSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected Activity")
                .font(Styles.Fonts.headline)

            if skillsStore.matchedActivities.isEmpty {
                Text("Matched activities from today will appear here.")
                    .font(Styles.Fonts.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(skillsStore.matchedActivities) { activity in
                            activityPane(activity)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private func activityPane(_ activity: SkillContextActivity) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedActivityIDs.contains(activity.id) },
                set: { isExpanded in
                    if isExpanded {
                        expandedActivityIDs.insert(activity.id)
                    } else {
                        expandedActivityIDs.remove(activity.id)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    onShowTimelineForActivity(activity.id, activity.startTime)
                } label: {
                    Label("Open in Timeline", systemImage: "clock")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                sidebarSection(title: "Summary", value: activity.summary ?? "")
                sidebarSection(title: "Microphone", value: activity.microphone)
                sidebarSection(title: "Keystrokes", value: activity.keystrokes)

                if !activity.screenshots.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Screenshots")
                            .font(Styles.Fonts.footnoteSemibold)
                            .foregroundStyle(AppColors.textSecondary)

                        ForEach(Array(activity.screenshots.enumerated()), id: \.offset) { _, screenshot in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(screenshot.timestamp?.formatted(date: .omitted, time: .shortened) ?? "Screenshot")
                                    .font(Styles.Fonts.footnoteSemibold)
                                sidebarSection(title: "Summary", value: screenshot.summary ?? "")
                                sidebarSection(title: "Description", value: screenshot.description ?? "")
                            }
                            .padding(10)
                            .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.application.split(separator: ".").last.map(String.init) ?? activity.application)
                    .font(Styles.Fonts.footnoteSemibold)
                    .foregroundStyle(AppColors.textPrimary)

                Text(activity.startTime.formatted(date: .omitted, time: .shortened))
                    .font(Styles.Fonts.footnoteMonospacedDigit)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(12)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sidebarSection(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Styles.Fonts.footnoteSemibold)
                .foregroundStyle(AppColors.textSecondary)

            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "None" : value)
                .font(Styles.Fonts.footnote)
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
            }
    }
}
