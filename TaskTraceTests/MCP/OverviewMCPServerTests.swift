//
//  OverviewMCPServerTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/21/26.
//

import Foundation
import MCP
import Testing
@testable import TaskTrace

@MainActor
struct OverviewMCPServerTests {
    @Test("tool list includes the search tool when it is enabled")
    func toolListIncludesTheSearchToolWhenItIsEnabled() async {
        let runtime = OverviewMCPServerRuntime(searchService: makeSearchService())
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.searchToolEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect((await runtime.toolNames()).contains(Vars.mcpSearchToolName))
    }

    @Test("tool list omits the search tool when it is disabled")
    func toolListOmitsTheSearchToolWhenItIsDisabled() async {
        let runtime = OverviewMCPServerRuntime(searchService: makeSearchService())
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.searchToolEnabled = false

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect(!((await runtime.toolNames()).contains(Vars.mcpSearchToolName)))
    }

    @Test("resource list includes the overview feed when it is enabled")
    func resourceListIncludesTheOverviewFeedWhenItIsEnabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.overviewResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect((await runtime.resourceURIs()).contains(Vars.mcpOverviewResourceURI))
    }

    @Test("resource list omits the overview feed when it is disabled")
    func resourceListOmitsTheOverviewFeedWhenItIsDisabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.overviewResourceEnabled = false

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect(!((await runtime.resourceURIs()).contains(Vars.mcpOverviewResourceURI)))
    }

    @Test("resource list includes the high level feed when it is enabled")
    func resourceListIncludesTheHighLevelFeedWhenItIsEnabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.highLevelActivityResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect((await runtime.resourceURIs()).contains(Vars.mcpHighLevelActivityResourceURI))
    }

    @Test("resource list omits the detailed feed when it is disabled")
    func resourceListOmitsTheDetailedFeedWhenItIsDisabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = false

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect(!((await runtime.resourceURIs()).contains(Vars.mcpDetailedActivityResourceURI)))
    }

    @Test("resource list includes the detailed feed when it is enabled")
    func resourceListIncludesTheDetailedFeedWhenItIsEnabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect((await runtime.resourceURIs()).contains(Vars.mcpDetailedActivityResourceURI))
    }

    @Test("resource template list includes the screenshot template when the detailed feed is enabled")
    func resourceTemplateListIncludesTheScreenshotTemplateWhenTheDetailedFeedIsEnabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect((await runtime.resourceTemplateURIs()).contains(Vars.mcpActivityScreenshotResourceTemplateURI))
    }

    @Test("resource template list omits the screenshot template when the detailed feed is disabled")
    func resourceTemplateListOmitsTheScreenshotTemplateWhenTheDetailedFeedIsDisabled() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = false

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [],
            configuration: configuration
        )

        #expect(!((await runtime.resourceTemplateURIs()).contains(Vars.mcpActivityScreenshotResourceTemplateURI)))
    }

    @Test("the detailed feed exposes screenshot URIs")
    func theDetailedFeedExposesScreenshotURIs() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true
        let screenshotData = Data("fake-webp-data".utf8)
        let expectedURI = Vars.mcpActivityScreenshotResourceURI(activityId: 123, screenshotId: 17)

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [
                makeActivity(
                    summary: nil,
                    screenshots: [
                        makeScreenshot(image: screenshotData)
                    ]
                )
            ],
            configuration: configuration
        )

        let detailedFeedText = await runtime.resourceContents(uri: Vars.mcpDetailedActivityResourceURI)?.first?.text ?? ""
        #expect(detailedFeedText.contains(expectedURI))
    }

    @Test("the detailed feed exposes screenshot descriptions")
    func theDetailedFeedExposesScreenshotDescriptions() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [
                makeActivity(
                    summary: nil,
                    screenshots: [
                        makeScreenshot()
                    ]
                )
            ],
            configuration: configuration
        )

        let detailedFeedText = await runtime.resourceContents(uri: Vars.mcpDetailedActivityResourceURI)?.first?.text ?? ""
        #expect(detailedFeedText.contains("VS Code showing MCP server code"))
    }

    @Test("the detailed feed exposes screenshot OCR")
    func theDetailedFeedExposesScreenshotOCR() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [
                makeActivity(
                    summary: nil,
                    screenshots: [
                        makeScreenshot()
                    ]
                )
            ],
            configuration: configuration
        )

        let detailedFeedText = await runtime.resourceContents(uri: Vars.mcpDetailedActivityResourceURI)?.first?.text ?? ""
        #expect(detailedFeedText.contains("resource template implementation"))
    }

    @Test("the detailed feed exposes screenshot summaries")
    func theDetailedFeedExposesScreenshotSummaries() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [
                makeActivity(
                    summary: nil,
                    screenshots: [
                        makeScreenshot()
                    ]
                )
            ],
            configuration: configuration
        )

        let detailedFeedText = await runtime.resourceContents(uri: Vars.mcpDetailedActivityResourceURI)?.first?.text ?? ""
        #expect(detailedFeedText.contains("Implementing the MCP resource template."))
    }

    @Test("the detailed feed omits embedded screenshot blobs")
    func theDetailedFeedOmitsEmbeddedScreenshotBlobs() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true
        let screenshotData = Data("fake-webp-data".utf8)

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [
                makeActivity(
                    summary: nil,
                    screenshots: [
                        makeScreenshot(image: screenshotData)
                    ]
                )
            ],
            configuration: configuration
        )

        let detailedFeedText = await runtime.resourceContents(uri: Vars.mcpDetailedActivityResourceURI)?.first?.text ?? ""
        #expect(!detailedFeedText.contains(screenshotData.base64EncodedString()))
    }

    @Test("reading a screenshot URI returns binary screenshot bytes")
    func readingAScreenshotURIReturnsBinaryScreenshotBytes() async {
        let runtime = OverviewMCPServerRuntime()
        var configuration = SettingsStore.MCPConfiguration.default
        configuration.detailedActivityResourceEnabled = true
        let screenshotData = Data("fake-webp-data".utf8)
        let screenshotURI = Vars.mcpActivityScreenshotResourceURI(activityId: 123, screenshotId: 17)

        await runtime.update(
            activeDay: Date(timeIntervalSince1970: 0),
            overviews: [],
            activities: [
                makeActivity(
                    summary: nil,
                    screenshots: [
                        makeScreenshot(image: screenshotData)
                    ]
                )
            ],
            configuration: configuration
        )

        let screenshotBlob = await runtime.resourceContents(uri: screenshotURI)?.first?.blob
        #expect(screenshotBlob == screenshotData.base64EncodedString())
    }

    @Test("starting the broker creates the socket")
    func startingTheBrokerCreatesTheSocket() async {
        let socketPath = "/tmp/tasktrace-mcp-\(UUID().uuidString).sock"
        let runtime = OverviewMCPServerRuntime(socketPath: socketPath)

        await runtime.start()

        #expect(FileManager.default.fileExists(atPath: socketPath))
        await runtime.stop()
    }

    @Test("stopping the broker removes the socket")
    func stoppingTheBrokerRemovesTheSocket() async {
        let socketPath = "/tmp/tasktrace-mcp-\(UUID().uuidString).sock"
        let runtime = OverviewMCPServerRuntime(socketPath: socketPath)

        await runtime.start()
        await runtime.stop()

        #expect(!FileManager.default.fileExists(atPath: socketPath))
    }

}

private func makeActivity(
    id: Int64 = 123,
    startTime: Date = Date(timeIntervalSince1970: 60),
    application: String = "Xcode",
    keystrokes: String = "git push",
    microphone: String = "Discussed MCP changes",
    summary: String? = "Implemented the MCP server refactor",
    screenshots: [ActivityActor.Screenshot] = []
) -> ActivityActor.Activity {
    ActivityActor.Activity(
        id: id,
        application: application,
        startTime: startTime,
        keystrokes: keystrokes,
        microphone: microphone,
        summary: summary,
        overviewID: 99,
        tagID: 7,
        screenshots: screenshots
    )
}

private func makeSearchService() -> TaskTraceSearchService {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
    let activityAI = FakeActivityAI()

    try! FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

    return TaskTraceSearchService(
        database: try! TaskTraceDatabase(
            databaseURL: try! TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL),
            activityAI: activityAI
        ),
        activityAI: activityAI
    )
}

private func makeScreenshot(
    id: Int64 = 17,
    image: Data? = Data("fake-webp-data".utf8),
    timestamp: Date = Date(timeIntervalSince1970: 90),
    description: String? = "VS Code showing MCP server code",
    text: String? = "resource template implementation",
    summary: String? = "Implementing the MCP resource template."
) -> ActivityActor.Screenshot {
    ActivityActor.Screenshot(
        id: id,
        image: image,
        timestamp: timestamp,
        description: description,
        text: text,
        summary: summary,
        ignoreReason: nil
    )
}
