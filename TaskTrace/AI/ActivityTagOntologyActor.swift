//
//  ActivityTagOntologyActor.swift
//  TaskTrace
//

import Foundation
import MLX
import MLXLMCommon
import OSLog

actor ActivityTagOntologyActor: Receiver {
    nonisolated enum Request: Sendable {
        case embedding(ActivitySummaryEmbedded)
        case job(JobRunRequested)
        case refresh(ActivityTagOntologyRefreshRequested)
    }

    nonisolated static let summaryMaxOutputTokens = 160

    private struct MatchKey: Hashable {
        let communityIndex: Int
        let previousIndex: Int
    }

    private struct CandidateMatch {
        let previousCandidate: ActivityTagOntologyCandidateSnapshot
        let memberOverlap: Double
        let centroidSimilarity: Double
        let similarity: Double
    }

    private struct CommunityCandidate {
        let memberActivityIDs: [Int64]
        let centroidVector: Data
        let centralityScoreByActivityID: [Int64: Double]
        let topActivities: [ActivityTagOntologyActivitySnapshot]
    }

    nonisolated static let summarizeInstructions =
        """
        You summarize a cluster of related desktop activities.
        Return plain text using exactly this structure:

        Name: a short concrete label
        Summary: one concise paragraph

        The name should be 2 to 6 words.
        The summary should explain the shared work theme using only the provided activities.
        Be specific, factual, and concise.
        """

    private let actorSystem: ActorSystem
    private let activityDatabaseActor: ActivityDatabaseActor
    private let identifierActor: IdentifierActor
    private let now: @Sendable () -> Date
    private var pendingTextRequests: [UUID: PendingTextRequest] = [:]
    private var pendingOntologyRuns: [UUID: PendingOntologyRun] = [:]
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    private enum PendingTextRequest: Sendable {
        case ontologySummary(operationID: UUID, communityIndex: Int)
    }

    private struct PendingOntologyRun: Sendable {
        let operationID: UUID
        let jobName: TaskTraceJobName?
        let runID: Int64
        let createdAt: Date
        let previousRunID: Int64?
        var plans: [Int: CandidatePlan]
        var pendingCommunityIndexes: Set<Int>
    }

    private struct CandidatePlan: Sendable {
        let community: CommunityCandidate
        let match: CandidateMatch?
        let existingTagName: String?
        let existingTagDescription: String?
        let nameIsUserEdited: Bool
        let descriptionIsUserEdited: Bool
        let tagID: Int64
        let candidateID: Int64
        var generatedText: ActivityTagOntologyGeneratedText?
    }

    init(
        actorSystem: ActorSystem,
        activityDatabaseActor: ActivityDatabaseActor,
        identifierActor: IdentifierActor = .shared,
        textResponder: (any AITextResponding)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.actorSystem = actorSystem
        self.activityDatabaseActor = activityDatabaseActor
        self.identifierActor = identifierActor
        self.now = now
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as ActivitySummaryEmbedded
            where !event.vector.isEmpty:
            Task {
                await self.process(.embedding(event))
            }
        case let request as JobRunRequested
            where request.jobName == .activityTagOntologyRefresh:
            Task {
                await self.process(.job(request))
            }
        case let request as ActivityTagOntologyRefreshRequested:
            Task {
                await self.process(.refresh(request))
            }
        case let event as ModelTextCompleted:
            await handleCompleted(event)
        case let event as ModelTextFailed:
            await handleFailed(event)
        default:
            return
        }
    }

    private func process(_ message: Request) async {
        do {
            switch message {
            case .embedding(let event):
                await processEmbedding(event)
            case .job(let request):
                try await processJobRequest(request)
            case .refresh:
                try await processRefreshRequest()
            }
        } catch {
            logger.error(
                "activity-tag-ontology-actor failed message error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func processEmbedding(_ event: ActivitySummaryEmbedded) async {
        do {
            if let assignment = try await activityDatabaseActor.applyActivitySummaryEmbeddingToOntology(
                activityID: event.activityID,
                vector: event.vector
            ) {
                await actorSystem.broadcast(
                    from: nil,
                    message: ActivityTagAssigned(
                        activityID: assignment.activityID,
                        tagID: assignment.tagID,
                        ontologyCandidateID: assignment.ontologyCandidateID
                    )
                )
            }
        } catch {
            logger.error(
                "activity-tag-ontology-actor failed embedding activityID=\(event.activityID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func processJobRequest(_ request: JobRunRequested) async throws {
        try await refreshOntology(jobName: request.jobName)
    }

    private func processRefreshRequest() async throws {
        try await refreshOntology(jobName: nil)
    }

    private func refreshOntology(jobName: TaskTraceJobName?) async throws {
        do {
            let snapshot = try await activityDatabaseActor.loadActivityTagOntologyRefreshSnapshot()

            guard !snapshot.activities.isEmpty, !snapshot.edges.isEmpty else {
                if let jobName {
                    if snapshot.latestRun == nil {
                        logger.log(
                            "activity-tag-ontology-actor deferred refresh because no ontology run exists and no usable graph is available"
                        )
                        await actorSystem.broadcast(
                            from: nil,
                            message: JobRunDeferred(
                                jobName: jobName,
                                finishedAt: now()
                            )
                        )
                    } else {
                        logger.log(
                            "activity-tag-ontology-actor completed refresh without changes because the latest ontology run already exists"
                        )
                        await actorSystem.broadcast(
                            from: nil,
                            message: JobRunSucceeded(
                                jobName: jobName,
                                finishedAt: now()
                            )
                        )
                    }
                }

                return
            }

            let activityByID = Dictionary(uniqueKeysWithValues: snapshot.activities.map { ($0.id, $0) })
            let communityByActivityID = KnowledgeCommunityDetection.communities(
                nodeIDs: snapshot.activities.map(\.id),
                edges: snapshot.edges.map {
                    KnowledgeCommunityDetection.Edge(
                        firstNodeID: $0.firstActivityID,
                        secondNodeID: $0.secondActivityID,
                        weight: $0.weight
                    )
                },
                resolution: ActivityTagOntologyDefaults.leidenResolution,
                theta: ActivityTagOntologyDefaults.leidenTheta
            )
            let communityCandidates = try Dictionary(grouping: communityByActivityID.keys, by: {
                communityByActivityID[$0] ?? $0
            })
            .values
            .map { memberIDs -> CommunityCandidate in
                let memberActivityIDs = memberIDs.sorted()
                let memberActivityIDSet = Set(memberActivityIDs)
                let centralityScoreByActivityID = memberActivityIDs.reduce(into: [Int64: Double]()) { partial, activityID in
                    partial[activityID] = snapshot.edges.reduce(0) { total, edge in
                        let pair = ActivityEdgeRecord.canonicalPair(edge.firstActivityID, edge.secondActivityID)

                        guard memberActivityIDSet.contains(pair.firstActivityID),
                              memberActivityIDSet.contains(pair.secondActivityID),
                              pair.firstActivityID == activityID || pair.secondActivityID == activityID else {
                            return total
                        }

                        return total + edge.weight
                    }
                }
                let rankedActivities = memberActivityIDs
                    .compactMap { activityByID[$0] }
                    .sorted {
                        let leftCentrality = centralityScoreByActivityID[$0.id] ?? 0
                        let rightCentrality = centralityScoreByActivityID[$1.id] ?? 0

                        if leftCentrality == rightCentrality {
                            return $0.id < $1.id
                        }

                        return leftCentrality > rightCentrality
                    }

                return CommunityCandidate(
                    memberActivityIDs: memberActivityIDs,
                    centroidVector: try Self.centroidVector(for: rankedActivities),
                    centralityScoreByActivityID: centralityScoreByActivityID,
                    topActivities: Array(rankedActivities.prefix(5))
                )
            }
            .sorted {
                ($0.memberActivityIDs.first ?? 0) < ($1.memberActivityIDs.first ?? 0)
            }

            guard !communityCandidates.isEmpty else {
                if let jobName {
                    if snapshot.latestRun == nil {
                        logger.log(
                            "activity-tag-ontology-actor deferred refresh because no communities could be formed for the first ontology run"
                        )
                        await actorSystem.broadcast(
                            from: nil,
                            message: JobRunDeferred(
                                jobName: jobName,
                                finishedAt: now()
                            )
                        )
                    } else {
                        logger.log(
                            "activity-tag-ontology-actor completed refresh without publishing because no communities changed"
                        )
                        await actorSystem.broadcast(
                            from: nil,
                            message: JobRunSucceeded(
                                jobName: jobName,
                                finishedAt: now()
                            )
                        )
                    }
                }

                return
            }

            let previousCandidates = snapshot.latestCandidates
                .filter { !$0.memberActivityIDs.isEmpty }
            let centroidSimilarityByPair = try {
                let previousCentroids = previousCandidates.enumerated().compactMap { candidateIndex, snapshot in
                    snapshot.candidate.centroidVector.map { (candidateIndex, $0) }
                }

                guard !previousCentroids.isEmpty else {
                    return [MatchKey: Double]()
                }

                let similarities = try Self.cosineSimilarityMatrix(
                    left: communityCandidates.map(\.centroidVector),
                    right: previousCentroids.map(\.1)
                )

                return communityCandidates.indices.reduce(into: [MatchKey: Double]()) { partial, communityIndex in
                    previousCentroids.enumerated().forEach { compactIndex, previousCentroid in
                        partial[MatchKey(communityIndex: communityIndex, previousIndex: previousCentroid.0)] =
                            similarities[(communityIndex * previousCentroids.count) + compactIndex]
                    }
                }
            }()
            let matchByCommunityIndex = {
                let pairScores = communityCandidates.enumerated().reduce(
                    into: [(communityIndex: Int, previousIndex: Int, similarity: Double, memberOverlap: Double, centroidSimilarity: Double)]()
                ) { partial, communityEntry in
                    let communityIndex = communityEntry.offset
                    let community = communityEntry.element
                    let communityActivityIDs = Set(community.memberActivityIDs)

                    previousCandidates.enumerated().forEach { previousEntry in
                        let previousIndex = previousEntry.offset
                        let previousCandidate = previousEntry.element
                        let overlapCount = communityActivityIDs
                            .intersection(previousCandidate.memberActivityIDs)
                            .count
                        let memberOverlap = previousCandidate.memberActivityIDs.isEmpty
                            ? 0
                            : Double(overlapCount) / Double(min(community.memberActivityIDs.count, previousCandidate.memberActivityIDs.count))
                        let centroidSimilarity = centroidSimilarityByPair[
                            MatchKey(
                                communityIndex: communityIndex,
                                previousIndex: previousIndex
                            )
                        ] ?? 0
                        let similarity = (ActivityTagOntologyDefaults.continuityAlpha * memberOverlap)
                            + (ActivityTagOntologyDefaults.continuityBeta * centroidSimilarity)

                        guard similarity >= ActivityTagOntologyDefaults.continuityGamma else {
                            return
                        }

                        partial.append(
                            (
                                communityIndex: communityIndex,
                                previousIndex: previousIndex,
                                similarity: similarity,
                                memberOverlap: memberOverlap,
                                centroidSimilarity: centroidSimilarity
                            )
                        )
                    }
                }
                .sorted {
                    if $0.similarity == $1.similarity {
                        if $0.communityIndex == $1.communityIndex {
                            return $0.previousIndex < $1.previousIndex
                        }

                        return $0.communityIndex < $1.communityIndex
                    }

                    return $0.similarity > $1.similarity
                }

                return pairScores.reduce(
                    into: (
                        matches: [Int: CandidateMatch](),
                        matchedCommunityIndices: Set<Int>(),
                        matchedPreviousIndices: Set<Int>()
                    )
                ) { partial, pairScore in
                    guard !partial.matchedCommunityIndices.contains(pairScore.communityIndex),
                          !partial.matchedPreviousIndices.contains(pairScore.previousIndex) else {
                        return
                    }

                    partial.matches[pairScore.communityIndex] = CandidateMatch(
                        previousCandidate: previousCandidates[pairScore.previousIndex],
                        memberOverlap: pairScore.memberOverlap,
                        centroidSimilarity: pairScore.centroidSimilarity,
                        similarity: pairScore.similarity
                    )
                    partial.matchedCommunityIndices.insert(pairScore.communityIndex)
                    partial.matchedPreviousIndices.insert(pairScore.previousIndex)
                }
                .matches
            }()
            let runID = await identifierActor.makeIdentifier()
            let createdAt = now()
            let operationID = UUID()
            var plans: [Int: CandidatePlan] = [:]
            var pendingCommunityIndexes = Set<Int>()

            for (communityIndex, community) in communityCandidates.enumerated() {
                let match = matchByCommunityIndex[communityIndex]
                let existingTag = match?.previousCandidate.tag
                let fallbackName = Self.normalizedText(existingTag?.name) ?? Self.normalizedText(match?.previousCandidate.candidate.name)
                let fallbackSummary = Self.normalizedText(existingTag?.description) ?? Self.normalizedText(match?.previousCandidate.candidate.summary)
                let generatedName = Self.normalizedText(existingTag?.generatedName)
                let generatedSummary = Self.normalizedText(existingTag?.generatedDescription)
                let generatedText: ActivityTagOntologyGeneratedText? = if let generatedName,
                                                                          let generatedSummary {
                    ActivityTagOntologyGeneratedText(
                        name: generatedName,
                        summary: generatedSummary
                    )
                } else if let fallbackName,
                          let fallbackSummary {
                    ActivityTagOntologyGeneratedText(
                        name: fallbackName,
                        summary: fallbackSummary
                    )
                } else {
                    nil
                }
                let tagID = if let match {
                    match.previousCandidate.candidate.tagID
                } else {
                    await identifierActor.makeIdentifier()
                }

                plans[communityIndex] = CandidatePlan(
                    community: community,
                    match: match,
                    existingTagName: Self.normalizedText(existingTag?.name),
                    existingTagDescription: Self.normalizedText(existingTag?.description),
                    nameIsUserEdited: existingTag?.nameIsUserEdited ?? false,
                    descriptionIsUserEdited: existingTag?.descriptionIsUserEdited ?? false,
                    tagID: tagID,
                    candidateID: await identifierActor.makeIdentifier(),
                    generatedText: generatedText
                )

                if generatedText == nil {
                    pendingCommunityIndexes.insert(communityIndex)
                }
            }

            pendingOntologyRuns[operationID] = PendingOntologyRun(
                operationID: operationID,
                jobName: jobName,
                runID: runID,
                createdAt: createdAt,
                previousRunID: snapshot.latestRun?.id,
                plans: plans,
                pendingCommunityIndexes: pendingCommunityIndexes
            )

            if pendingCommunityIndexes.isEmpty {
                await publishPendingOntologyRun(operationID: operationID)
            } else {
                for communityIndex in pendingCommunityIndexes.sorted() {
                    try await dispatchOntologySummaryRequest(
                        operationID: operationID,
                        communityIndex: communityIndex
                    )
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error(
                "activity-tag-ontology-actor failed job error=\(String(describing: error), privacy: .public)"
            )
            if let jobName {
                await actorSystem.broadcast(
                    from: nil,
                    message: JobRunFailed(
                        jobName: jobName,
                        finishedAt: now(),
                        errorMessage: String(describing: error)
                    )
                )
            }
        }
    }

    private func dispatchOntologySummaryRequest(
        operationID: UUID,
        communityIndex: Int
    ) async throws {
        guard let pendingRun = pendingOntologyRuns[operationID],
              let plan = pendingRun.plans[communityIndex] else {
            return
        }

        let modelRequest = try AIRecursivePromptReducer.makeRequest(
            source: "activity-tag-ontology-summary",
            priority: .interactive,
            prompt: Self.buildSummarizePrompt(plan.community.topActivities),
            instructions: Self.summarizeInstructions,
            generateParameters: GenerateParameters(maxTokens: Self.summaryMaxOutputTokens, temperature: 0),
            additionalContext: ["enable_thinking": false]
        )
        pendingTextRequests[modelRequest.requestID] = .ontologySummary(
            operationID: operationID,
            communityIndex: communityIndex
        )
        await actorSystem.broadcast(from: nil, message: modelRequest)
    }

    private func handleCompleted(_ event: ModelTextCompleted) async {
        guard let pending = pendingTextRequests.removeValue(forKey: event.requestID) else {
            return
        }

        switch pending {
        case .ontologySummary(let operationID, let communityIndex):
            guard var run = pendingOntologyRuns[operationID],
                  var plan = run.plans[communityIndex] else {
                return
            }

            plan.generatedText = Self.parseGeneratedText(event.response)
            run.plans[communityIndex] = plan
            run.pendingCommunityIndexes.remove(communityIndex)
            pendingOntologyRuns[operationID] = run

            if run.pendingCommunityIndexes.isEmpty {
                await publishPendingOntologyRun(operationID: operationID)
            }
        }
    }

    private func handleFailed(_ event: ModelTextFailed) async {
        guard let pending = pendingTextRequests.removeValue(forKey: event.requestID) else {
            return
        }

        switch pending {
        case .ontologySummary(let operationID, _):
            guard let run = pendingOntologyRuns.removeValue(forKey: operationID) else {
                return
            }

            logger.error(
                "activity-tag-ontology-actor failed job error=\(event.message, privacy: .public)"
            )
            if let jobName = run.jobName {
                await actorSystem.broadcast(
                    from: nil,
                    message: JobRunFailed(
                        jobName: jobName,
                        finishedAt: now(),
                        errorMessage: event.message
                    )
                )
            }
        }
    }

    private func publishPendingOntologyRun(operationID: UUID) async {
        guard let run = pendingOntologyRuns.removeValue(forKey: operationID) else {
            return
        }

        do {
            let generatedCandidates = run.plans
                .sorted { $0.key < $1.key }
                .map { _, plan in
                    let generatedText = plan.generatedText ?? ActivityTagOntologyGeneratedText(
                        name: "Untitled Cluster",
                        summary: "Cluster summary unavailable."
                    )
                    let visibleName = plan.nameIsUserEdited
                        ? plan.existingTagName ?? generatedText.name
                        : generatedText.name
                    let visibleSummary = plan.descriptionIsUserEdited
                        ? plan.existingTagDescription ?? generatedText.summary
                        : generatedText.summary

                    return (
                        candidate: ActivityTagOntologyCandidateInput(
                            candidateID: plan.candidateID,
                            tagID: plan.tagID,
                            predecessorCandidateID: plan.match?.previousCandidate.candidate.id,
                            name: visibleName,
                            summary: visibleSummary,
                            centroidVector: plan.community.centroidVector,
                            memberActivityIDs: plan.community.memberActivityIDs,
                            centralityScoreByActivityID: plan.community.centralityScoreByActivityID,
                            memberOverlap: plan.match?.memberOverlap,
                            centroidSimilarity: plan.match?.centroidSimilarity,
                            continuitySimilarity: plan.match?.similarity
                        ),
                        tag: TagInput(
                            id: plan.tagID,
                            name: visibleName,
                            description: visibleSummary,
                            createDate: plan.match == nil ? run.createdAt : nil,
                            deleteDate: nil,
                            jsonProperties: nil,
                            originKind: TagOriginKind.ontology.rawValue,
                            generatedName: generatedText.name,
                            generatedDescription: generatedText.summary,
                            nameIsUserEdited: plan.nameIsUserEdited,
                            descriptionIsUserEdited: plan.descriptionIsUserEdited
                        )
                    )
                }
            let runInput = ActivityTagOntologyRunInput(
                runID: run.runID,
                createdAt: run.createdAt,
                previousRunID: run.previousRunID,
                candidates: generatedCandidates.map { $0.candidate },
                kNeighbors: ActivityTagOntologyDefaults.neighborCount,
                leidenResolution: ActivityTagOntologyDefaults.leidenResolution,
                leidenTheta: ActivityTagOntologyDefaults.leidenTheta,
                continuityAlpha: ActivityTagOntologyDefaults.continuityAlpha,
                continuityBeta: ActivityTagOntologyDefaults.continuityBeta,
                continuityGamma: ActivityTagOntologyDefaults.continuityGamma
            )

            try await activityDatabaseActor.publishActivityTagOntologyRun(
                runInput,
                tags: generatedCandidates.map { $0.tag }
            )
            await actorSystem.broadcast(
                from: nil,
                message: ActivityTagOntologyRunPublished()
            )
            if let jobName = run.jobName {
                logger.log(
                    "activity-tag-ontology-actor published a new latest ontology run runID=\(run.runID, privacy: .public)"
                )
                await actorSystem.broadcast(
                    from: nil,
                    message: JobRunSucceeded(
                        jobName: jobName,
                        finishedAt: run.createdAt
                    )
                )
            }
        } catch {
            logger.error(
                "activity-tag-ontology-actor failed job error=\(String(describing: error), privacy: .public)"
            )
            if let jobName = run.jobName {
                await actorSystem.broadcast(
                    from: nil,
                    message: JobRunFailed(
                        jobName: jobName,
                        finishedAt: now(),
                        errorMessage: String(describing: error)
                    )
                )
            }
        }
    }

    nonisolated private static func parseGeneratedText(_ rawResponse: String) -> ActivityTagOntologyGeneratedText {
        let response = AITextUtilities.strippingThinkingBlocks(from: rawResponse)
        let name = Self.parseName(response) ?? "Untitled Cluster"
        let summary = Self.parseSummary(response) ?? response.trimmingCharacters(in: .whitespacesAndNewlines)

        return ActivityTagOntologyGeneratedText(
            name: name,
            summary: summary
        )
    }

    nonisolated private static func buildSummarizePrompt(
        _ activities: [ActivityTagOntologyActivitySnapshot]
    ) -> String {
        activities.enumerated().map { index, activity in
            """
            Activity \(index + 1):
            \(activity.summary)
            """
        }
        .joined(separator: "\n\n")
    }

    nonisolated private static func parseName(_ response: String) -> String? {
        response
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix("Name:") })
            .flatMap {
                normalizedText(
                    String($0.dropFirst("Name:".count))
                )
            }
    }

    nonisolated private static func parseSummary(_ response: String) -> String? {
        response
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix("Summary:") })
            .flatMap {
                normalizedText(
                    String($0.dropFirst("Summary:".count))
                )
            }
    }

    nonisolated private static func normalizedText(_ text: String?) -> String? {
        let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (normalized?.isEmpty == false) ? normalized : nil
    }

    nonisolated private static func centroidVector(
        for activities: [ActivityTagOntologyActivitySnapshot]
    ) throws -> Data {
        guard let firstActivity = activities.first else {
            return Data()
        }

        guard firstActivity.summaryVector.count.isMultiple(of: MemoryLayout<Float>.stride) else {
            throw ActivityVectorDecodingError.invalidFloat32ByteCount(
                firstActivity.id,
                firstActivity.summaryVector.count
            )
        }

        let vectorDimension = firstActivity.summaryVector.count / MemoryLayout<Float>.stride
        let vectorsData = try activities.reduce(
            into: Data(capacity: activities.count * firstActivity.summaryVector.count)
        ) { partial, activity in
            guard activity.summaryVector.count == firstActivity.summaryVector.count else {
                throw ActivityVectorDecodingError.inconsistentFloat32Dimension(
                    expected: vectorDimension,
                    activityID: activity.id,
                    actual: activity.summaryVector.count / MemoryLayout<Float>.stride
                )
            }

            partial.append(activity.summaryVector)
        }

        return mean(
            MLXArray(
                vectorsData,
                [activities.count, vectorDimension],
                type: Float.self
            ),
            axis: 0
        )
        .asArray(Float.self)
        .withUnsafeBytes { Data($0) }
    }

    nonisolated private static func cosineSimilarityMatrix(
        left: [Data],
        right: [Data]
    ) throws -> [Double] {
        guard let firstLeft = left.first,
              let firstRight = right.first else {
            return []
        }

        guard firstLeft.count == firstRight.count,
              firstLeft.count.isMultiple(of: MemoryLayout<Float>.stride) else {
            throw ActivityVectorDecodingError.invalidFloat32ByteCount(0, firstLeft.count)
        }

        let vectorDimension = firstLeft.count / MemoryLayout<Float>.stride
        let leftData = try left.enumerated().reduce(
            into: Data(capacity: left.count * firstLeft.count)
        ) { partial, element in
            guard element.element.count == firstLeft.count else {
                throw ActivityVectorDecodingError.inconsistentFloat32Dimension(
                    expected: vectorDimension,
                    activityID: Int64(element.offset),
                    actual: element.element.count / MemoryLayout<Float>.stride
                )
            }

            partial.append(element.element)
        }
        let rightData = try right.enumerated().reduce(
            into: Data(capacity: right.count * firstRight.count)
        ) { partial, element in
            guard element.element.count == firstRight.count else {
                throw ActivityVectorDecodingError.inconsistentFloat32Dimension(
                    expected: vectorDimension,
                    activityID: Int64(element.offset),
                    actual: element.element.count / MemoryLayout<Float>.stride
                )
            }

            partial.append(element.element)
        }
        let normalizedLeft = ActivityUMAPReducer.normalizeRows(
            MLXArray(leftData, [left.count, vectorDimension], type: Float.self),
            epsilon: 1e-6
        )
        let normalizedRight = ActivityUMAPReducer.normalizeRows(
            MLXArray(rightData, [right.count, vectorDimension], type: Float.self),
            epsilon: 1e-6
        )

        return normalizedLeft
            .matmul(normalizedRight.transposed())
            .asArray(Float.self)
            .map(Double.init)
    }
}

private extension Sequence {
    func asyncMap<T: Sendable>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        var values: [T] = []

        for element in self {
            values.append(try await transform(element))
        }

        return values
    }
}
