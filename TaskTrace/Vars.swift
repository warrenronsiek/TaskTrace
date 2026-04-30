//
//  Vars.swift
//  TaskTrace
//

import Foundation

enum Vars {
    nonisolated static let productionBundleIdentifier = "com.tasktrace.TaskTrace"
    nonisolated static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.tasktrace.TaskTrace.local"
    nonisolated static let keychainService = bundleIdentifier
    nonisolated static let visualModelId = "mlx-community/gemma-4-e2b-it-4bit"
    nonisolated static let textModelId = bigTextModelId
    nonisolated static let bigTextModelId = "mlx-community/Qwen3.5-4B-OptiQ-4bit"
    nonisolated static let smallTextModelId = "mlx-community/Qwen3.5-0.8B-OptiQ-4bit"
    nonisolated static let localModelsDirectoryName = "LocalModels"
    nonisolated static let visualModelDirectoryName = "gemma-4-e2b-it-4bit"
    nonisolated static let textModelDirectoryName = bigTextModelDirectoryName
    nonisolated static let bigTextModelDirectoryName = "Qwen3.5-4B-OptiQ-4bit"
    nonisolated static let smallTextModelDirectoryName = "Qwen3.5-0.8B-OptiQ-4bit"
    nonisolated static let embeddingModelDirectoryName = "Qwen3-Embedding-0.6B-4bit"
    nonisolated static let rerankerModelDirectoryName = "Qwen3-Reranker-0.6B-4bit"
    nonisolated static let retrievalInstruction =
        "Given a web search query, retrieve relevant passages that answer the query"
    nonisolated static let graphRAGRetrievalInstruction =
        "Given a knowledge-graph question, retrieve the graph entities and descriptions that best help answer the query"
    nonisolated static let graphRAGPerSourceCandidateLimit = 10
    nonisolated static let graphRAGHybridCandidateLimit = 30
    nonisolated static let graphRAGSummaryHitLimit = 5
    nonisolated static let graphRAGSummaryNodeLimit = 18
    nonisolated static let graphRAGSummaryEdgeLimit = 24
    nonisolated static let graphRAGSummaryClaimLimit = 24
    nonisolated static let skillContextHybridScoreFloor = 0.42
    nonisolated static let skillContextPromptCharacterLimit = 80_000
    nonisolated static let skillProcedureMaxTokens = 10_800
    nonisolated static let mcpStdioLaunchArgument = "--mcp-stdio"
    nonisolated static let mcpOverviewResourceURI = "tasktrace://overviews/active-day"
    nonisolated static let mcpHighLevelActivityResourceURI = "tasktrace://activities/high-level"
    nonisolated static let mcpDetailedActivityResourceURI = "tasktrace://activities/detailed"
    nonisolated static let mcpSearchToolName = "tasktrace_search"
    nonisolated static let mcpGraphRAGToolName = "tasktrace_graph_search"
    nonisolated static let mcpServerName = "tasktrace-mcp"
    nonisolated static let mcpServerTitle = "TaskTrace MCP Server"
    nonisolated static let browserPluginHostName = "com.tasktrace.browser_plugin"
    nonisolated static let browserPluginExtensionID = Bundle.main
        .object(forInfoDictionaryKey: "TaskTraceBrowserPluginExtensionID") as? String
        ?? "TASKTRACE_BROWSER_PLUGIN_EXTENSION_ID"
    nonisolated static let browserPluginSocketPath = "/tmp/tasktrace-browser-plugin.sock"
    nonisolated static let mcpActivityIdentifierPrefix = "act_"
    nonisolated static let mcpScreenshotMimeType = "image/webp"
    nonisolated static let mcpActivityScreenshotResourceTemplateURI = "tasktrace://activity/{activityId}/screenshot/{screenshotId}"
    nonisolated static let openClawChannelSocketPath = {
        let suffix = bundleIdentifier
            .replacingOccurrences(of: "com.tasktrace.", with: "")
            .replacingOccurrences(of: ".", with: "-")
            .lowercased()
        return "/tmp/tasktrace-\(suffix)-openclaw.sock"
    }()
    nonisolated static let mcpBrokerSocketPath = {
        let suffix = bundleIdentifier
            .replacingOccurrences(of: "com.tasktrace.", with: "")
            .replacingOccurrences(of: ".", with: "-")
            .lowercased()
        return "/tmp/tasktrace-\(suffix)-mcp.sock"
    }()
    nonisolated static let inactiveID: Int64 = 0
    nonisolated static let taggingFailureID: Int64 = 1
    nonisolated static let activityTagOntologyNeighborCount = 45
    nonisolated static let protectedIDs: Set<Int64> = [inactiveID, taggingFailureID]
    nonisolated static let inactiveName = "inactive"
    nonisolated static let inactiveDescription = "Computer went to sleep while TaskTrace was recording or TaskTrace was paused."
    nonisolated static let taggingFailureName = "tagging failure"
    nonisolated static let taggingFailureDescription = "TaskTrace could not confidently match this activity to any of your editable tags."

    nonisolated static func statsViewUsesConsumerText(forBundleIdentifier bundleIdentifier: String) -> Bool {
        bundleIdentifier == productionBundleIdentifier
    }

    nonisolated static func mcpActivityIdentifier(_ activityId: Int64) -> String {
        "\(mcpActivityIdentifierPrefix)\(activityId)"
    }

    nonisolated static func mcpActivityScreenshotResourceURI(
        activityId: Int64,
        screenshotId: Int64
    ) -> String {
        "tasktrace://activity/\(mcpActivityIdentifier(activityId))/screenshot/\(screenshotId)"
    }

    nonisolated static func localModelDirectory(
        named name: String,
        bundle: Bundle = .main
    ) -> URL? {
        let fileManager = FileManager.default
        let sourceTreeResources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AppResources", isDirectory: true)
        let resourceRoots = ([bundle.resourceURL, Bundle.main.resourceURL, sourceTreeResources]
            .compactMap { $0 })
            .reduce(into: [URL]()) { partialResult, url in
                if !partialResult.contains(where: { $0.path == url.path }) {
                    partialResult.append(url)
                }
            }

        let candidates = resourceRoots.flatMap { root in
            [
                root
                    .appendingPathComponent(localModelsDirectoryName, isDirectory: true)
                    .appendingPathComponent(name, isDirectory: true),
                root
                    .appendingPathComponent("AppResources", isDirectory: true)
                    .appendingPathComponent(localModelsDirectoryName, isDirectory: true)
                    .appendingPathComponent(name, isDirectory: true)
            ]
        }

        // Tests may load models directly from the checked-out source tree, while the app should
        // prefer the folder reference copied into the bundle resources.
        let requiredFiles = {
            switch name {
            case visualModelDirectoryName:
                [
                    "chat_template.jinja",
                    "config.json",
                    "model.safetensors",
                    "model.safetensors.index.json",
                    "processor_config.json",
                    "tokenizer.json",
                    "tokenizer_config.json"
                ]
            case bigTextModelDirectoryName, smallTextModelDirectoryName, embeddingModelDirectoryName, rerankerModelDirectoryName:
                ["config.json", "model.safetensors", "tokenizer.json"]
            default:
                ["config.json"]
            }
        }()

        return candidates.first { candidate in
            requiredFiles.allSatisfy { requiredFile in
                fileManager.fileExists(atPath: candidate.appendingPathComponent(requiredFile).path)
            }
        }
    }

    nonisolated static func embeddingModelDirectory(bundle: Bundle = .main) -> URL? {
        localModelDirectory(named: embeddingModelDirectoryName, bundle: bundle)
    }

    nonisolated static func textModelDirectory(bundle: Bundle = .main) -> URL? {
        bigTextModelDirectory(bundle: bundle)
    }

    nonisolated static func bigTextModelDirectory(bundle: Bundle = .main) -> URL? {
        localModelDirectory(named: bigTextModelDirectoryName, bundle: bundle)
    }

    nonisolated static func smallTextModelDirectory(bundle: Bundle = .main) -> URL? {
        localModelDirectory(named: smallTextModelDirectoryName, bundle: bundle)
    }

    nonisolated static func visualModelDirectory(bundle: Bundle = .main) -> URL? {
        localModelDirectory(named: visualModelDirectoryName, bundle: bundle)
    }

    nonisolated static func rerankerModelDirectory(bundle: Bundle = .main) -> URL? {
        localModelDirectory(named: rerankerModelDirectoryName, bundle: bundle)
    }

    nonisolated static func isProtected(_ tagID: Int64) -> Bool {
        protectedIDs.contains(tagID)
    }
}

typealias SystemTags = Vars
