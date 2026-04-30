import AppKit
import Foundation
import Testing
import Vision
@testable import TaskTrace

struct OCRTests {

    @Test("ReadScreenshotTextActor returns empty for invalid image bytes")
    func readScreenshotTextActorReturnsEmptyForInvalidBytes() async {
        let actor = ReadScreenshotTextActor(actorSystem: ActorSystem())
        let text = await actor.ocrImage(Data("not-an-image".utf8))
        #expect(text == "")
    }
}

@Suite(.serialized)
struct OCRIntegrationTests {

    @Test("VNRecognizeText (accurate, language correction) extracts lines from a synthetic text image")
    func visionAccurateRecognitionExtractsLinesFromScreenshot() async throws {
        let image = NSImage(size: NSSize(width: 1200, height: 400))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 400).fill()
        "TaskTrace OCR Fixture".draw(
            at: NSPoint(x: 80, y: 230),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 72, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
        )
        "Open source release safety".draw(
            at: NSPoint(x: 80, y: 130),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 52, weight: .regular),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Issue.record("Failed to render synthetic OCR image as CGImage")
            return
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let start = Date()
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        let elapsed = Date().timeIntervalSince(start)

        let observations = request.results ?? []
        let lines: [String] = observations.compactMap { $0.topCandidates(1).first?.string }

        print("Vision OCR (accurate) elapsed: \(String(format: "%.3f", elapsed))s")
        print("Vision OCR (accurate) line count: \(lines.count)")
        print("Vision OCR (accurate) lines:")
        for line in lines {
            print(line)
        }

        #expect(!lines.isEmpty, "Vision should produce at least one line of text from the synthetic image")
    }
}
