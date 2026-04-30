//
//  AITextUtilities.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation

enum AITextUtilities {
    nonisolated static let promptSourceCharacterLimit = 12_000

    nonisolated static func normalizedNarration(_ text: String) -> String {
        let prefixes = [
            "the user was ",
            "the user is ",
            "the user appears to be ",
            "this screenshot shows ",
            "the screenshot shows ",
            "this image shows ",
            "the image shows ",
            "a screenshot of ",
            "an image of "
        ]

        let normalized = {
            var result = text

            while let range = prefixes.compactMap({
                result.range(of: $0, options: [.anchored, .caseInsensitive])
            }).first {
                result = String(result[range.upperBound...])
            }

            guard let first = result.first, first.isLowercase else {
                return result
            }

            return first.uppercased() + result.dropFirst()
        }()

        return normalized.isEmpty ? text : normalized
    }

    nonisolated static func strippingThinkingBlocks(from text: String) -> String {
        let withoutBalancedBlocks = text.replacingOccurrences(
            of: #"(?is)<think>.*?</think>"#,
            with: "",
            options: .regularExpression
        )
        guard let danglingOpenRange = withoutBalancedBlocks.range(
            of: "<think>",
            options: [.anchored, .caseInsensitive]
        ) else {
            return withoutBalancedBlocks
        }

        return String(withoutBalancedBlocks[danglingOpenRange.upperBound...])
    }

    nonisolated static func prefixedText(_ text: String, promptPrefix: String?) -> String {
        guard let promptPrefix, !promptPrefix.isEmpty else {
            return text
        }

        let separator = promptPrefix.hasSuffix(" ") || text.isEmpty ? "" : " "
        return promptPrefix + separator + text
    }

    nonisolated static func clippedPromptSourceText(
        _ value: String?,
        maxCharacters: Int = promptSourceCharacterLimit
    ) -> String {
        let text = value ?? ""

        guard text.count > maxCharacters else {
            return text
        }

        return String(text.prefix(maxCharacters))
    }

    nonisolated static func xmlEscaped(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
