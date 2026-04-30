import Foundation

struct Envelope: Sendable {
    let sender: UUID?
    let message: any Sendable
}

actor Actor<State>: Sendable {
    private var state: State
    private let handler: @Sendable (State, Envelope) async -> State

    init(
        initialState: State,
        handler: @escaping @Sendable (State, Envelope) async -> State
    ) {
        self.state = initialState
        self.handler = handler
    }

    func receive(_ envelope: Envelope) async {
        state = await handler(state, envelope)
    }
}

protocol Receiver: Sendable {
    func receive(_ envelope: Envelope) async
}

extension Actor: Receiver {}

struct AnyReceiver: Sendable {
    private let _receive: @Sendable (Envelope) async -> Void

    nonisolated init<R: Receiver>(_ receiver: R) {
        self._receive = { envelope in
            await receiver.receive(envelope)
        }
    }

    nonisolated func receive(_ envelope: Envelope) async {
        await _receive(envelope)
    }
}

actor ActorSystem {
    private var receivers: [UUID: AnyReceiver] = [:]

    func register<R: Receiver>(_ receiver: R) -> UUID {
        let id = UUID()
        receivers[id] = AnyReceiver(receiver)
        return id
    }

    func unregister(_ id: UUID) {
        receivers.removeValue(forKey: id)
    }

    func send(to id: UUID, envelope: Envelope) async {
        guard let receiver = receivers[id] else { return }
        await receiver.receive(envelope)
    }

    func send(
        from sender: UUID?,
        to id: UUID,
        message: any Sendable
    ) async {
        await send(to: id, envelope: Envelope(sender: sender, message: message))
    }

    func broadcast(_ envelope: Envelope) async {
        let currentReceivers = Array(receivers.values)

        await withTaskGroup(of: Void.self) { group in
            for receiver in currentReceivers {
                group.addTask {
                    await receiver.receive(envelope)
                }
            }
        }
    }

    func broadcast(
        from sender: UUID?,
        message: any Sendable
    ) async {
        await broadcast(Envelope(sender: sender, message: message))
    }
}
