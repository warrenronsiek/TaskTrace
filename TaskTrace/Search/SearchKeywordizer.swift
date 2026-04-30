//
//  SearchKeywordizer.swift
//  TaskTrace
//
//  Created by Codex on 3/26/26.
//

import Foundation
import NaturalLanguage

enum SearchKeywordizer {
    private static let stopWords = Set([
        "a",
        "an",
        "and",
        "as",
        "at",
        "for",
        "from",
        "in",
        "into",
        "of",
        "on",
        "or",
        "the",
        "to",
        "with"
    ])
    private static let genericTerms = Set([
        "application",
        "app",
        "browser",
        "click",
        "code",
        "content",
        "current",
        "currently",
        "desktop",
        "dialog",
        "display",
        "field",
        "file",
        "icon",
        "image",
        "input",
        "interface",
        "menu",
        "modal",
        "open",
        "opened",
        "panel",
        "page",
        "screen",
        "screenshot",
        "section",
        "selected",
        "shows",
        "showing",
        "sidebar",
        "tab",
        "text",
        "toolbar",
        "user",
        "using",
        "view",
        "visible",
        "website",
        "window",
        "screen",
        "show",
        "use",
        "work"
    ])
    private static let maxKeywords = 12

    static func keywordize(_ text: String) -> String {
        query(from: keywords(in: text))
    }

    static func keywords(in texts: [String]) -> [String] {
        texts.reduce(into: ([String](), Set<String>())) { partialResult, text in
            keywords(in: text).forEach { keyword in
                guard partialResult.0.count < Self.maxKeywords,
                      partialResult.1.insert(keyword).inserted
                else {
                    return
                }

                partialResult.0.append(keyword)
            }
        }.0
    }

    static func keywords(in text: String) -> [String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagOptions: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        let importantTags: Set<NLTag> = [.noun, .personalName, .placeName, .organizationName]
        let normalizedKeyword: (String) -> String? = { candidate in
            let normalized = candidate
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { $0.count > 1 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalized.isEmpty else {
                return nil
            }

            let normalizedWords = normalized.split(separator: " ").map(String.init)

            guard normalizedWords.contains(where: { !Self.stopWords.contains($0) && !Self.genericTerms.contains($0) }) else {
                return nil
            }

            return normalized
        }
        let appendKeyword: (String, inout ([String], Set<String>)) -> Void = { candidate, partialResult in
            guard let keyword = normalizedKeyword(candidate),
                  partialResult.0.count < Self.maxKeywords,
                  partialResult.1.insert(keyword).inserted
            else {
                return
            }

            partialResult.0.append(keyword)
        }
        let extractedKeywords: [String] = trimmedText.isEmpty ? [] : {
            let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
            tagger.string = trimmedText

            return {
                var partialResult = ([String](), Set<String>())

                tagger.enumerateTags(
                    in: trimmedText.startIndex..<trimmedText.endIndex,
                    unit: .word,
                    scheme: .nameTypeOrLexicalClass,
                    options: tagOptions
                ) { tag, tokenRange in
                    guard let tag, importantTags.contains(tag) else {
                        return true
                    }

                    appendKeyword(String(trimmedText[tokenRange]), &partialResult)

                    return true
                }

                return partialResult.0
            }()
        }()
        let fallbackKeywords: [String] = extractedKeywords.isEmpty ? trimmedText
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .reduce(into: ([String](), Set<String>())) { partialResult, keyword in
                appendKeyword(String(keyword), &partialResult)
            }.0 : extractedKeywords

        return fallbackKeywords
    }

    static func query(from keywords: [String]) -> String {
        keywords
            .prefix(maxKeywords)
            .map { $0.replacingOccurrences(of: "\"", with: "\"\"") }
            .map { "\"\($0)\"" }
            .joined(separator: " OR ")
    }
}
