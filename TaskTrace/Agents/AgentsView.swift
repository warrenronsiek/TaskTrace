import SwiftUI

struct AgentsView: View {
    @ObservedObject var navigationStore: TaskTraceNavigationStore
    @ObservedObject var agentActionsStore: AgentActionsStore
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var skillsStore: SkillsStore
    let onShowTimelineForActivity: (Int64, Date) -> Void
    @State private var isTransportLogExpanded = false
    @State private var draftMessagesByAgentActionID: [Int64: String] = [:]

    var body: some View {
        activeTabContent
        .tint(AppColors.accent)
        .navigationTitle("Agents")
        .task {
            await agentActionsStore.load()
            navigationStore.reconcileAgentSelection(agentActions: agentActionsStore.agentActions)
        }
        .onChange(of: agentActionsStore.agentActions.map(\.id)) { _, _ in
            navigationStore.reconcileAgentSelection(agentActions: agentActionsStore.agentActions)
        }
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch navigationStore.selectedAgentsTab {
        case .chat:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if agentActionsStore.isAdding || agentActionsStore.isEditing {
                        formCard
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                )
                            )
                    }

                    agentActionsChatCard
                }
                .padding(24)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.34, dampingFraction: 0.84), value: agentActionsStore.isAdding || agentActionsStore.isEditing)
            }
        case .connection:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    connectionStatusCard
                }
                .padding(24)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .setup:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    setupCard
                }
                .padding(24)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .mcp:
            MCPView(settingsStore: settingsStore)
        case .skills:
            SkillsView(
                skillsStore: skillsStore,
                onShowTimelineForActivity: onShowTimelineForActivity
            )
        }
    }

    private var setupCard: some View {
        let commandPath = Bundle.main.executableURL?.path ?? "/Applications/TaskTrace.app/Contents/MacOS/TaskTrace"
        let openClawSetupCommands = """
        git clone https://github.com/warrenronsiek/TaskTraceMCPPlugin.git
        cd TaskTraceMCPPlugin
        openclaw plugins install .
        openclaw mcp set tasktrace '{"command":"\(commandPath)","args":["--mcp-stdio"]}'
        openclaw config unset tools.allow
        openclaw gateway restart
        openclaw mcp list
        openclaw channels list
        """

        return VStack(alignment: .leading, spacing: 10) {
            Text("OpenClaw Setup")
                .font(Styles.Fonts.title3Semibold)

            Text("Install the native TaskTrace OpenClaw plugin, register the TaskTrace stdio MCP server separately, clear any stale legacy TaskTrace allowlist config, then restart the gateway and confirm the channel is linked before expecting agent actions to execute. OpenClaw exposes `tasktrace_search` plus the TaskTrace feed tools `tasktrace_get_active_day_overviews`, `tasktrace_get_high_level_activities`, `tasktrace_get_detailed_activities`, `tasktrace_list_resources`, `tasktrace_list_resource_templates`, and `tasktrace_read_resource`.")
                .foregroundStyle(AppColors.textSecondary)

            Text("These commands assume TaskTrace is installed from the signed DMG into /Applications. If you launch TaskTrace from another location, replace the binary path in the MCP registration command.")
                .foregroundStyle(AppColors.textSecondary)

            Text(openClawSetupCommands)
                .font(Styles.Fonts.bodyMonospaced)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(glassCard)
    }

    private var connectionStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text("Connection Status")
                    .font(Styles.Fonts.title3Semibold)

                Spacer()

                Button(isTransportLogExpanded ? "Collapse Log" : "Expand Log") {
                    isTransportLogExpanded.toggle()
                }
                .buttonStyle(.plain)
                .font(Styles.Fonts.footnoteSemibold)
                .foregroundStyle(AppColors.accent)
            }

            VStack(alignment: .leading, spacing: 14) {
                statusRow(title: "Listener", value: agentActionsStore.isListening ? "Running" : "Stopped")
                statusRow(title: "Connected Clients", value: "\(agentActionsStore.connectedClients)")
                statusRow(title: "Socket Path", value: agentActionsStore.socketPath, monospaced: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Transport Events")
                    .font(Styles.Fonts.footnoteSemibold)
                    .foregroundStyle(AppColors.textSecondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if agentActionsStore.transportEvents.isEmpty {
                            Text("No transport events yet.")
                                .font(Styles.Fonts.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(agentActionsStore.transportEvents) { event in
                                Text("\(event.timestamp.formatted(date: .omitted, time: .standard))  \(event.message)")
                                    .font(Styles.Fonts.footnoteMonospaced)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(height: isTransportLogExpanded ? 320 : 148)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(glassCard)
    }

    private func statusRow(title: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .font(Styles.Fonts.subheadlineSemibold)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 132, alignment: .leading)

            Text(value)
                .font(monospaced ? Styles.Fonts.footnoteMonospaced : Styles.Fonts.subheadlineSemibold)
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(agentActionsStore.isEditing ? "Edit Agent Action" : "New Agent Action")
                .font(Styles.Fonts.title3Semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Message")
                    .font(Styles.Fonts.footnoteSemibold)
                    .foregroundStyle(AppColors.textSecondary)

                TextField(
                    "Tell OpenClaw what to do when TaskTrace summarizes a new activity.",
                    text: $agentActionsStore.currentInstructions,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(5...10)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let errorMessage = agentActionsStore.errorMessage {
                Text(errorMessage)
                    .font(Styles.Fonts.footnote)
                    .foregroundStyle(AppColors.danger)
            }

            HStack(spacing: 10) {
                Button(agentActionsStore.isEditing ? "Save Agent Action" : "Add Agent Action") {
                    Task { await agentActionsStore.saveCurrentAgentAction() }
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Button("Cancel") {
                    agentActionsStore.isEditing ? agentActionsStore.cancelEditing() : agentActionsStore.cancelAdding()
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(glassCard)
    }

    private var agentActionsChatCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Agent Actions")
                .font(Styles.Fonts.headline)

            if agentActionsStore.agentActions.isEmpty {
                VStack(spacing: 14) {
                    Text("No agent actions configured.")
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    addActionButton
                }
                .padding(.vertical, 24)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(agentActionsStore.agentActions, id: \.id) { agentAction in
                                let isSelected = navigationStore.selectedAgentActionID == agentAction.id

                                Button {
                                    navigationStore.selectAgentAction(agentAction.id)
                                } label: {
                                    Text(agentTabTitle(agentAction))
                                        .font(Styles.Fonts.footnoteSemibold)
                                        .lineLimit(1)
                                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.07))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.white.opacity(isSelected ? 0.22 : 0.12), lineWidth: 0.8)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    addActionButton
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

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(selectedAgentAction.instructions)
                                    .font(Styles.Fonts.headline)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)

                            HStack(spacing: 8) {
                                Button {
                                    agentActionsStore.startEditing(agentActionID: selectedAgentAction.id)
                                } label: {
                                    Image(systemName: "pencil")
                                        .frame(width: 16, height: 16)
                                }
                                .controlSize(.regular)
                                .buttonStyle(.bordered)

                                Button(role: .destructive) {
                                    Task { await agentActionsStore.deleteAgentAction(id: selectedAgentAction.id) }
                                } label: {
                                    Image(systemName: "trash")
                                        .frame(width: 16, height: 16)
                                }
                                .controlSize(.regular)
                                .buttonStyle(.bordered)
                                .tint(AppColors.danger)
                            }
                        }

                        VStack(spacing: 0) {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    if agentActionsStore.conversationHistory(for: selectedAgentAction.id).isEmpty {
                                        Text("No chat history yet.")
                                            .font(Styles.Fonts.footnote)
                                            .foregroundStyle(AppColors.textSecondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        ForEach(agentActionsStore.conversationHistory(for: selectedAgentAction.id).reversed()) { entry in
                                            chatBubble(for: entry)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 340, maxHeight: 520)

                            Divider()
                                .overlay(Color.white.opacity(0.1))

                            HStack(alignment: .bottom, spacing: 10) {
                                TextField(
                                    "Message this agent thread…",
                                    text: draftBinding(for: selectedAgentAction.id),
                                    axis: .vertical
                                )
                                .textFieldStyle(.plain)
                                .lineLimit(1...5)
                                .submitLabel(.send)
                                .onSubmit(sendSelectedAgentMessage)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .disabled(!agentActionsStore.agentsEnabled)

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
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                                }
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(glassCard)
    }

    private var addActionButton: some View {
        Button {
            agentActionsStore.startAdding()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))

                Text("Add Action")
                    .font(Styles.Fonts.footnoteSemibold)
            }
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private var selectedAgentAction: AgentActionRecord? {
        guard let selectedAgentActionID = navigationStore.selectedAgentActionID else {
            return agentActionsStore.agentActions.first
        }

        return agentActionsStore.agentActions.first(where: { $0.id == selectedAgentActionID })
    }

    private func agentTabTitle(_ agentAction: AgentActionRecord) -> String {
        let trimmedInstructions = agentAction.instructions.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedInstructions.isEmpty else {
            return "No message"
        }

        return String(trimmedInstructions.prefix(48))
    }

    private func draftBinding(for agentActionID: Int64) -> Binding<String> {
        Binding(
            get: { draftMessagesByAgentActionID[agentActionID, default: ""] },
            set: { draftMessagesByAgentActionID[agentActionID] = $0 }
        )
    }

    private func sendButtonEnabled(for agentActionID: Int64) -> Bool {
        agentActionsStore.agentsEnabled
            && !(draftMessagesByAgentActionID[agentActionID, default: ""])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }

    private func chatBubble(for entry: AgentChannelActor.ChatEntry) -> some View {
        let parsedMessage = AgentChatMessageParser.parse(entry)

        return VStack(alignment: entry.direction == .outbound ? .trailing : .leading, spacing: 6) {
            HStack(spacing: 8) {
                if entry.direction == .outbound {
                    Spacer(minLength: 0)
                }

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

                Text(parsedMessage.label)
                    .font(Styles.Fonts.footnoteSemibold)
                    .foregroundStyle(AppColors.textPrimary)

                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                    .font(Styles.Fonts.footnoteMonospacedDigit)
                    .foregroundStyle(AppColors.textSecondary)

                if entry.direction == .inbound {
                    Spacer(minLength: 0)
                }
            }

            Text(parsedMessage.content)
                .font(Styles.Fonts.subheadline)
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: entry.direction == .outbound ? .trailing : .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(entry.direction == .outbound ? AppColors.accent.opacity(0.16) : AppColors.insetBackground)
                )
        }
        .frame(maxWidth: .infinity, alignment: entry.direction == .outbound ? .trailing : .leading)
    }

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8)
            }
    }
}

extension AgentsView {
    enum Tab: String, CaseIterable, Identifiable {
        case chat
        case skills
        case connection
        case setup
        case mcp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chat:
                "Chat"
            case .skills:
                "Skills"
            case .connection:
                "Connection"
            case .setup:
                "Setup"
            case .mcp:
                "MCP"
            }
        }
    }
}
