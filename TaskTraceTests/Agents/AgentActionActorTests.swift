//
//  AgentActionActorTests.swift
//  TaskTraceTests
//
//  Created by Codex on 4/2/26.
//

import Foundation
import Testing
@testable import TaskTrace

struct AgentActionActorTests {
    private func withActor(
        responses: [String] = [],
        _ block: (AgentActionActor, TaskTraceDatabase, FakeAgentActionChannelSender) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let channelSender = FakeAgentActionChannelSender(responses: responses)
        let actor = AgentActionActor(
            agentActionsDatabaseActor: AgentActionsDatabaseActor(database: database),
            channelSender: channelSender
        )

        try await block(actor, database, channelSender)
    }

    @Test("activity summarized sends all configured agent actions")
    func activitySummarizedSendsAllConfiguredAgentActions() async throws {
        try await withActor(responses: ["ok", "ok"]) { actor, database, channelSender in
            try await database.save(.agentAction(.record(AgentActionInput(
                id: 1,
                instructions: "Handle summarized activity",
                eventType: .activitySummarized,
                conversationID: "conversation-1"
            ))))
            try await database.save(.agentAction(.record(AgentActionInput(
                id: 2,
                instructions: "Queue summarized activity for review",
                eventType: .activitySummarized,
                conversationID: "conversation-2"
            ))))

            await actor.activitySummarized()
            try await waitForRequestCount(channelSender, count: 2)

            #expect(await channelSender.requests().map(\.message) == [
                "Queue summarized activity for review",
                "Handle summarized activity"
            ])
        }
    }

    @Test("activity summarized forwards the stored instructions")
    func activitySummarizedForwardsTheStoredInstructions() async throws {
        try await withActor(responses: ["ok"]) { actor, database, channelSender in
            try await database.save(.agentAction(.record(AgentActionInput(
                id: 1,
                instructions: "Handle activity summary",
                eventType: .activitySummarized,
                conversationID: "conversation-1"
            ))))

            await actor.activitySummarized()
            try await waitForRequestCount(channelSender, count: 1)

            #expect(await channelSender.requests().first?.message == "Handle activity summary")
        }
    }

    @Test("activity summarized forwards the stored event type")
    func activitySummarizedForwardsTheStoredEventType() async throws {
        try await withActor(responses: ["ok"]) { actor, database, channelSender in
            try await database.save(.agentAction(.record(AgentActionInput(
                id: 1,
                instructions: "Handle activity summary",
                eventType: .activitySummarized,
                conversationID: "conversation-1"
            ))))

            await actor.activitySummarized()
            try await waitForRequestCount(channelSender, count: 1)

            #expect(await channelSender.requests().first?.eventType == "activity_summarized")
        }
    }

    @Test("queued summarized activities collapse into one follow-up send behind an in-flight action send")
    func queuedSummarizedActivitiesCollapseIntoOneFollowUpSendBehindAnInFlightActionSend() async throws {
        try await withActor(responses: []) { actor, database, channelSender in
            try await database.save(.agentAction(.record(AgentActionInput(
                id: 1,
                instructions: "Handle activity summary",
                eventType: .activitySummarized,
                conversationID: "conversation-1"
            ))))

            await actor.activitySummarized()
            try await waitForRequestCount(channelSender, count: 1)

            await actor.activitySummarized()
            await actor.activitySummarized()
            await channelSender.finishNextResponse()
            try await waitForRequestCount(channelSender, count: 2)
        }
    }

    private func waitForRequestCount(
        _ channelSender: FakeAgentActionChannelSender,
        count: Int,
        attempts: Int = 40
    ) async throws {
        for _ in 0..<attempts {
            if await channelSender.requests().count == count {
                return
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        Issue.record("Timed out waiting for request count \(count)")
    }
}

private actor FakeAgentActionChannelSender: AgentActionChannelSending {
    private var queuedResponses: [String]
    private var capturedRequests: [AgentActionChannelRequest]
    private var waitingContinuations: [CheckedContinuation<String?, Never>]

    init(responses: [String]) {
        self.queuedResponses = responses
        self.capturedRequests = []
        self.waitingContinuations = []
    }

    func sendAgentAction(_ request: AgentActionChannelRequest) async -> String? {
        capturedRequests.append(request)

        guard !queuedResponses.isEmpty else {
            return await withCheckedContinuation { continuation in
                waitingContinuations.append(continuation)
            }
        }

        return queuedResponses.removeFirst()
    }

    func enqueueResponse(_ response: String) {
        queuedResponses.append(response)
    }

    func finishNextResponse() {
        guard !waitingContinuations.isEmpty else {
            return
        }

        let continuation = waitingContinuations.removeFirst()
        let response = queuedResponses.isEmpty ? nil : queuedResponses.removeFirst()
        continuation.resume(returning: response)
    }

    func requests() -> [AgentActionChannelRequest] {
        capturedRequests
    }
}
