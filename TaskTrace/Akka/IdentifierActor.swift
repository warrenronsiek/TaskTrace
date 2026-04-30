//
//  IdentifierActor.swift
//  TaskTrace
//
//  Created by Codex on 4/7/26.
//

import Foundation

actor IdentifierActor {
    nonisolated static let shared = IdentifierActor()

    private let now: @Sendable () -> Date
    private var latestIdentifier: Int64

    init(
        now: @escaping @Sendable () -> Date = Date.init,
        latestIdentifier: Int64? = nil
    ) {
        let currentTimestamp = Int64(now().timeIntervalSince1970 * 1_000)
        self.now = now
        self.latestIdentifier = max(latestIdentifier ?? (currentTimestamp - 1), currentTimestamp - 1)
    }

    func observeExisting(_ identifier: Int64?) {
        guard let identifier else {
            return
        }

        latestIdentifier = max(latestIdentifier, identifier)
    }

    func makeIdentifier(minimum: Int64? = nil) -> Int64 {
        let currentTimestamp = Int64(now().timeIntervalSince1970 * 1_000)
        let minimumIdentifier = max(currentTimestamp, minimum ?? Int64.min)
        latestIdentifier = max(latestIdentifier + 1, minimumIdentifier)
        return latestIdentifier
    }
}
