//
//  BrowserPluginHostTests.swift
//  TaskTraceTests
//

import Foundation
import Testing
@testable import TaskTrace

struct BrowserPluginHostTests {
    private actor SignalCounter {
        private var value = 0

        func increment() {
            value += 1
        }

        func snapshot() -> Int {
            value
        }
    }

    private final class TestBrowserPluginIngestChangeSignal: BrowserPluginIngestChangeSignaling {
        private var handlers: [ObjectIdentifier: @Sendable () -> Void] = [:]

        func postDirectoryDidChange() {
            handlers.values.forEach { $0() }
        }

        func addDirectoryDidChangeObserver(
            _ handler: @escaping @Sendable () -> Void
        ) -> NSObjectProtocol {
            let observer = NSObject()
            handlers[ObjectIdentifier(observer)] = handler
            return observer
        }

        func removeObserver(_ observer: NSObjectProtocol) {
            guard let observerObject = observer as AnyObject? else {
                return
            }

            handlers.removeValue(forKey: ObjectIdentifier(observerObject))
        }
    }

    private func withMessageService(
        _ block: (BrowserPluginMessageService, URL, TestBrowserPluginIngestChangeSignal) async throws -> Void
    ) async throws {
        let ingestURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let signal = TestBrowserPluginIngestChangeSignal()
        let service = BrowserPluginMessageService(
            ingestDirectoryURL: { ingestURL },
            ingestChangeSignal: signal,
            now: { Date(timeIntervalSince1970: 1_776_091_200) }
        )

        try await block(service, ingestURL, signal)
    }

    @Test("native messaging frames round trip")
    func nativeMessagingFramesRoundTrip() throws {
        let response = BrowserPluginHostResponse(
            kind: .helloWorld,
            message: "Hello World!",
            receivedURL: "https://example.com",
            receivedTitle: "Example",
            receivedCharacterCount: 42
        )

        let framedResponse = try BrowserPluginNativeMessagingCodec.frame(response)
        let payload = try BrowserPluginNativeMessagingCodec.decodeFrame(framedResponse)
        let decodedResponse = try JSONDecoder().decode(BrowserPluginHostResponse.self, from: payload)

        #expect(decodedResponse == response)
    }

    @Test("truncated frame payload throws")
    func truncatedFramePayloadThrows() {
        var littleEndianLength = UInt32(5).littleEndian
        let header = withUnsafeBytes(of: &littleEndianLength) { Data($0) }
        let framedResponse = header + Data("abc".utf8)

        #expect(throws: BrowserPluginNativeMessagingError.truncatedPayload(expected: 5, actual: 3)) {
            try BrowserPluginNativeMessagingCodec.decodeFrame(framedResponse)
        }
    }

    @Test("captured page text gets hello world response")
    func capturedPageTextGetsHelloWorldResponse() async {
        let service = BrowserPluginMessageService()
        let response = await service.handle(
            BrowserPluginHostRequest(
                kind: .capturePageText,
                page: BrowserPluginPagePayload(
                    title: "Doc",
                    url: "file:///tmp/doc.txt",
                    markdown: "# This is the current page text.",
                    contentType: "text/markdown",
                    sourceContentType: "text/plain"
                )
            )
        )

        #expect(response.kind == .helloWorld)
    }

    @Test("captured page text reports character count")
    func capturedPageTextReportsCharacterCount() async {
        let service = BrowserPluginMessageService()
        let response = await service.handle(
            BrowserPluginHostRequest(
                kind: .capturePageText,
                page: BrowserPluginPagePayload(
                    title: "Doc",
                    url: "file:///tmp/doc.txt",
                    markdown: "# This is the current page text.",
                    contentType: "text/markdown",
                    sourceContentType: "text/plain"
                )
            )
        )

        #expect(response.receivedCharacterCount == 32)
    }

    @Test("captured page text writes markdown into the browser plugin ingest directory")
    func capturedPageTextWritesMarkdownIntoTheBrowserPluginIngestDirectory() async throws {
        try await withMessageService { service, ingestURL, _ in
            _ = await service.handle(
                BrowserPluginHostRequest(
                    kind: .capturePageText,
                    page: BrowserPluginPagePayload(
                        title: "Spec Review",
                        url: "https://example.com/spec",
                        markdown: "# Spec Review\n\nCaptured from the browser plugin.",
                        contentType: "text/markdown",
                        sourceContentType: "text/html"
                    )
                )
            )

            let fileNames = try FileManager.default.contentsOfDirectory(atPath: ingestURL.path)
            #expect(fileNames.count == 1)
        }
    }

    @Test("captured page text names the file from the first markdown words")
    func capturedPageTextNamesTheFileFromTheFirstMarkdownWords() async throws {
        try await withMessageService { service, ingestURL, _ in
            _ = await service.handle(
                BrowserPluginHostRequest(
                    kind: .capturePageText,
                    page: BrowserPluginPagePayload(
                        title: "Generic Tab",
                        url: "https://example.com/spec",
                        markdown: "# Build a local event pipeline for browser captures\n\nBody text.",
                        contentType: "text/markdown",
                        sourceContentType: "text/html"
                    )
                )
            )

            let fileNames = try FileManager.default.contentsOfDirectory(atPath: ingestURL.path)
            let fileName = try #require(fileNames.first)
            #expect(fileName.contains("build-a-local-event-pipeline-for-browser-captures"))
        }
    }

    @Test("captured page text includes browser plugin metadata in the written markdown")
    func capturedPageTextIncludesBrowserPluginMetadataInTheWrittenMarkdown() async throws {
        try await withMessageService { service, ingestURL, _ in
            _ = await service.handle(
                BrowserPluginHostRequest(
                    kind: .capturePageText,
                    page: BrowserPluginPagePayload(
                        title: "Spec Review",
                        url: "https://example.com/spec",
                        markdown: "# Spec Review\n\nCaptured from the browser plugin.",
                        contentType: "text/markdown",
                        sourceContentType: "text/html"
                    )
                )
            )

            let fileURL = try #require(
                try FileManager.default
                    .contentsOfDirectory(
                        at: ingestURL,
                        includingPropertiesForKeys: nil
                    )
                    .first
            )
            let content = try String(contentsOf: fileURL, encoding: .utf8)

            #expect(content.contains("ingested_via: \"tasktrace_browser_plugin\""))
        }
    }

    @Test("captured page text posts a browser plugin ingest change signal")
    func capturedPageTextPostsABrowserPluginIngestChangeSignal() async throws {
        try await withMessageService { service, _, signal in
            let counter = SignalCounter()
            let observer = signal.addDirectoryDidChangeObserver {
                Task {
                    await counter.increment()
                }
            }
            defer {
                signal.removeObserver(observer)
            }

            _ = await service.handle(
                BrowserPluginHostRequest(
                    kind: .capturePageText,
                    page: BrowserPluginPagePayload(
                        title: "Spec Review",
                        url: "https://example.com/spec",
                        markdown: "# Spec Review\n\nCaptured from the browser plugin.",
                        contentType: "text/markdown",
                        sourceContentType: "text/html"
                    )
                )
            )

            try await Task.sleep(nanoseconds: 50_000_000)

            #expect(await counter.snapshot() == 1)
        }
    }
}
