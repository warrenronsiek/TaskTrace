//
//  AgentChannelActorTests.swift
//  TaskTraceTests
//

import Foundation
import Testing
@testable import TaskTrace

struct AgentChannelActorTests {
    @Test("immediate socket cleanup removes an existing socket path")
    func immediateSocketCleanupRemovesAnExistingSocketPath() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let socketPath = temporaryDirectory
            .appendingPathComponent("agent.sock")
            .path

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        FileManager.default.createFile(atPath: socketPath, contents: Data())
        AgentChannelActor.removeSocketFileIfPresent(at: socketPath)

        #expect(FileManager.default.fileExists(atPath: socketPath) == false)
    }

    @Test("immediate socket cleanup ignores a missing socket path")
    func immediateSocketCleanupIgnoresAMissingSocketPath() {
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.sock")
            .path

        AgentChannelActor.removeSocketFileIfPresent(at: socketPath)

        #expect(FileManager.default.fileExists(atPath: socketPath) == false)
    }
}
