//
//  KnowledgeObsidianWriterActor.swift
//  TaskTrace
//

import Foundation
import MLXLMCommon
import OSLog

actor KnowledgeObsidianWriterActor: Receiver {
    typealias MailboxMessage = KnowledgeObsidianExportTarget

    nonisolated static let directSummaryMaxTokens = 160
    nonisolated static let chunkSummaryMaxTokens = 120

    nonisolated static let summarizeInstructions =
        """
        You summarize one knowledge graph note section for Obsidian.
        Use the entity description, the entity's claims, and its incoming and outgoing relationships.
        Prefer concrete facts from the claims and relationships over generic phrasing.
        Return markdown only.
        Use exactly this structure:

        Summary: one concise factual paragraph

        Do not invent facts.
        Do not mention claims, edges, or graph structure explicitly.
        """

    nonisolated static let summarizeChunkInstructions =
        """
        You summarize one evidence chunk for an Obsidian knowledge graph note section.
        Return markdown only.
        Use exactly this structure:

        Summary: concise factual notes from this evidence chunk

        Capture concrete facts about the entity, its claims, and its relationships.
        Do not invent facts not present in the input.
        """

    private let actorSystem: ActorSystem
    private let knowledgeDatabaseActor: KnowledgeDatabaseActor
    private let fileManager = FileManager.default
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "knowledge")

    private var pendingTargets: Set<KnowledgeObsidianExportTarget> = []
    private var queuedTargets: [KnowledgeObsidianExportTarget] = []
    private var isProcessingTarget = false
    private var activeExport: ActiveExport?
    private var pendingTextRequests: [UUID: PendingTextRequest] = [:]
    private var pendingReductions: [UUID: PendingReduction] = [:]
    private var quiescenceContinuations: [CheckedContinuation<Void, Never>] = []

    private struct ActiveExport: Sendable {
        let target: KnowledgeObsidianExportTarget
        let payload: KnowledgeObsidianCommunityPayload
        var memberSummaries: [Int64: String]
        var nextMemberIndex: Int
    }

    private enum PendingTextRequest: Sendable {
        case member(KnowledgeObsidianMemberReference)
        case reduction(operationID: UUID, stage: AIRecursivePromptReducer.Stage)
    }

    private struct PendingReduction: Sendable {
        let member: KnowledgeObsidianMemberReference
        var state: AIRecursivePromptReducer.ReductionState
    }

    init(
        actorSystem: ActorSystem,
        knowledgeDatabaseActor: KnowledgeDatabaseActor,
        textResponder: (any AITextResponding)? = nil
    ) {
        self.actorSystem = actorSystem
        self.knowledgeDatabaseActor = knowledgeDatabaseActor
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as KnowledgeNodeCreated:
            Task {
                await self.enqueueTargetsForNodeIDs([event.node.id])
            }
        case let event as UpdateKnowledgeNode:
            Task {
                await self.enqueueTargetsForNodeIDs([event.node.id])
            }
        case let event as KnowledgeEdgeCreated:
            Task {
                await self.enqueueTargetsForNodeIDs([event.edge.firstNodeID, event.edge.secondNodeID])
            }
        case let event as UpdateKnowledgeEdge:
            Task {
                await self.enqueueTargetsForNodeIDs([event.edge.firstNodeID, event.edge.secondNodeID])
            }
        case let event as CommunitiesGenerated:
            Task {
                await self.handleCommunitiesGenerated(event)
            }
        case let event as CommunitySummarized:
            Task {
                await self.handleCommunitySummarized(event)
            }
        case let target as KnowledgeObsidianExportTarget:
            await enqueueTargets([target])
        case let event as RebuildKnowledge:
            Task {
                await self.deleteExportDirectory(directoryID: event.directoryID)
            }
        case let event as ModelTextCompleted:
            await handleCompleted(event)
        case let event as ModelTextFailed:
            await handleFailed(event)
        default:
            return
        }
    }

    private func handleCommunitiesGenerated(_ event: CommunitiesGenerated) async {
        do {
            let targets = try await knowledgeDatabaseActor.loadKnowledgeObsidianCommunityTargets(
                nodeIDs: Array(Set(event.communityByNodeID.keys))
            )
            for directoryID in Set(targets.map(\.directoryID)) {
                await pruneExportFiles(directoryID: directoryID)
            }

            await enqueueTargets(targets)
        } catch {
            logger.error(
                "knowledge-obsidian-writer-actor failed communities-generated error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func handleCommunitySummarized(_ event: CommunitySummarized) async {
        do {
            let communityNodeIDs = try await knowledgeDatabaseActor.loadCommunityNodesAndEdges(communityID: event.communityID).nodes.map(\.id)
            let targets = try await knowledgeDatabaseActor.loadKnowledgeObsidianCommunityTargets(nodeIDs: communityNodeIDs)
            await enqueueTargets(targets)
        } catch {
            logger.error(
                "knowledge-obsidian-writer-actor failed communityID=\(event.communityID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func drainQueuedTargets() {
        guard !isProcessingTarget,
              !queuedTargets.isEmpty else {
            return
        }

        let target = queuedTargets.removeFirst()
        isProcessingTarget = true

        Task {
            await self.startQueuedTarget(target)
        }
    }

    private func finishQueuedTarget(_ target: KnowledgeObsidianExportTarget) {
        pendingTargets.remove(target)
        activeExport = nil
        isProcessingTarget = false
        drainQueuedTargets()
        resumeQuiescenceContinuationsIfIdle()
    }

    func waitForQuiescence() async {
        guard isProcessingTarget || !queuedTargets.isEmpty else {
            return
        }

        await withCheckedContinuation { continuation in
            quiescenceContinuations.append(continuation)
        }
    }

    private func resumeQuiescenceContinuationsIfIdle() {
        guard !isProcessingTarget,
              queuedTargets.isEmpty else {
            return
        }

        let continuations = quiescenceContinuations
        quiescenceContinuations = []
        continuations.forEach { $0.resume() }
    }

    private func startQueuedTarget(_ target: KnowledgeObsidianExportTarget) async {
        do {
            let payload = try await {
                var loadedPayload: KnowledgeObsidianCommunityPayload?

                for attempt in 0..<5 {
                    loadedPayload = try await knowledgeDatabaseActor.loadKnowledgeObsidianCommunityPayload(
                        directoryID: target.directoryID,
                        communityID: target.communityID
                    )

                    if loadedPayload != nil || attempt == 4 {
                        break
                    }

                    try await Task.sleep(nanoseconds: 75_000_000)
                }

                return loadedPayload
            }()

            guard let payload else {
                finishQueuedTarget(target)
                return
            }

            activeExport = ActiveExport(
                target: target,
                payload: payload,
                memberSummaries: [:],
                nextMemberIndex: 0
            )
            await summarizeNextMember()
        } catch {
            logger.error(
                "knowledge-obsidian-writer-actor failed directoryID=\(target.directoryID, privacy: .public) communityID=\(target.communityID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            finishQueuedTarget(target)
        }
    }

    private func enqueueTargetsForNodeIDs(_ nodeIDs: [Int64]) async {
        do {
            let targets = try await knowledgeDatabaseActor.loadKnowledgeObsidianCommunityTargets(nodeIDs: nodeIDs)
            await enqueueTargets(targets)
        } catch {
            logger.error(
                "knowledge-obsidian-writer-actor failed loading-targets error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func enqueueTargets(_ targets: [KnowledgeObsidianExportTarget]) async {
        for target in Array(Set(targets)).sorted(by: {
            if $0.directoryID != $1.directoryID {
                return $0.directoryID < $1.directoryID
            }

            return $0.communityID < $1.communityID
        }) {
            guard pendingTargets.insert(target).inserted else {
                continue
            }

            queuedTargets.append(target)
        }

        drainQueuedTargets()
    }

    private func summarizeNextMember() async {
        guard var export = activeExport else {
            return
        }

        guard export.nextMemberIndex < export.payload.members.count else {
            activeExport = export
            await writeActiveExport()
            return
        }

        let member = export.payload.members[export.nextMemberIndex]
        export.nextMemberIndex += 1
        activeExport = export
        await dispatchSummaryRequest(member: member)
    }

    private func dispatchSummaryRequest(member: KnowledgeObsidianMemberReference) async {
        let prompt = Self.buildMemberSummaryPrompt(member: member)

        do {
            if AIRecursivePromptReducer.fitsHardLimit(
                prompt: prompt,
                instructions: Self.summarizeInstructions,
                tokenBudget: AIRecursivePromptReducer.knowledgeSummaryTokenBudget
            ) {
                let modelRequest = try AIRecursivePromptReducer.makeRequest(
                    source: "knowledge-obsidian-summary",
                    priority: .interactive,
                    prompt: prompt,
                    instructions: Self.summarizeInstructions,
                    generateParameters: GenerateParameters(maxTokens: Self.directSummaryMaxTokens, temperature: 0),
                    additionalContext: ["enable_thinking": false],
                    tokenBudget: AIRecursivePromptReducer.knowledgeSummaryTokenBudget
                )
                pendingTextRequests[modelRequest.requestID] = .member(member)
                await actorSystem.broadcast(from: nil, message: modelRequest)
            } else {
                let state = AIRecursivePromptReducer.ReductionState(
                    source: "knowledge-obsidian-summary",
                    priority: .interactive,
                    evidenceItems: Self.buildMemberSummaryEvidenceItems(member: member),
                    finalPromptHeader: """
                    These are evidence items and partial summaries for one entity section in an Obsidian knowledge note.
                    Write the final concise section summary from this material.
                    """,
                    finalInstructions: Self.summarizeInstructions,
                    finalGenerateParameters: GenerateParameters(maxTokens: Self.directSummaryMaxTokens, temperature: 0),
                    chunkPromptHeader: """
                    This is one chunk of evidence for an entity section in an Obsidian knowledge note.
                    Summarize only the concrete facts present in this chunk.
                    """,
                    chunkInstructions: Self.summarizeChunkInstructions,
                    chunkGenerateParameters: GenerateParameters(maxTokens: Self.chunkSummaryMaxTokens, temperature: 0),
                    additionalContext: ["enable_thinking": false],
                    tokenBudget: AIRecursivePromptReducer.knowledgeSummaryTokenBudget
                )
                await dispatchNextReduction(
                    PendingReduction(
                        member: member,
                        state: state
                    )
                )
            }
        } catch {
            await failActiveExport(error)
        }
    }

    private func handleCompleted(_ event: ModelTextCompleted) async {
        guard let pending = pendingTextRequests.removeValue(forKey: event.requestID) else {
            return
        }

        switch pending {
        case .member(let member):
            await completeMemberSummary(member: member, rawResponse: event.response)
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
                await completeMemberSummary(member: reduction.member, rawResponse: event.response)
            }
        }
    }

    private func handleFailed(_ event: ModelTextFailed) async {
        guard let pending = pendingTextRequests.removeValue(forKey: event.requestID) else {
            return
        }

        switch pending {
        case .member:
            await failActiveExport(event.message)
        case .reduction(let operationID, _):
            pendingReductions.removeValue(forKey: operationID)
            await failActiveExport(event.message)
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
            await failActiveExport(error)
        }
    }

    private func completeMemberSummary(
        member: KnowledgeObsidianMemberReference,
        rawResponse: String
    ) async {
        guard var export = activeExport else {
            return
        }

        export.memberSummaries[member.nodeID] = Self.parseMemberSummary(
            rawResponse: rawResponse,
            member: member
        )
        activeExport = export
        await summarizeNextMember()
    }

    private func writeActiveExport() async {
        guard let export = activeExport else {
            return
        }

        do {
            let directoryURL = try resolvedDirectoryURL(for: export.payload.directory)
            let startedAccessing = directoryURL.startAccessingSecurityScopedResource()
            defer {
                if startedAccessing {
                    directoryURL.stopAccessingSecurityScopedResource()
                }
            }

            let exportDirectoryURL = directoryURL.appendingPathComponent("TaskTrace", isDirectory: true)
            try fileManager.createDirectory(at: exportDirectoryURL, withIntermediateDirectories: true)
            await pruneExportFiles(directoryID: export.target.directoryID)

            try Self.renderMarkdown(
                for: export.payload,
                memberSummaries: export.memberSummaries
            )
            .write(
                to: exportDirectoryURL.appendingPathComponent(Self.noteFileName(for: export.payload.community)),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            logger.error(
                "knowledge-obsidian-writer-actor failed directoryID=\(export.target.directoryID, privacy: .public) communityID=\(export.target.communityID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }

        finishQueuedTarget(export.target)
    }

    private func failActiveExport(_ error: Any) async {
        guard let export = activeExport else {
            return
        }

        logger.error(
            "knowledge-obsidian-writer-actor failed directoryID=\(export.target.directoryID, privacy: .public) communityID=\(export.target.communityID, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
        finishQueuedTarget(export.target)
    }

    nonisolated static func parseMemberSummary(
        rawResponse: String,
        member: KnowledgeObsidianMemberReference
    ) -> String {
        let response = AITextUtilities
            .strippingThinkingBlocks(from: rawResponse)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = response
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix("Summary:") })
            .map {
                let rawValue = String($0.dropFirst("Summary:".count))
                return rawValue.hasPrefix(" ")
                    ? String(rawValue.dropFirst())
                    : rawValue
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let fallbackDescription = {
            let description = member.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return description.isEmpty ? "No description yet." : description
        }()

        return summary?.isEmpty == false
            ? summary!
            : fallbackDescription
    }

    nonisolated static func buildMemberSummaryPrompt(member: KnowledgeObsidianMemberReference) -> String {
        var lines = [
            "Name: \(member.name)"
        ]

        member.description
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { !$0.isEmpty ? $0 : nil }
            .map { lines.append("Description: \($0)") }

        if !member.claims.isEmpty {
            lines.append("Claims:")
            member.claims.forEach { lines.append("- \($0.text)") }
        }

        let outgoingRelationships = member.relatedNodes
            .filter { $0.direction == .outgoing }
        if !outgoingRelationships.isEmpty {
            lines.append("Outgoing Relationships:")
            outgoingRelationships.forEach {
                let relationshipType = $0.relationshipType?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let relationshipPrefix = relationshipType?.isEmpty == false ? "\(relationshipType!): " : ""
                let description = $0.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let descriptionSuffix = description.isEmpty ? "" : " - \(description)"
                lines.append("- \($0.name) | \(relationshipPrefix)\(descriptionSuffix)".replacingOccurrences(of: "  ", with: " "))
            }
        }

        let incomingRelationships = member.relatedNodes
            .filter { $0.direction == .incoming }
        if !incomingRelationships.isEmpty {
            lines.append("Incoming Relationships:")
            incomingRelationships.forEach {
                let relationshipType = $0.relationshipType?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let relationshipPrefix = relationshipType?.isEmpty == false ? "\(relationshipType!): " : ""
                let description = $0.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let descriptionSuffix = description.isEmpty ? "" : " - \(description)"
                lines.append("- \($0.name) | \(relationshipPrefix)\(descriptionSuffix)".replacingOccurrences(of: "  ", with: " "))
            }
        }

        return lines.joined(separator: "\n")
    }

    nonisolated static func buildMemberSummaryEvidenceItems(member: KnowledgeObsidianMemberReference) -> [String] {
        let descriptionLine = member.description
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : "Description: \($0)" }
        let entityLines = [
            "Entity: \(member.name)",
            descriptionLine
        ].compactMap { $0 }
        let claimEvidence = member.claims
            .sorted {
                if $0.createDate != $1.createDate {
                    return $0.createDate < $1.createDate
                }

                return $0.id < $1.id
            }
            .map { "Claim about \(member.name): \($0.text)" }
        let relationshipEvidence = member.relatedNodes
            .sorted {
                if $0.direction.rawValue != $1.direction.rawValue {
                    return $0.direction.rawValue < $1.direction.rawValue
                }
                let firstName = KnowledgeNodeRecord.normalizedName(for: $0.name)
                let secondName = KnowledgeNodeRecord.normalizedName(for: $1.name)
                if firstName != secondName {
                    return firstName < secondName
                }
                let firstType = $0.relationshipType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let secondType = $1.relationshipType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if firstType != secondType {
                    return firstType < secondType
                }
                let firstDescription = $0.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let secondDescription = $1.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if firstDescription != secondDescription {
                    return firstDescription < secondDescription
                }

                return $0.nodeID < $1.nodeID
            }
            .map {
                [
                    "Relationship \($0.direction.rawValue): \(member.name) <-> \($0.name)",
                    $0.relationshipType.map { "Type: \($0)" },
                    "Description: \($0.description)"
                ]
                .compactMap { $0 }
                .joined(separator: "\n")
            }

        return [entityLines.joined(separator: "\n")] + claimEvidence + relationshipEvidence
    }

    private func deleteExportDirectory(directoryID: Int64) async {
        do {
            guard let directory = try await knowledgeDatabaseActor.loadKnowledgeDirectory(directoryID: directoryID) else {
                return
            }

            let directoryURL = try resolvedDirectoryURL(for: directory)
            let startedAccessing = directoryURL.startAccessingSecurityScopedResource()
            defer {
                if startedAccessing {
                    directoryURL.stopAccessingSecurityScopedResource()
                }
            }

            let exportDirectoryURL = directoryURL.appendingPathComponent("TaskTrace", isDirectory: true)

            if fileManager.fileExists(atPath: exportDirectoryURL.path) {
                try fileManager.removeItem(at: exportDirectoryURL)
            }
        } catch {
            logger.error(
                "knowledge-obsidian-writer-actor failed rebuild-delete directoryID=\(directoryID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func pruneExportFiles(directoryID: Int64) async {
        do {
            guard let directory = try await knowledgeDatabaseActor.loadKnowledgeDirectory(directoryID: directoryID) else {
                return
            }

            let directoryURL = try resolvedDirectoryURL(for: directory)
            let startedAccessing = directoryURL.startAccessingSecurityScopedResource()
            defer {
                if startedAccessing {
                    directoryURL.stopAccessingSecurityScopedResource()
                }
            }

            let exportDirectoryURL = directoryURL.appendingPathComponent("TaskTrace", isDirectory: true)
            guard fileManager.fileExists(atPath: exportDirectoryURL.path) else {
                return
            }

            let keptFileNames = try await knowledgeDatabaseActor.loadKnowledgeObsidianCommunityFileNames(
                directoryID: directoryID
            )

            try fileManager
                .contentsOfDirectory(at: exportDirectoryURL, includingPropertiesForKeys: nil)
                .filter {
                    $0.pathExtension.lowercased() == "md"
                        && !keptFileNames.contains($0.lastPathComponent)
                }
                .forEach { try fileManager.removeItem(at: $0) }
        } catch {
            logger.error(
                "knowledge-obsidian-writer-actor failed prune directoryID=\(directoryID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func resolvedDirectoryURL(for directory: KnowledgeDirectoryRecord) throws -> URL {
        if let bookmarkData = directory.bookmarkData {
            var isStale = false

            if let scopedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return scopedURL
            }

            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }

        return URL(fileURLWithPath: directory.path, isDirectory: true)
    }

    private nonisolated static func noteFileName(for community: KnowledgeCommunityRecord) -> String {
        let trimmedName = community.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let communityName = trimmedName?.isEmpty == false
            ? trimmedName!
            : "Community \(community.id)"
        return KnowledgeObsidianExportNaming.fileName(communityName: communityName)
    }

    private nonisolated static func renderMarkdown(
        for payload: KnowledgeObsidianCommunityPayload,
        memberSummaries: [Int64: String]
    ) -> String {
        let communityName = payload.community.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let communitySummary = payload.community.summary?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = communityName?.isEmpty == false
            ? communityName!
            : "Community \(payload.community.id)"
        let summary = if communitySummary?.isEmpty == false {
            communitySummary!
        } else {
            "No community summary yet."
        }

        var lines = ["# \(title)", summary]

        lines.append("## Members")

        for member in payload.members {
            lines.append("<a id=\"\(member.anchorKey)\"></a>")
            lines.append("### \(member.name)")
            lines.append(memberSummaries[member.nodeID] ?? "No description yet.")

            if !member.edgeLinks.isEmpty {
                lines.append("")
                lines.append("#### Relationships")

                for edgeLink in member.edgeLinks {
                    let linkText = {
                        let description = edgeLink.description.trimmingCharacters(in: .whitespacesAndNewlines)

                        guard description.isEmpty else {
                            return description
                        }

                        let relationshipType = edgeLink.relationshipType?
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        if relationshipType?.isEmpty == false {
                            return "\(member.name) \(relationshipType!) \(edgeLink.targetNodeName)"
                        }

                        return edgeLink.targetNodeName
                    }()
                    let linkTarget = edgeLink.communityID == payload.community.id
                        ? "#\(edgeLink.targetAnchorKey)"
                        : "\(KnowledgeObsidianExportNaming.fileName(communityName: edgeLink.communityName))#\(edgeLink.targetAnchorKey)"
                    lines.append("- [\(linkText)](<\(linkTarget)>)")
                }
            }

            if !member.sourceFiles.isEmpty {
                lines.append("")
                lines.append("#### Source Notes")

                for sourceFile in member.sourceFiles {
                    let sourceLabel = sourceFile.title?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let label = sourceLabel?.isEmpty == false ? sourceLabel! : sourceFile.path
                    lines.append("- [\(label)](<../\(sourceFile.path)>)")
                }
            }

            lines.append("")
        }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
