//
//  ImageSimilarity.swift
//  TaskTrace
//

import CoreImage
import Foundation

enum ImageSimilarity {
    nonisolated static let fingerprintEdge = 300
    nonisolated static let nearDuplicateMaxMeanDistance: Double = 5.0

    nonisolated static func fingerprint(for imageData: Data) -> [UInt8]? {
        guard let ciImage = CIImage(data: imageData, options: [.applyOrientationProperty: true]) else {
            return nil
        }

        let targetBounds = CGRect(
            x: 0,
            y: 0,
            width: fingerprintEdge,
            height: fingerprintEdge
        )
        let scaledImage = ciImage
            .transformed(by: .init(
                scaleX: CGFloat(fingerprintEdge) / max(ciImage.extent.width, 1),
                y: CGFloat(fingerprintEdge) / max(ciImage.extent.height, 1)
            ))
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .cropped(to: targetBounds)

        let context = CIContext(options: [.cacheIntermediates: false])
        var bytes = [UInt8](repeating: 0, count: fingerprintEdge * fingerprintEdge)
        context.render(
            scaledImage,
            toBitmap: &bytes,
            rowBytes: fingerprintEdge,
            bounds: targetBounds,
            format: .L8,
            colorSpace: CGColorSpaceCreateDeviceGray()
        )
        return bytes
    }

    nonisolated static func meanDistanceBetweenFingerprints(
        _ lhs: [UInt8],
        _ rhs: [UInt8]
    ) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else {
            return .infinity
        }

        let totalDistance = zip(lhs, rhs).reduce(into: 0) { partial, pair in
            partial += abs(Int(pair.0) - Int(pair.1))
        }
        return Double(totalDistance) / Double(lhs.count)
    }

    nonisolated static func areNearDuplicates(
        _ lhs: Data?,
        _ rhs: Data
    ) -> Bool {
        guard let lhs,
              let lhsFingerprint = fingerprint(for: lhs),
              let rhsFingerprint = fingerprint(for: rhs) else {
            return false
        }

        return meanDistanceBetweenFingerprints(lhsFingerprint, rhsFingerprint) <= nearDuplicateMaxMeanDistance
    }
}
