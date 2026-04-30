//
//  SearchKeywordizerTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/26/26.
//

import Testing
@testable import TaskTrace

struct SearchKeywordizerTests {
    @Test("keywordize includes important noun terms in the FTS query")
    func keywordizeIncludesImportantNounTermsInTheFTSQuery() {
        let query = SearchKeywordizer.keywordize("Approve quarterly invoices in Safari.")
        #expect(query.contains("\"invoice\"") || query.contains("\"invoices\""))
    }

    @Test("keywordize excludes stop words from the FTS query")
    func keywordizeExcludesStopWordsFromTheFTSQuery() {
        let query = SearchKeywordizer.keywordize("the quarterly approval")
        #expect(!query.contains("\"the\""))
    }

    @Test("keywordize falls back to token splitting when tagging yields no useful terms")
    func keywordizeFallsBackToTokenSplittingWhenTaggingYieldsNoUsefulTerms() {
        let query = SearchKeywordizer.keywordize("Q4 ledger_2026")
        #expect(query.contains("\"ledger 2026\""))
    }

    @Test("keywords extracts a meaningful word from noisy OCR text")
    func keywordsExtractsAMeaningfulWordFromNoisyOCRText() {
        let keywords = SearchKeywordizer.keywords(in: "xxq__ 77%% inv0ice invoice qqq ### apprvl ~~ ledger")
        #expect(keywords.contains("invoice"))
    }

    @Test("keywordize excludes generic verb-like expansion terms")
    func keywordizeExcludesGenericVerbLikeExpansionTerms() {
        let query = SearchKeywordizer.keywordize("Open the page and review the quarterly invoice.")
        #expect(!query.contains("\"open\""))
    }

    @Test("keywords keep multiword entities as a single term")
    func keywordsKeepMultiwordEntitiesAsASingleTerm() {
        let keywords = SearchKeywordizer.keywords(in: "Reviewed New York City tax approvals.")
        #expect(keywords.contains("new york city"))
    }

    @Test("keywordize excludes screenshot boilerplate terms")
    func keywordizeExcludesScreenshotBoilerplateTerms() {
        let query = SearchKeywordizer.keywordize("The screenshot shows the user viewing a desktop window with the quarterly invoice.")
        #expect(!query.contains("\"screenshot\"") && !query.contains("\"window\"") && !query.contains("\"user\""))
    }
}
