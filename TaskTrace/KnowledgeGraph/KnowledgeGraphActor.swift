//
//  KnowledgeGraphActor.swift
//  TaskTrace
//
//  Created by Codex on 4/3/26.
//

import CryptoKit
import Foundation
import Markdown
import OSLog

actor KnowledgeGraphActor: Receiver {
    struct State: Equatable, Sendable {
        var revision: Int64
        var directories: [KnowledgeDirectoryRecord]
        var selectedDirectoryID: Int64?
        var activeBuildID: Int64?
        var lastCompletedBuildID: Int64?
        var isBuilding: Bool
        var dataRevision: Int64
        var selectedFilePath: String?
        var selectedFilePreview: KnowledgeFilePreview?
        var errorMessage: String?

        init(
            revision: Int64 = 0,
            directories: [KnowledgeDirectoryRecord] = [],
            selectedDirectoryID: Int64? = nil,
            activeBuildID: Int64? = nil,
            lastCompletedBuildID: Int64? = nil,
            isBuilding: Bool = false,
            dataRevision: Int64 = 0,
            selectedFilePath: String? = nil,
            selectedFilePreview: KnowledgeFilePreview? = nil,
            errorMessage: String? = nil
        ) {
            self.revision = revision
            self.directories = directories
            self.selectedDirectoryID = selectedDirectoryID
            self.activeBuildID = activeBuildID
            self.lastCompletedBuildID = lastCompletedBuildID
            self.isBuilding = isBuilding
            self.dataRevision = dataRevision
            self.selectedFilePath = selectedFilePath
            self.selectedFilePreview = selectedFilePreview
            self.errorMessage = errorMessage
        }
    }

    struct ScanStateCounts: Equatable, Sendable {
        let pendingScannedFiles: Int
        let aliasTargets: Int
        let fileReferences: Int
        let anchorReferences: Int

        static let empty = ScanStateCounts(
            pendingScannedFiles: 0,
            aliasTargets: 0,
            fileReferences: 0,
            anchorReferences: 0
        )
    }

    private struct IndexedFileReference: Hashable, Sendable {
        let directoryID: Int64
        let path: String
    }

    private let activityDatabaseActor: ActivityDatabaseActor
    private let knowledgeDatabaseActor: KnowledgeDatabaseActor
    private let actorSystem: ActorSystem
    private let identifierActor: IdentifierActor
    private let maxPreviewByteCount: Int
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "knowledge")

    private var directories: [KnowledgeDirectoryRecord]
    private var selectedDirectoryID: Int64?
    private var selectedFilePath: String?
    private var selectedFilePreview: KnowledgeFilePreview?
    private var errorMessage: String?
    private var revision: Int64
    private var activeBuildID: Int64?
    private var lastCompletedBuildID: Int64?
    private var isBuilding: Bool
    private var dataRevision: Int64
    private var continuations: [UUID: AsyncStream<State>.Continuation]
    private var pendingScannedFilesByReference: [IndexedFileReference: KnowledgeScannedFile]
    private var aliasTargetFileIDByLookupKey: [String: Int64]
    private var fileReferenceByID: [Int64: IndexedFileReference]
    private var anchorReferenceByID: [Int64: (fileReference: IndexedFileReference, anchorKey: String)]

    init(
        activityDatabaseActor: ActivityDatabaseActor,
        knowledgeDatabaseActor: KnowledgeDatabaseActor,
        actorSystem: ActorSystem,
        identifierActor: IdentifierActor = .shared,
        maxPreviewByteCount: Int = 200_000,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.activityDatabaseActor = activityDatabaseActor
        self.knowledgeDatabaseActor = knowledgeDatabaseActor
        self.actorSystem = actorSystem
        self.identifierActor = identifierActor
        self.maxPreviewByteCount = maxPreviewByteCount
        self.now = now
        self.directories = []
        self.selectedDirectoryID = nil
        self.selectedFilePath = nil
        self.selectedFilePreview = nil
        self.errorMessage = nil
        self.revision = 0
        self.activeBuildID = nil
        self.lastCompletedBuildID = nil
        self.isBuilding = false
        self.dataRevision = 0
        self.continuations = [:]
        self.pendingScannedFilesByReference = [:]
        self.aliasTargetFileIDByLookupKey = [:]
        self.fileReferenceByID = [:]
        self.anchorReferenceByID = [:]
    }

    func updates() -> AsyncStream<State> {
        let id = UUID()

        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(snapshot())
            continuation.onTermination = { _ in
                Task {
                    await self.removeContinuation(id)
                }
            }
        }
    }

    func snapshot() -> State {
        State(
            revision: revision,
            directories: directories,
            selectedDirectoryID: selectedDirectoryID,
            activeBuildID: activeBuildID,
            lastCompletedBuildID: lastCompletedBuildID,
            isBuilding: isBuilding,
            dataRevision: dataRevision,
            selectedFilePath: selectedFilePath,
            selectedFilePreview: selectedFilePreview,
            errorMessage: errorMessage
        )
    }

    func scanStateCountsForTesting() -> ScanStateCounts {
        ScanStateCounts(
            pendingScannedFiles: pendingScannedFilesByReference.count,
            aliasTargets: aliasTargetFileIDByLookupKey.count,
            fileReferences: fileReferenceByID.count,
            anchorReferences: anchorReferenceByID.count
        )
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as KnowledgeLoadRequested:
            logger.log(
                "knowledge-actor received knowledge-load-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activeDay=\(event.activeDay.formatted(TaskTraceDatabase.sqlTimestampStyle), privacy: .public)"
            )

            do {
                directories = try await knowledgeDatabaseActor
                    .loadKnowledgeDirectories()
                    .sorted { $0.slot.rawValue < $1.slot.rawValue }
                selectedDirectoryID = nil
                errorMessage = nil
                selectedFilePath = nil
                selectedFilePreview = nil
                clearScanState()
                await identifierActor.observeExisting(directories.map(\.id).max())
                broadcast()

                for directoryID in directories.map(\.id) {
                    await actorSystem.broadcast(
                        from: nil,
                        message: KnowledgeDirectorySyncRequested(directoryID: directoryID)
                    )
                }

                try await replayActivityKnowledge(for: event.activeDay)
            } catch {
                errorMessage = "Could not load knowledge directories."
                broadcast()
            }
        case let event as KnowledgeBuildStarted:
            logger.log(
                "knowledge-actor received knowledge-build-started sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) buildID=\(event.buildID, privacy: .public) directoryID=\(event.directoryID, privacy: .public)"
            )
            activeBuildID = event.buildID
            isBuilding = true
            errorMessage = nil
            broadcast()
        case let event as KnowledgeBuildCompleted:
            logger.log(
                "knowledge-actor received knowledge-build-completed sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) buildID=\(event.buildID, privacy: .public) directoryID=\(event.directoryID, privacy: .public)"
            )
            if activeBuildID == event.buildID {
                activeBuildID = nil
                isBuilding = false
            }
            lastCompletedBuildID = event.buildID
            broadcast()
        case let event as KnowledgeBuildFailed:
            logger.log(
                "knowledge-actor received knowledge-build-failed sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) buildID=\(event.buildID, privacy: .public) directoryID=\(event.directoryID, privacy: .public)"
            )
            if activeBuildID == event.buildID {
                activeBuildID = nil
                isBuilding = false
                errorMessage = event.errorMessage
            }
            broadcast()
        case let event as KnowledgeGraphProjectionLoadRequested:
            logger.log(
                "knowledge-actor received knowledge-graph-projection-load-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) directoryID=\(String(describing: event.directoryID), privacy: .public)"
            )
            dataRevision += 1
            broadcast()
        case let event as KnowledgeDirectoryCreated:
            logger.log(
                "knowledge-actor received knowledge-directory-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) directoryID=\(event.directory.id, privacy: .public)"
            )
            directories = (directories + [event.directory])
                .reduce(into: [KnowledgeSourceSlot: KnowledgeDirectoryRecord]()) { partial, directory in
                    partial[directory.slot] = directory
                }
                .values
                .sorted { $0.slot.rawValue < $1.slot.rawValue }
            selectedDirectoryID = nil
            clearScanState()
            errorMessage = nil
            broadcast()
            await actorSystem.broadcast(
                from: nil,
                message: KnowledgeDirectorySyncRequested(directoryID: event.directory.id)
            )
        case let event as KnowledgeDirectoryDeleted:
            logger.log(
                "knowledge-actor received knowledge-directory-deleted sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) directoryID=\(event.directoryID, privacy: .public)"
            )
            directories.removeAll { $0.id == event.directoryID }
            selectedDirectoryID = nil
            selectedFilePath = nil
            selectedFilePreview = nil
            clearScanState()
            errorMessage = nil
            broadcast()
        case let event as RebuildKnowledge:
            logger.log(
                "knowledge-actor received rebuild-knowledge sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) directoryID=\(event.directoryID, privacy: .public)"
            )

            clearScanState()
            errorMessage = nil
            broadcast()
        case let event as ReplayActivityKnowledge:
            logger.log(
                "knowledge-actor received replay-activity-knowledge sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activeDay=\(event.activeDay.formatted(TaskTraceDatabase.sqlTimestampStyle), privacy: .public)"
            )

            do {
                try await replayActivityKnowledge(for: event.activeDay)
            } catch {
                logger.error(
                    "knowledge-actor failed event=replay-activity-knowledge activeDay=\(event.activeDay.formatted(TaskTraceDatabase.sqlTimestampStyle), privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ActivityKnowledgeEncoded:
            guard event.success else {
                return
            }

            logger.log(
                "knowledge-actor received activity-knowledge-encoded sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public)"
            )
            dataRevision += 1
            broadcast()
        case let event as KnowledgeDirectorySyncRequested:
            logger.log(
                "knowledge-actor received knowledge-directory-sync-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) directoryID=\(event.directoryID, privacy: .public)"
            )

            guard let directory = directories.first(where: { $0.id == event.directoryID }) else {
                return
            }

            selectedDirectoryID = nil
            clearScanState()
            fileReferenceByID = Dictionary(
                uniqueKeysWithValues: (try? await knowledgeDatabaseActor.loadKnowledgeFiles(
                    directoryID: event.directoryID,
                    includingDeleted: false
                ))?.map {
                    (
                        $0.id,
                        IndexedFileReference(directoryID: event.directoryID, path: $0.path)
                    )
                } ?? []
            )
            errorMessage = nil
            dataRevision += 1
            broadcast()

            let buildID = await identifierActor.makeIdentifier()
            do {
                defer { clearScanState() }

                await actorSystem.broadcast(
                    from: nil,
                    message: KnowledgeBuildStarted(
                        buildID: buildID,
                        directoryID: event.directoryID
                    )
                )
                let existingFiles = try await knowledgeDatabaseActor.loadKnowledgeFiles(
                    directoryID: event.directoryID,
                    includingDeleted: true
                )
                await identifierActor.observeExisting(existingFiles.map(\.id).max())
                let existingFilesByPath = Dictionary(uniqueKeysWithValues: existingFiles.map { ($0.path, $0) })
                var liveIndexedFileIDs = Set<Int64>()
                let retainingPaths = try await scanDirectory(directory) { [self] scannedFile in
                    let existingFile = existingFilesByPath[scannedFile.path]
                    let fileID = if let existingFile {
                        existingFile.id
                    } else {
                        await self.identifierActor.makeIdentifier()
                    }
                    self.pendingScannedFilesByReference[
                        IndexedFileReference(directoryID: event.directoryID, path: scannedFile.path)
                    ] = scannedFile
                    let aliasValues = scannedFile.aliases + [scannedFile.path, URL(fileURLWithPath: scannedFile.path).deletingPathExtension().lastPathComponent] + (scannedFile.title.map { [$0] } ?? [])
                    aliasValues.forEach { alias in
                        self.aliasTargetFileIDByLookupKey[Self.normalizedLookupKey(alias)] = fileID
                    }

                    guard existingFile == nil
                            || existingFile?.deletedAt != nil
                            || existingFile?.hash != scannedFile.hash else {
                        return
                    }

                    liveIndexedFileIDs.insert(fileID)

                    await self.actorSystem.broadcast(
                        from: nil,
                        message: KnowledgeFileCreated(
                            buildID: buildID,
                            directoryID: event.directoryID,
                            file: KnowledgeFileInput(
                                id: fileID,
                                directoryID: event.directoryID,
                                path: scannedFile.path,
                                title: scannedFile.title,
                                hash: scannedFile.hash,
                                modifiedAt: scannedFile.modifiedAt,
                                createDate: existingFile?.createDate ?? self.now(),
                                lastAccessed: existingFile?.lastAccessed,
                                metadataJSON: scannedFile.metadataJSON,
                                deletedAt: nil,
                                byteCount: scannedFile.byteCount
                            )
                        )
                    )
                }

                await actorSystem.broadcast(
                    from: nil,
                    message: KnowledgeDirectoryScanCompleted(
                        buildID: buildID,
                        directoryID: event.directoryID,
                        retainingPaths: retainingPaths,
                        deletedAt: now()
                    )
                )

                var lastChunkID: Int64?
                while true {
                    let chunkRequests = try await knowledgeDatabaseActor.loadUnprocessedKnowledgeChunkRequests(
                        directoryID: event.directoryID,
                        buildID: buildID,
                        afterChunkID: lastChunkID,
                        limit: 200
                    )

                    guard !chunkRequests.isEmpty else {
                        break
                    }

                    lastChunkID = chunkRequests.last?.chunk.id
                    for chunkRequest in chunkRequests {
                        guard liveIndexedFileIDs.contains(chunkRequest.fileID) == false else {
                            continue
                        }

                        await actorSystem.broadcast(
                            from: nil,
                            message: chunkRequest
                        )
                    }
                }
            } catch {
                await actorSystem.broadcast(
                    from: nil,
                    message: KnowledgeBuildFailed(
                        buildID: buildID,
                        directoryID: event.directoryID,
                        errorMessage: "Could not index the selected knowledge source."
                    )
                )
                errorMessage = "Could not index the selected knowledge source."
                selectedFilePath = nil
                selectedFilePreview = nil
                broadcast()
            }
        case let event as KnowledgeFileCreated:
            logger.log(
                "knowledge-actor received knowledge-file-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.file.id, privacy: .public) path=\(event.file.path, privacy: .public)"
            )

            let fileReference = IndexedFileReference(directoryID: event.directoryID, path: event.file.path)
            fileReferenceByID[event.file.id] = fileReference
            errorMessage = nil
            broadcast()

            guard let scannedFile = pendingScannedFilesByReference.removeValue(forKey: fileReference) else {
                await actorSystem.broadcast(
                    from: nil,
                    message: KnowledgeFileIndexed(
                        buildID: event.buildID,
                        fileID: event.file.id
                    )
                )
                return
            }

            await actorSystem.broadcast(
                from: nil,
                message: KnowledgeFileIndexReset(fileID: event.file.id)
            )

            for alias in scannedFile.aliases {
                await actorSystem.broadcast(
                    from: nil,
                    message: KnowledgeAliasCreated(
                        fileID: event.file.id,
                        alias: KnowledgeAliasInput(
                            id: await identifierActor.makeIdentifier(),
                            fileID: event.file.id,
                            aliasText: alias
                        )
                    )
                )
            }

            var anchorIDByKey: [String: Int64] = [:]
            for scannedAnchor in scannedFile.anchors {
                let anchorID = await identifierActor.makeIdentifier()
                anchorIDByKey[scannedAnchor.anchorKey] = anchorID
                await actorSystem.broadcast(
                    from: nil,
                    message: KnowledgeAnchorCreated(
                        buildID: event.buildID,
                        fileID: event.file.id,
                        anchor: KnowledgeAnchorInput(
                            id: anchorID,
                            fileID: event.file.id,
                            anchorType: scannedAnchor.anchorType,
                            anchorKey: scannedAnchor.anchorKey,
                            headingText: scannedAnchor.headingText,
                            blockID: scannedAnchor.blockID,
                            startLine: scannedAnchor.startLine,
                            endLine: scannedAnchor.endLine,
                            textHash: scannedAnchor.textHash
                        ),
                        scannedAnchor: scannedAnchor
                    )
                )
            }

            for link in scannedFile.links {
                guard let srcAnchorID = anchorIDByKey[link.srcAnchorKey] else {
                    continue
                }

                let resolvedFileID: Int64? = {
                    guard let dstPathCandidate = link.dstPathCandidate else {
                        return nil
                    }

                    let normalizedDestination = Self.normalizedLookupKey(dstPathCandidate)

                    return aliasTargetFileIDByLookupKey[normalizedDestination]
                        ?? aliasTargetFileIDByLookupKey[Self.normalizedLookupKey(URL(fileURLWithPath: dstPathCandidate).deletingPathExtension().lastPathComponent)]
                        ?? aliasTargetFileIDByLookupKey["\(normalizedDestination).md"]
                        ?? aliasTargetFileIDByLookupKey["\(normalizedDestination).markdown"]
                }()

                await actorSystem.broadcast(
                    from: nil,
                    message: KnowledgeLinkCreated(
                        fileID: event.file.id,
                        link: KnowledgeLinkInput(
                            id: await identifierActor.makeIdentifier(),
                            srcAnchorID: srcAnchorID,
                            dstFileID: resolvedFileID,
                            dstAnchorHint: link.dstAnchorHint,
                            linkText: link.linkText,
                            linkType: link.linkType
                        ),
                        scannedLink: link
                    )
                )
            }

            await actorSystem.broadcast(
                from: nil,
                message: KnowledgeFileIndexed(
                    buildID: event.buildID,
                    fileID: event.file.id
                )
            )
        case let event as KnowledgeFileIndexReset:
            logger.log(
                "knowledge-actor received knowledge-file-index-reset sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.fileID, privacy: .public)"
            )
            if let fileReference = fileReferenceByID[event.fileID] {
                anchorReferenceByID = anchorReferenceByID.filter { $0.value.fileReference != fileReference }
            }
        case let event as KnowledgeAliasCreated:
            logger.log(
                "knowledge-actor received knowledge-alias-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.fileID, privacy: .public) aliasID=\(event.alias.id, privacy: .public)"
            )
        case let event as KnowledgeAnchorCreated:
            logger.log(
                "knowledge-actor received knowledge-anchor-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.fileID, privacy: .public) anchorID=\(event.anchor.id, privacy: .public)"
            )
            guard let fileReference = fileReferenceByID[event.fileID] else {
                return
            }
            anchorReferenceByID[event.anchor.id] = (fileReference: fileReference, anchorKey: event.anchor.anchorKey)

            var emittedChunkHashes: Set<String> = []
            for chunk in event.scannedAnchor.chunks {
                guard emittedChunkHashes.insert(chunk.hash).inserted else {
                    continue
                }

                guard (try? await knowledgeDatabaseActor.knowledgeChunkExists(hash: chunk.hash)) != true else {
                    continue
                }

                await actorSystem.broadcast(
                    from: nil,
                    message: KnowledgeChunkCreated(
                        buildID: event.buildID,
                        fileID: event.fileID,
                        anchorID: event.anchor.id,
                        anchorKey: event.anchor.anchorKey,
                        chunk: KnowledgeChunkInput(
                            id: await identifierActor.makeIdentifier(),
                            anchorID: event.anchor.id,
                            ordinal: chunk.ordinal,
                            hash: chunk.hash,
                            text: chunk.text
                        ),
                        scannedChunk: chunk
                    )
                )
            }
        case _ as KnowledgeFileIndexed:
            break
        case let event as KnowledgeChunkCreated:
            logger.log(
                "knowledge-actor received knowledge-chunk-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.fileID, privacy: .public) chunkID=\(event.chunk.id, privacy: .public)"
            )
        case let event as KnowledgeChunkEncodeRequested:
            logger.log(
                "knowledge-actor received knowledge-chunk-encode-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.fileID, privacy: .public) chunkID=\(event.chunk.id, privacy: .public)"
            )
            guard let fileReference = fileReferenceByID[event.fileID] else {
                return
            }
            anchorReferenceByID[event.anchorID] = (fileReference: fileReference, anchorKey: event.anchorKey)
        case let event as KnowledgeLinkCreated:
            logger.log(
                "knowledge-actor received knowledge-link-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.fileID, privacy: .public) linkID=\(event.link.id, privacy: .public)"
            )
        case let event as KnowledgeDirectoryScanCompleted:
            logger.log(
                "knowledge-actor received knowledge-directory-scan-completed sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) directoryID=\(event.directoryID, privacy: .public) retained=\(event.retainingPaths.count, privacy: .public)"
            )

            // `pendingScannedFilesByReference` holds full scanned file payloads, including
            // chunk text. Those values are only needed while `KnowledgeFileCreated` events
            // are still being expanded into aliases, anchors, and links for the current
            // scan. Once the directory scan completes, retaining the live-file entries
            // turns the whole scanned corpus into an in-memory cache.
            pendingScannedFilesByReference = pendingScannedFilesByReference.filter { key, _ in
                key.directoryID != event.directoryID
            }
            errorMessage = nil
            broadcast()
        case let event as KnowledgeFileSelected:
            logger.log(
                "knowledge-actor received knowledge-file-selected sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) path=\(event.path, privacy: .public)"
            )
            break
        case let event as KnowledgeFileAccessed:
            logger.log(
                "knowledge-actor received knowledge-file-accessed sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) fileID=\(event.fileID, privacy: .public)"
            )
        case _ as KnowledgeDataInvalidated:
            dataRevision += 1
            broadcast()
        default:
            return
        }
    }

    private func replayActivityKnowledge(
        for activeDay: Date
    ) async throws {
        let dayStart = Calendar.current.startOfDay(for: activeDay)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        var lastActivityID: Int64?

        while true {
            let activityRequests = try await activityDatabaseActor.loadUnprocessedActivityKnowledgeRequests(
                dayStart: dayStart,
                dayEnd: dayEnd,
                afterActivityID: lastActivityID,
                limit: 200
            )

            guard !activityRequests.isEmpty else {
                return
            }

            lastActivityID = activityRequests.last?.activityID
            for activityRequest in activityRequests {
                await actorSystem.broadcast(
                    from: nil,
                    message: activityRequest
                )
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func clearScanState() {
        pendingScannedFilesByReference = [:]
        aliasTargetFileIDByLookupKey = [:]
        fileReferenceByID = [:]
        anchorReferenceByID = [:]
    }

    private func broadcast() {
        revision += 1
        let state = snapshot()
        continuations.values.forEach { $0.yield(state) }
    }

    private func scanDirectory(
        _ directory: KnowledgeDirectoryRecord,
        onFile: @escaping (KnowledgeScannedFile) async -> Void
    ) async throws -> Set<String> {
        let directoryURL = try resolvedDirectoryURL(for: directory)
        let startedAccessing = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccessing {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        let normalizedDirectoryURL = directoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        guard let enumerator else {
            return []
        }

        var retainingPaths = Set<String>()

        while let fileURL = enumerator.nextObject() as? URL {
            let normalizedFileURL = fileURL
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let relativePath = normalizedFileURL.path
                .replacingOccurrences(of: normalizedDirectoryURL.path + "/", with: "")
            let firstPathComponent = relativePath.split(separator: "/").first.map(String.init)
            let resourceValues = try? normalizedFileURL.resourceValues(forKeys: Set(resourceKeys))

            if firstPathComponent == "TaskTrace" {
                if resourceValues?.isDirectory == true {
                    enumerator.skipDescendants()
                }

                continue
            }

            guard let scannedFile = try Self.scanFile(
                at: normalizedFileURL,
                directoryURL: normalizedDirectoryURL,
                resourceKeys: resourceKeys
            ) else {
                continue
            }

            retainingPaths.insert(scannedFile.path)
            await onFile(scannedFile)
        }

        return retainingPaths
    }

    private nonisolated static func scanFile(
        at fileURL: URL,
        directoryURL: URL,
        resourceKeys: [URLResourceKey]
    ) throws -> KnowledgeScannedFile? {
        guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
              resourceValues.isRegularFile == true,
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let directoryPrefix = directoryURL.path + "/"
        var path = fileURL.path

        if path.hasPrefix(directoryPrefix) {
            path.removeFirst(directoryPrefix.count)
        }

        let content = String(data: data, encoding: .utf8)
        let lines = content?.components(separatedBy: .newlines) ?? []
        let titleFallback = fileURL.deletingPathExtension().lastPathComponent
        let frontmatter: (
            body: String,
            lineOffset: Int,
            metadataJSON: String?,
            explicitTitle: String?,
            aliases: [String]
        ) = if let content {
            Self.parseFrontmatter(from: content)
        } else {
            (body: "", lineOffset: 0, metadataJSON: nil, explicitTitle: nil, aliases: [])
        }
        let markdownBody = content == nil ? nil : frontmatter.body
        let markdownDocument: Document? = if let markdownBody {
            Document(parsing: markdownBody)
        } else {
            nil
        }
        let traversal: KnowledgeMarkdownWalker? = {
            if let markdownDocument {
                var walker = KnowledgeMarkdownWalker()
                walker.visit(markdownDocument)
                return walker
            }

            return nil
        }()
        let headingSlices = traversal.map { walker in
            Self.buildHeadingSlices(
                path: path,
                titleFallback: frontmatter.explicitTitle ?? titleFallback,
                lineOffset: frontmatter.lineOffset,
                totalLines: max(lines.count, 1),
                body: frontmatter.body,
                headings: walker.headings
            )
        } ?? []
        let aliases = Array(
            Set(
                ([titleFallback] + (frontmatter.explicitTitle.map { [$0] } ?? []) + frontmatter.aliases)
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
        let title = frontmatter.explicitTitle
            ?? headingSlices.first(where: { $0.anchorType == "heading" })?.headingText
            ?? titleFallback
        let anchors = headingSlices.map { slice in
            let chunkTexts = Self.sanitizedMarkdownChunkSource(from: slice.lines)
                .components(separatedBy: "\n\n")
                .enumerated()
                .compactMap { pair in
                    let chunkText = pair.element.trimmingCharacters(in: .whitespacesAndNewlines)

                    return chunkText.isEmpty
                        ? nil
                        : KnowledgeScannedChunk(
                            ordinal: pair.offset,
                            hash: sha256(for: chunkText),
                            text: chunkText
                        )
                }

            return KnowledgeScannedAnchor(
                anchorType: slice.anchorType,
                anchorKey: slice.anchorKey,
                headingText: slice.headingText,
                blockID: slice.blockID,
                startLine: slice.startLine,
                endLine: slice.endLine,
                textHash: slice.textHash,
                chunks: chunkTexts
            )
        }
        let lineResolvedLinks: [KnowledgeScannedLink] = traversal.map { walker in
            let markdownLinks = walker.links.compactMap { link -> KnowledgeScannedLink? in
                let destination = link.destination?.isEmpty == false ? link.destination : nil
                let resolvedSourceAnchorKey = headingSlices
                    .last(where: { $0.startLine <= link.line && link.line <= $0.endLine })?
                    .anchorKey
                    ?? headingSlices.first?.anchorKey
                    ?? "document"
                let parsedDestination = Self.parseDestination(
                    destination,
                    relativeTo: path
                )

                return KnowledgeScannedLink(
                    srcAnchorKey: resolvedSourceAnchorKey,
                    dstPathCandidate: parsedDestination.path,
                    dstAnchorHint: parsedDestination.anchorHint,
                    linkText: link.text,
                    linkType: "markdown"
                )
            }
            let wikiLinks = Self.parseWikiLinks(
                in: markdownBody ?? "",
                path: path,
                headingSlices: headingSlices,
                lineOffset: frontmatter.lineOffset
            )

            return Array(Set(markdownLinks + wikiLinks)).sorted {
                if $0.srcAnchorKey == $1.srcAnchorKey {
                    return $0.linkText < $1.linkText
                }
                return $0.srcAnchorKey < $1.srcAnchorKey
            }
        } ?? [KnowledgeScannedLink]()

        return KnowledgeScannedFile(
            path: path,
            title: title,
            hash: hash,
            modifiedAt: resourceValues.contentModificationDate,
            metadataJSON: content == nil
                ? #"{"content_type":"binary"}"#
                : frontmatter.metadataJSON ?? #"{"content_type":"markdown"}"#,
            byteCount: Int64(resourceValues.fileSize ?? data.count),
            aliases: aliases,
            anchors: anchors,
            links: lineResolvedLinks
        )
    }

    private func readFile(
        path: String,
        in directory: KnowledgeDirectoryRecord
    ) throws -> KnowledgeFilePreview {
        let directoryURL = try resolvedDirectoryURL(for: directory)
        let startedAccessing = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccessing {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileURL = directoryURL.appendingPathComponent(path)
        let data = try Data(contentsOf: fileURL)
        let previewData = data.prefix(maxPreviewByteCount)

        if let content = String(data: previewData, encoding: .utf8) {
            return KnowledgeFilePreview(
                path: path,
                byteCount: Int64(data.count),
                content: content,
                isTruncated: data.count > previewData.count
            )
        }

        return KnowledgeFilePreview(
            path: path,
            byteCount: Int64(data.count),
            content: "TaskTrace can see this file, but it is not UTF-8 text, so it cannot be previewed yet.",
            isTruncated: false
        )
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

    private nonisolated static func parseFrontmatter(from content: String) -> (
        body: String,
        lineOffset: Int,
        metadataJSON: String?,
        explicitTitle: String?,
        aliases: [String]
    ) {
        guard content.hasPrefix("---\n"),
              let closingRange = content.range(of: "\n---\n") else {
            return (content, 0, nil, nil, [])
        }

        let frontmatterText = String(content[content.index(content.startIndex, offsetBy: 4)..<closingRange.lowerBound])
        let bodyStartIndex = closingRange.upperBound
        let body = String(content[bodyStartIndex...])
        let lineOffset = frontmatterText.components(separatedBy: .newlines).count + 2
        let parsed = frontmatterText
            .components(separatedBy: .newlines)
            .reduce(into: (dictionary: [String: Any](), lastListKey: String?.none)) { partial, line in
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)

                if trimmedLine.hasPrefix("- "),
                   let lastListKey = partial.lastListKey {
                    let currentValues = (partial.dictionary[lastListKey] as? [String]) ?? []
                    partial.dictionary[lastListKey] = currentValues + [String(trimmedLine.dropFirst(2))]
                    return
                }

                let components = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard components.count == 2 else {
                    partial.lastListKey = nil
                    return
                }

                let key = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let rawValue = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                partial.lastListKey = nil

                if rawValue.isEmpty {
                    partial.dictionary[key] = [String]()
                    partial.lastListKey = key
                    return
                }

                if rawValue.hasPrefix("["),
                   rawValue.hasSuffix("]") {
                    partial.dictionary[key] = rawValue
                        .dropFirst()
                        .dropLast()
                        .split(separator: ",")
                        .map {
                            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        }
                    return
                }

                partial.dictionary[key] = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        let metadataData = try? JSONSerialization.data(withJSONObject: parsed.dictionary, options: [.sortedKeys])
        let metadataJSON = metadataData.map {
            String(decoding: $0, as: UTF8.self)
        }
        let aliases = (parsed.dictionary["aliases"] as? [String]) ?? []

        return (
            body,
            lineOffset,
            metadataJSON,
            parsed.dictionary["title"] as? String,
            aliases
        )
    }

    private nonisolated static func buildHeadingSlices(
        path: String,
        titleFallback: String,
        lineOffset: Int,
        totalLines: Int,
        body: String,
        headings: [KnowledgeMarkdownHeading]
    ) -> [KnowledgeHeadingSlice] {
        let bodyLines = body.components(separatedBy: .newlines)
        let headingLines = headings.map(\.line)
        let uniqueHeadingKeys = headings.enumerated().reduce(
            into: (
                usedKeys: Set(["document"]),
                duplicateCounts: [String: Int](),
                slices: [KnowledgeHeadingSlice]()
            )
        ) { partial, pair in
            let heading = pair.element
            let nextLine = pair.offset + 1 < headingLines.count ? headingLines[pair.offset + 1] - 1 : bodyLines.count
            let startLine = max(heading.line + lineOffset, 1)
            let endLine = max(nextLine + lineOffset, startLine)
            let blockStartIndex = min(max(heading.line + 1, 0), bodyLines.count)
            let blockEndIndex = min(nextLine, bodyLines.count)
            let blockLines = blockStartIndex < blockEndIndex
                ? Array(bodyLines[blockStartIndex..<blockEndIndex])
                : []
            let rawKey = slug(for: heading.text.isEmpty ? titleFallback : heading.text)
            let duplicateCount = partial.duplicateCounts[rawKey, default: 0]
            let anchorKey = {
                let baseKey = duplicateCount == 0 ? rawKey : "\(rawKey)-\(duplicateCount + 1)"

                guard !partial.usedKeys.contains(baseKey) else {
                    return "\(rawKey)-\(duplicateCount + 2)"
                }

                return baseKey
            }()

            partial.duplicateCounts[rawKey] = duplicateCount + 1
            partial.usedKeys.insert(anchorKey)
            partial.slices.append(KnowledgeHeadingSlice(
                anchorType: "heading",
                anchorKey: anchorKey,
                headingText: heading.text,
                blockID: anchorKey,
                startLine: startLine,
                endLine: endLine,
                textHash: sha256(for: blockLines.joined(separator: "\n")),
                lines: blockLines
            ))
        }.slices

        let preambleLines = headings.first.map {
            Array(bodyLines.prefix(max($0.line - 1, 0)))
        } ?? bodyLines
        let rootSlice = KnowledgeHeadingSlice(
            anchorType: "document",
            anchorKey: "document",
            headingText: titleFallback,
            blockID: nil,
            startLine: 1,
            endLine: max(totalLines, 1),
            textHash: sha256(for: body),
            lines: preambleLines.isEmpty && !body.isEmpty ? [body] : preambleLines
        )

        return [rootSlice] + uniqueHeadingKeys
    }

    private nonisolated static func parseWikiLinks(
        in body: String,
        path: String,
        headingSlices: [KnowledgeHeadingSlice],
        lineOffset: Int
    ) -> [KnowledgeScannedLink] {
        let regex = try! NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)

        return body
            .components(separatedBy: .newlines)
            .enumerated()
            .flatMap { pair -> [KnowledgeScannedLink] in
                let lineNumber = pair.offset + 1 + lineOffset
                let line = pair.element
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
                let matches = regex.matches(in: line, range: nsRange)
                let sourceAnchorKey = headingSlices
                    .last(where: { $0.startLine <= lineNumber && lineNumber <= $0.endLine })?
                    .anchorKey
                    ?? "document"

                return matches.compactMap { match in
                    guard
                        let rawRange = Range(match.range(at: 1), in: line)
                    else {
                        return nil
                    }

                    let rawValue = String(line[rawRange])
                    let components = rawValue.split(separator: "|", maxSplits: 1).map(String.init)
                    let destination = components.first ?? rawValue
                    let renderedText = components.count == 2 ? components[1] : destination
                    let parsedDestination = parseDestination(destination, relativeTo: path)

                    return KnowledgeScannedLink(
                        srcAnchorKey: sourceAnchorKey,
                        dstPathCandidate: parsedDestination.path,
                        dstAnchorHint: parsedDestination.anchorHint,
                        linkText: renderedText,
                        linkType: "wikilink"
                    )
                }
            }
    }

    private nonisolated static func parseDestination(
        _ destination: String?,
        relativeTo path: String
    ) -> (path: String?, anchorHint: String?) {
        guard let destination,
              !destination.hasPrefix("http://"),
              !destination.hasPrefix("https://"),
              !destination.hasPrefix("mailto:") else {
            return (nil, nil)
        }

        let parts = destination.split(separator: "#", maxSplits: 1).map(String.init)
        let destinationPath = parts.first ?? destination
        let anchorHint = parts.count == 2 ? parts[1] : nil
        let sourceDirectoryComponents = (path as NSString)
            .deletingLastPathComponent
            .split(separator: "/")
            .map(String.init)
        let candidateComponents = destinationPath.isEmpty
            ? path.split(separator: "/").map(String.init)
            : destinationPath.split(separator: "/").map(String.init)
        let normalizedComponents = (destinationPath.hasPrefix("/") ? [] : sourceDirectoryComponents) + candidateComponents
        let normalizedPath = normalizedComponents.reduce(into: [String]()) { partial, component in
            if component == "." || component.isEmpty {
                return
            }

            if component == ".." {
                _ = partial.popLast()
                return
            }

            partial.append(component)
        }
        .joined(separator: "/")

        return (normalizedPath.isEmpty ? nil : normalizedPath, anchorHint)
    }

    private nonisolated static func normalizedLookupKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "./"))
    }

    private nonisolated static func slug(for text: String) -> String {
        let slug = text
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")

        return slug.isEmpty ? "section" : slug
    }

    private nonisolated static func sha256(for text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func sanitizedMarkdownChunkSource(from lines: [String]) -> String {
        let markdownLinkRegex = try! NSRegularExpression(pattern: #"\[(.*?)\]\([^)]+\)"#)
        let wikiLinkWithLabelRegex = try! NSRegularExpression(pattern: #"\[\[([^|\]]+)\|([^\]]+)\]\]"#)
        let wikiLinkRegex = try! NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)
        let quotePrefixRegex = try! NSRegularExpression(pattern: #"^\s{0,3}>\s?"#)
        let bulletPrefixRegex = try! NSRegularExpression(pattern: #"^\s{0,3}[-*+]\s+"#)
        let orderedListPrefixRegex = try! NSRegularExpression(pattern: #"^\s{0,3}\d+\.\s+"#)
        let inlineCodeRegex = try! NSRegularExpression(pattern: #"`{1,3}([^`]+)`{1,3}"#)

        return lines
            .map {
                guard !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") else {
                    return ""
                }

                let sanitizedLine = [
                    (markdownLinkRegex, "$1"),
                    (wikiLinkWithLabelRegex, "$2"),
                    (wikiLinkRegex, "$1"),
                    (quotePrefixRegex, ""),
                    (bulletPrefixRegex, ""),
                    (orderedListPrefixRegex, ""),
                    (inlineCodeRegex, "$1")
                ]
                .reduce($0) { partial, entry in
                    let range = NSRange(partial.startIndex..<partial.endIndex, in: partial)
                    return entry.0.stringByReplacingMatches(
                        in: partial,
                        range: range,
                        withTemplate: entry.1
                    )
                }

                return sanitizedLine.trimmingCharacters(in: .whitespaces)
            }
            .reduce(into: [String]()) { partial, line in
                if line.isEmpty {
                    if partial.last?.isEmpty == false {
                        partial.append("")
                    }
                    return
                }

                partial.append(line)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated private struct KnowledgeMarkdownHeading: Equatable {
    let line: Int
    let text: String
}

nonisolated private struct KnowledgeMarkdownLink: Equatable {
    let line: Int
    let destination: String?
    let text: String
}

nonisolated private struct KnowledgeHeadingSlice: Equatable {
    let anchorType: String
    let anchorKey: String
    let headingText: String?
    let blockID: String?
    let startLine: Int
    let endLine: Int
    let textHash: String
    let lines: [String]
}

nonisolated private struct KnowledgeMarkdownWalker: MarkupWalker {
    var headings: [KnowledgeMarkdownHeading] = []
    var links: [KnowledgeMarkdownLink] = []

    mutating func visitHeading(_ heading: Heading) {
        headings.append(KnowledgeMarkdownHeading(
            line: heading.range?.lowerBound.line ?? 1,
            text: heading.plainText
        ))
        descendInto(heading)
    }

    mutating func visitLink(_ link: Link) {
        links.append(KnowledgeMarkdownLink(
            line: link.range?.lowerBound.line ?? 1,
            destination: link.destination,
            text: link.plainText
        ))
        descendInto(link)
    }
}
