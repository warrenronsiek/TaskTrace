//
//  NamedEntityExtractorTests.swift
//  TaskTraceTests
//
//  Created by Codex on 4/3/26.
//

import Testing
@testable import TaskTrace

struct NamedEntityExtractorTests {
    private func approximatelyTwelveHundredTokenChunk(inserting sentence: String) -> String {
        let filler = Array(
            repeating: "The team reviewed architecture notes, debugging steps, product planning, browser tests, billing exports, migration tasks, documentation, and design revisions.",
            count: 35
        )
        .joined(separator: " ")

        return "\(filler) \(sentence) \(filler)"
    }

    @Test("extract returns person entities from a long text chunk")
    func extractReturnsPersonEntitiesFromALongTextChunk() async {
        let extractor = NamedEntityExtractor()
        let entities = await extractor.extract(
            from: approximatelyTwelveHundredTokenChunk(
                inserting: "Later that afternoon, Sarah Chen approved the release notes for the client update."
            )
        )

        #expect(entities.contains(NamedEntity(text: "Sarah Chen", kind: .person)))
    }

    @Test("extract returns place entities from a long text chunk")
    func extractReturnsPlaceEntitiesFromALongTextChunk() async {
        let extractor = NamedEntityExtractor()
        let entities = await extractor.extract(
            from: approximatelyTwelveHundredTokenChunk(
                inserting: "The workshop moved from New York City to San Francisco after the venue change came through."
            )
        )

        #expect(entities.contains(NamedEntity(text: "San Francisco", kind: .place)))
    }

    @Test("extract returns organization entities from a long text chunk")
    func extractReturnsOrganizationEntitiesFromALongTextChunk() async {
        let extractor = NamedEntityExtractor()
        let entities = await extractor.extract(
            from: approximatelyTwelveHundredTokenChunk(
                inserting: "The compliance memo referenced the American Red Cross during the partnership review."
            )
        )

        #expect(entities.contains(NamedEntity(text: "American Red Cross", kind: .organization)))
    }
}
