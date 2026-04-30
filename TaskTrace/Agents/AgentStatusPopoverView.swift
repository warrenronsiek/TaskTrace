import SwiftUI

struct AgentStatusPopoverView: View {
    @ObservedObject var activityStore: ActivityStore
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var agentActionsStore: AgentActionsStore
    let onToggleRecording: () -> Void
    let onSetAgentsEnabled: (Bool) -> Void
    let onOpenTaskTrace: () -> Void
    let onQuitTaskTrace: () -> Void

    @State private var selectedAgentActionID: Int64?
    @State private var draftMessagesByAgentActionID: [Int64: String]

    init(
        activityStore: ActivityStore,
        settingsStore: SettingsStore,
        agentActionsStore: AgentActionsStore,
        onToggleRecording: @escaping () -> Void,
        onSetAgentsEnabled: @escaping (Bool) -> Void,
        onOpenTaskTrace: @escaping () -> Void,
        onQuitTaskTrace: @escaping () -> Void
    ) {
        self.activityStore = activityStore
        self.settingsStore = settingsStore
        self.agentActionsStore = agentActionsStore
        self.onToggleRecording = onToggleRecording
        self.onSetAgentsEnabled = onSetAgentsEnabled
        self.onOpenTaskTrace = onOpenTaskTrace
        self.onQuitTaskTrace = onQuitTaskTrace
        self._selectedAgentActionID = State(initialValue: agentActionsStore.agentActions.first?.id)
        self._draftMessagesByAgentActionID = State(initialValue: [:])
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 12) {
                    Button {
                        onToggleRecording()
                    } label: {
                        Image(systemName: activityStore.isRecording ? "stop.fill" : "play.fill")
                            .font(.system(size: 46, weight: .semibold))
                        .frame(width: 138, height: 138)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(activityStore.isRecording ? AppColors.recordActive : AppColors.recordIdle)
                    .disabled(activityStore.playStopButtonDisabled)

                    Text(activityStore.isRecording ? "Recording" : "Stopped")
                    .font(Styles.Fonts.headline)
                    .foregroundStyle(AppColors.textPrimary)
                }
                .frame(width: 150, alignment: .topLeading)
                .layoutPriority(1)

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { settingsStore.agentsEnabled },
                            set: { onSetAgentsEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable Agents")
                                    .font(Styles.Fonts.headline)
                                Text(agentStatusText)
                                    .font(Styles.Fonts.footnote)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                    )

                    HStack(spacing: 10) {
                        Button {
                            onOpenTaskTrace()
                        } label: {
                            Image("TrayIcon")
                                .resizable()
                                .scaledToFit()
                                .padding(12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                        )

                        Button {
                            onQuitTaskTrace()
                        } label: {
                            Image(systemName: "power")
                                .font(.system(size: 22, weight: .semibold))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundStyle(AppColors.textPrimary)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if agentActionsStore.agentActions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No Agent Actions")
                        .font(Styles.Fonts.headline)
                    Text("Create agent actions in the main TaskTrace window to start per-agent chat threads here.")
                        .font(Styles.Fonts.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                )
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(agentActionsStore.agentActions, id: \.id) { agentAction in
                                let isSelected = selectedAgentActionID == agentAction.id
                                let tabTitle = agentTabTitle(agentAction)
                                let foregroundColor = isSelected ? AppColors.textPrimary : AppColors.textSecondary
                                let backgroundColor = isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.08)
                                let borderColor = Color.white.opacity(isSelected ? 0.26 : 0.12)

                                Button {
                                    selectedAgentActionID = agentAction.id
                                } label: {
                                    Text(tabTitle)
                                        .font(Styles.Fonts.footnoteSemibold)
                                        .foregroundStyle(foregroundColor)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(backgroundColor)
                                        )
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .strokeBorder(borderColor, lineWidth: 0.8)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let selectedAgentAction {
                        let sendSelectedAgentMessage = {
                            let draftMessage = draftMessagesByAgentActionID[selectedAgentAction.id, default: ""]
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                            guard !draftMessage.isEmpty else {
                                return
                            }

                            draftMessagesByAgentActionID[selectedAgentAction.id] = ""
                            Task {
                                await agentActionsStore.sendChatMessage(
                                    agentActionID: selectedAgentAction.id,
                                    text: draftMessage
                                )
                            }
                        }

                        VStack(spacing: 0) {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(agentActionsStore.conversationHistory(for: selectedAgentAction.id).reversed()) { entry in
                                        chatBubble(for: entry)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            Divider()
                                .overlay(Color.white.opacity(0.1))

                            HStack(alignment: .bottom, spacing: 10) {
                                TextField(
                                    "Message this agent thread…",
                                    text: draftBinding(for: selectedAgentAction.id),
                                    axis: .vertical
                                )
                                .textFieldStyle(.plain)
                                .lineLimit(1...4)
                                .submitLabel(.send)
                                .onSubmit(sendSelectedAgentMessage)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .disabled(!settingsStore.agentsEnabled)

                                Button {
                                    sendSelectedAgentMessage()
                                } label: {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 28))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(sendButtonEnabled(for: selectedAgentAction.id) ? AppColors.accent : AppColors.textSecondary.opacity(0.5))
                                .disabled(!sendButtonEnabled(for: selectedAgentAction.id))
                            }
                            .padding(12)
                        }
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: 430, height: 620, alignment: .topLeading)
        .background(Color.clear)
        .onAppear {
            if selectedAgentActionID == nil {
                selectedAgentActionID = agentActionsStore.agentActions.first?.id
            }
        }
        .onChange(of: agentActionsStore.agentActions.map(\.id)) { _, ids in
            guard let firstID = ids.first else {
                selectedAgentActionID = nil
                return
            }

            if !ids.contains(selectedAgentActionID ?? -1) {
                selectedAgentActionID = firstID
            }
        }
    }

    private var agentStatusText: String {
        if !settingsStore.agentsEnabled {
            return "Disabled. TaskTrace will not keep the local OpenClaw socket open."
        }

        if agentActionsStore.connectedClients > 0 {
            return "Connected to OpenClaw."
        }

        if agentActionsStore.isListening {
            return "Waiting for OpenClaw to connect."
        }

        return "Listener stopped."
    }

    private var selectedAgentAction: AgentActionRecord? {
        guard let selectedAgentActionID else {
            return agentActionsStore.agentActions.first
        }

        return agentActionsStore.agentActions.first(where: { $0.id == selectedAgentActionID })
    }

    private func agentTabTitle(_ agentAction: AgentActionRecord) -> String {
        let trimmedInstructions = agentAction.instructions.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedInstructions.isEmpty {
            return "Agent Action"
        }

        return String(trimmedInstructions.prefix(18))
    }

    private func draftBinding(for agentActionID: Int64) -> Binding<String> {
        Binding(
            get: { draftMessagesByAgentActionID[agentActionID, default: ""] },
            set: { draftMessagesByAgentActionID[agentActionID] = $0 }
        )
    }

    private func sendButtonEnabled(for agentActionID: Int64) -> Bool {
        settingsStore.agentsEnabled &&
        agentActionsStore.connectedClients > 0 &&
        !draftMessagesByAgentActionID[agentActionID, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func chatBubble(for entry: AgentChannelActor.ChatEntry) -> some View {
        let parsedMessage = AgentChatMessageParser.parse(entry)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(parsedMessage.label)
                    .font(Styles.Fonts.footnoteSemibold)
                    .foregroundStyle(AppColors.textPrimary)

                if let importance = parsedMessage.importance {
                    Text(importance.uppercased())
                        .font(Styles.Fonts.footnoteMonospacedDigit)
                        .foregroundStyle(importance == "high" ? AppColors.danger : AppColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }

                Spacer()

                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(Styles.Fonts.footnoteMonospacedDigit)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Text(parsedMessage.content)
                .font(Styles.Fonts.subheadline)
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(entry.direction == .inbound ? Color.white.opacity(0.12) : Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
    }

}
