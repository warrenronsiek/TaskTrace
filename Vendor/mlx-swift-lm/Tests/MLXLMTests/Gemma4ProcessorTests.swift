import Foundation
@testable import MLXVLM
import XCTest

final class Gemma4ProcessorTests: XCTestCase {
    func testNestedImageProcessorConfigTakesPrecedence() throws {
        let config = try JSONDecoder().decode(
            Gemma4ProcessorConfiguration.self,
            from: Data(
                """
                {
                  "processor_class": "Gemma4Processor",
                  "do_normalize": true,
                  "image_mean": [0.5, 0.5, 0.5],
                  "image_std": [0.5, 0.5, 0.5],
                  "image_seq_length": 999,
                  "size": { "height": 800, "width": 800 },
                  "image_processor": {
                    "do_normalize": false,
                    "image_mean": [0.0, 0.0, 0.0],
                    "image_std": [1.0, 1.0, 1.0],
                    "image_seq_length": 280,
                    "size": { "height": 224, "width": 224 }
                  }
                }
                """.utf8
            )
        )

        XCTAssertTrue(
            config.doNormalize == false
                && config.imageMean == [0.0, 0.0, 0.0]
                && config.imageStd == [1.0, 1.0, 1.0]
                && config.imageSeqLength == 280
                && Int(config.fixedSize.height) == 224
                && Int(config.fixedSize.width) == 224
        )
    }

    func testExpandPromptCollapsesTripleImagePlaceholdersToOneSoftTokenRun() throws {
        let imageTokenId = 42
        let tokens = try gemma4ExpandPromptImageTokens(
            [7, 42, 42, 42, 8],
            imageCount: 1,
            imageTokenId: imageTokenId,
            boiTokenId: 40,
            eoiTokenId: 41,
            imageSeqLength: 280
        )

        XCTAssertEqual(tokens.filter { $0 == imageTokenId }.count, 280)
    }

    func testExpandPromptThrowsWhenImagePromptHasNoPlaceholder() throws {
        var didThrow = false
        do {
            _ = try gemma4ExpandPromptImageTokens(
                [7, 8],
                imageCount: 1,
                imageTokenId: 42,
                boiTokenId: 40,
                eoiTokenId: 41,
                imageSeqLength: 280
            )
        } catch {
            didThrow = true
        }

        XCTAssertTrue(didThrow)
    }

    func testImageTokenValidationAcceptsBatchedVisionTokens() throws {
        XCTAssertNoThrow(
            try gemma4ValidateImageTokenCount(
                visionBatchSize: 2,
                visionTokensPerImage: 280,
                promptImageTokenCount: 560
            )
        )
    }

    func testImageTokenValidationRejectsSingleImageTriplePlaceholderMismatch() throws {
        var didThrow = false
        do {
            try gemma4ValidateImageTokenCount(
                visionBatchSize: 1,
                visionTokensPerImage: 280,
                promptImageTokenCount: 840
            )
        } catch {
            didThrow = true
        }

        XCTAssertTrue(didThrow)
    }
}
