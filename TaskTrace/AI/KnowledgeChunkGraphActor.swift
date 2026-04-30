//
//  KnowledgeChunkGraphActor.swift
//  TaskTrace
//
//  Created by Codex on 4/7/26.
//

import CryptoKit
import Foundation
import MLXLMCommon
import OSLog

actor KnowledgeChunkGraphActor: Receiver {
    nonisolated static let maxOutputTokens = 600

    nonisolated static let allowedEntityTypes: Set<String> = [
        "organization",
        "person",
        "place",
        "product"
    ]

    nonisolated static let instructions =
        """
        You extract a knowledge graph from one markdown chunk.
        Return markdown only.
        Use exactly this structure:

        ## Entities
        Name: entity name
        Type: person|organization|place|product
        Description: short factual description grounded in the chunk
        Claims:
        - a specific claim about this entity from the chunk
        - another claim
        ---
        Name: another entity
        Type: ...
        Description: ...
        Claims:
        - ...

        ## Relationships
        Source: entity name
        Target: other entity name
        Type: short snake_case or lower-hyphen relationship type
        Description: short description of the relationship grounded in the chunk
        ---
        Source: ...
        Target: ...
        Type: ...
        Description: ...

        Extract only concrete named entities from the chunk.
        Only extract specific people, organizations, places, or products explicitly named in the text.
        Be parsimonious.
        Prefer returning fewer entities.
        Ignore abstract concepts, roles, processes, qualities, sections, recurring events, generic categories, implementation terms, headings, file names, log names, and document artifacts.
        Do not extract things like architecture, validation, inspection, plugin, resource, screenshot, documentation, automation, retrieval, synthesis, template, daily log, note sync, activity, capture, or review unless they are the exact proper name of a person, organization, place, or product.
        For relationships, consider the pairwise relationships between the retained entities and include only relationships explicitly supported by the chunk.
        Do not invent entities or relationships.
        Do not create self-relationships.
        Descriptions must be concise, concrete, and factual.
        Claims must be specific, verifiable assertions about the entity that are directly stated or strongly implied in the chunk.
        Each claim should be a single sentence.
        Omit claims that merely restate the description.
        If there are no claims for an entity, omit the Claims field.
        If there are no entities, write:
        ## Entities
        (none)
        If there are no relationships, write:
        ## Relationships
        (none)
        """

    private let actorSystem: ActorSystem?
    private let knowledgeDatabaseActor: KnowledgeDatabaseActor
    private let activityDatabaseActor: ActivityDatabaseActor
    private let identifierActor: IdentifierActor
    private let now: @Sendable () -> Date
    private var pendingRequests: [UUID: Request] = [:]
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    struct Request {
        let buildID: Int64?
        let source: KnowledgeGraphSource
        let text: String
        let deduplicationKey: String
        let generation: Int64
    }

    private var chunkGeneration: Int64 = 0
    private var activityGeneration: Int64 = 0

    init(
        actorSystem: ActorSystem,
        knowledgeDatabaseActor: KnowledgeDatabaseActor,
        activityDatabaseActor: ActivityDatabaseActor,
        identifierActor: IdentifierActor = .shared,
        textResponder: (any AITextResponding)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.actorSystem = actorSystem
        self.knowledgeDatabaseActor = knowledgeDatabaseActor
        self.activityDatabaseActor = activityDatabaseActor
        self.identifierActor = identifierActor
        self.now = now
    }

    func receive(_ envelope: Envelope) async {
        if let event = envelope.message as? RebuildActivityKnowledge {
            activityGeneration += 1
            logger.log(
                "knowledge-chunk-graph-actor advanced activity generation=\(self.activityGeneration, privacy: .public)"
            )
            let generation = activityGeneration
            Task {
                await self.enqueueActivityKnowledgeRebuild(
                    activeDay: event.activeDay,
                    generation: generation
                )
            }
            return
        }

        if let event = envelope.message as? ModelTextCompleted {
            await handleCompleted(event)
            return
        }

        if let event = envelope.message as? ModelTextFailed {
            await handleFailed(event)
            return
        }

        let request: Request? = {
            switch envelope.message {
            case _ as RebuildKnowledge:
                chunkGeneration += 1
                logger.log(
                    "knowledge-chunk-graph-actor advanced chunk generation=\(self.chunkGeneration, privacy: .public)"
                )
                return nil
            case let event as KnowledgeChunkEncodeRequested where !event.chunk.text.isEmpty:
                return Request(
                    buildID: event.buildID,
                    source: .chunk(event.chunk),
                    text: event.chunk.text,
                    deduplicationKey: "chunk:\(event.chunk.id)",
                    generation: chunkGeneration
                )
            case let event as ActivitySummarized:
                guard let summary = event.activity.summary, !summary.isEmpty else {
                    return nil
                }
                return Request(
                    buildID: nil,
                    source: .activity(activityID: event.activity.id),
                    text: summary,
                    deduplicationKey: "activity:\(event.activity.id)",
                    generation: activityGeneration
                )
            case let event as ActivityKnowledgeEncodeRequested:
                guard !event.summary.isEmpty else {
                    return nil
                }
                return Request(
                    buildID: nil,
                    source: .activity(activityID: event.activityID),
                    text: event.summary,
                    deduplicationKey: "activity:\(event.activityID)",
                    generation: activityGeneration
                )
            default:
                return nil
            }
        }()

        guard let request else {
            return
        }

        let sourceLog = request.source.logDescription
        let queueDepth = 0
        let activeLanes = 0
        let laneLimit = 1
        let preview = request.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(50)

        logger.log(
            "knowledge-chunk-graph-actor received sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) \(sourceLog, privacy: .public) characters=\(request.text.count, privacy: .public) preview=\(String(preview), privacy: .public) queueDepth=\(queueDepth, privacy: .public) activeLanes=\(activeLanes, privacy: .public)/\(laneLimit, privacy: .public)"
        )

        Task {
            await self.process(request)
        }
    }

    private func enqueueActivityKnowledgeRebuild(
        activeDay: Date,
        generation: Int64
    ) async {
        guard let actorSystem else {
            return
        }

        let calendar = Calendar(identifier: .gregorian)
        let dayStart = calendar.startOfDay(for: activeDay)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        var lastActivityID: Int64?

        do {
            while generation == activityGeneration {
                let activityRequests = try await activityDatabaseActor.loadActivityKnowledgeRebuildRequests(
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    afterActivityID: lastActivityID,
                    limit: 200
                )

                guard !activityRequests.isEmpty else {
                    logger.log(
                        "knowledge-chunk-graph-actor rebuild-activity-knowledge found no eligible activities activeDay=\(activeDay.formatted(TaskTraceDatabase.sqlTimestampStyle), privacy: .public) dayStart=\(dayStart.formatted(TaskTraceDatabase.sqlTimestampStyle), privacy: .public) dayEnd=\(dayEnd.formatted(TaskTraceDatabase.sqlTimestampStyle), privacy: .public) lastActivityID=\(String(describing: lastActivityID), privacy: .public)"
                    )
                    return
                }

                logger.log(
                    "knowledge-chunk-graph-actor rebuild-activity-knowledge loaded batch activeDay=\(activeDay.formatted(TaskTraceDatabase.sqlTimestampStyle), privacy: .public) count=\(activityRequests.count, privacy: .public) firstActivityID=\(activityRequests.first?.activityID ?? -1, privacy: .public) lastActivityID=\(activityRequests.last?.activityID ?? -1, privacy: .public)"
                )
                lastActivityID = activityRequests.last?.activityID
                for activityRequest in activityRequests {
                    guard generation == activityGeneration else {
                        return
                    }

                    await actorSystem.broadcast(
                        from: nil,
                        message: activityRequest
                    )
                }
            }
        } catch {
            logger.error(
                "knowledge-chunk-graph-actor failed event=rebuild-activity-knowledge operation=enqueue-activity-rebuild activeDay=\(activeDay.formatted(TaskTraceDatabase.sqlTimestampStyle), privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func process(_ request: Request) async {
        let requestIsStale = {
            switch request.source {
            case .chunk:
                request.generation != self.chunkGeneration
            case .activity:
                request.generation != self.activityGeneration
            }
        }

        if requestIsStale() {
            logger.log(
                "knowledge-chunk-graph-actor dropping stale request \(request.source.logDescription, privacy: .public) generation=\(request.generation, privacy: .public) chunkGeneration=\(self.chunkGeneration, privacy: .public) activityGeneration=\(self.activityGeneration, privacy: .public)"
            )
            await broadcastProcessed(request, success: false)
            return
        }

        let normalizedText = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedText.hasPrefix("#") {
            let sourceLog = request.source.logDescription
            logger.warning(
                "knowledge-chunk-graph-actor skipping structural chunk \(sourceLog, privacy: .public) preview=\(String(normalizedText.prefix(50)), privacy: .public)"
            )
            await broadcastProcessed(request, success: true)
            return
        }

        do {
            let modelRequest = try AIRecursivePromptReducer.makeRequest(
                source: "knowledge-chunk-graph",
                priority: .interactive,
                prompt: Self.prompt(text: request.text),
                instructions: Self.instructions,
                generateParameters: GenerateParameters(maxTokens: Self.maxOutputTokens, temperature: 0),
                additionalContext: ["enable_thinking": false]
            )
            pendingRequests[modelRequest.requestID] = request
            await actorSystem?.broadcast(from: nil, message: modelRequest)
        } catch {
            let sourceLog = request.source.logDescription
            let queueDepth = 0
            let activeLanes = 0
            let laneLimit = 1
            logger.error(
                "knowledge-chunk-graph-actor failed \(sourceLog, privacy: .public) error=\(String(describing: error), privacy: .public) queueDepth=\(queueDepth, privacy: .public) activeLanes=\(activeLanes, privacy: .public)/\(laneLimit, privacy: .public)"
            )
            await broadcastProcessed(request, success: false)
        }
    }

    private func handleCompleted(_ event: ModelTextCompleted) async {
        guard let request = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        await processResponse(request: request, rawResponse: event.response)
    }

    private func handleFailed(_ event: ModelTextFailed) async {
        guard let request = pendingRequests.removeValue(forKey: event.requestID) else {
            return
        }

        let sourceLog = request.source.logDescription
        logger.error(
            "knowledge-chunk-graph-actor failed \(sourceLog, privacy: .public) error=\(event.message, privacy: .public)"
        )
        await broadcastProcessed(request, success: false)
    }

    private func processResponse(request: Request, rawResponse: String) async {
        var didProcess = false
        let requestIsStale = {
            switch request.source {
            case .chunk:
                request.generation != self.chunkGeneration
            case .activity:
                request.generation != self.activityGeneration
            }
        }

        defer {
            if !Task.isCancelled {
                Task {
                    await self.broadcastProcessed(request, success: didProcess)
                }
            }
        }

        do {

            if requestIsStale() {
                logger.log(
                    "knowledge-chunk-graph-actor dropping stale response \(request.source.logDescription, privacy: .public) generation=\(request.generation, privacy: .public) chunkGeneration=\(self.chunkGeneration, privacy: .public) activityGeneration=\(self.activityGeneration, privacy: .public)"
                )
                return
            }

            let response = AITextUtilities.strippingThinkingBlocks(from: rawResponse)
            let (entities, relationships) = Self.parseResponse(response)

            guard !entities.isEmpty || !relationships.isEmpty else {
                let sourceLog = request.source.logDescription
                let queueDepth = 0
                let activeLanes = 0
                let laneLimit = 1
                let preview = request.text
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(50)
                logger.warning(
                    "knowledge-chunk-graph-actor empty extraction \(sourceLog, privacy: .public) preview=\(String(preview), privacy: .public) queueDepth=\(queueDepth, privacy: .public) activeLanes=\(activeLanes, privacy: .public)/\(laneLimit, privacy: .public)"
                )
                didProcess = true
                return
            }

            let sourceChunkID: Int64? = if case .chunk(let chunk) = request.source { chunk.id } else { nil }
            var nodeInputsByNormalizedName: [String: KnowledgeNodeInput] = [:]

            for entity in entities {
                guard !requestIsStale() else {
                    logger.log(
                        "knowledge-chunk-graph-actor dropping stale entity work \(request.source.logDescription, privacy: .public) generation=\(request.generation, privacy: .public)"
                    )
                    return
                }

                guard nodeInputsByNormalizedName.index(forKey: entity.normalizedName) == nil else {
                    continue
                }

                let existingNode = try await knowledgeDatabaseActor.loadKnowledgeNode(
                    normalizedName: entity.normalizedName
                )
                let nodeID = if let existingNode {
                    existingNode.id
                } else {
                    await identifierActor.makeIdentifier()
                }
                let nodeInput = KnowledgeNodeInput(
                    id: nodeID,
                    name: entity.name,
                    normalizedName: entity.normalizedName,
                    kind: entity.type,
                    description: entity.description,
                    sourceChunkID: sourceChunkID,
                    embedding: nil,
                    createDate: now()
                )
                nodeInputsByNormalizedName[entity.normalizedName] = nodeInput

                if let existingNode {
                    guard existingNode.name != nodeInput.name
                            || existingNode.kind != nodeInput.kind
                            || existingNode.description != nodeInput.description else {
                        let sourceLog = request.source.logDescription
                        let queueDepth = 0
                        let activeLanes = 0
                        let laneLimit = 1
                        logger.log(
                            "knowledge-chunk-graph-actor broadcasting update-knowledge-node \(sourceLog, privacy: .public) nodeID=\(existingNode.id, privacy: .public) name=\(existingNode.name, privacy: .public) queueDepth=\(queueDepth, privacy: .public) activeLanes=\(activeLanes, privacy: .public)/\(laneLimit, privacy: .public)"
                        )
                        await actorSystem?.broadcast(
                            from: nil,
                            message: UpdateKnowledgeNode(
                                buildID: request.buildID,
                                source: request.source,
                                node: nodeInput
                            )
                        )
                        continue
                    }

                    let sourceLog = request.source.logDescription
                    let queueDepth = 0
                    let activeLanes = 0
                    let laneLimit = 1
                    logger.log(
                        "knowledge-chunk-graph-actor broadcasting coalesce-knowledge-node \(sourceLog, privacy: .public) nodeID=\(existingNode.id, privacy: .public) name=\(existingNode.name, privacy: .public) queueDepth=\(queueDepth, privacy: .public) activeLanes=\(activeLanes, privacy: .public)/\(laneLimit, privacy: .public)"
                    )
                    await actorSystem?.broadcast(
                        from: nil,
                        message: CoalesceKnowledgeNode(
                            buildID: request.buildID,
                            source: request.source,
                            existingNode: existingNode,
                            incomingNode: nodeInput
                        )
                    )
                    continue
                }

                let sourceLog = request.source.logDescription
                let queueDepth = 0
                let activeLanes = 0
                let laneLimit = 1
                logger.log(
                    "knowledge-chunk-graph-actor broadcasting knowledge-node-created \(sourceLog, privacy: .public) nodeID=\(nodeInput.id, privacy: .public) name=\(nodeInput.name, privacy: .public) queueDepth=\(queueDepth, privacy: .public) activeLanes=\(activeLanes, privacy: .public)/\(laneLimit, privacy: .public)"
                )
                await actorSystem?.broadcast(
                        from: nil,
                        message: KnowledgeNodeCreated(
                            buildID: request.buildID,
                            source: request.source,
                            node: nodeInput
                        )
                )
            }

            for entity in entities {
                guard !requestIsStale() else {
                    logger.log(
                        "knowledge-chunk-graph-actor dropping stale claim work \(request.source.logDescription, privacy: .public) generation=\(request.generation, privacy: .public)"
                    )
                    return
                }

                guard !entity.claims.isEmpty,
                      let nodeInput = nodeInputsByNormalizedName[entity.normalizedName] else {
                    continue
                }

                for claimText in entity.claims {
                    let md5 = Insecure.MD5
                        .hash(data: Data(claimText.utf8))
                        .map { String(format: "%02x", $0) }
                        .joined()

                    let claimID = await identifierActor.makeIdentifier()
                    let claimInput = KnowledgeClaimInput(
                        id: claimID,
                        nodeID: nodeInput.id,
                        text: claimText,
                        md5: md5,
                        createDate: now()
                    )

                    await actorSystem?.broadcast(
                        from: nil,
                        message: KnowledgeClaimCreated(
                            buildID: request.buildID,
                            source: request.source,
                            claim: claimInput
                        )
                    )
                }
            }

            for relationship in relationships.reduce(into: [KnowledgeChunkGraphRelationshipPayload](), { partial, relationship in
                guard partial.contains(where: {
                    $0.sourceNormalizedName == relationship.sourceNormalizedName
                        && $0.targetNormalizedName == relationship.targetNormalizedName
                        && $0.type == relationship.type
                }) == false else {
                    return
                }

                partial.append(relationship)
            }) {
                guard !requestIsStale() else {
                    logger.log(
                        "knowledge-chunk-graph-actor dropping stale relationship work \(request.source.logDescription, privacy: .public) generation=\(request.generation, privacy: .public)"
                    )
                    return
                }

                guard let sourceNode = nodeInputsByNormalizedName[relationship.sourceNormalizedName],
                      let targetNode = nodeInputsByNormalizedName[relationship.targetNormalizedName] else {
                    continue
                }

                let pair = KnowledgeEdgeRecord.canonicalPair(sourceNode.id, targetNode.id)
                let existingEdge = try await knowledgeDatabaseActor.loadKnowledgeEdge(
                    firstNodeID: pair.firstNodeID,
                    secondNodeID: pair.secondNodeID
                )

                let edgeID = if let existingEdge {
                    existingEdge.id
                } else {
                    await identifierActor.makeIdentifier()
                }
                let edgeInput = KnowledgeEdgeInput(
                    id: edgeID,
                    firstNodeID: pair.firstNodeID,
                    secondNodeID: pair.secondNodeID,
                    relationshipType: relationship.type,
                    description: relationship.description,
                    sourceChunkID: sourceChunkID,
                    createDate: existingEdge?.createDate ?? now()
                )

                if let existingEdge {
                    guard existingEdge.relationshipType != edgeInput.relationshipType
                            || existingEdge.description != edgeInput.description else {
                        let sourceLog = request.source.logDescription
                        let queueDepth = 0
                        let activeLanes = 0
                        let laneLimit = 1
                        logger.log(
                            "knowledge-chunk-graph-actor broadcasting update-knowledge-edge \(sourceLog, privacy: .public) edgeID=\(existingEdge.id, privacy: .public) queueDepth=\(queueDepth, privacy: .public) activeLanes=\(activeLanes, privacy: .public)/\(laneLimit, privacy: .public)"
                        )
                        await actorSystem?.broadcast(
                            from: nil,
                            message: UpdateKnowledgeEdge(
                                source: request.source,
                                edge: KnowledgeEdgeInput(
                                    id: existingEdge.id,
                                    firstNodeID: existingEdge.firstNodeID,
                                    secondNodeID: existingEdge.secondNodeID,
                                    relationshipType: existingEdge.relationshipType,
                                    description: existingEdge.description,
                                    sourceChunkID: existingEdge.sourceChunkID ?? sourceChunkID,
                                    createDate: existingEdge.createDate
                                )
                            )
                        )
                        continue
                    }

                    let sourceLog = request.source.logDescription
                    let queueDepth = 0
                    let activeLanes = 0
                    let laneLimit = 1
                    logger.log(
                        "knowledge-chunk-graph-actor broadcasting coalesce-knowledge-edge \(sourceLog, privacy: .public) edgeID=\(existingEdge.id, privacy: .public) firstNodeID=\(existingEdge.firstNodeID, privacy: .public) secondNodeID=\(existingEdge.secondNodeID, privacy: .public) queueDepth=\(queueDepth, privacy: .public) activeLanes=\(activeLanes, privacy: .public)/\(laneLimit, privacy: .public)"
                    )
                    await actorSystem?.broadcast(
                        from: nil,
                        message: CoalesceKnowledgeEdge(
                            buildID: request.buildID,
                            source: request.source,
                            existingEdge: existingEdge,
                            incomingEdge: edgeInput
                        )
                    )
                    continue
                }

                let sourceLog = request.source.logDescription
                let queueDepth = 0
                let activeLanes = 0
                let laneLimit = 1
                logger.log(
                    "knowledge-chunk-graph-actor broadcasting knowledge-edge-created \(sourceLog, privacy: .public) edgeID=\(edgeInput.id, privacy: .public) firstNodeID=\(edgeInput.firstNodeID, privacy: .public) secondNodeID=\(edgeInput.secondNodeID, privacy: .public) queueDepth=\(queueDepth, privacy: .public) activeLanes=\(activeLanes, privacy: .public)/\(laneLimit, privacy: .public)"
                )
                await actorSystem?.broadcast(
                        from: nil,
                        message: KnowledgeEdgeCreated(
                            buildID: request.buildID,
                            source: request.source,
                            edge: edgeInput
                        )
                )
            }
            didProcess = true
        } catch is CancellationError {
            return
        } catch {
            let sourceLog = request.source.logDescription
            let queueDepth = 0
            let activeLanes = 0
            let laneLimit = 1
            logger.error(
                "knowledge-chunk-graph-actor failed \(sourceLog, privacy: .public) error=\(String(describing: error), privacy: .public) queueDepth=\(queueDepth, privacy: .public) activeLanes=\(activeLanes, privacy: .public)/\(laneLimit, privacy: .public)"
            )
        }
    }

    private func broadcastProcessed(_ request: Request, success: Bool) async {
        if case .chunk(let chunk) = request.source {
            await actorSystem?.broadcast(
                from: nil,
                message: KnowledgeChunkGraphProcessed(
                    buildID: request.buildID,
                    chunkID: chunk.id,
                    success: success
                )
            )
        } else if case .activity(let activityID) = request.source {
            await actorSystem?.broadcast(
                from: nil,
                message: ActivityKnowledgeEncoded(
                    activityID: activityID,
                    success: success
                )
            )
        }
    }

    nonisolated static func prompt(text: String) -> String {
        """

        CHUNK_TEXT
        <<<
        \(text)
        >>>
        """
    }

    private nonisolated static func parseResponse(
        _ response: String
    ) -> ([KnowledgeChunkGraphEntityPayload], [KnowledgeChunkGraphRelationshipPayload]) {
        let lines = response
            .replacingOccurrences(of: "```markdown", with: "")
            .replacingOccurrences(of: "```md", with: "")
            .replacingOccurrences(of: "```", with: "")
            .components(separatedBy: "\n")

        let (entityLines, relationshipLines, _) = lines.reduce(
            into: ([String](), [String](), "")
        ) { partial, line in
            let trimmedLine = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")

            if trimmedLine == "## Entities" {
                partial.2 = "entities"
                return
            }

            if trimmedLine == "## Relationships" {
                partial.2 = "relationships"
                return
            }

            guard !partial.2.isEmpty else {
                return
            }

            if partial.2 == "entities" {
                partial.0.append(line)
            } else {
                partial.1.append(line)
            }
        }

        let parseBlocks = { (sectionLines: [String]) -> [[String: String]] in
            sectionLines
                .split(separator: "---")
                .compactMap { blockLines in
                    let block = blockLines
                        .map { String($0) }
                        .joined(separator: "\n")
                    let normalizedBlock = block.split(whereSeparator: \.isWhitespace).joined(separator: " ")

                    guard !normalizedBlock.isEmpty,
                          normalizedBlock != "(none)" else {
                        return nil
                    }

                    let (fields, _) = block
                        .components(separatedBy: "\n")
                        .reduce(into: ([String: String](), "")) { partial, rawLine in
                            let line = rawLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")

                            guard !line.isEmpty else {
                                return
                            }

                            if let colonIndex = line.firstIndex(of: ":") {
                                let key = line[..<colonIndex].lowercased()
                                let value = line[line.index(after: colonIndex)...].split(whereSeparator: \.isWhitespace).joined(separator: " ")
                                partial.0[key] = value
                                partial.1 = String(key)
                                return
                            }

                            guard !partial.1.isEmpty else {
                                return
                            }

                            let separator = partial.1 == "claims" ? "\n" : " "
                            partial.0[partial.1] = [partial.0[partial.1], line]
                                .compactMap { $0 }
                                .joined(separator: separator)
                        }

                    return fields.isEmpty ? nil : fields
                }
        }

        let entities: [KnowledgeChunkGraphEntityPayload] = parseBlocks(entityLines).compactMap { fields in
            guard let name = fields["name"],
                  let type = fields["type"],
                  let description = fields["description"],
                  !name.isEmpty,
                  !type.isEmpty,
                  !description.isEmpty else {
                return nil
            }

            let normalizedType = type.lowercased()

            guard Self.allowedEntityTypes.contains(normalizedType),
                  name.contains(where: \.isUppercase) || name.contains(where: \.isNumber) else {
                return nil
            }

            let claims = (fields["claims"] ?? "")
                .components(separatedBy: "\n")
                .compactMap { line -> String? in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("- ") else { return nil }
                    let text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    return text.isEmpty ? nil : text
                }

            return KnowledgeChunkGraphEntityPayload(
                name: name,
                normalizedName: KnowledgeNodeRecord.normalizedName(for: name),
                type: normalizedType,
                description: description,
                claims: claims
            )
        }
        let relationships: [KnowledgeChunkGraphRelationshipPayload] = parseBlocks(relationshipLines).compactMap { fields in
            guard let source = fields["source"],
                  let target = fields["target"],
                  let type = fields["type"],
                  let description = fields["description"],
                  !source.isEmpty,
                  !target.isEmpty,
                  !type.isEmpty,
                  !description.isEmpty else {
                return nil
            }

            let sourceNormalizedName = KnowledgeNodeRecord.normalizedName(for: source)
            let targetNormalizedName = KnowledgeNodeRecord.normalizedName(for: target)

            guard sourceNormalizedName != targetNormalizedName else {
                return nil
            }

            return KnowledgeChunkGraphRelationshipPayload(
                source: source,
                sourceNormalizedName: sourceNormalizedName,
                target: target,
                targetNormalizedName: targetNormalizedName,
                type: type.lowercased(),
                description: description
            )
        }

        return (entities, relationships)
    }
}

nonisolated private struct KnowledgeChunkGraphEntityPayload: Sendable {
    let name: String
    let normalizedName: String
    let type: String
    let description: String
    let claims: [String]
}

nonisolated private struct KnowledgeChunkGraphRelationshipPayload: Sendable {
    let source: String
    let sourceNormalizedName: String
    let target: String
    let targetNormalizedName: String
    let type: String
    let description: String
}
