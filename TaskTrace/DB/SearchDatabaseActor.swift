//
//  SearchDatabaseActor.swift
//  TaskTrace
//
//  Created by Codex on 4/11/26.
//

import Foundation
import GRDB
import OSLog

nonisolated enum SearchMatchedNodeKind: String, Codable, Equatable, Sendable {
    case overview
    case activity
    case screenshot
}

nonisolated struct SearchMatchedNode: Codable, Equatable, Sendable {
    let kind: SearchMatchedNodeKind
    let id: Int64
    let rank: Double
}

nonisolated struct SearchDatabaseQueryResult: Codable, Equatable, Sendable {
    let trees: [SearchResultTree]
    let matchedNodes: [SearchMatchedNode]

    enum CodingKeys: String, CodingKey {
        case trees
        case matchedNodes = "matched_nodes"
    }
}

nonisolated struct SkillContextScreenshot: Equatable, Identifiable, Sendable {
    var id: String { "\(timestamp?.timeIntervalSince1970 ?? 0)-\(summary ?? description ?? "")" }
    let timestamp: Date?
    let summary: String?
    let description: String?
}

nonisolated struct SkillContextActivity: Equatable, Identifiable, Sendable {
    let id: Int64
    let startTime: Date
    let application: String
    let keystrokes: String
    let microphone: String
    let summary: String?
    let screenshots: [SkillContextScreenshot]
}

actor SearchDatabaseActor {
    private let database: TaskTraceDatabase
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "search-db")

    init(database: TaskTraceDatabase) {
        self.database = database
    }

    func skillContext(
        ftsQuery: String,
        queryVectorJSONString: String,
        day: Date,
        calendar: Calendar = .current,
        hybridScoreFloor: Double = Vars.skillContextHybridScoreFloor
    ) async throws -> [SkillContextActivity] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let trimmedFTSQuery = ftsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let activityFTSMatchesSQL = trimmedFTSQuery.isEmpty
            ? """
              SELECT
                  NULL AS activity_id,
                  NULL AS rank
              WHERE 0
              """
            : """
              SELECT
                  activities.id AS activity_id,
                  bm25(activity_fts) AS rank
              FROM activity_fts
              JOIN current_day_activities activities ON activities.id = activity_fts.rowid
              WHERE activity_fts MATCH ?
              """
        let screenshotFTSMatchesSQL = trimmedFTSQuery.isEmpty
            ? """
              SELECT
                  NULL AS activity_id,
                  NULL AS rank
              WHERE 0
              """
            : """
              SELECT
                  screenshots.activity_id AS activity_id,
                  bm25(screenshot_fts) AS rank
              FROM screenshot_fts
              JOIN screenshots ON screenshots.id = screenshot_fts.rowid
              JOIN current_day_activities activities ON activities.id = screenshots.activity_id
              WHERE screenshot_fts MATCH ?
              """
        let sql = """
            WITH
            current_day_activities AS (
                SELECT *
                FROM activities
                WHERE start_time >= ?
                  AND start_time < ?
            ),
            current_day_vector_count AS (
                SELECT COUNT(*) AS vector_count
                FROM current_day_activities
                WHERE summary_vector IS NOT NULL
            ),
            init_activity_vectors AS (
                SELECT vector_init(
                    'activities',
                    'summary_vector',
                    'type=FLOAT32,dimension=\(TaskTraceDatabaseBootstrap.activityEmbeddingDimension),distance=COSINE'
                )
            ),
            activity_fts_matches AS (
                \(activityFTSMatchesSQL)
            ),
            screenshot_fts_matches AS (
                \(screenshotFTSMatchesSQL)
            ),
            fts_matches AS (
                SELECT activity_id, MIN(rank) AS fts_rank
                FROM (
                    SELECT activity_id, rank FROM activity_fts_matches
                    UNION ALL
                    SELECT activity_id, rank FROM screenshot_fts_matches
                )
                WHERE activity_id IS NOT NULL
                GROUP BY activity_id
            ),
            vector_matches AS (
                SELECT
                    current_day_activities.id AS activity_id,
                    vector_hits.distance AS vector_distance
                FROM vector_full_scan(
                    'activities',
                    'summary_vector',
                    vector_as_f32(?),
                    MAX((SELECT vector_count FROM current_day_vector_count), 1)
                ) AS vector_hits,
                init_activity_vectors
                JOIN current_day_activities ON current_day_activities.id = vector_hits.id
            ),
            all_matches AS (
                SELECT
                    current_day_activities.id AS activity_id,
                    fts_matches.fts_rank AS fts_rank,
                    vector_matches.vector_distance AS vector_distance
                FROM current_day_activities
                LEFT JOIN fts_matches ON fts_matches.activity_id = current_day_activities.id
                LEFT JOIN vector_matches ON vector_matches.activity_id = current_day_activities.id
                WHERE fts_matches.activity_id IS NOT NULL
                   OR vector_matches.activity_id IS NOT NULL
            ),
            fts_bounds AS (
                SELECT MIN(fts_rank) AS min_rank, MAX(fts_rank) AS max_rank
                FROM all_matches
                WHERE fts_rank IS NOT NULL
            ),
            vector_bounds AS (
                SELECT MIN(vector_distance) AS min_distance, MAX(vector_distance) AS max_distance
                FROM all_matches
                WHERE vector_distance IS NOT NULL
            ),
            scored_matches AS (
                SELECT
                    activity_id,
                    CASE
                        WHEN fts_rank IS NULL THEN 0.0
                        WHEN (SELECT min_rank FROM fts_bounds) = (SELECT max_rank FROM fts_bounds) THEN 1.0
                        ELSE ((SELECT max_rank FROM fts_bounds) - fts_rank)
                             / NULLIF((SELECT max_rank FROM fts_bounds) - (SELECT min_rank FROM fts_bounds), 0)
                    END AS fts_score,
                    CASE
                        WHEN vector_distance IS NULL THEN 0.0
                        WHEN (SELECT min_distance FROM vector_bounds) = (SELECT max_distance FROM vector_bounds) THEN 1.0
                        ELSE ((SELECT max_distance FROM vector_bounds) - vector_distance)
                             / NULLIF((SELECT max_distance FROM vector_bounds) - (SELECT min_distance FROM vector_bounds), 0)
                    END AS vector_score
                FROM all_matches
            ),
            hybrid_matches AS (
                SELECT
                    activity_id,
                    fts_score,
                    vector_score,
                    ((vector_score * 0.55) + (fts_score * 0.45) + CASE
                        WHEN vector_score > 0 AND fts_score > 0 THEN 0.10
                        ELSE 0.0
                    END) AS hybrid_score
                FROM scored_matches
            )
            SELECT
                current_day_activities.id,
                current_day_activities.start_time,
                current_day_activities.application,
                current_day_activities.keystrokes,
                current_day_activities.microphone,
                current_day_activities.summary
            FROM hybrid_matches
            JOIN current_day_activities ON current_day_activities.id = hybrid_matches.activity_id
            WHERE hybrid_matches.hybrid_score >= ?
            ORDER BY current_day_activities.start_time ASC, current_day_activities.id ASC
            """
        let arguments: StatementArguments = {
            var values: [DatabaseValueConvertible?] = [
                dayStart.formatted(TaskTraceDatabase.sqlTimestampStyle),
                dayEnd.formatted(TaskTraceDatabase.sqlTimestampStyle)
            ]

            if !trimmedFTSQuery.isEmpty {
                values.append(trimmedFTSQuery)
                values.append(trimmedFTSQuery)
            }

            values.append(queryVectorJSONString)
            values.append(hybridScoreFloor)
            return StatementArguments(values)
        }()

        return try database.vectorAwareRead { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            let activityIDs = rows.map { $0["id"] as Int64 }
            let screenshotsByActivityID: [Int64: [SkillContextScreenshot]] = if activityIDs.isEmpty {
                [:]
            } else {
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT
                            ts,
                            summary,
                            description,
                            activity_id
                        FROM screenshots
                        WHERE activity_id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: activityIDs.count)))
                        ORDER BY activity_id ASC, ts ASC
                        """,
                    arguments: StatementArguments(activityIDs)
                )
                .reduce(into: [Int64: [SkillContextScreenshot]]()) { partial, row in
                    partial[row["activity_id"] as Int64, default: []].append(SkillContextScreenshot(
                        timestamp: row["ts"],
                        summary: row["summary"],
                        description: row["description"]
                    ))
                }
            }

            return rows.map { row in
                SkillContextActivity(
                    id: row["id"],
                    startTime: row["start_time"],
                    application: row["application"],
                    keystrokes: row["keystrokes"] ?? "",
                    microphone: row["microphone"] ?? "",
                    summary: row["summary"],
                    screenshots: screenshotsByActivityID[row["id"] as Int64] ?? []
                )
            }
        }
    }

    func dbSearch(
        query: String,
        limit: Int = 50,
        relevanceFloor: Double = -3
    ) async throws -> SearchDatabaseQueryResult {
        let resolvedLimit = max(1, min(limit, 50))
        let perSourceLimit = min(max(resolvedLimit * 3, 9), 45)
        let queryTermCount = query.components(separatedBy: " OR ").count
        let relevanceThreshold = relevanceFloor
        let logger = self.logger

        guard !query.isEmpty else {
            logger.log("dbSearch skipped empty query")
            return SearchDatabaseQueryResult(trees: [], matchedNodes: [])
        }

        return try database.read { db in
            let sqlStartedAt = Date()
            logger.log(
                "dbSearch SQL started queryCharacters=\(query.count, privacy: .public) queryTerms=\(queryTermCount, privacy: .public) relevanceThreshold=\(relevanceThreshold, privacy: .public) limit=\(resolvedLimit, privacy: .public) perSourceLimit=\(perSourceLimit, privacy: .public)"
            )
            let payloadJSON = try String.fetchOne(
                db,
                sql: """
                    WITH matched_overviews AS (
                        SELECT
                            'overview' AS match_kind,
                            rank,
                            overview_id,
                            NULL AS activity_id,
                            NULL AS screenshot_id
                        FROM (
                            SELECT
                                bm25(overview_fts) AS rank,
                                overviews.id AS overview_id
                            FROM overview_fts
                            JOIN overviews ON overviews.id = overview_fts.rowid
                            WHERE overview_fts MATCH ?
                        )
                        WHERE rank <= ?
                        ORDER BY rank ASC, overview_id ASC
                        LIMIT ?
                    ),
                    matched_activities AS (
                        SELECT
                            'activity' AS match_kind,
                            rank,
                            overview_id,
                            activity_id,
                            NULL AS screenshot_id
                        FROM (
                            SELECT
                                bm25(activity_fts) AS rank,
                                activities.overview_id AS overview_id,
                                activities.id AS activity_id
                            FROM activity_fts
                            JOIN activities ON activities.id = activity_fts.rowid
                            WHERE activity_fts MATCH ?
                        )
                        WHERE rank <= ?
                        ORDER BY rank ASC, activity_id ASC
                        LIMIT ?
                    ),
                    matched_screenshots AS (
                        SELECT
                            'screenshot' AS match_kind,
                            rank,
                            overview_id,
                            activity_id,
                            screenshot_id
                        FROM (
                            SELECT
                                bm25(screenshot_fts) AS rank,
                                activities.overview_id AS overview_id,
                                screenshots.activity_id AS activity_id,
                                screenshots.id AS screenshot_id
                            FROM screenshot_fts
                            JOIN screenshots ON screenshots.id = screenshot_fts.rowid
                            JOIN activities ON activities.id = screenshots.activity_id
                            WHERE screenshot_fts MATCH ?
                        )
                        WHERE rank <= ?
                        ORDER BY rank ASC, screenshot_id ASC
                        LIMIT ?
                    ),
                    all_candidates AS (
                        SELECT
                            match_kind,
                            rank,
                            overview_id,
                            activity_id,
                            screenshot_id
                        FROM matched_overviews

                        UNION ALL

                        SELECT
                            match_kind,
                            rank,
                            overview_id,
                            activity_id,
                            screenshot_id
                        FROM matched_activities

                        UNION ALL

                        SELECT
                            match_kind,
                            rank,
                            overview_id,
                            activity_id,
                            screenshot_id
                        FROM matched_screenshots
                    ),
                    top_overviews AS (
                        SELECT
                            overview_id,
                            MIN(rank) AS best_rank
                        FROM all_candidates
                        GROUP BY overview_id
                        ORDER BY best_rank ASC, overview_id ASC
                        LIMIT ?
                    ),
                    retained_candidates AS (
                        SELECT
                            all_candidates.match_kind,
                            all_candidates.rank,
                            all_candidates.overview_id,
                            all_candidates.activity_id,
                            all_candidates.screenshot_id
                        FROM all_candidates
                        JOIN top_overviews ON top_overviews.overview_id = all_candidates.overview_id
                    ),
                    matched_nodes_raw AS (
                        SELECT
                            match_kind,
                            rank,
                            overview_id,
                            activity_id,
                            screenshot_id,
                            CASE
                                WHEN match_kind = 'overview' THEN overview_id
                                WHEN match_kind = 'activity' THEN activity_id
                                ELSE screenshot_id
                            END AS matched_node_id
                        FROM retained_candidates
                    ),
                    matched_nodes AS (
                        SELECT
                            match_kind,
                            matched_node_id,
                            MIN(rank) AS rank,
                            MAX(overview_id) AS overview_id,
                            MAX(activity_id) AS activity_id,
                            MAX(screenshot_id) AS screenshot_id
                        FROM matched_nodes_raw
                        GROUP BY match_kind, matched_node_id
                    ),
                    ordered_matched_nodes AS (
                        SELECT
                            match_kind,
                            matched_node_id,
                            rank,
                            overview_id,
                            activity_id,
                            screenshot_id
                        FROM matched_nodes
                        ORDER BY rank ASC, matched_node_id ASC
                    ),
                    direct_overview_matches AS (
                        SELECT overview_id
                        FROM ordered_matched_nodes
                        WHERE match_kind = 'overview'
                    ),
                    direct_activity_matches AS (
                        SELECT activity_id
                        FROM ordered_matched_nodes
                        WHERE match_kind = 'activity'
                          AND activity_id IS NOT NULL
                    ),
                    direct_screenshot_matches AS (
                        SELECT screenshot_id, activity_id
                        FROM ordered_matched_nodes
                        WHERE match_kind = 'screenshot'
                          AND screenshot_id IS NOT NULL
                    ),
                    activity_match_candidates AS (
                        SELECT
                            overview_id,
                            activity_id,
                            MIN(rank) AS best_rank
                        FROM (
                            SELECT
                                overview_id,
                                activity_id,
                                rank
                            FROM ordered_matched_nodes
                            WHERE match_kind = 'activity'
                              AND activity_id IS NOT NULL

                            UNION ALL

                            SELECT
                                overview_id,
                                activity_id,
                                rank
                            FROM ordered_matched_nodes
                            WHERE match_kind = 'screenshot'
                              AND activity_id IS NOT NULL
                        )
                        GROUP BY overview_id, activity_id
                    ),
                    ranked_activities AS (
                        SELECT
                            activities.id AS activity_id,
                            activities.start_time AS activity_start_time,
                            activities.application AS activity_application,
                            activities.keystrokes AS activity_keystrokes,
                            activities.microphone AS activity_microphone,
                            activities.summary AS activity_summary,
                            activities.tag_id AS activity_tag_id,
                            activities.json_properties AS activity_json_properties,
                            activities.overview_id AS activity_overview_id,
                            ROW_NUMBER() OVER (
                                PARTITION BY activities.overview_id
                                ORDER BY activity_match_candidates.best_rank ASC, activities.start_time ASC, activities.id ASC
                            ) AS activity_position
                        FROM activities
                        JOIN activity_match_candidates ON activity_match_candidates.activity_id = activities.id
                        JOIN top_overviews ON top_overviews.overview_id = activity_match_candidates.overview_id
                    ),
                    included_activities AS (
                        SELECT
                            activity_id,
                            activity_start_time,
                            activity_application,
                            activity_keystrokes,
                            activity_microphone,
                            activity_summary,
                            activity_tag_id,
                            activity_json_properties,
                            activity_overview_id
                        FROM ranked_activities
                        WHERE activity_position <= 3
                    ),
                    ranked_screenshots AS (
                        SELECT
                            screenshots.id AS screenshot_id,
                            screenshots.ts AS screenshot_ts,
                            screenshots.description AS screenshot_description,
                            screenshots.ocr_text AS screenshot_ocr_text,
                            screenshots.summary AS screenshot_summary,
                            screenshots.ignore_reason AS screenshot_ignore_reason,
                            screenshots.json_properties AS screenshot_json_properties,
                            screenshots.activity_id AS screenshot_activity_id,
                            ROW_NUMBER() OVER (
                                PARTITION BY screenshots.activity_id
                                ORDER BY ordered_matched_nodes.rank ASC, screenshots.ts ASC, screenshots.id ASC
                            ) AS screenshot_position
                        FROM screenshots
                        JOIN included_activities ON included_activities.activity_id = screenshots.activity_id
                        JOIN direct_screenshot_matches ON direct_screenshot_matches.screenshot_id = screenshots.id
                        JOIN ordered_matched_nodes ON ordered_matched_nodes.match_kind = 'screenshot'
                            AND ordered_matched_nodes.screenshot_id = screenshots.id
                    ),
                    included_screenshots AS (
                        SELECT
                            screenshot_id,
                            screenshot_ts,
                            screenshot_description,
                            screenshot_ocr_text,
                            screenshot_summary,
                            screenshot_ignore_reason,
                            screenshot_json_properties,
                            screenshot_activity_id
                        FROM ranked_screenshots
                        WHERE screenshot_position <= 3
                    )
                    SELECT json_object(
                        'trees',
                        json(COALESCE((
                            SELECT json_group_array(json(tree_json))
                            FROM (
                                SELECT json_object(
                                    'id', overviews.id,
                                    'title', overviews.title,
                                    'summary', overviews.summary,
                                    'json_properties', overviews.json_properties,
                                    'edited_duration', overviews.edited_duration,
                                    'tag_id', overviews.tag_id,
                                    'activities',
                                    json(COALESCE((
                                        SELECT json_group_array(json(activity_json))
                                        FROM (
                                            SELECT json_object(
                                                'id', activity_rows.activity_id,
                                                'start_time', activity_rows.activity_start_time,
                                                'application', activity_rows.activity_application,
                                                'keystrokes', activity_rows.activity_keystrokes,
                                                'microphone', activity_rows.activity_microphone,
                                                'summary', activity_rows.activity_summary,
                                                'tag_id', activity_rows.activity_tag_id,
                                                'json_properties', activity_rows.activity_json_properties,
                                                'overview_id', activity_rows.activity_overview_id,
                                                'screenshots',
                                                json(COALESCE((
                                                    SELECT json_group_array(json(screenshot_json))
                                                    FROM (
                                                        SELECT json_object(
                                                            'id', screenshot_rows.screenshot_id,
                                                            'ts', screenshot_rows.screenshot_ts,
                                                            'description', screenshot_rows.screenshot_description,
                                                            'ocr_text', screenshot_rows.screenshot_ocr_text,
                                                            'summary', screenshot_rows.screenshot_summary,
                                                            'ignore_reason', screenshot_rows.screenshot_ignore_reason,
                                                            'json_properties', screenshot_rows.screenshot_json_properties,
                                                            'activity_id', screenshot_rows.screenshot_activity_id
                                                        ) AS screenshot_json
                                                        FROM (
                                                            SELECT
                                                                screenshot_id,
                                                                screenshot_ts,
                                                                screenshot_description,
                                                                screenshot_ocr_text,
                                                                screenshot_summary,
                                                                screenshot_ignore_reason,
                                                                screenshot_json_properties,
                                                                screenshot_activity_id
                                                            FROM included_screenshots
                                                            WHERE screenshot_activity_id = activity_rows.activity_id
                                                            ORDER BY screenshot_ts ASC, screenshot_id ASC
                                                        ) AS screenshot_rows
                                                    )
                                                ), '[]'))
                                            ) AS activity_json
                                            FROM (
                                                SELECT
                                                    activity_id,
                                                    activity_start_time,
                                                    activity_application,
                                                    activity_keystrokes,
                                                    activity_microphone,
                                                    activity_summary,
                                                    activity_tag_id,
                                                    activity_json_properties,
                                                    activity_overview_id
                                                FROM included_activities
                                                WHERE activity_overview_id = overviews.id
                                                ORDER BY activity_start_time ASC, activity_id ASC
                                            ) AS activity_rows
                                        )
                                    ), '[]'))
                                ) AS tree_json
                                FROM top_overviews
                                JOIN overviews ON overviews.id = top_overviews.overview_id
                                ORDER BY top_overviews.best_rank ASC, overviews.id ASC
                            )
                        ), '[]')),
                        'matched_nodes',
                        json(COALESCE((
                            SELECT json_group_array(json(node_json))
                            FROM (
                                SELECT json_object(
                                    'kind', match_kind,
                                    'id', matched_node_id,
                                    'rank', rank
                                ) AS node_json
                                FROM ordered_matched_nodes
                                ORDER BY rank ASC, matched_node_id ASC
                            )
                        ), '[]'))
                    )
                    """,
                arguments: [
                    query,
                    relevanceThreshold,
                    perSourceLimit,
                    query,
                    relevanceThreshold,
                    perSourceLimit,
                    query,
                    relevanceThreshold,
                    perSourceLimit,
                    resolvedLimit
                ]
            ) ?? #"{"trees":[],"matched_nodes":[]}"#
            logger.log(
                "dbSearch SQL finished durationMs=\(Int(Date().timeIntervalSince(sqlStartedAt) * 1000), privacy: .public) payloadCharacters=\(payloadJSON.count, privacy: .public)"
            )

            let decoder = JSONDecoder()

            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)

                if let timestamp = try? TaskTraceDatabase.date(fromSQLTimestamp: value) {
                    return timestamp
                }

                if let date = try? TaskTraceDatabase.date(fromSQLDate: value) {
                    return date
                }

                throw SQLDateError.invalidTimestamp(value)
            }

            let decodeStartedAt = Date()
            let result = try decoder.decode(SearchDatabaseQueryResult.self, from: Data(payloadJSON.utf8))
            logger.log(
                "dbSearch decode finished durationMs=\(Int(Date().timeIntervalSince(decodeStartedAt) * 1000), privacy: .public) resultCount=\(result.trees.count, privacy: .public) matchedNodeCount=\(result.matchedNodes.count, privacy: .public)"
            )
            return result
        }
    }
}
