//
//  TagsStore.swift
//  TaskTrace
//
//  Created by Codex on 3/13/26.
//

import Combine
import Foundation

@MainActor
final class TagsStore: ObservableObject {
    @Published private(set) var tags: [TagRecord]
    @Published private(set) var isAdding: Bool
    @Published private(set) var editingTagID: Int64?
    @Published var currentName: String
    @Published var currentDescription: String
    @Published private(set) var errorMessage: String?

    private let tagsDatabaseActor: TagsDatabaseActor?
    private let now: @Sendable () -> Date
    private let identifierActor: IdentifierActor

    var isEditing: Bool {
        editingTagID != nil
    }

    init(tagsDatabaseActor: TagsDatabaseActor) {
        self.tagsDatabaseActor = tagsDatabaseActor
        self.tags = []
        self.isAdding = false
        self.editingTagID = nil
        self.currentName = ""
        self.currentDescription = ""
        self.errorMessage = nil
        self.now = Date.init
        self.identifierActor = .shared
    }

    convenience init(database: TaskTraceDatabase) {
        self.init(tagsDatabaseActor: TagsDatabaseActor(database: database))
    }

    init(previewTags: [TagRecord]) {
        self.tagsDatabaseActor = nil
        self.tags = previewTags
        self.isAdding = false
        self.editingTagID = nil
        self.currentName = ""
        self.currentDescription = ""
        self.errorMessage = nil
        self.now = Date.init
        self.identifierActor = .shared
    }

    func load() async {
        guard let tagsDatabaseActor else {
            return
        }

        do {
            tags = try await tagsDatabaseActor.loadTags()
            errorMessage = nil
        } catch {
            errorMessage = "Could not load tags."
        }
    }

    func startAdding() {
        isAdding = true
        editingTagID = nil
        currentName = ""
        currentDescription = ""
        errorMessage = nil
    }

    func cancelAdding() {
        isAdding = false
        currentName = ""
        currentDescription = ""
        errorMessage = nil
    }

    func startEditing(tagID: Int64) {
        guard !SystemTags.isProtected(tagID), let tag = tags.first(where: { $0.id == tagID }) else {
            return
        }

        editingTagID = tagID
        isAdding = false
        currentName = tag.name ?? ""
        currentDescription = tag.description ?? ""
        errorMessage = nil
    }

    func cancelEditing() {
        editingTagID = nil
        currentName = ""
        currentDescription = ""
        errorMessage = nil
    }

    func saveCurrentTag() async {
        let trimmedName = currentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = currentDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Tag name cannot be empty."
            return
        }

        let duplicate = tags.contains { tag in
            tag.name?.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
                && tag.id != editingTagID
        }

        guard !duplicate else {
            errorMessage = "A tag with this name already exists."
            return
        }

        let identifier = if let editingTagID {
            editingTagID
        } else {
            await identifierActor.makeIdentifier(minimum: (tags.map(\.id).max() ?? 0) + 1)
        }
        let existingTag = editingTagID.flatMap { editingTagID in
            tags.first { $0.id == editingTagID }
        }
        let resolvedOriginKind = existingTag?.resolvedOriginKind ?? .manual
        let resolvedDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
        let nameIsUserEdited = if resolvedOriginKind == .ontology,
                                  let generatedName = existingTag?.generatedName {
            trimmedName != generatedName
        } else {
            existingTag?.nameIsUserEdited ?? false
        }
        let descriptionIsUserEdited = if resolvedOriginKind == .ontology,
                                         let generatedDescription = existingTag?.generatedDescription {
            resolvedDescription != generatedDescription
        } else {
            existingTag?.descriptionIsUserEdited ?? false
        }

        guard let tagsDatabaseActor else {
            return
        }

        do {
            try await tagsDatabaseActor.saveTag(TagInput(
                id: identifier,
                name: trimmedName,
                description: resolvedDescription,
                createDate: editingTagID == nil ? now() : nil,
                deleteDate: nil,
                jsonProperties: nil,
                originKind: resolvedOriginKind.rawValue,
                generatedName: existingTag?.generatedName,
                generatedDescription: existingTag?.generatedDescription,
                nameIsUserEdited: nameIsUserEdited,
                descriptionIsUserEdited: descriptionIsUserEdited
            ))
            await load()
            isAdding = false
            editingTagID = nil
            currentName = ""
            currentDescription = ""
            errorMessage = nil
        } catch {
            errorMessage = "Could not save tag."
        }
    }

    func deleteTag(id: Int64) async {
        guard canDeleteTag(id: id) else {
            return
        }

        guard let tagsDatabaseActor else {
            return
        }

        do {
            try await tagsDatabaseActor.deleteTag(id: id)
            await load()

            if editingTagID == id {
                editingTagID = nil
                currentName = ""
                currentDescription = ""
            }

            errorMessage = nil
        } catch {
            errorMessage = "Could not delete tag."
        }
    }

    func canDeleteTag(id: Int64) -> Bool {
        guard !SystemTags.isProtected(id) else {
            return false
        }

        return tags.first(where: { $0.id == id })?.resolvedOriginKind != .ontology
    }
}
