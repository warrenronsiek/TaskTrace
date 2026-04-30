//
//  KnowledgeDirectory.swift
//  TaskTrace
//
//  Created by Codex on 4/3/26.
//

import Foundation
import GRDB

enum KnowledgeSourceSlot: String, Codable, CaseIterable, Hashable, Sendable {
    case obsidianVault = "obsidian_vault"
    case chatGPTHistory = "chatgpt_history"
    case taskTraceIngest = "tasktrace_ingest"

    nonisolated var title: String {
        switch self {
        case .obsidianVault:
            "Obsidian Vault"
        case .chatGPTHistory:
            "OpenAI Export"
        case .taskTraceIngest:
            "TaskTrace Browser Plugin"
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .obsidianVault:
            "Index a single Obsidian vault from disk."
        case .chatGPTHistory:
            "Import a ChatGPT/OpenAI export into the knowledge graph."
        case .taskTraceIngest:
            "Ingest captured Browser Plugin knowledge directly."
        }
    }

    nonisolated var addLabel: String {
        switch self {
        case .obsidianVault:
            "Add Vault"
        case .chatGPTHistory:
            "Add Export"
        case .taskTraceIngest:
            "Configure Browser Plugin"
        }
    }

    nonisolated var systemImageName: String {
        switch self {
        case .obsidianVault:
            "books.vertical"
        case .chatGPTHistory:
            "text.bubble"
        case .taskTraceIngest:
            "bolt.horizontal.circle"
        }
    }

    nonisolated var supportsFilesystemPicker: Bool {
        switch self {
        case .obsidianVault:
            true
        case .chatGPTHistory, .taskTraceIngest:
            false
        }
    }
}

struct KnowledgeDirectoryRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "knowledge_directories"

    let id: Int64
    let slot: KnowledgeSourceSlot
    let path: String
    let bookmarkData: Data?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case slot
        case path
        case bookmarkData = "bookmark_data"
        case createdAt = "created_at"
    }
}

struct KnowledgeDirectoryInput: Equatable, Sendable {
    let id: Int64
    let slot: KnowledgeSourceSlot
    let path: String
    let bookmarkData: Data?
    let createdAt: Date
}

struct KnowledgeFileRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "knowledge_files"

    let id: Int64
    let directoryID: Int64
    let path: String
    let title: String?
    let hash: String
    let modifiedAt: Date?
    let createDate: Date
    let lastAccessed: Date?
    let metadataJSON: String?
    let deletedAt: Date?
    let byteCount: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case directoryID = "directory_id"
        case path = "relative_path"
        case title
        case hash = "checksum"
        case modifiedAt = "mtime"
        case createDate = "create_date"
        case lastAccessed = "last_accessed"
        case metadataJSON = "metadata_json"
        case deletedAt = "deleted_at"
        case byteCount = "byte_count"
    }

    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

struct KnowledgeFileInput: Equatable, Sendable {
    let id: Int64
    let directoryID: Int64
    let path: String
    let title: String?
    let hash: String
    let modifiedAt: Date?
    let createDate: Date
    let lastAccessed: Date?
    let metadataJSON: String?
    let deletedAt: Date?
    let byteCount: Int64
}

struct KnowledgeAnchorRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "knowledge_anchors"

    let id: Int64
    let fileID: Int64
    let anchorType: String
    let anchorKey: String
    let headingText: String?
    let blockID: String?
    let startLine: Int
    let endLine: Int
    let textHash: String

    enum CodingKeys: String, CodingKey {
        case id
        case fileID = "file_id"
        case anchorType = "anchor_type"
        case anchorKey = "anchor_key"
        case headingText = "heading_text"
        case blockID = "block_id"
        case startLine = "start_line"
        case endLine = "end_line"
        case textHash = "text_hash"
    }
}

struct KnowledgeAnchorInput: Equatable, Sendable {
    let id: Int64
    let fileID: Int64
    let anchorType: String
    let anchorKey: String
    let headingText: String?
    let blockID: String?
    let startLine: Int
    let endLine: Int
    let textHash: String
}

struct KnowledgeChunkRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "knowledge_chunks"

    let id: Int64
    let anchorID: Int64
    let ordinal: Int
    let hash: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case id
        case anchorID = "anchor_id"
        case ordinal
        case hash
        case text
    }
}

struct KnowledgeChunkInput: Equatable, Sendable {
    let id: Int64
    let anchorID: Int64
    let ordinal: Int
    let hash: String
    let text: String
}

struct KnowledgeLinkRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "knowledge_links"

    let id: Int64
    let srcAnchorID: Int64
    let dstFileID: Int64?
    let dstAnchorHint: String?
    let linkText: String
    let linkType: String

    enum CodingKeys: String, CodingKey {
        case id
        case srcAnchorID = "src_anchor_id"
        case dstFileID = "dst_file_id"
        case dstAnchorHint = "dst_anchor_hint"
        case linkText = "link_text"
        case linkType = "link_type"
    }
}

struct KnowledgeLinkInput: Equatable, Sendable {
    let id: Int64
    let srcAnchorID: Int64
    let dstFileID: Int64?
    let dstAnchorHint: String?
    let linkText: String
    let linkType: String
}

struct KnowledgeAliasRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable {
    static let databaseTableName = "knowledge_aliases"

    let id: Int64
    let fileID: Int64
    let aliasText: String

    enum CodingKeys: String, CodingKey {
        case id
        case fileID = "file_id"
        case aliasText = "alias_text"
    }
}

struct KnowledgeAliasInput: Equatable, Sendable {
    let id: Int64
    let fileID: Int64
    let aliasText: String
}

nonisolated struct KnowledgeScannedChunk: Hashable, Sendable {
    let ordinal: Int
    let hash: String
    let text: String
}

nonisolated struct KnowledgeScannedAnchor: Hashable, Sendable {
    let anchorType: String
    let anchorKey: String
    let headingText: String?
    let blockID: String?
    let startLine: Int
    let endLine: Int
    let textHash: String
    let chunks: [KnowledgeScannedChunk]
}

nonisolated struct KnowledgeScannedLink: Hashable, Sendable {
    let srcAnchorKey: String
    let dstPathCandidate: String?
    let dstAnchorHint: String?
    let linkText: String
    let linkType: String
}

nonisolated struct KnowledgeScannedFile: Equatable, Sendable {
    let path: String
    let title: String?
    let hash: String
    let modifiedAt: Date?
    let metadataJSON: String?
    let byteCount: Int64
    let aliases: [String]
    let anchors: [KnowledgeScannedAnchor]
    let links: [KnowledgeScannedLink]
}

nonisolated struct KnowledgeFileIndexSummary: Equatable, Sendable {
    let aliases: [String]
    let anchors: [KnowledgeScannedAnchor]
    let links: [KnowledgeScannedLink]

    var chunkCount: Int {
        anchors.reduce(0) { $0 + $1.chunks.count }
    }
}

nonisolated struct KnowledgeFilePreview: Equatable, Sendable {
    let path: String
    let byteCount: Int64
    let content: String
    let isTruncated: Bool
}
