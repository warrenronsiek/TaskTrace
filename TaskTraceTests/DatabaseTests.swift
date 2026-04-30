//
//  DatabaseTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/12/26.
//

import Foundation
import GRDB
import SQLite3
import Testing
@testable import TaskTrace

struct TaskTraceDatabaseTests {
    private let softRelevanceFloor = 1_000.0
    private let productionRelevanceFloor = -3.0

    private func withDatabase(
        activityAI: any ActivityAIOperating = FakeActivityAI(),
        _ block: (TaskTraceDatabase, URL) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: activityAI)

        try await block(database, databaseURL)
    }

    private func withLegacyV38OntologyRepairDatabase(
        _ block: (TaskTraceDatabase, JobsDatabaseActor) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
        let seededDatabase = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let activityDatabaseActor = ActivityDatabaseActor(database: seededDatabase)

        for (activityID, vector) in [
            (701 as Int64, activityEmbedding(activatedDimension: 0)),
            (702 as Int64, activityEmbedding(activatedDimension: 0)),
            (703 as Int64, activityEmbedding(activatedDimension: 1))
        ] {
            try await seededDatabase.saveActivityRecord(ActivityInput(
                id: activityID,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Legacy ontology repair seed \(activityID)",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await activityDatabaseActor.persistActivitySummaryVector(
                activityID: activityID,
                vector: vector
            )
        }

        let migrationRollbackQueue = try DatabaseQueue(
            path: databaseURL.path,
            configuration: TaskTraceDatabaseBootstrap.makeConfiguration(
                label: "TaskTraceLegacyOntologyRepairRollbackTests",
                extensionSet: .migrator
            )
        )

        try await migrationRollbackQueue.write { db in
            try db.execute(sql: "DELETE FROM activity_edges")
            try db.execute(sql: "DELETE FROM activity_tag_ontology_candidate_activities")
            try db.execute(sql: "DELETE FROM activity_tag_ontology_candidates")
            try db.execute(sql: "DELETE FROM activity_tag_ontology_runs")
            try db.execute(
                sql: """
                    UPDATE jobs
                    SET
                        last_success_at = ?,
                        last_started_at = ?,
                        lease_until = NULL
                    WHERE name = ?
                    """,
                arguments: [
                    sqlTimestamp(localDate(dayOffset: 0, hour: 1, minute: 27)),
                    sqlTimestamp(localDate(dayOffset: 0, hour: 1, minute: 27)),
                    TaskTraceJobName.activityTagOntologyRefresh.rawValue
                ]
            )
            try db.execute(
                sql: """
                    DELETE FROM grdb_migrations
                    WHERE identifier = ?
                    """,
                arguments: ["v39_repair_activity_tag_ontology_edges"]
            )
            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (38)")
        }

        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let jobsDatabaseActor = JobsDatabaseActor(database: database)

        try await block(database, jobsDatabaseActor)
    }

    @Test("database initialization writes the sqlite file to disk")
    func initializationWritesSQLiteFile() async throws {
        try await withDatabase { _, databaseURL in
            #expect(FileManager.default.fileExists(atPath: databaseURL.path))
        }
    }

    @Test("legacy knowledge directories schema accepts the slot migration column definition")
    func legacyKnowledgeDirectoriesSchemaAcceptsTheSlotMigrationColumnDefinition() throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let queue = try DatabaseQueue(
            path: databaseURL.path,
            configuration: TaskTraceDatabaseBootstrap.makeConfiguration(
                label: "TaskTraceMigrationDDLTests",
                extensionSet: .pooledRead
            )
        )

        try queue.write { db in
            try db.create(table: "knowledge_directories", ifNotExists: true) { t in
                t.column("id", Database.ColumnType.integer).primaryKey()
                t.column("path", .text).notNull()
                t.column("bookmark_data", .blob)
                t.column("created_at", .datetime).notNull()
            }

            try db.execute(
                sql: """
                    ALTER TABLE knowledge_directories
                    ADD COLUMN slot TEXT NOT NULL DEFAULT 'obsidian_vault'
                    """
            )

            let columnNames = try Row.fetchAll(db, sql: "PRAGMA table_info(knowledge_directories)")
                .compactMap { $0["name"] as String? }

            #expect(columnNames.contains("slot"))
        }
    }

    @Test("database initialization creates the rebuilt schema at the current version")
    func initializationCreatesTheCurrentSchemaVersion() async throws {
        try await withDatabase { database, _ in
            let version = try await database.getVersion()
            #expect(version == TaskTraceDatabaseBootstrap.currentVersion)
        }
    }

    @Test("database initialization removes the ontology current flag column")
    func initializationRemovesTheOntologyCurrentFlagColumn() async throws {
        try await withDatabase { database, _ in
            let columnNames = try database.read { db in
                try db.columns(in: "activity_tag_ontology_runs").map(\.name)
            }

            #expect(!columnNames.contains("is_current"))
        }
    }

    @Test("database initialization enables wal journal mode")
    func initializationEnablesWALJournalMode() async throws {
        try await withDatabase { _, databaseURL in
            let queue = try DatabaseQueue(path: databaseURL.path)
            let journalMode = try queue.read { db in
                try String.fetchOne(db, sql: "PRAGMA journal_mode")
            }
            #expect(journalMode == "wal")
        }
    }

    @Test("database initialization makes sqlite vector available")
    func initializationMakesSQLiteVectorAvailable() async throws {
        try await withDatabase { database, _ in
            let version = try await database.getVectorVersion()
            #expect(!(version ?? "").isEmpty)
        }
    }

    @Test("database initialization creates the activity summary vector index as a temp table")
    func initializationCreatesTheActivitySummaryVectorIndex() async throws {
        try await withDatabase { database, _ in
            let indexExists = try database.vectorAwareRead { db in
                try Bool.fetchOne(
                    db,
                    sql: """
                        SELECT EXISTS(
                            SELECT 1
                            FROM sqlite_temp_master
                            WHERE type = 'table'
                              AND name = ?
                        )
                        """,
                    arguments: [TaskTraceDatabaseBootstrap.activitySummaryVectorIndexTableName]
                ) ?? false
            }

            #expect(indexExists)
        }
    }

    @Test("database initialization removes the activity summary vector index from the persisted schema")
    func initializationRemovesTheActivitySummaryVectorIndexFromThePersistedSchema() async throws {
        try await withDatabase { database, _ in
            let indexExists = try database.read { db in
                try Bool.fetchOne(
                    db,
                    sql: """
                        SELECT EXISTS(
                            SELECT 1
                            FROM sqlite_master
                            WHERE type = 'table'
                              AND name = ?
                        )
                        """,
                    arguments: [TaskTraceDatabaseBootstrap.activitySummaryVectorIndexTableName]
                ) ?? false
            }

            #expect(!indexExists)
        }
    }

    @Test("legacy v33 activity vectors migrate into the activity vector index")
    func legacyActivityVectorsMigrateIntoTheActivityVectorIndex() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let legacyDatabase = try DatabaseQueue(
            path: databaseURL.path,
            configuration: TaskTraceDatabaseBootstrap.makeConfiguration(
                label: "TaskTraceLegacyActivityVectorMigrationTests",
                extensionSet: .pooledRead
            )
        )

        try await legacyDatabase.write { db in
            try db.execute(sql: "CREATE TABLE tags (id INTEGER PRIMARY KEY NOT NULL, name TEXT, create_date DATE, description TEXT, delete_date DATE, json_properties TEXT)")
            try db.execute(sql: "CREATE TABLE overviews (id INTEGER PRIMARY KEY NOT NULL, title TEXT, summary TEXT, summary_vector BLOB, json_properties TEXT, edited_duration INTEGER, tag_id INTEGER REFERENCES tags(id) ON DELETE SET NULL)")
            try db.execute(
                sql: """
                    CREATE TABLE activities (
                        id INTEGER PRIMARY KEY NOT NULL,
                        start_time TIMESTAMP NOT NULL,
                        application TEXT NOT NULL,
                        keystrokes TEXT,
                        microphone TEXT,
                        summary TEXT,
                        summary_hash TEXT,
                        summary_vector BLOB,
                        summary_vector_umap BLOB,
                        knowledge_processed INTEGER NOT NULL DEFAULT 0,
                        tag_id INTEGER REFERENCES tags(id) ON DELETE SET NULL,
                        json_properties TEXT,
                        overview_id INTEGER REFERENCES overviews(id) ON DELETE SET NULL
                    )
                    """
            )
            try db.execute(sql: "CREATE INDEX idx_activities_start_time ON activities (start_time)")
            try db.execute(sql: "CREATE TABLE screenshots (id INTEGER PRIMARY KEY NOT NULL, image BLOB, ts TIMESTAMP, description TEXT, ocr_text TEXT, description_vector BLOB, image_deletion_reason TEXT, ignore_reason TEXT, json_properties TEXT, activity_id INTEGER NOT NULL REFERENCES activities(id) ON DELETE CASCADE)")
            try db.execute(sql: "CREATE INDEX idx_screenshots_ts ON screenshots (ts)")
            try db.execute(sql: "CREATE TABLE versions (version INTEGER NOT NULL)")
            try db.execute(sql: "CREATE TABLE settings (name TEXT PRIMARY KEY, value TEXT)")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (33)")
            try db.execute(
                sql: """
                    INSERT INTO activities (
                        id,
                        start_time,
                        application,
                        keystrokes,
                        microphone,
                        summary,
                        summary_hash,
                        summary_vector,
                        summary_vector_umap,
                        knowledge_processed,
                        tag_id,
                        json_properties,
                        overview_id
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, vector_as_f32(?), ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    101,
                    sqlTimestamp(localDate(dayOffset: 0, hour: 9)),
                    "Xcode",
                    nil,
                    nil,
                    "Implement the vector index migration.",
                    nil,
                    try vectorJSONString(activityEmbedding(activatedDimension: 0)),
                    nil,
                    0,
                    nil,
                    nil,
                    nil
                ]
            )
        }

        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
        let migratedDatabase = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let nearestActivityIDs = try migratedDatabase.vectorAwareRead { db in
            try Int64.fetchAll(
                db,
                sql: """
                    SELECT rowid
                    FROM \(TaskTraceDatabaseBootstrap.activitySummaryVectorIndexTableName)
                    WHERE knn_search(
                        embedding,
                        knn_param(vector_from_json(?), 1)
                    )
                    ORDER BY distance ASC, rowid ASC
                    """,
                arguments: [try vectorJSONString(activityEmbedding(activatedDimension: 0))]
            )
        }
        let version = try migratedDatabase.getVersion()

        #expect(nearestActivityIDs == [101])
        #expect(version == TaskTraceDatabaseBootstrap.currentVersion)
    }

    @Test("v43 migration removes the legacy persisted activity vector index schema entry")
    func v43MigrationRemovesTheLegacyPersistedActivityVectorIndexSchemaEntry() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let queue = try DatabaseQueue(
            path: databaseURL.path,
            configuration: TaskTraceDatabaseBootstrap.makeConfiguration(
                label: "TaskTraceLegacyVectorIndexSchemaCleanupTests",
                extensionSet: .pooledRead
            )
        )

        try await queue.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v43_move_activity_summary_vector_index_to_runtime_sidecar'")
            try db.execute(sql: "DELETE FROM versions")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (42)")

            guard let sqliteConnection = db.sqliteConnection else {
                throw DatabaseError(resultCode: .SQLITE_MISUSE, message: "sqlite connection unavailable")
            }

            _ = taskTraceSQLiteSetDefensiveMode(sqliteConnection, 0)
            try db.execute(sql: "PRAGMA writable_schema = 1")
            try db.execute(
                sql: """
                    INSERT INTO sqlite_schema(type, name, tbl_name, rootpage, sql)
                    VALUES (
                        'table',
                        ?,
                        ?,
                        0,
                        ?
                    )
                    """,
                arguments: [
                    TaskTraceDatabaseBootstrap.activitySummaryVectorIndexTableName,
                    TaskTraceDatabaseBootstrap.activitySummaryVectorIndexTableName,
                    """
                    CREATE VIRTUAL TABLE activity_summary_vector_index
                    USING vectorlite(
                        embedding float32[1024] cosine,
                        hnsw(max_elements=1048576)
                    )
                    """
                ]
            )
            try db.execute(sql: "PRAGMA writable_schema = 0")
            _ = taskTraceSQLiteSetDefensiveMode(sqliteConnection, 1)
        }

        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let migratedDatabase = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let persistedIndexExists = try migratedDatabase.read { db in
            try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                        SELECT 1
                        FROM sqlite_master
                        WHERE type = 'table'
                          AND name = ?
                    )
                    """,
                arguments: [TaskTraceDatabaseBootstrap.activitySummaryVectorIndexTableName]
            ) ?? false
        }

        #expect(!persistedIndexExists)
    }

    @Test("database startup loads the activity vector index from canonical activity vectors")
    func databaseStartupLoadsTheActivityVectorIndexFromCanonicalActivityVectors() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let seedDatabase = try DatabaseQueue(
            path: databaseURL.path,
            configuration: TaskTraceDatabaseBootstrap.makeConfiguration(
                label: "TaskTraceActivityVectorStartupRebuildTests",
                extensionSet: .pooledRead
            )
        )

        try await seedDatabase.write { db in
            try db.execute(
                sql: """
                    INSERT INTO activities (
                        id,
                        start_time,
                        application,
                        summary,
                        summary_vector,
                        knowledge_processed
                    )
                    VALUES (?, ?, ?, ?, vector_as_f32(?), ?)
                    """,
                arguments: [
                    301,
                    sqlTimestamp(localDate(dayOffset: 0, hour: 10)),
                    "Xcode",
                    "Rebuild the startup activity vector index.",
                    try vectorJSONString(activityEmbedding(activatedDimension: 0)),
                    0
                ]
            )
        }

        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let nearestActivityIDs = try database.vectorAwareRead { db in
            try Int64.fetchAll(
                db,
                sql: """
                    SELECT rowid
                    FROM \(TaskTraceDatabaseBootstrap.activitySummaryVectorIndexTableName)
                    WHERE knn_search(
                        embedding,
                        knn_param(vector_from_json(?), 1)
                    )
                    ORDER BY distance ASC, rowid ASC
                    """,
                arguments: [try vectorJSONString(activityEmbedding(activatedDimension: 0))]
            )
        }

        #expect(nearestActivityIDs == [301])
    }

    @Test("activity summary vector index supports knn search")
    func activitySummaryVectorIndexSupportsKNNSearch() async throws {
        try await withDatabase { database, _ in
            let activityDatabaseActor = ActivityDatabaseActor(database: database)

            try await activityDatabaseActor.saveActivityRecord(ActivityInput(
                id: 201,
                startTime: today(),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Implement activity vector indexing.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await activityDatabaseActor.saveActivityRecord(ActivityInput(
                id: 202,
                startTime: today(),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Review browser traces.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            await activityDatabaseActor.receive(Envelope(
                sender: nil,
                message: ActivitySummaryEmbedded(
                    activityID: 201,
                    vector: activityEmbedding(activatedDimension: 0)
                )
            ))
            await activityDatabaseActor.receive(Envelope(
                sender: nil,
                message: ActivitySummaryEmbedded(
                    activityID: 202,
                    vector: activityEmbedding(activatedDimension: 1)
                )
            ))

            let nearestActivityIDs = try database.vectorAwareRead { db in
                try Int64.fetchAll(
                    db,
                    sql: """
                        SELECT rowid
                        FROM \(TaskTraceDatabaseBootstrap.activitySummaryVectorIndexTableName)
                        WHERE knn_search(
                            embedding,
                            knn_param(vector_from_json(?), 2)
                        )
                        ORDER BY distance ASC, rowid ASC
                        """,
                    arguments: [try vectorJSONString(activityEmbedding(activatedDimension: 0))]
                )
            }

            #expect(nearestActivityIDs == [201, 202])
        }
    }

    @Test("v39 repair migration backfills ontology edges for legacy v38 databases")
    func v39RepairMigrationBackfillsOntologyEdgesForLegacyV38Databases() async throws {
        try await withLegacyV38OntologyRepairDatabase { database, _ in
            let edgeCount = try database.read { db in
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*)
                        FROM activity_edges
                        """
                ) ?? 0
            }

            #expect(edgeCount == 3)
        }
    }

    @Test("v39 repair migration clears ontology refresh success when no current run exists")
    func v39RepairMigrationClearsOntologyRefreshSuccessWhenNoCurrentRunExists() async throws {
        try await withLegacyV38OntologyRepairDatabase { _, jobsDatabaseActor in
            let ontologyRefreshJob = try #require(
                try await jobsDatabaseActor.loadJob(named: .activityTagOntologyRefresh)
            )

            #expect(ontologyRefreshJob.lastSuccessAt == nil)
        }
    }

    @Test("ontology refresh snapshot selects the latest run when created at ties")
    func ontologyRefreshSnapshotSelectsTheLatestRunWhenCreatedAtTies() async throws {
        try await withDatabase { database, _ in
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            let createdAt = Date(timeIntervalSince1970: 1_765_000_000)

            try await activityDatabaseActor.publishActivityTagOntologyRun(
                ActivityTagOntologyRunInput(
                    runID: 801,
                    createdAt: createdAt,
                    previousRunID: nil,
                    candidates: [],
                    kNeighbors: ActivityTagOntologyDefaults.neighborCount,
                    leidenResolution: ActivityTagOntologyDefaults.leidenResolution,
                    leidenTheta: ActivityTagOntologyDefaults.leidenTheta,
                    continuityAlpha: ActivityTagOntologyDefaults.continuityAlpha,
                    continuityBeta: ActivityTagOntologyDefaults.continuityBeta,
                    continuityGamma: ActivityTagOntologyDefaults.continuityGamma
                ),
                tags: []
            )
            try await activityDatabaseActor.publishActivityTagOntologyRun(
                ActivityTagOntologyRunInput(
                    runID: 802,
                    createdAt: createdAt,
                    previousRunID: 801,
                    candidates: [],
                    kNeighbors: ActivityTagOntologyDefaults.neighborCount,
                    leidenResolution: ActivityTagOntologyDefaults.leidenResolution,
                    leidenTheta: ActivityTagOntologyDefaults.leidenTheta,
                    continuityAlpha: ActivityTagOntologyDefaults.continuityAlpha,
                    continuityBeta: ActivityTagOntologyDefaults.continuityBeta,
                    continuityGamma: ActivityTagOntologyDefaults.continuityGamma
                ),
                tags: []
            )
            let snapshot = try await activityDatabaseActor.loadActivityTagOntologyRefreshSnapshot()

            #expect(snapshot.latestRun?.id == 802)
        }
    }

    @Test("applying an ontology embedding without a run still persists the summary vector")
    func applyingAnOntologyEmbeddingWithoutARunStillPersistsTheSummaryVector() async throws {
        try await withDatabase { database, _ in
            let activityDatabaseActor = ActivityDatabaseActor(database: database)

            try await database.saveActivityRecord(ActivityInput(
                id: 398,
                startTime: today(),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Persist the embedding even before an ontology exists.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            let assignment = try await activityDatabaseActor.applyActivitySummaryEmbeddingToOntology(
                activityID: 398,
                vector: activityEmbedding(activatedDimension: 0)
            )
            let activity: ActivityRecord? = switch try await database.get(.activity(.id(398))) {
            case let .activity(activity):
                activity
            default:
                nil
            }

            #expect((assignment == nil, activity?.summaryVector != nil) == (true, true))
        }
    }

    @Test("loading the ontology catch-up snapshot returns current-day activities missing embeddings")
    func loadingTheOntologyCatchUpSnapshotReturnsCurrentDayActivitiesMissingEmbeddings() async throws {
        try await withDatabase { database, _ in
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            let day = localDate(dayOffset: 0, hour: 9)

            try await database.saveActivityRecord(ActivityInput(
                id: 901,
                startTime: day,
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Needs an embedding on startup.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            let snapshot = try await activityDatabaseActor.loadActivityOntologyCatchUpSnapshot(day: day)

            #expect(snapshot.activitiesMissingEmbeddings.map(\.id) == [901])
        }
    }

    @Test("loading the ontology catch-up snapshot returns current-day activity ids missing tags")
    func loadingTheOntologyCatchUpSnapshotReturnsCurrentDayActivityIDsMissingTags() async throws {
        try await withDatabase { database, _ in
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            let day = localDate(dayOffset: 0, hour: 10)

            try await database.saveActivityRecord(ActivityInput(
                id: 902,
                startTime: day,
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Embedded but untagged.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await activityDatabaseActor.persistActivitySummaryVector(
                activityID: 902,
                vector: activityEmbedding(activatedDimension: 0)
            )
            let snapshot = try await activityDatabaseActor.loadActivityOntologyCatchUpSnapshot(day: day)

            #expect(snapshot.activityIDsMissingTags == [902])
        }
    }

    @Test("loading the ontology catch-up snapshot returns current-day activity ids missing overviews")
    func loadingTheOntologyCatchUpSnapshotReturnsCurrentDayActivityIDsMissingOverviews() async throws {
        try await withDatabase { database, _ in
            let activityDatabaseActor = ActivityDatabaseActor(database: database)
            let day = localDate(dayOffset: 0, hour: 11)

            try await database.save(.tag(.record(TagInput(
                id: 903,
                name: "Startup Tag",
                description: "Needs an overview",
                createDate: day,
                deleteDate: nil,
                jsonProperties: nil
            ))))
            try await database.saveActivityRecord(ActivityInput(
                id: 903,
                startTime: day,
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Tagged but not overviewed.",
                tagID: 903,
                jsonProperties: nil,
                overviewID: nil
            ))
            let snapshot = try await activityDatabaseActor.loadActivityOntologyCatchUpSnapshot(day: day)

            #expect(snapshot.activityIDsMissingOverviews == [903])
        }
    }

    @Test("applying an ontology embedding upserts a canonical edge to the nearest neighbor")
    func applyingAnOntologyEmbeddingUpsertsACanonicalEdgeToTheNearestNeighbor() async throws {
        try await withDatabase { database, _ in
            let activityDatabaseActor = ActivityDatabaseActor(database: database)

            try await database.saveActivityRecord(ActivityInput(
                id: 401,
                startTime: today(),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Seed ontology member.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 402,
                startTime: today(),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Related activity to connect.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await activityDatabaseActor.persistActivitySummaryVector(
                activityID: 401,
                vector: activityEmbedding(activatedDimension: 0)
            )
            _ = try await activityDatabaseActor.applyActivitySummaryEmbeddingToOntology(
                activityID: 402,
                vector: activityEmbedding(activatedDimension: 0)
            )

            let edgePairs = try database.vectorAwareRead { db in
                try ActivityEdgeRecord.fetchAll(
                    db,
                    sql: """
                        SELECT *
                        FROM activity_edges
                        ORDER BY first_activity_id ASC, second_activity_id ASC
                        """
                )
                .map {
                    ActivityEdgePair(
                        firstActivityID: $0.firstActivityID,
                        secondActivityID: $0.secondActivityID
                    )
                }
            }

            #expect(edgePairs == [ActivityEdgePair(firstActivityID: 401, secondActivityID: 402)])
        }
    }

    @Test("applying an ontology embedding falls back to the nearest candidate centroid")
    func applyingAnOntologyEmbeddingFallsBackToTheNearestCandidateCentroid() async throws {
        try await withDatabase { database, _ in
            let activityDatabaseActor = ActivityDatabaseActor(database: database)

            for (activityID, dimension) in [
                (410 as Int64, 2),
                (420 as Int64, 1),
                (421 as Int64, 2)
            ] {
                try await database.saveActivityRecord(ActivityInput(
                    id: activityID,
                    startTime: today(),
                    application: "Xcode",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "Ontology centroid fallback seed \(activityID).",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: nil
                ))
                try await activityDatabaseActor.persistActivitySummaryVector(
                    activityID: activityID,
                    vector: activityEmbedding(activatedDimension: dimension)
                )
            }
            try await activityDatabaseActor.publishActivityTagOntologyRun(
                ActivityTagOntologyRunInput(
                    runID: 630,
                    createdAt: Date(timeIntervalSince1970: 1_765_000_000),
                    previousRunID: nil,
                    candidates: [
                        ActivityTagOntologyCandidateInput(
                            candidateID: 631,
                            tagID: 720,
                            predecessorCandidateID: nil,
                            name: "First Cluster",
                            summary: "First ontology-generated cluster",
                            centroidVector: activityEmbedding(activatedDimension: 1).withUnsafeBytes { Data($0) },
                            memberActivityIDs: [420],
                            centralityScoreByActivityID: [420: 1],
                            memberOverlap: nil,
                            centroidSimilarity: nil,
                            continuitySimilarity: nil
                        ),
                        ActivityTagOntologyCandidateInput(
                            candidateID: 632,
                            tagID: 721,
                            predecessorCandidateID: nil,
                            name: "Second Cluster",
                            summary: "Second ontology-generated cluster",
                            centroidVector: activityEmbedding(activatedDimension: 2).withUnsafeBytes { Data($0) },
                            memberActivityIDs: [421],
                            centralityScoreByActivityID: [421: 1],
                            memberOverlap: nil,
                            centroidSimilarity: nil,
                            continuitySimilarity: nil
                        )
                    ],
                    kNeighbors: ActivityTagOntologyDefaults.neighborCount,
                    leidenResolution: ActivityTagOntologyDefaults.leidenResolution,
                    leidenTheta: ActivityTagOntologyDefaults.leidenTheta,
                    continuityAlpha: ActivityTagOntologyDefaults.continuityAlpha,
                    continuityBeta: ActivityTagOntologyDefaults.continuityBeta,
                    continuityGamma: ActivityTagOntologyDefaults.continuityGamma
                ),
                tags: [
                    TagInput(
                        id: 720,
                        name: "First Cluster",
                        description: "First ontology-generated cluster",
                        createDate: Date(timeIntervalSince1970: 1_765_000_000),
                        deleteDate: nil,
                        jsonProperties: nil,
                        originKind: TagOriginKind.ontology.rawValue,
                        generatedName: "First Cluster",
                        generatedDescription: "First ontology-generated cluster",
                        nameIsUserEdited: false,
                        descriptionIsUserEdited: false
                    ),
                    TagInput(
                        id: 721,
                        name: "Second Cluster",
                        description: "Second ontology-generated cluster",
                        createDate: Date(timeIntervalSince1970: 1_765_000_000),
                        deleteDate: nil,
                        jsonProperties: nil,
                        originKind: TagOriginKind.ontology.rawValue,
                        generatedName: "Second Cluster",
                        generatedDescription: "Second ontology-generated cluster",
                        nameIsUserEdited: false,
                        descriptionIsUserEdited: false
                    )
                ]
            )
            try await database.saveActivityRecord(ActivityInput(
                id: 430,
                startTime: today(),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "New activity should pick the matching centroid.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            let assignment = try await activityDatabaseActor.applyActivitySummaryEmbeddingToOntology(
                activityID: 430,
                vector: activityEmbedding(activatedDimension: 2),
                k: 1
            )

            #expect(assignment?.tagID == 721)
        }
    }

    @Test("applying latest ontology assignments tags embedded activities")
    func applyingLatestOntologyAssignmentsTagsEmbeddedActivities() async throws {
        try await withDatabase { database, _ in
            let activityDatabaseActor = ActivityDatabaseActor(database: database)

            for (activityID, dimension) in [
                (440 as Int64, 2),
                (450 as Int64, 1),
                (451 as Int64, 2),
                (460 as Int64, 2)
            ] {
                try await database.saveActivityRecord(ActivityInput(
                    id: activityID,
                    startTime: today(),
                    application: "Xcode",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "Batch ontology fallback seed \(activityID).",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: nil
                ))
                try await activityDatabaseActor.persistActivitySummaryVector(
                    activityID: activityID,
                    vector: activityEmbedding(activatedDimension: dimension)
                )
            }
            try await activityDatabaseActor.publishActivityTagOntologyRun(
                ActivityTagOntologyRunInput(
                    runID: 640,
                    createdAt: Date(timeIntervalSince1970: 1_765_000_000),
                    previousRunID: nil,
                    candidates: [
                        ActivityTagOntologyCandidateInput(
                            candidateID: 641,
                            tagID: 730,
                            predecessorCandidateID: nil,
                            name: "First Batch Cluster",
                            summary: "First batch ontology-generated cluster",
                            centroidVector: activityEmbedding(activatedDimension: 1).withUnsafeBytes { Data($0) },
                            memberActivityIDs: [450],
                            centralityScoreByActivityID: [450: 1],
                            memberOverlap: nil,
                            centroidSimilarity: nil,
                            continuitySimilarity: nil
                        ),
                        ActivityTagOntologyCandidateInput(
                            candidateID: 642,
                            tagID: 731,
                            predecessorCandidateID: nil,
                            name: "Second Batch Cluster",
                            summary: "Second batch ontology-generated cluster",
                            centroidVector: activityEmbedding(activatedDimension: 2).withUnsafeBytes { Data($0) },
                            memberActivityIDs: [451],
                            centralityScoreByActivityID: [451: 1],
                            memberOverlap: nil,
                            centroidSimilarity: nil,
                            continuitySimilarity: nil
                        )
                    ],
                    kNeighbors: ActivityTagOntologyDefaults.neighborCount,
                    leidenResolution: ActivityTagOntologyDefaults.leidenResolution,
                    leidenTheta: ActivityTagOntologyDefaults.leidenTheta,
                    continuityAlpha: ActivityTagOntologyDefaults.continuityAlpha,
                    continuityBeta: ActivityTagOntologyDefaults.continuityBeta,
                    continuityGamma: ActivityTagOntologyDefaults.continuityGamma
                ),
                tags: [
                    TagInput(
                        id: 730,
                        name: "First Batch Cluster",
                        description: "First batch ontology-generated cluster",
                        createDate: Date(timeIntervalSince1970: 1_765_000_000),
                        deleteDate: nil,
                        jsonProperties: nil,
                        originKind: TagOriginKind.ontology.rawValue,
                        generatedName: "First Batch Cluster",
                        generatedDescription: "First batch ontology-generated cluster",
                        nameIsUserEdited: false,
                        descriptionIsUserEdited: false
                    ),
                    TagInput(
                        id: 731,
                        name: "Second Batch Cluster",
                        description: "Second batch ontology-generated cluster",
                        createDate: Date(timeIntervalSince1970: 1_765_000_000),
                        deleteDate: nil,
                        jsonProperties: nil,
                        originKind: TagOriginKind.ontology.rawValue,
                        generatedName: "Second Batch Cluster",
                        generatedDescription: "Second batch ontology-generated cluster",
                        nameIsUserEdited: false,
                        descriptionIsUserEdited: false
                    )
                ]
            )
            let assignments = try await activityDatabaseActor.applyLatestOntologyAssignments(
                activityIDs: [460],
                k: 1
            )

            #expect(assignments.map(\.tagID) == [731])
        }
    }

    @Test("applying an ontology embedding preserves a manual tag")
    func applyingAnOntologyEmbeddingPreservesAManualTag() async throws {
        try await withDatabase { database, _ in
            let activityDatabaseActor = ActivityDatabaseActor(database: database)

            try await database.saveActivityRecord(ActivityInput(
                id: 411,
                startTime: today(),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Ontology seed activity.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 412,
                startTime: today(),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Manual tag should win.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await activityDatabaseActor.persistActivitySummaryVector(
                activityID: 411,
                vector: activityEmbedding(activatedDimension: 0)
            )
            try await activityDatabaseActor.publishActivityTagOntologyRun(
                ActivityTagOntologyRunInput(
                    runID: 610,
                    createdAt: Date(timeIntervalSince1970: 1_765_000_000),
                    previousRunID: nil,
                    candidates: [
                        ActivityTagOntologyCandidateInput(
                            candidateID: 611,
                            tagID: 700,
                            predecessorCandidateID: nil,
                            name: "Ontology Cluster",
                            summary: "Ontology-generated cluster",
                            centroidVector: activityEmbedding(activatedDimension: 0).withUnsafeBytes { Data($0) },
                            memberActivityIDs: [411],
                            centralityScoreByActivityID: [411: 1],
                            memberOverlap: nil,
                            centroidSimilarity: nil,
                            continuitySimilarity: nil
                        )
                    ],
                    kNeighbors: ActivityTagOntologyDefaults.neighborCount,
                    leidenResolution: ActivityTagOntologyDefaults.leidenResolution,
                    leidenTheta: ActivityTagOntologyDefaults.leidenTheta,
                    continuityAlpha: ActivityTagOntologyDefaults.continuityAlpha,
                    continuityBeta: ActivityTagOntologyDefaults.continuityBeta,
                    continuityGamma: ActivityTagOntologyDefaults.continuityGamma
                ),
                tags: [
                    TagInput(
                        id: 700,
                        name: "Ontology Cluster",
                        description: "Ontology-generated cluster",
                        createDate: Date(timeIntervalSince1970: 1_765_000_000),
                        deleteDate: nil,
                        jsonProperties: nil,
                        originKind: TagOriginKind.ontology.rawValue,
                        generatedName: "Ontology Cluster",
                        generatedDescription: "Ontology-generated cluster",
                        nameIsUserEdited: false,
                        descriptionIsUserEdited: false
                    )
                ]
            )
            try await database.save(.tag(.record(TagInput(
                id: 900,
                name: "Manual Tag",
                description: "Manual description",
                createDate: Date(timeIntervalSince1970: 1_765_000_001),
                deleteDate: nil,
                jsonProperties: nil
            ))))
            await activityDatabaseActor.receive(Envelope(
                sender: nil,
                message: ActivityTagSet(
                    activityID: 412,
                    tagID: 900
                )
            ))
            _ = try await activityDatabaseActor.applyActivitySummaryEmbeddingToOntology(
                activityID: 412,
                vector: activityEmbedding(activatedDimension: 0)
            )

            let tagID: Int64? = switch try await database.get(.activity(.id(412))) {
            case let .activity(activity):
                activity?.tagID
            default:
                nil
            }

            #expect(tagID == 900)
        }
    }

    @Test("updating an activity summary clears incident ontology edges")
    func updatingAnActivitySummaryClearsIncidentOntologyEdges() async throws {
        try await withDatabase { database, _ in
            let activityDatabaseActor = ActivityDatabaseActor(database: database)

            try await database.saveActivityRecord(ActivityInput(
                id: 421,
                startTime: today(),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Seed ontology member.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 422,
                startTime: today(),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Activity whose summary will change.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await activityDatabaseActor.persistActivitySummaryVector(
                activityID: 421,
                vector: activityEmbedding(activatedDimension: 0)
            )
            _ = try await activityDatabaseActor.applyActivitySummaryEmbeddingToOntology(
                activityID: 422,
                vector: activityEmbedding(activatedDimension: 0)
            )
            await activityDatabaseActor.receive(Envelope(
                sender: nil,
                message: ActivitySummarized(
                    activity: ActivityActor.Activity(
                        id: 422,
                        application: "Safari",
                        startTime: today(),
                        keystrokes: "",
                        microphone: "",
                        summary: "Changed summary",
                        overviewID: nil,
                        tagID: nil,
                        screenshots: []
                    )
                )
            ))

            let edgeCount = try database.vectorAwareRead { db in
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*)
                        FROM activity_edges
                        WHERE first_activity_id = ?
                          AND second_activity_id = ?
                        """,
                    arguments: [421, 422]
                ) ?? 0
            }

            #expect(edgeCount == 0)
        }
    }

    @Test("updating an ontology assigned summary clears the visible ontology tag")
    func updatingAnOntologyAssignedSummaryClearsTheVisibleOntologyTag() async throws {
        try await withDatabase { database, _ in
            let activityDatabaseActor = ActivityDatabaseActor(database: database)

            try await database.saveActivityRecord(ActivityInput(
                id: 431,
                startTime: today(),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Ontology seed activity.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 432,
                startTime: today(),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Ontology-assigned activity.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await activityDatabaseActor.persistActivitySummaryVector(
                activityID: 431,
                vector: activityEmbedding(activatedDimension: 0)
            )
            try await activityDatabaseActor.publishActivityTagOntologyRun(
                ActivityTagOntologyRunInput(
                    runID: 620,
                    createdAt: Date(timeIntervalSince1970: 1_765_000_000),
                    previousRunID: nil,
                    candidates: [
                        ActivityTagOntologyCandidateInput(
                            candidateID: 621,
                            tagID: 710,
                            predecessorCandidateID: nil,
                            name: "Ontology Cluster",
                            summary: "Ontology-generated cluster",
                            centroidVector: activityEmbedding(activatedDimension: 0).withUnsafeBytes { Data($0) },
                            memberActivityIDs: [431],
                            centralityScoreByActivityID: [431: 1],
                            memberOverlap: nil,
                            centroidSimilarity: nil,
                            continuitySimilarity: nil
                        )
                    ],
                    kNeighbors: ActivityTagOntologyDefaults.neighborCount,
                    leidenResolution: ActivityTagOntologyDefaults.leidenResolution,
                    leidenTheta: ActivityTagOntologyDefaults.leidenTheta,
                    continuityAlpha: ActivityTagOntologyDefaults.continuityAlpha,
                    continuityBeta: ActivityTagOntologyDefaults.continuityBeta,
                    continuityGamma: ActivityTagOntologyDefaults.continuityGamma
                ),
                tags: [
                    TagInput(
                        id: 710,
                        name: "Ontology Cluster",
                        description: "Ontology-generated cluster",
                        createDate: Date(timeIntervalSince1970: 1_765_000_000),
                        deleteDate: nil,
                        jsonProperties: nil,
                        originKind: TagOriginKind.ontology.rawValue,
                        generatedName: "Ontology Cluster",
                        generatedDescription: "Ontology-generated cluster",
                        nameIsUserEdited: false,
                        descriptionIsUserEdited: false
                    )
                ]
            )
            _ = try await activityDatabaseActor.applyActivitySummaryEmbeddingToOntology(
                activityID: 432,
                vector: activityEmbedding(activatedDimension: 0)
            )
            await activityDatabaseActor.receive(Envelope(
                sender: nil,
                message: ActivitySummarized(
                    activity: ActivityActor.Activity(
                        id: 432,
                        application: "Safari",
                        startTime: today(),
                        keystrokes: "",
                        microphone: "",
                        summary: "Changed summary",
                        overviewID: nil,
                        tagID: nil,
                        screenshots: []
                    )
                )
            ))

            let tagTuple: (Int64?, String?, Int64?) = switch try await database.get(.activity(.id(432))) {
            case let .activity(activity):
                (activity?.tagID, activity?.tagAssignmentSource, activity?.ontologyCandidateID)
            default:
                (nil, nil, nil)
            }

            #expect(tagTuple == (nil, nil, nil))
        }
    }

    @Test("ensuring ontology overview assignment assigns the tagged activity to the created overview")
    func ensuringOntologyOverviewAssignmentAssignsTheTaggedActivityToTheCreatedOverview() async throws {
        try await withDatabase { database, _ in
            let overviewDatabaseActor = OverviewDatabaseActor(database: database)
            let day = localDate(dayOffset: 0, hour: 9)
            try await database.save(.tag(.record(TagInput(
                id: 55,
                name: "Tag 55",
                description: "Test tag 55",
                createDate: Date(timeIntervalSince1970: 1_765_000_000),
                deleteDate: nil,
                jsonProperties: nil
            ))))

            try await database.saveActivityRecord(ActivityInput(
                id: 501,
                startTime: day,
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Worked on the current feature.",
                tagID: 55,
                jsonProperties: nil,
                overviewID: nil
            ))

            let summaryKey = try await overviewDatabaseActor.ensureOntologyOverviewAssignment(
                key: OntologyOverviewRefreshKey(
                    day: Calendar(identifier: .gregorian).startOfDay(for: day),
                    tagID: 55
                ),
                newOverviewID: 990
            )

            let assignment = try database.read { db in
                try Row.fetchOne(
                    db,
                    sql: """
                        SELECT overview_id, overview_assignment_source
                        FROM activities
                        WHERE id = ?
                        """,
                    arguments: [501]
                )
            }
            .map { row in
                (
                    row["overview_id"] as Int64?,
                    row["overview_assignment_source"] as String?
                )
            } ?? (
                -1,
                nil
            )

            let expectedAssignment: (Int64?, String?) = (
                990,
                OverviewAssignmentSource.ontology.rawValue
            )
            #expect(summaryKey == OntologyOverviewSummaryKey(
                day: Calendar(identifier: .gregorian).startOfDay(for: day),
                overviewID: 990
            ) && assignment == expectedAssignment)
        }
    }

    @Test("ensuring ontology overview assignment writes the day tag binding")
    func ensuringOntologyOverviewAssignmentWritesTheDayTagBinding() async throws {
        try await withDatabase { database, _ in
            let overviewDatabaseActor = OverviewDatabaseActor(database: database)
            let day = localDate(dayOffset: 0, hour: 9)
            try await database.save(.tag(.record(TagInput(
                id: 56,
                name: "Tag 56",
                description: "Test tag 56",
                createDate: Date(timeIntervalSince1970: 1_765_000_000),
                deleteDate: nil,
                jsonProperties: nil
            ))))

            try await database.saveActivityRecord(ActivityInput(
                id: 502,
                startTime: day,
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Worked on the current feature.",
                tagID: 56,
                jsonProperties: nil,
                overviewID: nil
            ))

            _ = try await overviewDatabaseActor.ensureOntologyOverviewAssignment(
                key: OntologyOverviewRefreshKey(
                    day: Calendar(identifier: .gregorian).startOfDay(for: day),
                    tagID: 56
                ),
                newOverviewID: 991
            )

            let binding = try database.read { db in
                try Row.fetchOne(
                    db,
                    sql: """
                        SELECT overview_id, binding_source
                        FROM overview_day_tag_bindings
                        WHERE day_start = DATE(?)
                          AND tag_id = ?
                        """,
                    arguments: [
                        Calendar(identifier: .gregorian)
                            .startOfDay(for: day)
                            .formatted(TaskTraceDatabase.sqlDateStyle),
                        56
                    ]
                )
            }
            .map { row in
                (
                    row["overview_id"] as Int64?,
                    row["binding_source"] as String?
                )
            } ?? (
                -1,
                nil
            )

            let expectedBinding: (Int64?, String?) = (
                991,
                OverviewBindingSource.auto.rawValue
            )
            #expect(binding == expectedBinding)
        }
    }

    @Test("applying ontology overview generated text preserves user edited visible text")
    func applyingOntologyOverviewGeneratedTextPreservesUserEditedVisibleText() async throws {
        try await withDatabase { database, _ in
            let overviewDatabaseActor = OverviewDatabaseActor(database: database)
            let day = localDate(dayOffset: 0, hour: 9)
            try await database.save(.tag(.record(TagInput(
                id: 57,
                name: "Tag 57",
                description: "Test tag 57",
                createDate: Date(timeIntervalSince1970: 1_765_000_000),
                deleteDate: nil,
                jsonProperties: nil
            ))))

            try await database.saveActivityRecord(ActivityInput(
                id: 503,
                startTime: day,
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Worked on the current feature.",
                tagID: 57,
                jsonProperties: nil,
                overviewID: nil
            ))

            _ = try await overviewDatabaseActor.ensureOntologyOverviewAssignment(
                key: OntologyOverviewRefreshKey(
                    day: Calendar(identifier: .gregorian).startOfDay(for: day),
                    tagID: 57
                ),
                newOverviewID: 992
            )
            try await overviewDatabaseActor.applyOntologyOverviewGeneratedText(
                overviewID: 992,
                generatedTitle: "Generated Title 1",
                generatedSummary: "Generated summary 1."
            )

            try database.write { db in
                try db.execute(
                    sql: """
                        UPDATE overviews
                        SET
                            title = ?,
                            summary = ?,
                            title_is_user_edited = 1,
                            summary_is_user_edited = 1
                        WHERE id = ?
                        """,
                    arguments: [
                        "User Title",
                        "User Summary",
                        992
                    ]
                )
            }

            try await overviewDatabaseActor.applyOntologyOverviewGeneratedText(
                overviewID: 992,
                generatedTitle: "Generated Title 2",
                generatedSummary: "Generated summary 2."
            )

            let textTuple = try database.read { db in
                try Row.fetchOne(
                    db,
                    sql: """
                        SELECT
                            title,
                            summary,
                            generated_title,
                            generated_summary,
                            title_is_user_edited,
                            summary_is_user_edited
                        FROM overviews
                        WHERE id = ?
                        """,
                    arguments: [992]
                )
            }
            .map { row in
                (
                    row["title"] as String?,
                    row["summary"] as String?,
                    row["generated_title"] as String?,
                    row["generated_summary"] as String?,
                    row["title_is_user_edited"] as Int?,
                    row["summary_is_user_edited"] as Int?
                )
            } ?? (
                nil,
                nil,
                nil,
                nil,
                nil,
                nil
            )

            let expectedTextTuple: (String?, String?, String?, String?, Int?, Int?) = (
                "User Title",
                "User Summary",
                "Generated Title 2",
                "Generated summary 2.",
                1,
                1
            )
            #expect(textTuple == expectedTextTuple)
        }
    }

    @Test("summary snapshots include chronological linked activities for the resolved overview")
    func summarySnapshotsIncludeChronologicalLinkedActivitiesForTheResolvedOverview() async throws {
        try await withDatabase { database, _ in
            let overviewDatabaseActor = OverviewDatabaseActor(database: database)
            let day = localDate(dayOffset: 0, hour: 9)
            let startOfDay = Calendar(identifier: .gregorian).startOfDay(for: day)
            try await database.save(.tag(.record(TagInput(
                id: 55,
                name: "Tag 55",
                description: "Test tag 55",
                createDate: Date(timeIntervalSince1970: 1_765_000_000),
                deleteDate: nil,
                jsonProperties: nil
            ))))
            try await database.save(.tag(.record(TagInput(
                id: 77,
                name: "Tag 77",
                description: "Test tag 77",
                createDate: Date(timeIntervalSince1970: 1_765_000_000),
                deleteDate: nil,
                jsonProperties: nil
            ))))

            try await database.saveOverviewRecord(OverviewInput(
                id: 993,
                title: "Merged manual overview",
                summary: "Manual overview",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: 55,
                originKind: OverviewOriginKind.manual.rawValue
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 504,
                startTime: day,
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Tag 55 activity.",
                tagID: 55,
                jsonProperties: nil,
                overviewID: 993
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 505,
                startTime: localDate(dayOffset: 0, hour: 10),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Tag 77 activity.",
                tagID: 77,
                jsonProperties: nil,
                overviewID: 993
            ))

            try database.write { db in
                try db.execute(
                    sql: """
                        UPDATE activities
                        SET overview_assignment_source = ?
                        WHERE id IN (?, ?)
                        """,
                    arguments: [
                        OverviewAssignmentSource.manual.rawValue,
                        504,
                        505
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO overview_day_tag_bindings (
                            day_start,
                            tag_id,
                            overview_id,
                            binding_source
                        )
                        VALUES (DATE(?), ?, ?, ?)
                        """,
                    arguments: [
                        startOfDay.formatted(TaskTraceDatabase.sqlDateStyle),
                        55,
                        993,
                        OverviewBindingSource.manual.rawValue
                    ]
                )
            }

            let summaryKey = try #require(
                try await overviewDatabaseActor.ensureOntologyOverviewAssignment(
                    key: OntologyOverviewRefreshKey(day: startOfDay, tagID: 55),
                    newOverviewID: 993
                )
            )
            let snapshot = try await overviewDatabaseActor.loadOntologyOverviewSummarySnapshot(
                key: summaryKey
            )

            #expect(
                snapshot.activityIDs == [504, 505]
                    && snapshot.activities.map(\.id) == [504, 505]
            )
        }
    }

    @Test("database initialization seeds the built in tags")
    func initializationSeedsTheBuiltInTags() async throws {
        try await withDatabase { database, _ in
            let tags: [Int64] = switch try await database.get(.tag(.all)) {
            case let .tags(value):
                value.map(\.id)
            default:
                []
            }
            #expect(tags == [SystemTags.inactiveID, SystemTags.taggingFailureID])
        }
    }

    @Test("saved agent actions are readable from the agent actions table")
    func savedAgentActionsAreReadable() async throws {
        try await withDatabase { database, _ in
            try await database.save(.agentAction(.record(AgentActionInput(
                id: 101,
                instructions: "Handle summarized activities.",
                eventType: .activitySummarized,
                conversationID: "conversation-101"
            ))))

            let agentActions: [AgentActionRecord] = switch try await database.get(.agentAction(.all)) {
            case let .agentActions(value):
                value
            default:
                []
            }

            #expect(agentActions.map(\.conversationID) == ["conversation-101"])
        }
    }

    @Test("saved agent actions preserve their event type")
    func savedAgentActionsPreserveTheirEventType() async throws {
        try await withDatabase { database, _ in
            try await database.save(.agentAction(.record(AgentActionInput(
                id: 101,
                instructions: "Handle summarized activities.",
                eventType: .activitySummarized,
                conversationID: "conversation-101"
            ))))

            let agentActions: [AgentActionRecord] = switch try await database.get(.agentAction(.all)) {
            case let .agentActions(value):
                value
            default:
                []
            }

            #expect(agentActions.map(\.eventType) == [.activitySummarized])
        }
    }

    @Test("setting writes are readable through the settings table")
    func settingWritesAreReadable() async throws {
        try await withDatabase { database, _ in
            try await database.setSetting(named: "apiKey", value: "value")
            let setting = try await database.getSetting(named: "apiKey")
            #expect(setting == "value")
        }
    }

    @Test("setting writes tolerate a brief external sqlite write lock")
    func settingWritesTolerateABriefExternalSQLiteWriteLock() async throws {
        try await withDatabase { database, databaseURL in
            let releaseLock = DispatchSemaphore(value: 0)
            let externalQueue = try DatabaseQueue(path: databaseURL.path)
            var lockTask: Task<Void, Error>?
            let lockAcquired = AsyncStream<Void> { continuation in
                lockTask = Task.detached {
                    try externalQueue.inDatabase { db in
                        try db.execute(sql: "BEGIN EXCLUSIVE TRANSACTION")
                        continuation.yield()
                        continuation.finish()
                        releaseLock.wait()
                        try db.execute(sql: "COMMIT")
                    }
                }
            }

            for await _ in lockAcquired {
                break
            }

            let writeTask = Task.detached {
                try await database.setSetting(named: "apiKey", value: "value")
            }

            try await Task.sleep(for: .milliseconds(200))
            releaseLock.signal()
            try await writeTask.value
            try await lockTask?.value

            let setting = try await database.getSetting(named: "apiKey")
            #expect(setting == "value")
        }
    }

    @Test("saved screenshots are nested under their activity when loading a day")
    func savedScreenshotsLoadUnderActivity() async throws {
        try await withDatabase { database, _ in
            let image = Data("img".utf8)
            let overview = OverviewInput(
                id: 200,
                title: "Overview",
                summary: "Summary",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: 0
            )
            let activity = ActivityInput(
                id: 100,
                startTime: localDate(dayOffset: 0, hour: 12),
                application: "Xcode",
                keystrokes: "abc",
                microphone: "meeting notes",
                summary: "activity",
                tagID: 0,
                jsonProperties: nil,
                overviewID: 200
            )
            let screenshot = ScreenshotInput(
                id: 101,
                image: image,
                timestamp: localDate(dayOffset: 0, hour: 12, minute: 5),
                description: "desc",
                text: "ocr",
                ignoreReason: nil,
                jsonProperties: nil
            )

            try await database.saveOverviewRecord(overview)
            try await database.saveActivityRecord(activity)
            try await database.saveScreenshotRecord(activityID: 100, screenshot: screenshot)

            let state = try await database.loadState(for: today())
            let screenshotIDs = await MainActor.run { state.activity.first?.screenshots.map(\.id) }
            #expect(screenshotIDs == [101])
        }
    }

    @Test("saving a summarized activity leaves the summary vector empty until embedding is written")
    func savingASummarizedActivityLeavesTheSummaryVectorEmptyUntilEmbeddingIsWritten() async throws {
        try await withDatabase { database, _ in
            try await database.saveActivityRecord(ActivityInput(
                id: 1,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Xcode",
                keystrokes: "abc",
                microphone: nil,
                summary: "Implemented activity vector storage.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            let summaryVector: Data? = switch try await database.get(.activity(.id(1))) {
            case let .activity(activity):
                activity?.summaryVector
            default:
                nil
            }

            #expect(summaryVector == nil)
        }
    }

    @Test("saving an activity without a summary leaves the summary vector empty")
    func savingAnActivityWithoutASummaryLeavesTheSummaryVectorEmpty() async throws {
        try await withDatabase { database, _ in
            try await database.saveActivityRecord(ActivityInput(
                id: 1,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Xcode",
                keystrokes: "abc",
                microphone: nil,
                summary: nil,
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            let summaryVector: Data? = switch try await database.get(.activity(.id(1))) {
            case let .activity(activity):
                activity?.summaryVector
            default:
                nil
            }

            #expect(summaryVector == nil)
        }
    }

    @Test("saving a described screenshot leaves the description vector empty until embedding is written")
    func savingADescribedScreenshotLeavesTheDescriptionVectorEmptyUntilEmbeddingIsWritten() async throws {
        try await withDatabase { database, _ in
            try await database.saveActivityRecord(ActivityInput(
                id: 1,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: nil,
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            try await database.saveScreenshotRecord(
                activityID: 1,
                screenshot: ScreenshotInput(
                    id: 10,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9),
                    description: "Invoice approval modal",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            let descriptionVector: Data? = switch try await database.get(.screenshot(.id(10))) {
            case let .screenshot(screenshot):
                screenshot?.descriptionVector
            default:
                nil
            }

            #expect(descriptionVector == nil)
        }
    }

    @Test("saving a screenshot without a description leaves the description vector empty")
    func savingAScreenshotWithoutADescriptionLeavesTheDescriptionVectorEmpty() async throws {
        try await withDatabase { database, _ in
            try await database.saveActivityRecord(ActivityInput(
                id: 1,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: nil,
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            try await database.saveScreenshotRecord(
                activityID: 1,
                screenshot: ScreenshotInput(
                    id: 10,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9),
                    description: nil,
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            let descriptionVector: Data? = switch try await database.get(.screenshot(.id(10))) {
            case let .screenshot(screenshot):
                screenshot?.descriptionVector
            default:
                nil
            }

            #expect(descriptionVector == nil)
        }
    }

    @Test("saving a summarized overview leaves the summary vector empty until embedding is written")
    func savingASummarizedOverviewLeavesTheSummaryVectorEmptyUntilEmbeddingIsWritten() async throws {
        try await withDatabase { database, _ in
            try await database.saveOverviewRecord(OverviewInput(
                id: 7,
                title: "Billing work",
                summary: "Retrospective for the March billing export incident.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))

            let summaryVector: Data? = switch try await database.get(.overview(.id(7))) {
            case let .overview(overview):
                overview?.summaryVector
            default:
                nil
            }

            #expect(summaryVector == nil)
        }
    }

    @Test("saving an overview without a summary leaves the summary vector empty")
    func savingAnOverviewWithoutASummaryLeavesTheSummaryVectorEmpty() async throws {
        try await withDatabase { database, _ in
            try await database.saveOverviewRecord(OverviewInput(
                id: 7,
                title: "Billing work",
                summary: nil,
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))

            let summaryVector: Data? = switch try await database.get(.overview(.id(7))) {
            case let .overview(overview):
                overview?.summaryVector
            default:
                nil
            }

            #expect(summaryVector == nil)
        }
    }

    @Test("loading a day with no activity returns an empty activity list")
    func loadingADayWithNoActivityReturnsAnEmptyActivityList() async throws {
        try await withDatabase { database, _ in
            let state = try await database.loadState(for: today())
            let isEmpty = await MainActor.run { state.activity.isEmpty }
            #expect(isEmpty)
        }
    }

    @Test("activity full text search matches summary text")
    func activityFullTextSearchMatchesSummaryText() async throws {
        try await withDatabase { database, _ in
            try await database.saveActivityRecord(ActivityInput(
                id: 1,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Xcode",
                keystrokes: "fts migration",
                microphone: nil,
                summary: "Implemented billing export search indexing.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            let matches = try database.searchActivities(matching: "billing")
            #expect(matches.map(\.id) == [1])
        }
    }

    @Test("activity full text search uses porter stemming")
    func activityFullTextSearchUsesPorterStemming() async throws {
        try await withDatabase { database, _ in
            try await database.saveActivityRecord(ActivityInput(
                id: 1,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Xcode",
                keystrokes: "corrected parser",
                microphone: nil,
                summary: "The user corrected the billing export parser.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            let matches = try database.searchActivities(matching: "correction")
            #expect(matches.map(\.id) == [1])
        }
    }

    @Test("database initialization configures activity fts with porter ascii")
    func initializationConfiguresActivityFTSWithPorterASCII() async throws {
        try await withDatabase { _, databaseURL in
            let queue = try DatabaseQueue(path: databaseURL.path)
            let sql = try queue.read { db in
                try String.fetchOne(
                    db,
                    sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'activity_fts'"
                )
            }
            #expect((sql?.contains("porter") == true) && (sql?.contains("ascii") == true))
        }
    }

    @Test("activity full text search reflects updated activity text")
    func activityFullTextSearchReflectsUpdatedActivityText() async throws {
        try await withDatabase { database, _ in
            try await database.saveActivityRecord(ActivityInput(
                id: 1,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Xcode",
                keystrokes: "fts migration",
                microphone: nil,
                summary: "Implemented billing export search indexing.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            try await database.saveActivityRecord(ActivityInput(
                id: 1,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Xcode",
                keystrokes: "overview matching",
                microphone: nil,
                summary: "Refined overview assignment retries.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))

            let matches = try await database.searchActivities(matching: "overview")
            #expect(matches.map(\.id) == [1])
        }
    }

    @Test("database search matches screenshot text and returns its activity tree")
    func databaseSearchMatchesScreenshotTextAndReturnsItsActivityTree() async throws {
        try await withDatabase { database, _ in
            let searchDatabaseActor = SearchDatabaseActor(database: database)
            try await database.saveOverviewRecord(OverviewInput(
                id: 100,
                title: "Billing",
                summary: "Billing review",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 1,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: nil,
                tagID: nil,
                jsonProperties: nil,
                overviewID: 100
            ))

            try await database.saveScreenshotRecord(
                activityID: 1,
                screenshot: ScreenshotInput(
                    id: 10,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9),
                    description: "Invoice approval dialog",
                    text: "Approve quarterly billing export",
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            let trees = try await searchDatabaseActor.dbSearch(query: "\"quarterly\"", relevanceFloor: softRelevanceFloor).trees
            let recoveredTree = try #require(
                trees.first.map { ($0.id, $0.activities.map(\.id), $0.activities.first?.screenshots.map(\.id) ?? []) }
            )
            #expect(recoveredTree == (100, [1], [10]))
        }
    }

    @Test("database search matches overview text and returns its tree")
    func databaseSearchMatchesOverviewTextAndReturnsItsTree() async throws {
        try await withDatabase { database, _ in
            let searchDatabaseActor = SearchDatabaseActor(database: database)
            try await database.saveOverviewRecord(OverviewInput(
                id: 7,
                title: "Billing work",
                summary: "Retrospective for the March billing export incident.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 1,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Reviewed the incident timeline.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 7
            ))
            try await database.saveScreenshotRecord(
                activityID: 1,
                screenshot: ScreenshotInput(
                    id: 71,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9, minute: 5),
                    description: "Billing incident timeline",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            let trees = try await searchDatabaseActor.dbSearch(query: "\"retrospective\"", relevanceFloor: softRelevanceFloor).trees
            let recoveredOverviewID = try #require(trees.first?.id)
            #expect(recoveredOverviewID == 7)
        }
    }

    @Test("database search links a screenshot match back to its original screenshot")
    func databaseSearchLinksAScreenshotMatchBackToItsOriginalScreenshot() async throws {
        try await withDatabase { database, _ in
            let searchDatabaseActor = SearchDatabaseActor(database: database)
            try await database.saveOverviewRecord(OverviewInput(
                id: 101,
                title: "Receivables",
                summary: "Receivables review",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 1,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: nil,
                tagID: nil,
                jsonProperties: nil,
                overviewID: 101
            ))

            try await database.saveScreenshotRecord(
                activityID: 1,
                screenshot: ScreenshotInput(
                    id: 22,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9),
                    description: "Dashboard",
                    text: "OCR mentions receivables aging",
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            let screenshotIDs = try await searchDatabaseActor
                .dbSearch(query: "\"receivables\"", relevanceFloor: softRelevanceFloor).trees
                .flatMap(\.activities)
                .flatMap(\.screenshots)
                .map(\.id)
            #expect(screenshotIDs == [22])
        }
    }

    @Test("database search recovers a matched screenshot with its activity and overview")
    func databaseSearchRecoversAMatchedScreenshotWithItsActivityAndOverview() async throws {
        try await withDatabase { database, _ in
            let searchDatabaseActor = SearchDatabaseActor(database: database)
            try await database.saveOverviewRecord(OverviewInput(
                id: 7,
                title: "Billing work",
                summary: "Quarterly billing export review.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 1,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Prepared the billing export approval.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 7
            ))
            try await database.saveScreenshotRecord(
                activityID: 1,
                screenshot: ScreenshotInput(
                    id: 10,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9, minute: 5),
                    description: "Approval dialog",
                    text: "Approve quarterly billing export",
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            let trees = try await searchDatabaseActor.dbSearch(query: "\"quarterly\"", relevanceFloor: softRelevanceFloor).trees
            let recoveredTree = try #require(
                trees.first.map { ($0.id, $0.activities.first?.id, $0.activities.first?.screenshots.map(\.id) ?? []) }
            )
            #expect(recoveredTree == (7, 1, [10]))
        }
    }

    @Test("database search ignores activities without an overview")
    func databaseSearchIgnoresActivitiesWithoutAnOverview() async throws {
        try await withDatabase { database, _ in
            let searchDatabaseActor = SearchDatabaseActor(database: database)
            try await database.saveActivityRecord(ActivityInput(
                id: 3,
                startTime: localDate(dayOffset: 0, hour: 11),
                application: "Xcode",
                keystrokes: nil,
                microphone: nil,
                summary: "Investigated the ledger import bug.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: nil
            ))
            try await database.saveScreenshotRecord(
                activityID: 3,
                screenshot: ScreenshotInput(
                    id: 31,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 11, minute: 5),
                    description: "Ledger import error",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            let trees = try await searchDatabaseActor.dbSearch(query: "\"ledger\"", relevanceFloor: softRelevanceFloor).trees
            #expect(trees.isEmpty)
        }
    }

    @Test("database search dedupes an overview root across overview activity and screenshot matches")
    func databaseSearchDedupesAnOverviewRootAcrossOverviewActivityAndScreenshotMatches() async throws {
        try await withDatabase { database, _ in
            let searchDatabaseActor = SearchDatabaseActor(database: database)
            try await database.saveOverviewRecord(OverviewInput(
                id: 8,
                title: "Ledger work",
                summary: "Ledger reconciliation follow-up.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 81,
                startTime: localDate(dayOffset: 0, hour: 13),
                application: "Numbers",
                keystrokes: nil,
                microphone: nil,
                summary: "Resolved the ledger mismatch.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 8
            ))
            try await database.saveScreenshotRecord(
                activityID: 81,
                screenshot: ScreenshotInput(
                    id: 811,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 13, minute: 10),
                    description: "Ledger mismatch details",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            let rootIDs = try await searchDatabaseActor.dbSearch(query: "\"ledger\"", relevanceFloor: softRelevanceFloor).trees.map(\.id)
            #expect(rootIDs == [8])
        }
    }

    @Test("database search ranks the stronger multi keyword root ahead of incidental matches")
    func databaseSearchRanksTheStrongerMultiKeywordRootAheadOfIncidentalMatches() async throws {
        try await withDatabase { database, _ in
            let searchDatabaseActor = SearchDatabaseActor(database: database)
            try await database.saveOverviewRecord(OverviewInput(
                id: 40,
                title: "Quarterly billing",
                summary: "Quarterly billing export approval quarterly billing export approval quarterly billing export approval quarterly billing export approval.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 400,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Quarterly billing export approval quarterly billing export approval quarterly billing export approval quarterly billing export approval.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 40
            ))
            try await database.saveScreenshotRecord(
                activityID: 400,
                screenshot: ScreenshotInput(
                    id: 4000,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9, minute: 5),
                    description: "Quarterly billing export approval quarterly billing export approval quarterly billing export approval quarterly billing export approval",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )
            try await database.saveOverviewRecord(OverviewInput(
                id: 41,
                title: "Gardening notes",
                summary: "Unrelated gardening notes and plant watering checklist.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 410,
                startTime: localDate(dayOffset: 0, hour: 10),
                application: "Notes",
                keystrokes: nil,
                microphone: nil,
                summary: "One billing mention inside unrelated gardening notes.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 41
            ))
            try await database.saveScreenshotRecord(
                activityID: 410,
                screenshot: ScreenshotInput(
                    id: 4100,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 10, minute: 5),
                    description: "Gardening notes",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            let rootIDs = try await searchDatabaseActor.dbSearch(
                query: "\"billing\" OR \"export\" OR \"quarterly\" OR \"approval\"",
                relevanceFloor: softRelevanceFloor
            ).trees.map(\.id)
            #expect(rootIDs.first == 40)
        }
    }

    @Test("database search returns an overview root without child branches for an overview-only match")
    func databaseSearchReturnsAnOverviewRootWithoutChildBranchesForAnOverviewOnlyMatch() async throws {
        try await withDatabase { database, _ in
            let searchDatabaseActor = SearchDatabaseActor(database: database)
            try await database.saveOverviewRecord(OverviewInput(
                id: 9,
                title: "Quarter close",
                summary: "Quarter close work for finance handoff.",
                jsonProperties: nil,
                editedDuration: nil,
                tagID: nil
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 91,
                startTime: localDate(dayOffset: 0, hour: 8),
                application: "Safari",
                keystrokes: nil,
                microphone: nil,
                summary: "Reviewed the finance checklist.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 9
            ))
            try await database.saveActivityRecord(ActivityInput(
                id: 92,
                startTime: localDate(dayOffset: 0, hour: 9),
                application: "Excel",
                keystrokes: nil,
                microphone: nil,
                summary: "Updated the quarter close numbers.",
                tagID: nil,
                jsonProperties: nil,
                overviewID: 9
            ))
            try await database.saveScreenshotRecord(
                activityID: 91,
                screenshot: ScreenshotInput(
                    id: 911,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 8, minute: 5),
                    description: "Finance checklist",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )
            try await database.saveScreenshotRecord(
                activityID: 92,
                screenshot: ScreenshotInput(
                    id: 921,
                    image: nil,
                    timestamp: localDate(dayOffset: 0, hour: 9, minute: 5),
                    description: "Quarter close workbook",
                    text: nil,
                    ignoreReason: nil,
                    jsonProperties: nil
                )
            )

            let recoveredTree = try #require(try await searchDatabaseActor
                .dbSearch(query: "\"handoff\"", relevanceFloor: softRelevanceFloor).trees
                .first
                .map { ($0.id, $0.activities.map(\.id), $0.activities.flatMap(\.screenshots).map(\.id)) })
            #expect(recoveredTree == (9, [], []))
        }
    }

    @Test("sqlite vector smoke test can create and query vectors")
    func sqliteVectorSmokeTestCanCreateAndQueryVectors() async throws {
        try await withDatabase { database, _ in
            let ids = try await database.runVectorSmokeTest()
            #expect(ids == [1, 2])
        }
    }

    @Test("legacy activity schema migrates summaries into the unified summary column")
    func legacyActivitySchemaMigratesSummariesIntoTheUnifiedSummaryColumn() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let legacyDatabase = try DatabaseQueue(path: databaseURL.path)
        try await legacyDatabase.write { db in
            try db.execute(sql: "CREATE TABLE tags (id INTEGER PRIMARY KEY NOT NULL, name TEXT, create_date DATE, description TEXT, delete_date DATE, json_properties TEXT)")
            try db.execute(sql: "CREATE TABLE overviews (id INTEGER PRIMARY KEY NOT NULL, title TEXT, summary TEXT, json_properties TEXT, edited_duration INTEGER, tag_id INTEGER REFERENCES tags(id) ON DELETE SET NULL)")
            try db.execute(sql: "CREATE TABLE activities (id INTEGER PRIMARY KEY NOT NULL, start_time TIMESTAMP NOT NULL, application TEXT NOT NULL, keystrokes TEXT, screen_summary TEXT, activity_summary TEXT, tag_id INTEGER REFERENCES tags(id) ON DELETE SET NULL, json_properties TEXT, overview_id INTEGER REFERENCES overviews(id) ON DELETE SET NULL)")
            try db.execute(sql: "CREATE INDEX idx_activities_start_time ON activities (start_time)")
            try db.execute(sql: "CREATE TABLE screenshots (id INTEGER PRIMARY KEY NOT NULL, image BLOB, ts TIMESTAMP, description TEXT, ocr_text TEXT, image_deletion_reason TEXT, ignore_reason TEXT, json_properties TEXT, activity_id INTEGER NOT NULL REFERENCES activities(id) ON DELETE CASCADE)")
            try db.execute(sql: "CREATE INDEX idx_screenshots_ts ON screenshots (ts)")
            try db.execute(sql: "CREATE TABLE versions (version INTEGER NOT NULL)")
            try db.execute(sql: "CREATE TABLE settings (name TEXT PRIMARY KEY, value TEXT)")
            try db.execute(sql: "INSERT INTO versions (version) VALUES (1)")
            try db.execute(
                sql: """
                    INSERT INTO activities (
                        id,
                        start_time,
                        application,
                        keystrokes,
                        screen_summary,
                        activity_summary,
                        tag_id,
                        json_properties,
                        overview_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    1,
                    sqlTimestamp(localDate(dayOffset: 0, hour: 9)),
                    "Xcode",
                    "abc",
                    "screen summary",
                    "activity summary",
                    nil,
                    nil,
                    nil
                ]
            )
        }

        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)
        let migratedDatabase = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let state = try await migratedDatabase.loadState(for: today())
        let summary = await MainActor.run { state.activity.first?.summary }
        let version = try await migratedDatabase.getVersion()
        #expect((summary, version) == ("activity summary", TaskTraceDatabaseBootstrap.currentVersion))
    }
}

private func today() -> Date {
    Calendar(identifier: .gregorian).startOfDay(for: Date())
}

private func localDate(dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
    let calendar = Calendar(identifier: .gregorian)
    let baseDay = calendar.startOfDay(for: Date())
    let shiftedDay = calendar.date(byAdding: .day, value: dayOffset, to: baseDay) ?? baseDay
    return calendar.date(byAdding: .minute, value: hour * 60 + minute, to: shiftedDay) ?? shiftedDay
}

private func sqlTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
}

private func activityEmbedding(activatedDimension: Int) -> [Float] {
    (0..<TaskTraceDatabaseBootstrap.activityEmbeddingDimension).map {
        $0 == activatedDimension ? 1 : 0
    }
}

private func vectorJSONString(_ vector: [Float]) throws -> String {
    let data = try JSONEncoder().encode(vector)
    return String(decoding: data, as: UTF8.self)
}
