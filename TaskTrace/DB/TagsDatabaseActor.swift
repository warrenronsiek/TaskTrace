//
//  TagsDatabaseActor.swift
//  TaskTrace
//
//  Created by Codex on 4/11/26.
//

import Foundation
import GRDB

actor TagsDatabaseActor {
    private let database: TaskTraceDatabase

    init(database: TaskTraceDatabase) {
        self.database = database
    }

    func loadTags() async throws -> [TagRecord] {
        try database.read { db in
            try TagRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM tags
                    WHERE delete_date IS NULL
                    ORDER BY create_date ASC, id ASC
                    """
            )
        }
    }

    func saveTag(_ tag: TagInput) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tags (
                        id,
                        name,
                        create_date,
                        description,
                        delete_date,
                        json_properties,
                        origin_kind,
                        generated_name,
                        generated_description,
                        name_is_user_edited,
                        description_is_user_edited
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = COALESCE(excluded.name, tags.name),
                        description = COALESCE(excluded.description, tags.description),
                        create_date = COALESCE(tags.create_date, excluded.create_date),
                        delete_date = COALESCE(excluded.delete_date, tags.delete_date),
                        json_properties = COALESCE(excluded.json_properties, tags.json_properties),
                        origin_kind = COALESCE(excluded.origin_kind, tags.origin_kind),
                        generated_name = COALESCE(excluded.generated_name, tags.generated_name),
                        generated_description = COALESCE(excluded.generated_description, tags.generated_description),
                        name_is_user_edited = COALESCE(excluded.name_is_user_edited, tags.name_is_user_edited),
                        description_is_user_edited = COALESCE(excluded.description_is_user_edited, tags.description_is_user_edited)
                    """,
                arguments: [
                    tag.id,
                    tag.name,
                    (tag.createDate ?? Date()).formatted(TaskTraceDatabase.sqlDateStyle),
                    tag.description,
                    tag.deleteDate.map { $0.formatted(TaskTraceDatabase.sqlDateStyle) },
                    tag.jsonProperties,
                    tag.originKind,
                    tag.generatedName,
                    tag.generatedDescription,
                    tag.nameIsUserEdited ?? false,
                    tag.descriptionIsUserEdited ?? false
                ]
            )
        }
    }

    func deleteTag(id: Int64) async throws {
        try database.write { db in
            let originKind = try String.fetchOne(
                db,
                sql: """
                    SELECT origin_kind
                    FROM tags
                    WHERE id = ?
                    """,
                arguments: [id]
            )

            guard TagOriginKind(rawValue: originKind ?? "") != .ontology else {
                return
            }

            try db.execute(
                sql: "UPDATE tags SET delete_date = ? WHERE id = ?",
                arguments: [Date().formatted(TaskTraceDatabase.sqlDateStyle), id]
            )
        }
    }
}
