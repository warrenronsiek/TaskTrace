import Testing
@testable import TaskTrace

struct AgentChatMessageParserTests {
    private func entry(
        direction: AgentChannelActor.ChatEntry.Direction,
        content: String
    ) -> AgentChannelActor.ChatEntry {
        AgentChannelActor.ChatEntry(
            direction: direction,
            content: content
        )
    }

    @Test("inbound structured response exposes the content text")
    func inboundStructuredResponseExposesTheContentText() {
        let parsed = AgentChatMessageParser.parse(
            entry(
                direction: .inbound,
                content: #"{"importance":"high","content":"Check the MCP restart path."}"#
            )
        )

        #expect(parsed.content == "Check the MCP restart path.")
    }

    @Test("inbound structured response exposes the importance")
    func inboundStructuredResponseExposesTheImportance() {
        let parsed = AgentChatMessageParser.parse(
            entry(
                direction: .inbound,
                content: #"{"importance":"high","content":"Check the MCP restart path."}"#
            )
        )

        #expect(parsed.importance == "high")
    }

    @Test("manual outbound chat drops the transport envelope")
    func manualOutboundChatDropsTheTransportEnvelope() {
        let parsed = AgentChatMessageParser.parse(
            entry(
                direction: .outbound,
                content: #"{"kind":"chat_message","conversationID":"abc-123","message":"Just send the summary."}"#
            )
        )

        #expect(parsed.content == "Just send the summary.")
    }

    @Test("agent action outbound chat drops metadata and queued payloads")
    func agentActionOutboundChatDropsMetadataAndQueuedPayloads() {
        let parsed = AgentChatMessageParser.parse(
            entry(
                direction: .outbound,
                content: #"{"kind":"agent_action","conversationID":"abc-123","message":"Search TaskTrace first, then the web.","eventType":"activity_summarized","queuedEventPayloads":["payload-1"]}"#
            )
        )

        #expect(parsed.content == "Search TaskTrace first, then the web.")
    }

    @Test("plain outbound text still renders as plain text")
    func plainOutboundTextStillRendersAsPlainText() {
        let parsed = AgentChatMessageParser.parse(
            entry(
                direction: .outbound,
                content: "Fallback plain text"
            )
        )

        #expect(parsed.content == "Fallback plain text")
    }
}
