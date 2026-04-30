//
//  TagsStoreTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/13/26.
//

import Foundation
import Testing
@testable import TaskTrace

@MainActor
struct TagsStoreTests {
    @Test("load includes the built in seeded tags")
    func loadIncludesTheBuiltInSeededTags() async throws {
        try await withStore { store, _ in
            await store.load()
            #expect(store.tags.map(\.id) == [SystemTags.inactiveID, SystemTags.taggingFailureID])
        }
    }

    @Test("saveCurrentTag creates a new tag")
    func saveCurrentTagCreatesANewTag() async throws {
        try await withStore { store, _ in
            store.startAdding()
            store.currentName = "Work"
            store.currentDescription = "Programming and AI"
            await store.saveCurrentTag()

            #expect(store.tags.compactMap(\.name) == [SystemTags.inactiveName, SystemTags.taggingFailureName, "Work"])
        }
    }

    @Test("saveCurrentTag rejects duplicate names case insensitively")
    func saveCurrentTagRejectsDuplicateNamesCaseInsensitively() async throws {
        try await withStore { store, database in
            try await database.save(.tag(.record(TagInput(
                id: 101,
                name: "Work",
                description: nil,
                createDate: Date(),
                deleteDate: nil,
                jsonProperties: nil
            ))))
            await store.load()
            store.startAdding()
            store.currentName = "work"
            await store.saveCurrentTag()

            #expect(store.errorMessage == "A tag with this name already exists.")
        }
    }

    @Test("saveCurrentTag updates the edited tag")
    func saveCurrentTagUpdatesTheEditedTag() async throws {
        try await withStore { store, database in
            try await database.save(.tag(.record(TagInput(
                id: 102,
                name: "Work",
                description: "Old",
                createDate: Date(),
                deleteDate: nil,
                jsonProperties: nil
            ))))
            await store.load()
            store.startEditing(tagID: 102)
            store.currentDescription = "New"
            await store.saveCurrentTag()

            #expect(store.tags.first(where: { $0.id == 102 })?.description == "New")
        }
    }

    @Test("deleteTag removes the tag from the active list")
    func deleteTagRemovesTheTagFromTheActiveList() async throws {
        try await withStore { store, database in
            try await database.save(.tag(.record(TagInput(
                id: 103,
                name: "Work",
                description: nil,
                createDate: Date(),
                deleteDate: nil,
                jsonProperties: nil
            ))))
            await store.load()
            await store.deleteTag(id: 103)

            #expect(store.tags.map(\.id) == [SystemTags.inactiveID, SystemTags.taggingFailureID])
        }
    }

    @Test("startEditing ignores the tagging failure tag")
    func startEditingIgnoresTheTaggingFailureTag() async throws {
        try await withStore { store, _ in
            await store.load()
            store.startEditing(tagID: SystemTags.taggingFailureID)
            #expect(store.isEditing == false)
        }
    }

    @Test("deleteTag ignores the tagging failure tag")
    func deleteTagIgnoresTheTaggingFailureTag() async throws {
        try await withStore { store, _ in
            await store.load()
            await store.deleteTag(id: SystemTags.taggingFailureID)
            #expect(store.tags.map(\.id) == [SystemTags.inactiveID, SystemTags.taggingFailureID])
        }
    }

    @Test("canDeleteTag returns false for ontology tags")
    func canDeleteTagReturnsFalseForOntologyTags() async throws {
        try await withStore { store, database in
            try await database.save(.tag(.record(TagInput(
                id: 104,
                name: "Generated Cluster",
                description: "Generated description",
                createDate: Date(),
                deleteDate: nil,
                jsonProperties: nil,
                originKind: TagOriginKind.ontology.rawValue,
                generatedName: "Generated Cluster",
                generatedDescription: "Generated description"
            ))))
            await store.load()

            #expect(store.canDeleteTag(id: 104) == false)
        }
    }

    @Test("deleteTag ignores ontology tags")
    func deleteTagIgnoresOntologyTags() async throws {
        try await withStore { store, database in
            try await database.save(.tag(.record(TagInput(
                id: 105,
                name: "Generated Cluster",
                description: "Generated description",
                createDate: Date(),
                deleteDate: nil,
                jsonProperties: nil,
                originKind: TagOriginKind.ontology.rawValue,
                generatedName: "Generated Cluster",
                generatedDescription: "Generated description"
            ))))
            await store.load()
            await store.deleteTag(id: 105)

            #expect(store.tags.contains(where: { $0.id == 105 }))
        }
    }

    @Test("saveCurrentTag marks an ontology tag name as user edited when renamed")
    func saveCurrentTagMarksAnOntologyTagNameAsUserEditedWhenRenamed() async throws {
        try await withStore { store, database in
            try await database.save(.tag(.record(TagInput(
                id: 106,
                name: "Generated Cluster",
                description: "Generated description",
                createDate: Date(),
                deleteDate: nil,
                jsonProperties: nil,
                originKind: TagOriginKind.ontology.rawValue,
                generatedName: "Generated Cluster",
                generatedDescription: "Generated description"
            ))))
            await store.load()
            store.startEditing(tagID: 106)
            store.currentName = "User Edited Cluster"
            await store.saveCurrentTag()

            #expect(store.tags.first(where: { $0.id == 106 })?.nameIsUserEdited == true)
        }
    }

    @Test("saveCurrentTag marks an ontology tag description as user edited when changed")
    func saveCurrentTagMarksAnOntologyTagDescriptionAsUserEditedWhenChanged() async throws {
        try await withStore { store, database in
            try await database.save(.tag(.record(TagInput(
                id: 107,
                name: "Generated Cluster",
                description: "Generated description",
                createDate: Date(),
                deleteDate: nil,
                jsonProperties: nil,
                originKind: TagOriginKind.ontology.rawValue,
                generatedName: "Generated Cluster",
                generatedDescription: "Generated description"
            ))))
            await store.load()
            store.startEditing(tagID: 107)
            store.currentDescription = "User edited description"
            await store.saveCurrentTag()

            #expect(store.tags.first(where: { $0.id == 107 })?.descriptionIsUserEdited == true)
        }
    }
}

@MainActor
private func withStore(
    _ block: (TagsStore, TaskTraceDatabase) async throws -> Void
) async throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

    try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
    let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
    let store = TagsStore(database: database)

    try await block(store, database)
}
