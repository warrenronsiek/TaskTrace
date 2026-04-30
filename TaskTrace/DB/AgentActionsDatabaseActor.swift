//
//  AgentActionsDatabaseActor.swift
//  TaskTrace
//
//  Created by Codex on 4/11/26.
//

import Foundation
import GRDB

actor AgentActionsDatabaseActor {
    private let database: TaskTraceDatabase

    init(database: TaskTraceDatabase) {
        self.database = database
    }

    func loadAgentActions() async throws -> [AgentActionRecord] {
        try database.read { db in
            try AgentActionRecord.fetchAll(
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
            )
        }
    }

    func saveAgentAction(_ agentAction: AgentActionInput) async throws {
        try database.write { db in
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
        }
    }

    func deleteAgentAction(id: Int64) async throws {
        try database.write { db in
            try db.execute(
                sql: "DELETE FROM agent_actions WHERE id = ?",
                arguments: [id]
            )
        }
    }
}
