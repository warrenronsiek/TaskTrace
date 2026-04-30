//
//  TagsView.swift
//  TaskTrace
//
//  Created by Codex on 3/13/26.
//

import SwiftUI

struct TagsView: View {
    @ObservedObject var tagsStore: TagsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if tagsStore.isAdding {
                    formCard
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                } else {
                    addButton
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                }
                tagsListCard
            }
            .padding(24)
            .frame(maxWidth: 1080)
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.34, dampingFraction: 0.84), value: tagsStore.isAdding)
            .animation(.spring(response: 0.34, dampingFraction: 0.84), value: tagsStore.editingTagID)
        }
        .navigationTitle("Tags")
        .task {
            await tagsStore.load()
        }
    }

    private var addButton: some View {
        Button {
            tagsStore.startAdding()
        } label: {
            Label("Add New Tag", systemImage: "plus")
                .font(Styles.Fonts.headline)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppColors.accent)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Tag")
                .font(Styles.Fonts.title3Semibold)

            VStack(spacing: 10) {
                TextField("Tag name", text: $tagsStore.currentName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    TextField(
                        "Describe when this tag applies.",
                        text: $tagsStore.currentDescription,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .lineLimit(4...8)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text("User-created tags are assigned by hand. AI-generated tags come from the daily community job and can also be edited here.")
                        .font(Styles.Fonts.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            if let errorMessage = tagsStore.errorMessage {
                Text(errorMessage)
                    .font(Styles.Fonts.footnote)
                    .foregroundStyle(AppColors.danger)
            }

            HStack(spacing: 10) {
                Button("Add Tag") {
                    Task { await tagsStore.saveCurrentTag() }
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Button("Cancel") {
                    tagsStore.cancelAdding()
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .backgroundExtensionEffect()
    }

    private var tagsListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tags")
                .font(Styles.Fonts.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            if tagsStore.tags.isEmpty {
                Text("No tags available.")
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ForEach(tagsStore.tags, id: \.id) { tag in
                    tagRow(tag)
                    if tag.id != tagsStore.tags.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .padding(.bottom, 8)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .backgroundExtensionEffect()
    }

    private func tagRow(_ tag: TagRecord) -> some View {
        let isEditingRow = tagsStore.editingTagID == tag.id
        let originLabel = tag.resolvedOriginKind == .ontology ? "AI Generated" : "User Created"

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tag.name ?? "Untitled Tag")
                        .font(Styles.Fonts.headline)

                    if let description = tag.description, !description.isEmpty {
                        Text(description)
                            .font(Styles.Fonts.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Text(originLabel)
                        .font(Styles.Fonts.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppColors.insetBackground)
                        )

                    Button {
                        if isEditingRow {
                            tagsStore.cancelEditing()
                        } else {
                            tagsStore.startEditing(tagID: tag.id)
                        }
                    } label: {
                        Image(systemName: isEditingRow ? "xmark" : "pencil")
                            .frame(width: 16, height: 16)
                    }
                    .controlSize(.regular)
                    .buttonStyle(.bordered)
                    .disabled(SystemTags.isProtected(tag.id))

                    Button(role: .destructive) {
                        Task { await tagsStore.deleteTag(id: tag.id) }
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 16, height: 16)
                    }
                    .controlSize(.regular)
                    .buttonStyle(.bordered)
                    .tint(AppColors.danger)
                    .disabled(!tagsStore.canDeleteTag(id: tag.id))
                }
            }

            if isEditingRow {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Tag name", text: $tagsStore.currentName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    TextField(
                        "Describe when this tag applies.",
                        text: $tagsStore.currentDescription,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .lineLimit(3...6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if let errorMessage = tagsStore.errorMessage {
                        Text(errorMessage)
                            .font(Styles.Fonts.footnote)
                            .foregroundStyle(AppColors.danger)
                    }

                    HStack(spacing: 10) {
                        Button("Save Tag") {
                            Task { await tagsStore.saveCurrentTag() }
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)

                        Button("Cancel") {
                            tagsStore.cancelEditing()
                        }
                        .controlSize(.large)
                        .buttonStyle(.bordered)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
