//
//  SettingsDatabaseActor.swift
//  TaskTrace
//
//  Created by Codex on 4/11/26.
//

import Foundation
import GRDB

actor SettingsDatabaseActor {
    private let database: TaskTraceDatabase

    init(database: TaskTraceDatabase) {
        self.database = database
    }

    func getSetting(named name: String) async throws -> String? {
        try database.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM settings WHERE name = ?",
                arguments: [name]
            )
        }
    }

    func getUserID() async throws -> String? {
        try await getSetting(named: "UserID")
    }

    func setSetting(named name: String, value: String) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO settings (name, value)
                    VALUES (?, ?)
                    ON CONFLICT(name) DO UPDATE SET
                        value = excluded.value
                    """,
                arguments: [name, value]
            )
        }
    }
}
