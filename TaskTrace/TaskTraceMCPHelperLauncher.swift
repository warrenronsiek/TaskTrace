import AppKit
import Darwin
import Foundation

enum TaskTraceMCPHelperLauncher {
    nonisolated static let executableName = "TaskTraceMCPHelper"

    nonisolated static func execIfTaskTraceIsRunning() -> Never {
        guard shouldExecHelper(
            bundleURL: Bundle.main.bundleURL,
            currentProcessIdentifier: Int32(ProcessInfo.processInfo.processIdentifier),
            runningApplications: runningTaskTraceApplications()
        ) else {
            Darwin.exit(0)
        }

        exec()
    }

    nonisolated static func shouldExecHelper(
        bundleURL: URL?,
        currentProcessIdentifier: Int32,
        runningApplications: [(processIdentifier: Int32, bundleURL: URL?)]
    ) -> Bool {
        runningApplications.contains {
            $0.processIdentifier != currentProcessIdentifier
            && (
                bundleURL == nil
                || $0.bundleURL == nil
                || $0.bundleURL?.path == bundleURL?.path
            )
        }
    }

    nonisolated static func exec() -> Never {
        let fileManager = FileManager.default
        let helperURL = candidateHelperURLs()
            .first(where: { fileManager.isExecutableFile(atPath: $0.path) })

        guard let helperURL else {
            fputs("TaskTrace MCP helper executable is missing.\n", stderr)
            Darwin.exit(1)
        }

        let arguments = CommandLine.arguments
        let cArguments = ([helperURL.path] + Array(arguments.dropFirst())).map {
            guard let duplicated = strdup($0) else {
                fputs("Could not allocate helper argv.\n", stderr)
                Darwin.exit(1)
            }
            return duplicated
        }
        let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: cArguments.count + 1)

        for (index, value) in cArguments.enumerated() {
            argv[index] = value
        }
        argv[cArguments.count] = nil

        _ = helperURL.path.withCString {
            execv($0, argv)
        }

        perror("execv")
        Darwin.exit(1)
    }

    nonisolated private static func runningTaskTraceApplications() -> [(processIdentifier: Int32, bundleURL: URL?)] {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return []
        }

        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).map {
            (processIdentifier: Int32($0.processIdentifier), bundleURL: $0.bundleURL)
        }
    }

    nonisolated private static func candidateHelperURLs() -> [URL] {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundleHelpersURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(executableName, isDirectory: false)
        let adjacentHelpersURL = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent(executableName, isDirectory: false)

        return [bundleHelpersURL, adjacentHelpersURL]
    }
}
