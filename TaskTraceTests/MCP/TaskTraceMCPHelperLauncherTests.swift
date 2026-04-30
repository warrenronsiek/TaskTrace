import Foundation
import Testing
@testable import TaskTrace

struct TaskTraceMCPHelperLauncherTests {
    @Test("mcp stdio skips helper launch when only the caller process is listed")
    func skipsHelperLaunchWhenOnlyCallerProcessIsListed() {
        let shouldLaunch = TaskTraceMCPHelperLauncher.shouldExecHelper(
            bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app"),
            currentProcessIdentifier: 100,
            runningApplications: [
                (processIdentifier: 100, bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app"))
            ]
        )

        #expect(shouldLaunch == false)
    }

    @Test("mcp stdio launches helper when another TaskTrace process from the same bundle is running")
    func launchesHelperWhenAnotherTaskTraceProcessFromTheSameBundleIsRunning() {
        let shouldLaunch = TaskTraceMCPHelperLauncher.shouldExecHelper(
            bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app"),
            currentProcessIdentifier: 100,
            runningApplications: [
                (processIdentifier: 200, bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app"))
            ]
        )

        #expect(shouldLaunch == true)
    }

    @Test("mcp stdio ignores running TaskTrace processes from a different bundle")
    func ignoresRunningTaskTraceProcessesFromADifferentBundle() {
        let shouldLaunch = TaskTraceMCPHelperLauncher.shouldExecHelper(
            bundleURL: URL(fileURLWithPath: "/Applications/TaskTrace.app"),
            currentProcessIdentifier: 100,
            runningApplications: [
                (processIdentifier: 200, bundleURL: URL(fileURLWithPath: "/Applications/TaskTraceDev.app"))
            ]
        )

        #expect(shouldLaunch == false)
    }
}
