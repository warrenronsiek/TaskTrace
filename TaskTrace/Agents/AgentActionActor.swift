//
//  AgentActionActor.swift
//  TaskTrace
//
//  Created by Codex on 4/2/26.
//

import Foundation
import OSLog

nonisolated struct AgentActionChannelRequest: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, Codable, Equatable, Sendable {
        case agentAction = "agent_action"
        case chatMessage = "chat_message"
    }

    let kind: Kind
    let conversationID: String
    let message: String?
    let eventType: String?

    init(
        kind: Kind,
        conversationID: String,
        message: String,
        eventType: String? = nil
    ) {
        self.kind = kind
        self.conversationID = conversationID
        self.message = message
        self.eventType = eventType
    }
}

nonisolated protocol AgentActionChannelSending: Sendable {
    func sendAgentAction(_ request: AgentActionChannelRequest) async -> String?
}

actor AgentActionActor {
    private let agentActionsDatabaseActor: AgentActionsDatabaseActor
    private let channelSender: any AgentActionChannelSending
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "agents")
    private var queuedActivityCountsByActionID: [Int64: Int]
    private var drainingActionIDs: Set<Int64>

    init(
        agentActionsDatabaseActor: AgentActionsDatabaseActor,
        channelSender: any AgentActionChannelSending,
    ) {
        self.agentActionsDatabaseActor = agentActionsDatabaseActor
        self.channelSender = channelSender
        self.queuedActivityCountsByActionID = [:]
        self.drainingActionIDs = []
    }

    func activitySummarized() async {
        do {
            let actions = try await agentActionsDatabaseActor.loadAgentActions()

            for action in actions {
                self.queuedActivityCountsByActionID[action.id, default: 0] += 1
                self.logger.log(
                    "queued agent activity actionID=\(action.id, privacy: .public) depth=\(self.queuedActivityCountsByActionID[action.id, default: 0], privacy: .public)"
                )

                guard !self.drainingActionIDs.contains(action.id) else {
                    continue
                }

                self.drainingActionIDs.insert(action.id)
                Task {
                    await self.drainQueuedEvents(for: action)
                }
            }
        } catch {
            return
        }
    }

    private func drainQueuedEvents(for action: AgentActionRecord) async {
        while true {
            let queuedActivityCount = self.queuedActivityCountsByActionID.removeValue(forKey: action.id) ?? 0

            guard queuedActivityCount > 0 else {
                self.drainingActionIDs.remove(action.id)
                self.logger.log("agent queue drained actionID=\(action.id, privacy: .public)")
                return
            }

            self.logger.log(
                "flushing agent queue actionID=\(action.id, privacy: .public) activityBatchSize=\(queuedActivityCount, privacy: .public)"
            )

            _ = await self.channelSender.sendAgentAction(
                AgentActionChannelRequest(
                    kind: .agentAction,
                    conversationID: action.conversationID,
                    message: action.instructions,
                    eventType: action.eventType.rawValue
                )
            )
        }
    }
}
