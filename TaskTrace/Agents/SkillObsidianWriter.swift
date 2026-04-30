//
//  SkillObsidianWriter.swift
//  TaskTrace
//
//  Created by Codex on 4/21/26.
//

import Foundation

nonisolated struct SkillObsidianWriteTarget: Equatable, Sendable {
    let directory: KnowledgeDirectoryRecord
    let fileURL: URL
}

actor SkillObsidianWriter {
    private let knowledgeDatabaseActor: KnowledgeDatabaseActor
    private let fileManager: FileManager

    init(
        knowledgeDatabaseActor: KnowledgeDatabaseActor,
        fileManager: FileManager = .default
    ) {
        self.knowledgeDatabaseActor = knowledgeDatabaseActor
        self.fileManager = fileManager
    }

    func createTarget(
        query: String,
        createdAt: Date = Date()
    ) async throws -> SkillObsidianWriteTarget? {
        guard let directory = try await knowledgeDatabaseActor
            .loadKnowledgeDirectories()
            .first(where: { $0.slot == .obsidianVault })
        else {
            return nil
        }

        let directoryURL = try resolvedDirectoryURL(for: directory)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let timestamp = formatter.string(from: createdAt)
        let title = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let fileName = KnowledgeObsidianExportNaming.fileName(
            communityName: "\(timestamp) - \(title.isEmpty ? "Skill" : title)"
        )

        return SkillObsidianWriteTarget(
            directory: directory,
            fileURL: directoryURL
                .appendingPathComponent("TaskTrace", isDirectory: true)
                .appendingPathComponent("Skills", isDirectory: true)
                .appendingPathComponent(fileName)
        )
    }

    func write(
        markdown: String,
        target: SkillObsidianWriteTarget
    ) throws {
        let directoryURL = try resolvedDirectoryURL(for: target.directory)
        let startedAccessing = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccessing {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        let skillDirectoryURL = directoryURL
            .appendingPathComponent("TaskTrace", isDirectory: true)
            .appendingPathComponent("Skills", isDirectory: true)
        try fileManager.createDirectory(at: skillDirectoryURL, withIntermediateDirectories: true)
        try markdown.write(to: target.fileURL, atomically: true, encoding: .utf8)
    }

    private func resolvedDirectoryURL(for directory: KnowledgeDirectoryRecord) throws -> URL {
        if let bookmarkData = directory.bookmarkData {
            var isStale = false

            if let scopedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return scopedURL
            }

            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }

        return URL(fileURLWithPath: directory.path, isDirectory: true)
    }
}
