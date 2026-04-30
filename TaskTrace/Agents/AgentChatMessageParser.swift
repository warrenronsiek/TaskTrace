import Foundation

nonisolated struct ParsedAgentChatMessage: Equatable, Sendable {
    let label: String
    let content: String
    let importance: String?
}

nonisolated enum AgentChatMessageParser {
    nonisolated static func parse(_ entry: AgentChannelActor.ChatEntry) -> ParsedAgentChatMessage {
        parse(rawMessage: entry.content, direction: entry.direction)
    }

    nonisolated static func parseStructuredResponse(rawMessage: String) -> (importance: String, content: String)? {
        let strippedMessage = stripped(rawMessage)

        guard let data = strippedMessage.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let importance = object["importance"] as? String,
              let content = object["content"] as? String else {
            return nil
        }

        let normalizedImportance = importance
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedContent = content
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedImportance.isEmpty, !normalizedContent.isEmpty else {
            return nil
        }

        return (normalizedImportance, normalizedContent)
    }

    private nonisolated static func parse(
        rawMessage: String,
        direction: AgentChannelActor.ChatEntry.Direction
    ) -> ParsedAgentChatMessage {
        let strippedMessage = stripped(rawMessage)

        if direction == .inbound,
           let structuredResponse = parseStructuredResponse(rawMessage: strippedMessage) {
            return ParsedAgentChatMessage(
                label: "OpenClaw",
                content: structuredResponse.content,
                importance: structuredResponse.importance
            )
        }

        if let data = strippedMessage.data(using: .utf8),
           let request = try? JSONDecoder().decode(AgentActionChannelRequest.self, from: data) {
            let normalizedMessage = {
                let message = request.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                return message?.isEmpty == false ? message : nil
            }()
            switch request.kind {
            case .chatMessage:
                return ParsedAgentChatMessage(
                    label: "You",
                    content: normalizedMessage ?? strippedMessage,
                    importance: nil
                )
            case .agentAction:
                return ParsedAgentChatMessage(
                    label: "TaskTrace",
                    content: normalizedMessage ?? strippedMessage,
                    importance: nil
                )
            }
        }

        return ParsedAgentChatMessage(
            label: direction == .inbound ? "OpenClaw" : "TaskTrace",
            content: strippedMessage,
            importance: nil
        )
    }

    private nonisolated static func stripped(_ rawMessage: String) -> String {
        rawMessage
            .replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
