//
//  AgentActionsStoreTests.swift
//  TaskTraceTests
//
//  Created by Codex on 4/1/26.
//

import Foundation
import GRDB
import Testing
@testable import TaskTrace

@MainActor
struct AgentActionsStoreTests {
    private func withStore(
        now: @escaping @Sendable () -> Date = Date.init,
        conversationIDGenerator: @escaping @Sendable () -> String = { UUID().uuidString },
        _ block: (AgentActionsStore, TaskTraceDatabase) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let store = AgentActionsStore(
            database: database,
            now: now,
            identifierActor: IdentifierActor(now: now),
            conversationIDGenerator: conversationIDGenerator
        )

        try await block(store, database)
    }

    @Test("load returns saved agent actions")
    func loadReturnsSavedAgentActions() async throws {
        try await withStore { store, database in
            try await database.save(.agentAction(.record(AgentActionInput(
                id: 1,
                instructions: "Create a recap when a new activity is summarized.",
                eventType: .activitySummarized,
                conversationID: "conversation-1"
            ))))

            await store.load()
            #expect(store.agentActions.map(\.id) == [1])
        }
    }

    @Test("saving a new agent action creates a generated conversation id")
    func savingANewAgentActionCreatesAGeneratedConversationID() async throws {
        try await withStore(
            now: { Date(timeIntervalSince1970: 10) },
            conversationIDGenerator: { "generated-conversation" }
        ) { store, database in
            store.startAdding()
            store.currentInstructions = "Notify the agent when an activity is summarized."

            await store.saveCurrentAgentAction()

            let conversationID: String? = switch try await database.get(.agentAction(.id(10_000))) {
            case let .agentAction(agentAction):
                agentAction?.conversationID
            default:
                nil
            }

            #expect(conversationID == "generated-conversation")
        }
    }

    @Test("saving ignores unsupported existing agent action event types")
    func savingIgnoresUnsupportedExistingAgentActionEventTypes() async throws {
        try await withStore(
            now: { Date(timeIntervalSince1970: 10) },
            conversationIDGenerator: { "generated-conversation" }
        ) { store, database in
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
                        """,
                    arguments: [
                        9,
                        "Malformed existing action",
                        "unknown_event",
                        "malformed-conversation"
                    ]
                )
            }

            store.startAdding()
            store.currentInstructions = "Notify the agent when an activity is summarized."

            await store.saveCurrentAgentAction()

            #expect(store.errorMessage == nil)
        }
    }

    @Test("editing an agent action preserves the existing conversation id")
    func editingAnAgentActionPreservesTheExistingConversationID() async throws {
        try await withStore { store, database in
            try await database.save(.agentAction(.record(AgentActionInput(
                id: 42,
                instructions: "Original instructions",
                eventType: .activitySummarized,
                conversationID: "existing-conversation"
            ))))

            await store.load()
            store.startEditing(agentActionID: 42)
            store.currentInstructions = "Updated instructions"
            await store.saveCurrentAgentAction()

            let conversationID: String? = switch try await database.get(.agentAction(.id(42))) {
            case let .agentAction(agentAction):
                agentAction?.conversationID
            default:
                nil
            }

            #expect(conversationID == "existing-conversation")
        }
    }

    @Test("deleting an agent action removes it from the store")
    func deletingAnAgentActionRemovesItFromTheStore() async throws {
        try await withStore { store, database in
            try await database.save(.agentAction(.record(AgentActionInput(
                id: 7,
                instructions: "Delete me",
                eventType: .activitySummarized,
                conversationID: "conversation-7"
            ))))

            await store.load()
            await store.deleteAgentAction(id: 7)
            #expect(store.agentActions.isEmpty)
        }
    }
}
