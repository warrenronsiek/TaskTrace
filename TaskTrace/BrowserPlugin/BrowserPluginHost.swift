//
//  BrowserPluginHost.swift
//  TaskTrace
//

import Foundation
import OSLog
import Darwin

enum BrowserPluginIngestLocation {
    nonisolated static func directoryURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("TaskTrace", isDirectory: true)
            .appendingPathComponent("BrowserPlugin", isDirectory: true)
    }
}

enum BrowserPluginNativeHostInstallLocation {
    nonisolated static func supportDirectoryURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("TaskTrace", isDirectory: true)
            .appendingPathComponent("BrowserPlugin", isDirectory: true)
            .appendingPathComponent("NativeMessaging", isDirectory: true)
    }

    nonisolated static func hostScriptURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        try supportDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("tasktrace-browser-plugin-host.sh", isDirectory: false)
    }

    nonisolated static func chromeNativeMessagingHostsDirectoryURL(
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Google", isDirectory: true)
            .appendingPathComponent("Chrome", isDirectory: true)
            .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
    }

    nonisolated static func chromeManifestURL(
        fileManager: FileManager = .default
    ) -> URL {
        chromeNativeMessagingHostsDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("\(Vars.browserPluginHostName).json", isDirectory: false)
    }
}

enum BrowserPluginNativeHostInstaller {
    nonisolated static func install(
        fileManager: FileManager = .default
    ) throws {
        try install(
            fileManager: fileManager,
            supportDirectoryURL: BrowserPluginNativeHostInstallLocation.supportDirectoryURL(
                fileManager: fileManager
            ),
            chromeNativeMessagingHostsDirectoryURL: BrowserPluginNativeHostInstallLocation
                .chromeNativeMessagingHostsDirectoryURL(fileManager: fileManager)
        )
    }

    nonisolated static func install(
        fileManager: FileManager = .default,
        supportDirectoryURL: URL,
        chromeNativeMessagingHostsDirectoryURL: URL
    ) throws {
        let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "browser-plugin")
        let hostScriptURL = supportDirectoryURL
            .appendingPathComponent("tasktrace-browser-plugin-host.sh", isDirectory: false)
        let chromeManifestURL = chromeNativeMessagingHostsDirectoryURL
            .appendingPathComponent("\(Vars.browserPluginHostName).json", isDirectory: false)

        try fileManager.createDirectory(
            at: supportDirectoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: chromeManifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let hostScript = """
        #!/bin/sh

        TASKTRACE_BROWSER_PLUGIN_SOCKET_PATH="${TASKTRACE_BROWSER_PLUGIN_SOCKET_PATH:-\(Vars.browserPluginSocketPath)}"

        if [ ! -S "$TASKTRACE_BROWSER_PLUGIN_SOCKET_PATH" ]; then
          echo "TaskTrace browser service is not running." >&2
          exit 1
        fi

        exec /usr/bin/nc -U "$TASKTRACE_BROWSER_PLUGIN_SOCKET_PATH"
        """
        try hostScript.write(to: hostScriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: hostScriptURL.path
        )

        let manifest = [
            "name": Vars.browserPluginHostName,
            "description": "TaskTrace browser plugin native messaging host",
            "path": hostScriptURL.path,
            "type": "stdio",
            "allowed_origins": [
                "chrome-extension://\(Vars.browserPluginExtensionID)/"
            ]
        ] as [String: Any]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(to: chromeManifestURL, options: .atomic)

        logger.log(
            "browser plugin native host installed manifest=\(chromeManifestURL.path, privacy: .public) script=\(hostScriptURL.path, privacy: .public)"
        )
    }
}

enum BrowserPluginIngestNotificationNames {
    nonisolated static let directoryDidChange = Foundation.Notification.Name("TaskTraceBrowserPluginDirectoryDidChange")
}

nonisolated protocol BrowserPluginIngestChangeSignaling {
    func postDirectoryDidChange()
    func addDirectoryDidChangeObserver(_ handler: @escaping @Sendable () -> Void) -> NSObjectProtocol
    func removeObserver(_ observer: NSObjectProtocol)
}

final class DistributedBrowserPluginIngestChangeSignal: BrowserPluginIngestChangeSignaling {
    private let center: DistributedNotificationCenter

    nonisolated init(center: DistributedNotificationCenter = .default()) {
        self.center = center
    }

    nonisolated func postDirectoryDidChange() {
        center.postNotificationName(
            BrowserPluginIngestNotificationNames.directoryDidChange,
            object: nil,
            userInfo: nil,
            options: [.deliverImmediately]
        )
    }

    nonisolated func addDirectoryDidChangeObserver(
        _ handler: @escaping @Sendable () -> Void
    ) -> NSObjectProtocol {
        center.addObserver(
            forName: BrowserPluginIngestNotificationNames.directoryDidChange,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }

    nonisolated func removeObserver(_ observer: NSObjectProtocol) {
        center.removeObserver(observer)
    }
}

nonisolated struct BrowserPluginPagePayload: Codable, Equatable, Sendable {
    let title: String?
    let url: String?
    let markdown: String
    let contentType: String?
    let sourceContentType: String?
}

nonisolated struct BrowserPluginHostRequest: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case ping
        case capturePageText = "capture_page_text"
    }

    let kind: Kind
    let page: BrowserPluginPagePayload?
}

nonisolated struct BrowserPluginHostResponse: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case helloWorld = "hello_world"
        case error
    }

    let kind: Kind
    let message: String
    let receivedURL: String?
    let receivedTitle: String?
    let receivedCharacterCount: Int
}

nonisolated enum BrowserPluginNativeMessagingError: Error, Equatable {
    case truncatedHeader
    case truncatedPayload(expected: UInt32, actual: Int)
    case invalidMessageLength(UInt32)
}

nonisolated enum BrowserPluginNativeMessagingCodec {
    nonisolated static func frame<Message: Encodable>(_ message: Message) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        let payloadLength = UInt32(payload.count)
        var littleEndianLength = payloadLength.littleEndian
        let header = withUnsafeBytes(of: &littleEndianLength) { Data($0) }
        return header + payload
    }

    nonisolated static func decodeFrame(_ frame: Data) throws -> Data {
        guard frame.count >= MemoryLayout<UInt32>.size else {
            throw BrowserPluginNativeMessagingError.truncatedHeader
        }

        let payloadLength = frame.prefix(MemoryLayout<UInt32>.size).withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt32.self).littleEndian
        }

        let payload = frame.dropFirst(MemoryLayout<UInt32>.size)

        guard payload.count == Int(payloadLength) else {
            throw BrowserPluginNativeMessagingError.truncatedPayload(
                expected: payloadLength,
                actual: payload.count
            )
        }

        return Data(payload)
    }

    nonisolated static func decodeNextFrame(
        from buffer: Data
    ) throws -> (payload: Data, remaining: Data)? {
        guard buffer.count >= MemoryLayout<UInt32>.size else {
            return nil
        }

        let payloadLength = buffer.prefix(MemoryLayout<UInt32>.size).withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt32.self).littleEndian
        }

        let frameLength = MemoryLayout<UInt32>.size + Int(payloadLength)

        guard frameLength >= MemoryLayout<UInt32>.size else {
            throw BrowserPluginNativeMessagingError.invalidMessageLength(payloadLength)
        }

        guard buffer.count >= frameLength else {
            return nil
        }

        return (
            Data(buffer[MemoryLayout<UInt32>.size..<frameLength]),
            Data(buffer.dropFirst(frameLength))
        )
    }
}

actor BrowserPluginMessageService {
    private let fileManager: FileManager
    private let ingestDirectoryURL: @Sendable () throws -> URL
    private let ingestChangeSignal: any BrowserPluginIngestChangeSignaling
    private let now: @Sendable () -> Date

    init(
        fileManager: FileManager = .default,
        ingestDirectoryURL: @escaping @Sendable () throws -> URL = { try BrowserPluginIngestLocation.directoryURL() },
        ingestChangeSignal: any BrowserPluginIngestChangeSignaling = DistributedBrowserPluginIngestChangeSignal(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.ingestDirectoryURL = ingestDirectoryURL
        self.ingestChangeSignal = ingestChangeSignal
        self.now = now
    }

    func handle(_ request: BrowserPluginHostRequest) -> BrowserPluginHostResponse {
        switch request.kind {
        case .ping:
            return BrowserPluginHostResponse(
                kind: .helloWorld,
                message: "Hello World!",
                receivedURL: nil,
                receivedTitle: nil,
                receivedCharacterCount: 0
            )
        case .capturePageText:
            guard let page = request.page else {
                return BrowserPluginHostResponse(
                    kind: .error,
                    message: "Browser plugin capture request did not include a page payload.",
                    receivedURL: nil,
                    receivedTitle: nil,
                    receivedCharacterCount: 0
                )
            }

            do {
                let ingestDirectoryURL = try ingestDirectoryURL()
                let capturedAt = now()
                try fileManager.createDirectory(
                    at: ingestDirectoryURL,
                    withIntermediateDirectories: true
                )

                let fileURL = ingestDirectoryURL.appendingPathComponent({
                    let timestamp = ISO8601DateFormatter()
                        .string(from: capturedAt)
                        .replacingOccurrences(of: ":", with: "-")
                    let slugSource = {
                        let contentWords = page.markdown
                            .replacingOccurrences(
                                of: #"(?m)^\s{0,3}#{1,6}\s*"#,
                                with: "",
                                options: .regularExpression
                            )
                            .components(separatedBy: CharacterSet.alphanumerics.inverted)
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .prefix(8)
                            .joined(separator: " ")

                        if !contentWords.isEmpty {
                            return contentWords
                        }

                        let trimmedTitle = page.title?.trimmingCharacters(in: .whitespacesAndNewlines)

                        if let trimmedTitle, !trimmedTitle.isEmpty {
                            return trimmedTitle
                        }

                        return page.url
                            .flatMap(URL.init(string:))
                            .flatMap { url in
                                let lastPathComponent = url.lastPathComponent
                                return lastPathComponent.isEmpty ? nil : lastPathComponent
                            }
                            ?? "browser-capture"
                    }()
                    let slug = slugSource
                        .lowercased()
                        .map { character in
                            character.isLetter || character.isNumber ? String(character) : "-"
                        }
                        .joined()
                        .split(separator: "-")
                        .map(String.init)
                        .prefix(10)
                        .joined(separator: "-")

                    return "\(timestamp)-\((slug.isEmpty ? "browser-capture" : slug)).md"
                }())
                let markdownDocument = {
                    let escapedTitle = (page.title ?? fileURL.deletingPathExtension().lastPathComponent)
                        .replacingOccurrences(of: "\"", with: "'")
                        .replacingOccurrences(of: "\n", with: " ")
                    let metadataLines = [
                        "---",
                        "title: \"\(escapedTitle)\"",
                        page.url.map {
                            "source_url: \"\($0.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " "))\""
                        },
                        page.contentType.map {
                            "content_type: \"\($0.replacingOccurrences(of: "\"", with: "'"))\""
                        },
                        page.sourceContentType.map {
                            "source_content_type: \"\($0.replacingOccurrences(of: "\"", with: "'"))\""
                        },
                        "ingested_via: \"tasktrace_browser_plugin\"",
                        "captured_at: \"\(ISO8601DateFormatter().string(from: capturedAt))\"",
                        "---",
                        "",
                        page.markdown.trimmingCharacters(in: .whitespacesAndNewlines),
                        ""
                    ]

                    return metadataLines.compactMap { $0 }.joined(separator: "\n")
                }()

                try markdownDocument.write(to: fileURL, atomically: true, encoding: .utf8)
                ingestChangeSignal.postDirectoryDidChange()

                return BrowserPluginHostResponse(
                    kind: .helloWorld,
                    message: "Hello World!",
                    receivedURL: page.url,
                    receivedTitle: page.title,
                    receivedCharacterCount: page.markdown.count
                )
            } catch {
                return BrowserPluginHostResponse(
                    kind: .error,
                    message: "TaskTrace could not persist the browser capture.",
                    receivedURL: page.url,
                    receivedTitle: page.title,
                    receivedCharacterCount: page.markdown.count
                )
            }
        }
    }
}

actor BrowserPluginSocketService {
    private struct Connection {
        let fileDescriptor: Int32
        var buffer: Data
    }

    nonisolated static func removeSocketFileIfPresent(at socketPath: String) {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            return
        }

        do {
            try FileManager.default.removeItem(atPath: socketPath)
        } catch {
            Logger(subsystem: "com.tasktrace.TaskTrace", category: "browser-plugin").error(
                "browser plugin remove socket file failed path=\(socketPath, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "browser-plugin")
    private let socketPath: String
    private let queue: DispatchQueue
    private let messageService: BrowserPluginMessageService

    private var listenerFileDescriptor: Int32?
    private var listenerSource: DispatchSourceRead?
    private var connections: [UUID: Connection]
    private var connectionSources: [UUID: DispatchSourceRead]

    init(
        socketPath: String = Vars.browserPluginSocketPath,
        messageService: BrowserPluginMessageService = BrowserPluginMessageService()
    ) {
        self.socketPath = socketPath
        self.queue = DispatchQueue(label: "com.tasktrace.browser-plugin.socket")
        self.messageService = messageService
        self.listenerFileDescriptor = nil
        self.listenerSource = nil
        self.connections = [:]
        self.connectionSources = [:]
    }

    func start() {
        guard listenerFileDescriptor == nil else {
            return
        }

        removeSocketFileIfPresent()

        let result: (Int32, DispatchSourceRead)? = {
            let listenerFileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)

            guard listenerFileDescriptor >= 0 else {
                return nil
            }

            let currentFlags = Darwin.fcntl(listenerFileDescriptor, F_GETFL)
            if currentFlags >= 0 {
                _ = Darwin.fcntl(listenerFileDescriptor, F_SETFL, currentFlags | O_NONBLOCK)
            }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.stride)
            let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)

            guard socketPath.utf8.count < maxPathLength else {
                Darwin.close(listenerFileDescriptor)
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

            let bindDidSucceed = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(listenerFileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.stride))
                }
            } == 0

            guard bindDidSucceed else {
                Darwin.close(listenerFileDescriptor)
                return nil
            }

            _ = socketPath.withCString {
                Darwin.chmod($0, mode_t(S_IRUSR | S_IWUSR))
            }

            guard Darwin.listen(listenerFileDescriptor, SOMAXCONN) == 0 else {
                Darwin.close(listenerFileDescriptor)
                removeSocketFileIfPresent()
                return nil
            }

            let listenerSource = DispatchSource.makeReadSource(
                fileDescriptor: listenerFileDescriptor,
                queue: queue
            )
            listenerSource.setEventHandler { [weak self] in
                guard let self else {
                    return
                }

                Task {
                    await self.acceptPendingConnections()
                }
            }
            listenerSource.setCancelHandler {
                Darwin.close(listenerFileDescriptor)
            }

            return (listenerFileDescriptor, listenerSource)
        }()

        guard let result else {
            logger.error("browser plugin socket listener start failed path=\(self.socketPath, privacy: .public) errno=\(errno, privacy: .public)")
            return
        }

        listenerFileDescriptor = result.0
        listenerSource = result.1
        result.1.resume()
        logger.log("browser plugin socket listener ready path=\(self.socketPath, privacy: .public)")
    }

    func stop() {
        listenerSource?.cancel()
        listenerSource = nil
        listenerFileDescriptor = nil
        connectionSources.values.forEach { $0.cancel() }
        connectionSources = [:]
        connections = [:]
        removeSocketFileIfPresent()
    }

    private func acceptPendingConnections() {
        guard let listenerFileDescriptor else {
            return
        }

        while true {
            let acceptedFileDescriptor = Darwin.accept(listenerFileDescriptor, nil, nil)

            if acceptedFileDescriptor < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    return
                }

                logger.error("browser plugin socket accept failed errno=\(errno, privacy: .public)")
                return
            }

            let currentFlags = Darwin.fcntl(acceptedFileDescriptor, F_GETFL)
            if currentFlags >= 0 {
                _ = Darwin.fcntl(acceptedFileDescriptor, F_SETFL, currentFlags | O_NONBLOCK)
            }

            let id = UUID()
            let source = DispatchSource.makeReadSource(
                fileDescriptor: acceptedFileDescriptor,
                queue: queue
            )
            source.setEventHandler { [weak self] in
                guard let self else {
                    return
                }

                Task {
                    await self.receiveAvailableData(on: id)
                }
            }
            source.setCancelHandler {
                Darwin.close(acceptedFileDescriptor)
            }
            connections[id] = Connection(
                fileDescriptor: acceptedFileDescriptor,
                buffer: Data()
            )
            connectionSources[id] = source
            source.resume()
        }
    }

    private func receiveAvailableData(on id: UUID) async {
        guard let connectionFileDescriptor = connections[id]?.fileDescriptor else {
            return
        }

        var buffer = [UInt8](repeating: 0, count: 65_536)

        while true {
            let receivedByteCount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.recv(connectionFileDescriptor, bytes.baseAddress, bytes.count, 0)
            }

            if receivedByteCount > 0 {
                guard var connection = connections[id] else {
                    return
                }

                connection.buffer.append(contentsOf: buffer.prefix(receivedByteCount))
                connections[id] = connection
                await drainBufferedMessages(on: id)
                continue
            }

            if receivedByteCount == 0 {
                removeConnection(id)
                return
            }

            if errno == EWOULDBLOCK || errno == EAGAIN {
                return
            }

            logger.error("browser plugin socket receive failed id=\(id.uuidString, privacy: .public) errno=\(errno, privacy: .public)")
            removeConnection(id)
            return
        }
    }

    private func drainBufferedMessages(on id: UUID) async {
        while true {
            guard var connection = connections[id] else {
                return
            }

            do {
                guard let framedMessage = try BrowserPluginNativeMessagingCodec.decodeNextFrame(
                    from: connection.buffer
                ) else {
                    return
                }

                let request = try JSONDecoder().decode(
                    BrowserPluginHostRequest.self,
                    from: framedMessage.payload
                )
                connection.buffer = framedMessage.remaining
                connections[id] = connection
                let response = await messageService.handle(request)
                try writeResponse(response, to: connection.fileDescriptor)
            } catch {
                logger.error("browser plugin socket message failed id=\(id.uuidString, privacy: .public) error=\(String(describing: error), privacy: .public)")
                removeConnection(id)
                return
            }
        }
    }

    private func writeResponse(
        _ response: BrowserPluginHostResponse,
        to fileDescriptor: Int32
    ) throws {
        let responseData = try BrowserPluginNativeMessagingCodec.frame(response)
        var writtenByteCount = 0

        try responseData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }

            while writtenByteCount < responseData.count {
                let nextChunkStart = baseAddress.advanced(by: writtenByteCount)
                let nextChunkLength = responseData.count - writtenByteCount
                let sentByteCount = Darwin.send(fileDescriptor, nextChunkStart, nextChunkLength, 0)

                if sentByteCount > 0 {
                    writtenByteCount += sentByteCount
                    continue
                }

                if errno == EWOULDBLOCK || errno == EAGAIN {
                    usleep(1_000)
                    continue
                }

                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    private func removeConnection(_ id: UUID) {
        connectionSources[id]?.cancel()
        connectionSources[id] = nil
        connections[id] = nil
    }

    private func removeSocketFileIfPresent() {
        Self.removeSocketFileIfPresent(at: socketPath)
    }
}

@MainActor
final class BrowserPluginSocketController {
    private let service: BrowserPluginSocketService
    private var isStarted = false

    init(service: BrowserPluginSocketService = BrowserPluginSocketService()) {
        self.service = service
    }

    func start() async {
        guard !isStarted else {
            return
        }

        isStarted = true
        await service.start()
    }

    func stop() async {
        guard isStarted else {
            return
        }

        isStarted = false
        await service.stop()
    }
}
