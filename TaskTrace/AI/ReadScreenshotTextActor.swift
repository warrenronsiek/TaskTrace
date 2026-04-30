//
//  ReadScreenshotTextActor.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation
import CoreImage
import OSLog
import Vision

actor ReadScreenshotTextActor: Receiver, ActivityScreenshotTextRecognizing {
    private let actorSystem: ActorSystem?
    private let fallbackRecognizer: (any ActivityScreenshotTextRecognizing)?
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.fallbackRecognizer = nil
    }

    init(
        actorSystem: ActorSystem,
        screenshotTextRecognizer: any ActivityScreenshotTextRecognizing
    ) {
        self.actorSystem = actorSystem
        self.fallbackRecognizer = screenshotTextRecognizer
    }

    func ocrImage(_ image: Data) async -> String {
        if let fallbackRecognizer {
            return await fallbackRecognizer.ocrImage(image)
        }

        return await ocrImageWithVision(image)
    }

    private func ocrImageWithVision(_ image: Data) async -> String {
        do {
            let priority = Task.currentPriority

            return try await Task.detached(priority: priority) { [logger = self.logger] in
                let ciImage = try AIImageDataDecoder.image(from: image)
                let scale = max(1, 1000 / max(min(ciImage.extent.width, ciImage.extent.height), 1))
                let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                guard let cgImage = CIContext().createCGImage(scaledImage, from: scaledImage.extent) else {
                    logger.error("read-screenshot-text-actor failed to decode image")
                    return ""
                }

                let recognitionRequest = VNRecognizeTextRequest()
                recognitionRequest.recognitionLevel = .accurate
                recognitionRequest.usesLanguageCorrection = true

                try VNImageRequestHandler(cgImage: cgImage).perform([recognitionRequest])
                return (recognitionRequest.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
            }.value
        } catch {
            logger.error("read-screenshot-text-actor failed: \(String(describing: error), privacy: .public)")
            return ""
        }
    }

    func receive(_ envelope: Envelope) async {
        guard let request = envelope.message as? ReadScreenshotTextRequest else {
            return
        }

        logger.log(
            "read-screenshot-text-actor received sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) screenshotID=\(request.screenshotID, privacy: .public) bytes=\(request.image.count, privacy: .public)"
        )

        Task {
            await self.process(request)
        }
    }

    private func process(_ request: ReadScreenshotTextRequest) async {
        let text = await ocrImage(request.image)

        logger.log(
            "read-screenshot-text-actor broadcasting screenshot-text-read screenshotID=\(request.screenshotID, privacy: .public) characters=\(text.count, privacy: .public)"
        )
        await actorSystem?.broadcast(
            from: nil,
            message: ScreenshotTextRead(
                screenshotID: request.screenshotID,
                text: text
            )
        )
    }
}
