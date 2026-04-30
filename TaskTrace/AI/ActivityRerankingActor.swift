//
//  ActivityRerankingActor.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import OSLog

actor ActivityRerankingActor: Receiver, ActivityRerankingGenerating {
    private let rerankingGenerator: any ActivityRerankingGenerating
    let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "ai")

    init() {
        self.rerankingGenerator = AISchedulerClient.shared
    }

    func receive(_ envelope: Envelope) async {}

    func generateRerankings(
        query: String,
        documents: [String],
        instruction: String
    ) async -> [ActivityAIReranking] {
        await generateRerankings(
            query: query,
            documents: documents,
            instruction: instruction,
            source: "activity-reranking"
        )
    }

    func generateRerankings(
        query: String,
        documents: [String],
        instruction: String,
        source: String
    ) async -> [ActivityAIReranking] {
        await rerankingGenerator.generateRerankings(
            query: query,
            documents: documents,
            instruction: instruction,
            source: source
        )
    }

    nonisolated static func prompt(
        query: String,
        document: String,
        instruction: String
    ) -> String {
        """
        <|im_start|>system
        Judge whether the Document meets the requirements based on the Query and the Instruct provided. Note that the answer can only be "yes" or "no".<|im_end|>
        <|im_start|>user
        <Instruct>: \(instruction)
        <Query>: \(query)
        <Document>: \(document)<|im_end|>
        <|im_start|>assistant
        <think>

        </think>

        """
    }

    nonisolated static func score(
        promptTokens: [Int],
        model: any LanguageModel,
        yesTokenID: Int,
        noTokenID: Int
    ) -> Float {
        let cache = model.newCache(parameters: nil)
        var remaining = LMInput.Text(tokens: MLXArray(promptTokens))

        while remaining.tokens.size > 512 {
            _ = model(remaining[.newAxis, ..<512], cache: cache.isEmpty ? nil : cache, state: nil)
            eval(cache)
            remaining = remaining[512...]
        }

        let result = model(remaining[text: .newAxis], cache: cache.isEmpty ? nil : cache, state: nil)
        eval(result.logits)

        let lastTokenIndex = result.logits.dim(1) - 1
        let yesLogit = result.logits[0, lastTokenIndex, yesTokenID].item(Float.self)
        let noLogit = result.logits[0, lastTokenIndex, noTokenID].item(Float.self)
        let maxLogit = max(yesLogit, noLogit)
        let yesExp = Foundation.exp(Double(yesLogit - maxLogit))
        let noExp = Foundation.exp(Double(noLogit - maxLogit))
        let denominator = yesExp + noExp

        guard denominator > 0 else {
            return 0
        }

        return Float(yesExp / denominator)
    }
}
