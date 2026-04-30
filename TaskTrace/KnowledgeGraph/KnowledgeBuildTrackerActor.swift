//
//  KnowledgeBuildTrackerActor.swift
//  TaskTrace
//

import Foundation
import OSLog

actor KnowledgeBuildTrackerActor: Receiver {
    private struct BuildState {
        let directoryID: Int64
        var scanFinished = false
        var pendingFiles = 0
        var pendingChunkGraphs = 0
        var pendingNodeEmbeddings = 0
        var communitiesDirty = false
    }

    private let actorSystem: ActorSystem?
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "knowledge")
    private var builds: [Int64: BuildState] = [:]

    init(actorSystem: ActorSystem? = nil) {
        self.actorSystem = actorSystem
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as KnowledgeBuildStarted:
            logger.log(
                "knowledge-build-tracker-actor received knowledge-build-started sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) buildID=\(event.buildID, privacy: .public) directoryID=\(event.directoryID, privacy: .public)"
            )
            builds[event.buildID] = BuildState(directoryID: event.directoryID)
            await emitIfCompleted(buildID: event.buildID)
        case let event as KnowledgeFileCreated:
            guard var state = builds[event.buildID] else {
                return
            }
            state.pendingFiles += 1
            builds[event.buildID] = state
        case let event as KnowledgeFileIndexed:
            guard var state = builds[event.buildID] else {
                return
            }
            state.pendingFiles = max(state.pendingFiles - 1, 0)
            builds[event.buildID] = state
            await emitIfCompleted(buildID: event.buildID)
        case let event as KnowledgeChunkEncodeRequested:
            guard let buildID = event.buildID,
                  var state = builds[buildID] else {
                return
            }
            state.pendingChunkGraphs += 1
            builds[buildID] = state
        case let event as KnowledgeChunkGraphProcessed:
            guard let buildID = event.buildID,
                  var state = builds[buildID] else {
                return
            }
            state.pendingChunkGraphs = max(state.pendingChunkGraphs - 1, 0)
            builds[buildID] = state
            await emitIfCompleted(buildID: buildID)
        case let event as KnowledgeNodeCreated:
            guard let buildID = event.buildID,
                  var state = builds[buildID] else {
                return
            }
            if !(event.node.description?.isEmpty ?? true) {
                state.pendingNodeEmbeddings += 1
            }
            state.communitiesDirty = true
            builds[buildID] = state
        case let event as UpdateKnowledgeNode:
            guard let buildID = event.buildID,
                  var state = builds[buildID] else {
                return
            }
            if !(event.node.description?.isEmpty ?? true) {
                state.pendingNodeEmbeddings += 1
            }
            builds[buildID] = state
        case let event as KnowledgeNodeEmbedded:
            guard let buildID = event.buildID,
                  var state = builds[buildID] else {
                return
            }
            state.pendingNodeEmbeddings = max(state.pendingNodeEmbeddings - 1, 0)
            builds[buildID] = state
            await emitIfCompleted(buildID: buildID)
        case let event as KnowledgeEdgeCreated:
            guard let buildID = event.buildID,
                  var state = builds[buildID] else {
                return
            }
            state.communitiesDirty = true
            builds[buildID] = state
        case let event as CommunitiesGenerated:
            guard let buildID = event.buildID,
                  var state = builds[buildID] else {
                return
            }
            state.communitiesDirty = false
            builds[buildID] = state
            await emitIfCompleted(buildID: buildID)
        case let event as KnowledgeDirectoryScanCompleted:
            guard var state = builds[event.buildID] else {
                return
            }
            state.scanFinished = true
            builds[event.buildID] = state
            await emitIfCompleted(buildID: event.buildID)
        case let event as KnowledgeBuildFailed:
            builds.removeValue(forKey: event.buildID)
        default:
            return
        }
    }

    private func emitIfCompleted(buildID: Int64) async {
        guard let state = builds[buildID],
              state.scanFinished,
              state.pendingFiles == 0,
              state.pendingChunkGraphs == 0,
              state.pendingNodeEmbeddings == 0,
              !state.communitiesDirty else {
            return
        }

        logger.log(
            "knowledge-build-tracker-actor broadcasting knowledge-build-completed buildID=\(buildID, privacy: .public) directoryID=\(state.directoryID, privacy: .public)"
        )
        builds.removeValue(forKey: buildID)
        await actorSystem?.broadcast(
            from: nil,
            message: KnowledgeBuildCompleted(
                buildID: buildID,
                directoryID: state.directoryID
            )
        )
    }
}
