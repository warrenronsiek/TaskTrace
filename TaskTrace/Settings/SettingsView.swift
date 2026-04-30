//
//  SettingsView.swift
//  TaskTrace
//
//  Created by Codex on 3/12/26.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var appUpdater: AppUpdater

    var body: some View {
        Form {
            Section("Permissions") {
                Text("TaskTrace needs Accessibility and Screen Recording permission to capture keystrokes and screenshots. Microphone and Speech Recognition are only needed when background audio capture is enabled.")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.textSecondary)

                PermissionRow(
                    title: "Accessibility",
                    subtitle: "Required for global keystroke capture.",
                    isGranted: settingsStore.permissionStatus.accessibilityGranted,
                    requestTitle: "Request Accessibility"
                ) {
                    Task {
                        await settingsStore.requestPermission(.accessibility)
                    }
                } openSettings: {
                    settingsStore.openSystemSettings(for: .accessibility)
                }

                PermissionRow(
                    title: "Screen Recording",
                    subtitle: "Required for screenshot capture.",
                    isGranted: settingsStore.permissionStatus.screenRecordingGranted,
                    requestTitle: "Request Screen Recording"
                ) {
                    Task {
                        await settingsStore.requestPermission(.screenRecording)
                    }
                } openSettings: {
                    settingsStore.openSystemSettings(for: .screenRecording)
                }

                PermissionRow(
                    title: "Microphone",
                    subtitle: "Required for background audio capture.",
                    isGranted: settingsStore.permissionStatus.microphoneGranted,
                    requestTitle: "Request Microphone"
                ) {
                    Task {
                        await settingsStore.requestPermission(.microphone)
                    }
                } openSettings: {
                    settingsStore.openSystemSettings(for: .microphone)
                }

                PermissionRow(
                    title: "Speech Recognition",
                    subtitle: "Required for live on-device voice transcription.",
                    isGranted: settingsStore.permissionStatus.speechRecognitionGranted,
                    requestTitle: "Request Speech Recognition"
                ) {
                    Task {
                        await settingsStore.requestPermission(.speechRecognition)
                    }
                } openSettings: {
                    settingsStore.openSystemSettings(for: .speechRecognition)
                }

                HStack {
                    Button("Request Missing Permissions") {
                        Task {
                            await settingsStore.requestMissingPermissionsIfNeeded()
                        }
                    }

                    Button("Refresh Status") {
                        settingsStore.refreshPermissions()
                    }
                }
                .font(.system(size: 17, weight: .medium))
                .controlSize(.large)
            }
            
            Section("Recording") {
                Toggle(
                    "Capture background audio while recording",
                    isOn: Binding(
                        get: { settingsStore.microphoneCaptureEnabled },
                        set: settingsStore.setMicrophoneCaptureEnabled
                    )
                )
                .font(.system(size: 17, weight: .medium))
                .controlSize(.large)

                Text("TaskTrace can transcribe both your microphone and system audio while you record, which is powerful and invasive.")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.textSecondary)

                Toggle(
                    "Launch TaskTrace at login",
                    isOn: Binding(
                        get: { settingsStore.launchAtLoginEnabled },
                        set: settingsStore.setLaunchAtLoginEnabled
                    )
                )
                .font(.system(size: 17, weight: .medium))
                .controlSize(.large)

                Text("When enabled, TaskTrace starts automatically when you sign in to your Mac.")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.textSecondary)

                if settingsStore.launchAtLoginStatus == .requiresApproval {
                    HStack(spacing: 12) {
                        Text("Finish enabling TaskTrace in System Settings > General > Login Items.")
                            .font(.system(size: 17))
                            .foregroundStyle(AppColors.textSecondary)

                        Button("Open Login Items") {
                            settingsStore.openLaunchAtLoginSystemSettings()
                        }
                    }
                    .controlSize(.large)
                }

                Toggle(
                    "Start recording when TaskTrace launches",
                    isOn: Binding(
                        get: { settingsStore.autoRecordOnLaunchEnabled },
                        set: settingsStore.setAutoRecordOnLaunchEnabled
                    )
                )
                .font(.system(size: 17, weight: .medium))
                .controlSize(.large)

                Text("When enabled, TaskTrace begins recording automatically as soon as the app launches.")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Section("Updates") {
                Text("TaskTrace can check for new app updates and download them automatically.")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.textSecondary)

                if !appUpdater.currentVersion.isEmpty {
                    LabeledContent("Current version", value: appUpdater.currentVersion)
                        .font(.system(size: 17))
                }

                if appUpdater.isConfigured {
                    Toggle(
                        "Automatically check for updates",
                        isOn: Binding(
                            get: { appUpdater.automaticallyChecksForUpdates },
                            set: appUpdater.setAutomaticallyChecksForUpdates
                        )
                    )
                    .font(.system(size: 17, weight: .medium))
                    .controlSize(.large)

                    Toggle(
                        "Automatically download updates",
                        isOn: Binding(
                            get: { appUpdater.automaticallyDownloadsUpdates },
                            set: appUpdater.setAutomaticallyDownloadsUpdates
                        )
                    )
                    .font(.system(size: 17, weight: .medium))
                    .controlSize(.large)
                    .disabled(!appUpdater.automaticallyChecksForUpdates)

                    CheckForUpdatesButton(appUpdater: appUpdater)
                        .controlSize(.large)
                } else {
                    Text("Updates are disabled until `SUPublicEDKey` is configured with the Sparkle public key.")
                        .font(.system(size: 17))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .formStyle(.grouped)
        .tint(AppColors.accent)
        .navigationTitle("Settings")
        .onAppear {
            settingsStore.refreshPermissions()
            settingsStore.refreshLaunchAtLoginStatus()
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let subtitle: String
    let isGranted: Bool
    let requestTitle: String
    let requestAccess: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isGranted ? AppColors.success : AppColors.danger)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Text(isGranted ? "Granted" : "Missing")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }

            if !isGranted {
                HStack(spacing: 12) {
                    Button("Open System Settings", action: openSettings)
                    Button(requestTitle, action: requestAccess)
                }
                .font(.system(size: 17, weight: .medium))
                .controlSize(.large)
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}
