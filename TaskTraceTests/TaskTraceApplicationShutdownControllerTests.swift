//
//  TaskTraceApplicationShutdownControllerTests.swift
//  TaskTraceTests
//
//  Created by Codex on 4/13/26.
//

import AppKit
import Foundation
import Testing
@testable import TaskTrace

@MainActor
struct TaskTraceApplicationShutdownControllerTests {
    @Test("termination returns later while async shutdown runs")
    func terminationReturnsLaterWhileAsyncShutdownRuns() async {
        let probe = ShutdownProbe()
        let controller = TaskTraceApplicationShutdownController(
            shutdown: {
                probe.shutdownCount += 1
                await withCheckedContinuation { continuation in
                    probe.shutdownContinuation = continuation
                }
            },
            replyToApplicationShouldTerminate: { shouldTerminate in
                probe.recordReply(shouldTerminate)
            }
        )

        let reply = controller.applicationShouldTerminate()
        await Task.yield()

        #expect(reply == .terminateLater)
        #expect(probe.shutdownCount == 1)
        #expect(probe.replyValues.isEmpty)

        probe.shutdownContinuation?.resume()
        await probe.waitForReplyCount(1)

        #expect(probe.replyValues == [true])
    }

    @Test("termination runs shutdown exactly once")
    func terminationRunsShutdownExactlyOnce() async {
        let probe = ShutdownProbe()
        let controller = TaskTraceApplicationShutdownController(
            shutdown: {
                probe.shutdownCount += 1
                await withCheckedContinuation { continuation in
                    probe.shutdownContinuation = continuation
                }
            },
            replyToApplicationShouldTerminate: { shouldTerminate in
                probe.recordReply(shouldTerminate)
            }
        )

        _ = controller.applicationShouldTerminate()
        await Task.yield()
        #expect(probe.shutdownCount == 1)

        probe.shutdownContinuation?.resume()
        await probe.waitForReplyCount(1)

        #expect(probe.replyValues == [true])
    }

    @Test("repeat termination requests stay pending and do not rerun shutdown")
    func repeatTerminationRequestsStayPendingAndDoNotRerunShutdown() async {
        let probe = ShutdownProbe()
        let controller = TaskTraceApplicationShutdownController(
            shutdown: {
                probe.shutdownCount += 1
                await withCheckedContinuation { continuation in
                    probe.shutdownContinuation = continuation
                }
            },
            replyToApplicationShouldTerminate: { shouldTerminate in
                probe.recordReply(shouldTerminate)
            }
        )

        let firstReply = controller.applicationShouldTerminate()
        let secondReply = controller.applicationShouldTerminate()
        await Task.yield()

        #expect(firstReply == .terminateLater)
        #expect(secondReply == .terminateLater)
        #expect(probe.shutdownCount == 1)

        probe.shutdownContinuation?.resume()
        await probe.waitForReplyCount(1)

        #expect(probe.replyValues == [true])
    }

    @Test("termination enables the shutdown overlay only when the window is visible")
    func terminationEnablesTheShutdownOverlayOnlyWhenTheWindowIsVisible() async {
        let shutdownState = TaskTraceApplicationShutdownState()
        let controller = TaskTraceApplicationShutdownController(
            shutdown: {},
            shutdownState: shutdownState,
            shouldShowOverlay: { true }
        )

        _ = controller.applicationShouldTerminate()

        #expect((shutdownState.isShuttingDown, shutdownState.showsOverlay) == (true, true))
    }
}

@MainActor
private final class ShutdownProbe {
    var shutdownCount = 0
    var shutdownContinuation: CheckedContinuation<Void, Never>?
    var replyValues: [Bool] = []
    private var replyContinuations: [(Int, CheckedContinuation<Void, Never>)] = []

    func recordReply(_ value: Bool) {
        replyValues.append(value)
        let continuations = replyContinuations
        replyContinuations.removeAll()
        continuations.forEach { expectedCount, continuation in
            if replyValues.count >= expectedCount {
                continuation.resume()
            } else {
                replyContinuations.append((expectedCount, continuation))
            }
        }
    }

    func waitForReplyCount(_ count: Int) async {
        guard replyValues.count < count else {
            return
        }

        await withCheckedContinuation { continuation in
            replyContinuations.append((count, continuation))
        }
    }
}
