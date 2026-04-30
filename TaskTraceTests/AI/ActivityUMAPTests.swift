import Foundation
import GRDB
import MLX
import Testing
@testable import TaskTrace

struct ActivityUMAPTests {
    @Test("loading activity summary embeddings produces a float32 batch")
    func loadingActivitySummaryEmbeddingsProducesFloat32Batch() async throws {
        try await withActivityDatabaseActor { database, activityDatabaseActor in
            try await database.saveActivityRecord(
                ActivityInput(
                    id: 1,
                    startTime: Date(timeIntervalSince1970: 1_765_000_000),
                    application: "Xcode",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "Worked on embeddings",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: nil
                )
            )
            try database.write { db in
                try db.execute(
                    sql: """
                        UPDATE activities
                        SET summary_vector = vector_as_f32(?)
                        WHERE id = ?
                        """,
                    arguments: ["[1.0, 2.0, 3.0]", 1]
                )
            }

            #expect(
                try await activityDatabaseActor.loadActivitySummaryEmbeddingBatch()
                == {
                    let floats: [Float] = [1.0, 2.0, 3.0]

                    return ActivitySummaryEmbeddingBatch(
                        activityIDs: [1],
                        vectorsData: floats.withUnsafeBytes { Data($0) },
                        vectorCount: 1,
                        vectorDimension: 3
                    )
                }()
            )
        }
    }

    @Test("saving activity UMAP batches writes the reduced vector blob")
    func savingActivityUMAPBatchesWritesTheReducedVectorBlob() async throws {
        try await withActivityDatabaseActor { database, activityDatabaseActor in
            try await database.saveActivityRecord(
                ActivityInput(
                    id: 1,
                    startTime: Date(timeIntervalSince1970: 1_765_000_000),
                    application: "Xcode",
                    keystrokes: nil,
                    microphone: nil,
                    summary: "Worked on embeddings",
                    tagID: nil,
                    jsonProperties: nil,
                    overviewID: nil
                )
            )

            let umapFloats: [Float] = [0.25, -0.5, 0.75]

            try await activityDatabaseActor.saveActivitySummaryUMAPBatch(
                ActivitySummaryUMAPBatch(
                    activityIDs: [1],
                    vectorsData: umapFloats.withUnsafeBytes { Data($0) },
                    vectorCount: 1,
                    vectorDimension: 3
                )
            )

            #expect(
                try database.read { db in
                    let record = try #require(
                        try ActivityRecord.fetchOne(
                            db,
                            sql: "SELECT * FROM activities WHERE id = ?",
                            arguments: [1]
                        )
                    )

                    return record.summaryVectorUMAP
                } == umapFloats.withUnsafeBytes { Data($0) }
            )
        }
    }

    @Test("fitting clustered embeddings keeps points closer to their own reduced cluster centroid")
    func fittingClusteredEmbeddingsKeepsPointsCloserToTheirOwnReducedClusterCentroid() async throws {
        let parameters = ActivityUMAPParameters(
            targetDimensions: 3,
            neighborCount: 2,
            iterations: 80,
            learningRate: 0.05,
            patience: 20,
            minimumVariance: 1e-6,
            inferenceTemperature: 0.05
        )
        let reducer = ActivityUMAPReducer(parameters: parameters)
        let clusterDimension = 4
        let clusterCount = 3
        let pointsPerCluster = 3
        let embeddings: [Float] = [
            1.00, 0.00, 0.00, 0.00,
            0.99, 0.01, 0.00, 0.00,
            0.98, 0.02, 0.00, 0.00,
            0.00, 1.00, 0.00, 0.00,
            0.01, 0.99, 0.00, 0.00,
            0.02, 0.98, 0.00, 0.00,
            0.00, 0.00, 1.00, 0.00,
            0.00, 0.01, 0.99, 0.00,
            0.00, 0.02, 0.98, 0.00
        ]
        let fit = try reducer.fit(
            MLXArray(
                embeddings.withUnsafeBytes { Data($0) },
                [clusterCount * pointsPerCluster, clusterDimension],
                type: Float.self
            )
        )
        let reducedValues = fit.reducedEmbeddings.asArray(Float.self)
        let targetDimension = fit.reducedEmbeddings.dim(1)
        let row = { (index: Int) in
            Array(
                reducedValues[
                    (index * targetDimension)..<((index + 1) * targetDimension)
                ]
            )
        }
        let centroids = (0..<clusterCount).map { clusterIndex in
            (0..<targetDimension).map { dimensionIndex in
                (0..<pointsPerCluster)
                    .map { pointOffset in
                        row((clusterIndex * pointsPerCluster) + pointOffset)[dimensionIndex]
                    }
                    .reduce(0, +) / Float(pointsPerCluster)
            }
        }
        let distance = { (lhs: [Float], rhs: [Float]) in
            sqrt(
                zip(lhs, rhs)
                    .map { pow($0 - $1, 2) }
                    .reduce(0, +)
            )
        }

        #expect(
            (0..<(clusterCount * pointsPerCluster)).allSatisfy { index in
                let clusterIndex = index / pointsPerCluster
                let point = row(index)
                let ownDistance = distance(point, centroids[clusterIndex])
                let otherDistance = (0..<clusterCount)
                    .filter { $0 != clusterIndex }
                    .map { distance(point, centroids[$0]) }
                    .min() ?? .greatestFiniteMagnitude

                return ownDistance < otherDistance
            }
        )
    }

    @Test("loading a persisted activity UMAP model predicts a new row into the expected cluster")
    func loadingAPersistedActivityUMAPModelPredictsANewRowIntoTheExpectedCluster() async throws {
        let parameters = ActivityUMAPParameters(
            targetDimensions: 3,
            neighborCount: 2,
            iterations: 80,
            learningRate: 0.05,
            patience: 20,
            minimumVariance: 1e-6,
            inferenceTemperature: 0.05
        )
        let reducer = ActivityUMAPReducer(parameters: parameters)
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelMetadataURL = rootURL.appendingPathComponent("activity-umap-model.json")
        let sourceVectorsURL = rootURL.appendingPathComponent("activity-umap-source-vectors.f32")
        let reducedVectorsURL = rootURL.appendingPathComponent("activity-umap-reduced-vectors.f32")
        let clusterDimension = 4
        let pointsPerCluster = 3
        let embeddings: [Float] = [
            1.00, 0.00, 0.00, 0.00,
            0.99, 0.01, 0.00, 0.00,
            0.98, 0.02, 0.00, 0.00,
            0.00, 1.00, 0.00, 0.00,
            0.01, 0.99, 0.00, 0.00,
            0.02, 0.98, 0.00, 0.00,
            0.00, 0.00, 1.00, 0.00,
            0.00, 0.01, 0.99, 0.00,
            0.00, 0.02, 0.98, 0.00
        ]
        let fit = try reducer.fit(
            MLXArray(
                embeddings.withUnsafeBytes { Data($0) },
                [9, clusterDimension],
                type: Float.self
            )
        )
        let sourceVectorData = fit.model.sourceVectors.asData(access: .copy)
        let reducedVectorData = fit.model.reducedVectors.asData(access: .copy)
        let reducedValues = fit.reducedEmbeddings.asArray(Float.self)
        let targetDimension = fit.reducedEmbeddings.dim(1)
        let centroids = (0..<3).map { clusterIndex in
            (0..<targetDimension).map { dimensionIndex in
                (0..<pointsPerCluster)
                    .map { pointOffset in
                        reducedValues[
                            (((clusterIndex * pointsPerCluster) + pointOffset) * targetDimension) + dimensionIndex
                        ]
                    }
                    .reduce(0, +) / Float(pointsPerCluster)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try sourceVectorData.data.write(to: sourceVectorsURL, options: .atomic)
        try reducedVectorData.data.write(to: reducedVectorsURL, options: .atomic)
        try encoder
            .encode(
                ActivityUMAPModelArtifact(
                    version: 2,
                    fittedAt: Date(timeIntervalSince1970: 1_765_000_000),
                    sourceDimension: sourceVectorData.shape.last ?? 0,
                    targetDimension: reducedVectorData.shape.last ?? 0,
                    activityCount: 9,
                    parameters: parameters,
                    activityIDs: Array(1...9).map(Int64.init),
                    sourceVectorsFileName: sourceVectorsURL.lastPathComponent,
                    sourceVectorsShape: sourceVectorData.shape,
                    sourceVectorsDType: String(describing: sourceVectorData.dType),
                    reducedVectorsFileName: reducedVectorsURL.lastPathComponent,
                    reducedVectorsShape: reducedVectorData.shape,
                    reducedVectorsDType: String(describing: reducedVectorData.dType)
                )
            )
            .write(to: modelMetadataURL, options: .atomic)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let model = try ActivityUMAPPersistedModel(
            artifact: decoder.decode(
                ActivityUMAPModelArtifact.self,
                from: Data(contentsOf: modelMetadataURL)
            ),
            directoryURL: rootURL
        )
        let predicted = model.transform(
            MLXArray(
                [Float(0.995), Float(0.005), 0, 0].withUnsafeBytes { Data($0) },
                [1, clusterDimension],
                type: Float.self
            )
        )
        .asArray(Float.self)
        let distance = { (lhs: [Float], rhs: [Float]) in
            sqrt(
                zip(lhs, rhs)
                    .map { pow($0 - $1, 2) }
                    .reduce(0, +)
            )
        }

        #expect(
            distance(predicted, centroids[0])
                < ((1..<3).map { distance(predicted, centroids[$0]) }.min() ?? .greatestFiniteMagnitude)
        )
    }
}

private func withActivityDatabaseActor(
    _ block: (TaskTraceDatabase, ActivityDatabaseActor) async throws -> Void
) async throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

    let (database, activityDatabaseActor) = try await MainActor.run {
        let database = try TaskTraceDatabase(databaseURL: databaseURL)

        return (
            database,
            ActivityDatabaseActor(database: database)
        )
    }

    try await block(database, activityDatabaseActor)
}
