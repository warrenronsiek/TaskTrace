//
//  ActivityAITests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/13/26.
//

import Foundation
import MLXLMCommon
import Testing
@testable import TaskTrace

struct ActivityAITests {
    @Test("clipped prompt source text leaves short text unchanged")
    func clippedPromptSourceTextLeavesShortTextUnchanged() {
        let result = AITextUtilities.clippedPromptSourceText("short text")

        #expect(result == "short text")
    }

    @Test("clipped prompt source text caps long text at the shared limit")
    func clippedPromptSourceTextCapsLongTextAtTheSharedLimit() {
        let result = AITextUtilities.clippedPromptSourceText(String(repeating: "a", count: 12_001))

        #expect(result.count == AITextUtilities.promptSourceCharacterLimit)
    }

    @Test("describeImage returns unavailable when the bytes are not a decodable image")
    func describeImageReturnsUnavailableForInvalidImageBytes() async {
        let describeImageActor = DescribeImageActor(actorSystem: ActorSystem())
        let description = await describeImageActor.describeImage(Data("not-an-image".utf8))

        #expect(description == "Image description unavailable.")
    }

    @Test("visual model uses the Gemma 4 E2B IT bundle")
    func visualModelUsesGemma4E2BITBundle() {
        #expect(
            (Vars.visualModelId, Vars.visualModelDirectoryName)
                == ("mlx-community/gemma-4-e2b-it-4bit", "gemma-4-e2b-it-4bit")
        )
    }

    @Test("text models use Qwen 3.5 OptiQ bundles")
    func textModelsUseQwen35OptiQBundles() {
        #expect(
            (
                Vars.bigTextModelId,
                Vars.bigTextModelDirectoryName,
                Vars.smallTextModelId,
                Vars.smallTextModelDirectoryName
            ) == (
                "mlx-community/Qwen3.5-4B-OptiQ-4bit",
                "Qwen3.5-4B-OptiQ-4bit",
                "mlx-community/Qwen3.5-0.8B-OptiQ-4bit",
                "Qwen3.5-0.8B-OptiQ-4bit"
            )
        )
    }

    @Test("describe image prompt omits screenshot click guidance")
    func describeImagePromptOmitsScreenshotClickGuidance() {
        #expect(!DescribeImageActor.prompt.lowercased().contains("red circle"))
    }

    @Test("activity summary prompt wraps screenshot summaries as XML")
    func activitySummaryPromptWrapsScreenshotSummariesAsXML() {
        let prompt = SummarizeActivityActor.summaryPrompt(
            for: ActivityActor.Activity(
                id: 1,
                application: "com.apple.dt.Xcode",
                startTime: Date(timeIntervalSince1970: 1_700_000_000),
                keystrokes: "",
                microphone: "",
                summary: nil,
                overviewID: nil,
                tagID: nil,
                screenshots: [
                    ActivityActor.Screenshot(
                        id: 2,
                        image: nil,
                        timestamp: Date(timeIntervalSince1970: 1_700_000_010),
                        description: "Editing <file>",
                        text: "let x = 1 && y > 0",
                        summary: "Reviewing <file> & tests",
                        ignoreReason: nil
                    )
                ]
            )
        )

        #expect(
            (
                prompt.contains("<summary>Reviewing &lt;file&gt; &amp; tests</summary>"),
                prompt.contains("<ocr>"),
                prompt.contains("<description>"),
                prompt.contains("<application>com.apple.dt.Xcode</application>")
            ) == (true, false, false, true)
        )
    }

    @Test("activity summary prompt clips oversized screenshot summaries before escaping them into XML")
    func activitySummaryPromptClipsOversizedScreenshotSummariesBeforeEscapingThemIntoXML() {
        let rawSummary = String(repeating: "a", count: 11_999) + "&dropped"
        let prompt = SummarizeActivityActor.summaryPrompt(
            for: ActivityActor.Activity(
                id: 1,
                application: "com.apple.dt.Xcode",
                startTime: Date(timeIntervalSince1970: 1_700_000_000),
                keystrokes: "",
                microphone: "",
                summary: nil,
                overviewID: nil,
                tagID: nil,
                screenshots: [
                    ActivityActor.Screenshot(
                        id: 2,
                        image: nil,
                        timestamp: Date(timeIntervalSince1970: 1_700_000_010),
                        description: "Editing <file>",
                        text: "let x = 1 && y > 0",
                        summary: rawSummary,
                        ignoreReason: nil
                    )
                ]
            )
        )
        let extractedSummary = {
            let start = prompt.range(of: "<summary>")!.upperBound
            let end = prompt.range(of: "</summary>")!.lowerBound
            return String(prompt[start..<end])
        }()

        #expect(extractedSummary == String(repeating: "a", count: 11_999) + "&amp;")
    }

    @Test("screenshot summary prompt wraps OCR and description as XML")
    func screenshotSummaryPromptWrapsOCRAndDescriptionAsXML() {
        let prompt = SummarizeScreenshotActor.summaryPrompt(
            description: "Editing <file>",
            text: "let x = 1 && y > 0"
        )

        #expect(
            prompt.contains("<description>Editing &lt;file&gt;</description>")
                && prompt.contains("<ocr>let x = 1 &amp;&amp; y &gt; 0</ocr>")
        )
    }

    @Test("screenshot summary output budget is eighty tokens")
    func screenshotSummaryOutputBudgetIsEightyTokens() {
        #expect(SummarizeScreenshotActor.maxOutputTokens == 80)
    }

    @Test("knowledge chunk graph output budget is six hundred tokens")
    func knowledgeChunkGraphOutputBudgetIsSixHundredTokens() {
        #expect(KnowledgeChunkGraphActor.maxOutputTokens == 600)
    }

    @Test("knowledge node coalesce output budget is eighty tokens")
    func knowledgeNodeCoalesceOutputBudgetIsEightyTokens() {
        #expect(CoalesceKnowledgeNodeActor.maxOutputTokens == 80)
    }

    @Test("knowledge edge coalesce output budget is eighty tokens")
    func knowledgeEdgeCoalesceOutputBudgetIsEightyTokens() {
        #expect(CoalesceKnowledgeEdgeActor.maxOutputTokens == 80)
    }

    @Test("overview merge output budget is one hundred twenty tokens")
    func overviewMergeOutputBudgetIsOneHundredTwentyTokens() {
        #expect(MergeOverviewsActor.maxOutputTokens == 120)
    }

    @Test("activity tag ontology summary output budget is one hundred sixty tokens")
    func activityTagOntologySummaryOutputBudgetIsOneHundredSixtyTokens() {
        #expect(ActivityTagOntologyActor.summaryMaxOutputTokens == 160)
    }

    @Test("ontology overview summary output budget is one hundred sixty tokens")
    func ontologyOverviewSummaryOutputBudgetIsOneHundredSixtyTokens() {
        #expect(OntologyOverviewActor.summaryMaxOutputTokens == 160)
    }

    @Test("normalized narration strips user lead-ins")
    func normalizedNarrationStripsUserLeadIns() {
        #expect(
            AITextUtilities.normalizedNarration("The user was implementing a TaskTrace migration in Xcode.")
                == "Implementing a TaskTrace migration in Xcode."
        )
    }

    @Test("normalized narration strips screenshot lead-ins")
    func normalizedNarrationStripsScreenshotLeadIns() {
        #expect(
            AITextUtilities.normalizedNarration("The screenshot shows a billing dashboard with open filters.")
                == "A billing dashboard with open filters."
        )
    }

    @Test("search summary prompt wraps the query and ranked results")
    func searchSummaryPromptWrapsTheQueryAndRankedResults() {
        let prompt = ActivityTextGenerationActor.searchSummaryPrompt(
            query: "tax filing",
            rankedDocuments: [
                "Reviewed tax forms for filing.",
                "Tax filing checklist on screen."
            ]
        )

        #expect(
            prompt.contains("<query>tax filing</query>")
                && prompt.contains(#"<result rank="1">"#)
                && prompt.contains("Reviewed tax forms for filing.")
                && prompt.contains(#"<result rank="2">"#)
                && prompt.contains("Tax filing checklist on screen.")
        )
    }

    @Test("overview merge request wraps both overviews and durations as XML")
    func overviewMergeRequestWrapsBothOverviewsAndDurationsAsXML() {
        let request = MergeOverviewsActor.request(
            firstOverview: ActivityOverviewMergeOption(
                title: "TaskTrace desktop development",
                summary: "Built desktop recording flows.",
                durationSeconds: 1800
            ),
            secondOverview: ActivityOverviewMergeOption(
                title: "TaskTrace analytics polish",
                summary: "Refined analytics and overview summaries.",
                durationSeconds: 900
            )
        )

        #expect(
            request.contains("<first_overview>")
                && request.contains("<second_overview>")
                && request.contains("<duration_seconds>1800</duration_seconds>")
                && request.contains("<duration_seconds>900</duration_seconds>")
                && request.contains("30 minutes")
        )
    }

    @Test("overview merge parser returns a merged payload")
    func overviewMergeParserReturnsAMergedPayload() {
        let decision = MergeOverviewsActor.parseDecision(
            "TITLE: TaskTrace product development\nSUMMARY: Built and refined TaskTrace desktop features across recording and analytics."
        )

        #expect(
            decision == ActivityOverviewMergeDecision(
                title: "TaskTrace product development",
                summary: "Built and refined TaskTrace desktop features across recording and analytics."
            )
        )
    }

    @Test("prefixedText prepends the prompt prefix when one is provided")
    func prefixedTextPrependsThePromptPrefix() {
        #expect(
            AITextUtilities.prefixedText(
                "capital of china",
                promptPrefix: "Instruct: Given a web search query, retrieve relevant passages that answer the query\nQuery:"
            ) == "Instruct: Given a web search query, retrieve relevant passages that answer the query\nQuery: capital of china"
        )
    }

    @Test("reranker prompt includes instruction query and document fields")
    func rerankerPromptIncludesInstructionQueryAndDocumentFields() {
        let prompt = ActivityRerankingActor.prompt(
            query: "What is the capital of China?",
            document: "Beijing is the capital of China.",
            instruction: Vars.retrievalInstruction
        )

        #expect(
            prompt.contains("<Instruct>: \(Vars.retrievalInstruction)")
                && prompt.contains("<Query>: What is the capital of China?")
                && prompt.contains("<Document>: Beijing is the capital of China.")
                && prompt.contains("answer can only be \"yes\" or \"no\"")
        )
    }
}

@MainActor @Suite(.serialized)
struct TextModelIntegrationTests {
    private static let textRuntime = AISchedulerModelRuntime(warmOnInit: false)

    @Test("text model responds to hi")
    func textModelRespondsToHi() async throws {
        let responses = try await Self.textRuntime.respond(
            prompts: ["Hi!"],
            instructions: "Reply with one short friendly greeting.",
            generateParameters: GenerateParameters(maxTokens: 12, temperature: 0),
            additionalContext: ["enable_thinking": false]
        )

        #expect((responses.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    @Test("text model responds to batched hi prompts")
    func textModelRespondsToBatchedHiPrompts() async throws {
        let responses = try await Self.textRuntime.respond(
            prompts: ["Hi!", "Hi!", "Hi!"],
            instructions: "Reply with one short friendly greeting.",
            generateParameters: GenerateParameters(maxTokens: 12, temperature: 0),
            additionalContext: ["enable_thinking": false]
        )

        #expect(
            responses.count == 3
                && responses.allSatisfy {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
        )
    }

    @Test("text model responds to mixed-length batched prompts")
    func textModelRespondsToMixedLengthBatchedPrompts() async throws {
        let responses = try await Self.textRuntime.respond(
            prompts: [
                "Hi!",
                "Reply with one short greeting for a desktop app that summarizes work."
            ],
            instructions: "Reply with one short friendly greeting.",
            generateParameters: GenerateParameters(maxTokens: 12, temperature: 0),
            additionalContext: ["enable_thinking": false]
        )

        #expect(
            responses.count == 2
                && responses.allSatisfy {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
        )
    }
}

@MainActor @Suite(.serialized)
struct ActivityAIIntegrationTests {
    private static let activityAI = IntegratedActivityAI()

    @Test("generateVectors ranks a similar sentence closer than an unrelated sentence")
    func generateVectorsRanksSimilarSentenceCloserThanUnrelatedSentence() async {
        let vectors = await Self.activityAI.generateVectors(
            for: [
                "The developer updated a Swift database migration in Xcode for TaskTrace.",
                "A Swift engineer changed the TaskTrace database migration while working in Xcode.",
                "The baker prepared sourdough bread in the kitchen before sunrise."
            ],
            promptPrefix: nil
        )

        let similarSimilarity = cosineSimilarity(vectors[0], vectors[1])
        let unrelatedSimilarity = cosineSimilarity(vectors[0], vectors[2])

        #expect(similarSimilarity > unrelatedSimilarity)
    }

    @Test("generateRerankings scores the relevant document above an unrelated document")
    func generateRerankingsScoresRelevantDocumentAboveUnrelatedDocument() async {
        let rankings = await Self.activityAI.generateRerankings(
            query: "Swift database migration work in TaskTrace",
            documents: [
                "The engineer implemented a new SQLite migration for the TaskTrace macOS app in Swift.",
                "The gardener watered tomato plants and trimmed basil on the patio."
            ],
            instruction: Vars.retrievalInstruction
        )

        let relevantScore = rankings.first { $0.documentIndex == 0 }?.score ?? -.infinity
        let unrelatedScore = rankings.first { $0.documentIndex == 1 }?.score ?? -.infinity

        #expect(relevantScore > unrelatedScore)
    }

    @Test("describeImage identifies the abacus illustration")
    func describeImageIdentifiesTheAbacusIllustration() async throws {
        let description = await Self.activityAI.describeImage(try fixtureData(named: "screenshot.webp"))
        print("abacus-test.webp description:", description)

        #expect(description.lowercased().contains("git"))
    }

    @Test("describeImage recognizes the book-cover scene")
    func describeImageRecognizesTheBookCoverScene() async throws {
        let description = await Self.activityAI.describeImage(try fixtureData(named: "book-cover.webp"))
        print("book-cover.webp description:", description)

        #expect(description.lowercased().contains("claire and penelope"))
    }

}

@MainActor private final class IntegratedActivityAI: ActivityAIOperating {
    private let describeImageActor: DescribeImageActor
    private let readScreenshotTextActor: ReadScreenshotTextActor
    private let summarizeScreenshotActor: SummarizeScreenshotActor
    private let summarizeActivityActor: SummarizeActivityActor
    private let mergeOverviewsActor: MergeOverviewsActor
    private let rerankingActor: ActivityRerankingActor
    private let textGenerationActor: ActivityTextGenerationActor

    init() {
        let actorSystem = ActorSystem()
        self.describeImageActor = DescribeImageActor(actorSystem: actorSystem)
        self.readScreenshotTextActor = ReadScreenshotTextActor(actorSystem: actorSystem)
        self.summarizeScreenshotActor = SummarizeScreenshotActor(actorSystem: actorSystem)
        self.summarizeActivityActor = SummarizeActivityActor(actorSystem: actorSystem)
        self.mergeOverviewsActor = MergeOverviewsActor(actorSystem: actorSystem)
        self.rerankingActor = ActivityRerankingActor()
        self.textGenerationActor = ActivityTextGenerationActor()
    }

    func describeImage(_ image: Data) async -> String {
        await describeImageActor.describeImage(image)
    }

    func ocrImage(_ image: Data) async -> String {
        await readScreenshotTextActor.ocrImage(image)
    }

    func summarizeScreenshot(description: String, text: String) async -> String {
        await summarizeScreenshotActor.summarizeScreenshot(description: description, text: text)
    }

    func summarizeActivity(_ activity: ActivityActor.Activity) async -> String {
        await summarizeActivityActor.summarizeActivity(activity)
    }

    func mergeOverviews(
        _ firstOverview: ActivityOverviewMergeOption,
        _ secondOverview: ActivityOverviewMergeOption
    ) async throws -> ActivityOverviewMergeDecision {
        try await mergeOverviewsActor.mergeOverviews(firstOverview, secondOverview)
    }

    func generateRerankings(
        query: String,
        documents: [String],
        instruction: String
    ) async -> [ActivityAIReranking] {
        await rerankingActor.generateRerankings(
            query: query,
            documents: documents,
            instruction: instruction
        )
    }

    func warmSearchSummaryModel(traceStartedAt: Date?) async {
        await textGenerationActor.warmSearchSummaryModel(traceStartedAt: traceStartedAt)
    }

    func streamResponse(
        prompt: String,
        instructions: String,
        generateParameters: GenerateParameters,
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        await textGenerationActor.streamResponse(
            prompt: prompt,
            instructions: instructions,
            generateParameters: generateParameters,
            traceStartedAt: traceStartedAt
        )
    }

    func searchSummary(
        query: String,
        rankedDocuments: [String],
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        await textGenerationActor.searchSummary(
            query: query,
            rankedDocuments: rankedDocuments,
            traceStartedAt: traceStartedAt
        )
    }

    func skillProcedure(
        prompt: String,
        instructions: String,
        traceStartedAt: Date?
    ) async -> AsyncThrowingStream<String, Error> {
        await textGenerationActor.skillProcedure(
            prompt: prompt,
            instructions: instructions,
            traceStartedAt: traceStartedAt
        )
    }

    func generateVectors(for texts: [String], promptPrefix: String?) async -> [[Float]] {
        await AISchedulerClient.shared.generateVectors(for: texts, promptPrefix: promptPrefix)
    }
}

private func fixtureData(named name: String) throws -> Data {
    let testDirectoryURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: testDirectoryURL.appendingPathComponent(name))
}

private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
    guard lhs.count == rhs.count, !lhs.isEmpty else {
        return -.infinity
    }

    let dot = zip(lhs, rhs).reduce(0 as Float) { partial, pair in
        partial + pair.0 * pair.1
    }
    let lhsMagnitude = Foundation.sqrt(lhs.reduce(0 as Float) { partial, value in
        partial + value * value
    })
    let rhsMagnitude = Foundation.sqrt(rhs.reduce(0 as Float) { partial, value in
        partial + value * value
    })
    let denominator = lhsMagnitude * rhsMagnitude

    guard denominator > 0 else {
        return -.infinity
    }

    return dot / denominator
}
