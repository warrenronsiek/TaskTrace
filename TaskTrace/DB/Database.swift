//
//  Database.swift
//  TaskTrace
//
//  Created by Codex on 3/12/26.
//

import Foundation
import GRDB
import OSLog

final class TaskTraceDatabase: @unchecked Sendable {
    nonisolated let databaseURL: URL
    nonisolated static func databaseQuestionMarks(count: Int) -> String {
        Array(repeating: "?", count: max(count, 1)).joined(separator: ", ")
    }

    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "search-db")
    // `dbPool` is the general-purpose pooled handle for the canonical SQLite
    // file. These connections still load sqlite-vector because canonical
    // embedding blobs and helper functions are part of the base schema, but
    // they intentionally do not load vectorlite.
    //
    // This is the "normal GRDB world": pooled readers and writers against the
    // main database file, with no connection-local ANN state attached.
    nonisolated let dbPool: DatabasePool

    // `vectorAwareDBQueue` is the single connection that owns all vector-aware
    // work against the same SQLite file. Vectorlite keeps HNSW state in memory
    // per connection, so ANN reads and writes that must stay in sync with the
    // runtime-local temp HNSW table need one canonical connection that sees
    // the same extension state for the lifetime of the process.
    //
    // This is not a second database. It is a second connection strategy for
    // the same database file, used only when a SQL operation can touch HNSW-
    // backed virtual tables or needs the writer's immediate view of state that
    // is maintained on the vectorlite connection.
    nonisolated let vectorAwareDBQueue: DatabaseQueue

    nonisolated func read<T: Sendable>(
        _ value: (Database) throws -> T
    ) throws -> T {
        try dbPool.read(value)
    }

    nonisolated func vectorAwareRead<T: Sendable>(
        _ value: (Database) throws -> T
    ) throws -> T {
        // Reads that depend on vectorlite state or must observe data created by
        // the vector-aware write pipeline should come here, not through `dbPool`.
        try vectorAwareDBQueue.read(value)
    }

    nonisolated func write<T: Sendable>(
        _ updates: (Database) throws -> T
    ) throws -> T {
        // Use the pooled writer for ordinary canonical-table mutations that do
        // not participate in vectorlite/HNSW maintenance.
        try dbPool.write(updates)
    }

    nonisolated func vectorAwareWrite<T: Sendable>(
        _ updates: (Database) throws -> T
    ) throws -> T {
        // Vector-aware writes opt into the dedicated connection so the same SQL
        // transaction can touch canonical tables and the temp vectorlite-backed
        // ANN table without crossing SQLite connections.
        let result = try vectorAwareDBQueue.write(updates)
        try vectorAwareDBQueue.write { db in
            try TaskTraceDatabaseBootstrap.flushActivitySummaryVectorIndexIfNeeded(on: db)
        }
        return result
    }

    nonisolated func vectorAwareWriteFlushing<T: Sendable>(
        _ updates: (Database) throws -> T
    ) throws -> T {
        let result = try vectorAwareDBQueue.write(updates)
        try vectorAwareDBQueue.write { db in
            try TaskTraceDatabaseBootstrap.flushActivitySummaryVectorIndex(on: db)
        }
        return result
    }

    convenience init() throws {
        try self.init(
            databaseURL: nil,
            fileManager: .default
        )
    }

    convenience init(databaseURL: URL?) throws {
        try self.init(
            databaseURL: databaseURL,
            fileManager: .default
        )
    }

    init(
        databaseURL: URL?,
        fileManager: FileManager = .default
    ) throws {
        let resolvedURL = try TaskTraceDatabaseBootstrap.resolvedDatabaseURL(databaseURL, fileManager: fileManager)

        self.databaseURL = resolvedURL

        try fileManager.createDirectory(
            at: resolvedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Both handles target the same SQLite file. The difference is the
        // extension set and lifetime of the underlying connection, not the data
        // store they operate on.
        dbPool = try DatabasePool(
            path: resolvedURL.path,
            configuration: TaskTraceDatabaseBootstrap.makeConfiguration(
                label: "TaskTraceDatabasePool",
                extensionSet: .pooledRead
            )
        )
        vectorAwareDBQueue = try DatabaseQueue(
            path: resolvedURL.path,
            configuration: TaskTraceDatabaseBootstrap.makeConfiguration(
                label: "TaskTraceVectorAwareDatabase",
                extensionSet: .vectorAware
            )
        )
        try vectorAwareDBQueue.write { db in
            try TaskTraceDatabaseBootstrap.prepareActivitySummaryVectorIndex(
                on: db,
                databaseURL: resolvedURL
            )
        }
    }

    convenience init(
        databaseURL: URL?,
        fileManager: FileManager = .default,
        activityAI: any ActivityAIOperating
    ) throws {
        try self.init(
            databaseURL: databaseURL,
            fileManager: fileManager
        )
    }

    func getVersion() throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT version FROM versions LIMIT 1") ?? 0
        }
    }

    func getSetting(named name: String) throws -> String? {
        try dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM settings WHERE name = ?",
                arguments: [name]
            )
        }
    }

    func getUserID() throws -> String? {
        try getSetting(named: "UserID")
    }

    func getVectorVersion() throws -> String? {
        try dbPool.read { db in
            // `vector_version()` comes from sqlite-vector, which is available on
            // every connection because canonical embedding columns depend on it.
            try String.fetchOne(db, sql: "SELECT vector_version()")
        }
    }

    func getVectorliteInfo() throws -> String? {
        try vectorAwareDBQueue.read { db in
            // `vectorlite_info()` only exists on the dedicated vector-aware
            // connection because vectorlite is intentionally not loaded on the
            // general pooled connections.
            try String.fetchOne(db, sql: "SELECT vectorlite_info()")
        }
    }

    func setSetting(named name: String, value: String) throws {
        try dbPool.write { db in
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

    func get(_ entity: DatabaseEntity) throws -> DatabaseGetResult {
        try dbPool.read { db in
            switch entity {
            case .activity(.all):
                return .activities(try ActivityRecord.fetchAll(
                    db,
                    sql: "SELECT * FROM activities ORDER BY start_time ASC"
                ))
            case let .activity(.id(id)):
                return .activity(try ActivityRecord.fetchOne(
                    db,
                    sql: "SELECT * FROM activities WHERE id = ?",
                    arguments: [id]
                ))
            case .screenshot(.all):
                return .screenshots(try ScreenshotRecord.fetchAll(
                    db,
                    sql: "SELECT * FROM screenshots ORDER BY ts ASC"
                ))
            case let .screenshot(.id(id)):
                return .screenshot(try ScreenshotRecord.fetchOne(
                    db,
                    sql: "SELECT * FROM screenshots WHERE id = ?",
                    arguments: [id]
                ))
            case .overview(.all):
                return .overviews(try OverviewRecord.fetchAll(
                    db,
                    sql: "SELECT * FROM overviews ORDER BY id ASC"
                ))
            case let .overview(.id(id)):
                return .overview(try OverviewRecord.fetchOne(
                    db,
                    sql: "SELECT * FROM overviews WHERE id = ?",
                    arguments: [id]
                ))
            case .tag(.all):
                return .tags(try TagRecord.fetchAll(
                    db,
                    sql: """
                        SELECT *
                        FROM tags
                        WHERE delete_date IS NULL
                        ORDER BY create_date ASC, id ASC
                        """
                ))
            case .agentAction(.all):
                return .agentActions(try AgentActionRecord.fetchAll(
                    db,
                    sql: """
                        SELECT
                            id,
                            instructions,
                            event_type,
                            conversation_id
                        FROM agent_actions
                        WHERE event_type = ?
                        ORDER BY id DESC
                        """,
                    arguments: [AgentActionEventType.activitySummarized.rawValue]
                ))
            case let .agentAction(.id(id)):
                return .agentAction(try AgentActionRecord.fetchOne(
                    db,
                    sql: """
                        SELECT
                            id,
                            instructions,
                            event_type,
                            conversation_id
                        FROM agent_actions
                        WHERE id = ? AND event_type = ?
                        """,
                    arguments: [id, AgentActionEventType.activitySummarized.rawValue]
                ))
            case .knowledgeDirectory(.all):
                return .knowledgeDirectories(try KnowledgeDirectoryRecord.fetchAll(
                    db,
                    sql: """
                        SELECT *
                        FROM knowledge_directories
                        ORDER BY created_at DESC, id DESC
                        """
                ))
            case let .knowledgeDirectory(.id(id)):
                return .knowledgeDirectory(try KnowledgeDirectoryRecord.fetchOne(
                    db,
                    sql: "SELECT * FROM knowledge_directories WHERE id = ?",
                    arguments: [id]
                ))
            case let .knowledgeFile(.directoryID(directoryID)):
                return .knowledgeFiles(try KnowledgeFileRecord.fetchAll(
                    db,
                    sql: """
                        SELECT *
                        FROM knowledge_files
                        WHERE directory_id = ?
                          AND deleted_at IS NULL
                        ORDER BY relative_path ASC
                        """,
                    arguments: [directoryID]
                ))
            case let .knowledgeFile(.directoryIDIncludingDeleted(directoryID)):
                return .knowledgeFiles(try KnowledgeFileRecord.fetchAll(
                    db,
                    sql: """
                        SELECT *
                        FROM knowledge_files
                        WHERE directory_id = ?
                        ORDER BY relative_path ASC
                        """,
                    arguments: [directoryID]
                ))
            case let .knowledgeFile(.id(id)):
                return .knowledgeFile(try KnowledgeFileRecord.fetchOne(
                    db,
                    sql: "SELECT * FROM knowledge_files WHERE id = ?",
                    arguments: [id]
                ))
            case .knowledgeNode(.all):
                return .knowledgeNodes(try KnowledgeNodeRecord.fetchAll(
                    db,
                    sql: """
                        SELECT *
                        FROM knowledge_nodes
                        ORDER BY normalized_name ASC, id ASC
                        """
                ))
            case let .knowledgeNode(.id(id)):
                return .knowledgeNode(try KnowledgeNodeRecord.fetchOne(
                    db,
                    sql: "SELECT * FROM knowledge_nodes WHERE id = ?",
                    arguments: [id]
                ))
            case let .knowledgeNode(.normalizedName(normalizedName)):
                return .knowledgeNode(try KnowledgeNodeRecord.fetchOne(
                    db,
                    sql: "SELECT * FROM knowledge_nodes WHERE normalized_name = ?",
                    arguments: [normalizedName]
                ))
            case .knowledgeEdge(.all):
                return .knowledgeEdges(try KnowledgeEdgeRecord.fetchAll(
                    db,
                    sql: """
                        SELECT *
                        FROM knowledge_edges
                        ORDER BY first_node_id ASC, second_node_id ASC, id ASC
                        """
                ))
            case let .knowledgeEdge(.id(id)):
                return .knowledgeEdge(try KnowledgeEdgeRecord.fetchOne(
                    db,
                    sql: "SELECT * FROM knowledge_edges WHERE id = ?",
                    arguments: [id]
                ))
            case let .knowledgeEdge(.pair(firstNodeID, secondNodeID)):
                let pair = KnowledgeEdgeRecord.canonicalPair(firstNodeID, secondNodeID)

                return .knowledgeEdge(try KnowledgeEdgeRecord.fetchOne(
                    db,
                    sql: """
                        SELECT *
                        FROM knowledge_edges
                        WHERE first_node_id = ? AND second_node_id = ?
                        """,
                    arguments: [pair.firstNodeID, pair.secondNodeID]
                ))
            case .activity(.record), .screenshot(.record), .overview(.record), .tag(.record), .agentAction(.record), .knowledgeDirectory(.record), .knowledgeFile(.record), .knowledgeNode(.record), .knowledgeEdge(.record), .screenshot(.activityID), .tag(.id):
                throw DatabaseRequestError.invalidGet
            }
        }
    }

    func save(_ entity: DatabaseEntity) async throws {
        try await dbPool.write { db in
            switch entity {
            case let .tag(.record(tag)):
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
                        (tag.createDate ?? Date()).formatted(Self.sqlDateStyle),
                        tag.description,
                        tag.deleteDate.map { $0.formatted(Self.sqlDateStyle) },
                        tag.jsonProperties,
                        tag.originKind,
                        tag.generatedName,
                        tag.generatedDescription,
                        tag.nameIsUserEdited ?? false,
                        tag.descriptionIsUserEdited ?? false
                    ]
                )
            case let .agentAction(.record(agentAction)):
                try db.execute(
                    sql: """
                        INSERT INTO agent_actions (
                            id,
                            instructions,
                            event_type,
                            conversation_id
                        )
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            instructions = excluded.instructions,
                            event_type = excluded.event_type,
                            conversation_id = excluded.conversation_id
                        """,
                    arguments: [
                        agentAction.id,
                        agentAction.instructions,
                        agentAction.eventType.rawValue,
                        agentAction.conversationID
                    ]
                )
            case .activity(.all), .activity(.id), .activity(.record), .screenshot(.all), .screenshot(.id), .screenshot(.activityID), .screenshot(.record), .overview(.all), .overview(.id), .overview(.record), .tag(.all), .tag(.id):
                throw DatabaseRequestError.invalidSave
            case .agentAction(.all), .agentAction(.id), .knowledgeDirectory(.all), .knowledgeDirectory(.id), .knowledgeDirectory(.record), .knowledgeFile(.directoryID), .knowledgeFile(.directoryIDIncludingDeleted), .knowledgeFile(.id), .knowledgeFile(.record), .knowledgeNode(.all), .knowledgeNode(.id), .knowledgeNode(.normalizedName), .knowledgeNode(.record), .knowledgeEdge(.all), .knowledgeEdge(.id), .knowledgeEdge(.pair), .knowledgeEdge(.record):
                throw DatabaseRequestError.invalidSave
            }
        }
    }
    func delete(_ entity: DatabaseEntity) throws {
        try dbPool.write { db in
            switch entity {
            case let .tag(.id(id)):
                try db.execute(
                    sql: "UPDATE tags SET delete_date = ? WHERE id = ?",
                    arguments: [Date().formatted(Self.sqlDateStyle), id]
                )
            case let .agentAction(.id(id)):
                try db.execute(sql: "DELETE FROM agent_actions WHERE id = ?", arguments: [id])
            case let .knowledgeFile(.id(id)):
                try db.execute(sql: "DELETE FROM knowledge_files WHERE id = ?", arguments: [id])
            case let .knowledgeNode(.id(id)):
                try db.execute(sql: "DELETE FROM knowledge_nodes WHERE id = ?", arguments: [id])
            case let .knowledgeEdge(.id(id)):
                try db.execute(sql: "DELETE FROM knowledge_edges WHERE id = ?", arguments: [id])
            case .activity(.all), .activity(.id), .activity(.record), .screenshot(.all), .screenshot(.id), .screenshot(.activityID), .screenshot(.record), .overview(.all), .overview(.id), .overview(.record), .tag(.all), .tag(.record), .agentAction(.all), .agentAction(.record):
                throw DatabaseRequestError.invalidDelete
            case .knowledgeDirectory(.all), .knowledgeDirectory(.id), .knowledgeDirectory(.record), .knowledgeFile(.directoryID), .knowledgeFile(.directoryIDIncludingDeleted), .knowledgeFile(.record), .knowledgeNode(.all), .knowledgeNode(.record), .knowledgeNode(.normalizedName), .knowledgeEdge(.all), .knowledgeEdge(.record), .knowledgeEdge(.pair):
                throw DatabaseRequestError.invalidDelete
            }
        }
    }

    func activityAggregation(startDate: Date, endDate: Date) throws -> [ActivityAggregation] {
        try dbPool.read { db in
            try ActivityAggregation.fetchAll(
                db,
                sql: """
                    WITH leads AS (
                        SELECT
                            start_time,
                            tags.name AS tag_name,
                            application,
                            CAST((
                                strftime('%s', LEAD(start_time)
                                    OVER (PARTITION BY DATE(start_time) ORDER BY start_time)
                                ) - strftime('%s', start_time)
                            ) AS INTEGER) AS duration
                        FROM activities
                        LEFT JOIN tags ON activities.tag_id = tags.id
                        WHERE DATE(start_time) BETWEEN DATE(?) AND DATE(?)
                    )
                    SELECT
                        DATE(start_time) AS dt,
                        tag_name,
                        SUM(duration) AS duration
                    FROM leads
                    WHERE application <> 'PAUSED'
                      AND application <> 'SLEEP'
                    GROUP BY DATE(start_time), tag_name
                    ORDER BY DATE(start_time) ASC, tag_name ASC
                    """,
                arguments: [
                    startDate.formatted(Self.sqlDateStyle),
                    endDate.formatted(Self.sqlDateStyle)
                ]
            )
        }
    }

    func searchActivities(matching query: String, limit: Int = 50) throws -> [ActivityRecord] {
        guard !query.isEmpty else {
            return []
        }

        return try dbPool.read { db in
            try ActivityRecord.fetchAll(
                db,
                sql: """
                    SELECT activities.*
                    FROM activity_fts
                    JOIN activities ON activities.id = activity_fts.rowid
                    WHERE activity_fts MATCH ?
                    ORDER BY bm25(activity_fts), activities.start_time DESC
                    LIMIT ?
                    """,
                arguments: [query, limit]
            )
        }
    }


    func runVectorSmokeTest() throws -> [Int64] {
        try dbPool.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS tt_vector_smoke")
            try db.execute(sql: "CREATE TABLE tt_vector_smoke (id INTEGER PRIMARY KEY, embedding BLOB)")
            try db.execute(
                sql: """
                    INSERT INTO tt_vector_smoke (id, embedding)
                    VALUES
                        (1, vector_as_f32('[0.1, 0.2, 0.3]')),
                        (2, vector_as_f32('[0.9, 0.8, 0.7]'))
                    """
            )
            try db.execute(
                sql: "SELECT vector_init('tt_vector_smoke', 'embedding', 'type=FLOAT32,dimension=3,distance=COSINE')"
            )

            return try Int64.fetchAll(
                db,
                sql: """
                    SELECT id
                    FROM vector_full_scan('tt_vector_smoke', 'embedding', vector_as_f32('[0.1, 0.2, 0.3]'), 2)
                    ORDER BY distance ASC
                    """
            )
        }
    }

    func runVectorliteSmokeTest() throws -> [Int64] {
        try vectorAwareDBQueue.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS tt_vectorlite_smoke")
            try db.execute(
                sql: """
                    CREATE VIRTUAL TABLE tt_vectorlite_smoke
                    USING vectorlite(embedding float32[3] cosine, hnsw(max_elements=8))
                    """
            )
            try db.execute(
                sql: """
                    INSERT INTO tt_vectorlite_smoke (rowid, embedding)
                    VALUES
                        (1, vector_from_json('[0.1, 0.2, 0.3]')),
                        (2, vector_from_json('[0.9, 0.8, 0.7]'))
                    """
            )

            return try Int64.fetchAll(
                db,
                sql: """
                    SELECT rowid
                    FROM tt_vectorlite_smoke
                    WHERE knn_search(embedding, knn_param(vector_from_json('[0.1, 0.2, 0.3]'), 2))
                    ORDER BY distance ASC
                    """
            )
        }
    }

    func loadState(for date: Date) throws -> LoadedState {
        let startOfDay = Calendar(identifier: .gregorian).startOfDay(for: date)
        let nextDay = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let daySQL = startOfDay.formatted(Self.sqlDateStyle)
        let startSQL = startOfDay.formatted(Self.sqlTimestampStyle)
        let endSQL = nextDay.formatted(Self.sqlTimestampStyle)

        return try dbPool.read { db in
            let joinRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        a.id AS a_id,
                        a.start_time AS a_start_time,
                        a.application AS a_application,
                        a.keystrokes AS a_keystrokes,
                        a.microphone AS a_microphone,
                        a.summary AS a_summary,
                        a.tag_id AS a_tag_id,
                        a.tag_assignment_source AS a_tag_assignment_source,
                        a.ontology_candidate_id AS a_ontology_candidate_id,
                        a.overview_id AS a_overview_id,
                        a.overview_assignment_source AS a_overview_assignment_source,
                        s.id AS s_id,
                        s.ts AS s_ts,
                        s.description AS s_description,
                        s.ocr_text AS s_ocr_text,
                        s.summary AS s_summary,
                        s.ignore_reason AS s_ignore_reason
                    FROM activities a
                    LEFT JOIN screenshots s
                        ON a.id = s.activity_id
                        AND s.ts >= ?
                        AND s.ts < ?
                    WHERE a.start_time >= ?
                      AND a.start_time < ?
                    ORDER BY a.start_time ASC, s.ts ASC
                    """,
                arguments: [startSQL, endSQL, startSQL, endSQL]
            )

            let activities = try joinRows.reduce(into: [Int64: LoadedActivity]()) { partialResult, row in
                let id: Int64 = row["a_id"]

                if partialResult[id] == nil {
                    partialResult[id] = LoadedActivity(
                        id: id,
                        startTime: try Self.date(fromSQLTimestamp: row["a_start_time"]),
                        application: row["a_application"],
                        keystrokes: row["a_keystrokes"],
                        microphone: row["a_microphone"],
                        summary: row["a_summary"],
                        tagID: row["a_tag_id"],
                        tagAssignmentSource: (row["a_tag_assignment_source"] as String?)
                            .flatMap(ActivityTagAssignmentSource.init(rawValue:)),
                        ontologyCandidateID: row["a_ontology_candidate_id"],
                        overviewAssignmentSource: (row["a_overview_assignment_source"] as String?)
                            .flatMap(OverviewAssignmentSource.init(rawValue:)),
                        overviewID: row["a_overview_id"],
                        screenshots: []
                    )
                }

                if let screenshotID: Int64 = row["s_id"] {
                    partialResult[id]?.screenshots.append(
                        LoadedScreenshot(
                            id: screenshotID,
                            image: nil,
                            timestamp: try Self.date(fromSQLTimestamp: row["s_ts"]),
                            description: row["s_description"],
                            text: row["s_ocr_text"],
                            summary: row["s_summary"],
                            ignoreReason: row["s_ignore_reason"]
                        )
                    )
                }
            }

            let overviews = try LoadedOverview.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT
                        o.id AS id,
                        o.title AS title,
                        o.summary AS summary,
                        o.edited_duration AS edited_duration,
                        o.tag_id AS tag_id,
                        o.origin_kind AS origin_kind,
                        o.generated_title AS generated_title,
                        o.generated_summary AS generated_summary,
                        o.title_is_user_edited AS title_is_user_edited,
                        o.summary_is_user_edited AS summary_is_user_edited
                    FROM overviews o
                    INNER JOIN activities a ON a.overview_id = o.id
                    WHERE DATE(a.start_time) = DATE(?)
                    ORDER BY o.id ASC
                    """,
                arguments: [daySQL]
            )

            let tags = try LoadedTag.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT
                        id,
                        name,
                        description
                    FROM tags
                    WHERE DATE(create_date) <= DATE(?)
                      AND (delete_date IS NULL OR DATE(delete_date) >= DATE(?))
                    ORDER BY create_date ASC, id ASC
                    """,
                arguments: [daySQL, daySQL]
            )

            return LoadedState(
                activity: activities.values.sorted { $0.id < $1.id },
                overview: overviews,
                tags: tags
            )
        }
    }

    func loadableDates() throws -> [Date] {
        try dbPool.read { db in
            let dates = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT DATE(start_time) AS dt
                    FROM activities
                    ORDER BY dt ASC
                    """
            )

            return try (dates + [Date().formatted(Self.sqlDateStyle)]).reduce(into: [Date]()) { partialResult, value in
                let date = try Self.date(fromSQLDate: value)

                if !partialResult.contains(date) {
                    partialResult.append(date)
                }
            }
        }
    }

    nonisolated static let sqlCalendar = Calendar(identifier: .gregorian)

    nonisolated static let sqlLocale = Locale(identifier: "en_US_POSIX")

    nonisolated static let sqlDateFormat: Date.FormatString =
        "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)"

    nonisolated static let sqlTimestampFormat: Date.FormatString =
        "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)"

    nonisolated static let sqlDateStyle = Date.VerbatimFormatStyle(
        format: sqlDateFormat,
        locale: sqlLocale,
        timeZone: .current,
        calendar: sqlCalendar
    )

    nonisolated static let sqlTimestampStyle = Date.VerbatimFormatStyle(
        format: sqlTimestampFormat,
        locale: sqlLocale,
        timeZone: .current,
        calendar: sqlCalendar
    )

    nonisolated static func date(fromSQLDate value: String) throws -> Date {
        do {
            return try Date.ParseStrategy(
                format: sqlDateFormat,
                locale: sqlLocale,
                timeZone: .current,
                calendar: sqlCalendar
            ).parse(value)
        } catch {
            throw SQLDateError.invalidDate(value)
        }
    }

    nonisolated static func date(fromSQLTimestamp value: String) throws -> Date {
        do {
            return try Date.ParseStrategy(
                format: sqlTimestampFormat,
                locale: sqlLocale,
                timeZone: .current,
                calendar: sqlCalendar
            ).parse(value)
        } catch {
            throw SQLDateError.invalidTimestamp(value)
        }
    }
}

struct OverviewRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "overviews"

    let id: Int64
    let title: String?
    let summary: String?
    let summaryVector: Data?
    let jsonProperties: String?
    let editedDuration: Int?
    let tagID: Int64?
    let knowledgeProcessed: Bool
    let originKind: String?
    let generatedTitle: String?
    let generatedSummary: String?
    let titleIsUserEdited: Bool
    let summaryIsUserEdited: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case summaryVector = "summary_vector"
        case jsonProperties = "json_properties"
        case editedDuration = "edited_duration"
        case tagID = "tag_id"
        case knowledgeProcessed = "knowledge_processed"
        case originKind = "origin_kind"
        case generatedTitle = "generated_title"
        case generatedSummary = "generated_summary"
        case titleIsUserEdited = "title_is_user_edited"
        case summaryIsUserEdited = "summary_is_user_edited"
    }
}

nonisolated enum OverviewOriginKind: String, Codable, Equatable, Sendable {
    case legacy
    case ontology
    case manual
}

nonisolated enum OverviewAssignmentSource: String, Codable, Equatable, Sendable {
    case legacy
    case ontology
    case manual
}

nonisolated enum OverviewBindingSource: String, Codable, Equatable, Sendable {
    case auto
    case manual
}

struct TagRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "tags"

    let id: Int64
    let name: String?
    let createDate: Date?
    let description: String?
    let deleteDate: Date?
    let jsonProperties: String?
    let originKind: String?
    let generatedName: String?
    let generatedDescription: String?
    let nameIsUserEdited: Bool
    let descriptionIsUserEdited: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createDate = "create_date"
        case description
        case deleteDate = "delete_date"
        case jsonProperties = "json_properties"
        case originKind = "origin_kind"
        case generatedName = "generated_name"
        case generatedDescription = "generated_description"
        case nameIsUserEdited = "name_is_user_edited"
        case descriptionIsUserEdited = "description_is_user_edited"
    }

    init(
        id: Int64,
        name: String?,
        createDate: Date?,
        description: String?,
        deleteDate: Date?,
        jsonProperties: String?,
        originKind: String? = nil,
        generatedName: String? = nil,
        generatedDescription: String? = nil,
        nameIsUserEdited: Bool = false,
        descriptionIsUserEdited: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createDate = createDate
        self.description = description
        self.deleteDate = deleteDate
        self.jsonProperties = jsonProperties
        self.originKind = originKind
        self.generatedName = generatedName
        self.generatedDescription = generatedDescription
        self.nameIsUserEdited = nameIsUserEdited
        self.descriptionIsUserEdited = descriptionIsUserEdited
    }
}

struct ActivityRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "activities"

    let id: Int64
    let startTime: Date
    let application: String
    let keystrokes: String?
    let microphone: String?
    let summary: String?
    let summaryVector: Data?
    let summaryVectorUMAP: Data?
    let tagID: Int64?
    let jsonProperties: String?
    let overviewID: Int64?
    let knowledgeProcessed: Bool
    let tagAssignmentSource: String?
    let ontologyCandidateID: Int64?
    let overviewAssignmentSource: String?
    let goalTodoID: Int64?
    let goalTodoAssignmentSource: String?
    let goalTodoAssignmentScore: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case application
        case keystrokes
        case microphone
        case summary
        case summaryVector = "summary_vector"
        case summaryVectorUMAP = "summary_vector_umap"
        case tagID = "tag_id"
        case jsonProperties = "json_properties"
        case overviewID = "overview_id"
        case knowledgeProcessed = "knowledge_processed"
        case tagAssignmentSource = "tag_assignment_source"
        case ontologyCandidateID = "ontology_candidate_id"
        case overviewAssignmentSource = "overview_assignment_source"
        case goalTodoID = "goal_todo_id"
        case goalTodoAssignmentSource = "goal_todo_assignment_source"
        case goalTodoAssignmentScore = "goal_todo_assignment_score"
    }
}

nonisolated struct ActivitySummaryEmbeddingBatch: Equatable, Sendable {
    let activityIDs: [Int64]
    let vectorsData: Data
    let vectorCount: Int
    let vectorDimension: Int
}

nonisolated struct ActivitySummaryUMAPBatch: Equatable, Sendable {
    let activityIDs: [Int64]
    let vectorsData: Data
    let vectorCount: Int
    let vectorDimension: Int
}

nonisolated enum GoalTodoStatus: String, CaseIterable, Codable, Sendable {
    case open
    case done
    case failed
}

nonisolated enum GoalTodoTargetMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case minimum
    case maximum

    var id: String { rawValue }
}

nonisolated enum GoalTodoAssignmentSource: String, Codable, Sendable {
    case automatic = "auto"
    case manual
}

nonisolated struct GoalRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "goals"

    let id: Int64
    let name: String
    let description: String?
    let createTs: Date
    let doneTs: Date?
    let deleteTs: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case createTs = "create_ts"
        case doneTs = "done_ts"
        case deleteTs = "delete_ts"
    }
}

nonisolated struct GoalTodoRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "goal_todos"

    let id: Int64
    let goalID: Int64?
    let name: String
    let createTs: Date
    let doneTs: Date?
    let status: GoalTodoStatus
    let statusTs: Date?
    let repeating: Bool
    let repeatTemplateID: Int64?
    let targetDate: Date?
    let dailyTargetSeconds: Int?
    var dailyTargetMode: GoalTodoTargetMode = .minimum
    let embedding: Data?
    let deleteTs: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case goalID = "goal_id"
        case name
        case createTs = "create_ts"
        case doneTs = "done_ts"
        case status
        case statusTs = "status_ts"
        case repeating
        case repeatTemplateID = "repeat_template_id"
        case targetDate = "target_date"
        case dailyTargetSeconds = "daily_target_seconds"
        case dailyTargetMode = "daily_target_mode"
        case embedding
        case deleteTs = "delete_ts"
    }
}

nonisolated struct GoalInput: Equatable, Sendable {
    let id: Int64
    let name: String
    let description: String?
    let createTs: Date?
    let doneTs: Date?
}

nonisolated struct GoalTodoInput: Equatable, Sendable {
    let id: Int64
    let goalID: Int64?
    let name: String
    let createTs: Date?
    let status: GoalTodoStatus
    let statusTs: Date?
    let repeating: Bool
    let repeatTemplateID: Int64?
    let targetDate: Date?
    let dailyTargetSeconds: Int?
    var dailyTargetMode: GoalTodoTargetMode = .minimum
}

nonisolated struct GoalTodoCandidate: Equatable, Sendable {
    let todo: GoalTodoRecord
    let goal: GoalRecord?
}

nonisolated struct GoalTodoRollup: Codable, Equatable, FetchableRecord, Sendable {
    let todoID: Int64
    let duration: Int

    enum CodingKeys: String, CodingKey {
        case todoID = "todo_id"
        case duration
    }
}

nonisolated struct GoalRollup: Codable, Equatable, FetchableRecord, Sendable {
    let goalID: Int64
    let duration: Int

    enum CodingKeys: String, CodingKey {
        case goalID = "goal_id"
        case duration
    }
}

nonisolated struct DailyGoalDuration: Codable, Equatable, FetchableRecord, Sendable {
    let goalID: Int64
    let day: Date
    let duration: Int

    enum CodingKeys: String, CodingKey {
        case goalID = "goal_id"
        case day
        case duration
    }
}

nonisolated struct DailyCompletedTodoCount: Codable, Equatable, FetchableRecord, Sendable {
    let goalID: Int64?
    let day: Date
    let completedCount: Int

    enum CodingKeys: String, CodingKey {
        case goalID = "goal_id"
        case day
        case completedCount = "completed_count"
    }
}

nonisolated struct GoalActivityAssignment: Codable, Equatable, FetchableRecord, Sendable, Identifiable {
    let id: Int64
    let startTime: Date
    let application: String
    let summary: String?
    let goalTodoID: Int64?
    let duration: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case application
        case summary
        case goalTodoID = "goal_todo_id"
        case duration
    }
}

nonisolated struct GoalsSnapshot: Equatable, Sendable {
    let goals: [GoalRecord]
    let todos: [GoalTodoRecord]
    let goalRollups: [GoalRollup]
    let todoRollups: [GoalTodoRollup]
    let dailyGoalDurations: [DailyGoalDuration]
    let dailyCompletedTodoCounts: [DailyCompletedTodoCount]
}

struct ScreenshotRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "screenshots"

    let id: Int64
    let image: Data?
    let ts: Date?
    let description: String?
    let ocrText: String?
    let summary: String?
    let descriptionVector: Data?
    let ignoreReason: String?
    let jsonProperties: String?
    let activityID: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case image
        case ts
        case description
        case ocrText = "ocr_text"
        case summary
        case descriptionVector = "description_vector"
        case ignoreReason = "ignore_reason"
        case jsonProperties = "json_properties"
        case activityID = "activity_id"
    }
}

struct ActivityInput: Equatable {
    let id: Int64
    let startTime: Date
    let application: String
    let keystrokes: String?
    let microphone: String?
    let summary: String?
    let tagID: Int64?
    let jsonProperties: String?
    let overviewID: Int64?
}

struct ScreenshotInput: Equatable {
    let id: Int64
    let image: Data?
    let timestamp: Date?
    let description: String?
    let text: String?
    let summary: String?
    let ignoreReason: String?
    let jsonProperties: String?

    init(
        id: Int64,
        image: Data?,
        timestamp: Date?,
        description: String?,
        text: String?,
        summary: String? = nil,
        ignoreReason: String?,
        jsonProperties: String?
    ) {
        self.id = id
        self.image = image
        self.timestamp = timestamp
        self.description = description
        self.text = text
        self.summary = summary
        self.ignoreReason = ignoreReason
        self.jsonProperties = jsonProperties
    }
}

struct OverviewInput: Equatable {
    let id: Int64
    let title: String?
    let summary: String?
    let jsonProperties: String?
    let editedDuration: Int?
    let tagID: Int64?
    let originKind: String?
    let generatedTitle: String?
    let generatedSummary: String?
    let titleIsUserEdited: Bool?
    let summaryIsUserEdited: Bool?

    nonisolated init(
        id: Int64,
        title: String?,
        summary: String?,
        jsonProperties: String?,
        editedDuration: Int?,
        tagID: Int64?,
        originKind: String? = nil,
        generatedTitle: String? = nil,
        generatedSummary: String? = nil,
        titleIsUserEdited: Bool? = nil,
        summaryIsUserEdited: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.jsonProperties = jsonProperties
        self.editedDuration = editedDuration
        self.tagID = tagID
        self.originKind = originKind
        self.generatedTitle = generatedTitle
        self.generatedSummary = generatedSummary
        self.titleIsUserEdited = titleIsUserEdited
        self.summaryIsUserEdited = summaryIsUserEdited
    }
}

nonisolated struct TagInput: Equatable, Sendable {
    let id: Int64
    let name: String?
    let description: String?
    let createDate: Date?
    let deleteDate: Date?
    let jsonProperties: String?
    let originKind: String?
    let generatedName: String?
    let generatedDescription: String?
    let nameIsUserEdited: Bool?
    let descriptionIsUserEdited: Bool?

    init(
        id: Int64,
        name: String?,
        description: String?,
        createDate: Date?,
        deleteDate: Date?,
        jsonProperties: String?,
        originKind: String? = nil,
        generatedName: String? = nil,
        generatedDescription: String? = nil,
        nameIsUserEdited: Bool? = nil,
        descriptionIsUserEdited: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createDate = createDate
        self.deleteDate = deleteDate
        self.jsonProperties = jsonProperties
        self.originKind = originKind
        self.generatedName = generatedName
        self.generatedDescription = generatedDescription
        self.nameIsUserEdited = nameIsUserEdited
        self.descriptionIsUserEdited = descriptionIsUserEdited
    }
}

struct ActivityAggregation: Codable, Equatable, FetchableRecord {
    let date: String
    let tagName: String?
    let duration: Int?

    enum CodingKeys: String, CodingKey {
        case date = "dt"
        case tagName = "tag_name"
        case duration
    }
}

nonisolated struct SearchResultTree: Codable, Equatable, Identifiable, Sendable {
    let id: Int64
    let title: String?
    let summary: String?
    let jsonProperties: String?
    let editedDuration: Int?
    let tagID: Int64?
    let score: Float?
    let activities: [SearchResultActivity]

    init(
        id: Int64,
        title: String?,
        summary: String?,
        jsonProperties: String?,
        editedDuration: Int?,
        tagID: Int64?,
        score: Float? = nil,
        activities: [SearchResultActivity]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.jsonProperties = jsonProperties
        self.editedDuration = editedDuration
        self.tagID = tagID
        self.score = score
        self.activities = activities
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case jsonProperties = "json_properties"
        case editedDuration = "edited_duration"
        case tagID = "tag_id"
        case score
        case activities
    }
}

nonisolated struct KnowledgeNodeSearchResult: Codable, Equatable, FetchableRecord, Sendable, Identifiable {
    let id: Int64
    let name: String
    let normalizedName: String
    let kind: String?
    let description: String?
    let sourceChunkID: Int64?
    let createDate: Date
    let rank: Double

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case normalizedName = "normalized_name"
        case kind
        case description
        case sourceChunkID = "source_chunk_id"
        case createDate = "create_date"
        case rank
    }
}

nonisolated struct SearchResultActivity: Codable, Equatable, Identifiable, Sendable {
    let id: Int64
    let startTime: Date
    let application: String
    let keystrokes: String?
    let microphone: String?
    let summary: String?
    let tagID: Int64?
    let jsonProperties: String?
    let overviewID: Int64?
    let score: Float?
    let screenshots: [SearchResultScreenshot]

    init(
        id: Int64,
        startTime: Date,
        application: String,
        keystrokes: String?,
        microphone: String?,
        summary: String?,
        tagID: Int64?,
        jsonProperties: String?,
        overviewID: Int64?,
        score: Float? = nil,
        screenshots: [SearchResultScreenshot]
    ) {
        self.id = id
        self.startTime = startTime
        self.application = application
        self.keystrokes = keystrokes
        self.microphone = microphone
        self.summary = summary
        self.tagID = tagID
        self.jsonProperties = jsonProperties
        self.overviewID = overviewID
        self.score = score
        self.screenshots = screenshots
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case application
        case keystrokes
        case microphone
        case summary
        case tagID = "tag_id"
        case jsonProperties = "json_properties"
        case overviewID = "overview_id"
        case score
        case screenshots
    }
}

nonisolated struct SearchResultScreenshot: Codable, Equatable, Identifiable, Sendable {
    let id: Int64
    let image: Data?
    let ts: Date?
    let description: String?
    let ocrText: String?
    let summary: String?
    let descriptionVector: Data?
    let ignoreReason: String?
    let jsonProperties: String?
    let activityID: Int64
    let score: Float?

    init(
        id: Int64,
        image: Data?,
        ts: Date?,
        description: String?,
        ocrText: String?,
        summary: String? = nil,
        descriptionVector: Data?,
        ignoreReason: String?,
        jsonProperties: String?,
        activityID: Int64,
        score: Float? = nil
    ) {
        self.id = id
        self.image = image
        self.ts = ts
        self.description = description
        self.ocrText = ocrText
        self.summary = summary
        self.descriptionVector = descriptionVector
        self.ignoreReason = ignoreReason
        self.jsonProperties = jsonProperties
        self.activityID = activityID
        self.score = score
    }

    enum CodingKeys: String, CodingKey {
        case id
        case image
        case ts
        case description
        case ocrText = "ocr_text"
        case summary
        case descriptionVector = "description_vector"
        case ignoreReason = "ignore_reason"
        case jsonProperties = "json_properties"
        case activityID = "activity_id"
        case score
    }
}

nonisolated struct LoadedState: Equatable, Sendable {
    let activity: [LoadedActivity]
    let overview: [LoadedOverview]
    let tags: [LoadedTag]
}

nonisolated struct LoadedActivity: Equatable, Sendable {
    let id: Int64
    let startTime: Date
    let application: String
    let keystrokes: String?
    let microphone: String?
    let summary: String?
    let tagID: Int64?
    let overviewID: Int64?
    let tagAssignmentSource: ActivityTagAssignmentSource?
    let ontologyCandidateID: Int64?
    let overviewAssignmentSource: OverviewAssignmentSource?
    let goalTodoID: Int64?
    let goalTodoAssignmentSource: GoalTodoAssignmentSource?
    let goalTodoAssignmentScore: Double?
    var screenshots: [LoadedScreenshot]

    init(
        id: Int64,
        startTime: Date,
        application: String,
        keystrokes: String?,
        microphone: String?,
        summary: String?,
        tagID: Int64?,
        tagAssignmentSource: ActivityTagAssignmentSource?,
        ontologyCandidateID: Int64?,
        overviewAssignmentSource: OverviewAssignmentSource? = nil,
        overviewID: Int64?,
        goalTodoID: Int64? = nil,
        goalTodoAssignmentSource: GoalTodoAssignmentSource? = nil,
        goalTodoAssignmentScore: Double? = nil,
        screenshots: [LoadedScreenshot]
    ) {
        self.id = id
        self.startTime = startTime
        self.application = application
        self.keystrokes = keystrokes
        self.microphone = microphone
        self.summary = summary
        self.tagID = tagID
        self.tagAssignmentSource = tagAssignmentSource
        self.ontologyCandidateID = ontologyCandidateID
        self.overviewAssignmentSource = overviewAssignmentSource
        self.overviewID = overviewID
        self.goalTodoID = goalTodoID
        self.goalTodoAssignmentSource = goalTodoAssignmentSource
        self.goalTodoAssignmentScore = goalTodoAssignmentScore
        self.screenshots = screenshots
    }
}

nonisolated struct LoadedScreenshot: Equatable, Sendable {
    let id: Int64
    let image: Data?
    let timestamp: Date
    let description: String?
    let text: String?
    let summary: String?
    let ignoreReason: String?
}

nonisolated struct LoadedOverview: Codable, Equatable, FetchableRecord, Sendable {
    let id: Int64
    let title: String?
    let summary: String?
    let editedDuration: Int?
    let tagID: Int64?
    let originKind: OverviewOriginKind?
    let generatedTitle: String?
    let generatedSummary: String?
    let titleIsUserEdited: Bool
    let summaryIsUserEdited: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case editedDuration = "edited_duration"
        case tagID = "tag_id"
        case originKind = "origin_kind"
        case generatedTitle = "generated_title"
        case generatedSummary = "generated_summary"
        case titleIsUserEdited = "title_is_user_edited"
        case summaryIsUserEdited = "summary_is_user_edited"
    }

    init(
        id: Int64,
        title: String?,
        summary: String?,
        editedDuration: Int?,
        tagID: Int64?,
        originKind: OverviewOriginKind? = nil,
        generatedTitle: String? = nil,
        generatedSummary: String? = nil,
        titleIsUserEdited: Bool = false,
        summaryIsUserEdited: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.editedDuration = editedDuration
        self.tagID = tagID
        self.originKind = originKind
        self.generatedTitle = generatedTitle
        self.generatedSummary = generatedSummary
        self.titleIsUserEdited = titleIsUserEdited
        self.summaryIsUserEdited = summaryIsUserEdited
    }
}

nonisolated struct LoadedTag: Codable, Equatable, FetchableRecord, Sendable {
    let id: Int64
    let name: String?
    let description: String?
}

enum SQLDateError: Error {
    case invalidDate(String)
    case invalidTimestamp(String)
}

enum DatabaseEntity: Equatable {
    case activity(Activity)
    case screenshot(Screenshot)
    case overview(Overview)
    case tag(Tag)
    case agentAction(AgentAction)
    case knowledgeDirectory(KnowledgeDirectory)
    case knowledgeFile(KnowledgeFile)
    case knowledgeNode(KnowledgeNode)
    case knowledgeEdge(KnowledgeEdge)

    enum Activity: Equatable {
        case all
        case id(Int64)
        case record(ActivityInput)
    }

    enum Screenshot: Equatable {
        case all
        case id(Int64)
        case activityID(Int64)
        case record(activityID: Int64, ScreenshotInput)
    }

    enum Overview: Equatable {
        case all
        case id(Int64)
        case record(OverviewInput)
    }

    enum Tag: Equatable {
        case all
        case id(Int64)
        case record(TagInput)
    }

    enum AgentAction: Equatable {
        case all
        case id(Int64)
        case record(AgentActionInput)
    }

    enum KnowledgeDirectory: Equatable {
        case all
        case id(Int64)
        case record(KnowledgeDirectoryInput)
    }

    enum KnowledgeFile: Equatable {
        case directoryID(Int64)
        case directoryIDIncludingDeleted(Int64)
        case id(Int64)
        case record(KnowledgeFileInput)
    }

    enum KnowledgeNode: Equatable {
        case all
        case id(Int64)
        case normalizedName(String)
        case record(KnowledgeNodeInput)
    }

    enum KnowledgeEdge: Equatable {
        case all
        case id(Int64)
        case pair(Int64, Int64)
        case record(KnowledgeEdgeInput)
    }
}

enum DatabaseGetResult: Equatable {
    case activities([ActivityRecord])
    case activity(ActivityRecord?)
    case screenshots([ScreenshotRecord])
    case screenshot(ScreenshotRecord?)
    case overviews([OverviewRecord])
    case overview(OverviewRecord?)
    case tags([TagRecord])
    case agentActions([AgentActionRecord])
    case agentAction(AgentActionRecord?)
    case knowledgeDirectories([KnowledgeDirectoryRecord])
    case knowledgeDirectory(KnowledgeDirectoryRecord?)
    case knowledgeFiles([KnowledgeFileRecord])
    case knowledgeFile(KnowledgeFileRecord?)
    case knowledgeNodes([KnowledgeNodeRecord])
    case knowledgeNode(KnowledgeNodeRecord?)
    case knowledgeEdges([KnowledgeEdgeRecord])
    case knowledgeEdge(KnowledgeEdgeRecord?)
}

enum DatabaseRequestError: Error {
    case invalidGet
    case invalidSave
    case invalidDelete
}
