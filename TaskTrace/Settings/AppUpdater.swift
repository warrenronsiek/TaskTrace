//
//  AppUpdater.swift
//  TaskTrace
//
//  Created by Codex on 3/19/26.
//

import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var isConfigured = false
    @Published private(set) var currentVersion = ""

    let updaterController: SPUStandardUpdaterController
    private let updaterDelegate: SparkleFeedDelegate

    init() {
        let feedURLString = Self.feedURLString
        let publicKey = ((Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? Self.fallbackPublicKey
        let isPlaceholder = publicKey == Self.publicKeyPlaceholder
        let feedURL = URL(string: feedURLString)
        let isConfigured = !publicKey.isEmpty && !isPlaceholder && feedURL?.scheme != nil
        updaterDelegate = SparkleFeedDelegate(feedURLString: feedURLString)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: isConfigured,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )

        let updater = updaterController.updater
        self.isConfigured = isConfigured
        currentVersion = Self.currentVersionString

        canCheckForUpdates = updater.canCheckForUpdates && isConfigured
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates

        updater.publisher(for: \.canCheckForUpdates)
            .map { [weak self] canCheckForUpdates in
                canCheckForUpdates && (self?.isConfigured ?? false)
            }
            .assign(to: &$canCheckForUpdates)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)

        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .assign(to: &$automaticallyDownloadsUpdates)
    }

    func checkForUpdates() {
        guard isConfigured else {
            return
        }

        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isConfigured else {
            return
        }

        updaterController.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard isConfigured else {
            return
        }

        updaterController.updater.automaticallyDownloadsUpdates = enabled
    }
}

private final class SparkleFeedDelegate: NSObject, SPUUpdaterDelegate {
    let feedURLString: String

    init(feedURLString: String) {
        self.feedURLString = feedURLString
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feedURLString
    }
}

private extension AppUpdater {
    static let publicKeyPlaceholder = "TASKTRACE_SPARKLE_PUBLIC_ED_KEY"
    static let fallbackPublicKey = publicKeyPlaceholder

    static var currentVersionString: String {
        let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return shortVersion
    }

    static var feedURLString: String {
        ((Bundle.main.object(forInfoDictionaryKey: "TaskTraceAppcastURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? ""
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var appUpdater: AppUpdater

    var body: some View {
        Button("Check for Updates…", action: appUpdater.checkForUpdates)
            .disabled(!appUpdater.canCheckForUpdates)
    }
}
