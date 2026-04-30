//
//  AgentChannelActor.swift
//  TaskTrace
//
//  Created by Codex on 4/2/26.
//

import Foundation
import OSLog
import Darwin

actor AgentChannelActor: AgentActionChannelSending {
    nonisolated static func removeSocketFileIfPresent(at socketPath: String) {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            return
        }

        do {
            try FileManager.default.removeItem(atPath: socketPath)
        } catch {
            Logger(subsystem: "com.tasktrace.TaskTrace", category: "agents").error(
                "agent channel remove socket file failed path=\(socketPath, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    struct TransportEvent: Identifiable, Equatable, Sendable {
        let id: UUID
        let timestamp: Date
        let message: String

        init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            message: String
        ) {
            self.id = id
            self.timestamp = timestamp
            self.message = message
        }
    }

    struct ChatEntry: Identifiable, Equatable, Sendable {
        enum Direction: String, Equatable, Sendable {
            case outbound
            case inbound
        }

        let id: UUID
        let timestamp: Date
        let direction: Direction
        let content: String

        init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            direction: Direction,
            content: String
        ) {
            self.id = id
            self.timestamp = timestamp
            self.direction = direction
            self.content = content
        }
    }

    struct State: Equatable, Sendable {
        var socketPath: String
        var isEnabled: Bool
        var isListening: Bool
        var connectedClients: Int
        var transportEvents: [TransportEvent]
        var conversationHistoryByConversationID: [String: [ChatEntry]]
        var errorMessage: String?

        init(
            socketPath: String,
            isEnabled: Bool = true,
            isListening: Bool = false,
            connectedClients: Int = 0,
            transportEvents: [TransportEvent] = [],
            conversationHistoryByConversationID: [String: [ChatEntry]] = [:],
            errorMessage: String? = nil
        ) {
            self.socketPath = socketPath
            self.isEnabled = isEnabled
            self.isListening = isListening
            self.connectedClients = connectedClients
            self.transportEvents = transportEvents
            self.conversationHistoryByConversationID = conversationHistoryByConversationID
            self.errorMessage = errorMessage
        }
    }

    private struct PendingResponse {
        let conversationID: String
        let continuation: CheckedContinuation<String?, Never>
    }

    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "agents")
    private let socketPath: String
    private let queue: DispatchQueue
    private let notificationManager: AgentNotificationManager?
    private let responseTimeoutNanoseconds: UInt64

    private var listenerFileDescriptor: Int32?
    private var listenerSource: DispatchSourceRead?
    private var connections: [UUID: Int32]
    private var connectionSources: [UUID: DispatchSourceRead]
    private var transportEvents: [TransportEvent]
    private var conversationHistoryByConversationID: [String: [ChatEntry]]
    private var errorMessage: String?
    private var isEnabled: Bool
    private var continuations: [UUID: AsyncStream<State>.Continuation]
    private var pendingResponses: [PendingResponse]
    private var lastOutboundConversationID: String?
    private var isSendSlotAcquired: Bool
    private var sendSlotContinuations: [CheckedContinuation<Void, Never>]

    init(
        socketPath: String = Vars.openClawChannelSocketPath,
        notificationManager: AgentNotificationManager? = nil,
        responseTimeoutNanoseconds: UInt64 = 600_000_000_000
    ) {
        self.socketPath = socketPath
        self.queue = DispatchQueue(label: "com.tasktrace.agents.socket")
        self.notificationManager = notificationManager
        self.responseTimeoutNanoseconds = responseTimeoutNanoseconds
        self.listenerFileDescriptor = nil
        self.listenerSource = nil
        self.connections = [:]
        self.connectionSources = [:]
        self.transportEvents = []
        self.conversationHistoryByConversationID = [:]
        self.errorMessage = nil
        self.isEnabled = true
        self.continuations = [:]
        self.pendingResponses = []
        self.lastOutboundConversationID = nil
        self.isSendSlotAcquired = false
        self.sendSlotContinuations = []
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
            socketPath: socketPath,
            isEnabled: isEnabled,
            isListening: listenerFileDescriptor != nil,
            connectedClients: connections.count,
            transportEvents: transportEvents,
            conversationHistoryByConversationID: conversationHistoryByConversationID,
            errorMessage: errorMessage
        )
    }

    func start() async {
        guard isEnabled else {
            appendTransportEvent("Skipped socket listener start because agents are disabled.")
            broadcast()
            return
        }

        guard listenerFileDescriptor == nil else {
            appendTransportEvent("Socket listener already running at \(socketPath).")
            return
        }

        removeSocketFileIfPresent()

        let result: (Int32, DispatchSourceRead)? = {
            let listenerFileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)

            guard listenerFileDescriptor >= 0 else {
                return nil
            }

            let setNonBlockingFlags = Darwin.fcntl(listenerFileDescriptor, F_GETFL)
            if setNonBlockingFlags >= 0 {
                _ = Darwin.fcntl(listenerFileDescriptor, F_SETFL, setNonBlockingFlags | O_NONBLOCK)
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
            errorMessage = "Could not start the OpenClaw channel socket."
            appendTransportEvent("Failed to start socket listener: \(String(cString: strerror(errno)))")
            logger.error("agent channel listener start failed path=\(self.socketPath, privacy: .public) errno=\(errno, privacy: .public)")
            broadcast()
            return
        }

        listenerFileDescriptor = result.0
        listenerSource = result.1
        errorMessage = nil
        appendTransportEvent("Starting Unix socket listener at \(socketPath).")
        result.1.resume()
        appendTransportEvent("Socket listener is ready.")
        broadcast()
    }

    func stop() {
        listenerSource?.cancel()
        listenerSource = nil
        listenerFileDescriptor = nil
        connectionSources.values.forEach { $0.cancel() }
        connectionSources = [:]
        connections = [:]
        pendingResponses.forEach { $0.continuation.resume(returning: nil) }
        pendingResponses = []
        removeSocketFileIfPresent()
        appendTransportEvent("Stopped Unix socket listener.")
        broadcast()
    }

    func setEnabled(_ nextValue: Bool) async {
        guard isEnabled != nextValue else {
            return
        }

        isEnabled = nextValue

        if nextValue {
            errorMessage = nil
            appendTransportEvent("Agents enabled.")
            broadcast()
            await start()
            return
        }

        errorMessage = nil
        appendTransportEvent("Agents disabled.")
        stop()
    }

    func sendAgentAction(_ request: AgentActionChannelRequest) async -> String? {
        guard isEnabled else {
            return nil
        }

        let payloadData = try? JSONEncoder().encode(request)
        let payloadText = payloadData.map { String(decoding: $0, as: UTF8.self) }

        return await sendPayload(
            conversationID: request.conversationID,
            payloadData: payloadData,
            payloadText: payloadText,
            sendDescription: request.kind == .agentAction ? "activity action" : request.kind.rawValue
        )
    }

    func sendChatMessage(
        conversationID: String,
        message: String
    ) async -> String? {
        guard isEnabled else {
            return nil
        }

        let request = AgentActionChannelRequest(
            kind: .chatMessage,
            conversationID: conversationID,
            message: message
        )
        let payloadData = try? JSONEncoder().encode(request)
        let payloadText = payloadData.map { String(decoding: $0, as: UTF8.self) }

        return await sendPayload(
            conversationID: conversationID,
            payloadData: payloadData,
            payloadText: payloadText,
            sendDescription: "manual chat"
        )
    }

    private func sendPayload(
        conversationID: String,
        payloadData: Data?,
        payloadText: String?,
        sendDescription: String
    ) async -> String? {
        guard isEnabled else {
            return nil
        }

        guard listenerFileDescriptor != nil else {
            errorMessage = "The OpenClaw channel socket is not running."
            appendTransportEvent("Skipped channel send because the socket listener is not running.")
            broadcast()
            return nil
        }

        guard let connectionID = connections.keys.sorted(by: { $0.uuidString < $1.uuidString }).first,
              let connectionFileDescriptor = connections[connectionID] else {
            errorMessage = "No OpenClaw channel clients are connected."
            appendTransportEvent("Skipped channel send because no channel clients are connected.")
            broadcast()
            return nil
        }

        guard let payloadData, let payloadText else {
            errorMessage = "Could not encode the agent action payload."
            appendTransportEvent("Failed to encode channel payload before send.")
            broadcast()
            return nil
        }

        let isQueuedBehindActiveRequest = isSendSlotAcquired
        appendTransportEvent(
            isQueuedBehindActiveRequest
                ? "Queued channel send \(sendDescription) behind an active request."
                : "Queued channel send \(sendDescription)."
        )
        appendChatEntry(
            ChatEntry(direction: .outbound, content: payloadText),
            conversationID: conversationID
        )
        lastOutboundConversationID = conversationID
        broadcast()

        await acquireSendSlot()
        defer {
            releaseSendSlot()
        }

        appendTransportEvent(
            "Preparing channel send \(sendDescription)"
        )
        logPayloadLines(
            prefix: "agent channel outbound",
            context: "\(sendDescription) connectionID=\(connectionID.uuidString.prefix(8))",
            text: payloadText
        )

        let didSend = await withCheckedContinuation { continuation in
            let sentAllBytes = payloadData.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    return false
                }

                var totalSent = 0

                while totalSent < bytes.count {
                    let sentCount = Darwin.send(
                        connectionFileDescriptor,
                        baseAddress.advanced(by: totalSent),
                        bytes.count - totalSent,
                        0
                    )

                    if sentCount < 0 {
                        if errno == EINTR {
                            continue
                        }

                        return false
                    }

                    totalSent += sentCount
                }

                return true
            }

            continuation.resume(returning: sentAllBytes)
        }

        guard didSend else {
            errorMessage = "Could not send the agent action through the OpenClaw channel socket."
            appendTransportEvent("Failed to send channel payload to channel client \(connectionID.uuidString.prefix(8)).")
            broadcast()
            return nil
        }

        errorMessage = nil
        appendTransportEvent("Sent channel payload to channel client \(connectionID.uuidString.prefix(8)).")
        broadcast()

        return await withCheckedContinuation { continuation in
            pendingResponses.append(
                PendingResponse(
                    conversationID: conversationID,
                    continuation: continuation
                )
            )

            Task {
                try? await Task.sleep(nanoseconds: responseTimeoutNanoseconds)
                await self.handlePendingResponseTimeout(conversationID: conversationID)
            }
        }
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

                appendTransportEvent("Socket accept failed: \(String(cString: strerror(errno)))")
                logger.error("agent channel accept failed errno=\(errno, privacy: .public)")
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
            connections[id] = acceptedFileDescriptor
            connectionSources[id] = source
            source.resume()
            errorMessage = nil
            appendTransportEvent("Accepted channel client \(id.uuidString.prefix(8)).")
            broadcast()
        }
    }

    private func receiveAvailableData(on id: UUID) {
        guard let connectionFileDescriptor = connections[id] else {
            return
        }

        var buffer = [UInt8](repeating: 0, count: 65_536)

        while true {
            let receivedByteCount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.recv(connectionFileDescriptor, bytes.baseAddress, bytes.count, 0)
            }

            if receivedByteCount > 0 {
                let message = String(decoding: buffer.prefix(receivedByteCount), as: UTF8.self)
                handleInboundMessage(message, connectionID: id)
                continue
            }

            if receivedByteCount == 0 {
                appendTransportEvent("Channel client \(id.uuidString.prefix(8)) disconnected.")
                removeConnection(id)
                return
            }

            if errno == EWOULDBLOCK || errno == EAGAIN {
                return
            }

            appendTransportEvent("Receive failed from \(id.uuidString.prefix(8)): \(String(cString: strerror(errno)))")
            logger.error("agent channel receive failed id=\(id.uuidString, privacy: .public) errno=\(errno, privacy: .public)")
            removeConnection(id)
            return
        }
    }

    private func handleInboundMessage(_ message: String, connectionID: UUID) {
        appendTransportEvent("Received channel response from \(connectionID.uuidString.prefix(8)).")
        logPayloadLines(
            prefix: "agent channel inbound",
            context: "connectionID=\(connectionID.uuidString.prefix(8))",
            text: message
        )

        if !pendingResponses.isEmpty {
            let pendingResponse = pendingResponses.removeFirst()
            appendTransportEvent(
                "Matched inbound channel response to the waiting request."
            )
            appendChatEntry(
                ChatEntry(direction: .inbound, content: message),
                conversationID: pendingResponse.conversationID
            )
            if let notificationManager {
                Task {
                    await notificationManager.notifyIfHighPriority(
                        rawMessage: message,
                        conversationID: pendingResponse.conversationID
                    )
                }
            }
            pendingResponse.continuation.resume(returning: message)
            lastOutboundConversationID = pendingResponse.conversationID
        } else if let lastOutboundConversationID {
            appendTransportEvent(
                "Matched inbound channel response using the most recent conversation."
            )
            appendChatEntry(
                ChatEntry(direction: .inbound, content: message),
                conversationID: lastOutboundConversationID
            )
            if let notificationManager {
                Task {
                    await notificationManager.notifyIfHighPriority(
                        rawMessage: message,
                        conversationID: lastOutboundConversationID
                    )
                }
            }
        }

        broadcast()
    }

    private func timeoutOldestPendingResponse(conversationID: String) {
        guard let index = pendingResponses.firstIndex(where: { $0.conversationID == conversationID }) else {
            return
        }

        let pendingResponse = pendingResponses.remove(at: index)
        appendTransportEvent("Timed out waiting for a channel response.")
        pendingResponse.continuation.resume(returning: nil)
        broadcast()
    }

    private func handlePendingResponseTimeout(conversationID: String) async {
        timeoutOldestPendingResponse(conversationID: conversationID)
    }

    private func acquireSendSlot() async {
        guard isSendSlotAcquired else {
            isSendSlotAcquired = true
            return
        }

        await withCheckedContinuation { continuation in
            sendSlotContinuations.append(continuation)
        }
    }

    private func releaseSendSlot() {
        guard !sendSlotContinuations.isEmpty else {
            isSendSlotAcquired = false
            return
        }

        let continuation = sendSlotContinuations.removeFirst()
        continuation.resume()
    }

    private func removeConnection(_ id: UUID) {
        connectionSources[id]?.cancel()
        connectionSources[id] = nil
        connections[id] = nil
        broadcast()
    }

    private func appendTransportEvent(_ message: String) {
        transportEvents.insert(TransportEvent(message: message), at: 0)
        transportEvents = Array(transportEvents.prefix(20))
        logger.log("\(message, privacy: .public)")
    }

    private func appendChatEntry(_ entry: ChatEntry, conversationID: String) {
        conversationHistoryByConversationID[conversationID] = [entry] + (conversationHistoryByConversationID[conversationID] ?? [])
        conversationHistoryByConversationID[conversationID] = Array((conversationHistoryByConversationID[conversationID] ?? []).prefix(50))
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func broadcast() {
        let state = snapshot()
        continuations.values.forEach { $0.yield(state) }
    }

    private func removeSocketFileIfPresent() {
        Self.removeSocketFileIfPresent(at: socketPath)
    }

    private func logPayloadLines(prefix: String, context: String, text: String) {
        let lines = text.components(separatedBy: "\n")

        lines.enumerated().forEach { index, line in
            logger.log(
                "\(prefix, privacy: .public) \(context, privacy: .public) line=\(index, privacy: .public) text=\(line, privacy: .public)"
            )
        }
    }
}
