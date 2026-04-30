//
//  KnowledgeGraphStoreTests.swift
//  TaskTraceTests
//
//  Created by Codex on 4/3/26.
//

import Foundation
import MLXLMCommon
import Testing
@testable import TaskTrace

@MainActor
struct KnowledgeGraphStoreTests {
    private enum FixtureError: Error {
        case timedOut
    }

    private final class TestBrowserPluginIngestChangeSignal: BrowserPluginIngestChangeSignaling {
        private var handlers: [ObjectIdentifier: @Sendable () -> Void] = [:]

        func postDirectoryDidChange() {
            handlers.values.forEach { $0() }
        }

        func addDirectoryDidChangeObserver(
            _ handler: @escaping @Sendable () -> Void
        ) -> NSObjectProtocol {
            let observer = NSObject()
            handlers[ObjectIdentifier(observer)] = handler
            return observer
        }

        func removeObserver(_ observer: NSObjectProtocol) {
            guard let observerObject = observer as AnyObject? else {
                return
            }

            handlers.removeValue(forKey: ObjectIdentifier(observerObject))
        }
    }

    private actor FixedKnowledgeTextScheduler: Receiver {
        private let actorSystem: ActorSystem

        init(actorSystem: ActorSystem) {
            self.actorSystem = actorSystem
        }

        func receive(_ envelope: Envelope) async {
            guard let request = envelope.message as? ModelTextRequest else {
                return
            }

            let response = {
                guard request.prompt.contains("TaskTrace Plugin") else {
                    return """
                    ## Entities
                    (none)

                    ## Relationships
                    (none)
                    """
                }

                return """
                ## Entities
                Name: TaskTrace Plugin
                Type: product
                Description: TaskTrace Plugin captures browser activity for TaskTrace.
                Claims:
                - TaskTrace Plugin is referenced by the note.

                ## Relationships
                (none)
                """
            }()
            let now = Date()
            await actorSystem.broadcast(
                from: nil,
                message: ModelTextCompleted(
                    requestID: request.requestID,
                    response: response,
                    schedulerMetadata: AISchedulerMetadata(
                        scheduler: .textBig,
                        bucket: "test",
                        batchSize: 1,
                        source: request.source
                    ),
                    timing: AISchedulerTiming(
                        queuedAt: now,
                        startedAt: now,
                        finishedAt: now
                    )
                )
            )
        }
    }

    private func withStore(
        _ block: (KnowledgeGraphStore, TaskTraceDatabase, URL, URL, TestBrowserPluginIngestChangeSignal) async throws -> Void
    ) async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
        let knowledgeURL = rootURL.appendingPathComponent("Knowledge", isDirectory: true)
        let ingestURL = rootURL.appendingPathComponent("BrowserPlugin", isDirectory: true)
        let browserPluginIngestSignal = TestBrowserPluginIngestChangeSignal()

        try FileManager.default.createDirectory(at: knowledgeURL, withIntermediateDirectories: true)
        try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

        let database = try TaskTraceDatabase(databaseURL: databaseURL, activityAI: FakeActivityAI())
        let knowledgeReadDatabase = try KnowledgeReadDatabase(database: database)
        let actorSystem = ActorSystem()
        let activityDatabaseActor = ActivityDatabaseActor(database: database)
        let knowledgeDatabaseActor = KnowledgeDatabaseActor(database: database, actorSystem: actorSystem)
        let knowledgeGraphActor = KnowledgeGraphActor(
            activityDatabaseActor: activityDatabaseActor,
            knowledgeDatabaseActor: knowledgeDatabaseActor,
            actorSystem: actorSystem
        )
        let textScheduler = FixedKnowledgeTextScheduler(actorSystem: actorSystem)
        let chunkGraphActor = KnowledgeChunkGraphActor(
            actorSystem: actorSystem,
            knowledgeDatabaseActor: knowledgeDatabaseActor,
            activityDatabaseActor: activityDatabaseActor
        )
        let store = KnowledgeGraphStore(
            actorSystem: actorSystem,
            knowledgeGraphActor: knowledgeGraphActor,
            knowledgeReadDatabase: knowledgeReadDatabase,
            now: { Date(timeIntervalSince1970: 1_775_000_000) },
            taskTraceIngestDirectoryURL: { ingestURL },
            browserPluginIngestSignal: browserPluginIngestSignal
        )
        _ = await actorSystem.register(knowledgeGraphActor)
        _ = await actorSystem.register(knowledgeDatabaseActor)
        _ = await actorSystem.register(textScheduler)
        _ = await actorSystem.register(chunkGraphActor)

        try await block(store, database, knowledgeURL, ingestURL, browserPluginIngestSignal)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let startedAt = Date()

        while Date().timeIntervalSince(startedAt) < timeout {
            if await condition() {
                return
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        throw FixtureError.timedOut
    }

    private func fileEntrySummary(
        _ entries: [KnowledgeFileSystemEntry]
    ) -> Set<String> {
        Set(
            entries.map {
                "\($0.sourceSlot.rawValue):\(URL(fileURLWithPath: $0.path).lastPathComponent)"
            }
        )
    }

    @Test("adding a directory persists a file row with a hash")
    func addingDirectoryPersistsAFileRowWithHash() async throws {
        try await withStore { store, database, knowledgeURL, _, _ in
            try "hello tasktrace".write(
                to: knowledgeURL.appendingPathComponent("notes.txt"),
                atomically: true,
                encoding: .utf8
            )

            await store.addDirectory(url: knowledgeURL)

            let directoryID = try #require(store.directories.first?.id)
            let files: [KnowledgeFileRecord] = switch try await database.get(.knowledgeFile(.directoryID(directoryID))) {
            case let .knowledgeFiles(value):
                value
            default:
                []
            }

            #expect(files.first?.hash.isEmpty == false)
        }
    }

    @Test("reading a file updates the stored last accessed timestamp")
    func readingAFileUpdatesTheStoredLastAccessedTimestamp() async throws {
        try await withStore { store, database, knowledgeURL, _, _ in
            try "hello tasktrace".write(
                to: knowledgeURL.appendingPathComponent("notes.txt"),
                atomically: true,
                encoding: .utf8
            )

            await store.addDirectory(url: knowledgeURL)
            try await waitUntil {
                store.fileSystemEntries.contains(where: { $0.path == "notes.txt" })
            }
            await store.selectFile(path: "notes.txt")
            try await waitUntil {
                let directoryID = store.directories.first?.id
                return directoryID != nil
            }
            try await waitUntil {
                let directoryID = store.directories.first?.id
                let files: [KnowledgeFileRecord] = switch try? await database.get(.knowledgeFile(.directoryID(directoryID ?? -1))) {
                case let .knowledgeFiles(value):
                    value
                default:
                    []
                }

                return files.first?.lastAccessed != nil
            }

            let directoryID = try #require(store.directories.first?.id)
            let files: [KnowledgeFileRecord] = switch try await database.get(.knowledgeFile(.directoryID(directoryID))) {
            case let .knowledgeFiles(value):
                value
            default:
                []
            }

            #expect(files.first?.lastAccessed != nil)
        }
    }

    @Test("adding a markdown directory builds anchors aliases and links")
    func addingAMarkdownDirectoryBuildsAnchorsAliasesAndLinks() async throws {
        try await withStore { store, _, knowledgeURL, _, _ in
            try """
            ---
            title: Project Notes
            aliases:
            - Notes
            - Project
            ---

            # Overview

            Read [[Roadmap]] and [capture internals](Capture.md#vision).
            """.write(
                to: knowledgeURL.appendingPathComponent("Notes.md"),
                atomically: true,
                encoding: .utf8
            )
            try "# Roadmap\n\nShip the capture improvements.".write(
                to: knowledgeURL.appendingPathComponent("Roadmap.md"),
                atomically: true,
                encoding: .utf8
            )
            try "# Capture\n\n## Vision\n\nUse the vision lane.".write(
                to: knowledgeURL.appendingPathComponent("Capture.md"),
                atomically: true,
                encoding: .utf8
            )

            await store.addDirectory(url: knowledgeURL)
            try await waitUntil {
                store.fileSystemEntries.contains(where: { $0.path == "Notes.md" })
            }
            await store.selectFile(path: "Notes.md")
            try await waitUntil {
                store.selectedFileIndex?.anchors.isEmpty == false
            }

            #expect(store.selectedFileIndex?.anchors.isEmpty == false)
        }
    }

    @Test("adding a second Obsidian vault reports that the current vault must be deleted first")
    func addingASecondObsidianVaultReportsDeletionRequirement() async throws {
        try await withStore { store, _, knowledgeURL, _, _ in
            let secondVaultURL = knowledgeURL
                .deletingLastPathComponent()
                .appendingPathComponent("Knowledge-2", isDirectory: true)

            try FileManager.default.createDirectory(at: secondVaultURL, withIntermediateDirectories: true)

            await store.connectObsidianVault(url: knowledgeURL)
            await store.connectObsidianVault(url: secondVaultURL)

            #expect(store.errorMessage == "Delete the current Obsidian vault before adding a new one.")
        }
    }

    @Test("adding a second Obsidian vault leaves the original vault connected")
    func addingASecondObsidianVaultLeavesTheOriginalVaultConnected() async throws {
        try await withStore { store, _, knowledgeURL, _, _ in
            let secondVaultURL = knowledgeURL
                .deletingLastPathComponent()
                .appendingPathComponent("Knowledge-2", isDirectory: true)

            try FileManager.default.createDirectory(at: secondVaultURL, withIntermediateDirectories: true)

            await store.connectObsidianVault(url: knowledgeURL)
            await store.connectObsidianVault(url: secondVaultURL)

            #expect(store.directories.first?.path == knowledgeURL.path)
        }
    }

    @Test("removing the Obsidian vault deletes its ingested files")
    func removingTheObsidianVaultDeletesItsIngestedFiles() async throws {
        try await withStore { store, database, knowledgeURL, _, _ in
            try "hello tasktrace".write(
                to: knowledgeURL.appendingPathComponent("notes.txt"),
                atomically: true,
                encoding: .utf8
            )

            await store.connectObsidianVault(url: knowledgeURL)

            let directoryID = try #require(store.directories.first?.id)

            await store.removeSource(slot: .obsidianVault)

            let files: [KnowledgeFileRecord] = switch try await database.get(.knowledgeFile(.directoryID(directoryID))) {
            case let .knowledgeFiles(value):
                value
            default:
                []
            }

            #expect(files.isEmpty)
        }
    }

    @Test("loading the store provisions the managed TaskTrace ingest source")
    func loadingTheStoreProvisionsTheManagedTaskTraceIngestSource() async throws {
        try await withStore { store, _, _, ingestURL, _ in
            await store.load()

            #expect(store.directories.contains(where: {
                $0.slot == .taskTraceIngest && $0.path == ingestURL.path
            }))
        }
    }

    @Test("browser plugin ingest notifications rescan the managed TaskTrace ingest directory")
    func browserPluginIngestNotificationsRescanTheManagedTaskTraceIngestDirectory() async throws {
        try await withStore { store, _, _, ingestURL, browserPluginIngestSignal in
            await store.load()
            try """
            ---
            title: Browser Capture
            ---

            # Browser Capture

            Shipping captured markdown through TaskTrace ingest.
            """.write(
                to: ingestURL.appendingPathComponent("Browser Capture.md"),
                atomically: true,
                encoding: .utf8
            )

            browserPluginIngestSignal.postDirectoryDidChange()
            try await waitUntil {
                store.fileSystemEntries.contains(where: {
                    $0.sourceSlot == .taskTraceIngest
                        && URL(fileURLWithPath: $0.path).lastPathComponent == "Browser Capture.md"
                })
            }

            #expect(store.fileSystemEntries.contains(where: {
                $0.sourceSlot == .taskTraceIngest
                    && URL(fileURLWithPath: $0.path).lastPathComponent == "Browser Capture.md"
            }))
        }
    }

    @Test("rebuilding Obsidian knowledge only rescans the Obsidian slot")
    func rebuildingObsidianKnowledgeOnlyRescansTheObsidianSlot() async throws {
        try await withStore { store, _, knowledgeURL, ingestURL, browserPluginIngestSignal in
            let obsidianURL = knowledgeURL.appendingPathComponent("Notes.md")
            let ingestFileURL = ingestURL.appendingPathComponent("Browser Capture.md")

            try "# Notes\n\nShip the browser capture.".write(
                to: obsidianURL,
                atomically: true,
                encoding: .utf8
            )
            await store.connectObsidianVault(url: knowledgeURL)
            await store.load()
            try """
            ---
            title: Browser Capture
            ---

            # Browser Capture

            Plugin ingest content.
            """.write(
                to: ingestFileURL,
                atomically: true,
                encoding: .utf8
            )

            browserPluginIngestSignal.postDirectoryDidChange()
            try await waitUntil {
                fileEntrySummary(store.fileSystemEntries) == [
                    "obsidian_vault:Notes.md",
                    "tasktrace_ingest:Browser Capture.md"
                ]
            }

            try FileManager.default.removeItem(at: obsidianURL)
            try FileManager.default.removeItem(at: ingestFileURL)
            await store.rebuildSourceKnowledge(slot: .obsidianVault)
            try await waitUntil {
                fileEntrySummary(store.fileSystemEntries) == [
                    "tasktrace_ingest:Browser Capture.md"
                ]
            }

            #expect(fileEntrySummary(store.fileSystemEntries) == [
                "tasktrace_ingest:Browser Capture.md"
            ])
        }
    }

    @Test("rebuilding plugin knowledge only rescans the TaskTrace ingest slot")
    func rebuildingPluginKnowledgeOnlyRescansTheTaskTraceIngestSlot() async throws {
        try await withStore { store, _, knowledgeURL, ingestURL, browserPluginIngestSignal in
            let obsidianURL = knowledgeURL.appendingPathComponent("Notes.md")
            let ingestFileURL = ingestURL.appendingPathComponent("Browser Capture.md")

            try "# Notes\n\nShip the browser capture.".write(
                to: obsidianURL,
                atomically: true,
                encoding: .utf8
            )
            await store.connectObsidianVault(url: knowledgeURL)
            await store.load()
            try """
            ---
            title: Browser Capture
            ---

            # Browser Capture

            Plugin ingest content.
            """.write(
                to: ingestFileURL,
                atomically: true,
                encoding: .utf8
            )

            browserPluginIngestSignal.postDirectoryDidChange()
            try await waitUntil {
                fileEntrySummary(store.fileSystemEntries) == [
                    "obsidian_vault:Notes.md",
                    "tasktrace_ingest:Browser Capture.md"
                ]
            }

            try FileManager.default.removeItem(at: obsidianURL)
            try FileManager.default.removeItem(at: ingestFileURL)
            await store.rebuildSourceKnowledge(slot: .taskTraceIngest)
            try await waitUntil {
                fileEntrySummary(store.fileSystemEntries) == [
                    "obsidian_vault:Notes.md"
                ]
            }

            #expect(fileEntrySummary(store.fileSystemEntries) == [
                "obsidian_vault:Notes.md"
            ])
        }
    }

    @Test("deleting a browser plugin file triggers scan deletion and clears downstream nodes")
    func deletingABrowserPluginFileTriggersScanDeletionAndCascade() async throws {
        try await withStore { store, database, _, ingestURL, browserPluginIngestSignal in
            let fileName = "Browser Capture.md"
            let fileURL = ingestURL.appendingPathComponent(fileName)

            await store.load()
            try """
            ---
            title: Browser Capture
            aliases:
            - Browser Capture
            ---

            # Browser Capture

            Capture links to [[TaskTrace Plugin]].
            """.write(
                to: fileURL,
                atomically: true,
                encoding: .utf8
            )

            browserPluginIngestSignal.postDirectoryDidChange()
            try await waitUntil {
                store.fileSystemEntries.contains(where: {
                    $0.sourceSlot == .taskTraceIngest && $0.path == fileName
                })
            }

            let file = try #require(store.fileSystemEntries.first(where: {
                $0.sourceSlot == .taskTraceIngest && $0.path == fileName
            }))
            await store.selectFile(id: file.id)
            try await waitUntil {
                store.selectedFileIndex != nil
            }
            try await waitUntil {
                let nodes: [KnowledgeNodeRecord] = switch try? await database.get(.knowledgeNode(.all)) {
                    case let .knowledgeNodes(value):
                        value
                    default:
                        []
                }

                return nodes.isEmpty == false
            }

            let nodesBefore = switch try? await database.get(.knowledgeNode(.all)) {
                case let .knowledgeNodes(value):
                    value
                default:
                    []
            }
            #expect(nodesBefore.isEmpty == false)

            await store.deleteFile(id: file.id)
            try await waitUntil {
                store.fileSystemEntries.contains(where: { $0.id == file.id }) == false
            }

            let deletedFile: KnowledgeFileRecord? = switch try await database.get(.knowledgeFile(.id(file.id))) {
                case let .knowledgeFile(value):
                    value
                default:
                    nil
            }
            #expect(deletedFile?.deletedAt != nil)

            let nodesAfter = switch try await database.get(.knowledgeNode(.all)) {
                case let .knowledgeNodes(value):
                    value
                default:
                    []
            }
            #expect(nodesAfter.isEmpty)
        }
    }
}
