//
//  TaskTraceSiblingProcessControllerTests.swift
//  TaskTraceTests
//

import Foundation
import Testing
@testable import TaskTrace

@MainActor
struct TaskTraceSiblingProcessControllerTests {
    @Test("immediate cleanup only force kills sibling processes from the same bundle path")
    func immediateCleanupOnlyForceKillsSiblingProcessesFromTheSameBundlePath() {
        let listing = ProcessListingProbe(
            snapshots: [[
                TaskTraceSiblingProcess(
                    processIdentifier: 100,
                    bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app")
                ),
                TaskTraceSiblingProcess(
                    processIdentifier: 200,
                    bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app")
                ),
                TaskTraceSiblingProcess(
                    processIdentifier: 300,
                    bundleURL: URL(fileURLWithPath: "/Applications/OtherTaskTrace.app")
                )
            ]]
        )
        let killer = ProcessKillingProbe()
        let controller = TaskTraceSiblingProcessController(
            bundleIdentifier: "com.tasktrace.TaskTrace",
            bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app"),
            currentProcessIdentifier: 100,
            processListing: listing,
            processKilling: killer,
            pollIntervalNanoseconds: 1,
            maxPollingPasses: 3
        )

        controller.forceKillSiblingProcessesImmediately()

        #expect(killer.killedProcessIdentifiers == [200])
    }

    @Test("async cleanup retries until no sibling processes remain")
    func asyncCleanupRetriesUntilNoSiblingProcessesRemain() async {
        let listing = ProcessListingProbe(
            snapshots: [
                [
                    TaskTraceSiblingProcess(
                        processIdentifier: 200,
                        bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app")
                    )
                ],
                [
                    TaskTraceSiblingProcess(
                        processIdentifier: 200,
                        bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app")
                    )
                ],
                []
            ]
        )
        let killer = ProcessKillingProbe()
        let sleepProbe = SleepProbe()
        let controller = TaskTraceSiblingProcessController(
            bundleIdentifier: "com.tasktrace.TaskTrace",
            bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app"),
            currentProcessIdentifier: 100,
            processListing: listing,
            processKilling: killer,
            pollIntervalNanoseconds: 1,
            maxPollingPasses: 3,
            sleep: { nanoseconds in
                await sleepProbe.sleep(nanoseconds: nanoseconds)
            }
        )

        await controller.forceKillSiblingProcesses()

        #expect(killer.killedProcessIdentifiers == [200, 200])
        #expect(await sleepProbe.requestedNanoseconds == [1, 1])
    }

    @Test("cleanup does nothing when the bundle identifier is unavailable")
    func cleanupDoesNothingWhenTheBundleIdentifierIsUnavailable() async {
        let listing = ProcessListingProbe(
            snapshots: [[
                TaskTraceSiblingProcess(
                    processIdentifier: 200,
                    bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app")
                )
            ]]
        )
        let killer = ProcessKillingProbe()
        let controller = TaskTraceSiblingProcessController(
            bundleIdentifier: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app"),
            currentProcessIdentifier: 100,
            processListing: listing,
            processKilling: killer,
            pollIntervalNanoseconds: 1,
            maxPollingPasses: 3
        )

        controller.forceKillSiblingProcessesImmediately()
        await controller.forceKillSiblingProcesses()

        #expect(listing.bundleIdentifiers.isEmpty)
        #expect(killer.killedProcessIdentifiers.isEmpty)
    }

    @Test("cleanup preserves protected sibling process identifiers")
    func cleanupPreservesProtectedSiblingProcessIdentifiers() {
        let listing = ProcessListingProbe(
            snapshots: [[
                TaskTraceSiblingProcess(
                    processIdentifier: 200,
                    bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app")
                ),
                TaskTraceSiblingProcess(
                    processIdentifier: 300,
                    bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app")
                )
            ]]
        )
        let killer = ProcessKillingProbe()
        let controller = TaskTraceSiblingProcessController(
            bundleIdentifier: "com.tasktrace.TaskTrace",
            bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app"),
            currentProcessIdentifier: 100,
            processListing: listing,
            processKilling: killer,
            pollIntervalNanoseconds: 1,
            maxPollingPasses: 3,
            protectedProcessIdentifiers: { [300] }
        )

        controller.forceKillSiblingProcessesImmediately()

        #expect(killer.killedProcessIdentifiers == [200])
    }
}

private final class ProcessListingProbe: TaskTraceSiblingProcessListing {
    private let snapshots: [[TaskTraceSiblingProcess]]
    private(set) var callCount = 0
    private(set) var bundleIdentifiers: [String] = []

    init(snapshots: [[TaskTraceSiblingProcess]]) {
        self.snapshots = snapshots
    }

    func runningSiblingCandidates(bundleIdentifier: String) -> [TaskTraceSiblingProcess] {
        bundleIdentifiers.append(bundleIdentifier)
        let snapshot = snapshots[min(callCount, snapshots.count - 1)]
        callCount += 1
        return snapshot
    }
}

private final class ProcessKillingProbe: TaskTraceProcessKilling {
    private(set) var killedProcessIdentifiers: [Int32] = []

    func forceKill(processIdentifier: Int32) {
        killedProcessIdentifiers.append(processIdentifier)
    }
}

private actor SleepProbe {
    private(set) var requestedNanoseconds: [UInt64] = []

    func sleep(nanoseconds: UInt64) {
        requestedNanoseconds.append(nanoseconds)
    }
}
