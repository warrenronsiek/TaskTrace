import Dispatch
import Darwin
import Foundation
import OSLog

Task {
    let proxy = TaskTraceMCPStdioProxy()
    Darwin.exit(await proxy.run())
}

dispatchMain()

struct TaskTraceMCPStdioProxy: Sendable {
    private let socketPath: String
    private let standardInput: Int32
    private let standardOutput: Int32
    private let standardError: Int32
    private let maxConnectionAttempts: Int
    private let retryDelayNanoseconds: UInt64
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "mcp-proxy")

    init(
        socketPath: String = ProcessInfo.processInfo.environment["TASKTRACE_MCP_SOCKET_PATH"]
            ?? Self.defaultSocketPath(),
        standardInput: Int32 = STDIN_FILENO,
        standardOutput: Int32 = STDOUT_FILENO,
        standardError: Int32 = STDERR_FILENO,
        maxConnectionAttempts: Int = 100,
        retryDelayNanoseconds: UInt64 = 50_000_000
    ) {
        self.socketPath = socketPath
        self.standardInput = standardInput
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.maxConnectionAttempts = maxConnectionAttempts
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    nonisolated func run() async -> Int32 {
        signal(SIGPIPE, SIG_IGN)

        guard let socketFileDescriptor = await connectToBroker() else {
            writeStandardError("TaskTrace MCP broker is not running.\n")
            return 1
        }

        logger.log("mcp helper connected socket=\(socketPath, privacy: .public)")
        return await proxy(socketFileDescriptor: socketFileDescriptor)
    }

    nonisolated private func connectToBroker() async -> Int32? {
        for attempt in 0..<maxConnectionAttempts {
            if let socketFileDescriptor = connectSocket() {
                return socketFileDescriptor
            }

            if attempt + 1 < maxConnectionAttempts {
                try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            }
        }

        return nil
    }

    nonisolated private func connectSocket() -> Int32? {
        let socketFileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)

        guard socketFileDescriptor >= 0 else {
            return nil
        }

        var noSigPipe: Int32 = 1
        setsockopt(
            socketFileDescriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.stride)
        let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)

        guard socketPath.utf8.count < maxPathLength else {
            Darwin.close(socketFileDescriptor)
            return nil
        }

        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: CChar.self, repeating: 0)
            _ = socketPath.withCString { source in
                strncpy(
                    destination.baseAddress?.assumingMemoryBound(to: CChar.self),
                    source,
                    maxPathLength - 1
                )
            }
        }

        let didConnect = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketFileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.stride))
            }
        } == 0

        guard didConnect else {
            Darwin.close(socketFileDescriptor)
            return nil
        }

        return socketFileDescriptor
    }

    nonisolated private func proxy(socketFileDescriptor: Int32) async -> Int32 {
        let inputTask = Task.detached {
            let result = Self.copy(from: standardInput, to: socketFileDescriptor)
            Darwin.shutdown(socketFileDescriptor, SHUT_WR)
            return result
        }
        let outputTask = Task.detached {
            Self.copy(from: socketFileDescriptor, to: standardOutput)
        }
        let outputResult = await outputTask.value
        inputTask.cancel()
        Darwin.close(socketFileDescriptor)
        return outputResult
    }

    nonisolated private static func copy(
        from sourceFileDescriptor: Int32,
        to destinationFileDescriptor: Int32
    ) -> Int32 {
        var buffer = [UInt8](repeating: 0, count: 65_536)

        while !Task.isCancelled {
            let readCount = Darwin.read(sourceFileDescriptor, &buffer, buffer.count)

            if readCount == 0 {
                return 0
            }

            if readCount < 0 {
                if errno == EINTR {
                    continue
                }

                if errno == EAGAIN || errno == EWOULDBLOCK {
                    usleep(1_000)
                    continue
                }

                return 1
            }

            var writtenCount = 0

            while writtenCount < readCount {
                let nextWriteCount = buffer.withUnsafeBytes { bytes in
                    Darwin.write(
                        destinationFileDescriptor,
                        bytes.baseAddress?.advanced(by: writtenCount),
                        readCount - writtenCount
                    )
                }

                if nextWriteCount > 0 {
                    writtenCount += nextWriteCount
                    continue
                }

                if nextWriteCount < 0 && errno == EINTR {
                    continue
                }

                if nextWriteCount < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    usleep(1_000)
                    continue
                }

                return 1
            }
        }

        return 0
    }

    nonisolated private func writeStandardError(_ message: String) {
        let data = Array(message.utf8)
        _ = data.withUnsafeBytes { bytes in
            Darwin.write(standardError, bytes.baseAddress, bytes.count)
        }
    }

    nonisolated private static func defaultApplicationURL() -> URL {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    nonisolated private static func defaultSocketPath() -> String {
        let bundleIdentifier = Bundle(url: defaultApplicationURL())?.bundleIdentifier
            ?? "com.tasktrace.TaskTrace.local"
        let suffix = bundleIdentifier
            .replacingOccurrences(of: "com.tasktrace.", with: "")
            .replacingOccurrences(of: ".", with: "-")
            .lowercased()
        return "/tmp/tasktrace-\(suffix)-mcp.sock"
    }
}
