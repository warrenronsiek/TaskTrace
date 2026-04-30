//
//  ActivityUMAPActor.swift
//  TaskTrace
//
//  Created by Codex on 4/15/26.
//

import Foundation
import MLX
import OSLog

actor ActivityUMAPActor: Receiver {
    nonisolated enum Request: Sendable {
        case job(JobRunRequested)
        case embedding(ActivitySummaryEmbedded)
    }

    private let actorSystem: ActorSystem
    private let activityDatabaseActor: ActivityDatabaseActor
    private let reducer: ActivityUMAPReducer
    nonisolated private let modelDirectoryURL: URL
    nonisolated private let now: @Sendable () -> Date
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init(
        actorSystem: ActorSystem,
        activityDatabaseActor: ActivityDatabaseActor,
        reducer: ActivityUMAPReducer = ActivityUMAPReducer(),
        fileManager: FileManager = .default,
        modelDirectoryURL: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.actorSystem = actorSystem
        self.activityDatabaseActor = activityDatabaseActor
        self.reducer = reducer
        self.modelDirectoryURL = modelDirectoryURL ?? (
            (
                try? TaskTraceDatabaseBootstrap
                    .resolvedDatabaseURL(nil, fileManager: fileManager)
                    .deletingLastPathComponent()
            ) ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("TaskTrace", isDirectory: true)
        )
        .appendingPathComponent("AI", isDirectory: true)
        .appendingPathComponent("ActivityUMAP", isDirectory: true)
        self.now = now
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let request as JobRunRequested
            where request.jobName == .activityUMAP:
            logger.log(
                "activity-umap-actor received job sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) leaseUntil=\(request.leaseUntil.formatted(TaskTraceDatabase.sqlTimestampStyle), privacy: .public)"
            )
            Task {
                await self.process(.job(request))
            }
        case let event as ActivitySummaryEmbedded
            where !event.vector.isEmpty:
            logger.log(
                "activity-umap-actor received embedding sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public) dimensions=\(event.vector.count, privacy: .public)"
            )
            Task {
                await self.process(.embedding(event))
            }
        default:
            return
        }
    }

    private func process(_ message: Request) async {
        switch message {
        case .job(let request):
            await processJobRequest(request)
        case .embedding(let event):
            await processEmbedding(event)
        }
    }

    private func processJobRequest(_ request: JobRunRequested) async {
        do {
            let embeddingBatch = try await activityDatabaseActor.loadActivitySummaryEmbeddingBatch()

            guard embeddingBatch.vectorCount > 0 else {
                try await activityDatabaseActor.clearActivitySummaryUMAPVectors()
                try removePersistedModelIfPresent()
                await actorSystem.broadcast(
                    from: nil,
                    message: JobRunSucceeded(
                        jobName: request.jobName,
                        finishedAt: now()
                    )
                )
                return
            }

            let embeddings = MLXArray(
                embeddingBatch.vectorsData,
                [embeddingBatch.vectorCount, embeddingBatch.vectorDimension],
                type: Float.self
            )
            let fit = try reducer.fit(embeddings)
            let reducedVectorData = fit.reducedEmbeddings.asData(access: .copy)
            let fittedAt = now()

            try await activityDatabaseActor.saveActivitySummaryUMAPBatch(
                ActivitySummaryUMAPBatch(
                    activityIDs: embeddingBatch.activityIDs,
                    vectorsData: reducedVectorData.data,
                    vectorCount: embeddingBatch.vectorCount,
                    vectorDimension: reducedVectorData.shape.last ?? 0
                )
            )
            try persistModel(
                fit.model,
                activityIDs: embeddingBatch.activityIDs,
                fittedAt: fittedAt
            )

            logger.log(
                "activity-umap-actor completed job activityCount=\(embeddingBatch.vectorCount, privacy: .public) modelPath=\(self.modelMetadataURL().path, privacy: .public)"
            )
            await actorSystem.broadcast(
                from: nil,
                message: JobRunSucceeded(
                    jobName: request.jobName,
                    finishedAt: fittedAt
                )
            )
        } catch {
            logger.error(
                "activity-umap-actor failed job error=\(String(describing: error), privacy: .public)"
            )
            await actorSystem.broadcast(
                from: nil,
                message: JobRunFailed(
                    jobName: request.jobName,
                    finishedAt: now(),
                    errorMessage: String(describing: error)
                )
            )
        }
    }

    private func processEmbedding(_ event: ActivitySummaryEmbedded) async {
        do {
            let vectorDimension = event.vector.count

            let reducedVectors = try await AISchedulerRegistry.shared.requestUMAP(
                ModelUMAPRequest(
                    source: "activity-umap",
                    priority: .background,
                    vectors: [event.vector],
                    modelDirectoryURL: modelDirectoryURL,
                    metadata: [
                        "activity_count": "1",
                        "vector_dimension": "\(vectorDimension)"
                    ]
                )
            )

            guard let vector = reducedVectors.first,
                  !vector.isEmpty else {
                return
            }

            await actorSystem.broadcast(
                from: nil,
                message: ActivityUMAPed(
                    activityID: event.activityID,
                    vector: vector
                )
            )
            logger.log(
                "activity-umap-actor transformed embedding activityID=\(event.activityID, privacy: .public) dimensions=\(vector.count, privacy: .public)"
            )
        } catch {
            logger.error(
                "activity-umap-actor failed embedding activityID=\(event.activityID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    nonisolated private static func loadPersistedModel(
        directoryURL: URL
    ) throws -> ActivityUMAPPersistedModel {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try ActivityUMAPPersistedModel(
            artifact: decoder.decode(
                ActivityUMAPModelArtifact.self,
                from: Data(contentsOf: directoryURL.appendingPathComponent("activity-umap-model.json"))
            ),
            directoryURL: directoryURL
        )
    }

    private func persistModel(
        _ model: ActivityUMAPPersistedModel,
        activityIDs: [Int64],
        fittedAt: Date
    ) throws {
        try FileManager.default.createDirectory(
            at: modelDirectoryURL,
            withIntermediateDirectories: true
        )

        let sourceVectorData = model.sourceVectors.asData(access: .copy)
        let reducedVectorData = model.reducedVectors.asData(access: .copy)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        try encoder
            .encode(
                ActivityUMAPModelArtifact(
                    version: 2,
                    fittedAt: fittedAt,
                    sourceDimension: sourceVectorData.shape.last ?? 0,
                    targetDimension: reducedVectorData.shape.last ?? 0,
                    activityCount: activityIDs.count,
                    parameters: model.parameters,
                    activityIDs: activityIDs,
                    sourceVectorsFileName: sourceVectorsURL().lastPathComponent,
                    sourceVectorsShape: sourceVectorData.shape,
                    sourceVectorsDType: String(describing: sourceVectorData.dType),
                    reducedVectorsFileName: reducedVectorsURL().lastPathComponent,
                    reducedVectorsShape: reducedVectorData.shape,
                    reducedVectorsDType: String(describing: reducedVectorData.dType)
                )
            )
            .write(to: modelMetadataURL(), options: .atomic)
        try sourceVectorData.data.write(to: sourceVectorsURL(), options: .atomic)
        try reducedVectorData.data.write(to: reducedVectorsURL(), options: .atomic)
    }

    private func removePersistedModelIfPresent() throws {
        let fileManager = FileManager.default

        [modelMetadataURL(), sourceVectorsURL(), reducedVectorsURL()].forEach {
            guard fileManager.fileExists(atPath: $0.path) else {
                return
            }

            try? fileManager.removeItem(at: $0)
        }
    }

    private func modelMetadataURL() -> URL {
        modelDirectoryURL.appendingPathComponent("activity-umap-model.json")
    }

    private func sourceVectorsURL() -> URL {
        modelDirectoryURL.appendingPathComponent("activity-umap-source-vectors.f32")
    }

    private func reducedVectorsURL() -> URL {
        modelDirectoryURL.appendingPathComponent("activity-umap-reduced-vectors.f32")
    }
}
