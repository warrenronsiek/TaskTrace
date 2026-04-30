//
//  ActivityUMAP.swift
//  TaskTrace
//
//  Created by Codex on 4/15/26.
//

import Foundation
import MLX

nonisolated struct ActivityUMAPParameters: Codable, Equatable, Sendable {
    let targetDimensions: Int
    let neighborCount: Int
    let iterations: Int
    let learningRate: Float
    let patience: Int
    let minimumVariance: Float
    let inferenceTemperature: Float

    init(
        targetDimensions: Int = 3,
        neighborCount: Int = Vars.activityTagOntologyNeighborCount,
        iterations: Int = 150,
        learningRate: Float = 0.05,
        patience: Int = 20,
        minimumVariance: Float = 1e-6,
        inferenceTemperature: Float = 0.05
    ) {
        self.targetDimensions = targetDimensions
        self.neighborCount = neighborCount
        self.iterations = iterations
        self.learningRate = learningRate
        self.patience = patience
        self.minimumVariance = minimumVariance
        self.inferenceTemperature = inferenceTemperature
    }
}

nonisolated struct ActivityUMAPModelArtifact: Codable, Equatable, Sendable {
    let version: Int
    let fittedAt: Date
    let sourceDimension: Int
    let targetDimension: Int
    let activityCount: Int
    let parameters: ActivityUMAPParameters
    let activityIDs: [Int64]
    let sourceVectorsFileName: String
    let sourceVectorsShape: [Int]
    let sourceVectorsDType: String
    let reducedVectorsFileName: String
    let reducedVectorsShape: [Int]
    let reducedVectorsDType: String
}

nonisolated enum ActivityUMAPModelError: Error {
    case invalidSourceVectorShape([Int])
    case invalidReducedVectorShape([Int])
    case invalidSourceVectorDType(String)
    case invalidReducedVectorDType(String)
}

nonisolated final class ActivityUMAPPersistedModel: @unchecked Sendable {
    let parameters: ActivityUMAPParameters
    let sourceVectors: MLXArray
    let reducedVectors: MLXArray

    init(
        parameters: ActivityUMAPParameters,
        sourceVectors: MLXArray,
        reducedVectors: MLXArray
    ) {
        self.parameters = parameters
        self.sourceVectors = sourceVectors.asType(.float32)
        self.reducedVectors = reducedVectors.asType(.float32)
    }

    convenience init(
        artifact: ActivityUMAPModelArtifact,
        directoryURL: URL
    ) throws {
        guard artifact.sourceVectorsShape.count == 2 else {
            throw ActivityUMAPModelError.invalidSourceVectorShape(artifact.sourceVectorsShape)
        }

        guard artifact.reducedVectorsShape.count == 2 else {
            throw ActivityUMAPModelError.invalidReducedVectorShape(artifact.reducedVectorsShape)
        }

        guard artifact.sourceVectorsDType == String(describing: DType.float32) else {
            throw ActivityUMAPModelError.invalidSourceVectorDType(artifact.sourceVectorsDType)
        }

        guard artifact.reducedVectorsDType == String(describing: DType.float32) else {
            throw ActivityUMAPModelError.invalidReducedVectorDType(artifact.reducedVectorsDType)
        }

        self.init(
            parameters: artifact.parameters,
            sourceVectors: MLXArray(
                try Data(contentsOf: directoryURL.appendingPathComponent(artifact.sourceVectorsFileName)),
                artifact.sourceVectorsShape,
                type: Float.self
            ),
            reducedVectors: MLXArray(
                try Data(contentsOf: directoryURL.appendingPathComponent(artifact.reducedVectorsFileName)),
                artifact.reducedVectorsShape,
                type: Float.self
            )
        )
    }

    func transform(_ embeddings: MLXArray) -> MLXArray {
        precondition(embeddings.ndim == 2, "Activity UMAP expects a rank-2 embedding matrix.")
        precondition(
            embeddings.dim(1) == sourceVectors.dim(1),
            "Activity UMAP expects incoming embeddings to match the persisted source dimension."
        )

        let queryCount = embeddings.dim(0)
        let sourceCount = sourceVectors.dim(0)
        let targetDimension = reducedVectors.dim(1)

        guard queryCount > 0, sourceCount > 0 else {
            return MLXArray.zeros(
                [queryCount, targetDimension],
                type: Float.self
            )
        }

        let normalizedQueries = ActivityUMAPReducer.normalizeRows(
            embeddings.asType(.float32),
            epsilon: parameters.minimumVariance
        )
        let similarities = clip(
            normalizedQueries.matmul(sourceVectors.transposed()),
            min: -1.0,
            max: 1.0
        )
        let neighborCount = min(
            max(parameters.neighborCount, 1),
            sourceCount
        )
        let topIndices = argSort(-similarities, axis: -1)[0..., 0..<neighborCount]
        let topSimilarities = takeAlong(similarities, topIndices, axis: 1)
        let gatheredReducedVectors = take(
            reducedVectors,
            topIndices.reshaped([-1]),
            axis: 0
        )
        .reshaped([queryCount, neighborCount, targetDimension])
        let weights = softmax(
            topSimilarities / MLXArray(max(parameters.inferenceTemperature, parameters.minimumVariance)),
            axis: -1
        )
        let transformed = sum(
            gatheredReducedVectors * expandedDimensions(weights, axis: 2),
            axis: 1
        )

        transformed.eval()

        return transformed.asType(.float32)
    }
}

nonisolated struct ActivityUMAPFit: @unchecked Sendable {
    let model: ActivityUMAPPersistedModel
    let reducedEmbeddings: MLXArray
}

nonisolated struct ActivityUMAPReducer {
    let parameters: ActivityUMAPParameters

    init(parameters: ActivityUMAPParameters = ActivityUMAPParameters()) {
        self.parameters = parameters
    }

    func fit(_ embeddings: MLXArray) throws -> ActivityUMAPFit {
        precondition(embeddings.ndim == 2, "Activity UMAP expects a rank-2 embedding matrix.")

        let input = embeddings.asType(.float32)
        let pointCount = input.dim(0)
        let sourceDimension = input.dim(1)
        let normalizedInput = Self.normalizeRows(
            input,
            epsilon: parameters.minimumVariance
        )

        guard pointCount > 1, sourceDimension > 0 else {
            let reducedEmbeddings = MLXArray.zeros(
                [pointCount, max(parameters.targetDimensions, 1)],
                type: Float.self
            )
            let model = ActivityUMAPPersistedModel(
                parameters: parameters,
                sourceVectors: normalizedInput,
                reducedVectors: reducedEmbeddings
            )

            return ActivityUMAPFit(
                model: model,
                reducedEmbeddings: model.transform(input)
            )
        }

        let highDimAffinities = computeHighDimAffinities(
            data: normalizedInput,
            neighborCount: min(
                max(parameters.neighborCount, 1),
                pointCount - 1
            )
        )
        var lowDimEmbedding = makeInitialEmbedding(
            data: normalizedInput,
            sourceDimension: sourceDimension
        )

        optimize(
            lowDimEmbedding: &lowDimEmbedding,
            highDimAffinities: highDimAffinities
        )
        lowDimEmbedding.eval()

        let model = ActivityUMAPPersistedModel(
            parameters: parameters,
            sourceVectors: normalizedInput,
            reducedVectors: lowDimEmbedding.asType(.float32)
        )
        let reducedEmbeddings = model.transform(input)

        reducedEmbeddings.eval()

        return ActivityUMAPFit(
            model: model,
            reducedEmbeddings: reducedEmbeddings
        )
    }

    nonisolated static func normalizeRows(
        _ data: MLXArray,
        epsilon: Float
    ) -> MLXArray {
        let safeEpsilon = MLXArray(max(epsilon, Float.ulpOfOne))
        let norms = sqrt(
            maximum(
                sum(data * data, axis: 1, keepDims: true),
                safeEpsilon
            )
        )

        return data / norms
    }

    private func computeHighDimAffinities(
        data: MLXArray,
        neighborCount: Int
    ) -> MLXArray {
        let epsilon = MLXArray(parameters.minimumVariance)
        let pointCount = data.dim(0)
        let cosineDistances = maximum(
            MLXArray(1.0) - clip(
                data.matmul(data.transposed()),
                min: -1.0,
                max: 1.0
            ),
            MLXArray(0.0)
        )
        let maskedDistances = cosineDistances
            + (MLXArray.eye(pointCount, type: Float.self) * MLXArray(1_000_000.0))
        let neighborIndices = argSort(maskedDistances, axis: -1)[0..., 0..<neighborCount]
        let neighborDistances = takeAlong(cosineDistances, neighborIndices, axis: 1)
        let sigma = maximum(
            std(
                neighborDistances,
                axis: 1,
                keepDims: true,
                ddof: 0
            ),
            epsilon
        )
        let neighborAffinities = exp(
            -neighborDistances
                / (MLXArray(2.0) * sigma * sigma)
        )
        let offDiagonalMask = MLXArray.ones([pointCount, pointCount], type: Float.self)
            - MLXArray.eye(pointCount, type: Float.self)
        let affinities = putAlong(
            MLXArray.zeros([pointCount, pointCount], type: Float.self),
            neighborIndices,
            values: neighborAffinities,
            axis: 1
        ) * offDiagonalMask
        let symmetrized = (affinities + affinities.transposed()) / MLXArray(2.0)

        return symmetrized / maximum(sum(symmetrized), epsilon)
    }

    private func makeInitialEmbedding(
        data: MLXArray,
        sourceDimension: Int
    ) -> MLXArray {
        let centered = data - mean(
            data,
            axis: 0,
            keepDims: true
        )
        let resolvedTargetDimensions = min(
            max(parameters.targetDimensions, 1),
            sourceDimension
        )
        let (_, _, vt) = MLXLinalg.svd(centered, stream: .cpu)
        let components = vt[0..<resolvedTargetDimensions, 0...]
        let projected = centered.matmul(components.transposed())

        guard resolvedTargetDimensions < parameters.targetDimensions else {
            return projected
        }

        return concatenated(
            [
                projected,
                MLXArray.zeros(
                    [
                        projected.dim(0),
                        parameters.targetDimensions - resolvedTargetDimensions
                    ],
                    type: Float.self
                )
            ],
            axis: 1
        )
    }

    private func computeLowDimAffinities(
        _ embedding: MLXArray
    ) -> (numerators: MLXArray, normalized: MLXArray) {
        let epsilon = MLXArray(parameters.minimumVariance)
        let pointCount = embedding.dim(0)
        let squaredNorms = sum(embedding * embedding, axis: 1, keepDims: true)
        let distancesSquared = maximum(
            squaredNorms
                + squaredNorms.transposed()
                - (MLXArray(2.0) * embedding.matmul(embedding.transposed())),
            MLXArray(0.0)
        )
        let offDiagonalMask = MLXArray.ones([pointCount, pointCount], type: Float.self)
            - MLXArray.eye(pointCount, type: Float.self)
        let numerators = (
            MLXArray(1.0)
            / (MLXArray(1.0) + distancesSquared + epsilon)
        ) * offDiagonalMask

        return (
            numerators,
            numerators / maximum(sum(numerators), epsilon)
        )
    }

    private func loss(_ arrays: [MLXArray]) -> [MLXArray] {
        let epsilon = MLXArray(parameters.minimumVariance)
        let highDimAffinities = arrays[1] + epsilon
        let (_, lowDimAffinities) = computeLowDimAffinities(arrays[0])
        let q = clip(
            lowDimAffinities + epsilon,
            min: parameters.minimumVariance,
            max: 1 - parameters.minimumVariance
        )
        let totalLoss = sum(
            -(
                (highDimAffinities * log(q))
                + ((MLXArray(1.0) - highDimAffinities) * log((MLXArray(1.0) - q) + epsilon))
            )
        )

        return [nanToNum(totalLoss)]
    }

    private func optimize(
        lowDimEmbedding: inout MLXArray,
        highDimAffinities: MLXArray
    ) {
        let computeValueAndGradient = valueAndGrad { arrays in
            loss(arrays)
        }
        var bestLoss = Float.greatestFiniteMagnitude
        var stalledIterations = 0

        for _ in 0..<parameters.iterations {
            let (value, gradient) = computeValueAndGradient(
                [lowDimEmbedding, highDimAffinities]
            )
            let currentLoss = value[0].item(Float.self)

            if currentLoss < bestLoss {
                bestLoss = currentLoss
                stalledIterations = 0
            } else {
                stalledIterations += 1
            }

            lowDimEmbedding -= parameters.learningRate * gradient[0]
            lowDimEmbedding -= mean(
                lowDimEmbedding,
                axis: 0,
                keepDims: true
            )
            lowDimEmbedding.eval()

            if stalledIterations >= parameters.patience {
                break
            }
        }
    }
}
