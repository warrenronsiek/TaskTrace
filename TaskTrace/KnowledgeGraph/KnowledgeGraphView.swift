//
//  KnowledgeGraphView.swift
//  TaskTrace
//
//  Created by Codex on 4/3/26.
//

import AppKit
import SwiftUI

private struct KnowledgeFileTreeNode: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let file: KnowledgeFileSystemEntry?
    let children: [KnowledgeFileTreeNode]

    nonisolated var isFolder: Bool {
        file == nil
    }
}

private struct KnowledgeFileTreeRow: Identifiable, Equatable {
    let id: String
    let node: KnowledgeFileTreeNode
    let depth: Int
}

struct KnowledgeGraphView: View {
    enum Mode: String, CaseIterable {
        case fileSystem = "FileSystem"
        case graph = "Graph"
    }

    @ObservedObject var knowledgeGraphStore: KnowledgeGraphStore
    let mode: Mode
    @State private var expandedFolderPaths = Set<String>()
    @State private var selectedAnchorKey: String?

    private var directoryBySlot: [KnowledgeSourceSlot: KnowledgeDirectoryRecord] {
        Dictionary(uniqueKeysWithValues: knowledgeGraphStore.directories.map { ($0.slot, $0) })
    }

    private var selectedFileEntry: KnowledgeFileSystemEntry? {
        knowledgeGraphStore.selectedFileID.flatMap { selectedFileID in
            knowledgeGraphStore.fileSystemEntries.first(where: { $0.id == selectedFileID })
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompactGraphLayout = proxy.size.width < 1180

            Group {
                if mode == .fileSystem {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if let errorMessage = knowledgeGraphStore.errorMessage {
                                Text(errorMessage)
                                    .font(Styles.Fonts.footnote)
                                    .foregroundStyle(AppColors.danger)
                            }

                            HStack(alignment: .top, spacing: 20) {
                                knowledgeSourcesColumn
                                    .frame(width: 280)

                                fileColumn
                                    .frame(width: 420)

                                previewColumn
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 1480)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        if let errorMessage = knowledgeGraphStore.errorMessage {
                            Text(errorMessage)
                                .font(Styles.Fonts.footnote)
                                .foregroundStyle(AppColors.danger)
                        }

                        HStack(alignment: .top, spacing: 20) {
                            graphControlsColumn
                                .frame(width: 360)
                                .frame(maxHeight: .infinity)

                            graphColumn(showsOuterChrome: !isCompactGraphLayout)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(24)
                    .frame(maxWidth: 1480)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Knowledge")
        .task {
            await knowledgeGraphStore.load()
        }
        .onChange(of: selectedFileEntry?.treePath) { _, newTreePath in
            guard let newTreePath else {
                return
            }

            expandedFolderPaths.formUnion(Self.folderAncestors(for: newTreePath))
        }
        .onChange(of: knowledgeGraphStore.selectedFileIndex) { _, newIndex in
            let currentAnchorStillExists = newIndex?.anchors.contains(where: {
                $0.anchorKey == selectedAnchorKey
            }) == true

            if !currentAnchorStillExists {
                selectedAnchorKey = newIndex?.anchors.first?.anchorKey
            }
        }
    }

    private var knowledgeSourcesColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Knowledge Sources")
                .font(Styles.Fonts.title3Semibold)

            Text("Obsidian imports from a picked vault. TaskTrace Browser Plugin is managed automatically from the browser plugin capture directory.")
                .font(Styles.Fonts.footnote)
                .foregroundStyle(AppColors.textSecondary)

            ForEach(KnowledgeSourceSlot.allCases, id: \.self) { slot in
                let directory = directoryBySlot[slot]

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppColors.chipBackground.opacity(0.7))
                                .frame(width: 38, height: 38)

                            Image(systemName: slot.systemImageName)
                                .foregroundStyle(AppColors.accent)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(slot.title)
                                .font(Styles.Fonts.subheadlineSemibold)
                                .foregroundStyle(AppColors.textPrimary)

                            Text(slot.subtitle)
                                .font(Styles.Fonts.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let directory {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(URL(fileURLWithPath: directory.path).lastPathComponent)
                                .font(Styles.Fonts.subheadlineSemibold)
                                .foregroundStyle(AppColors.textPrimary)

                            Text(directory.path)
                                .font(Styles.Fonts.footnoteMonospaced)
                                .foregroundStyle(AppColors.textSecondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)

                            Button(role: .destructive) {
                                Task {
                                    await knowledgeGraphStore.removeSource(slot: slot)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "trash")
                                        .foregroundStyle(AppColors.danger)

                                    Text("Remove Source")
                                        .font(Styles.Fonts.subheadlineSemibold)
                                        .foregroundStyle(AppColors.textPrimary)

                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AppColors.danger.opacity(0.12))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } else if slot.supportsFilesystemPicker {
                        Button {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Add Vault"

                            if panel.runModal() == .OK, let url = panel.url {
                                Task {
                                    await knowledgeGraphStore.connectObsidianVault(url: url)
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(AppColors.accent)

                                Text(slot.addLabel)
                                    .font(Styles.Fonts.subheadlineSemibold)
                                    .foregroundStyle(AppColors.textPrimary)

                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppColors.insetBackground)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Coming soon.")
                            .font(Styles.Fonts.footnoteMonospaced)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppColors.insetBackground)
                            )
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppColors.insetBackground)
                )
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(glassCard)
    }

    private var fileColumn: some View {
        let rows = Self.flattenedFileTree(
            from: Self.fileTree(for: knowledgeGraphStore.fileSystemEntries),
            expandedFolderPaths: expandedFolderPaths
        )

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Files")
                    .font(Styles.Fonts.title3Semibold)

                if knowledgeGraphStore.isBuilding {
                    Text("Rebuilding knowledge graph…")
                        .font(Styles.Fonts.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if rows.isEmpty {
                        Text("Add a knowledge source to index files here.")
                            .font(Styles.Fonts.footnote)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(rows) { row in
                            if row.node.isFolder {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        if expandedFolderPaths.contains(row.node.path) {
                                            expandedFolderPaths.remove(row.node.path)
                                        } else {
                                            expandedFolderPaths.insert(row.node.path)
                                        }
                                    }
                                } label: {
                                    let isExpanded = expandedFolderPaths.contains(row.node.path)

                                    HStack(spacing: 10) {
                                        HStack(spacing: 10) {
                                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(AppColors.textSecondary.opacity(0.75))
                                                .frame(width: 12)

                                            ZStack {
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .fill(AppColors.chipBackground.opacity(0.7))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                            .stroke(AppColors.accent.opacity(0.18), lineWidth: 1)
                                                    )
                                                    .frame(width: 28, height: 28)

                                                Image(systemName: isExpanded ? "folder.fill" : "folder")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(AppColors.accent)
                                            }

                                            Text(row.node.name)
                                                .font(Styles.Fonts.subheadlineSemibold)
                                                .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.vertical, 9)
                                        .padding(.horizontal, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(Color.clear)
                                        )
                                    }
                                    .padding(.leading, CGFloat(row.depth) * 16)
                                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            } else if let file = row.node.file {
                                HStack(alignment: .top, spacing: 10) {
                                    Button {
                                        Task {
                                            await knowledgeGraphStore.selectFile(id: file.id)
                                        }
                                    } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: "doc.text")
                                                .foregroundStyle(AppColors.textSecondary)

                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                                    Text(file.title ?? file.name)
                                                        .font(Styles.Fonts.subheadlineSemibold)
                                                        .foregroundStyle(AppColors.textPrimary)
                                                        .frame(maxWidth: .infinity, alignment: .leading)

                                                    Text(file.statusLabel)
                                                        .font(Styles.Fonts.footnoteMonospaced)
                                                        .foregroundStyle(file.isComplete ? AppColors.textSecondary : AppColors.accent)
                                                }

                                                GeometryReader { proxy in
                                                    ZStack(alignment: .leading) {
                                                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                                                            .fill(Color.white.opacity(0.08))

                                                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                                                            .fill(file.isComplete ? AppColors.textSecondary.opacity(0.35) : AppColors.accent.opacity(0.7))
                                                            .frame(width: max(proxy.size.width * file.progressFraction, file.progressFraction > 0 ? 8 : 0))
                                                    }
                                                }
                                                .frame(height: 6)

                                                if !file.isComplete {
                                                    Text("\(file.pendingChunkGraphs) graph · \(file.pendingNodeEmbeddings) embed")
                                                        .font(Styles.Fonts.footnote)
                                                        .foregroundStyle(AppColors.textSecondary)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                        .padding(.leading, CGFloat(row.depth) * 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(knowledgeGraphStore.selectedFileID == file.id ? AppColors.chipBackground : Color.clear)
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    if file.sourceSlot == .taskTraceIngest {
                                        Button(role: .destructive) {
                                            Task {
                                                await knowledgeGraphStore.deleteFile(id: file.id)
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(AppColors.danger)
                                                .font(.system(size: 12, weight: .semibold))
                                                .padding(4)
                                                .background(
                                                    Circle()
                                                        .fill(AppColors.danger.opacity(0.18))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .help("Delete from TaskTrace Browser Plugin")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 12)
                .animation(.easeInOut(duration: 0.18), value: expandedFolderPaths)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(glassCard)
    }

    private var previewColumn: some View {
        let selectedAnchor = {
            guard let selectedFileIndex = knowledgeGraphStore.selectedFileIndex else {
                return nil as KnowledgeScannedAnchor?
            }

            return selectedFileIndex.anchors.first(where: {
                $0.anchorKey == selectedAnchorKey
            }) ?? selectedFileIndex.anchors.first
        }()

        return VStack(alignment: .leading, spacing: 14) {
            Text("Index")
                .font(Styles.Fonts.title3Semibold)

            if let selectedFile = selectedFileEntry {
                VStack(alignment: .leading, spacing: 10) {
                    Text(selectedFile.title ?? selectedFile.name)
                        .font(Styles.Fonts.subheadlineSemibold)

                    Text(selectedFile.sourceSlot.title)
                        .font(Styles.Fonts.footnoteMonospaced)
                        .foregroundStyle(AppColors.accent)

                    Text(selectedFile.path)
                        .font(Styles.Fonts.footnoteMonospaced)
                        .foregroundStyle(AppColors.textSecondary)
                        .textSelection(.enabled)

                    if let selectedFileIndex = knowledgeGraphStore.selectedFileIndex {
                        HStack(spacing: 12) {
                            indexMetric(label: "Aliases", value: selectedFileIndex.aliases.count)
                            indexMetric(label: "Anchors", value: selectedFileIndex.anchors.count)
                            indexMetric(label: "Chunks", value: selectedFileIndex.chunkCount)
                            indexMetric(label: "Links", value: selectedFileIndex.links.count)
                        }

                        if !selectedFileIndex.aliases.isEmpty {
                            Text(selectedFileIndex.aliases.joined(separator: " · "))
                                .font(Styles.Fonts.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if knowledgeGraphStore.isSelectedFileLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(AppColors.textPrimary)

                            Text("Loading file index…")
                                .font(Styles.Fonts.subheadlineSemibold)
                                .foregroundStyle(AppColors.textPrimary)

                            Text("Reading anchors, chunks, and links for the selected file.")
                                .font(Styles.Fonts.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                    } else if let selectedFileIndex = knowledgeGraphStore.selectedFileIndex,
                       !selectedFileIndex.anchors.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Anchors")
                                .font(Styles.Fonts.subheadlineSemibold)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(selectedFileIndex.anchors.enumerated()), id: \.offset) { pair in
                                        let anchor = pair.element

                                        Button {
                                            selectedAnchorKey = anchor.anchorKey
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(anchor.headingText ?? anchor.anchorKey)
                                                    .font(Styles.Fonts.footnoteMonospaced)
                                                    .foregroundStyle(AppColors.textPrimary)

                                                Text("\(anchor.chunks.count) chunks")
                                                    .font(Styles.Fonts.footnote)
                                                    .foregroundStyle(AppColors.textSecondary)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill((selectedAnchor?.anchorKey ?? selectedFileIndex.anchors.first?.anchorKey) == anchor.anchorKey ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if let selectedAnchor {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(selectedAnchor.headingText ?? selectedAnchor.anchorKey)
                                        .font(Styles.Fonts.subheadlineSemibold)
                                        .foregroundStyle(AppColors.textPrimary)

                                    Text("\(selectedAnchor.anchorType) · lines \(selectedAnchor.startLine)-\(selectedAnchor.endLine)")
                                        .font(Styles.Fonts.footnote)
                                        .foregroundStyle(AppColors.textSecondary)

                                    Text(selectedAnchor.chunks.map(\.text).joined(separator: "\n\n"))
                                        .font(Styles.Fonts.bodyMonospaced)
                                        .foregroundStyle(AppColors.textPrimary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(Color.white.opacity(0.06))
                                        )
                                }
                            }
                        }
                    } else if knowledgeGraphStore.selectedFileID != nil {
                        Text("No anchors available for this file yet.")
                            .font(Styles.Fonts.footnote)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Select a file to inspect its anchors.")
                            .font(Styles.Fonts.footnote)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(glassCard)
    }

    private func graphColumn(showsOuterChrome: Bool) -> some View {
        let payload = Self.knowledgeGraphPayload(
            fileSystemEntries: knowledgeGraphStore.fileSystemEntries,
            graphSnapshot: knowledgeGraphStore.graphSnapshot,
            selectedNodeID: knowledgeGraphStore.selectedGraphNodeID,
            graphRAGRetrieval: knowledgeGraphStore.graphRAGRetrieval,
            communityLinks: knowledgeGraphStore.knowledgeCommunityLinks,
            bridgeLinks: knowledgeGraphStore.knowledgeBridgeLinks,
            claims: knowledgeGraphStore.selectedNodeClaims
        )
        let overlayLinks = Self.graphOverlayLinks(
            graphSnapshot: knowledgeGraphStore.graphSnapshot,
            communityLinks: knowledgeGraphStore.knowledgeCommunityLinks,
            activityLinks: knowledgeGraphStore.knowledgeActivityLinks,
            overviewLinks: knowledgeGraphStore.knowledgeOverviewLinks
        )
        let (showsBusyBadge, busyBadgeTitle, busyBadgeSubtitle) = {
            let hasFileWork = knowledgeGraphStore.graphBuildProgress.totalChunks > 0
                && knowledgeGraphStore.graphBuildProgress.processedChunks < knowledgeGraphStore.graphBuildProgress.totalChunks
            let hasActivityWork = knowledgeGraphStore.graphBuildProgress.totalActivities > 0
                && knowledgeGraphStore.graphBuildProgress.processedActivities < knowledgeGraphStore.graphBuildProgress.totalActivities

            if knowledgeGraphStore.isGraphLoading {
                return (true, "Loading graph…", "Reading graph data from the database.")
            }

            if hasFileWork || hasActivityWork {
                return (true, "Updating graph…", "Knowledge processing is still in progress.")
            }

            return (false, "", "")
        }()

        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if knowledgeGraphStore.isGraphLoading,
                   payload.nodes.isEmpty {
                    VStack(spacing: 10) {
                        Text("Loading graph…")
                            .font(Styles.Fonts.subheadlineSemibold)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("Reading knowledge graph data from the database.")
                            .font(Styles.Fonts.footnote)
                            .foregroundStyle(AppColors.textSecondary)
                        }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppColors.insetBackground)
                    )
                } else if payload.nodes.isEmpty {
                    Text("No linked knowledge is available yet.")
                    .font(Styles.Fonts.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppColors.insetBackground)
                    )
                } else {
                    TaskTraceWebView(
                        payload: .knowledgeGraph(payload),
                        overlayLinks: overlayLinks,
                        onNodeSelection: { nodeID in
                            Task {
                                await knowledgeGraphStore.selectGraphNode(id: nodeID)
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppColors.insetBackground)
                    )
                }
            }

            .overlay(alignment: .topLeading) {
                if showsBusyBadge {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColors.textPrimary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(busyBadgeTitle)
                                .font(Styles.Fonts.footnoteMonospaced)
                                .foregroundStyle(AppColors.textPrimary)

                            Text(busyBadgeSubtitle)
                                .font(Styles.Fonts.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.32))
                    )
                    .padding(16)
                }
            }
        }
        .padding(showsOuterChrome ? 20 : 0)
        .background(
            Group {
                if showsOuterChrome {
                    glassCard
                }
            }
        )
    }

    private var graphControlsColumn: some View {
        let taskTraceIngestFiles = knowledgeGraphStore.fileSystemEntries.filter {
            $0.sourceSlot == .taskTraceIngest
        }
        let taskTraceIngestReadyCount = taskTraceIngestFiles.filter(\.isComplete).count
        let taskTraceIngestFraction = taskTraceIngestFiles.isEmpty
            ? 0.0
            : taskTraceIngestFiles.reduce(0.0) { $0 + $1.progressFraction } / Double(taskTraceIngestFiles.count)
        let taskTraceIngestLabel = "\(taskTraceIngestReadyCount)/\(taskTraceIngestFiles.count) ready"

        return VStack(alignment: .leading, spacing: 18) {
            Text("Graph Controls")
                .font(Styles.Fonts.title3Semibold)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Progress")
                        .font(Styles.Fonts.subheadlineSemibold)

                    graphProgressMetric(
                        title: "Files to Knowledge",
                        detail: knowledgeGraphStore.graphBuildProgress.filesLabel,
                        fraction: knowledgeGraphStore.graphBuildProgress.fileFraction,
                        tint: AppColors.accent
                    )

                    graphProgressMetric(
                        title: "Activities to Knowledge",
                        detail: knowledgeGraphStore.graphBuildProgress.activitiesLabel,
                        fraction: knowledgeGraphStore.graphBuildProgress.activityFraction,
                        tint: AppColors.recordIdle
                    )

                    graphProgressMetric(
                        title: "TaskTrace Browser Plugin",
                        detail: taskTraceIngestLabel,
                        fraction: taskTraceIngestFraction,
                        tint: AppColors.accent
                    )
                }

                Divider()
                    .overlay(Color.white.opacity(0.08))

                Button {
                    Task {
                        await knowledgeGraphStore.rebuildSourceKnowledge(slot: .obsidianVault)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(AppColors.danger)
                        Text("Rebuild Obsidian Knowledge")
                            .font(Styles.Fonts.subheadlineSemibold)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppColors.danger.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColors.danger.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await knowledgeGraphStore.rebuildSourceKnowledge(slot: .taskTraceIngest)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(AppColors.danger)
                        Text("Rebuild Plugin Knowledge")
                            .font(Styles.Fonts.subheadlineSemibold)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppColors.danger.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColors.danger.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await knowledgeGraphStore.rebuildActivityKnowledge()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(AppColors.recordActive)
                        Text("Rebuild Activity Knowledge")
                            .font(Styles.Fonts.subheadlineSemibold)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppColors.recordActive.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColors.recordActive.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )

            VStack(alignment: .leading, spacing: 14) {
                Text("Graph Search")
                    .font(Styles.Fonts.subheadlineSemibold)

                if let graphRAGErrorMessage = knowledgeGraphStore.graphRAGErrorMessage {
                    Text(graphRAGErrorMessage)
                        .font(Styles.Fonts.footnote)
                        .foregroundStyle(AppColors.danger)
                }

                TextField("Ask the graph about these knowledge sources…", text: $knowledgeGraphStore.graphRAGQuery, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Styles.Fonts.footnote)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                Button {
                    Task {
                        await knowledgeGraphStore.runGraphRAG()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: knowledgeGraphStore.isGraphRAGSearching || knowledgeGraphStore.isGraphRAGSummarizing ? "waveform.path.ecg" : "sparkles")
                            .foregroundStyle(AppColors.accent)
                        Text(knowledgeGraphStore.isGraphRAGSearching ? "Searching…" : knowledgeGraphStore.isGraphRAGSummarizing ? "Summarizing…" : "Ask")
                            .font(Styles.Fonts.subheadlineSemibold)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppColors.accent.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColors.accent.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary")
                        .font(Styles.Fonts.footnoteMonospaced)
                        .foregroundStyle(AppColors.textSecondary)

                    ScrollView {
                        Text(
                            knowledgeGraphStore.graphRAGSummaryText
                            ?? (knowledgeGraphStore.isGraphRAGSearching || knowledgeGraphStore.isGraphRAGSummarizing
                                ? "Building graph answer…"
                                : "Run a graph search to synthesize matching communities, nodes, claims, and internal edges.")
                        )
                        .font(Styles.Fonts.footnote)
                        .foregroundStyle(
                            knowledgeGraphStore.graphRAGSummaryText == nil
                            ? AppColors.textSecondary
                            : AppColors.textPrimary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    }
                    .frame(minHeight: 180, maxHeight: 280)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(glassCard)
    }

    private func indexMetric(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(Styles.Fonts.subheadlineSemibold)
                .foregroundStyle(AppColors.textPrimary)

            Text(label)
                .font(Styles.Fonts.footnote)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func graphProgressMetric(
        title: String,
        detail: String,
        fraction: Double,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(Styles.Fonts.footnote)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer(minLength: 0)

                Text(detail)
                    .font(Styles.Fonts.footnoteMonospaced)
                    .foregroundStyle(AppColors.textSecondary)
            }

            GeometryReader { proxy in
                let clampedFraction = max(0, min(fraction, 1))
                let barWidth = clampedFraction > 0 ? max(proxy.size.width * clampedFraction, 10) : 0 as CGFloat

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(tint.opacity(0.8))
                        .frame(width: barWidth)
                }
            }
            .frame(height: 12)
        }
    }

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    private nonisolated static func folderAncestors(for path: String) -> Set<String> {
        let components = path.split(separator: "/").map(String.init)

        return Set(
            components.dropLast().indices.map {
                components.prefix($0 + 1).joined(separator: "/")
            }
        )
    }

    private nonisolated static func fileTree(for files: [KnowledgeFileSystemEntry]) -> [KnowledgeFileTreeNode] {
        final class Builder {
            let name: String
            let path: String
            var file: KnowledgeFileSystemEntry?
            var children: [String: Builder]

            init(name: String, path: String, file: KnowledgeFileSystemEntry? = nil, children: [String: Builder] = [:]) {
                self.name = name
                self.path = path
                self.file = file
                self.children = children
            }
        }

        func materialize(_ builder: Builder) -> KnowledgeFileTreeNode {
            let children = builder.children.values
                .map(materialize)
                .sorted {
                    if $0.isFolder != $1.isFolder {
                        return $0.isFolder && !$1.isFolder
                    }

                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }

            return KnowledgeFileTreeNode(
                id: builder.path,
                name: builder.name,
                path: builder.path,
                file: builder.file,
                children: children
            )
        }

        return KnowledgeSourceSlot.allCases.compactMap { slot in
            let slotFiles = files.filter { $0.sourceSlot == slot }

            guard !slotFiles.isEmpty else {
                return nil
            }

            let root = Builder(name: slot.title, path: slot.rawValue)

            slotFiles.forEach { file in
                let components = file.path.split(separator: "/").map(String.init)
                var current = root

                components.indices.forEach { index in
                    let component = components[index]
                    let path = "\(slot.rawValue)/" + components.prefix(index + 1).joined(separator: "/")
                    let isLeaf = index == components.count - 1

                    if let existing = current.children[component] {
                        if isLeaf {
                            existing.file = file
                        }
                        current = existing
                    } else {
                        let node = Builder(name: component, path: path, file: isLeaf ? file : nil)
                        current.children[component] = node
                        current = node
                    }
                }
            }

            return materialize(root)
        }
    }

    private nonisolated static func flattenedFileTree(
        from nodes: [KnowledgeFileTreeNode],
        expandedFolderPaths: Set<String>
    ) -> [KnowledgeFileTreeRow] {
        func flatten(_ nodes: [KnowledgeFileTreeNode], _ depth: Int) -> [KnowledgeFileTreeRow] {
            nodes.flatMap { node in
                let row = KnowledgeFileTreeRow(id: node.path, node: node, depth: depth)

                if node.isFolder, expandedFolderPaths.contains(node.path) {
                    return [row] + flatten(node.children, depth + 1)
                }

                return [row]
            }
        }

        return flatten(nodes, 0)
    }

    nonisolated static func knowledgeGraphPayload(
        fileSystemEntries: [KnowledgeFileSystemEntry],
        graphSnapshot: KnowledgeGraphDirectorySnapshot,
        selectedNodeID: String?,
        graphRAGRetrieval: GraphRAGRetrievalResult?,
        communityLinks: [KnowledgeCommunityLinkRecord],
        bridgeLinks: [KnowledgeBridgeLinkRecord],
        claims: [KnowledgeClaimRecord]
    ) -> TaskTraceKnowledgeGraphRenderPayload {
        let fileNodeIDByID = Dictionary(uniqueKeysWithValues: fileSystemEntries.map { ($0.id, "knowledge-file:\($0.id)") })
        let knowledgeNodeIDByID = Dictionary(uniqueKeysWithValues: graphSnapshot.knowledgeNodes.map { ($0.id, "knowledge-node:\($0.id)") })
        let overviewNodeIDByID = Dictionary(uniqueKeysWithValues: graphSnapshot.overviews.map { ($0.id, "knowledge-overview:\($0.id)") })
        let activityNodeIDByID = Dictionary(uniqueKeysWithValues: graphSnapshot.activities.map { ($0.id, "knowledge-activity:\($0.id)") })
        let visibleCommunities = graphSnapshot.communities.filter {
            !($0.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        let communityNodeIDByID = Dictionary(uniqueKeysWithValues: visibleCommunities.map { ($0.id, "knowledge-community:\($0.id)") })
        let searchHitRankByNodeID = (graphRAGRetrieval?.hits ?? []).enumerated().reduce(into: [String: Int]()) { partial, pair in
            let rank = pair.offset
            let hit = pair.element
            let nodeID: String? = switch hit.entityType {
            case .community:
                communityNodeIDByID[hit.entityID]
            case .node:
                knowledgeNodeIDByID[hit.entityID]
            case .claim:
                hit.nodeID.flatMap { knowledgeNodeIDByID[$0] }
            }

            guard let nodeID else {
                return
            }

            partial[nodeID] = min(partial[nodeID] ?? rank, rank)
        }
        let fileLinks = graphSnapshot.fileLinks.compactMap { link -> TaskTraceKnowledgeGraphLink? in
            guard let sourceID = fileNodeIDByID[link.sourceFileID],
                  let targetID = fileNodeIDByID[link.targetFileID] else {
                return nil
            }

            return TaskTraceKnowledgeGraphLink(
                sourceID: sourceID,
                targetID: targetID,
                kind: "file",
                weight: link.weight
            )
        }
        let fileKnowledgeLinks = bridgeLinks.compactMap { link -> TaskTraceKnowledgeGraphLink? in
            guard let sourceID = fileNodeIDByID[link.fileID],
                  let targetID = knowledgeNodeIDByID[link.nodeID] else {
                return nil
            }

            return TaskTraceKnowledgeGraphLink(
                sourceID: sourceID,
                targetID: targetID,
                kind: "file-knowledge",
                weight: 1
            )
        }
        let communityKnowledgeLinks = communityLinks.compactMap { link -> TaskTraceKnowledgeGraphLink? in
            guard let sourceID = communityNodeIDByID[link.communityID],
                  let targetID = knowledgeNodeIDByID[link.nodeID] else {
                return nil
            }

            return TaskTraceKnowledgeGraphLink(
                sourceID: sourceID,
                targetID: targetID,
                kind: "community",
                weight: 1
            )
        }
        let searchHitKnowledgeNodeIDs = Set(searchHitRankByNodeID.keys.filter { $0.hasPrefix("knowledge-node:") })
        let searchHitCommunityNodeIDs = Set(searchHitRankByNodeID.keys.filter { $0.hasPrefix("knowledge-community:") })
        let visibleFilePaths = Set(fileSystemEntries.map(\.path))
        let directlyVisibleKnowledgeNodeIDs = Set(
            graphSnapshot.knowledgeNodes.compactMap { node -> String? in
                guard let nodeID = knowledgeNodeIDByID[node.id] else {
                    return nil
                }

                let isBackedByVisibleFile = node.sourcePath.map(visibleFilePaths.contains) ?? false
                let isAttachedToVisibleCommunity = node.communityID.flatMap { communityNodeIDByID[$0] } != nil
                let isAttachedToSelectedFile = fileKnowledgeLinks.contains { $0.targetID == nodeID }
                let isAttachedToSelectedCommunity = communityKnowledgeLinks.contains { $0.targetID == nodeID }

                return isBackedByVisibleFile || isAttachedToVisibleCommunity || isAttachedToSelectedFile || isAttachedToSelectedCommunity
                    ? nodeID
                    : nil
            }
        )
        let knowledgeLinks = graphSnapshot.knowledgeEdges.compactMap { edge -> TaskTraceKnowledgeGraphLink? in
            guard let sourceID = knowledgeNodeIDByID[edge.firstNodeID],
                  let targetID = knowledgeNodeIDByID[edge.secondNodeID] else {
                return nil
            }

            return TaskTraceKnowledgeGraphLink(
                sourceID: sourceID,
                targetID: targetID,
                kind: "knowledge",
                weight: 1
            )
        }
        let visibleKnowledgeNodeIDs = {
            let adjacency = knowledgeLinks.reduce(into: [String: Set<String>]()) { partial, link in
                partial[link.sourceID, default: []].insert(link.targetID)
                partial[link.targetID, default: []].insert(link.sourceID)
            }
            var visited = directlyVisibleKnowledgeNodeIDs.union(searchHitKnowledgeNodeIDs)
            var frontier = Array(visited)

            while let nodeID = frontier.popLast() {
                let newNeighbors = (adjacency[nodeID] ?? []).subtracting(visited)
                visited.formUnion(newNeighbors)
                frontier.append(contentsOf: newNeighbors)
            }

            return visited
        }()
        let filteredKnowledgeLinks = knowledgeLinks.filter {
            visibleKnowledgeNodeIDs.contains($0.sourceID)
                && visibleKnowledgeNodeIDs.contains($0.targetID)
        }
        let filteredFileKnowledgeLinks = fileKnowledgeLinks.filter {
            visibleKnowledgeNodeIDs.contains($0.targetID)
        }
        let filteredCommunityKnowledgeLinks = communityKnowledgeLinks.filter {
            visibleKnowledgeNodeIDs.contains($0.targetID)
        }
        let visibleCommunityNodeIDs = Set(
            graphSnapshot.knowledgeNodes.compactMap { node -> String? in
                guard let communityID = node.communityID,
                      let nodeID = knowledgeNodeIDByID[node.id],
                      visibleKnowledgeNodeIDs.contains(nodeID) else {
                    return nil
                }

                return communityNodeIDByID[communityID]
            }
            + filteredCommunityKnowledgeLinks.map(\.sourceID)
            + Array(searchHitCommunityNodeIDs)
        )
        let overviewActivityLinks = graphSnapshot.activities.compactMap { activity -> TaskTraceKnowledgeGraphLink? in
            guard let overviewID = activity.overviewID,
                  let sourceID = overviewNodeIDByID[overviewID],
                  let targetID = activityNodeIDByID[activity.id] else {
                return nil
            }

            return TaskTraceKnowledgeGraphLink(
                sourceID: sourceID,
                targetID: targetID,
                kind: "overview-activity",
                weight: 1
            )
        }
        let claimNodes: [TaskTraceKnowledgeGraphNode] = claims.compactMap { claim in
            guard let parentID = knowledgeNodeIDByID[claim.nodeID] else {
                return nil
            }
            guard visibleKnowledgeNodeIDs.contains(parentID) else {
                return nil
            }

            return TaskTraceKnowledgeGraphNode(
                id: "knowledge-claim:\(claim.id)",
                label: claim.text.count > 60 ? String(claim.text.prefix(59)) + "…" : claim.text,
                detail: claim.text,
                nodeType: "claim",
                layer: 2,
                communityID: nil,
                kind: "claim",
                sourcePath: nil,
                linkCount: 1,
                searchHitRank: nil,
                parentNodeID: parentID
            )
        }
        let claimLinks: [TaskTraceKnowledgeGraphLink] = claims.compactMap { claim in
            guard let parentID = knowledgeNodeIDByID[claim.nodeID] else {
                return nil
            }
            guard visibleKnowledgeNodeIDs.contains(parentID) else {
                return nil
            }

            return TaskTraceKnowledgeGraphLink(
                sourceID: parentID,
                targetID: "knowledge-claim:\(claim.id)",
                kind: "claim",
                weight: 1
            )
        }
        let allLinks = fileLinks + filteredFileKnowledgeLinks + filteredCommunityKnowledgeLinks + filteredKnowledgeLinks + overviewActivityLinks + claimLinks
        let linkCountByNodeID = allLinks.reduce(into: [String: Int]()) { partial, link in
            partial[link.sourceID, default: 0] += link.weight
            partial[link.targetID, default: 0] += link.weight
        }

        return TaskTraceKnowledgeGraphRenderPayload(
            graphID: "knowledge-all-sources",
            nodes: fileSystemEntries.map { file in
                let nodeID = fileNodeIDByID[file.id] ?? "knowledge-file:\(file.id)"

                return TaskTraceKnowledgeGraphNode(
                    id: nodeID,
                    label: file.title ?? file.name,
                    detail: "\(file.sourceSlot.title) · \(file.path)",
                    nodeType: "file",
                    layer: file.sourceSlot == .taskTraceIngest ? 4 : 0,
                    communityID: nil,
                    kind: "file",
                    sourcePath: file.path,
                    linkCount: linkCountByNodeID[nodeID, default: 0],
                    searchHitRank: searchHitRankByNodeID[nodeID]
                )
            } + graphSnapshot.overviews.map { overview in
                let nodeID = overviewNodeIDByID[overview.id] ?? "knowledge-overview:\(overview.id)"

                return TaskTraceKnowledgeGraphNode(
                    id: nodeID,
                    label: overview.title,
                    detail: overview.summary ?? "",
                    nodeType: "overview",
                    layer: 1,
                    communityID: nil,
                    kind: "overview",
                    sourcePath: nil,
                    linkCount: linkCountByNodeID[nodeID, default: 0],
                    searchHitRank: searchHitRankByNodeID[nodeID]
                )
            } + graphSnapshot.activities.map { activity in
                let nodeID = activityNodeIDByID[activity.id] ?? "knowledge-activity:\(activity.id)"
                let application = activity.application.trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = activity.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                return TaskTraceKnowledgeGraphNode(
                    id: nodeID,
                    label: application.isEmpty ? "Activity \(activity.id)" : application,
                    detail: summary.isEmpty ? application : summary,
                    nodeType: "activity",
                    layer: 1,
                    communityID: nil,
                    kind: "activity",
                    sourcePath: nil,
                    linkCount: linkCountByNodeID[nodeID, default: 0],
                    searchHitRank: searchHitRankByNodeID[nodeID],
                    parentNodeID: activity.overviewID.flatMap { overviewNodeIDByID[$0] }
                )
            } + graphSnapshot.knowledgeNodes.compactMap { node -> TaskTraceKnowledgeGraphNode? in
                guard let nodeID = knowledgeNodeIDByID[node.id] else {
                    return nil
                }
                guard visibleKnowledgeNodeIDs.contains(nodeID) else {
                    return nil
                }

                return TaskTraceKnowledgeGraphNode(
                    id: nodeID,
                    label: node.name,
                    detail: node.description ?? "",
                    nodeType: "knowledge",
                    layer: 2,
                    communityID: node.communityID.map(String.init),
                    kind: node.kind,
                    sourcePath: node.sourcePath,
                    linkCount: linkCountByNodeID[nodeID, default: 0],
                    searchHitRank: searchHitRankByNodeID[nodeID]
                )
            } + visibleCommunities.compactMap { community -> TaskTraceKnowledgeGraphNode? in
                let nodeID = communityNodeIDByID[community.id] ?? "knowledge-community:\(community.id)"
                guard visibleCommunityNodeIDs.contains(nodeID) else {
                    return nil
                }
                let name = community.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let summary = community.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                return TaskTraceKnowledgeGraphNode(
                    id: nodeID,
                    label: name.isEmpty ? "Community \(community.id)" : name,
                    detail: summary,
                    nodeType: "community",
                    layer: 2,
                    communityID: String(community.id),
                    kind: "community",
                    sourcePath: nil,
                    linkCount: linkCountByNodeID[nodeID, default: 0],
                    searchHitRank: searchHitRankByNodeID[nodeID]
                )
            } + claimNodes,
            links: allLinks,
            selectedNodeID: selectedNodeID
        )
    }

    nonisolated static func graphOverlayLinks(
        graphSnapshot: KnowledgeGraphDirectorySnapshot,
        communityLinks _: [KnowledgeCommunityLinkRecord],
        activityLinks: [KnowledgeActivityLinkRecord],
        overviewLinks: [KnowledgeOverviewLinkRecord]
    ) -> [TaskTraceKnowledgeGraphLink] {
        let knowledgeNodeIDByID = Dictionary(
            uniqueKeysWithValues: graphSnapshot.knowledgeNodes.map { ($0.id, "knowledge-node:\($0.id)") }
        )
        let overviewNodeIDByID = Dictionary(
            uniqueKeysWithValues: graphSnapshot.overviews.map { ($0.id, "knowledge-overview:\($0.id)") }
        )
        let activityNodeIDByID = Dictionary(
            uniqueKeysWithValues: graphSnapshot.activities.map { ($0.id, "knowledge-activity:\($0.id)") }
        )
        return activityLinks.compactMap { link in
            guard let sourceID = activityNodeIDByID[link.activityID],
                  let targetID = knowledgeNodeIDByID[link.nodeID] else {
                return nil
            }

            return TaskTraceKnowledgeGraphLink(
                sourceID: sourceID,
                targetID: targetID,
                kind: "activity-knowledge",
                weight: 1
            )
        } + overviewLinks.compactMap { link in
            guard let sourceID = overviewNodeIDByID[link.overviewID],
                  let targetID = knowledgeNodeIDByID[link.nodeID] else {
                return nil
            }

            return TaskTraceKnowledgeGraphLink(
                sourceID: sourceID,
                targetID: targetID,
                kind: "overview-knowledge",
                weight: 1
            )
        }
    }
}
