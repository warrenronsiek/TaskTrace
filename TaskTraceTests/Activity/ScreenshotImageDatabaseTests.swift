import AppKit
import Foundation
import Testing
@testable import TaskTrace

struct ScreenshotImageDatabaseTests {
    @Test("loading screenshot images returns the blob for the requested screenshot id")
    func loadingScreenshotImagesReturnsTheBlobForTheRequestedScreenshotID() async throws {
        let setup = try makeActivityDatabaseActor()

        try await setup.database.saveActivityRecord(ActivityInput(
            id: 100,
            startTime: Date(timeIntervalSince1970: 1_777_000_000),
            application: "Xcode",
            keystrokes: "abc",
            microphone: nil,
            summary: nil,
            tagID: nil,
            jsonProperties: nil,
            overviewID: nil
        ))
        try await setup.database.saveScreenshotRecord(
            activityID: 100,
            screenshot: ScreenshotInput(
                id: 101,
                image: Data("image-one".utf8),
                timestamp: Date(timeIntervalSince1970: 1_777_000_001),
                description: "desc one",
                text: nil,
                ignoreReason: nil,
                jsonProperties: nil
            )
        )
        try await setup.database.saveScreenshotRecord(
            activityID: 100,
            screenshot: ScreenshotInput(
                id: 102,
                image: Data("image-two".utf8),
                timestamp: Date(timeIntervalSince1970: 1_777_000_002),
                description: "desc two",
                text: nil,
                ignoreReason: nil,
                jsonProperties: nil
            )
        )

        let result = try await (
            setup.actor.loadScreenshotImage(screenshotID: 101),
            setup.actor.loadScreenshotImage(screenshotID: 102)
        )

        #expect(result.0 == Data("image-one".utf8) && result.1 == Data("image-two".utf8))
    }

    @Test("saving activity updates for persisted screenshots keeps the stored image blob")
    func savingActivityUpdatesForPersistedScreenshotsKeepsTheStoredImageBlob() async throws {
        let setup = try makeActivityDatabaseActor()
        let image = try #require(makePNGData(red: 24, green: 96, blue: 180))
        let createdActivity = makeActivity(
            image: image,
            description: nil,
            text: nil
        )

        await setup.actor.receive(
            Envelope(
                sender: nil,
                message: ActivityCreated(activity: createdActivity)
            )
        )

        let initialImage = try #require(
            await setup.actor.loadScreenshotImage(screenshotID: createdActivity.screenshots[0].id)
        )

        await setup.actor.receive(
            Envelope(
                sender: nil,
                message: ActivityUpdated(
                    activity: makeActivity(
                        image: image,
                        description: nil,
                        text: "ocr text"
                    )
                )
            )
        )

        let persistedImage = try #require(
            await setup.actor.loadScreenshotImage(screenshotID: createdActivity.screenshots[0].id)
        )
        let fetched = try await setup.database.get(.screenshot(.id(createdActivity.screenshots[0].id)))

        guard case let .screenshot(record?) = fetched else {
            Issue.record("expected screenshot record")
            return
        }

        #expect((persistedImage, record.ocrText) == (initialImage, "ocr text"))
    }

}

private func makeActivityDatabaseActor() throws -> (actor: ActivityDatabaseActor, database: TaskTraceDatabase) {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

    let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
    return (
        ActivityDatabaseActor(database: database),
        database
    )
}

private func makeActivity(
    image: Data,
    description: String?,
    text: String?
) -> ActivityActor.Activity {
    ActivityActor.Activity(
        id: 100,
        application: "Xcode",
        startTime: Date(timeIntervalSince1970: 1_777_000_000),
        keystrokes: "",
        microphone: "",
        summary: nil,
        overviewID: nil,
        tagID: nil,
        screenshots: [
            ActivityActor.Screenshot(
                id: 101,
                image: image,
                timestamp: Date(timeIntervalSince1970: 1_777_000_001),
                description: description,
                text: text,
                ignoreReason: nil
            )
        ]
    )
}

private func makePNGData(
    width: Int = 4,
    height: Int = 4,
    red: UInt8,
    green: UInt8,
    blue: UInt8
) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    ), let data = bitmap.bitmapData else {
        return nil
    }

    for offset in stride(from: 0, to: width * height * 4, by: 4) {
        data[offset] = red
        data[offset + 1] = green
        data[offset + 2] = blue
        data[offset + 3] = 255
    }

    return bitmap.representation(using: .png, properties: [:])
}
