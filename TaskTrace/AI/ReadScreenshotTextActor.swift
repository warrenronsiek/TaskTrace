//
//  ReadScreenshotTextActor.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import AppKit
import ApplicationServices
import CoreImage
import Foundation
import OSLog
import Vision

protocol ActivityVisibleTextReading: Sendable {
    func visibleActiveText() async -> String
}

struct EmptyActivityVisibleTextReader: ActivityVisibleTextReading {
    func visibleActiveText() async -> String {
        ""
    }
}

struct MacOSAccessibilityVisibleTextReader: ActivityVisibleTextReading {
    private let logger: Logger
    private let maxNodes: Int
    private let maxCharacters: Int

    nonisolated init(
        logger: Logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai"),
        maxNodes: Int = 400,
        maxCharacters: Int = AITextUtilities.promptSourceCharacterLimit
    ) {
        self.logger = logger
        self.maxNodes = maxNodes
        self.maxCharacters = maxCharacters
    }

    nonisolated func visibleActiveText() async -> String {
        await MainActor.run {
            readVisibleActiveText()
        }
    }

    @MainActor
    private func readVisibleActiveText() -> String {
        guard accessibilityIsTrusted(),
              let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return ""
        }

        let appElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
        let roots = uniqueElements([
            elementAttribute(kAXFocusedWindowAttribute, from: appElement),
            elementAttribute(kAXMainWindowAttribute, from: appElement),
            elementAttribute(kAXFocusedUIElementAttribute, from: appElement)
        ].compactMap { $0 })

        guard !roots.isEmpty else {
            return ""
        }

        var state = TraversalState()
        for root in roots {
            collectText(from: root, state: &state)
            if state.exhausted(maxNodes: maxNodes, maxCharacters: maxCharacters) {
                break
            }
        }

        return ActivityScreenshotTextNormalizer.normalizedText(state.lines, maxCharacters: maxCharacters)
    }

    private func accessibilityIsTrusted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: kCFBooleanFalse] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func collectText(from element: AXUIElement, state: inout TraversalState) {
        guard !state.exhausted(maxNodes: maxNodes, maxCharacters: maxCharacters) else {
            return
        }

        let identifier = CFHash(element)
        guard !state.visitedElementIDs.contains(identifier) else {
            return
        }

        state.visitedElementIDs.insert(identifier)
        state.nodeCount += 1

        if hiddenAttribute(from: element) == true {
            return
        }

        textAttributes(from: element).forEach { text in
            state.append(text, maxCharacters: maxCharacters)
        }

        for child in childElements(from: element) {
            collectText(from: child, state: &state)
            if state.exhausted(maxNodes: maxNodes, maxCharacters: maxCharacters) {
                break
            }
        }
    }

    private func textAttributes(from element: AXUIElement) -> [String] {
        [
            stringAttribute(kAXSelectedTextAttribute, from: element),
            stringAttribute(kAXValueAttribute, from: element),
            stringAttribute(kAXTitleAttribute, from: element),
            stringAttribute(kAXDescriptionAttribute, from: element),
            stringAttribute(kAXHelpAttribute, from: element)
        ].compactMap { $0 }
    }

    private func childElements(from element: AXUIElement) -> [AXUIElement] {
        let visibleChildren = elementArrayAttribute(kAXVisibleChildrenAttribute, from: element)
        if !visibleChildren.isEmpty {
            return visibleChildren
        }

        return elementArrayAttribute(kAXChildrenAttribute, from: element)
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        guard let value = copyAttribute(attribute, from: element) else {
            return nil
        }

        if let string = value as? String {
            return string
        }

        if let attributedString = value as? NSAttributedString {
            return attributedString.string
        }

        return nil
    }

    private func hiddenAttribute(from element: AXUIElement) -> Bool? {
        guard let value = copyAttribute(kAXHiddenAttribute, from: element) else {
            return nil
        }

        return value as? Bool
    }

    private func elementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func elementArrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(attribute, from: element) else {
            return []
        }

        return (value as? [AXUIElement]) ?? []
    }

    private func copyAttribute(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            if result != .attributeUnsupported && result != .noValue {
                logger.debug("accessibility text read skipped attribute=\(attribute as String, privacy: .public) result=\(result.rawValue, privacy: .public)")
            }
            return nil
        }

        return value
    }

    private func uniqueElements(_ elements: [AXUIElement]) -> [AXUIElement] {
        var seen: Set<CFHashCode> = []
        var unique: [AXUIElement] = []

        for element in elements {
            let identifier = CFHash(element)
            guard !seen.contains(identifier) else {
                continue
            }

            seen.insert(identifier)
            unique.append(element)
        }

        return unique
    }

    private struct TraversalState {
        var visitedElementIDs: Set<CFHashCode> = []
        var nodeCount = 0
        var characterCount = 0
        var lines: [String] = []

        mutating func append(_ text: String, maxCharacters: Int) {
            guard characterCount < maxCharacters else {
                return
            }

            lines.append(text)
            characterCount += text.count
        }

        func exhausted(maxNodes: Int, maxCharacters: Int) -> Bool {
            nodeCount >= maxNodes || characterCount >= maxCharacters
        }
    }
}

enum ActivityScreenshotTextNormalizer {
    static func normalizedText(_ text: String, maxCharacters: Int = AITextUtilities.promptSourceCharacterLimit) -> String {
        normalizedText([text], maxCharacters: maxCharacters)
    }

    static func normalizedText(_ sources: [String], maxCharacters: Int = AITextUtilities.promptSourceCharacterLimit) -> String {
        var seen: Set<String> = []
        var lines: [String] = []
        var characterCount = 0

        for source in sources {
            for line in source.components(separatedBy: .newlines) {
                let normalizedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedLine.isEmpty else {
                    continue
                }

                let key = normalizedLine.lowercased()
                guard !seen.contains(key) else {
                    continue
                }

                seen.insert(key)
                lines.append(normalizedLine)
                characterCount += normalizedLine.count

                if characterCount >= maxCharacters {
                    return String(lines.joined(separator: "\n").prefix(maxCharacters))
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}

actor ReadScreenshotTextActor: Receiver, ActivityScreenshotTextRecognizing {
    private let actorSystem: ActorSystem?
    private let fallbackRecognizer: (any ActivityScreenshotTextRecognizing)?
    private let visibleTextReader: any ActivityVisibleTextReading
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init(
        actorSystem: ActorSystem,
        visibleTextReader: any ActivityVisibleTextReading = MacOSAccessibilityVisibleTextReader()
    ) {
        self.actorSystem = actorSystem
        self.fallbackRecognizer = nil
        self.visibleTextReader = visibleTextReader
    }

    init(
        actorSystem: ActorSystem,
        screenshotTextRecognizer: any ActivityScreenshotTextRecognizing,
        visibleTextReader: any ActivityVisibleTextReading = MacOSAccessibilityVisibleTextReader()
    ) {
        self.actorSystem = actorSystem
        self.fallbackRecognizer = screenshotTextRecognizer
        self.visibleTextReader = visibleTextReader
    }

    func ocrImage(_ image: Data) async -> String {
        let visibleText = ActivityScreenshotTextNormalizer.normalizedText(await visibleTextReader.visibleActiveText())
        if !visibleText.isEmpty {
            logger.log("read-screenshot-text-actor used accessibility text characters=\(visibleText.count, privacy: .public)")
            return visibleText
        }

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
