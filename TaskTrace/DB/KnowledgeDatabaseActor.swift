//
//  KnowledgeDatabaseActor.swift
//  TaskTrace
//
//  Created by Codex on 4/7/26.
//

import Foundation
import GRDB
import OSLog

actor KnowledgeDatabaseActor: Receiver {
    // Knowledge graph mutations are the first place where canonical rows and
    // vectorlite-backed ANN tables will need to move together. Keeping the
    // whole write surface on the vector-aware connection gives this subsystem
    // one ownership boundary instead of mixing pooled writes with ANN writes.
    //
    // That also means follow-up reads that participate in dedupe/resume logic
    // should generally use `vectorAwareRead`, because they need the writer's
    // immediate view of state on the same long-lived vectorlite connection.
    private let database: TaskTraceDatabase
    private let actorSystem: ActorSystem?
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "knowledge-db")
    init(database: TaskTraceDatabase, actorSystem: ActorSystem? = nil) {
        self.database = database
        self.actorSystem = actorSystem
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as KnowledgeDirectoryCreated:
            logger.log(
                "knowledge-database-actor received knowledge-directory-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) directoryID=\(event.directory.id, privacy: .public)"
            )

            do {
                try await saveKnowledgeDirectory(KnowledgeDirectoryInput(
                    id: event.directory.id,
                    slot: event.directory.slot,
                    path: event.directory.path,
                    bookmarkData: event.directory.bookmarkData,
                    createdAt: event.directory.createdAt
                ))
                await invalidate(directoryID: event.directory.id)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-directory-created operation=save-knowledge-directory directoryID=\(event.directory.id, privacy: .public) path=\(event.directory.path, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeDirectoryDeleted:
            logger.log(
                "knowledge-database-actor received knowledge-directory-deleted sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) directoryID=\(event.directoryID, privacy: .public)"
            )

            do {
                try await deleteKnowledgeDirectory(id: event.directoryID)
                await invalidate(directoryID: event.directoryID)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-directory-deleted operation=delete-knowledge-directory directoryID=\(event.directoryID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as RebuildKnowledge:
            logger.log(
                "knowledge-database-actor received rebuild-knowledge sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) directoryID=\(event.directoryID, privacy: .public)"
            )

            do {
                try await rebuildKnowledgeDirectory(id: event.directoryID)
                await invalidate(directoryID: event.directoryID)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=rebuild-knowledge operation=rebuild-knowledge-directory directoryID=\(event.directoryID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as RebuildActivityKnowledge:
            logger.log(
                "knowledge-database-actor received rebuild-activity-knowledge sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activeDay=\(event.activeDay.formatted(TaskTraceDatabase.sqlTimestampStyle), privacy: .public)"
            )

            do {
                try await rebuildActivityKnowledge(activeDay: event.activeDay)
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=rebuild-activity-knowledge operation=rebuild-activity-knowledge activeDay=\(event.activeDay.formatted(TaskTraceDatabase.sqlTimestampStyle), privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeFileCreated:
            logger.log(
                "knowledge-database-actor received knowledge-file-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) directoryID=\(event.directoryID, privacy: .public) fileID=\(event.file.id, privacy: .public) path=\(event.file.path, privacy: .public)"
            )

            do {
                try await saveKnowledgeFile(event.file)
                await invalidate(directoryID: event.directoryID)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-file-created operation=save-knowledge-file fileID=\(event.file.id, privacy: .public) directoryID=\(event.directoryID, privacy: .public) path=\(event.file.path, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeFileAccessed:
            logger.log(
                "knowledge-database-actor received knowledge-file-accessed sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.fileID, privacy: .public)"
            )

            do {
                try await updateKnowledgeFileLastAccessed(
                    fileID: event.fileID,
                    lastAccessed: event.lastAccessed
                )
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-file-accessed operation=update-knowledge-file-last-accessed fileID=\(event.fileID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeFileIndexReset:
            logger.log(
                "knowledge-database-actor received knowledge-file-index-reset sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.fileID, privacy: .public)"
            )

            do {
                try await resetKnowledgeFileIndex(fileID: event.fileID)
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-file-index-reset operation=reset-knowledge-file-index fileID=\(event.fileID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeAliasCreated:
            logger.log(
                "knowledge-database-actor received knowledge-alias-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.fileID, privacy: .public) aliasID=\(event.alias.id, privacy: .public)"
            )

            do {
                try await insertKnowledgeAlias(event.alias)
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-alias-created operation=insert-knowledge-alias fileID=\(event.fileID, privacy: .public) aliasID=\(event.alias.id, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeAnchorCreated:
            logger.log(
                "knowledge-database-actor received knowledge-anchor-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.fileID, privacy: .public) anchorID=\(event.anchor.id, privacy: .public)"
            )

            do {
                try await insertKnowledgeAnchor(event.anchor)
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-anchor-created operation=insert-knowledge-anchor fileID=\(event.fileID, privacy: .public) anchorID=\(event.anchor.id, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeChunkCreated:
            logger.log(
                "knowledge-database-actor received knowledge-chunk-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.fileID, privacy: .public) chunkID=\(event.chunk.id, privacy: .public)"
            )

            do {
                try await insertKnowledgeChunk(event.chunk)
                await actorSystem?.broadcast(
                    from: nil,
                    message: KnowledgeChunkEncodeRequested(
                        buildID: event.buildID,
                        fileID: event.fileID,
                        anchorID: event.anchorID,
                        anchorKey: event.anchorKey,
                        chunk: event.chunk,
                        scannedChunk: event.scannedChunk
                    )
                )
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-chunk-created operation=insert-knowledge-chunk fileID=\(event.fileID, privacy: .public) chunkID=\(event.chunk.id, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeChunkGraphProcessed:
            logger.log(
                "knowledge-database-actor received knowledge-chunk-graph-processed sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) chunkID=\(event.chunkID, privacy: .public) success=\(event.success, privacy: .public)"
            )

            guard event.success else {
                return
            }

            do {
                try await markKnowledgeChunkProcessed(
                    chunkID: event.chunkID,
                    processed: true
                )
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-chunk-graph-processed operation=mark-knowledge-chunk-processed chunkID=\(event.chunkID, privacy: .public) success=\(event.success, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeNodeCreated:
            logger.log(
                "knowledge-database-actor received knowledge-node-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) \(event.source.logDescription, privacy: .public) nodeID=\(event.node.id, privacy: .public) name=\(event.node.name, privacy: .public)"
            )

            do {
                try await saveKnowledgeNode(event.node)
                try await saveNodeSourceLink(nodeID: event.node.id, source: event.source)
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-node-created operation=save-knowledge-node \(event.source.logDescription, privacy: .public) nodeID=\(event.node.id, privacy: .public) name=\(event.node.name, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as UpdateKnowledgeNode:
            logger.log(
                "knowledge-database-actor received update-knowledge-node sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) \(event.source.logDescription, privacy: .public) nodeID=\(event.node.id, privacy: .public) name=\(event.node.name, privacy: .public)"
            )

            do {
                try await updateKnowledgeNode(event.node)
                try await saveNodeSourceLink(nodeID: event.node.id, source: event.source)
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=update-knowledge-node operation=update-knowledge-node \(event.source.logDescription, privacy: .public) nodeID=\(event.node.id, privacy: .public) name=\(event.node.name, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeNodeEmbedded:
            logger.log(
                "knowledge-database-actor received knowledge-node-embedded sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) nodeID=\(event.nodeID, privacy: .public) dimensions=\(event.vector.count, privacy: .public)"
            )

            do {
                try await updateKnowledgeNodeEmbedding(
                    nodeID: event.nodeID,
                    vector: event.vector
                )
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-node-embedded operation=update-knowledge-node-embedding nodeID=\(event.nodeID, privacy: .public) dimensions=\(event.vector.count, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeEdgeCreated:
            logger.log(
                "knowledge-database-actor received knowledge-edge-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) \(event.source.logDescription, privacy: .public) edgeID=\(event.edge.id, privacy: .public)"
            )

            do {
                try await saveKnowledgeEdge(event.edge)
                try await saveEdgeSourceLink(edgeID: event.edge.id, source: event.source)
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-edge-created operation=save-knowledge-edge \(event.source.logDescription, privacy: .public) edgeID=\(event.edge.id, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as UpdateKnowledgeEdge:
            logger.log(
                "knowledge-database-actor received update-knowledge-edge sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) \(event.source.logDescription, privacy: .public) edgeID=\(event.edge.id, privacy: .public)"
            )

            do {
                try await updateKnowledgeEdge(event.edge)
                try await saveEdgeSourceLink(edgeID: event.edge.id, source: event.source)
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=update-knowledge-edge operation=update-knowledge-edge \(event.source.logDescription, privacy: .public) edgeID=\(event.edge.id, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeLinkCreated:
            logger.log(
                "knowledge-database-actor received knowledge-link-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.fileID, privacy: .public) linkID=\(event.link.id, privacy: .public)"
            )

            do {
                try await insertKnowledgeLink(event.link)
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-link-created operation=insert-knowledge-link fileID=\(event.fileID, privacy: .public) linkID=\(event.link.id, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as CommunitiesGenerated:
            let communityCount = Set(event.communityByNodeID.values).count
            logger.log(
                "knowledge-database-actor received communities-generated sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) communityCount=\(communityCount, privacy: .public) nodeCount=\(event.communityByNodeID.count, privacy: .public)"
            )

            do {
                try await saveCommunities(communityByNodeID: event.communityByNodeID)
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=communities-generated operation=save-communities communityCount=\(communityCount, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as CommunitySummarized:
            logger.log(
                "knowledge-database-actor received community-summarized sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) communityID=\(event.communityID, privacy: .public)"
            )

            do {
                try await updateCommunitySummary(
                    communityID: event.communityID,
                    name: event.name,
                    summary: event.summary,
                    inputHash: event.inputHash
                )
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=community-summarized operation=update-community-summary communityID=\(event.communityID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as CommunityEmbedded:
            logger.log(
                "knowledge-database-actor received community-embedded sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) communityID=\(event.communityID, privacy: .public) dimensions=\(event.vector.count, privacy: .public)"
            )

            do {
                try await updateCommunityEmbedding(communityID: event.communityID, vector: event.vector)
                await invalidate(directoryID: nil)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=community-embedded operation=update-community-embedding communityID=\(event.communityID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeClaimCreated:
            logger.log(
                "knowledge-database-actor received knowledge-claim-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) claimID=\(event.claim.id, privacy: .public) nodeID=\(event.claim.nodeID, privacy: .public)"
            )

            do {
                try await saveKnowledgeClaim(event.claim)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-claim-created operation=save-knowledge-claim claimID=\(event.claim.id, privacy: .public) nodeID=\(event.claim.nodeID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeClaimEmbedded:
            logger.log(
                "knowledge-database-actor received knowledge-claim-embedded sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) claimID=\(event.claimID, privacy: .public) dimensions=\(event.vector.count, privacy: .public)"
            )

            do {
                try await updateKnowledgeClaimEmbedding(claimID: event.claimID, vector: event.vector)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-claim-embedded operation=update-knowledge-claim-embedding claimID=\(event.claimID, privacy: .public) dimensions=\(event.vector.count, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as KnowledgeDirectoryScanCompleted:
            logger.log(
                "knowledge-database-actor received knowledge-directory-scan-completed sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) directoryID=\(event.directoryID, privacy: .public) retained=\(event.retainingPaths.count, privacy: .public)"
            )

            do {
                try await markKnowledgeFilesDeleted(
                    directoryID: event.directoryID,
                    retainingPaths: event.retainingPaths,
                    deletedAt: event.deletedAt
                )
                await invalidate(directoryID: event.directoryID)
            } catch {
                logger.error(
                    "knowledge-database-actor failed event=knowledge-directory-scan-completed operation=mark-knowledge-files-deleted directoryID=\(event.directoryID, privacy: .public) retained=\(event.retainingPaths.count, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        default:
            return
        }
    }

    private func saveNodeSourceLink(
        nodeID: Int64,
        source: KnowledgeGraphSource
    ) async throws {
        switch source {
        case .chunk(let chunk):
            try await saveNodeChunk(nodeID: nodeID, chunkID: chunk.id)
        case .activity(let activityID):
            try await saveNodeActivity(nodeID: nodeID, activityID: activityID)
        }
    }

    private func saveEdgeSourceLink(
        edgeID: Int64,
        source: KnowledgeGraphSource
    ) async throws {
        switch source {
        case .chunk(let chunk):
            try await saveEdgeChunk(edgeID: edgeID, chunkID: chunk.id)
        case .activity(let activityID):
            try await saveEdgeActivity(edgeID: edgeID, activityID: activityID)
        }
    }

    private func invalidate(directoryID: Int64?) async {
        await actorSystem?.broadcast(
            from: nil,
            message: KnowledgeDataInvalidated(directoryID: directoryID)
        )
    }

    func loadKnowledgeDirectories() async throws -> [KnowledgeDirectoryRecord] {
        try database.read { db in
            try KnowledgeDirectoryRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM knowledge_directories
                    ORDER BY created_at DESC, id DESC
                    """
            )
        }
    }

    func loadKnowledgeFileSystemEntries(
        directoryID: Int64
    ) async throws -> [KnowledgeFileSystemEntry] {
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
                        WHERE knowledge_files.directory_id = ?
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
                        WHERE knowledge_files.directory_id = ?
                          AND knowledge_files.deleted_at IS NULL
                        GROUP BY knowledge_files.id
                    )
                    SELECT
                        knowledge_files.id,
                        knowledge_files.directory_id,
                        knowledge_files.relative_path AS path,
                        knowledge_files.title,
                        knowledge_files.byte_count,
                        COALESCE(file_chunk_counts.total_chunks, 0) AS total_chunks,
                        COALESCE(file_chunk_counts.processed_chunks, 0) AS processed_chunks,
                        COALESCE(file_node_counts.total_node_embeddings, 0) AS total_node_embeddings,
                        COALESCE(file_node_counts.embedded_node_count, 0) AS embedded_node_count
                    FROM knowledge_files
                    LEFT JOIN file_chunk_counts ON file_chunk_counts.file_id = knowledge_files.id
                    LEFT JOIN file_node_counts ON file_node_counts.file_id = knowledge_files.id
                    WHERE knowledge_files.directory_id = ?
                      AND knowledge_files.deleted_at IS NULL
                    ORDER BY knowledge_files.relative_path ASC, knowledge_files.id ASC
                    """,
                arguments: [directoryID, directoryID, directoryID]
            )
        }
    }

    func loadKnowledgeFileDetail(
        directoryID: Int64,
        path: String
    ) async throws -> KnowledgeFileIndexSummary? {
        try database.read { db in
            guard let fileRow = try Row.fetchOne(
                db,
                sql: """
                    SELECT id
                    FROM knowledge_files
                    WHERE directory_id = ?
                      AND deleted_at IS NULL
                      AND relative_path = ?
                    LIMIT 1
                    """,
                arguments: [directoryID, path]
            ), let fileID: Int64 = fileRow["id"] else {
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
                arguments: [fileID]
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
                arguments: [fileID]
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
                arguments: [fileID]
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
                arguments: [fileID]
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

    func loadKnowledgeGraphDirectorySnapshot(
        directoryID: Int64
    ) async throws -> KnowledgeGraphDirectorySnapshot {
        try database.read { db in
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
                    WHERE source_files.directory_id = ?
                      AND source_files.deleted_at IS NULL
                      AND destination_files.directory_id = ?
                      AND destination_files.deleted_at IS NULL
                      AND source_files.id != destination_files.id
                    GROUP BY source_file_id, target_file_id
                    ORDER BY source_file_id ASC, target_file_id ASC
                    """,
                arguments: [directoryID, directoryID]
            )
            let knowledgeNodes = try KnowledgeGraphNodeEntry.fetchAll(
                db,
                sql: """
                    SELECT
                        knowledge_nodes.id,
                        knowledge_nodes.name,
                        knowledge_nodes.kind,
                        knowledge_nodes.description,
                        knowledge_nodes.community_id,
                        MIN(knowledge_files.relative_path) AS source_path
                    FROM knowledge_nodes
                    JOIN knowledge_node_chunks ON knowledge_node_chunks.node_id = knowledge_nodes.id
                    JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                    JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                    JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                    WHERE knowledge_files.directory_id = ?
                      AND knowledge_files.deleted_at IS NULL
                    GROUP BY knowledge_nodes.id
                    ORDER BY knowledge_nodes.normalized_name ASC, knowledge_nodes.id ASC
                    """,
                arguments: [directoryID]
            )
            let knowledgeEdges = try KnowledgeEdgeRecord.fetchAll(
                db,
                sql: """
                    WITH scoped_nodes AS (
                        SELECT DISTINCT knowledge_nodes.id
                        FROM knowledge_nodes
                        JOIN knowledge_node_chunks ON knowledge_node_chunks.node_id = knowledge_nodes.id
                        JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                        JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                        JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                        WHERE knowledge_files.directory_id = ?
                          AND knowledge_files.deleted_at IS NULL
                    )
                    SELECT knowledge_edges.*
                    FROM knowledge_edges
                    JOIN scoped_nodes AS first_nodes ON first_nodes.id = knowledge_edges.first_node_id
                    JOIN scoped_nodes AS second_nodes ON second_nodes.id = knowledge_edges.second_node_id
                    ORDER BY knowledge_edges.first_node_id ASC, knowledge_edges.second_node_id ASC, knowledge_edges.id ASC
                    """,
                arguments: [directoryID]
            )
            let communities = try KnowledgeCommunityRecord.fetchAll(
                db,
                sql: """
                    SELECT knowledge_communities.*
                    FROM knowledge_communities
                    WHERE knowledge_communities.id IN (
                        SELECT DISTINCT knowledge_nodes.community_id
                        FROM knowledge_nodes
                        JOIN knowledge_node_chunks ON knowledge_node_chunks.node_id = knowledge_nodes.id
                        JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                        JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                        JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                        WHERE knowledge_files.directory_id = ?
                          AND knowledge_files.deleted_at IS NULL
                          AND knowledge_nodes.community_id IS NOT NULL
                    )
                    ORDER BY knowledge_communities.id ASC
                    """,
                arguments: [directoryID]
            )

            return KnowledgeGraphDirectorySnapshot(
                fileLinks: fileLinks,
                knowledgeNodes: knowledgeNodes,
                knowledgeEdges: knowledgeEdges,
                communities: communities
            )
        }
    }

    func loadKnowledgeGraphBuildProgress(
        directoryID: Int64,
        activeDay: Date
    ) async throws -> KnowledgeGraphBuildProgress {
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
                        WHERE knowledge_files.directory_id = ?
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
                arguments: [directoryID, startSQL, endSQL]
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

    func loadKnowledgeBridgeLinks(
        directoryID: Int64?,
        fileID: Int64? = nil,
        nodeID: Int64? = nil
    ) async throws -> [KnowledgeBridgeLinkRecord] {
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

    func loadKnowledgeCommunityLinks(
        directoryID: Int64?,
        communityID: Int64
    ) async throws -> [KnowledgeCommunityLinkRecord] {
        try database.read { db in
            try KnowledgeCommunityLinkRecord.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT
                        knowledge_nodes.community_id AS community_id,
                        knowledge_nodes.id AS node_id
                    FROM knowledge_nodes
                    LEFT JOIN knowledge_node_chunks ON knowledge_node_chunks.node_id = knowledge_nodes.id
                    LEFT JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                    LEFT JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                    LEFT JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                    WHERE knowledge_nodes.community_id = ?
                      AND (
                        ? IS NULL
                        OR (
                            knowledge_files.deleted_at IS NULL
                            AND knowledge_files.directory_id = ?
                        )
                      )
                    ORDER BY knowledge_nodes.id ASC
                    """,
                arguments: [communityID, directoryID, directoryID]
            )
        }
    }

    func loadKnowledgeClaims(nodeID: Int64) async throws -> [KnowledgeClaimRecord] {
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

    func loadKnowledgeDirectory(directoryID: Int64) async throws -> KnowledgeDirectoryRecord? {
        try database.read { db in
            try KnowledgeDirectoryRecord.fetchOne(
                db,
                sql: """
                    SELECT *
                    FROM knowledge_directories
                    WHERE id = ?
                    LIMIT 1
                    """,
                arguments: [directoryID]
            )
        }
    }

    func loadKnowledgeFiles(
        directoryID: Int64,
        includingDeleted: Bool
    ) async throws -> [KnowledgeFileRecord] {
        try database.read { db in
            try KnowledgeFileRecord.fetchAll(
                db,
                sql: includingDeleted
                    ? """
                        SELECT *
                        FROM knowledge_files
                        WHERE directory_id = ?
                        ORDER BY relative_path ASC
                        """
                    : """
                        SELECT *
                        FROM knowledge_files
                        WHERE directory_id = ?
                          AND deleted_at IS NULL
                        ORDER BY relative_path ASC
                        """,
                arguments: [directoryID]
            )
        }
    }

    func loadKnowledgeNode(normalizedName: String) async throws -> KnowledgeNodeRecord? {
        try database.vectorAwareRead { db in
            // Node dedup runs inline with graph extraction writes. Reading on the
            // same vector-aware connection avoids racing pooled reads against
            // freshly inserted canonical rows.
            try KnowledgeNodeRecord.fetchOne(
                db,
                sql: """
                    SELECT *
                    FROM knowledge_nodes
                    WHERE normalized_name = ?
                    LIMIT 1
                    """,
                arguments: [normalizedName]
            )
        }
    }

    func loadKnowledgeNodes() async throws -> [KnowledgeNodeRecord] {
        try database.vectorAwareRead { db in
            // Community detection reacts to node/edge creation events emitted by
            // the write pipeline, so it needs the writer's view of the graph.
            try KnowledgeNodeRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM knowledge_nodes
                    ORDER BY normalized_name ASC, id ASC
                    """
            )
        }
    }

    func loadKnowledgeEdge(
        firstNodeID: Int64,
        secondNodeID: Int64
    ) async throws -> KnowledgeEdgeRecord? {
        try database.vectorAwareRead { db in
            // Edge dedup is part of the same mutation pipeline as edge writes.
            try KnowledgeEdgeRecord.fetchOne(
                db,
                sql: """
                    SELECT *
                    FROM knowledge_edges
                    WHERE first_node_id = ?
                      AND second_node_id = ?
                    LIMIT 1
                    """,
                arguments: [firstNodeID, secondNodeID]
            )
        }
    }

    func loadKnowledgeEdges() async throws -> [KnowledgeEdgeRecord] {
        try database.vectorAwareRead { db in
            try KnowledgeEdgeRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM knowledge_edges
                    ORDER BY first_node_id ASC, second_node_id ASC, id ASC
                    """
            )
        }
    }

    func knowledgeChunkExists(hash: String) async throws -> Bool {
        try database.vectorAwareRead { db in
            // Chunk enqueue dedup should see inserts made moments earlier in the
            // same knowledge indexing pipeline.
            try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                        SELECT 1
                        FROM knowledge_chunks
                        WHERE hash = ?
                    )
                    """,
                arguments: [hash]
            ) ?? false
        }
    }

    func loadUnprocessedKnowledgeChunkRequests(
        directoryID: Int64,
        buildID: Int64?,
        afterChunkID: Int64?,
        limit: Int
    ) async throws -> [KnowledgeChunkEncodeRequested] {
        try database.vectorAwareRead { db in
            // Rebuild/resume work needs a consistent view of chunk rows and the
            // processed flags that are mutated on the vector-aware connection.
            try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        knowledge_chunks.id AS chunk_id,
                        knowledge_chunks.anchor_id AS anchor_id,
                        knowledge_chunks.ordinal AS ordinal,
                        knowledge_chunks.hash AS hash,
                        knowledge_chunks.text AS text,
                        knowledge_anchors.anchor_key AS anchor_key,
                        knowledge_anchors.file_id AS file_id
                    FROM knowledge_chunks
                    JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                    JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                    WHERE knowledge_files.directory_id = ?
                      AND knowledge_files.deleted_at IS NULL
                      AND knowledge_chunks.processed = 0
                      AND knowledge_chunks.id > ?
                    ORDER BY knowledge_chunks.id ASC
                    LIMIT ?
                    """,
                arguments: [directoryID, afterChunkID ?? 0, limit]
            )
            .compactMap { row in
                guard let chunkID: Int64 = row["chunk_id"],
                      let anchorID: Int64 = row["anchor_id"],
                      let ordinal: Int = row["ordinal"],
                      let hash: String = row["hash"],
                      let text: String = row["text"],
                      let anchorKey: String = row["anchor_key"],
                      let fileID: Int64 = row["file_id"] else {
                    return nil
                }

                return KnowledgeChunkEncodeRequested(
                    buildID: buildID,
                    fileID: fileID,
                    anchorID: anchorID,
                    anchorKey: anchorKey,
                    chunk: KnowledgeChunkInput(
                        id: chunkID,
                        anchorID: anchorID,
                        ordinal: ordinal,
                        hash: hash,
                        text: text
                    ),
                    scannedChunk: KnowledgeScannedChunk(
                        ordinal: ordinal,
                        hash: hash,
                        text: text
                    )
                )
            }
        }
    }

    func loadCommunitySummaryInput(communityID: Int64) async throws -> KnowledgeCommunitySummaryInput {
        try database.vectorAwareRead { db in
            // Community assignment is persisted on the vector-aware connection.
            // Summaries that immediately follow `CommunitiesGenerated` need to
            // read through that same handle so they do not race a pooled read
            // against a just-committed community_id update.
            let community = try KnowledgeCommunityRecord.fetchOne(
                db,
                sql: """
                    SELECT *
                    FROM knowledge_communities
                    WHERE id = ?
                    """,
                arguments: [communityID]
            )
            let nodes = try KnowledgeNodeRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM knowledge_nodes
                    WHERE community_id = ?
                    ORDER BY normalized_name ASC, id ASC
                    """,
                arguments: [communityID]
            )
            let nodeIDs = nodes.map(\.id)

            guard !nodeIDs.isEmpty else {
                return KnowledgeCommunitySummaryInput(
                    currentSummary: community?.summary,
                    summaryInputHash: community?.summaryInputHash,
                    nodes: [],
                    edges: [],
                    claimsByNodeID: [:]
                )
            }

            let arguments = StatementArguments(
                (Array(nodeIDs) + Array(nodeIDs)) as [(any DatabaseValueConvertible)?]
            )
            let edges = try KnowledgeEdgeRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM knowledge_edges
                    WHERE first_node_id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: nodeIDs.count)))
                      AND second_node_id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: nodeIDs.count)))
                    """,
                arguments: arguments
            )
            let claims = try KnowledgeClaimRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM knowledge_claims
                    WHERE node_id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: nodeIDs.count)))
                    ORDER BY node_id ASC, create_date ASC, id ASC
                    """,
                arguments: StatementArguments(Array(nodeIDs) as [(any DatabaseValueConvertible)?])
            )

            return KnowledgeCommunitySummaryInput(
                currentSummary: community?.summary,
                summaryInputHash: community?.summaryInputHash,
                nodes: nodes,
                edges: edges,
                claimsByNodeID: Dictionary(grouping: claims, by: \.nodeID)
            )
        }
    }

    func loadCommunityNodesAndEdges(
        communityID: Int64
    ) async throws -> (nodes: [KnowledgeNodeRecord], edges: [KnowledgeEdgeRecord]) {
        let summaryInput = try await loadCommunitySummaryInput(communityID: communityID)
        return (summaryInput.nodes, summaryInput.edges)
    }

    func loadKnowledgeObsidianCommunityTargets(
        nodeIDs: [Int64]
    ) async throws -> [KnowledgeObsidianExportTarget] {
        let scopedNodeIDs = Array(Set(nodeIDs)).sorted()

        guard !scopedNodeIDs.isEmpty else {
            return []
        }

        return try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT
                        knowledge_files.directory_id AS directory_id,
                        knowledge_nodes.community_id AS community_id
                    FROM knowledge_nodes
                    JOIN knowledge_node_chunks ON knowledge_node_chunks.node_id = knowledge_nodes.id
                    JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                    JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                    JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                    WHERE knowledge_nodes.id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: scopedNodeIDs.count)))
                      AND knowledge_nodes.community_id IS NOT NULL
                      AND knowledge_files.deleted_at IS NULL
                    ORDER BY knowledge_files.directory_id ASC, knowledge_nodes.community_id ASC
                    """,
                arguments: StatementArguments(scopedNodeIDs as [(any DatabaseValueConvertible)?])
            )
            .compactMap { row in
                guard let directoryID: Int64 = row["directory_id"],
                      let communityID: Int64 = row["community_id"] else {
                    return nil
                }

                return KnowledgeObsidianExportTarget(
                    directoryID: directoryID,
                    communityID: communityID
                )
            }
        }
    }

    func loadKnowledgeObsidianCommunityFileNames(
        directoryID: Int64
    ) async throws -> Set<String> {
        try database.read { db in
            Set(
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT DISTINCT
                            knowledge_communities.id AS community_id,
                            knowledge_communities.name AS community_name
                        FROM knowledge_communities
                        JOIN knowledge_nodes ON knowledge_nodes.community_id = knowledge_communities.id
                        JOIN knowledge_node_chunks ON knowledge_node_chunks.node_id = knowledge_nodes.id
                        JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                        JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                        JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                        WHERE knowledge_files.directory_id = ?
                          AND knowledge_files.deleted_at IS NULL
                        """,
                    arguments: [directoryID]
                )
                .compactMap { row in
                    guard let communityID: Int64 = row["community_id"] else {
                        return nil
                    }

                    let trimmedName = (row["community_name"] as String?)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let communityName = trimmedName?.isEmpty == false
                        ? trimmedName!
                        : "Community \(communityID)"
                    return KnowledgeObsidianExportNaming.fileName(communityName: communityName)
                }
            )
        }
    }

    func loadKnowledgeObsidianCommunityPayload(
        directoryID: Int64,
        communityID: Int64
    ) async throws -> KnowledgeObsidianCommunityPayload? {
        try database.read { db -> KnowledgeObsidianCommunityPayload? in
            guard let directory = try KnowledgeDirectoryRecord.fetchOne(
                db,
                sql: "SELECT * FROM knowledge_directories WHERE id = ?",
                arguments: [directoryID]
            ) else {
                return nil
            }

            guard let community = try KnowledgeCommunityRecord.fetchOne(
                db,
                sql: "SELECT * FROM knowledge_communities WHERE id = ?",
                arguments: [communityID]
            ) else {
                return nil
            }

            let members = try KnowledgeNodeRecord.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT knowledge_nodes.*
                    FROM knowledge_nodes
                    JOIN knowledge_node_chunks ON knowledge_node_chunks.node_id = knowledge_nodes.id
                    JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                    JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                    JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                    WHERE knowledge_nodes.community_id = ?
                      AND knowledge_files.directory_id = ?
                      AND knowledge_files.deleted_at IS NULL
                    ORDER BY knowledge_nodes.normalized_name ASC, knowledge_nodes.id ASC
                    """,
                arguments: [communityID, directory.id]
            )

            let memberIDs = members.map(\.id)
            let memberIDSet = Set(memberIDs)

            guard !memberIDs.isEmpty else {
                return nil
            }

            let sourceRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT
                        knowledge_node_chunks.node_id AS node_id,
                        knowledge_files.id AS file_id,
                        knowledge_files.relative_path AS file_path,
                        knowledge_files.title AS file_title
                    FROM knowledge_node_chunks
                    JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                    JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                    JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                    WHERE knowledge_node_chunks.node_id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: memberIDs.count)))
                      AND knowledge_files.directory_id = ?
                      AND knowledge_files.deleted_at IS NULL
                    ORDER BY knowledge_node_chunks.node_id ASC, knowledge_files.relative_path ASC
                    """,
                arguments: StatementArguments((memberIDs + [directory.id]) as [(any DatabaseValueConvertible)?])
            )
            let claimRows = try KnowledgeClaimRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM knowledge_claims
                    WHERE node_id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: memberIDs.count)))
                    ORDER BY node_id ASC, create_date ASC, id ASC
                    """,
                arguments: StatementArguments(memberIDs as [(any DatabaseValueConvertible)?])
            )
            let noteableRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT
                        knowledge_nodes.id AS node_id,
                        knowledge_nodes.name AS node_name,
                        knowledge_nodes.normalized_name AS normalized_name,
                        knowledge_nodes.community_id AS community_id,
                        knowledge_communities.name AS community_name
                    FROM knowledge_nodes
                    JOIN knowledge_node_chunks ON knowledge_node_chunks.node_id = knowledge_nodes.id
                    JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_node_chunks.chunk_id
                    JOIN knowledge_anchors ON knowledge_anchors.id = knowledge_chunks.anchor_id
                    JOIN knowledge_files ON knowledge_files.id = knowledge_anchors.file_id
                    LEFT JOIN knowledge_communities ON knowledge_communities.id = knowledge_nodes.community_id
                    WHERE knowledge_files.directory_id = ?
                      AND knowledge_files.deleted_at IS NULL
                    ORDER BY knowledge_nodes.community_id ASC, knowledge_nodes.normalized_name ASC, knowledge_nodes.id ASC
                    """,
                arguments: [directory.id]
            )
            let noteableNodes = noteableRows.compactMap {
                row -> (
                    nodeID: Int64,
                    nodeName: String,
                    normalizedName: String?,
                    communityID: Int64,
                    communityName: String
                )? in
                guard let nodeID: Int64 = row["node_id"],
                      let nodeName: String = row["node_name"],
                      let communityID: Int64 = row["community_id"] else {
                    return nil
                }

                let trimmedCommunityName = (row["community_name"] as String?)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                return (
                    nodeID: nodeID,
                    nodeName: nodeName,
                    normalizedName: row["normalized_name"] as String?,
                    communityID: communityID,
                    communityName: trimmedCommunityName?.isEmpty == false
                        ? trimmedCommunityName!
                        : "Community \(communityID)"
                )
            }
            let noteableNodeIDs = Set(noteableNodes.map(\.nodeID))
            let noteableNodeTargetsByID = Dictionary(
                uniqueKeysWithValues: Dictionary(grouping: noteableNodes, by: \.communityID)
                    .flatMap { communityID, communityNodes in
                        communityNodes
                            .sorted {
                                ($0.normalizedName ?? KnowledgeNodeRecord.normalizedName(for: $0.nodeName), $0.nodeID)
                                    < ($1.normalizedName ?? KnowledgeNodeRecord.normalizedName(for: $1.nodeName), $1.nodeID)
                            }
                            .reduce(
                                into: (
                                    usedAnchorKeys: Set<String>(),
                                    duplicateCounts: [String: Int](),
                                    nodeTargets: [(Int64, (communityID: Int64, communityName: String, nodeName: String, anchorKey: String))]()
                                )
                            ) { partial, node in
                                let baseAnchorKey = KnowledgeObsidianExportNaming.anchorKey(sectionTitle: node.nodeName)
                                let duplicateCount = partial.duplicateCounts[baseAnchorKey, default: 0]
                                let anchorKey = {
                                    let candidate = duplicateCount == 0
                                        ? baseAnchorKey
                                        : "\(baseAnchorKey)-\(duplicateCount + 1)"

                                    guard !partial.usedAnchorKeys.contains(candidate) else {
                                        return "\(baseAnchorKey)-\(duplicateCount + 2)"
                                    }

                                    return candidate
                                }()

                                partial.duplicateCounts[baseAnchorKey] = duplicateCount + 1
                                partial.usedAnchorKeys.insert(anchorKey)
                                partial.nodeTargets.append((
                                    node.nodeID,
                                    (
                                        communityID: communityID,
                                        communityName: node.communityName,
                                        nodeName: node.nodeName,
                                        anchorKey: anchorKey
                                    )
                                ))
                            }
                            .nodeTargets
                    }
            )
            let edgeRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        knowledge_edges.first_node_id AS first_node_id,
                        knowledge_edges.second_node_id AS second_node_id,
                        knowledge_edges.relationship_type AS relationship_type,
                        knowledge_edges.description AS description,
                        first_nodes.name AS first_name,
                        second_nodes.name AS second_name
                    FROM knowledge_edges
                    JOIN knowledge_nodes first_nodes ON first_nodes.id = knowledge_edges.first_node_id
                    JOIN knowledge_nodes second_nodes ON second_nodes.id = knowledge_edges.second_node_id
                    WHERE knowledge_edges.first_node_id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: memberIDs.count)))
                       OR knowledge_edges.second_node_id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: memberIDs.count)))
                    ORDER BY first_nodes.normalized_name ASC, second_nodes.normalized_name ASC
                    """,
                arguments: StatementArguments((memberIDs + memberIDs) as [(any DatabaseValueConvertible)?])
            )

            let sourceFilesByNodeID = sourceRows.reduce(into: [Int64: [KnowledgeObsidianSourceFileReference]]()) { partial, row in
                guard let memberNodeID: Int64 = row["node_id"],
                      let fileID: Int64 = row["file_id"],
                      let path: String = row["file_path"] else {
                    return
                }

                partial[memberNodeID, default: []].append(
                    KnowledgeObsidianSourceFileReference(
                        fileID: fileID,
                        path: path,
                        title: row["file_title"]
                    )
                )
            }
            let claimsByNodeID = Dictionary(grouping: claimRows, by: \.nodeID)
            let relatedNodesByMemberID = edgeRows.reduce(into: [Int64: [KnowledgeObsidianRelatedNodeReference]]()) { partial, row in
                guard let firstNodeID: Int64 = row["first_node_id"],
                      let secondNodeID: Int64 = row["second_node_id"],
                      let firstName: String = row["first_name"],
                      let secondName: String = row["second_name"],
                      noteableNodeIDs.contains(firstNodeID) || noteableNodeIDs.contains(secondNodeID) else {
                    return
                }

                if memberIDSet.contains(firstNodeID),
                   noteableNodeIDs.contains(secondNodeID) {
                    partial[firstNodeID, default: []].append(
                        KnowledgeObsidianRelatedNodeReference(
                            nodeID: secondNodeID,
                            name: secondName,
                            direction: .outgoing,
                            relationshipType: row["relationship_type"],
                            description: (row["description"] as String?) ?? ""
                        )
                    )
                }

                if memberIDSet.contains(secondNodeID),
                   noteableNodeIDs.contains(firstNodeID) {
                    partial[secondNodeID, default: []].append(
                        KnowledgeObsidianRelatedNodeReference(
                            nodeID: firstNodeID,
                            name: firstName,
                            direction: .incoming,
                            relationshipType: row["relationship_type"],
                            description: (row["description"] as String?) ?? ""
                        )
                    )
                }
            }
            let edgeLinksByMemberID = edgeRows.reduce(into: [Int64: [KnowledgeObsidianEdgeLinkReference]]()) { partial, row in
                guard let firstNodeID: Int64 = row["first_node_id"],
                      let secondNodeID: Int64 = row["second_node_id"],
                      noteableNodeIDs.contains(firstNodeID) || noteableNodeIDs.contains(secondNodeID) else {
                    return
                }

                if memberIDSet.contains(firstNodeID),
                   let target = noteableNodeTargetsByID[secondNodeID] {
                    partial[firstNodeID, default: []].append(
                        KnowledgeObsidianEdgeLinkReference(
                            communityID: target.communityID,
                            communityName: target.communityName,
                            targetNodeName: target.nodeName,
                            targetAnchorKey: target.anchorKey,
                            relationshipType: row["relationship_type"],
                            description: (row["description"] as String?) ?? ""
                        )
                    )
                }

                if memberIDSet.contains(secondNodeID),
                   let target = noteableNodeTargetsByID[firstNodeID] {
                    partial[secondNodeID, default: []].append(
                        KnowledgeObsidianEdgeLinkReference(
                            communityID: target.communityID,
                            communityName: target.communityName,
                            targetNodeName: target.nodeName,
                            targetAnchorKey: target.anchorKey,
                            relationshipType: row["relationship_type"],
                            description: (row["description"] as String?) ?? ""
                        )
                    )
                }
            }

            return KnowledgeObsidianCommunityPayload(
                directory: directory,
                community: community,
                members: members.map { member in
                    KnowledgeObsidianMemberReference(
                        nodeID: member.id,
                        anchorKey: noteableNodeTargetsByID[member.id]?.anchorKey
                            ?? KnowledgeObsidianExportNaming.anchorKey(sectionTitle: member.name),
                        name: member.name,
                        description: member.description,
                        claims: claimsByNodeID[member.id] ?? [],
                        sourceFiles: sourceFilesByNodeID[member.id] ?? [],
                        relatedNodes: relatedNodesByMemberID[member.id] ?? [],
                        edgeLinks: (edgeLinksByMemberID[member.id] ?? [])
                            .sorted {
                                let firstCommunityName = KnowledgeNodeRecord.normalizedName(for: $0.communityName)
                                let secondCommunityName = KnowledgeNodeRecord.normalizedName(for: $1.communityName)
                                if firstCommunityName != secondCommunityName {
                                    return firstCommunityName < secondCommunityName
                                }

                                let firstTargetName = KnowledgeNodeRecord.normalizedName(for: $0.targetNodeName)
                                let secondTargetName = KnowledgeNodeRecord.normalizedName(for: $1.targetNodeName)
                                if firstTargetName != secondTargetName {
                                    return firstTargetName < secondTargetName
                                }

                                let firstDescription = $0.description.trimmingCharacters(in: .whitespacesAndNewlines)
                                let secondDescription = $1.description.trimmingCharacters(in: .whitespacesAndNewlines)
                                if firstDescription != secondDescription {
                                    return firstDescription < secondDescription
                                }

                                let firstRelationshipType = $0.relationshipType?
                                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                let secondRelationshipType = $1.relationshipType?
                                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                if firstRelationshipType != secondRelationshipType {
                                    return firstRelationshipType < secondRelationshipType
                                }

                                return $0.targetAnchorKey < $1.targetAnchorKey
                            }
                    )
                }
            )
        }
    }

    func saveKnowledgeDirectory(_ knowledgeDirectory: KnowledgeDirectoryInput) async throws {
        try database.vectorAwareWrite { db in
            // Directory lifecycle writes start on the vector-aware connection so
            // any future ANN/index side effects stay in the same transaction
            // boundary as the canonical row mutation.
            try db.execute(
                sql: """
                    INSERT INTO knowledge_directories (
                        id,
                        slot,
                        path,
                        bookmark_data,
                        created_at
                    )
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        slot = excluded.slot,
                        path = excluded.path,
                        bookmark_data = excluded.bookmark_data,
                        created_at = excluded.created_at
                    """,
                arguments: [
                    knowledgeDirectory.id,
                    knowledgeDirectory.slot.rawValue,
                    knowledgeDirectory.path,
                    knowledgeDirectory.bookmarkData,
                    knowledgeDirectory.createdAt.formatted(TaskTraceDatabase.sqlTimestampStyle)
                ]
            )
        }
    }

    func deleteKnowledgeDirectory(id: Int64) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: "DELETE FROM knowledge_directories WHERE id = ?",
                arguments: [id]
            )
        }
    }

    func rebuildKnowledgeDirectory(id: Int64) async throws {
        try database.vectorAwareWrite { db in
            // Rebuild is intentionally vector-aware end-to-end because it can
            // invalidate canonical rows, chunk processing state, graph rows, and
            // any vectorlite-backed structures derived from them.
            try db.execute(
                sql: "DELETE FROM knowledge_files WHERE directory_id = ?",
                arguments: [id]
            )

            try db.execute(
                sql: """
                    DELETE FROM knowledge_edges
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM knowledge_edge_chunks
                        WHERE knowledge_edge_chunks.edge_id = knowledge_edges.id
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM knowledge_edge_activities
                        WHERE knowledge_edge_activities.edge_id = knowledge_edges.id
                    )
                    """
            )

            try db.execute(
                sql: """
                    DELETE FROM knowledge_nodes
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM knowledge_node_chunks
                        WHERE knowledge_node_chunks.node_id = knowledge_nodes.id
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM knowledge_node_activities
                        WHERE knowledge_node_activities.node_id = knowledge_nodes.id
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM knowledge_edges
                        WHERE knowledge_edges.first_node_id = knowledge_nodes.id
                           OR knowledge_edges.second_node_id = knowledge_nodes.id
                    )
                    """
            )

            try db.execute(
                sql: """
                    DELETE FROM knowledge_communities
                    WHERE id NOT IN (
                        SELECT DISTINCT community_id
                        FROM knowledge_nodes
                        WHERE community_id IS NOT NULL
                    )
                    """
            )
        }
    }

    func rebuildActivityKnowledge(
        activeDay: Date
    ) async throws {
        let startOfDay = Calendar(identifier: .gregorian).startOfDay(for: activeDay)
        let nextDay = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let startSQL = startOfDay.formatted(TaskTraceDatabase.sqlTimestampStyle)
        let endSQL = nextDay.formatted(TaskTraceDatabase.sqlTimestampStyle)

        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    WITH day_activities AS (
                        SELECT id
                        FROM activities
                        WHERE start_time >= ?
                          AND start_time < ?
                          AND overview_id IS NOT NULL
                    )
                    UPDATE activities
                    SET knowledge_processed = 0
                    WHERE id IN (SELECT id FROM day_activities)
                    """,
                arguments: [startSQL, endSQL]
            )

            try db.execute(
                sql: """
                    WITH day_overviews AS (
                        SELECT DISTINCT overview_id AS id
                        FROM activities
                        WHERE start_time >= ?
                          AND start_time < ?
                          AND overview_id IS NOT NULL
                    )
                    UPDATE overviews
                    SET knowledge_processed = 0
                    WHERE id IN (SELECT id FROM day_overviews)
                    """,
                arguments: [startSQL, endSQL]
            )

            try db.execute(
                sql: """
                    WITH day_activities AS (
                        SELECT id
                        FROM activities
                        WHERE start_time >= ?
                          AND start_time < ?
                          AND overview_id IS NOT NULL
                    )
                    DELETE FROM knowledge_node_activities
                    WHERE activity_id IN (SELECT id FROM day_activities)
                    """,
                arguments: [startSQL, endSQL]
            )

            try db.execute(
                sql: """
                    WITH day_activities AS (
                        SELECT id
                        FROM activities
                        WHERE start_time >= ?
                          AND start_time < ?
                          AND overview_id IS NOT NULL
                    )
                    DELETE FROM knowledge_edge_activities
                    WHERE activity_id IN (SELECT id FROM day_activities)
                    """,
                arguments: [startSQL, endSQL]
            )

            try db.execute(
                sql: """
                    DELETE FROM knowledge_edges
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM knowledge_edge_chunks
                        WHERE knowledge_edge_chunks.edge_id = knowledge_edges.id
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM knowledge_edge_activities
                        WHERE knowledge_edge_activities.edge_id = knowledge_edges.id
                    )
                    """
            )

            try db.execute(
                sql: """
                    DELETE FROM knowledge_nodes
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM knowledge_node_chunks
                        WHERE knowledge_node_chunks.node_id = knowledge_nodes.id
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM knowledge_node_activities
                        WHERE knowledge_node_activities.node_id = knowledge_nodes.id
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM knowledge_edges
                        WHERE knowledge_edges.first_node_id = knowledge_nodes.id
                           OR knowledge_edges.second_node_id = knowledge_nodes.id
                    )
                    """
            )

            try db.execute(
                sql: """
                    DELETE FROM knowledge_communities
                    WHERE id NOT IN (
                        SELECT DISTINCT community_id
                        FROM knowledge_nodes
                        WHERE community_id IS NOT NULL
                    )
                    """
            )
        }
    }

    func saveKnowledgeFile(_ knowledgeFile: KnowledgeFileInput) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT INTO knowledge_files (
                        id,
                        directory_id,
                        relative_path,
                        title,
                        mtime,
                        create_date,
                        last_accessed,
                        checksum,
                        metadata_json,
                        deleted_at,
                        byte_count
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        directory_id = excluded.directory_id,
                        relative_path = excluded.relative_path,
                        title = excluded.title,
                        mtime = excluded.mtime,
                        create_date = excluded.create_date,
                        last_accessed = excluded.last_accessed,
                        checksum = excluded.checksum,
                        metadata_json = excluded.metadata_json,
                        deleted_at = excluded.deleted_at,
                        byte_count = excluded.byte_count
                    """,
                arguments: [
                    knowledgeFile.id,
                    knowledgeFile.directoryID,
                    knowledgeFile.path,
                    knowledgeFile.title,
                    knowledgeFile.modifiedAt?.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    knowledgeFile.createDate.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    knowledgeFile.lastAccessed?.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    knowledgeFile.hash,
                    knowledgeFile.metadataJSON,
                    knowledgeFile.deletedAt?.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    knowledgeFile.byteCount
                ]
            )
        }
    }

    func saveKnowledgeNode(_ knowledgeNode: KnowledgeNodeInput) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT INTO knowledge_nodes (
                        id,
                        name,
                        normalized_name,
                        kind,
                        description,
                        source_chunk_id,
                        embedding,
                        create_date
                    )
                    VALUES (?, ?, ?, ?, ?, ?, CASE WHEN ? IS NULL THEN NULL ELSE vector_as_f32(?) END, ?)
                    ON CONFLICT(normalized_name) DO UPDATE SET
                        name = COALESCE(excluded.name, knowledge_nodes.name),
                        normalized_name = excluded.normalized_name,
                        kind = COALESCE(excluded.kind, knowledge_nodes.kind),
                        description = COALESCE(excluded.description, knowledge_nodes.description),
                        source_chunk_id = COALESCE(excluded.source_chunk_id, knowledge_nodes.source_chunk_id),
                        embedding = COALESCE(excluded.embedding, knowledge_nodes.embedding),
                        create_date = COALESCE(knowledge_nodes.create_date, excluded.create_date)
                    """,
                arguments: [
                    knowledgeNode.id,
                    knowledgeNode.name,
                    knowledgeNode.normalizedName,
                    knowledgeNode.kind,
                    knowledgeNode.description,
                    knowledgeNode.sourceChunkID,
                    knowledgeNode.embedding,
                    knowledgeNode.embedding,
                    knowledgeNode.createDate.formatted(TaskTraceDatabase.sqlTimestampStyle)
                ]
            )
        }
    }

    func updateKnowledgeNode(_ knowledgeNode: KnowledgeNodeInput) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    UPDATE knowledge_nodes
                    SET
                        name = ?,
                        kind = ?,
                        description = ?,
                        source_chunk_id = CASE
                            WHEN ? IS NULL THEN source_chunk_id
                            ELSE ?
                        END,
                        embedding = CASE
                            WHEN ? IS NULL THEN embedding
                            ELSE vector_as_f32(?)
                        END
                    WHERE id = ?
                    """,
                arguments: [
                    knowledgeNode.name,
                    knowledgeNode.kind,
                    knowledgeNode.description,
                    knowledgeNode.sourceChunkID,
                    knowledgeNode.sourceChunkID,
                    knowledgeNode.embedding,
                    knowledgeNode.embedding,
                    knowledgeNode.id
                ]
            )
        }
    }

    func saveKnowledgeEdge(_ knowledgeEdge: KnowledgeEdgeInput) async throws {
        let pair = KnowledgeEdgeRecord.canonicalPair(
            knowledgeEdge.firstNodeID,
            knowledgeEdge.secondNodeID
        )

        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT INTO knowledge_edges (
                        id,
                        first_node_id,
                        second_node_id,
                        relationship_type,
                        description,
                        source_chunk_id,
                        create_date
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(first_node_id, second_node_id) DO UPDATE SET
                        relationship_type = COALESCE(excluded.relationship_type, knowledge_edges.relationship_type),
                        description = COALESCE(excluded.description, knowledge_edges.description),
                        source_chunk_id = COALESCE(excluded.source_chunk_id, knowledge_edges.source_chunk_id),
                        create_date = COALESCE(knowledge_edges.create_date, excluded.create_date)
                    """,
                arguments: [
                    knowledgeEdge.id,
                    pair.firstNodeID,
                    pair.secondNodeID,
                    knowledgeEdge.relationshipType,
                    knowledgeEdge.description,
                    knowledgeEdge.sourceChunkID,
                    knowledgeEdge.createDate.formatted(TaskTraceDatabase.sqlTimestampStyle)
                ]
            )
        }
    }

    func updateKnowledgeEdge(_ knowledgeEdge: KnowledgeEdgeInput) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    UPDATE knowledge_edges
                    SET
                        relationship_type = ?,
                        description = ?,
                        source_chunk_id = CASE
                            WHEN ? IS NULL THEN source_chunk_id
                            ELSE ?
                        END
                    WHERE id = ?
                    """,
                arguments: [
                    knowledgeEdge.relationshipType,
                    knowledgeEdge.description,
                    knowledgeEdge.sourceChunkID,
                    knowledgeEdge.sourceChunkID,
                    knowledgeEdge.id
                ]
            )
        }
    }

    func saveNodeChunk(nodeID: Int64, chunkID: Int64) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO knowledge_node_chunks (node_id, chunk_id)
                    VALUES (?, ?)
                    """,
                arguments: [nodeID, chunkID]
            )
        }
    }

    func saveEdgeChunk(edgeID: Int64, chunkID: Int64) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO knowledge_edge_chunks (edge_id, chunk_id)
                    VALUES (?, ?)
                    """,
                arguments: [edgeID, chunkID]
            )
        }
    }

    func saveNodeActivity(nodeID: Int64, activityID: Int64) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO knowledge_node_activities (node_id, activity_id)
                    VALUES (?, ?)
                    """,
                arguments: [nodeID, activityID]
            )
        }
    }

    func saveEdgeActivity(edgeID: Int64, activityID: Int64) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO knowledge_edge_activities (edge_id, activity_id)
                    VALUES (?, ?)
                    """,
                arguments: [edgeID, activityID]
            )
        }
    }

    func resetKnowledgeFileIndex(fileID: Int64) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(sql: "DELETE FROM knowledge_aliases WHERE file_id = ?", arguments: [fileID])
            try db.execute(
                sql: """
                    DELETE FROM knowledge_links
                    WHERE src_anchor_id IN (
                        SELECT id
                        FROM knowledge_anchors
                        WHERE file_id = ?
                    )
                    """,
                arguments: [fileID]
            )
            try db.execute(
                sql: """
                    DELETE FROM knowledge_chunks
                    WHERE anchor_id IN (
                        SELECT id
                        FROM knowledge_anchors
                        WHERE file_id = ?
                    )
                    """,
                arguments: [fileID]
            )
            try db.execute(sql: "DELETE FROM knowledge_anchors WHERE file_id = ?", arguments: [fileID])
            try db.execute(
                sql: """
                    DELETE FROM knowledge_edges
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM knowledge_edge_chunks
                        WHERE knowledge_edge_chunks.edge_id = knowledge_edges.id
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM knowledge_edge_activities
                        WHERE knowledge_edge_activities.edge_id = knowledge_edges.id
                    )
                    """
            )
            try db.execute(
                sql: """
                    DELETE FROM knowledge_nodes
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM knowledge_node_chunks
                        WHERE knowledge_node_chunks.node_id = knowledge_nodes.id
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM knowledge_node_activities
                        WHERE knowledge_node_activities.node_id = knowledge_nodes.id
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM knowledge_edges
                        WHERE knowledge_edges.first_node_id = knowledge_nodes.id
                           OR knowledge_edges.second_node_id = knowledge_nodes.id
                    )
                    """
            )
            try db.execute(
                sql: """
                    DELETE FROM knowledge_communities
                    WHERE id NOT IN (
                        SELECT DISTINCT community_id
                        FROM knowledge_nodes
                        WHERE community_id IS NOT NULL
                    )
                    """
            )
        }
    }

    func insertKnowledgeAlias(_ alias: KnowledgeAliasInput) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT INTO knowledge_aliases (
                        id,
                        file_id,
                        alias_text
                    )
                    VALUES (?, ?, ?)
                    """,
                arguments: [
                    alias.id,
                    alias.fileID,
                    alias.aliasText
                ]
            )
        }
    }

    func insertKnowledgeAnchor(_ anchor: KnowledgeAnchorInput) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT INTO knowledge_anchors (
                        id,
                        file_id,
                        anchor_type,
                        anchor_key,
                        heading_text,
                        block_id,
                        start_line,
                        end_line,
                        text_hash
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    anchor.id,
                    anchor.fileID,
                    anchor.anchorType,
                    anchor.anchorKey,
                    anchor.headingText,
                    anchor.blockID,
                    anchor.startLine,
                    anchor.endLine,
                    anchor.textHash
                ]
            )
        }
    }

    func insertKnowledgeChunk(_ chunk: KnowledgeChunkInput) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT INTO knowledge_chunks (
                        id,
                        anchor_id,
                        ordinal,
                        hash,
                        text,
                        processed
                    )
                    VALUES (?, ?, ?, ?, ?, 0)
                    """,
                arguments: [
                    chunk.id,
                    chunk.anchorID,
                    chunk.ordinal,
                    chunk.hash,
                    chunk.text
                ]
            )
        }
    }

    func markKnowledgeChunkProcessed(
        chunkID: Int64,
        processed: Bool
    ) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    UPDATE knowledge_chunks
                    SET processed = ?
                    WHERE id = ?
                    """,
                arguments: [processed ? 1 : 0, chunkID]
            )
        }
    }

    func updateKnowledgeNodeEmbedding(
        nodeID: Int64,
        vector: [Float]
    ) async throws {
        let vectorData = try JSONEncoder().encode(vector)
        let vectorJSONString = String(decoding: vectorData, as: UTF8.self)

        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    UPDATE knowledge_nodes
                    SET embedding = vector_as_f32(?)
                    WHERE id = ?
                    """,
                arguments: [vectorJSONString, nodeID]
            )
        }
    }

    func insertKnowledgeLink(_ link: KnowledgeLinkInput) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT INTO knowledge_links (
                        id,
                        src_anchor_id,
                        dst_file_id,
                        dst_anchor_hint,
                        link_text,
                        link_type
                    )
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    link.id,
                    link.srcAnchorID,
                    link.dstFileID,
                    link.dstAnchorHint,
                    link.linkText,
                    link.linkType
                ]
            )
        }
    }

    func updateKnowledgeFileLastAccessed(
        fileID: Int64,
        lastAccessed: Date
    ) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    UPDATE knowledge_files
                    SET last_accessed = ?
                    WHERE id = ?
                    """,
                arguments: [
                    lastAccessed.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    fileID
                ]
            )
        }
    }

    func markKnowledgeFilesDeleted(
        directoryID: Int64,
        retainingPaths: Set<String>,
        deletedAt: Date
    ) async throws {
        try database.vectorAwareWrite { db in
            let staleIDs = try {
                if retainingPaths.isEmpty {
                    return try Int64.fetchAll(
                        db,
                        sql: """
                            SELECT id
                            FROM knowledge_files
                            WHERE directory_id = ?
                              AND deleted_at IS NULL
                            """,
                        arguments: [directoryID]
                    )
                }

                let arguments = StatementArguments(
                    ([directoryID] + retainingPaths.sorted()) as [(any DatabaseValueConvertible)?]
                )

                return try Int64.fetchAll(
                    db,
                    sql: """
                        SELECT id
                        FROM knowledge_files
                        WHERE directory_id = ?
                          AND deleted_at IS NULL
                          AND relative_path NOT IN (\(TaskTraceDatabase.databaseQuestionMarks(count: retainingPaths.count)))
                        """,
                    arguments: arguments
                )
            }()

            guard !staleIDs.isEmpty else {
                return
            }

            for staleID in staleIDs {
                try db.execute(sql: "DELETE FROM knowledge_aliases WHERE file_id = ?", arguments: [staleID])
                try db.execute(
                    sql: """
                        DELETE FROM knowledge_links
                        WHERE src_anchor_id IN (
                            SELECT id
                            FROM knowledge_anchors
                            WHERE file_id = ?
                        )
                        """,
                    arguments: [staleID]
                )
                try db.execute(
                    sql: """
                        DELETE FROM knowledge_chunks
                        WHERE anchor_id IN (
                            SELECT id
                            FROM knowledge_anchors
                            WHERE file_id = ?
                        )
                        """,
                    arguments: [staleID]
                )
                try db.execute(sql: "DELETE FROM knowledge_anchors WHERE file_id = ?", arguments: [staleID])
            }

            try db.execute(
                sql: """
                    DELETE FROM knowledge_edges
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM knowledge_edge_chunks
                        WHERE knowledge_edge_chunks.edge_id = knowledge_edges.id
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM knowledge_edge_activities
                        WHERE knowledge_edge_activities.edge_id = knowledge_edges.id
                    )
                    """
            )
            try db.execute(
                sql: """
                    DELETE FROM knowledge_nodes
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM knowledge_node_chunks
                        WHERE knowledge_node_chunks.node_id = knowledge_nodes.id
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM knowledge_node_activities
                        WHERE knowledge_node_activities.node_id = knowledge_nodes.id
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM knowledge_edges
                        WHERE knowledge_edges.first_node_id = knowledge_nodes.id
                           OR knowledge_edges.second_node_id = knowledge_nodes.id
                    )
                    """
            )
            try db.execute(
                sql: """
                    DELETE FROM knowledge_communities
                    WHERE id NOT IN (
                        SELECT DISTINCT community_id
                        FROM knowledge_nodes
                        WHERE community_id IS NOT NULL
                    )
                    """
            )

            let updateArguments = StatementArguments(
                ([deletedAt.formatted(TaskTraceDatabase.sqlTimestampStyle)] + staleIDs) as [(any DatabaseValueConvertible)?]
            )

            try db.execute(
                sql: """
                    UPDATE knowledge_files
                    SET deleted_at = ?
                    WHERE id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: staleIDs.count)))
                    """,
                arguments: updateArguments
            )
        }
    }

    func saveCommunities(communityByNodeID: [Int64: Int64]) async throws {
        let communityIDs = Set(communityByNodeID.values)

        try database.vectorAwareWrite { db in
            for communityID in communityIDs {
                try db.execute(
                    sql: """
                        INSERT INTO knowledge_communities (id)
                        VALUES (?)
                        ON CONFLICT(id) DO NOTHING
                        """,
                    arguments: [communityID]
                )
            }

            try db.execute(sql: "UPDATE knowledge_nodes SET community_id = NULL")

            for (nodeID, communityID) in communityByNodeID {
                try db.execute(
                    sql: "UPDATE knowledge_nodes SET community_id = ? WHERE id = ?",
                    arguments: [communityID, nodeID]
                )
            }

            try db.execute(
                sql: """
                    DELETE FROM knowledge_communities
                    WHERE id NOT IN (
                        SELECT DISTINCT community_id
                        FROM knowledge_nodes
                        WHERE community_id IS NOT NULL
                    )
                    """
            )
        }
    }

    func updateCommunitySummary(
        communityID: Int64,
        name: String,
        summary: String,
        inputHash: String
    ) async throws {
        try database.vectorAwareWrite { db in
            let baseName = {
                let trimmed = name
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Community \(communityID)" : trimmed
            }()
            let existingNames = try String.fetchAll(
                db,
                sql: """
                    SELECT name
                    FROM knowledge_communities
                    WHERE id != ?
                      AND name IS NOT NULL
                      AND TRIM(name) != ''
                    """,
                arguments: [communityID]
            )
            let normalizedExistingNames = Set(
                existingNames.map(KnowledgeNodeRecord.normalizedName(for:))
            )
            let existingFileNames = Set(
                existingNames.map(KnowledgeObsidianExportNaming.fileName(communityName:))
            )
            let uniqueName = {
                let normalizedBaseName = KnowledgeNodeRecord.normalizedName(for: baseName)
                let baseFileName = KnowledgeObsidianExportNaming.fileName(communityName: baseName)

                guard normalizedExistingNames.contains(normalizedBaseName)
                        || existingFileNames.contains(baseFileName) else {
                    return baseName
                }

                return (2...)
                    .lazy
                    .map { "\(baseName) \($0)" }
                    .first {
                        !normalizedExistingNames.contains(KnowledgeNodeRecord.normalizedName(for: $0))
                            && !existingFileNames.contains(KnowledgeObsidianExportNaming.fileName(communityName: $0))
                    } ?? baseName
            }()

            try db.execute(
                sql: "UPDATE knowledge_communities SET name = ?, summary = ?, summary_input_hash = ? WHERE id = ?",
                arguments: [uniqueName, summary.trimmingCharacters(in: .whitespacesAndNewlines), inputHash, communityID]
            )
        }
    }

    func updateCommunityEmbedding(communityID: Int64, vector: [Float]) async throws {
        let vectorData = try JSONEncoder().encode(vector)
        let vectorJSONString = String(decoding: vectorData, as: UTF8.self)

        try database.vectorAwareWrite { db in
            try db.execute(
                sql: "UPDATE knowledge_communities SET embedding = vector_as_f32(?) WHERE id = ?",
                arguments: [vectorJSONString, communityID]
            )
        }
    }

    func saveKnowledgeClaim(_ claim: KnowledgeClaimInput) async throws {
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT INTO knowledge_claims (id, node_id, text, md5, create_date)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(md5) DO UPDATE SET
                        node_id = excluded.node_id,
                        text = excluded.text,
                        create_date = COALESCE(knowledge_claims.create_date, excluded.create_date)
                    """,
                arguments: [
                    claim.id,
                    claim.nodeID,
                    claim.text,
                    claim.md5,
                    claim.createDate
                ]
            )
        }
    }

    func updateKnowledgeClaimEmbedding(claimID: Int64, vector: [Float]) async throws {
        let vectorData = try JSONEncoder().encode(vector)
        let vectorJSONString = String(decoding: vectorData, as: UTF8.self)

        try database.vectorAwareWrite { db in
            try db.execute(
                sql: "UPDATE knowledge_claims SET embedding = vector_as_f32(?) WHERE id = ?",
                arguments: [vectorJSONString, claimID]
            )
        }
    }
}
