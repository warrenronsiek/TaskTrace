//
//  DatabaseBootstrap.swift
//  TaskTrace
//
//  Created by Codex on 3/27/26.
//

import CryptoKit
import Foundation
import GRDB
import SQLite3

enum TaskTraceDatabaseBootstrap {
    // We intentionally expose multiple connection profiles because the process
    // now has two distinct SQLite extension stacks:
    //
    // 1. The general pooled connections use our project-owned SQLite runtime
    //    plus sqlite-vector. That keeps ordinary GRDB reads/writes fast and
    //    pooled while preserving the existing canonical embedding column
    //    representation.
    // 2. The vector-aware connection uses the same SQLite runtime, also loads
    //    sqlite-vector, and then loads vectorlite. vectorlite owns connection-
    //    local HNSW state, so all ANN work must stay on one long-lived SQLite
    //    connection.
    // 3. The migrator uses our owned SQLite runtime plus sqlite-vector and
    //    vectorlite's scalar helpers. Migrations no longer create a persisted
    //    vectorlite ANN table, but repair paths still rely on
    //    `vector_distance(...)`.
    enum ExtensionSet {
        case pooledRead
        case vectorAware
        case migrator
    }

    nonisolated static let activityEmbeddingDimension = 1024
    nonisolated static let activitySummaryVectorIndexMinimumMaxElements = 4_096
    nonisolated static let activitySummaryVectorIndexTableName = "activity_summary_vector_index"
    nonisolated static let activitySummaryVectorIndexDirtyIDsTableName = "activity_summary_vector_index_dirty_ids"
    nonisolated static let activitySummaryVectorIndexSchemaVersion = 34
    nonisolated static let currentVersion = 45

    nonisolated static func resolvedDatabaseURL(
        _ databaseURL: URL?,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let databaseURL else {
            let applicationSupportURL = try fileManager
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("TaskTrace", isDirectory: true)
            let defaultDatabaseURL = applicationSupportURL.appendingPathComponent("TaskTrace.sqlite")

            if !fileManager.fileExists(atPath: defaultDatabaseURL.path) {
                let documentsDatabaseURL = try fileManager
                    .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("TaskTrace.sqlite")

                if fileManager.fileExists(atPath: documentsDatabaseURL.path) {
                    try fileManager.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
                    try fileManager.moveItem(at: documentsDatabaseURL, to: defaultDatabaseURL)
                }
            }

            return defaultDatabaseURL
        }

        return databaseURL
    }

    nonisolated static func makeConfiguration(
        label: String,
        extensionSet: ExtensionSet
    ) -> Configuration {
        var configuration = Configuration()
        configuration.label = label
        configuration.journalMode = .wal
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { db in
            // Every GRDB connection in this process must be initialized from the
            // same owned SQLite core before any schema access happens. That is
            // what keeps FTS5 availability stable across pooled connections,
            // migration connections, and the vector-aware queue.
            switch extensionSet {
            case .pooledRead:
                // The pooled path still loads sqlite-vector because canonical
                // embedding blobs and helper functions like `vector_as_f32(...)`
                // are part of the existing schema contract. sqlite-vector is
                // safe to register on every connection because it operates over
                // persisted tables in the database file.
                try TaskTraceSQLiteVector.initialize(on: db)
            case .vectorAware:
                // Vector-aware work stays on one connection because vectorlite owns
                // connection-local in-memory HNSW state. This connection still
                // loads sqlite-vector first so the canonical embedding columns
                // keep their existing SQL representation, then layers vectorlite
                // on top for ANN/HNSW virtual tables.
                try TaskTraceSQLiteVector.initialize(on: db)
                try TaskTraceVectorlite.initialize(on: db)
            case .migrator:
                // Migrations operate only on canonical tables now. We still
                // load vectorlite here because repair paths use its scalar
                // `vector_distance(...)` helper, but the migrator no longer
                // creates or owns a persisted ANN table.
                try TaskTraceSQLiteVector.initialize(on: db)
                try TaskTraceVectorlite.initialize(on: db)
            }

            try db.execute(sql: "PRAGMA foreign_keys = ON")
            // The schema depends on FTS5. Validate it on every connection so
            // pooled reads, writes, migrations, and vector-aware work all fail
            // immediately if a second SQLite runtime or bad load order strips
            // required modules from the process.
            try db.execute(sql: "CREATE VIRTUAL TABLE temp.__tasktrace_fts5_smoke USING fts5(value)")
            try db.execute(sql: "DROP TABLE temp.__tasktrace_fts5_smoke")
        }
        return configuration
    }

    private enum FullTextTokenizer {
        case unicode61
        case porterUnicode61
        case porterAscii

        nonisolated func configure(_ definition: FTS5TableDefinition) {
            switch self {
            case .unicode61:
                definition.tokenizer = .unicode61()
            case .porterUnicode61:
                definition.tokenizer = .porter(wrapping: .unicode61())
            case .porterAscii:
                definition.tokenizer = .porter(wrapping: .ascii())
            }
        }
    }

    private nonisolated static func createSynchronizedFullTextTable(
        on db: Database,
        tableName: String,
        contentTable: String,
        columns: [String],
        tokenizer: FullTextTokenizer
    ) throws {
        try db.create(virtualTable: tableName, using: FTS5()) { t in
            t.synchronize(withTable: contentTable)
            for column in columns {
                t.column(column)
            }
            tokenizer.configure(t)
        }
    }

    nonisolated static func activitySummaryVectorIndexSidecarURL(
        for databaseURL: URL
    ) -> URL {
        databaseURL.deletingPathExtension()
            .appendingPathExtension("activity_summary_vector_index.hnsw")
    }

    nonisolated static func activitySummaryVectorIndexMaxElements(
        forVectorCount vectorCount: Int
    ) -> Int {
        max(activitySummaryVectorIndexMinimumMaxElements, max(vectorCount, 1) * 2)
    }

    nonisolated static func prepareActivitySummaryVectorIndex(
        on db: Database,
        databaseURL: URL
    ) throws {
        let canonicalVectorCount = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM activities
                WHERE summary_vector IS NOT NULL
                """
        ) ?? 0
        let sidecarURL = activitySummaryVectorIndexSidecarURL(for: databaseURL)
        let sidecarExists = FileManager.default.fileExists(atPath: sidecarURL.path)
        let escapedSidecarPath = sidecarURL.path.replacingOccurrences(of: "'", with: "''")
        let maxElements = activitySummaryVectorIndexMaxElements(forVectorCount: canonicalVectorCount)
        let tempTableExists = try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1
                    FROM sqlite_temp_master
                    WHERE type = 'table'
                      AND name = ?
                )
                """,
            arguments: [activitySummaryVectorIndexTableName]
        ) ?? false

        if !tempTableExists {
            try db.execute(
                sql: """
                    CREATE VIRTUAL TABLE temp.\(activitySummaryVectorIndexTableName)
                    USING vectorlite(
                        embedding float32[\(activityEmbeddingDimension)] cosine,
                        hnsw(max_elements=\(maxElements)),
                        '\(escapedSidecarPath)'
                    )
                    """
            )
        }

        let dirtyActivityIDs = try Int64.fetchAll(
            db,
            sql: """
                SELECT activity_id
                FROM \(activitySummaryVectorIndexDirtyIDsTableName)
                ORDER BY activity_id ASC
                """
        )
        let needsFullPopulate = !tempTableExists && !sidecarExists && canonicalVectorCount > 0

        if needsFullPopulate {
            try bulkPopulateActivitySummaryVectorIndex(on: db)
        }

        if !dirtyActivityIDs.isEmpty {
            try dirtyActivityIDs.forEach {
                try syncActivitySummaryVectorIndexEntry(on: db, activityID: $0)
            }
        }

        if needsFullPopulate || !dirtyActivityIDs.isEmpty {
            try flushActivitySummaryVectorIndex(on: db)
            try clearDirtyActivitySummaryVectorIndexEntries(on: db)
        }
    }

    nonisolated static func bulkPopulateActivitySummaryVectorIndex(
        on db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT OR REPLACE INTO \(activitySummaryVectorIndexTableName) (
                    rowid,
                    embedding
                )
                SELECT
                    id,
                    vector_from_json(vector_to_json(summary_vector))
                FROM activities
                WHERE summary_vector IS NOT NULL
                """
        )
    }

    nonisolated static func markActivitySummaryVectorIndexDirty(
        on db: Database,
        activityID: Int64
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO \(activitySummaryVectorIndexDirtyIDsTableName) (activity_id)
                VALUES (?)
                ON CONFLICT(activity_id) DO NOTHING
                """,
            arguments: [activityID]
        )
    }

    nonisolated static func syncActivitySummaryVectorIndexEntry(
        on db: Database,
        activityID: Int64
    ) throws {
        try db.execute(
            sql: "DELETE FROM \(activitySummaryVectorIndexTableName) WHERE rowid = ?",
            arguments: [activityID]
        )
        try db.execute(
            sql: """
                INSERT INTO \(activitySummaryVectorIndexTableName) (
                    rowid,
                    embedding
                )
                SELECT
                    id,
                    vector_from_json(vector_to_json(summary_vector))
                FROM activities
                WHERE id = ?
                  AND summary_vector IS NOT NULL
                """,
            arguments: [activityID]
        )
    }

    nonisolated static func flushActivitySummaryVectorIndexIfNeeded(
        on db: Database
    ) throws {
        let dirtyCount = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM \(activitySummaryVectorIndexDirtyIDsTableName)
                """
        ) ?? 0

        guard dirtyCount > 0 else {
            return
        }

        try flushActivitySummaryVectorIndex(on: db)
        try clearDirtyActivitySummaryVectorIndexEntries(on: db)
    }

    nonisolated static func flushActivitySummaryVectorIndex(
        on db: Database
    ) throws {
        try db.execute(
            sql: "SELECT vectorlite_save(?)",
            arguments: [activitySummaryVectorIndexTableName]
        )
    }

    nonisolated static func clearDirtyActivitySummaryVectorIndexEntries(
        on db: Database
    ) throws {
        try db.execute(sql: "DELETE FROM \(activitySummaryVectorIndexDirtyIDsTableName)")
    }

    nonisolated static func rebuildActivityTagOntologyEdges(
        on db: Database
    ) throws {
        try db.execute(sql: "DELETE FROM activity_edges")

        let activityIDs = try Int64.fetchAll(
            db,
            sql: """
                SELECT id
                FROM activities
                WHERE summary_vector IS NOT NULL
                ORDER BY id ASC
                """
        )

        try activityIDs.forEach { activityID in
            let neighborhoodIDs = try Int64.fetchAll(
                db,
                sql: """
                    SELECT id
                    FROM activities
                    WHERE id != ?
                      AND summary_vector IS NOT NULL
                    ORDER BY vector_distance(
                        summary_vector,
                        (
                            SELECT summary_vector
                            FROM activities
                            WHERE id = ?
                              AND summary_vector IS NOT NULL
                        ),
                        'cosine'
                    ) ASC,
                    id ASC
                    LIMIT ?
                    """,
                arguments: [
                    activityID,
                    activityID,
                    ActivityTagOntologyDefaults.neighborCount
                ]
            )

            try upsertActivityOntologyEdges(
                on: db,
                activityIDs: [activityID] + Array(neighborhoodIDs.prefix(ActivityTagOntologyDefaults.neighborCount))
            )
        }
    }

    nonisolated static func upsertActivityOntologyEdges(
        on db: Database,
        activityIDs: [Int64]
    ) throws {
        let uniqueActivityIDs = Array(Set(activityIDs)).sorted()

        guard uniqueActivityIDs.count > 1 else {
            return
        }

        let valuesSQL = uniqueActivityIDs
            .map { _ in "(?)" }
            .joined(separator: ", ")

        try db.execute(
            sql: """
                WITH group_activity_ids(id) AS (
                    VALUES \(valuesSQL)
                ),
                group_pairs AS (
                    SELECT
                        MIN(first_activity.id, second_activity.id) AS first_activity_id,
                        MAX(first_activity.id, second_activity.id) AS second_activity_id,
                        MAX(
                            0.0,
                            1.0 - vector_distance(
                                first_activity.summary_vector,
                                second_activity.summary_vector,
                                'cosine'
                            )
                        ) AS weight
                    FROM group_activity_ids first_id
                    JOIN group_activity_ids second_id
                      ON first_id.id < second_id.id
                    JOIN activities first_activity
                      ON first_activity.id = first_id.id
                    JOIN activities second_activity
                      ON second_activity.id = second_id.id
                    WHERE first_activity.summary_vector IS NOT NULL
                      AND second_activity.summary_vector IS NOT NULL
                )
                INSERT INTO activity_edges (
                    first_activity_id,
                    second_activity_id,
                    weight
                )
                SELECT
                    first_activity_id,
                    second_activity_id,
                    weight
                FROM group_pairs
                WHERE 1
                ON CONFLICT(first_activity_id, second_activity_id) DO UPDATE SET
                    weight = MAX(activity_edges.weight, excluded.weight)
                """,
            arguments: StatementArguments(uniqueActivityIDs)
        )
    }

    @discardableResult
    nonisolated static func migrate(
        databaseURL: URL?,
        fileManager: FileManager = .default
    ) throws -> URL {
        let resolvedURL = try resolvedDatabaseURL(databaseURL, fileManager: fileManager)

        try fileManager.createDirectory(
            at: resolvedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let dbQueue = try DatabaseQueue(
            path: resolvedURL.path,
            configuration: makeConfiguration(
                label: "TaskTraceDatabaseMigrator",
                extensionSet: .migrator
            )
        )

        // Migrations run through a dedicated queue so schema changes happen on
        // one deterministic connection before the app opens its long-lived pool
        // and vector-aware queue against the same file.
        try makeMigrator().migrate(dbQueue)

        return resolvedURL
    }

    private nonisolated static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "tags", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("name", .text)
                t.column("create_date", .date)
                t.column("description", .text)
                t.column("delete_date", .date)
                t.column("json_properties", .text)
            }

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_tag_date ON tags (create_date)")

            try db.create(table: "overviews", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("title", .text)
                t.column("summary", .text)
                t.column("json_properties", .text)
                t.column("edited_duration", .integer)
                t.column("tag_id", .integer).references("tags", onDelete: .setNull)
                t.column("knowledge_processed", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "activities", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("start_time", .datetime).notNull()
                t.column("application", .text).notNull()
                t.column("keystrokes", .text)
                t.column("microphone", .text)
                t.column("summary", .text)
                t.column("tag_id", .integer).references("tags", onDelete: .setNull)
                t.column("json_properties", .text)
                t.column("overview_id", .integer).references("overviews", onDelete: .setNull)
            }

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_activities_start_time ON activities (start_time)")

            try db.create(table: "screenshots", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("image", .blob)
                t.column("ts", .datetime)
                t.column("description", .text)
                t.column("ocr_text", .text)
                t.column("summary", .text)
                t.column("ignore_reason", .text)
                t.column("json_properties", .text)
                t.column("activity_id", .integer).notNull().references("activities", onDelete: .cascade)
            }

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_screenshots_ts ON screenshots (ts)")

            try db.create(table: "versions", ifNotExists: true) { t in
                t.column("version", .integer).notNull()
            }

            try db.create(table: "settings", ifNotExists: true) { t in
                t.column("name", .text).primaryKey()
                t.column("value", .text)
            }

            try db.execute(
                sql: """
                    INSERT INTO tags (id, name, create_date, description, delete_date, json_properties)
                    VALUES (?, ?, ?, ?, NULL, NULL)
                    ON CONFLICT(id) DO NOTHING
                    """,
                arguments: [
                    SystemTags.inactiveID,
                    SystemTags.inactiveName,
                    Self.sqlDateString(Date()),
                    SystemTags.inactiveDescription
                ]
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (1)")
        }

        migrator.registerMigration("v2_unify_activity_summary_column") { db in
            let activityColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(activities)")
                .compactMap { row in
                    row["name"] as String?
                }

            guard !activityColumns.isEmpty else {
                try db.execute(sql: "DELETE FROM versions")
                try db.execute(sql: "INSERT INTO versions (version) VALUES (2)")
                return
            }

            if !activityColumns.contains("summary") {
                try db.execute(sql: "ALTER TABLE activities ADD COLUMN summary TEXT")
            }

            if activityColumns.contains("activity_summary") || activityColumns.contains("screen_summary") {
                try db.execute(
                    sql: """
                        UPDATE activities
                        SET summary = COALESCE(summary, activity_summary, screen_summary)
                        """
                )
            }

            if activityColumns.contains("screen_summary") {
                try db.execute(sql: "ALTER TABLE activities DROP COLUMN screen_summary")
            }

            if activityColumns.contains("activity_summary") {
                try db.execute(sql: "ALTER TABLE activities DROP COLUMN activity_summary")
            }

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (2)")
        }

        migrator.registerMigration("v3_add_activity_microphone_column") { db in
            let activityColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(activities)")
                .compactMap { row in
                    row["name"] as String?
                }

            if !activityColumns.contains("microphone") {
                try db.execute(sql: "ALTER TABLE activities ADD COLUMN microphone TEXT")
            }

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (3)")
        }

        migrator.registerMigration("v4_seed_tagging_failure_tag") { db in
            try db.execute(
                sql: """
                    INSERT INTO tags (id, name, create_date, description, delete_date, json_properties)
                    VALUES (?, ?, ?, ?, NULL, NULL)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        description = excluded.description,
                        delete_date = NULL
                    """,
                arguments: [
                    SystemTags.taggingFailureID,
                    SystemTags.taggingFailureName,
                    Self.sqlDateString(Date()),
                    SystemTags.taggingFailureDescription
                ]
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (4)")
        }

        migrator.registerMigration("v5_add_activity_fts") { db in
            try createSynchronizedFullTextTable(
                on: db,
                tableName: "activity_fts",
                contentTable: "activities",
                columns: ["application", "keystrokes", "microphone", "summary"],
                tokenizer: .porterUnicode61
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (5)")
        }

        migrator.registerMigration("v6_add_activity_summary_vector") { db in
            let activityColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(activities)")
                .compactMap { row in
                    row["name"] as String?
                }

            if !activityColumns.contains("summary_vector") {
                try db.execute(sql: "ALTER TABLE activities ADD COLUMN summary_vector BLOB")
            }

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (6)")
        }

        migrator.registerMigration("v7_rebuild_fts_with_native_grdb_tables") { db in
            try db.dropFTS5SynchronizationTriggers(forTable: "activity_fts")
            try db.dropFTS5SynchronizationTriggers(forTable: "screenshot_fts")
            try db.dropFTS5SynchronizationTriggers(forTable: "overview_fts")
            try db.execute(
                sql: """
                    DROP TRIGGER IF EXISTS activities_ai;
                    DROP TRIGGER IF EXISTS activities_ad;
                    DROP TRIGGER IF EXISTS activities_au;
                    """
            )

            if try db.tableExists("activity_fts") {
                try db.drop(table: "activity_fts")
            }

            if try db.tableExists("screenshot_fts") {
                try db.drop(table: "screenshot_fts")
            }

            if try db.tableExists("overview_fts") {
                try db.drop(table: "overview_fts")
            }

            try createSynchronizedFullTextTable(
                on: db,
                tableName: "activity_fts",
                contentTable: "activities",
                columns: ["application", "keystrokes", "microphone", "summary"],
                tokenizer: .porterUnicode61
            )

            try createSynchronizedFullTextTable(
                on: db,
                tableName: "screenshot_fts",
                contentTable: "screenshots",
                columns: ["description", "ocr_text"],
                tokenizer: .porterUnicode61
            )

            try createSynchronizedFullTextTable(
                on: db,
                tableName: "overview_fts",
                contentTable: "overviews",
                columns: ["summary"],
                tokenizer: .porterUnicode61
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (7)")
        }

        migrator.registerMigration("v8_add_screenshot_and_overview_vectors") { db in
            let screenshotColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(screenshots)")
                .compactMap { row in
                    row["name"] as String?
                }
            let overviewColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(overviews)")
                .compactMap { row in
                    row["name"] as String?
                }

            if !screenshotColumns.contains("description_vector") {
                try db.execute(sql: "ALTER TABLE screenshots ADD COLUMN description_vector BLOB")
            }

            if !overviewColumns.contains("summary_vector") {
                try db.execute(sql: "ALTER TABLE overviews ADD COLUMN summary_vector BLOB")
            }

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (8)")
        }

        migrator.registerMigration("v9_rebuild_fts_with_ascii_porter") { db in
            try db.dropFTS5SynchronizationTriggers(forTable: "activity_fts")
            try db.dropFTS5SynchronizationTriggers(forTable: "screenshot_fts")
            try db.dropFTS5SynchronizationTriggers(forTable: "overview_fts")

            if try db.tableExists("activity_fts") {
                try db.drop(table: "activity_fts")
            }

            if try db.tableExists("screenshot_fts") {
                try db.drop(table: "screenshot_fts")
            }

            if try db.tableExists("overview_fts") {
                try db.drop(table: "overview_fts")
            }

            try createSynchronizedFullTextTable(
                on: db,
                tableName: "activity_fts",
                contentTable: "activities",
                columns: ["application", "keystrokes", "microphone", "summary"],
                tokenizer: .porterAscii
            )

            try createSynchronizedFullTextTable(
                on: db,
                tableName: "screenshot_fts",
                contentTable: "screenshots",
                columns: ["description", "ocr_text"],
                tokenizer: .porterAscii
            )

            try createSynchronizedFullTextTable(
                on: db,
                tableName: "overview_fts",
                contentTable: "overviews",
                columns: ["summary"],
                tokenizer: .porterAscii
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (9)")
        }

        migrator.registerMigration("v10_add_agent_actions") { db in
            try db.create(table: "agent_actions", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("instructions", .text).notNull()
                t.column("event_type", .text).notNull()
                t.column("event_payload", .text)
                t.column("conversation_id", .text).notNull()
            }

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (10)")
        }

        migrator.registerMigration("v11_add_knowledge_directories") { db in
            try db.create(table: "knowledge_directories", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("slot", .text).notNull()
                t.column("path", .text).notNull()
                t.column("bookmark_data", .blob)
                t.column("created_at", .datetime).notNull()
            }

            try db.create(index: "idx_knowledge_directories_slot", on: "knowledge_directories", columns: ["slot"], unique: true)

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (11)")
        }

        migrator.registerMigration("v12_add_knowledge_files") { db in
            try db.create(table: "knowledge_files", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("directory_id", .integer).notNull().references("knowledge_directories", onDelete: .cascade)
                t.column("relative_path", .text).notNull()
                t.column("create_date", .datetime).notNull()
                t.column("last_accessed", .datetime)
                t.column("checksum", .text).notNull()
                t.column("byte_count", .integer).notNull()
            }

            try db.create(index: "idx_knowledge_files_directory_relative_path", on: "knowledge_files", columns: ["directory_id", "relative_path"], unique: true)

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (12)")
        }

        migrator.registerMigration("v13_add_knowledge_nodes") { db in
            try db.create(table: "knowledge_nodes", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("name", .text).notNull()
                t.column("normalized_name", .text).notNull()
                t.column("kind", .text)
                t.column("description", .text)
                t.column("create_date", .datetime).notNull()
            }

            try db.create(
                index: "idx_knowledge_nodes_normalized_name",
                on: "knowledge_nodes",
                columns: ["normalized_name"],
                unique: true
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (13)")
        }

        migrator.registerMigration("v14_add_knowledge_edges") { db in
            try db.create(table: "knowledge_edges", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("first_node_id", .integer).notNull().references("knowledge_nodes", onDelete: .cascade)
                t.column("second_node_id", .integer).notNull().references("knowledge_nodes", onDelete: .cascade)
                t.column("description", .text).notNull()
                t.column("create_date", .datetime).notNull()
            }

            try db.create(
                index: "idx_knowledge_edges_pair",
                on: "knowledge_edges",
                columns: ["first_node_id", "second_node_id"],
                unique: true
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (14)")
        }

        migrator.registerMigration("v15_expand_knowledge_markdown_index") { db in
            try db.alter(table: "knowledge_files") { t in
                t.add(column: "title", .text)
                t.add(column: "mtime", .datetime)
                t.add(column: "metadata_json", .text)
                t.add(column: "deleted_at", .datetime)
            }

            try db.create(table: "knowledge_anchors", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("file_id", .integer).notNull().references("knowledge_files", onDelete: .cascade)
                t.column("anchor_type", .text).notNull()
                t.column("anchor_key", .text).notNull()
                t.column("heading_text", .text)
                t.column("block_id", .text)
                t.column("start_line", .integer).notNull()
                t.column("end_line", .integer).notNull()
                t.column("text_hash", .text).notNull()
            }

            try db.create(index: "idx_knowledge_anchors_file_key", on: "knowledge_anchors", columns: ["file_id", "anchor_key"], unique: true)

            try db.create(table: "knowledge_chunks", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("anchor_id", .integer).notNull().references("knowledge_anchors", onDelete: .cascade)
                t.column("ordinal", .integer).notNull()
                t.column("hash", .text).notNull()
                t.column("text", .text).notNull()
                t.column("token_count", .integer).notNull()
                t.column("bm25_docid", .integer)
                t.column("embedding", .text)
            }

            try db.create(index: "idx_knowledge_chunks_anchor_ordinal", on: "knowledge_chunks", columns: ["anchor_id", "ordinal"], unique: true)
            try db.create(index: "idx_knowledge_chunks_hash", on: "knowledge_chunks", columns: ["hash"])

            try db.create(table: "knowledge_links", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("src_anchor_id", .integer).notNull().references("knowledge_anchors", onDelete: .cascade)
                t.column("dst_file_id", .integer).references("knowledge_files", onDelete: .setNull)
                t.column("dst_anchor_hint", .text)
                t.column("link_text", .text).notNull()
                t.column("link_type", .text).notNull()
            }

            try db.create(index: "idx_knowledge_links_src_anchor", on: "knowledge_links", columns: ["src_anchor_id"])
            try db.create(index: "idx_knowledge_links_dst_file", on: "knowledge_links", columns: ["dst_file_id"])

            try db.create(table: "knowledge_aliases", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("file_id", .integer).notNull().references("knowledge_files", onDelete: .cascade)
                t.column("alias_text", .text).notNull()
            }

            try db.create(index: "idx_knowledge_aliases_file_alias", on: "knowledge_aliases", columns: ["file_id", "alias_text"], unique: true)

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (15)")
        }

        migrator.registerMigration("v16_expand_knowledge_graph_records") { db in
            try db.alter(table: "knowledge_nodes") { t in
                t.add(column: "source_chunk_id", .integer).references("knowledge_chunks", onDelete: .setNull)
                t.add(column: "bm25_docid", .integer)
                t.add(column: "embedding", .text)
            }

            try db.alter(table: "knowledge_edges") { t in
                t.add(column: "relationship_type", .text)
                t.add(column: "source_chunk_id", .integer).references("knowledge_chunks", onDelete: .setNull)
            }

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (16)")
        }

        migrator.registerMigration("v17_add_knowledge_fts") { db in
            try createSynchronizedFullTextTable(
                on: db,
                tableName: "knowledge_chunk_fts",
                contentTable: "knowledge_chunks",
                columns: ["text"],
                tokenizer: .porterAscii
            )

            try createSynchronizedFullTextTable(
                on: db,
                tableName: "knowledge_node_fts",
                contentTable: "knowledge_nodes",
                columns: ["name", "description"],
                tokenizer: .porterAscii
            )

            try db.execute(sql: "INSERT INTO knowledge_chunk_fts(knowledge_chunk_fts) VALUES('rebuild')")
            try db.execute(sql: "INSERT INTO knowledge_node_fts(knowledge_node_fts) VALUES('rebuild')")

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (17)")
        }

        migrator.registerMigration("v18_remove_knowledge_bm25_docid") { db in
            let chunkColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(knowledge_chunks)")
            if chunkColumns.contains(where: { ($0["name"] as String?) == "bm25_docid" }) {
                try db.execute(sql: "ALTER TABLE knowledge_chunks DROP COLUMN bm25_docid")
            }

            let nodeColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(knowledge_nodes)")
            if nodeColumns.contains(where: { ($0["name"] as String?) == "bm25_docid" }) {
                try db.execute(sql: "ALTER TABLE knowledge_nodes DROP COLUMN bm25_docid")
            }

            try db.execute(sql: "INSERT INTO knowledge_chunk_fts(knowledge_chunk_fts) VALUES('rebuild')")
            try db.execute(sql: "INSERT INTO knowledge_node_fts(knowledge_node_fts) VALUES('rebuild')")

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (18)")
        }

        migrator.registerMigration("v19_knowledge_node_edge_chunks") { db in
            try db.execute(sql: "DELETE FROM knowledge_edges")
            try db.execute(sql: "DELETE FROM knowledge_nodes")
            try db.execute(sql: "DELETE FROM knowledge_chunks")
            try db.execute(sql: "DELETE FROM knowledge_aliases")
            try db.execute(sql: "DELETE FROM knowledge_links")
            try db.execute(sql: "DELETE FROM knowledge_anchors")
            try db.execute(sql: "DELETE FROM knowledge_files")

            try db.execute(sql: """
                CREATE TABLE knowledge_node_chunks (
                    node_id INTEGER NOT NULL REFERENCES knowledge_nodes(id) ON DELETE CASCADE,
                    chunk_id INTEGER NOT NULL REFERENCES knowledge_chunks(id) ON DELETE CASCADE,
                    PRIMARY KEY (node_id, chunk_id)
                )
                """)

            try db.execute(sql: """
                CREATE TABLE knowledge_edge_chunks (
                    edge_id INTEGER NOT NULL REFERENCES knowledge_edges(id) ON DELETE CASCADE,
                    chunk_id INTEGER NOT NULL REFERENCES knowledge_chunks(id) ON DELETE CASCADE,
                    PRIMARY KEY (edge_id, chunk_id)
                )
                """)

            try db.execute(sql: """
                CREATE TABLE knowledge_node_activities (
                    node_id INTEGER NOT NULL REFERENCES knowledge_nodes(id) ON DELETE CASCADE,
                    activity_id INTEGER NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
                    PRIMARY KEY (node_id, activity_id)
                )
                """)

            try db.execute(sql: """
                CREATE TABLE knowledge_edge_activities (
                    edge_id INTEGER NOT NULL REFERENCES knowledge_edges(id) ON DELETE CASCADE,
                    activity_id INTEGER NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
                    PRIMARY KEY (edge_id, activity_id)
                )
                """)

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (19)")
        }

        migrator.registerMigration("v20_drop_knowledge_chunk_fts_and_embedding") { db in
            try db.dropFTS5SynchronizationTriggers(forTable: "knowledge_chunk_fts")
            if try db.tableExists("knowledge_chunk_fts") {
                try db.drop(table: "knowledge_chunk_fts")
            }

            let chunkColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(knowledge_chunks)")
                .compactMap { $0["name"] as String? }

            if chunkColumns.contains("embedding") {
                try db.execute(sql: "ALTER TABLE knowledge_chunks DROP COLUMN embedding")
            }

            if chunkColumns.contains("token_count") {
                try db.execute(sql: "ALTER TABLE knowledge_chunks DROP COLUMN token_count")
            }

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (20)")
        }

        migrator.registerMigration("v21_add_knowledge_communities") { db in
            try db.execute(sql: """
                CREATE TABLE knowledge_communities (
                    id INTEGER PRIMARY KEY,
                    name TEXT,
                    summary TEXT,
                    embedding BLOB
                )
                """)

            let nodeColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(knowledge_nodes)")
                .compactMap { $0["name"] as String? }

            if !nodeColumns.contains("community_id") {
                try db.execute(sql: """
                    ALTER TABLE knowledge_nodes
                    ADD COLUMN community_id INTEGER REFERENCES knowledge_communities(id) ON DELETE SET NULL
                    """)
            }

            try createSynchronizedFullTextTable(
                on: db,
                tableName: "knowledge_community_fts",
                contentTable: "knowledge_communities",
                columns: ["name", "summary"],
                tokenizer: .porterAscii
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (21)")
        }

        migrator.registerMigration("v22_add_knowledge_community_names") { db in
            let communityColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(knowledge_communities)")
                .compactMap { $0["name"] as String? }

            if !communityColumns.contains("name") {
                try db.execute(sql: """
                    ALTER TABLE knowledge_communities
                    ADD COLUMN name TEXT
                    """)
            }

            try db.execute(sql: "DROP TRIGGER IF EXISTS __knowledge_community_fts_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __knowledge_community_fts_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __knowledge_community_fts_au")
            try db.execute(sql: "DROP TABLE IF EXISTS knowledge_community_fts")
            try createSynchronizedFullTextTable(
                on: db,
                tableName: "knowledge_community_fts",
                contentTable: "knowledge_communities",
                columns: ["name", "summary"],
                tokenizer: .porterAscii
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (22)")
        }

        migrator.registerMigration("v23_add_knowledge_chunk_hash") { db in
            let chunkColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(knowledge_chunks)")
                .compactMap { $0["name"] as String? }

            if !chunkColumns.contains("hash") {
                try db.execute(sql: "ALTER TABLE knowledge_chunks ADD COLUMN hash TEXT")
            }

            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, text
                    FROM knowledge_chunks
                    WHERE hash IS NULL OR hash = ''
                    """
            )
            try rows.forEach { row in
                guard let id: Int64 = row["id"],
                      let text: String = row["text"] else {
                    return
                }

                let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
                try db.execute(
                    sql: "UPDATE knowledge_chunks SET hash = ? WHERE id = ?",
                    arguments: [hash, id]
                )
            }

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_hash ON knowledge_chunks(hash)")
            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (23)")
        }

        migrator.registerMigration("v24_add_knowledge_processing_state") { db in
            let chunkColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(knowledge_chunks)")
                .compactMap { $0["name"] as String? }
            if !chunkColumns.contains("processed") {
                try db.execute(sql: "ALTER TABLE knowledge_chunks ADD COLUMN processed INTEGER NOT NULL DEFAULT 0")
            }
            try db.execute(sql: """
                UPDATE knowledge_chunks
                SET processed = 1
                WHERE id IN (
                    SELECT chunk_id FROM knowledge_node_chunks
                    UNION
                    SELECT chunk_id FROM knowledge_edge_chunks
                )
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_processed ON knowledge_chunks(processed)")

            let activityColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(activities)")
                .compactMap { $0["name"] as String? }
            if !activityColumns.contains("summary_hash") {
                try db.execute(sql: "ALTER TABLE activities ADD COLUMN summary_hash TEXT")
            }
            if !activityColumns.contains("knowledge_processed") {
                try db.execute(sql: "ALTER TABLE activities ADD COLUMN knowledge_processed INTEGER NOT NULL DEFAULT 0")
            }

            let activityRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, summary
                    FROM activities
                    WHERE summary IS NOT NULL AND summary <> ''
                    """
            )
            try activityRows.forEach { row in
                guard let id: Int64 = row["id"],
                      let summary: String = row["summary"] else {
                    return
                }
                let hash = SHA256.hash(data: Data(summary.utf8)).map { String(format: "%02x", $0) }.joined()
                try db.execute(
                    sql: "UPDATE activities SET summary_hash = ? WHERE id = ?",
                    arguments: [hash, id]
                )
            }
            try db.execute(sql: """
                UPDATE activities
                SET knowledge_processed = 1
                WHERE id IN (
                    SELECT activity_id FROM knowledge_node_activities
                    UNION
                    SELECT activity_id FROM knowledge_edge_activities
                )
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_activities_summary_hash ON activities(summary_hash)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_activities_knowledge_processed_start_time ON activities(knowledge_processed, start_time)")

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (24)")
        }

        migrator.registerMigration("v25_add_knowledge_read_model_indexes") { db in
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_knowledge_files_directory_deleted_relative_path
                    ON knowledge_files(directory_id, deleted_at, relative_path)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_knowledge_nodes_community_id
                    ON knowledge_nodes(community_id)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_knowledge_node_chunks_chunk_id
                    ON knowledge_node_chunks(chunk_id)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_knowledge_node_chunks_node_id
                    ON knowledge_node_chunks(node_id)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_knowledge_edges_first_node_id
                    ON knowledge_edges(first_node_id)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_knowledge_edges_second_node_id
                    ON knowledge_edges(second_node_id)
                    """
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (25)")
        }

        migrator.registerMigration("v26_add_knowledge_claims") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS knowledge_claims (
                    id INTEGER PRIMARY KEY,
                    node_id INTEGER NOT NULL REFERENCES knowledge_nodes(id) ON DELETE CASCADE,
                    text TEXT NOT NULL,
                    md5 TEXT NOT NULL,
                    embedding BLOB,
                    create_date DATETIME NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_knowledge_claims_node_id
                ON knowledge_claims(node_id)
                """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_knowledge_claims_md5
                ON knowledge_claims(md5)
                """)

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (26)")
        }

        migrator.registerMigration("v27_add_knowledge_claim_fts") { db in
            try db.execute(sql: "DROP TRIGGER IF EXISTS __knowledge_claim_fts_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __knowledge_claim_fts_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __knowledge_claim_fts_au")
            try db.execute(sql: "DROP TABLE IF EXISTS knowledge_claim_fts")
            try createSynchronizedFullTextTable(
                on: db,
                tableName: "knowledge_claim_fts",
                contentTable: "knowledge_claims",
                columns: ["text"],
                tokenizer: .porterAscii
            )
            try db.execute(sql: "INSERT INTO knowledge_claim_fts(knowledge_claim_fts) VALUES('rebuild')")

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (27)")
        }

        migrator.registerMigration("v28_fix_knowledge_node_embedding_blob") { db in
            let nodeColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(knowledge_nodes)")
            let embeddingColumn = nodeColumns.first { ($0["name"] as String?) == "embedding" }
            let embeddingType = (embeddingColumn?["type"] as String?)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()

            if embeddingColumn != nil, embeddingType != "BLOB" {
                try db.execute(sql: "DROP TRIGGER IF EXISTS __knowledge_node_fts_ai")
                try db.execute(sql: "DROP TRIGGER IF EXISTS __knowledge_node_fts_ad")
                try db.execute(sql: "DROP TRIGGER IF EXISTS __knowledge_node_fts_au")
                try db.execute(sql: "DROP TABLE IF EXISTS knowledge_node_fts")

                let hasEmbeddingVectorColumn = nodeColumns.contains { ($0["name"] as String?) == "embedding_vector" }
                if !hasEmbeddingVectorColumn {
                    try db.execute(sql: "ALTER TABLE knowledge_nodes ADD COLUMN embedding_vector BLOB")
                }

                try db.execute(
                    sql: """
                        UPDATE knowledge_nodes
                        SET embedding_vector = CASE
                            WHEN embedding IS NULL THEN NULL
                            WHEN typeof(embedding) = 'blob' THEN embedding
                            WHEN TRIM(CAST(embedding AS TEXT)) = '' THEN NULL
                            ELSE vector_as_f32(CAST(embedding AS TEXT))
                        END
                        """
                )

                try db.execute(sql: "ALTER TABLE knowledge_nodes DROP COLUMN embedding")
                try db.execute(sql: "ALTER TABLE knowledge_nodes RENAME COLUMN embedding_vector TO embedding")

                try createSynchronizedFullTextTable(
                    on: db,
                    tableName: "knowledge_node_fts",
                    contentTable: "knowledge_nodes",
                    columns: ["name", "description"],
                    tokenizer: .porterAscii
                )

                try db.execute(sql: "INSERT INTO knowledge_node_fts(knowledge_node_fts) VALUES('rebuild')")
            }

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (28)")
        }

        migrator.registerMigration("v29_enforce_unique_knowledge_community_names") { db in
            let communities = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, name
                    FROM knowledge_communities
                    WHERE name IS NOT NULL
                      AND TRIM(name) != ''
                    ORDER BY id ASC
                    """
            )
            var usedNormalizedNames: Set<String> = []
            var usedFileNames: Set<String> = []

            for community in communities {
                guard let communityID: Int64 = community["id"],
                      let rawName: String = community["name"] else {
                    continue
                }

                let baseName = rawName
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !baseName.isEmpty else {
                    continue
                }

                let uniqueName = {
                    let normalizedBaseName = KnowledgeNodeRecord.normalizedName(for: baseName)
                    let baseFileName = KnowledgeObsidianExportNaming.fileName(communityName: baseName)

                    guard !usedNormalizedNames.contains(normalizedBaseName),
                          !usedFileNames.contains(baseFileName) else {
                        return (2...)
                            .lazy
                            .map { "\(baseName) \($0)" }
                            .first {
                                !usedNormalizedNames.contains(KnowledgeNodeRecord.normalizedName(for: $0))
                                    && !usedFileNames.contains(
                                        KnowledgeObsidianExportNaming.fileName(communityName: $0)
                                    )
                            } ?? baseName
                    }

                    return baseName
                }()

                usedNormalizedNames.insert(KnowledgeNodeRecord.normalizedName(for: uniqueName))
                usedFileNames.insert(KnowledgeObsidianExportNaming.fileName(communityName: uniqueName))

                if uniqueName != rawName {
                    try db.execute(
                        sql: "UPDATE knowledge_communities SET name = ? WHERE id = ?",
                        arguments: [uniqueName, communityID]
                    )
                }
            }

            try db.execute(sql: "DROP INDEX IF EXISTS knowledge_communities_name_unique_idx")
            try db.execute(
                sql: """
                    CREATE UNIQUE INDEX knowledge_communities_name_unique_idx
                    ON knowledge_communities(TRIM(name) COLLATE NOCASE)
                    WHERE name IS NOT NULL
                      AND TRIM(name) != ''
                    """
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (29)")
        }

        migrator.registerMigration("v30_add_overview_knowledge_progress") { db in
            let overviewColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(overviews)")
                .compactMap { $0["name"] as String? }
            if !overviewColumns.contains("knowledge_processed") {
                try db.execute(sql: "ALTER TABLE overviews ADD COLUMN knowledge_processed INTEGER NOT NULL DEFAULT 0")
            }

            try db.execute(
                sql: """
                    UPDATE overviews
                    SET knowledge_processed = CASE
                        WHEN EXISTS (
                            SELECT 1
                            FROM activities
                            WHERE activities.overview_id = overviews.id
                        ) AND NOT EXISTS (
                            SELECT 1
                            FROM activities
                            WHERE activities.overview_id = overviews.id
                              AND (
                                  activities.summary IS NULL
                                  OR activities.summary = ''
                                  OR activities.knowledge_processed = 0
                              )
                        ) THEN 1
                        ELSE 0
                    END
                    """
            )
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_overviews_knowledge_processed ON overviews(knowledge_processed)")

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (30)")
        }

        migrator.registerMigration("v31_add_knowledge_source_slots") { db in
            let directoryColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(knowledge_directories)")
                .compactMap { $0["name"] as String? }

            if !directoryColumns.contains("slot") {
                try db.execute(
                    sql: """
                        ALTER TABLE knowledge_directories
                        ADD COLUMN slot TEXT NOT NULL DEFAULT 'obsidian_vault'
                        """
                )
            }

            try db.execute(
                sql: """
                    UPDATE knowledge_directories
                    SET slot = ?
                    WHERE slot IS NULL
                       OR TRIM(slot) = ''
                    """,
                arguments: [KnowledgeSourceSlot.obsidianVault.rawValue]
            )

            let obsoleteDirectoryIDs = try Int64.fetchAll(
                db,
                sql: """
                    SELECT id
                    FROM knowledge_directories
                    WHERE slot = ?
                    ORDER BY created_at DESC, id DESC
                    LIMIT -1 OFFSET 1
                    """,
                arguments: [KnowledgeSourceSlot.obsidianVault.rawValue]
            )

            try obsoleteDirectoryIDs.forEach {
                try db.execute(
                    sql: "DELETE FROM knowledge_directories WHERE id = ?",
                    arguments: [$0]
                )
            }

            try db.execute(sql: "DROP INDEX IF EXISTS idx_knowledge_directories_slot")
            try db.execute(
                sql: """
                    CREATE UNIQUE INDEX idx_knowledge_directories_slot
                    ON knowledge_directories(slot)
                    """
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (31)")
        }

        migrator.registerMigration("v32_add_jobs") { db in
            try db.create(table: "jobs", ifNotExists: true) { t in
                t.column("name", .text).primaryKey()
                t.column("schedule_type", .text).notNull()
                t.column("interval_seconds", .integer)
                t.column("daily_policy_json", .text)
                t.column("last_success_at", .datetime)
                t.column("last_started_at", .datetime)
                t.column("lease_until", .datetime)
                t.column("enabled", .boolean).notNull().defaults(to: false)
            }

            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_jobs_enabled_lease
                    ON jobs(enabled, lease_until)
                    """
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (32)")
        }

        migrator.registerMigration("v33_add_activity_summary_umap_vector") { db in
            let activityColumns = try db.columns(in: "activities").map(\.name)

            if !activityColumns.contains("summary_vector_umap") {
                try db.execute(sql: "ALTER TABLE activities ADD COLUMN summary_vector_umap BLOB")
            }

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (33)")
        }

        migrator.registerMigration("v34_add_activity_summary_vector_index") { db in
            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (34)")
        }

        migrator.registerMigration("v35_remove_screenshot_image_deletion_reason") { db in
            let screenshotColumns = try db.columns(in: "screenshots").map(\.name)

            guard screenshotColumns.contains("image_deletion_reason") else {
                try db.execute(sql: "DELETE FROM versions")
                try db.execute(sql: "INSERT INTO versions (version) VALUES (35)")
                return
            }

            try db.execute(
                sql: """
                    CREATE TABLE screenshots_v35 (
                        id INTEGER PRIMARY KEY NOT NULL,
                        image BLOB,
                        ts TIMESTAMP,
                        description TEXT,
                        ocr_text TEXT,
                        description_vector BLOB,
                        ignore_reason TEXT,
                        json_properties TEXT,
                        activity_id INTEGER NOT NULL REFERENCES activities(id) ON DELETE CASCADE
                    )
                    """
            )
            try db.execute(
                sql: """
                    INSERT INTO screenshots_v35 (
                        id,
                        image,
                        ts,
                        description,
                        ocr_text,
                        description_vector,
                        ignore_reason,
                        json_properties,
                        activity_id
                    )
                    SELECT
                        id,
                        image,
                        ts,
                        description,
                        ocr_text,
                        description_vector,
                        ignore_reason,
                        json_properties,
                        activity_id
                    FROM screenshots
                    """
            )
            try db.execute(sql: "DROP TABLE screenshots")
            try db.execute(sql: "ALTER TABLE screenshots_v35 RENAME TO screenshots")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_screenshots_ts ON screenshots (ts)")

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (35)")
        }

        migrator.registerMigration("v36_add_activity_tag_ontology_metadata") { db in
            let tagColumns = try db.columns(in: "tags").map(\.name)

            if !tagColumns.contains("origin_kind") {
                try db.execute(sql: "ALTER TABLE tags ADD COLUMN origin_kind TEXT")
            }

            if !tagColumns.contains("generated_name") {
                try db.execute(sql: "ALTER TABLE tags ADD COLUMN generated_name TEXT")
            }

            if !tagColumns.contains("generated_description") {
                try db.execute(sql: "ALTER TABLE tags ADD COLUMN generated_description TEXT")
            }

            if !tagColumns.contains("name_is_user_edited") {
                try db.execute(
                    sql: """
                        ALTER TABLE tags
                        ADD COLUMN name_is_user_edited INTEGER NOT NULL DEFAULT 0
                        """
                )
            }

            if !tagColumns.contains("description_is_user_edited") {
                try db.execute(
                    sql: """
                        ALTER TABLE tags
                        ADD COLUMN description_is_user_edited INTEGER NOT NULL DEFAULT 0
                        """
                )
            }

            let activityColumns = try db.columns(in: "activities").map(\.name)

            if !activityColumns.contains("tag_assignment_source") {
                try db.execute(sql: "ALTER TABLE activities ADD COLUMN tag_assignment_source TEXT")
            }

            try db.execute(
                sql: """
                    UPDATE tags
                    SET origin_kind = ?
                    WHERE id IN (?, ?)
                    """,
                arguments: [
                    TagOriginKind.system.rawValue,
                    SystemTags.inactiveID,
                    SystemTags.taggingFailureID
                ]
            )
            try db.execute(
                sql: """
                    UPDATE tags
                    SET origin_kind = ?
                    WHERE origin_kind IS NULL
                      AND id NOT IN (?, ?)
                    """,
                arguments: [
                    TagOriginKind.manual.rawValue,
                    SystemTags.inactiveID,
                    SystemTags.taggingFailureID
                ]
            )
            try db.execute(
                sql: """
                    UPDATE activities
                    SET tag_assignment_source = ?
                    WHERE tag_id IS NOT NULL
                      AND tag_assignment_source IS NULL
                    """,
                arguments: [ActivityTagAssignmentSource.manual.rawValue]
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_activities_tag_assignment_source
                    ON activities(tag_assignment_source)
                    """
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (36)")
        }

        migrator.registerMigration("v37_add_activity_tag_ontology_schema") { db in
            try db.create(table: "activity_edges", ifNotExists: true) { t in
                t.column("first_activity_id", .integer).notNull().references("activities", onDelete: .cascade)
                t.column("second_activity_id", .integer).notNull().references("activities", onDelete: .cascade)
                t.column("weight", .double).notNull()
                t.primaryKey(["first_activity_id", "second_activity_id"])
            }

            try db.create(table: "activity_tag_ontology_runs", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("created_at", .datetime).notNull()
                t.column("previous_run_id", .integer).references("activity_tag_ontology_runs", onDelete: .setNull)
                t.column("k_neighbors", .integer).notNull()
                t.column("leiden_resolution", .double).notNull()
                t.column("leiden_theta", .double).notNull()
                t.column("continuity_alpha", .double).notNull()
                t.column("continuity_beta", .double).notNull()
                t.column("continuity_gamma", .double).notNull()
            }

            try db.create(table: "activity_tag_ontology_candidates", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("run_id", .integer).notNull().references("activity_tag_ontology_runs", onDelete: .cascade)
                t.column("tag_id", .integer).notNull().references("tags")
                t.column("predecessor_candidate_id", .integer).references("activity_tag_ontology_candidates", onDelete: .setNull)
                t.column("name", .text)
                t.column("summary", .text)
                t.column("centroid_vector", .blob)
                t.column("member_count", .integer).notNull().defaults(to: 0)
                t.column("member_overlap", .double)
                t.column("centroid_similarity", .double)
                t.column("continuity_similarity", .double)
            }

            try db.create(table: "activity_tag_ontology_candidate_activities", ifNotExists: true) { t in
                t.column("candidate_id", .integer).notNull().references("activity_tag_ontology_candidates", onDelete: .cascade)
                t.column("activity_id", .integer).notNull().references("activities", onDelete: .cascade)
                t.column("centrality_score", .double)
                t.primaryKey(["candidate_id", "activity_id"])
            }

            let activityColumns = try db.columns(in: "activities").map(\.name)

            if !activityColumns.contains("ontology_candidate_id") {
                try db.execute(
                    sql: """
                        ALTER TABLE activities
                        ADD COLUMN ontology_candidate_id INTEGER
                        REFERENCES activity_tag_ontology_candidates(id) ON DELETE SET NULL
                        """
                )
            }

            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_activity_edges_first_activity_id
                    ON activity_edges(first_activity_id)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_activity_edges_second_activity_id
                    ON activity_edges(second_activity_id)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_activity_tag_ontology_runs_created_at
                    ON activity_tag_ontology_runs(created_at DESC, id DESC)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_activity_tag_ontology_candidates_run_id
                    ON activity_tag_ontology_candidates(run_id)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_activity_tag_ontology_candidates_tag_id
                    ON activity_tag_ontology_candidates(tag_id)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_activity_tag_ontology_candidate_activities_activity_id
                    ON activity_tag_ontology_candidate_activities(activity_id)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_activities_ontology_candidate_id
                    ON activities(ontology_candidate_id)
                    """
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (37)")
        }

        migrator.registerMigration("v38_backfill_activity_tag_ontology_edges") { db in
            try rebuildActivityTagOntologyEdges(on: db)

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (38)")
        }

        migrator.registerMigration("v39_repair_activity_tag_ontology_edges") { db in
            try rebuildActivityTagOntologyEdges(on: db)

            let ontologyRunCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM activity_tag_ontology_runs
                    """
            ) ?? 0
            let eligibleActivityCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM activities
                    WHERE summary_vector IS NOT NULL
                    """
            ) ?? 0

            if ontologyRunCount == 0,
               eligibleActivityCount > 0 {
                try db.execute(
                    sql: """
                        UPDATE jobs
                        SET
                            last_success_at = NULL,
                            last_started_at = NULL,
                            lease_until = NULL
                        WHERE name = ?
                        """,
                    arguments: [TaskTraceJobName.activityTagOntologyRefresh.rawValue]
                )
            }

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (39)")
        }

        migrator.registerMigration("v40_add_ontology_overview_routing") { db in
            let overviewColumns = try db.columns(in: "overviews").map(\.name)

            if !overviewColumns.contains("origin_kind") {
                try db.execute(sql: "ALTER TABLE overviews ADD COLUMN origin_kind TEXT")
            }
            if !overviewColumns.contains("generated_title") {
                try db.execute(sql: "ALTER TABLE overviews ADD COLUMN generated_title TEXT")
            }
            if !overviewColumns.contains("generated_summary") {
                try db.execute(sql: "ALTER TABLE overviews ADD COLUMN generated_summary TEXT")
            }
            if !overviewColumns.contains("title_is_user_edited") {
                try db.execute(sql: "ALTER TABLE overviews ADD COLUMN title_is_user_edited INTEGER NOT NULL DEFAULT 0")
            }
            if !overviewColumns.contains("summary_is_user_edited") {
                try db.execute(sql: "ALTER TABLE overviews ADD COLUMN summary_is_user_edited INTEGER NOT NULL DEFAULT 0")
            }

            let activityColumns = try db.columns(in: "activities").map(\.name)

            if !activityColumns.contains("overview_assignment_source") {
                try db.execute(sql: "ALTER TABLE activities ADD COLUMN overview_assignment_source TEXT")
            }

            try db.create(table: "overview_day_tag_bindings", ifNotExists: true) { t in
                t.column("day_start", .date).notNull()
                t.column("tag_id", .integer).notNull().references("tags", onDelete: .cascade)
                t.column("overview_id", .integer).notNull().references("overviews", onDelete: .cascade)
                t.column("binding_source", .text).notNull()
                t.primaryKey(["day_start", "tag_id"])
            }

            try db.execute(
                sql: """
                    UPDATE activities
                    SET overview_assignment_source = ?
                    WHERE overview_assignment_source IS NULL
                    """,
                arguments: [OverviewAssignmentSource.legacy.rawValue]
            )
            try db.execute(
                sql: """
                    UPDATE overviews
                    SET origin_kind = ?
                    WHERE origin_kind IS NULL
                    """,
                arguments: [OverviewOriginKind.legacy.rawValue]
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_activities_overview_assignment_source
                    ON activities(overview_assignment_source)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_overview_day_tag_bindings_overview_id
                    ON overview_day_tag_bindings(overview_id)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_overview_day_tag_bindings_day_start
                    ON overview_day_tag_bindings(day_start)
                    """
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (40)")
        }

        migrator.registerMigration("v41_add_community_summary_input_hash") { db in
            let communityColumns = try db.columns(in: "knowledge_communities").map(\.name)

            if !communityColumns.contains("summary_input_hash") {
                try db.execute(
                    sql: """
                        ALTER TABLE knowledge_communities
                        ADD COLUMN summary_input_hash TEXT
                        """
                )
            }

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (41)")
        }

        migrator.registerMigration("v42_remove_activity_tag_ontology_current_flag") { db in
            let ontologyRunColumns = try db.columns(in: "activity_tag_ontology_runs").map(\.name)

            if ontologyRunColumns.contains("is_current") {
                try db.execute(sql: "DROP INDEX IF EXISTS idx_activity_tag_ontology_runs_current")
                try db.execute(sql: "ALTER TABLE activity_tag_ontology_runs DROP COLUMN is_current")
            }

            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_activity_tag_ontology_runs_created_at
                    ON activity_tag_ontology_runs(created_at DESC, id DESC)
                    """
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (42)")
        }

        migrator.registerMigration("v43_move_activity_summary_vector_index_to_runtime_sidecar") { db in
            try db.create(table: activitySummaryVectorIndexDirtyIDsTableName, ifNotExists: true) { t in
                t.column("activity_id", .integer).notNull().references("activities", onDelete: .cascade)
                t.primaryKey(["activity_id"])
            }

            try removeLegacyActivitySummaryVectorIndexSchemaEntry(on: db)

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (43)")
        }

        migrator.registerMigration("v44_add_screenshot_summary") { db in
            let screenshotColumns = try db.columns(in: "screenshots").map(\.name)

            if !screenshotColumns.contains("summary") {
                try db.execute(sql: "ALTER TABLE screenshots ADD COLUMN summary TEXT")
            }

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (44)")
        }

        migrator.registerMigration("v45_add_goals") { db in
            try db.create(table: "goals", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("create_ts", .datetime).notNull()
                t.column("done_ts", .datetime)
            }

            try db.create(table: "goal_todos", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("goal_id", .integer).notNull().references("goals", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("create_ts", .datetime).notNull()
                t.column("done_ts", .datetime)
                t.column("status", .text).notNull().defaults(to: "open")
                t.column("status_ts", .datetime)
                t.column("repeating", .boolean).notNull().defaults(to: false)
                t.column("repeat_template_id", .integer).references("goal_todos", onDelete: .cascade)
                t.column("target_date", .date)
                t.column("daily_target_seconds", .integer)
                t.column("embedding", .blob)
            }

            let activityColumns = try db.columns(in: "activities").map(\.name)

            if !activityColumns.contains("goal_todo_id") {
                try db.execute(
                    sql: """
                        ALTER TABLE activities
                        ADD COLUMN goal_todo_id INTEGER REFERENCES goal_todos(id) ON DELETE SET NULL
                        """
                )
            }

            if !activityColumns.contains("goal_todo_assignment_source") {
                try db.execute(sql: "ALTER TABLE activities ADD COLUMN goal_todo_assignment_source TEXT")
            }

            if !activityColumns.contains("goal_todo_assignment_score") {
                try db.execute(sql: "ALTER TABLE activities ADD COLUMN goal_todo_assignment_score REAL")
            }

            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_goals_open
                    ON goals(done_ts, create_ts)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_goal_todos_goal_status
                    ON goal_todos(goal_id, status, target_date)
                    """
            )
            try db.execute(
                sql: """
                    CREATE UNIQUE INDEX IF NOT EXISTS idx_goal_todos_repeat_instance
                    ON goal_todos(repeat_template_id, target_date)
                    WHERE repeat_template_id IS NOT NULL
                      AND target_date IS NOT NULL
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_activities_goal_todo
                    ON activities(goal_todo_id, start_time)
                    """
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (45)")
        }

        migrator.registerMigration("v46_add_goal_soft_deletes") { db in
            let goalColumns = try db.columns(in: "goals").map(\.name)
            let todoColumns = try db.columns(in: "goal_todos").map(\.name)

            if !goalColumns.contains("delete_ts") {
                try db.execute(sql: "ALTER TABLE goals ADD COLUMN delete_ts DATETIME")
            }

            if !todoColumns.contains("delete_ts") {
                try db.execute(sql: "ALTER TABLE goal_todos ADD COLUMN delete_ts DATETIME")
            }

            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_goals_visible
                    ON goals(delete_ts, done_ts, create_ts)
                    """
            )
            try db.execute(
                sql: """
                    CREATE INDEX IF NOT EXISTS idx_goal_todos_visible
                    ON goal_todos(delete_ts, goal_id, status, target_date)
                    """
            )

            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (46)")
        }

        return migrator
    }

    private nonisolated static func removeLegacyActivitySummaryVectorIndexSchemaEntry(
        on db: Database
    ) throws {
        let legacyIndexExists = try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1
                    FROM sqlite_schema
                    WHERE type = 'table'
                      AND name = ?
                )
                """,
            arguments: [activitySummaryVectorIndexTableName]
        ) ?? false

        guard legacyIndexExists,
              let sqliteConnection = db.sqliteConnection else {
            return
        }

        _ = taskTraceSQLiteSetDefensiveMode(sqliteConnection, 0)

        do {
            try db.execute(sql: "PRAGMA writable_schema = 1")
            try db.execute(
                sql: """
                    DELETE FROM sqlite_schema
                    WHERE type = 'table'
                      AND name = ?
                    """,
                arguments: [activitySummaryVectorIndexTableName]
            )
            try db.execute(sql: "PRAGMA writable_schema = 0")

            let integrityCheck = try String.fetchOne(db, sql: "PRAGMA integrity_check")

            guard integrityCheck == "ok" else {
                throw DatabaseError(
                    resultCode: .SQLITE_CORRUPT,
                    message: "Integrity check failed after removing legacy activity summary vector index."
                )
            }
        } catch {
            try? db.execute(sql: "PRAGMA writable_schema = 0")
            _ = taskTraceSQLiteSetDefensiveMode(sqliteConnection, 1)
            throw error
        }

        _ = taskTraceSQLiteSetDefensiveMode(sqliteConnection, 1)
    }

    private nonisolated static func sqlDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
