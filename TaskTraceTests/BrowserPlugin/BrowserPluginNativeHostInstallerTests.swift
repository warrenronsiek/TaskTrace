//
//  BrowserPluginNativeHostInstallerTests.swift
//  TaskTraceTests
//

import Foundation
import Testing
@testable import TaskTrace

struct BrowserPluginNativeHostInstallerTests {
    private func nativeHostManifest(at manifestURL: URL) throws -> [String: Any] {
        let manifestData = try Data(contentsOf: manifestURL)
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return manifest
    }

    private func withInstallSandbox(
        _ block: (URL, URL, URL, URL) throws -> Void
    ) throws {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let supportDirectoryURL = rootURL
            .appendingPathComponent("support", isDirectory: true)
            .appendingPathComponent("TaskTrace", isDirectory: true)
            .appendingPathComponent("BrowserPlugin", isDirectory: true)
            .appendingPathComponent("NativeMessaging", isDirectory: true)
        let chromeNativeMessagingHostsDirectoryURL = rootURL
            .appendingPathComponent("home", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Google", isDirectory: true)
            .appendingPathComponent("Chrome", isDirectory: true)
            .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        let hostScriptURL = supportDirectoryURL
            .appendingPathComponent("tasktrace-browser-plugin-host.sh", isDirectory: false)
        let manifestURL = chromeNativeMessagingHostsDirectoryURL
            .appendingPathComponent("\(Vars.browserPluginHostName).json", isDirectory: false)

        try BrowserPluginNativeHostInstaller.install(
            supportDirectoryURL: supportDirectoryURL,
            chromeNativeMessagingHostsDirectoryURL: chromeNativeMessagingHostsDirectoryURL
        )

        try block(supportDirectoryURL, chromeNativeMessagingHostsDirectoryURL, hostScriptURL, manifestURL)
        try? fileManager.removeItem(at: rootURL)
    }

    @Test("native host installer writes the launcher script")
    func nativeHostInstallerWritesTheLauncherScript() throws {
        try withInstallSandbox { _, _, hostScriptURL, _ in
            #expect(FileManager.default.fileExists(atPath: hostScriptURL.path))
        }
    }

    @Test("native host installer makes the launcher script executable")
    func nativeHostInstallerMakesTheLauncherScriptExecutable() throws {
        try withInstallSandbox { _, _, hostScriptURL, _ in
            let permissions = try #require(
                try FileManager.default.attributesOfItem(atPath: hostScriptURL.path)[.posixPermissions]
                    as? NSNumber
            )
            #expect((permissions.intValue & 0o111) == 0o111)
        }
    }

    @Test("native host installer writes the Chrome manifest")
    func nativeHostInstallerWritesTheChromeManifest() throws {
        try withInstallSandbox { _, _, _, manifestURL in
            #expect(FileManager.default.fileExists(atPath: manifestURL.path))
        }
    }

    @Test("native host manifest whitelists the fixed browser plugin extension id")
    func nativeHostManifestWhitelistsTheFixedBrowserPluginExtensionID() throws {
        try withInstallSandbox { _, _, _, manifestURL in
            let manifest = try nativeHostManifest(at: manifestURL)
            let allowedOrigins = try #require(manifest["allowed_origins"] as? [String])
            #expect(allowedOrigins == ["chrome-extension://\(Vars.browserPluginExtensionID)/"])
        }
    }

    @Test("native host manifest points to the installed launcher script")
    func nativeHostManifestPointsToTheInstalledLauncherScript() throws {
        try withInstallSandbox { _, _, hostScriptURL, manifestURL in
            let manifest = try nativeHostManifest(at: manifestURL)
            let path = try #require(manifest["path"] as? String)
            #expect(path == hostScriptURL.path)
        }
    }

    @Test("native host manifest uses the browser plugin host name expected by Chrome")
    func nativeHostManifestUsesTheBrowserPluginHostNameExpectedByChrome() throws {
        try withInstallSandbox { _, _, _, manifestURL in
            let manifest = try nativeHostManifest(at: manifestURL)
            let hostName = try #require(manifest["name"] as? String)
            #expect(hostName == Vars.browserPluginHostName)
        }
    }
}
