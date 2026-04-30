//
//  KnowledgeCommunitySummaryActor.swift
//  TaskTrace
//

import CryptoKit
import Foundation
import MLXLMCommon
import OSLog

actor KnowledgeCommunitySummaryActor: Receiver {
    struct Request: Sendable {
        let buildID: Int64?
        let communityID: Int64
    }

    nonisolated static let directSummaryMaxTokens = 320
    nonisolated static let chunkSummaryMaxTokens = 180

    nonisolated static let summarizeInstructions =
        """
        You summarize a knowledge graph community (a cluster of related entities and relationships).
        Return markdown only.
        Use exactly this structure:

        Name: a short specific title for the community
        Summary: one concise paragraph describing the community

        The name should be 2 to 6 words, concrete, and specific.
        The summary should capture what the community is about, who/what the key entities are, how they relate, and the most specific grounded facts from the claims.
        Be concise and factual.
        Do not invent facts not present in the input.
        Prefer incorporating concrete claim details when they materially enrich the summary.
        """

    nonisolated static let summarizeChunkInstructions =
        """
        You summarize one evidence chunk from a larger knowledge graph community.
        Return markdown only.
        Use exactly this structure:

        Summary: concise factual notes from this evidence chunk

        Capture concrete entities, relationships, and claims that matter for the final community summary.
        Do not invent facts not present in the input.
        """

    private let actorSystem: ActorSystem
    private let knowledgeDatabaseActor: KnowledgeDatabaseActor
    private let debounceDelay: Duration
    private var pendingTextRequests: [UUID: PendingTextRequest] = [:]
    private var pendingReductions: [UUID: PendingReduction] = [:]
    private var scheduledRequestIDsByCommunityID: [Int64: UUID] = [:]
    private var activeInputHashByCommunityID: [Int64: String] = [:]
    private var queuedRequestByCommunityID: [Int64: Request] = [:]
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    private enum PendingTextRequest: Sendable {
        case final(request: Request, inputHash: String)
        case reduction(operationID: UUID, stage: AIRecursivePromptReducer.Stage)
    }

    private struct PendingReduction: Sendable {
        let request: Request
        let inputHash: String
        var state: AIRecursivePromptReducer.ReductionState
    }

    init(
        actorSystem: ActorSystem,
        knowledgeDatabaseActor: KnowledgeDatabaseActor,
        textResponder: (any AITextResponding)? = nil,
        debounceDelay: Duration = .seconds(2)
    ) {
        self.actorSystem = actorSystem
        self.knowledgeDatabaseActor = knowledgeDatabaseActor
        self.debounceDelay = debounceDelay
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as CommunitiesGenerated:
            Set(event.communityByNodeID.values).forEach { communityID in
                schedule(
                    Request(
                        buildID: event.buildID,
                        communityID: communityID
                    ),
                    delay: debounceDelay
                )
            }
        case _ as KnowledgeBuildCompleted:
            return
        case let event as ModelTextCompleted:
            await handleCompleted(event)
        case let event as ModelTextFailed:
            await handleFailed(event)
        default:
            return
        }
    }

    private func schedule(_ request: Request, delay: Duration) {
        let requestID = UUID()
        scheduledRequestIDsByCommunityID[request.communityID] = requestID

        Task {
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }

            await self.processScheduled(
                request,
                requestID: requestID
            )
        }
    }

    private func processScheduled(
        _ request: Request,
        requestID: UUID
    ) async {
        guard scheduledRequestIDsByCommunityID[request.communityID] == requestID else {
            return
        }

        scheduledRequestIDsByCommunityID.removeValue(forKey: request.communityID)
        await process(request)
    }

    private func process(_ request: Request) async {
        do {
            let summaryInput = try await knowledgeDatabaseActor.loadCommunitySummaryInput(communityID: request.communityID)

            guard !summaryInput.nodes.isEmpty else {
                return
            }

            let prompt = Self.buildSummarizePrompt(summaryInput: summaryInput)
            let inputHash = Self.sha256Hex(of: prompt)
            let normalizedExistingSummary = summaryInput.currentSummary?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if summaryInput.summaryInputHash == inputHash,
               !(normalizedExistingSummary?.isEmpty ?? true) {
                return
            }

            if let activeInputHash = activeInputHashByCommunityID[request.communityID] {
                if activeInputHash != inputHash {
                    queuedRequestByCommunityID[request.communityID] = request
                }
                return
            }

            if AIRecursivePromptReducer.fitsHardLimit(
                prompt: prompt,
                instructions: Self.summarizeInstructions,
                tokenBudget: AIRecursivePromptReducer.knowledgeSummaryTokenBudget
            ) {
                let modelRequest = try AIRecursivePromptReducer.makeRequest(
                    source: "knowledge-community-summary",
                    priority: .interactive,
                    prompt: prompt,
                    instructions: Self.summarizeInstructions,
                    generateParameters: GenerateParameters(maxTokens: Self.directSummaryMaxTokens, temperature: 0),
                    additionalContext: ["enable_thinking": false],
                    tokenBudget: AIRecursivePromptReducer.knowledgeSummaryTokenBudget
                )
                activeInputHashByCommunityID[request.communityID] = inputHash
                pendingTextRequests[modelRequest.requestID] = .final(
                    request: request,
                    inputHash: inputHash
                )
                await actorSystem.broadcast(from: nil, message: modelRequest)
            } else {
                let state = AIRecursivePromptReducer.ReductionState(
                    source: "knowledge-community-summary",
                    priority: .interactive,
                    evidenceItems: Self.buildSummaryEvidenceItems(summaryInput: summaryInput),
                    finalPromptHeader: """
                    These are evidence items and partial summaries from one knowledge graph community.
                    Create the final community name and summary from this material.
                    """,
                    finalInstructions: Self.summarizeInstructions,
                    finalGenerateParameters: GenerateParameters(maxTokens: Self.directSummaryMaxTokens, temperature: 0),
                    chunkPromptHeader: """
                    This is one chunk of evidence from a larger knowledge graph community.
                    Summarize only the concrete facts present in this chunk.
                    """,
                    chunkInstructions: Self.summarizeChunkInstructions,
                    chunkGenerateParameters: GenerateParameters(maxTokens: Self.chunkSummaryMaxTokens, temperature: 0),
                    additionalContext: ["enable_thinking": false],
                    tokenBudget: AIRecursivePromptReducer.knowledgeSummaryTokenBudget
                )
                activeInputHashByCommunityID[request.communityID] = inputHash
                await dispatchNextReduction(
                    PendingReduction(
                        request: request,
                        inputHash: inputHash,
                        state: state
                    )
                )
            }
        } catch {
            logger.error(
                "knowledge-community-summary-actor failed communityID=\(request.communityID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func handleCompleted(_ event: ModelTextCompleted) async {
        guard let pending = pendingTextRequests.removeValue(forKey: event.requestID) else {
            return
        }

        switch pending {
        case .final(let request, let inputHash):
            await completeSummary(
                request: request,
                inputHash: inputHash,
                rawResponse: event.response
            )
            await finishActiveRequest(communityID: request.communityID)
        case .reduction(let operationID, let stage):
            guard var reduction = pendingReductions.removeValue(forKey: operationID) else {
                return
            }

            switch stage {
            case .chunk:
                reduction.state.acceptChunkResponse(event.response)
                await dispatchNextReduction(reduction)
            case .final:
                reduction.state.acceptFinalResponse()
                await completeSummary(
                    request: reduction.request,
                    inputHash: reduction.inputHash,
                    rawResponse: event.response
                )
                await finishActiveRequest(communityID: reduction.request.communityID)
            }
        }
    }

    private func handleFailed(_ event: ModelTextFailed) async {
        guard let pending = pendingTextRequests.removeValue(forKey: event.requestID) else {
            return
        }

        switch pending {
        case .final(let request, _):
            logger.error(
                "knowledge-community-summary-actor failed communityID=\(request.communityID, privacy: .public) error=\(event.message, privacy: .public)"
            )
            await finishActiveRequest(communityID: request.communityID)
        case .reduction(let operationID, _):
            if let reduction = pendingReductions.removeValue(forKey: operationID) {
                logger.error(
                    "knowledge-community-summary-actor failed communityID=\(reduction.request.communityID, privacy: .public) error=\(event.message, privacy: .public)"
                )
                await finishActiveRequest(communityID: reduction.request.communityID)
            }
        }
    }

    private func dispatchNextReduction(_ reduction: PendingReduction) async {
        var reduction = reduction

        do {
            let next = try reduction.state.nextRequest()
            pendingReductions[reduction.state.operationID] = reduction
            pendingTextRequests[next.request.requestID] = .reduction(
                operationID: reduction.state.operationID,
                stage: next.stage
            )
            await actorSystem.broadcast(from: nil, message: next.request)
        } catch {
            pendingReductions.removeValue(forKey: reduction.state.operationID)
            logger.error(
                "knowledge-community-summary-actor failed communityID=\(reduction.request.communityID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            await finishActiveRequest(communityID: reduction.request.communityID)
        }
    }

    private func finishActiveRequest(communityID: Int64) async {
        activeInputHashByCommunityID.removeValue(forKey: communityID)

        guard let queuedRequest = queuedRequestByCommunityID.removeValue(forKey: communityID) else {
            return
        }

        await process(queuedRequest)
    }

    private func completeSummary(
        request: Request,
        inputHash: String,
        rawResponse: String
    ) async {
        let response = AITextUtilities.strippingThinkingBlocks(from: rawResponse)
        let name = Self.parseName(response) ?? "Untitled Community"
        let summary = Self.parseSummary(response) ?? response.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !summary.isEmpty else {
            return
        }

        await actorSystem.broadcast(
            from: nil,
            message: CommunitySummarized(
                buildID: request.buildID,
                communityID: request.communityID,
                name: name,
                summary: summary,
                inputHash: inputHash
            )
        )
    }

    nonisolated static func buildSummarizePrompt(
        summaryInput: KnowledgeCommunitySummaryInput
    ) -> String {
        let nodes = summaryInput.nodes.sorted {
            if $0.normalizedName != $1.normalizedName {
                return $0.normalizedName < $1.normalizedName
            }

            return $0.id < $1.id
        }
        let edges = summaryInput.edges.sorted {
            if $0.firstNodeID != $1.firstNodeID {
                return $0.firstNodeID < $1.firstNodeID
            }
            if $0.secondNodeID != $1.secondNodeID {
                return $0.secondNodeID < $1.secondNodeID
            }
            let firstType = $0.relationshipType ?? ""
            let secondType = $1.relationshipType ?? ""
            if firstType != secondType {
                return firstType < secondType
            }
            if $0.description != $1.description {
                return $0.description < $1.description
            }

            return $0.id < $1.id
        }
        var lines: [String] = ["## Entities"]
        nodes.forEach { node in
            lines.append("Name: \(node.name)")
            node.kind.map { lines.append("Type: \($0)") }
            node.description.map { lines.append("Description: \($0)") }
            let claims = (summaryInput.claimsByNodeID[node.id] ?? []).sorted {
                if $0.createDate != $1.createDate {
                    return $0.createDate < $1.createDate
                }

                return $0.id < $1.id
            }
            if !claims.isEmpty {
                lines.append("Claims:")
                claims.forEach { claim in
                    lines.append("- \(claim.text)")
                }
            }
            lines.append("---")
        }

        lines.append("")
        lines.append("## Relationships")

        let nodeNameByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.name) })
        edges.forEach { edge in
            guard let sourceName = nodeNameByID[edge.firstNodeID],
                  let targetName = nodeNameByID[edge.secondNodeID] else {
                return
            }

            lines.append("Source: \(sourceName)")
            lines.append("Target: \(targetName)")
            edge.relationshipType.map { lines.append("Type: \($0)") }
            lines.append("Description: \(edge.description)")
            lines.append("---")
        }

        return lines.joined(separator: "\n")
    }

    nonisolated static func buildSummaryEvidenceItems(
        summaryInput: KnowledgeCommunitySummaryInput
    ) -> [String] {
        let nodes = summaryInput.nodes.sorted {
            if $0.normalizedName != $1.normalizedName {
                return $0.normalizedName < $1.normalizedName
            }

            return $0.id < $1.id
        }
        let edges = summaryInput.edges.sorted {
            if $0.firstNodeID != $1.firstNodeID {
                return $0.firstNodeID < $1.firstNodeID
            }
            if $0.secondNodeID != $1.secondNodeID {
                return $0.secondNodeID < $1.secondNodeID
            }
            let firstType = $0.relationshipType ?? ""
            let secondType = $1.relationshipType ?? ""
            if firstType != secondType {
                return firstType < secondType
            }
            if $0.description != $1.description {
                return $0.description < $1.description
            }

            return $0.id < $1.id
        }
        let nodeNameByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.name) })
        let nodeEvidence = nodes.flatMap { node in
            let claims = (summaryInput.claimsByNodeID[node.id] ?? []).sorted {
                if $0.createDate != $1.createDate {
                    return $0.createDate < $1.createDate
                }

                return $0.id < $1.id
            }
            let entityLines = [
                "Entity: \(node.name)",
                node.kind.map { "Type: \($0)" },
                node.description.map { "Description: \($0)" }
            ].compactMap { $0 }

            return [entityLines.joined(separator: "\n")] + claims.map {
                "Claim about \(node.name): \($0.text)"
            }
        }
        let relationshipEvidence = edges.compactMap { edge -> String? in
            guard let sourceName = nodeNameByID[edge.firstNodeID],
                  let targetName = nodeNameByID[edge.secondNodeID] else {
                return nil
            }

            return [
                "Relationship: \(sourceName) -> \(targetName)",
                edge.relationshipType.map { "Type: \($0)" },
                "Description: \(edge.description)"
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        }

        return nodeEvidence + relationshipEvidence
    }

    nonisolated static func sha256Hex(of value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    nonisolated static func parseSummary(_ response: String) -> String? {
        response
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix("Summary:") })
            .map {
                let rawValue = String($0.dropFirst("Summary:".count))
                return rawValue.hasPrefix(" ")
                    ? String(rawValue.dropFirst())
                    : rawValue
            }
    }

    nonisolated static func parseName(_ response: String) -> String? {
        response
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix("Name:") })
            .map {
                let rawValue = String($0.dropFirst("Name:".count))
                let value = rawValue.hasPrefix(" ")
                    ? String(rawValue.dropFirst())
                    : rawValue
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }
}
