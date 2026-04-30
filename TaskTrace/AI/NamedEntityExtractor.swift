//
//  NamedEntityExtractor.swift
//  TaskTrace
//
//  Created by Codex on 4/3/26.
//

import Foundation
import NaturalLanguage
import OSLog

nonisolated struct NamedEntity: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case person
        case place
        case organization
    }

    let text: String
    let kind: Kind
}

protocol NamedEntityExtracting: Sendable {
    nonisolated func extract(from text: String) async -> [NamedEntity]
}

actor NamedEntityExtractor: NamedEntityExtracting {
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    nonisolated func extract(from text: String) -> [NamedEntity] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            return []
        }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = trimmedText

        return {
            var entities: [NamedEntity] = []
            var seen = Set<String>()

            tagger.enumerateTags(
                in: trimmedText.startIndex..<trimmedText.endIndex,
                unit: .word,
                scheme: .nameType,
                options: [.omitWhitespace, .omitPunctuation, .joinNames]
            ) { tag, tokenRange in
                let kind: NamedEntity.Kind? = switch tag {
                case .personalName:
                    .person
                case .placeName:
                    .place
                case .organizationName:
                    .organization
                default:
                    nil
                }

                guard let kind else {
                    return true
                }

                let entityText = trimmedText[tokenRange]
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let dedupeKey = "\(kind.rawValue):\(entityText.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current))"

                guard !entityText.isEmpty, seen.insert(dedupeKey).inserted else {
                    return true
                }

                entities.append(NamedEntity(text: entityText, kind: kind))

                return true
            }

            return entities
        }()
    }
}
