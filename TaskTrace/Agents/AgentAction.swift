//
//  AgentAction.swift
//  TaskTrace
//
//  Created by Codex on 4/1/26.
//

import Foundation
import GRDB

enum AgentActionEventType: String, Codable, Equatable, Sendable {
    case activitySummarized = "activity_summarized"
}

struct AgentActionRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "agent_actions"

    let id: Int64
    let instructions: String
    let eventType: AgentActionEventType
    let conversationID: String

    enum CodingKeys: String, CodingKey {
        case id
        case instructions
        case eventType = "event_type"
        case conversationID = "conversation_id"
    }
}

struct AgentActionInput: Equatable, Sendable {
    let id: Int64
    let instructions: String
    let eventType: AgentActionEventType
    let conversationID: String
}
