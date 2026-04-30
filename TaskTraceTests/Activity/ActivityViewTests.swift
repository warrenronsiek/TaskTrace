import Foundation
import Testing
@testable import TaskTrace

struct ActivityViewTests {
    @Test("starting a new screenshot load hides the previous image")
    func startingANewScreenshotLoadHidesThePreviousImage() {
        var state = ScreenshotDetailImageLoadState()
        state.startLoading(screenshotID: 1)
        state.finishLoading(screenshotID: 1, imageData: Data("one".utf8))
        state.startLoading(screenshotID: 2)

        #expect(state.displayedImageData(for: 2) == nil)
    }

    @Test("stale screenshot load completions do not replace the selected image")
    func staleScreenshotLoadCompletionsDoNotReplaceTheSelectedImage() {
        var state = ScreenshotDetailImageLoadState()
        state.startLoading(screenshotID: 1)
        state.startLoading(screenshotID: 2)
        state.finishLoading(screenshotID: 1, imageData: Data("one".utf8))

        #expect(state.displayedImageData(for: 2) == nil)
    }

    @Test("finished screenshot load displays only matching image data")
    func finishedScreenshotLoadDisplaysOnlyMatchingImageData() {
        var state = ScreenshotDetailImageLoadState()
        state.startLoading(screenshotID: 2)
        state.finishLoading(screenshotID: 2, imageData: Data("two".utf8))

        #expect(state.displayedImageData(for: 2) == Data("two".utf8))
    }

    @Test("missing screenshot image does not retry as an unloaded image")
    func missingScreenshotImageDoesNotRetryAsAnUnloadedImage() {
        var state = ScreenshotDetailImageLoadState()
        state.startLoading(screenshotID: 2)
        state.finishLoading(screenshotID: 2, imageData: nil)

        #expect(state.needsLoad(screenshotID: 2) == false)
    }
}
