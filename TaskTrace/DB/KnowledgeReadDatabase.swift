//
//  KnowledgeReadDatabase.swift
//  TaskTrace
//
//  Created by Codex on 4/11/26.
//

import Foundation
import GRDB

final class KnowledgeReadDatabase: @unchecked Sendable {
    // Reuse the two handles owned by TaskTraceDatabase instead of opening a
    // second read pool against the same file. Ordinary read models stay on the
    // shared pool, and the few vector-aware reads opt into the dedicated queue.
    nonisolated private let database: TaskTraceDatabase

    nonisolated init(database: TaskTraceDatabase) {
        self.database = database
    }

    nonisolated func loadKnowledgeFileSystemEntries(
        directoryID: Int64? = nil
    ) throws -> [KnowledgeFileSystemEntry] {
        try database.read { db in
            try KnowledgeFileSystemEntry.fetchAll(
                db,
                sql: """
                    WITH file_chunk_counts AS (
                        SELECT
                            knowledge_files.id AS file_id,
                            COUNT(knowledge_chunks.id) AS total_chunks,
                            COALESCE(SUM(CASE WHEN knowledge_chunks.processed = 1 THEN 1 ELSE 0 END), 0) AS processed_chunks
                        FROM knowledge_files
                        LEFT JOIN knowledge_anchors ON knowledge_anchors.file_id = knowledge_files.id
                        LEFT JOIN knowledge_chunks ON knowledge_chunks.anchor_id = knowledge_anchors.id
                        WHERE (? IS NULL OR knowledge_files.directory_id = ?)
                          AND knowledge_files.deleted_at IS NULL
                        GROUP BY knowledge_files.id
                    ),
                    file_node_counts AS (
                        SELECT
                            knowledge_files.id AS file_id,
                            COUNT(DISTINCT CASE
                                WHEN knowledge_nodes.description IS NOT NULL AND knowledge_nodes.description <> '' THEN knowledge_nodes.id
                                ELSE NULL
                            END) AS total_node_embeddings,
                            COUNT(DISTINCT CASE
                                WHEN knowledge_nodes.description IS NOT NULL
                                 AND knowledge_nodes.description <> ''
                                 AND knowledge_nodes.embedding IS NOT NULL
                                 AND knowledge_nodes.embedding <> '' THEN knowledge_nodes.id
                                ELSE NULL
                            END) AS embedded_node_count
                        FROM knowledge_files
                        LEFT JOIN knowledge_anchors ON knowledge_anchors.file_id = knowledge_files.id
                        LEFT JOIN knowledge_chunks ON knowledge_chunks.anchor_id = knowledge_anchors.id
                        LEFT JOIN knowledge_node_chunks ON knowledge_node_chunks.chunk_id = knowledge_chunks.id
                        LEFT JOIN knowledge_nodes ON knowledge_nodes.id = knowledge_node_chunks.node_id
                        WHERE (? IS NULL OR knowledge_files.directory_id = ?)
                          AND knowledge_files.deleted_at IS NULL
                        GROUP BY knowledge_files.id
                    )
                    SELECT
                        knowledge_files.id,
                        knowledge_files.directory_id,
                        knowledge_directories.slot AS source_slot,
                        knowledge_files.relative_path AS path,
                        knowledge_files.title,
                        knowledge_files.byte_count,
                        COALESCE(file_chunk_counts.total_chunks, 0) AS total_chunks,
                        COALESCE(file_chunk_counts.processed_chunks, 0) AS processed_chunks,
                        COALESCE(file_node_counts.total_node_embeddings, 0) AS total_node_embeddings,
                        COALESCE(file_node_counts.embedded_node_count, 0) AS embedded_node_count
                    FROM knowledge_files
                    JOIN knowledge_directories ON knowledge_directories.id = knowledge_files.directory_id
                    LEFT JOIN file_chunk_counts ON file_chunk_counts.file_id = knowledge_files.id
                    LEFT JOIN file_node_counts ON file_node_counts.file_id = knowledge_files.id
                    WHERE (? IS NULL OR knowledge_files.directory_id = ?)
                      AND knowledge_files.deleted_at IS NULL
                    ORDER BY knowledge_directories.slot ASC, knowledge_files.relative_path ASC, knowledge_files.id ASC
                    """,
                arguments: [
                    directoryID,
                    directoryID,
                    directoryID,
                    directoryID,
                    directoryID,
                    directoryID
                ]
            )
        }
    }

    nonisolated func loadKnowledgeFileDetail(
        fileID: Int64
    ) throws -> KnowledgeFileIndexSummary? {
        try database.read { db in
            guard let resolvedFileID = try Int64.fetchOne(
                db,
                sql: """
                    SELECT id
                    FROM knowledge_files
                    WHERE id = ?
                      AND deleted_at IS NULL
                    LIMIT 1
                    """,
                arguments: [fileID]
            ) else {
                return nil
            }

            let aliases = try String.fetchAll(
                db,
                sql: """
                    SELECT alias_text
                    FROM knowledge_aliases
                    WHERE file_id = ?
                    ORDER BY alias_text ASC
                    """,
                arguments: [resolvedFileID]
            )
            let chunkRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        anchor_id,
                        ordinal,
                        hash,
                        text
                    FROM knowledge_chunks
                    WHERE anchor_id IN (
                        SELECT id
                        FROM knowledge_anchors
                        WHERE file_id = ?
                    )
                    ORDER BY anchor_id ASC, ordinal ASC, id ASC
                    """,
                arguments: [resolvedFileID]
            )
            let chunksByAnchorID = chunkRows.reduce(into: [Int64: [KnowledgeScannedChunk]]()) { partial, row in
                guard let anchorID: Int64 = row["anchor_id"],
                      let ordinal: Int = row["ordinal"],
                      let hash: String = row["hash"],
                      let text: String = row["text"] else {
                    return
                }

                partial[anchorID, default: []].append(
                    KnowledgeScannedChunk(
                        ordinal: ordinal,
                        hash: hash,
                        text: text
                    )
                )
            }
            let anchors = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        id,
                        anchor_type,
                        anchor_key,
                        heading_text,
                        block_id,
                        start_line,
                        end_line,
                        text_hash
                    FROM knowledge_anchors
                    WHERE file_id = ?
                    ORDER BY start_line ASC, id ASC
                    """,
                arguments: [resolvedFileID]
            ).compactMap { row -> KnowledgeScannedAnchor? in
                guard let anchorID: Int64 = row["id"],
                      let anchorType: String = row["anchor_type"],
                      let anchorKey: String = row["anchor_key"],
                      let startLine: Int = row["start_line"],
                      let endLine: Int = row["end_line"],
                      let textHash: String = row["text_hash"] else {
                    return nil
                }

                return KnowledgeScannedAnchor(
                    anchorType: anchorType,
                    anchorKey: anchorKey,
                    headingText: row["heading_text"],
                    blockID: row["block_id"],
                    startLine: startLine,
                    endLine: endLine,
                    textHash: textHash,
                    chunks: chunksByAnchorID[anchorID] ?? []
                )
            }
            let links = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        knowledge_anchors.anchor_key AS src_anchor_key,
                        destination_files.relative_path AS dst_file_path,
                        knowledge_links.dst_anchor_hint AS dst_anchor_hint,
                        knowledge_links.link_text AS link_text,
                        knowledge_links.link_type AS link_type
                    FROM knowledge_links
                    JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_links.src_anchor_id
                    LEFT JOIN knowledge_files AS destination_files ON destination_files.id = knowledge_links.dst_file_id
                    WHERE knowledge_anchors.file_id = ?
                    ORDER BY knowledge_links.id ASC
                    """,
                arguments: [resolvedFileID]
            ).compactMap { row -> KnowledgeScannedLink? in
                guard let srcAnchorKey: String = row["src_anchor_key"],
                      let linkText: String = row["link_text"],
                      let linkType: String = row["link_type"] else {
                    return nil
                }

                return KnowledgeScannedLink(
                    srcAnchorKey: srcAnchorKey,
                    dstPathCandidate: row["dst_file_path"],
                    dstAnchorHint: row["dst_anchor_hint"],
                    linkText: linkText,
                    linkType: linkType
                )
            }

            return KnowledgeFileIndexSummary(
                aliases: aliases,
                anchors: anchors,
                links: links
            )
        }
    }

    nonisolated func loadKnowledgeGraphDirectorySnapshot(
        directoryID: Int64? = nil,
        activeDay: Date
    ) throws -> KnowledgeGraphDirectorySnapshot {
        try database.read { db in
            let startOfDay = Calendar(identifier: .gregorian).startOfDay(for: activeDay)
            let nextDay = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            let startSQL = startOfDay.formatted(TaskTraceDatabase.sqlTimestampStyle)
            let endSQL = nextDay.formatted(TaskTraceDatabase.sqlTimestampStyle)
            let fileLinks = try KnowledgeFileGraphLinkRecord.fetchAll(
                db,
                sql: """
                    SELECT
                        CASE
                            WHEN source_files.id < destination_files.id THEN source_files.id
                            ELSE destination_files.id
                        END AS source_file_id,
                        CASE
                            WHEN source_files.id < destination_files.id THEN destination_files.id
                            ELSE source_files.id
                        END AS target_file_id,
                        COUNT(knowledge_links.id) AS weight
                    FROM knowledge_links
                    JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_links.src_anchor_id
                    JOIN knowledge_files AS source_files ON source_files.id = knowledge_anchors.file_id
                    JOIN knowledge_files AS destination_files ON destination_files.id = knowledge_links.dst_file_id
                    WHERE (? IS NULL OR source_files.directory_id = ?)
                      AND source_files.deleted_at IS NULL
                      AND (? IS NULL OR destination_files.directory_id = ?)
                      AND destination_files.deleted_at IS NULL
                      AND source_files.id != destination_files.id
                    GROUP BY source_file_id, target_file_id
                    ORDER BY source_file_id ASC, target_file_id ASC
                    """,
                arguments: [directoryID, directoryID, directoryID, directoryID]
            )
            let overviews = try KnowledgeGraphOverviewEntry.fetchAll(
                db,
                sql: """
                    WITH day_activities AS (
                        SELECT
                            id,
                            overview_id,
                            start_time
                        FROM activities
                        WHERE start_time >= ?
                          AND start_time < ?
                          AND overview_id IS NOT NULL
                    ),
                    graph_activities AS (
                        SELECT day_activities.id, day_activities.overview_id, day_activities.start_time
                        FROM day_activities
                        WHERE EXISTS (
                            SELECT 1
                            FROM knowledge_node_activities
                            WHERE knowledge_node_activities.activity_id = day_activities.id
                        )
                        OR EXISTS (
                            SELECT 1
                            FROM knowledge_edge_activities
                            WHERE knowledge_edge_activities.activity_id = day_activities.id
                        )
                    )
                    SELECT
                        overviews.id,
                        COALESCE(NULLIF(TRIM(overviews.title), ''), 'Overview ' || overviews.id) AS title,
                        overviews.summary
                    FROM overviews
                    JOIN graph_activities ON graph_activities.overview_id = overviews.id
                    GROUP BY overviews.id
                    ORDER BY MIN(graph_activities.start_time) ASC, overviews.id ASC
                    """,
                arguments: [startSQL, endSQL]
            )
            let activities = try KnowledgeGraphActivityEntry.fetchAll(
                db,
                sql: """
                    WITH day_activities AS (
                        SELECT
                            activities.id,
                            activities.overview_id,
                            activities.application,
                            activities.summary,
                            activities.start_time
                        FROM activities
                        WHERE activities.start_time >= ?
                          AND activities.start_time < ?
                          AND activities.overview_id IS NOT NULL
                    )
                    SELECT
                        day_activities.id,
                        day_activities.overview_id,
                        day_activities.application,
                        day_activities.summary,
                        day_activities.start_time
                    FROM day_activities
                    WHERE EXISTS (
                        SELECT 1
                        FROM knowledge_node_activities
                        WHERE knowledge_node_activities.activity_id = day_activities.id
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM knowledge_edge_activities
                        WHERE knowledge_edge_activities.activity_id = day_activities.id
                    )
                    ORDER BY day_activities.start_time ASC, day_activities.id ASC
                    """,
                arguments: [startSQL, endSQL]
            )
            let knowledgeNodes = try KnowledgeGraphNodeEntry.fetchAll(
                db,
                sql: """
                    WITH
                    directory_nodes AS (
                        SELECT DISTINCT knowledge_node_chunks.node_id AS id
                        FROM knowledge_node_chunks
                        JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                        JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                        JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                        WHERE (? IS NULL OR knowledge_files.directory_id = ?)
                          AND knowledge_files.deleted_at IS NULL
                    ),
                    day_activities AS (
                        SELECT id
                        FROM activities
                        WHERE start_time >= ?
                          AND start_time < ?
                    ),
                    activity_nodes AS (
                        SELECT knowledge_node_activities.node_id AS id
                        FROM knowledge_node_activities
                        JOIN day_activities ON day_activities.id = knowledge_node_activities.activity_id
                        UNION
                        SELECT knowledge_edges.first_node_id AS id
                        FROM knowledge_edge_activities
                        JOIN day_activities ON day_activities.id = knowledge_edge_activities.activity_id
                        JOIN knowledge_edges ON knowledge_edges.id = knowledge_edge_activities.edge_id
                        UNION
                        SELECT knowledge_edges.second_node_id AS id
                        FROM knowledge_edge_activities
                        JOIN day_activities ON day_activities.id = knowledge_edge_activities.activity_id
                        JOIN knowledge_edges ON knowledge_edges.id = knowledge_edge_activities.edge_id
                    ),
                    visible_node_ids AS (
                        SELECT id FROM directory_nodes
                        UNION
                        SELECT id FROM activity_nodes
                    )
                    SELECT
                        knowledge_nodes.id,
                        knowledge_nodes.name,
                        knowledge_nodes.kind,
                        knowledge_nodes.description,
                        knowledge_nodes.community_id,
                        MIN(CASE
                            WHEN knowledge_files.deleted_at IS NULL THEN knowledge_files.relative_path
                            ELSE NULL
                        END) AS source_path
                    FROM knowledge_nodes
                    LEFT JOIN knowledge_node_chunks ON knowledge_node_chunks.node_id = knowledge_nodes.id
                    LEFT JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                    LEFT JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                    LEFT JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                    WHERE knowledge_nodes.id IN (SELECT id FROM visible_node_ids)
                    GROUP BY knowledge_nodes.id
                    ORDER BY knowledge_nodes.normalized_name ASC, knowledge_nodes.id ASC
                    """,
                arguments: [directoryID, directoryID, startSQL, endSQL]
            )
            let knowledgeEdges = try KnowledgeEdgeRecord.fetchAll(
                db,
                sql: """
                    WITH
                    directory_nodes AS (
                        SELECT DISTINCT knowledge_node_chunks.node_id AS id
                        FROM knowledge_node_chunks
                        JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                        JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                        JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                        WHERE (? IS NULL OR knowledge_files.directory_id = ?)
                          AND knowledge_files.deleted_at IS NULL
                    ),
                    day_activities AS (
                        SELECT id
                        FROM activities
                        WHERE start_time >= ?
                          AND start_time < ?
                    ),
                    activity_nodes AS (
                        SELECT knowledge_node_activities.node_id AS id
                        FROM knowledge_node_activities
                        JOIN day_activities ON day_activities.id = knowledge_node_activities.activity_id
                        UNION
                        SELECT knowledge_edges.first_node_id AS id
                        FROM knowledge_edge_activities
                        JOIN day_activities ON day_activities.id = knowledge_edge_activities.activity_id
                        JOIN knowledge_edges ON knowledge_edges.id = knowledge_edge_activities.edge_id
                        UNION
                        SELECT knowledge_edges.second_node_id AS id
                        FROM knowledge_edge_activities
                        JOIN day_activities ON day_activities.id = knowledge_edge_activities.activity_id
                        JOIN knowledge_edges ON knowledge_edges.id = knowledge_edge_activities.edge_id
                    ),
                    visible_node_ids AS (
                        SELECT id FROM directory_nodes
                        UNION
                        SELECT id FROM activity_nodes
                    )
                    SELECT knowledge_edges.*
                    FROM knowledge_edges
                    JOIN visible_node_ids AS first_nodes ON first_nodes.id = knowledge_edges.first_node_id
                    JOIN visible_node_ids AS second_nodes ON second_nodes.id = knowledge_edges.second_node_id
                    ORDER BY knowledge_edges.first_node_id ASC, knowledge_edges.second_node_id ASC, knowledge_edges.id ASC
                    """,
                arguments: [directoryID, directoryID, startSQL, endSQL]
            )
            let communities = try KnowledgeCommunityRecord.fetchAll(
                db,
                sql: """
                    WITH
                    directory_nodes AS (
                        SELECT DISTINCT knowledge_node_chunks.node_id AS id
                        FROM knowledge_node_chunks
                        JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                        JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                        JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                        WHERE (? IS NULL OR knowledge_files.directory_id = ?)
                          AND knowledge_files.deleted_at IS NULL
                    ),
                    day_activities AS (
                        SELECT id
                        FROM activities
                        WHERE start_time >= ?
                          AND start_time < ?
                    ),
                    activity_nodes AS (
                        SELECT knowledge_node_activities.node_id AS id
                        FROM knowledge_node_activities
                        JOIN day_activities ON day_activities.id = knowledge_node_activities.activity_id
                        UNION
                        SELECT knowledge_edges.first_node_id AS id
                        FROM knowledge_edge_activities
                        JOIN day_activities ON day_activities.id = knowledge_edge_activities.activity_id
                        JOIN knowledge_edges ON knowledge_edges.id = knowledge_edge_activities.edge_id
                        UNION
                        SELECT knowledge_edges.second_node_id AS id
                        FROM knowledge_edge_activities
                        JOIN day_activities ON day_activities.id = knowledge_edge_activities.activity_id
                        JOIN knowledge_edges ON knowledge_edges.id = knowledge_edge_activities.edge_id
                    ),
                    visible_node_ids AS (
                        SELECT id FROM directory_nodes
                        UNION
                        SELECT id FROM activity_nodes
                    )
                    SELECT knowledge_communities.*
                    FROM knowledge_communities
                    WHERE knowledge_communities.id IN (
                        SELECT DISTINCT knowledge_nodes.community_id
                        FROM knowledge_nodes
                        WHERE knowledge_nodes.id IN (SELECT id FROM visible_node_ids)
                          AND knowledge_nodes.community_id IS NOT NULL
                    )
                    ORDER BY knowledge_communities.id ASC
                    """,
                arguments: [directoryID, directoryID, startSQL, endSQL]
            )

            return KnowledgeGraphDirectorySnapshot(
                fileLinks: fileLinks,
                knowledgeNodes: knowledgeNodes,
                knowledgeEdges: knowledgeEdges,
                communities: communities,
                overviews: overviews,
                activities: activities
            )
        }
    }

    nonisolated func loadKnowledgeGraphBuildProgress(
        directoryID: Int64? = nil,
        activeDay: Date
    ) throws -> KnowledgeGraphBuildProgress {
        try database.read { db in
            let startOfDay = Calendar(identifier: .gregorian).startOfDay(for: activeDay)
            let nextDay = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            let startSQL = startOfDay.formatted(TaskTraceDatabase.sqlTimestampStyle)
            let endSQL = nextDay.formatted(TaskTraceDatabase.sqlTimestampStyle)
            let row = try Row.fetchOne(
                db,
                sql: """
                    WITH directory_chunks AS (
                        SELECT knowledge_chunks.id, knowledge_chunks.processed
                        FROM knowledge_chunks
                        JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                        JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                        WHERE (? IS NULL OR knowledge_files.directory_id = ?)
                          AND knowledge_files.deleted_at IS NULL
                    ),
                    day_activities AS (
                        SELECT id, overview_id, knowledge_processed
                        FROM activities
                        WHERE start_time >= ?
                          AND start_time < ?
                          AND overview_id IS NOT NULL
                    ),
                    day_overviews AS (
                        SELECT
                            overviews.id,
                            overviews.knowledge_processed
                        FROM overviews
                        JOIN day_activities ON day_activities.overview_id = overviews.id
                        GROUP BY overviews.id
                    )
                    SELECT
                        COALESCE((SELECT COUNT(*) FROM directory_chunks), 0) AS total_chunks,
                        COALESCE((SELECT COUNT(*) FROM directory_chunks WHERE processed = 1), 0) AS processed_chunks,
                        COALESCE((SELECT COUNT(*) FROM day_activities), 0) AS total_activities,
                        COALESCE((SELECT COUNT(*) FROM day_activities WHERE knowledge_processed = 1), 0) AS processed_activities,
                        COALESCE((SELECT COUNT(*) FROM day_overviews), 0) AS total_overviews,
                        COALESCE((SELECT COUNT(*) FROM day_overviews WHERE knowledge_processed = 1), 0) AS processed_overviews
                    """,
                arguments: [directoryID, directoryID, startSQL, endSQL]
            )

            return KnowledgeGraphBuildProgress(
                totalChunks: row?["total_chunks"] ?? 0,
                processedChunks: row?["processed_chunks"] ?? 0,
                totalActivities: row?["total_activities"] ?? 0,
                processedActivities: row?["processed_activities"] ?? 0,
                totalOverviews: row?["total_overviews"] ?? 0,
                processedOverviews: row?["processed_overviews"] ?? 0
            )
        }
    }

    nonisolated func loadKnowledgeBridgeLinks(
        directoryID: Int64?,
        fileID: Int64? = nil,
        nodeID: Int64? = nil
    ) throws -> [KnowledgeBridgeLinkRecord] {
        try database.read { db in
            try KnowledgeBridgeLinkRecord.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT
                        knowledge_files.id AS file_id,
                        knowledge_node_chunks.node_id AS node_id
                    FROM knowledge_node_chunks
                    JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                    JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                    JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                    WHERE knowledge_files.deleted_at IS NULL
                      AND (? IS NULL OR knowledge_files.directory_id = ?)
                      AND (? IS NULL OR knowledge_files.id = ?)
                      AND (? IS NULL OR knowledge_node_chunks.node_id = ?)
                    ORDER BY knowledge_files.id ASC, knowledge_node_chunks.node_id ASC
                    """,
                arguments: [directoryID, directoryID, fileID, fileID, nodeID, nodeID]
            )
        }
    }

    nonisolated func loadKnowledgeCommunityLinks(
        directoryID: Int64?,
        activeDay: Date,
        communityID: Int64
    ) throws -> [KnowledgeCommunityLinkRecord] {
        try database.read { db in
            let startOfDay = Calendar(identifier: .gregorian).startOfDay(for: activeDay)
            let nextDay = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            let startSQL = startOfDay.formatted(TaskTraceDatabase.sqlTimestampStyle)
            let endSQL = nextDay.formatted(TaskTraceDatabase.sqlTimestampStyle)
            return try KnowledgeCommunityLinkRecord.fetchAll(
                db,
                sql: """
                    WITH
                    directory_nodes AS (
                        SELECT DISTINCT knowledge_node_chunks.node_id AS id
                        FROM knowledge_node_chunks
                        JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                        JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                        JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                        WHERE (? IS NULL OR knowledge_files.directory_id = ?)
                          AND knowledge_files.deleted_at IS NULL
                    ),
                    day_activities AS (
                        SELECT id
                        FROM activities
                        WHERE start_time >= ?
                          AND start_time < ?
                    ),
                    activity_nodes AS (
                        SELECT knowledge_node_activities.node_id AS id
                        FROM knowledge_node_activities
                        JOIN day_activities ON day_activities.id = knowledge_node_activities.activity_id
                        UNION
                        SELECT knowledge_edges.first_node_id AS id
                        FROM knowledge_edge_activities
                        JOIN day_activities ON day_activities.id = knowledge_edge_activities.activity_id
                        JOIN knowledge_edges ON knowledge_edges.id = knowledge_edge_activities.edge_id
                        UNION
                        SELECT knowledge_edges.second_node_id AS id
                        FROM knowledge_edge_activities
                        JOIN day_activities ON day_activities.id = knowledge_edge_activities.activity_id
                        JOIN knowledge_edges ON knowledge_edges.id = knowledge_edge_activities.edge_id
                    ),
                    visible_node_ids AS (
                        SELECT id FROM directory_nodes
                        UNION
                        SELECT id FROM activity_nodes
                    )
                    SELECT DISTINCT
                        knowledge_nodes.community_id AS community_id,
                        knowledge_nodes.id AS node_id
                    FROM knowledge_nodes
                    WHERE knowledge_nodes.community_id = ?
                      AND knowledge_nodes.id IN (SELECT id FROM visible_node_ids)
                    ORDER BY knowledge_nodes.id ASC
                    """,
                arguments: [directoryID, directoryID, startSQL, endSQL, communityID]
            )
        }
    }

    nonisolated func loadKnowledgeActivityLinks(
        activityID: Int64
    ) throws -> [KnowledgeActivityLinkRecord] {
        try database.read { db in
            try KnowledgeActivityLinkRecord.fetchAll(
                db,
                sql: """
                    WITH linked_nodes AS (
                        SELECT
                            knowledge_node_activities.activity_id AS activity_id,
                            knowledge_node_activities.node_id AS node_id
                        FROM knowledge_node_activities
                        WHERE knowledge_node_activities.activity_id = ?
                        UNION
                        SELECT
                            knowledge_edge_activities.activity_id AS activity_id,
                            knowledge_edges.first_node_id AS node_id
                        FROM knowledge_edge_activities
                        JOIN knowledge_edges ON knowledge_edges.id = knowledge_edge_activities.edge_id
                        WHERE knowledge_edge_activities.activity_id = ?
                        UNION
                        SELECT
                            knowledge_edge_activities.activity_id AS activity_id,
                            knowledge_edges.second_node_id AS node_id
                        FROM knowledge_edge_activities
                        JOIN knowledge_edges ON knowledge_edges.id = knowledge_edge_activities.edge_id
                        WHERE knowledge_edge_activities.activity_id = ?
                    )
                    SELECT DISTINCT
                        activity_id,
                        node_id
                    FROM linked_nodes
                    ORDER BY node_id ASC
                    """,
                arguments: [activityID, activityID, activityID]
            )
        }
    }

    nonisolated func loadKnowledgeOverviewLinks(
        overviewID: Int64,
        activeDay: Date
    ) throws -> [KnowledgeOverviewLinkRecord] {
        try database.read { db in
            let startOfDay = Calendar(identifier: .gregorian).startOfDay(for: activeDay)
            let nextDay = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            let startSQL = startOfDay.formatted(TaskTraceDatabase.sqlTimestampStyle)
            let endSQL = nextDay.formatted(TaskTraceDatabase.sqlTimestampStyle)

            return try KnowledgeOverviewLinkRecord.fetchAll(
                db,
                sql: """
                    WITH overview_activities AS (
                        SELECT id
                        FROM activities
                        WHERE overview_id = ?
                          AND start_time >= ?
                          AND start_time < ?
                    ),
                    linked_nodes AS (
                        SELECT knowledge_node_activities.node_id AS node_id
                        FROM knowledge_node_activities
                        JOIN overview_activities ON overview_activities.id = knowledge_node_activities.activity_id
                        UNION
                        SELECT knowledge_edges.first_node_id AS node_id
                        FROM knowledge_edge_activities
                        JOIN overview_activities ON overview_activities.id = knowledge_edge_activities.activity_id
                        JOIN knowledge_edges ON knowledge_edges.id = knowledge_edge_activities.edge_id
                        UNION
                        SELECT knowledge_edges.second_node_id AS node_id
                        FROM knowledge_edge_activities
                        JOIN overview_activities ON overview_activities.id = knowledge_edge_activities.activity_id
                        JOIN knowledge_edges ON knowledge_edges.id = knowledge_edge_activities.edge_id
                    )
                    SELECT DISTINCT
                        ? AS overview_id,
                        linked_nodes.node_id AS node_id
                    FROM linked_nodes
                    ORDER BY linked_nodes.node_id ASC
                    """,
                arguments: [overviewID, startSQL, endSQL, overviewID]
            )
        }
    }

    nonisolated func loadKnowledgeClaims(nodeID: Int64) throws -> [KnowledgeClaimRecord] {
        try database.read { db in
            try KnowledgeClaimRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM knowledge_claims
                    WHERE node_id = ?
                    ORDER BY create_date ASC, id ASC
                    """,
                arguments: [nodeID]
            )
        }
    }

    nonisolated func loadGraphRAGCandidates(
        directoryID: Int64?,
        ftsQuery: String,
        queryVectorJSONString: String,
        perSourceLimit: Int,
        totalLimit: Int
    ) throws -> [GraphRAGHybridCandidateRow] {
        // This path runs on the dedicated vector-aware connection because the
        // current hybrid retrieval query uses sqlite-vector helpers today and
        // will move to vectorlite-backed ANN tables next. Either way, the
        // vector extension state is connection-local and must not ride the
        // pooled read connections.
        try database.vectorAwareRead { db in
            try GraphRAGHybridCandidateRow.fetchAll(
                db,
                sql: """
                    WITH
                    init_community_vectors AS (
                        SELECT vector_init(
                            'knowledge_communities',
                            'embedding',
                            'type=FLOAT32,dimension=1024,distance=COSINE'
                        )
                    ),
                    init_node_vectors AS (
                        SELECT vector_init(
                            'knowledge_nodes',
                            'embedding',
                            'type=FLOAT32,dimension=1024,distance=COSINE'
                        )
                    ),
                    init_claim_vectors AS (
                        SELECT vector_init(
                            'knowledge_claims',
                            'embedding',
                            'type=FLOAT32,dimension=1024,distance=COSINE'
                        )
                    ),
                    scoped_nodes AS (
                        SELECT DISTINCT
                            knowledge_nodes.id,
                            knowledge_nodes.community_id
                        FROM knowledge_nodes
                        LEFT JOIN knowledge_node_chunks ON knowledge_node_chunks.node_id = knowledge_nodes.id
                        LEFT JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                        LEFT JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                        LEFT JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                        WHERE ? IS NULL
                           OR (
                                knowledge_files.directory_id = ?
                                AND knowledge_files.deleted_at IS NULL
                           )
                    ),
                    scoped_community_ids AS (
                        SELECT DISTINCT community_id AS id
                        FROM scoped_nodes
                        WHERE community_id IS NOT NULL
                    ),
                    community_fts_matches AS (
                        SELECT
                            'community' AS entity_type,
                            knowledge_communities.id AS entity_id,
                            NULL AS node_id,
                            knowledge_communities.id AS community_id,
                            COALESCE(NULLIF(TRIM(knowledge_communities.name), ''), 'Community ' || knowledge_communities.id) AS title,
                            COALESCE(knowledge_communities.summary, '') AS description,
                            bm25(knowledge_community_fts) AS fts_rank,
                            NULL AS vector_distance
                        FROM knowledge_community_fts, init_community_vectors
                        JOIN knowledge_communities ON knowledge_communities.id = knowledge_community_fts.rowid
                        WHERE knowledge_community_fts MATCH ?
                          AND (
                                ? IS NULL
                                OR knowledge_communities.id IN (SELECT id FROM scoped_community_ids)
                          )
                        ORDER BY fts_rank ASC
                        LIMIT ?
                    ),
                    community_vector_matches AS (
                        SELECT
                            'community' AS entity_type,
                            knowledge_communities.id AS entity_id,
                            NULL AS node_id,
                            knowledge_communities.id AS community_id,
                            COALESCE(NULLIF(TRIM(knowledge_communities.name), ''), 'Community ' || knowledge_communities.id) AS title,
                            COALESCE(knowledge_communities.summary, '') AS description,
                            NULL AS fts_rank,
                            vector_hits.distance AS vector_distance
                        FROM vector_full_scan('knowledge_communities', 'embedding', vector_as_f32(?), ?) AS vector_hits, init_community_vectors
                        JOIN knowledge_communities ON knowledge_communities.id = vector_hits.id
                        WHERE (
                                ? IS NULL
                                OR knowledge_communities.id IN (SELECT id FROM scoped_community_ids)
                              )
                    ),
                    node_fts_matches AS (
                        SELECT
                            'node' AS entity_type,
                            knowledge_nodes.id AS entity_id,
                            knowledge_nodes.id AS node_id,
                            knowledge_nodes.community_id AS community_id,
                            knowledge_nodes.name AS title,
                            COALESCE(knowledge_nodes.description, '') AS description,
                            bm25(knowledge_node_fts) AS fts_rank,
                            NULL AS vector_distance
                        FROM knowledge_node_fts, init_node_vectors
                        JOIN knowledge_nodes ON knowledge_nodes.id = knowledge_node_fts.rowid
                        WHERE knowledge_node_fts MATCH ?
                          AND (
                                ? IS NULL
                                OR knowledge_nodes.id IN (SELECT id FROM scoped_nodes)
                              )
                        ORDER BY fts_rank ASC
                        LIMIT ?
                    ),
                    node_vector_matches AS (
                        SELECT
                            'node' AS entity_type,
                            knowledge_nodes.id AS entity_id,
                            knowledge_nodes.id AS node_id,
                            knowledge_nodes.community_id AS community_id,
                            knowledge_nodes.name AS title,
                            COALESCE(knowledge_nodes.description, '') AS description,
                            NULL AS fts_rank,
                            vector_hits.distance AS vector_distance
                        FROM vector_full_scan('knowledge_nodes', 'embedding', vector_as_f32(?), ?) AS vector_hits, init_node_vectors
                        JOIN knowledge_nodes ON knowledge_nodes.id = vector_hits.id
                        WHERE (
                                ? IS NULL
                                OR knowledge_nodes.id IN (SELECT id FROM scoped_nodes)
                              )
                    ),
                    claim_fts_matches AS (
                        SELECT
                            'claim' AS entity_type,
                            knowledge_claims.id AS entity_id,
                            knowledge_claims.node_id AS node_id,
                            knowledge_nodes.community_id AS community_id,
                            knowledge_nodes.name AS title,
                            knowledge_claims.text AS description,
                            bm25(knowledge_claim_fts) AS fts_rank,
                            NULL AS vector_distance
                        FROM knowledge_claim_fts, init_claim_vectors
                        JOIN knowledge_claims ON knowledge_claims.id = knowledge_claim_fts.rowid
                        JOIN knowledge_nodes ON knowledge_nodes.id = knowledge_claims.node_id
                        WHERE knowledge_claim_fts MATCH ?
                          AND (
                                ? IS NULL
                                OR knowledge_claims.node_id IN (SELECT id FROM scoped_nodes)
                              )
                        ORDER BY fts_rank ASC
                        LIMIT ?
                    ),
                    claim_vector_matches AS (
                        SELECT
                            'claim' AS entity_type,
                            knowledge_claims.id AS entity_id,
                            knowledge_claims.node_id AS node_id,
                            knowledge_nodes.community_id AS community_id,
                            knowledge_nodes.name AS title,
                            knowledge_claims.text AS description,
                            NULL AS fts_rank,
                            vector_hits.distance AS vector_distance
                        FROM vector_full_scan('knowledge_claims', 'embedding', vector_as_f32(?), ?) AS vector_hits, init_claim_vectors
                        JOIN knowledge_claims ON knowledge_claims.id = vector_hits.id
                        JOIN knowledge_nodes ON knowledge_nodes.id = knowledge_claims.node_id
                        WHERE (
                                ? IS NULL
                                OR knowledge_claims.node_id IN (SELECT id FROM scoped_nodes)
                              )
                    ),
                    all_matches AS (
                        SELECT * FROM community_fts_matches
                        UNION ALL
                        SELECT * FROM community_vector_matches
                        UNION ALL
                        SELECT * FROM node_fts_matches
                        UNION ALL
                        SELECT * FROM node_vector_matches
                        UNION ALL
                        SELECT * FROM claim_fts_matches
                        UNION ALL
                        SELECT * FROM claim_vector_matches
                    ),
                    fts_bounds AS (
                        SELECT
                            MIN(fts_rank) AS min_rank,
                            MAX(fts_rank) AS max_rank
                        FROM all_matches
                        WHERE fts_rank IS NOT NULL
                    ),
                    vector_bounds AS (
                        SELECT
                            MIN(vector_distance) AS min_distance,
                            MAX(vector_distance) AS max_distance
                        FROM all_matches
                        WHERE vector_distance IS NOT NULL
                    ),
                    scored_matches AS (
                        SELECT
                            entity_type,
                            entity_id,
                            node_id,
                            community_id,
                            title,
                            description,
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
                    deduped_matches AS (
                        SELECT
                            entity_type,
                            entity_id,
                            node_id,
                            community_id,
                            title,
                            description,
                            MAX(fts_score) AS fts_score,
                            MAX(vector_score) AS vector_score
                        FROM scored_matches
                        GROUP BY
                            entity_type,
                            entity_id,
                            node_id,
                            community_id,
                            title,
                            description
                    )
                    SELECT
                        entity_type,
                        entity_id,
                        node_id,
                        community_id,
                        title,
                        description,
                        (
                            (vector_score * 0.55)
                            + (fts_score * 0.45)
                            + CASE
                                WHEN vector_score > 0 AND fts_score > 0 THEN 0.10
                                ELSE 0.0
                              END
                        ) AS hybrid_score
                    FROM deduped_matches
                    ORDER BY hybrid_score DESC, entity_type ASC, entity_id ASC
                    LIMIT ?
                    """,
                arguments: [
                    directoryID,
                    directoryID,
                    ftsQuery,
                    directoryID,
                    perSourceLimit,
                    queryVectorJSONString,
                    perSourceLimit,
                    directoryID,
                    ftsQuery,
                    directoryID,
                    perSourceLimit,
                    queryVectorJSONString,
                    perSourceLimit,
                    directoryID,
                    ftsQuery,
                    directoryID,
                    perSourceLimit,
                    queryVectorJSONString,
                    perSourceLimit,
                    directoryID,
                    totalLimit
                ]
            )
        }
    }

    nonisolated func loadGraphRAGContext(
        directoryID: Int64?,
        communityIDs: [Int64],
        seedNodeIDs: [Int64],
        nodeLimit: Int,
        edgeLimit: Int,
        claimLimit: Int
    ) throws -> GraphRAGContext {
        guard !communityIDs.isEmpty || !seedNodeIDs.isEmpty else {
            return GraphRAGContext()
        }

        let communityPlaceholders = communityIDs.isEmpty
            ? "SELECT NULL AS id WHERE 0"
            : communityIDs.map { _ in "SELECT ? AS id" }.joined(separator: " UNION ALL ")
        let seedNodePlaceholders = seedNodeIDs.isEmpty
            ? "SELECT NULL AS id WHERE 0"
            : seedNodeIDs.map { _ in "SELECT ? AS id" }.joined(separator: " UNION ALL ")
        let arguments = StatementArguments(
            communityIDs.map { $0 as (any DatabaseValueConvertible)? }
            + seedNodeIDs.map { $0 as (any DatabaseValueConvertible)? }
            + [
                directoryID as (any DatabaseValueConvertible)?,
                directoryID as (any DatabaseValueConvertible)?,
                max(1, nodeLimit) as (any DatabaseValueConvertible)?,
                max(1, edgeLimit) as (any DatabaseValueConvertible)?,
                max(1, claimLimit) as (any DatabaseValueConvertible)?
            ]
        )

        return try database.read { db in
            let json = try String.fetchOne(
                db,
                sql: """
                    WITH
                    selected_communities AS (
                        \(communityPlaceholders)
                    ),
                    selected_seed_nodes AS (
                        \(seedNodePlaceholders)
                    ),
                    ranked_selected_nodes AS (
                        SELECT DISTINCT
                            knowledge_nodes.id,
                            knowledge_nodes.name,
                            knowledge_nodes.kind,
                            knowledge_nodes.description,
                            knowledge_nodes.community_id,
                            CASE
                                WHEN knowledge_nodes.id IN (SELECT id FROM selected_seed_nodes) THEN 0
                                ELSE 1
                            END AS seed_priority
                        FROM knowledge_nodes
                        LEFT JOIN knowledge_node_chunks ON knowledge_node_chunks.node_id = knowledge_nodes.id
                        LEFT JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                        LEFT JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                        LEFT JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                        WHERE (
                                knowledge_nodes.id IN (SELECT id FROM selected_seed_nodes)
                                OR knowledge_nodes.community_id IN (SELECT id FROM selected_communities)
                              )
                          AND (
                                ? IS NULL
                                OR (
                                    knowledge_files.directory_id = ?
                                    AND knowledge_files.deleted_at IS NULL
                                )
                              )
                    ),
                    selected_nodes AS (
                        SELECT
                            ranked_selected_nodes.id,
                            ranked_selected_nodes.name,
                            ranked_selected_nodes.kind,
                            ranked_selected_nodes.description,
                            ranked_selected_nodes.community_id
                        FROM ranked_selected_nodes
                        ORDER BY
                            ranked_selected_nodes.seed_priority ASC,
                            ranked_selected_nodes.community_id ASC,
                            ranked_selected_nodes.name ASC,
                            ranked_selected_nodes.id ASC
                        LIMIT ?
                    ),
                    selected_edges AS (
                        SELECT DISTINCT
                            knowledge_edges.id,
                            knowledge_edges.first_node_id,
                            knowledge_edges.second_node_id,
                            knowledge_edges.relationship_type,
                            knowledge_edges.description
                        FROM knowledge_edges
                        JOIN selected_nodes AS first_nodes ON first_nodes.id = knowledge_edges.first_node_id
                        JOIN selected_nodes AS second_nodes ON second_nodes.id = knowledge_edges.second_node_id
                        ORDER BY knowledge_edges.first_node_id ASC, knowledge_edges.second_node_id ASC, knowledge_edges.id ASC
                        LIMIT ?
                    ),
                    selected_claims AS (
                        SELECT
                            knowledge_claims.id,
                            knowledge_claims.node_id,
                            knowledge_claims.text
                        FROM knowledge_claims
                        WHERE knowledge_claims.node_id IN (SELECT id FROM selected_nodes)
                        ORDER BY knowledge_claims.node_id ASC, knowledge_claims.id ASC
                        LIMIT ?
                    )
                    SELECT json_object(
                        'communities',
                        COALESCE((
                            SELECT json_group_array(json(community_json))
                            FROM (
                                SELECT json_object(
                                    'id', knowledge_communities.id,
                                    'name', knowledge_communities.name,
                                    'summary', knowledge_communities.summary
                                ) AS community_json
                                FROM knowledge_communities
                                WHERE knowledge_communities.id IN (SELECT id FROM selected_communities)
                                ORDER BY knowledge_communities.id ASC
                            )
                        ), '[]'),
                        'nodes',
                        COALESCE((
                            SELECT json_group_array(json(node_json))
                            FROM (
                                SELECT json_object(
                                    'id', selected_nodes.id,
                                    'name', selected_nodes.name,
                                    'kind', selected_nodes.kind,
                                    'description', selected_nodes.description,
                                    'communityID', selected_nodes.community_id
                                ) AS node_json
                                FROM selected_nodes
                                ORDER BY selected_nodes.name ASC, selected_nodes.id ASC
                            )
                        ), '[]'),
                        'edges',
                        COALESCE((
                            SELECT json_group_array(json(edge_json))
                            FROM (
                                SELECT json_object(
                                    'id', selected_edges.id,
                                    'firstNodeID', selected_edges.first_node_id,
                                    'secondNodeID', selected_edges.second_node_id,
                                    'relationshipType', selected_edges.relationship_type,
                                    'description', selected_edges.description
                                ) AS edge_json
                                FROM selected_edges
                                ORDER BY selected_edges.first_node_id ASC, selected_edges.second_node_id ASC, selected_edges.id ASC
                            )
                        ), '[]'),
                        'claims',
                        COALESCE((
                            SELECT json_group_array(json(claim_json))
                            FROM (
                                SELECT json_object(
                                    'id', selected_claims.id,
                                    'nodeID', selected_claims.node_id,
                                    'text', selected_claims.text
                                ) AS claim_json
                                FROM selected_claims
                                ORDER BY selected_claims.node_id ASC, selected_claims.id ASC
                            )
                        ), '[]')
                    )
                    """,
                arguments: arguments
            ) ?? #"{"communities":[],"nodes":[],"edges":[],"claims":[]}"#

            return try JSONDecoder().decode(GraphRAGContext.self, from: Data(json.utf8))
        }
    }
}
