//
//  TaskTraceWebView.swift
//  TaskTrace
//
//  Created by Codex on 4/7/26.
//

import Foundation
import WebKit
import SwiftUI

nonisolated struct TaskTraceKnowledgeGraphNode: Encodable, Sendable {
    let id: String
    let label: String
    let detail: String
    let nodeType: String
    let layer: Int
    let communityID: String?
    let kind: String?
    let sourcePath: String?
    let linkCount: Int
    let searchHitRank: Int?
    let parentNodeID: String?

    init(
        id: String,
        label: String,
        detail: String,
        nodeType: String,
        layer: Int,
        communityID: String?,
        kind: String?,
        sourcePath: String?,
        linkCount: Int,
        searchHitRank: Int? = nil,
        parentNodeID: String? = nil
    ) {
        self.id = id
        self.label = label
        self.detail = detail
        self.nodeType = nodeType
        self.layer = layer
        self.communityID = communityID
        self.kind = kind
        self.sourcePath = sourcePath
        self.linkCount = linkCount
        self.searchHitRank = searchHitRank
        self.parentNodeID = parentNodeID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case detail
        case nodeType
        case layer
        case communityID = "communityId"
        case kind
        case sourcePath
        case linkCount
        case searchHitRank
        case parentNodeID = "parentNodeId"
    }
}

nonisolated struct TaskTraceKnowledgeGraphLink: Encodable, Sendable {
    let sourceID: String
    let targetID: String
    let kind: String
    let weight: Int

    enum CodingKeys: String, CodingKey {
        case sourceID = "sourceId"
        case targetID = "targetId"
        case kind
        case weight
    }
}

nonisolated struct TaskTraceKnowledgeGraphRenderPayload: Encodable, Sendable {
    let graphID: String
    let nodes: [TaskTraceKnowledgeGraphNode]
    let links: [TaskTraceKnowledgeGraphLink]
    let selectedNodeID: String?

    enum CodingKeys: String, CodingKey {
        case graphID = "graphId"
        case nodes
        case links
        case selectedNodeID = "selectedNodeId"
    }
}

enum TaskTraceWebViewPayload {
    case searchResults([SearchResultTree])
    case knowledgeGraph(TaskTraceKnowledgeGraphRenderPayload)

    fileprivate func encodedJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let encodedData: Data? = switch self {
        case .searchResults(let results):
            try? encoder.encode(TaskTraceSearchWebPayload(results: results))
        case .knowledgeGraph(let graph):
            try? encoder.encode(TaskTraceKnowledgeWebPayload(graph: graph))
        }

        return encodedData.flatMap { String(data: $0, encoding: .utf8) }
    }
}

struct TaskTraceWebView: NSViewRepresentable {
    let payload: TaskTraceWebViewPayload
    var overlayLinks: [TaskTraceKnowledgeGraphLink] = []
    var onNodeSelection: (@MainActor @Sendable (String?) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onNodeSelection: onNodeSelection)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "taskTraceGraphSelection")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        let distURL = Bundle.main.resourceURL?.appending(path: "dist", directoryHint: .isDirectory)
        let indexURL = distURL?.appending(path: "index.html")

        if
            let distURL,
            let indexURL,
            FileManager.default.fileExists(atPath: indexURL.path())
        {
            webView.loadFileURL(indexURL, allowingReadAccessTo: distURL)
        } else {
            webView.loadHTMLString(
                """
                <html>
                  <body style="font-family: -apple-system; padding: 24px;">
                    TaskTraceWebView bundle not found at \(indexURL?.path() ?? "unknown path").
                  </body>
                </html>
                """,
                baseURL: nil
            )
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onNodeSelection = onNodeSelection

        if let payloadJSON = payload.encodedJSON(),
           payloadJSON != context.coordinator.lastRenderedPayloadJSON {
            context.coordinator.pendingPayloadJSON = payloadJSON
            context.coordinator.lastRenderedPayloadJSON = payloadJSON
            context.coordinator.renderIfPossible()
        }

        let overlayJSON = Self.encodeOverlayLinks(overlayLinks)
        if overlayJSON != context.coordinator.lastOverlayJSON {
            context.coordinator.lastOverlayJSON = overlayJSON
            context.coordinator.sendOverlayLinks(overlayJSON)
        }
    }

    private static func encodeOverlayLinks(_ links: [TaskTraceKnowledgeGraphLink]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(links) else {
            return "[]"
        }

        return String(data: data, encoding: .utf8) ?? "[]"
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var pendingPayloadJSON: String?
        var lastRenderedPayloadJSON: String?
        var lastOverlayJSON: String?
        var onNodeSelection: (@MainActor @Sendable (String?) -> Void)?
        private var hasFinishedNavigation = false

        init(onNodeSelection: (@MainActor @Sendable (String?) -> Void)?) {
            self.onNodeSelection = onNodeSelection
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            hasFinishedNavigation = true
            renderIfPossible()
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "taskTraceGraphSelection" else {
                return
            }

            let nodeID = (message.body as? [String: Any])?["nodeId"] as? String

            Task { @MainActor in
                self.onNodeSelection?(nodeID)
            }
        }

        func renderIfPossible() {
            guard
                hasFinishedNavigation,
                let webView,
                let pendingPayloadJSON
            else {
                return
            }

            webView.evaluateJavaScript(
                "window.TaskTraceWebView && window.TaskTraceWebView.render(\(pendingPayloadJSON));"
            )
            self.pendingPayloadJSON = nil

            if let overlayJSON = lastOverlayJSON {
                sendOverlayLinks(overlayJSON)
            }
        }

        func sendOverlayLinks(_ json: String) {
            guard hasFinishedNavigation, let webView else {
                return
            }

            webView.evaluateJavaScript(
                "window.TaskTraceWebView && window.TaskTraceWebView.updateOverlayLinks(\(json));"
            )
        }
    }
}

private struct TaskTraceSearchWebPayload: Encodable {
    let kind = "search-results-graph"
    let results: [SearchResultTree]
}

private struct TaskTraceKnowledgeWebPayload: Encodable {
    let kind = "knowledge-graph"
    let graph: TaskTraceKnowledgeGraphRenderPayload
}
