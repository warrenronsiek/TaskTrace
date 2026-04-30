//
//  KnowledgeDatabaseQueueTests.swift
//  TaskTraceTests
//

import Foundation
import GRDB
import Testing
@testable import TaskTrace

struct KnowledgeDatabaseQueueTests {
    private func withDatabase(
        _ block: (TaskTraceDatabase, KnowledgeDatabaseActor) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL)
        let knowledgeDatabaseActor = KnowledgeDatabaseActor(database: database)

        try await block(database, knowledgeDatabaseActor)
    }

    private func installVectorliteProbeTables(_ database: TaskTraceDatabase) throws {
        let nodeProbeVector = "[0.1, 0.2, 0.3]"
        let claimProbeVector = "[0.4, 0.5, 0.6]"
        let communityProbeVector = "[0.7, 0.8, 0.9]"

        try database.vectorAwareWrite { db in
            try db.execute(sql: "DROP TRIGGER IF EXISTS tk_node_embedding_insert_probe")
            try db.execute(sql: "DROP TRIGGER IF EXISTS tk_node_embedding_update_probe")
            try db.execute(sql: "DROP TRIGGER IF EXISTS tk_claim_embedding_insert_probe")
            try db.execute(sql: "DROP TRIGGER IF EXISTS tk_claim_embedding_update_probe")
            try db.execute(sql: "DROP TRIGGER IF EXISTS tk_community_embedding_update_probe")
            try db.execute(sql: "DROP TABLE IF EXISTS tk_node_embedding_probe")
            try db.execute(sql: "DROP TABLE IF EXISTS tk_claim_embedding_probe")
            try db.execute(sql: "DROP TABLE IF EXISTS tk_community_embedding_probe")
            try db.execute(sql: "DROP TABLE IF EXISTS tk_node_embedding_probe_log")
            try db.execute(sql: "DROP TABLE IF EXISTS tk_claim_embedding_probe_log")
            try db.execute(sql: "DROP TABLE IF EXISTS tk_community_embedding_probe_log")

            try db.execute(
                sql: """
                CREATE VIRTUAL TABLE tk_node_embedding_probe
                USING vectorlite(embedding float32[3] cosine, hnsw(max_elements=16))
                """
            )
            try db.execute(
                sql: """
                CREATE VIRTUAL TABLE tk_claim_embedding_probe
                USING vectorlite(embedding float32[3] cosine, hnsw(max_elements=16))
                """
            )
            try db.execute(
                sql: """
                CREATE VIRTUAL TABLE tk_community_embedding_probe
                USING vectorlite(embedding float32[3] cosine, hnsw(max_elements=16))
                """
            )
            try db.execute(
                sql: """
                CREATE TABLE tk_node_embedding_probe_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT
                )
                """
            )
            try db.execute(
                sql: """
                CREATE TABLE tk_claim_embedding_probe_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT
                )
                """
            )
            try db.execute(
                sql: """
                CREATE TABLE tk_community_embedding_probe_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT
                )
                """
            )

            try db.execute(
                sql: """
                CREATE TRIGGER tk_node_embedding_insert_probe
                AFTER INSERT ON knowledge_nodes
                BEGIN
                    INSERT INTO tk_node_embedding_probe_log(id) VALUES (NULL);
                    DELETE FROM tk_node_embedding_probe WHERE rowid = NEW.id;
                    INSERT INTO tk_node_embedding_probe(rowid, embedding)
                    VALUES (NEW.id, vector_from_json('\(nodeProbeVector)'));
                END;
                """
            )
            try db.execute(
                sql: """
                CREATE TRIGGER tk_node_embedding_update_probe
                AFTER UPDATE OF embedding ON knowledge_nodes
                BEGIN
                    INSERT INTO tk_node_embedding_probe_log(id) VALUES (NULL);
                    DELETE FROM tk_node_embedding_probe WHERE rowid = NEW.id;
                    INSERT INTO tk_node_embedding_probe(rowid, embedding)
                    VALUES (NEW.id, vector_from_json('\(nodeProbeVector)'));
                END;
                """
            )
            try db.execute(
                sql: """
                CREATE TRIGGER tk_claim_embedding_insert_probe
                AFTER INSERT ON knowledge_claims
                BEGIN
                    INSERT INTO tk_claim_embedding_probe_log(id) VALUES (NULL);
                    DELETE FROM tk_claim_embedding_probe WHERE rowid = NEW.id;
                    INSERT INTO tk_claim_embedding_probe(rowid, embedding)
                    VALUES (NEW.id, vector_from_json('\(claimProbeVector)'));
                END;
                """
            )
            try db.execute(
                sql: """
                CREATE TRIGGER tk_claim_embedding_update_probe
                AFTER UPDATE OF embedding ON knowledge_claims
                BEGIN
                    INSERT INTO tk_claim_embedding_probe_log(id) VALUES (NULL);
                    DELETE FROM tk_claim_embedding_probe WHERE rowid = NEW.id;
                    INSERT INTO tk_claim_embedding_probe(rowid, embedding)
                    VALUES (NEW.id, vector_from_json('\(claimProbeVector)'));
                END;
                """
            )
            try db.execute(
                sql: """
                CREATE TRIGGER tk_community_embedding_update_probe
                AFTER UPDATE OF embedding ON knowledge_communities
                BEGIN
                    INSERT INTO tk_community_embedding_probe_log(id) VALUES (NULL);
                    DELETE FROM tk_community_embedding_probe WHERE rowid = NEW.id;
                    INSERT INTO tk_community_embedding_probe(rowid, embedding)
                    VALUES (NEW.id, vector_from_json('\(communityProbeVector)'));
                END;
                """
            )
        }
    }

    @Test("database read and write can use both queue handles")
    func databaseReadWriteSupportsBothQueues() async throws {
        try await withDatabase { database, _ in
            try database.write { db in
                try db.execute(sql: "CREATE TABLE db_pool_probe (id INTEGER PRIMARY KEY)")
                try db.execute(sql: "INSERT INTO db_pool_probe(id) VALUES (1)")
            }

            try database.vectorAwareWrite { db in
                try db.execute(sql: "CREATE TABLE db_vector_probe (id INTEGER PRIMARY KEY)")
                try db.execute(sql: "INSERT INTO db_vector_probe(id) VALUES (1)")
            }

            let poolCount = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM db_pool_probe") ?? 0
            }
            let vectorCount = try database.vectorAwareRead { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM db_vector_probe") ?? 0
            }
            let vectorReadFromPool = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM db_vector_probe") ?? 0
            }
            let poolReadFromVectorQueue = try database.vectorAwareRead { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM db_pool_probe") ?? 0
            }

            #expect(poolCount == 1)
            #expect(vectorCount == 1)
            #expect(vectorReadFromPool == 1)
            #expect(poolReadFromVectorQueue == 1)
        }
    }

    @Test("knowledge vector writes use the vector-aware queue")
    func knowledgeVectorWritesUseVectorAwareQueue() async throws {
        try await withDatabase { database, knowledgeDatabaseActor in
            try installVectorliteProbeTables(database)

            let nodeID: Int64 = 101
            let claimID: Int64 = 202
            let communityID: Int64 = 303
            let createdNodeEmbedding = try String(
                decoding: JSONEncoder().encode([0.12, 0.34, 0.56] as [Float]),
                as: UTF8.self
            )
            let updatedNodeEmbedding = try String(
                decoding: JSONEncoder().encode([0.21, 0.43, 0.65] as [Float]),
                as: UTF8.self
            )

            let createdNode = KnowledgeNodeInput(
                id: nodeID,
                name: "Node A",
                normalizedName: KnowledgeNodeRecord.normalizedName(for: "Node A"),
                kind: "note",
                description: "First node",
                sourceChunkID: nil,
                embedding: createdNodeEmbedding,
                createDate: Date()
            )
            let updatedNode = KnowledgeNodeInput(
                id: nodeID,
                name: "Updated Node A",
                normalizedName: KnowledgeNodeRecord.normalizedName(for: "Updated Node A"),
                kind: "note",
                description: "Updated node",
                sourceChunkID: nil,
                embedding: updatedNodeEmbedding,
                createDate: Date()
            )
            let claim = KnowledgeClaimInput(
                id: claimID,
                nodeID: nodeID,
                text: "A claim",
                md5: "claim-md5-1",
                createDate: Date()
            )

            try await knowledgeDatabaseActor.saveKnowledgeNode(createdNode)
            try await knowledgeDatabaseActor.updateKnowledgeNode(updatedNode)
            try await knowledgeDatabaseActor.updateKnowledgeNodeEmbedding(
                nodeID: nodeID,
                vector: [0.11, 0.22, 0.33]
            )

            try await knowledgeDatabaseActor.saveCommunities(communityByNodeID: [nodeID: communityID])
            try await knowledgeDatabaseActor.updateCommunityEmbedding(
                communityID: communityID,
                vector: [0.44, 0.55, 0.66]
            )

            try await knowledgeDatabaseActor.saveKnowledgeClaim(claim)
            try await knowledgeDatabaseActor.updateKnowledgeClaimEmbedding(
                claimID: claimID,
                vector: [0.77, 0.88, 0.99]
            )

            let nodeProbeCount = try database.vectorAwareRead { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tk_node_embedding_probe_log") ?? 0
            }
            let claimProbeCount = try database.vectorAwareRead { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tk_claim_embedding_probe_log") ?? 0
            }
            let communityProbeCount = try database.vectorAwareRead { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tk_community_embedding_probe_log") ?? 0
            }
            let persistedNode = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM knowledge_nodes WHERE id = ?", arguments: [nodeID]) ?? 0
            }
            let persistedClaim = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM knowledge_claims WHERE id = ?", arguments: [claimID]) ?? 0
            }
            let persistedCommunity = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM knowledge_communities WHERE id = ?", arguments: [communityID]) ?? 0
            }
            let claimEmbeddingPersisted = try database.read { db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM knowledge_claims WHERE id = ? AND embedding IS NOT NULL",
                    arguments: [claimID]
                ) ?? 0
            }

            #expect(nodeProbeCount == 3)
            #expect(claimProbeCount == 2)
            #expect(communityProbeCount == 1)
            #expect(persistedNode == 1)
            #expect(persistedClaim == 1)
            #expect(persistedCommunity == 1)
            #expect(claimEmbeddingPersisted == 1)
        }
    }
}
