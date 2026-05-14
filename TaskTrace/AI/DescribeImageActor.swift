//
//  DescribeImageActor.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation
import MLXLMCommon
import OSLog

actor DescribeImageActor: Receiver, ActivityImageDescribing {
    nonisolated static let instructions = "You are a precise visual assistant. Only describe what is visible."
    nonisolated static let prompt =
        "Describe this screenshot in concise detail. Do not speculate beyond what is visible. Dont read out or list the text from the image, instead describe what you think the user is doing. Start directly with the content. Do not begin with phrases like 'the screenshot shows', 'this screenshot shows', 'the image shows', or similar preambles."

    private let actorSystem: ActorSystem?
    private let fallbackImageDescriber: (any ActivityImageDescribing)?
    private let imageDescriber: any ActivityImageDescribing
    private let screenshotTextRecognizer: ReadScreenshotTextActor
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.fallbackImageDescriber = nil
        self.imageDescriber = AISchedulerClient.shared
        self.screenshotTextRecognizer = ReadScreenshotTextActor(actorSystem: actorSystem)
    }

    init(
        actorSystem: ActorSystem,
        imageDescriber: any ActivityImageDescribing
    ) {
        self.actorSystem = actorSystem
        self.fallbackImageDescriber = imageDescriber
        self.imageDescriber = imageDescriber
        self.screenshotTextRecognizer = ReadScreenshotTextActor(
            actorSystem: actorSystem,
            visibleTextReader: EmptyActivityVisibleTextReader()
        )
    }

    func describeImage(_ image: Data) async -> String {
        do {
            let description = try await describeImageResponse(image)
            return description.isEmpty ? "Image description unavailable." : description
        } catch {
            logger.error("describe-image-actor failed: \(String(describing: error), privacy: .public)")
            return "Image description unavailable."
        }
    }

    private func describeImageResponse(_ image: Data) async throws -> String {
        if let fallbackImageDescriber {
            return await fallbackImageDescriber.describeImage(image)
        }

        let rawResponse = await imageDescriber.describeImage(image)
        let description = AITextUtilities.normalizedNarration(rawResponse)
        let recognizedText = await screenshotTextRecognizer.ocrImage(image)
        let normalizedText = recognizedText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "; ")

        let lowercasedDescription = description.lowercased()
        let needsTextFallback = description.isEmpty
            || lowercasedDescription == "image description unavailable."
            || lowercasedDescription.contains("you are a precise visual assistant")
            || lowercasedDescription.contains("visible application names")
            || lowercasedDescription.contains("and likely work context")
            || lowercasedDescription.contains("do not begin with phrases")

        if needsTextFallback {
            return normalizedText.isEmpty ? "Image description unavailable." : "Visible text: \(normalizedText)"
        }

        return normalizedText.isEmpty ? description : "\(description)\nVisible text: \(normalizedText)"
    }

    func receive(_ envelope: Envelope) async {
        guard let request = envelope.message as? DescribeImageRequest else {
            return
        }

        logger.log(
            "describe-image-actor received sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) screenshotID=\(request.screenshotID, privacy: .public)"
        )
        Task {
            await self.process(request)
        }
    }

    private func process(_ request: DescribeImageRequest) async {
        let description = await describeImage(request.image)

        logger.log(
            "describe-image-actor broadcasting image-described screenshotID=\(request.screenshotID, privacy: .public) characters=\(description.count, privacy: .public)"
        )
        await actorSystem?.broadcast(
            from: nil,
            message: ImageDescribed(
                screenshotID: request.screenshotID,
                description: description
            )
        )
    }
}
