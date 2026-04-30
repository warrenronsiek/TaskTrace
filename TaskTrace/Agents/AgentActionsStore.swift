//
//  AgentActionsStore.swift
//  TaskTrace
//
//  Created by Codex on 4/1/26.
//

import Combine
import Foundation

@MainActor
final class AgentActionsStore: ObservableObject {
    @Published private(set) var agentActions: [AgentActionRecord]
    @Published private(set) var socketPath: String
    @Published private(set) var agentsEnabled: Bool
    @Published private(set) var isListening: Bool
    @Published private(set) var connectedClients: Int
    @Published private(set) var transportEvents: [AgentChannelActor.TransportEvent]
    @Published private(set) var conversationHistoryByConversationID: [String: [AgentChannelActor.ChatEntry]]
    @Published private(set) var isAdding: Bool
    @Published private(set) var editingAgentActionID: Int64?
    @Published var currentInstructions: String
    @Published private(set) var errorMessage: String?

    private let agentActionsDatabaseActor: AgentActionsDatabaseActor?
    private let agentChannelActor: AgentChannelActor?
    private let identifierActor: IdentifierActor
    private let conversationIDGenerator: @Sendable () -> String
    private var currentConversationID: String?
    private var channelUpdatesTask: Task<Void, Never>?

    var isEditing: Bool {
        editingAgentActionID != nil
    }

    init(
        agentActionsDatabaseActor: AgentActionsDatabaseActor,
        agentChannelActor: AgentChannelActor? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        identifierActor: IdentifierActor = .shared,
        conversationIDGenerator: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.agentActionsDatabaseActor = agentActionsDatabaseActor
        self.agentChannelActor = agentChannelActor
        self.identifierActor = identifierActor
        self.agentActions = []
        self.socketPath = Vars.openClawChannelSocketPath
        self.agentsEnabled = true
        self.isListening = false
        self.connectedClients = 0
        self.transportEvents = []
        self.conversationHistoryByConversationID = [:]
        self.isAdding = false
        self.editingAgentActionID = nil
        self.currentInstructions = ""
        self.errorMessage = nil
        self.conversationIDGenerator = conversationIDGenerator
        self.currentConversationID = nil
        self.channelUpdatesTask = agentChannelActor.map { agentChannelActor in
            Task { @MainActor in
                let updates = await agentChannelActor.updates()

                for await state in updates {
                    self.socketPath = state.socketPath
                    self.agentsEnabled = state.isEnabled
                    self.isListening = state.isListening
                    self.connectedClients = state.connectedClients
                    self.transportEvents = state.transportEvents
                    self.conversationHistoryByConversationID = state.conversationHistoryByConversationID
                    self.errorMessage = state.errorMessage
                }
            }
        }
    }

    convenience init(
        database: TaskTraceDatabase,
        agentChannelActor: AgentChannelActor? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        identifierActor: IdentifierActor = .shared,
        conversationIDGenerator: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.init(
            agentActionsDatabaseActor: AgentActionsDatabaseActor(database: database),
            agentChannelActor: agentChannelActor,
            now: now,
            identifierActor: identifierActor,
            conversationIDGenerator: conversationIDGenerator
        )
    }

    init(previewAgentActions: [AgentActionRecord]) {
        self.agentActionsDatabaseActor = nil
        self.agentChannelActor = nil
        self.agentActions = previewAgentActions
        self.socketPath = Vars.openClawChannelSocketPath
        self.agentsEnabled = true
        self.isListening = false
        self.connectedClients = 0
        self.transportEvents = []
        self.conversationHistoryByConversationID = [:]
        self.isAdding = false
        self.editingAgentActionID = nil
        self.currentInstructions = ""
        self.errorMessage = nil
        self.identifierActor = .shared
        self.conversationIDGenerator = { UUID().uuidString }
        self.currentConversationID = nil
        self.channelUpdatesTask = nil
    }

    deinit {
        channelUpdatesTask?.cancel()
    }

    func load() async {
        guard let agentActionsDatabaseActor else {
            return
        }

        do {
            agentActions = try await agentActionsDatabaseActor.loadAgentActions()
            errorMessage = nil
        } catch {
            errorMessage = "Could not load agent actions."
        }
    }

    func startAdding() {
        isAdding = true
        editingAgentActionID = nil
        currentInstructions = ""
        currentConversationID = nil
        errorMessage = nil
    }

    func cancelAdding() {
        isAdding = false
        currentInstructions = ""
        currentConversationID = nil
        errorMessage = nil
    }

    func startEditing(agentActionID: Int64) {
        guard let agentAction = agentActions.first(where: { $0.id == agentActionID }) else {
            return
        }

        editingAgentActionID = agentActionID
        isAdding = false
        currentInstructions = agentAction.instructions
        currentConversationID = agentAction.conversationID
        errorMessage = nil
    }

    func cancelEditing() {
        editingAgentActionID = nil
        currentInstructions = ""
        currentConversationID = nil
        errorMessage = nil
    }

    func saveCurrentAgentAction() async {
        let trimmedInstructions = currentInstructions.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedInstructions.isEmpty else {
            errorMessage = "Instructions cannot be empty."
            return
        }

        guard let agentActionsDatabaseActor else {
            return
        }

        let identifier = if let editingAgentActionID {
            editingAgentActionID
        } else {
            await identifierActor.makeIdentifier(minimum: (agentActions.map(\.id).max() ?? 0) + 1)
        }

        let conversationID = currentConversationID ?? conversationIDGenerator()

        do {
            try await agentActionsDatabaseActor.saveAgentAction(AgentActionInput(
                id: identifier,
                instructions: trimmedInstructions,
                eventType: .activitySummarized,
                conversationID: conversationID
            ))
            agentActions = try await agentActionsDatabaseActor.loadAgentActions()
            isAdding = false
            editingAgentActionID = nil
            currentInstructions = ""
            currentConversationID = nil
            errorMessage = nil
        } catch {
            errorMessage = "Could not save agent action."
        }
    }

    func deleteAgentAction(id: Int64) async {
        guard let agentActionsDatabaseActor else {
            return
        }

        do {
            try await agentActionsDatabaseActor.deleteAgentAction(id: id)
            await load()

            if editingAgentActionID == id {
                editingAgentActionID = nil
                currentInstructions = ""
                currentConversationID = nil
            }

            errorMessage = nil
        } catch {
            errorMessage = "Could not delete agent action."
        }
    }

    func conversationHistory(for agentActionID: Int64) -> [AgentChannelActor.ChatEntry] {
        guard let conversationID = agentActions.first(where: { $0.id == agentActionID })?.conversationID else {
            return []
        }

        return conversationHistoryByConversationID[conversationID] ?? []
    }

    func sendChatMessage(
        agentActionID: Int64,
        text: String
    ) async {
        guard let conversationID = agentActions.first(where: { $0.id == agentActionID })?.conversationID,
              let agentChannelActor else {
            return
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            return
        }

        _ = await agentChannelActor.sendChatMessage(
            conversationID: conversationID,
            message: trimmedText
        )
    }
}
