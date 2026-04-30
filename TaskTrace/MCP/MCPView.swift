import SwiftUI

struct MCPView: View {
    @ObservedObject var settingsStore: SettingsStore
    @State private var selectedConfiguration = MCPClientConfiguration.claudeMarketplace

    var body: some View {
        let commandPath = Bundle.main.executableURL?.path ?? "/Applications/TaskTrace.app/Contents/MacOS/TaskTrace"
        let selectedConfigurationText = switch selectedConfiguration {
        case .claudeMarketplace:
            """
            /plugin marketplace add warrenronsiek/TaskTraceMCPPlugin
            /plugin install tasktrace-mcp@tasktrace-mcp
            """
        case .claudeCodeMCP:
            "claude mcp add --transport stdio --scope user tasktrace -- \(commandPath) \(Vars.mcpStdioLaunchArgument)"
        case .codexMCP:
            "codex mcp add tasktrace \(commandPath) \(Vars.mcpStdioLaunchArgument)"
        case .openClaw:
            """
            git clone https://github.com/warrenronsiek/TaskTraceMCPPlugin.git
            cd TaskTraceMCPPlugin
            openclaw plugins install .
            openclaw mcp set tasktrace '{"command":"\(commandPath)","args":["\(Vars.mcpStdioLaunchArgument)"]}'
            openclaw config set tools.profile '"full"' --strict-json
            openclaw config unset tools.allow
            openclaw gateway restart
            openclaw mcp list
            openclaw channels list
            openclaw plugins inspect tasktrace-mcp
            """
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("TaskTrace can expose local MCP resources over standard input and output when another app launches it.")
                        .font(Styles.Fonts.title3Semibold)

                    Text("Use this page to decide whether MCP is enabled and which feeds and tools external AI clients can use from your machine.")
                        .foregroundStyle(AppColors.textSecondary)

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 14) {
                        GridRow {
                            MCPHeaderLabel(text: "Enable MCP Server")

                            Toggle(
                                "Enable MCP Server",
                                isOn: Binding(
                                    get: { settingsStore.mcpConfiguration.serverEnabled },
                                    set: settingsStore.setServerEnabled
                                )
                            )
                            .labelsHidden()
                                .toggleStyle(.switch)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GridRow(alignment: .top) {
                            MCPHeaderLabel(text: "Config Format")

                            HStack(spacing: 6) {
                                ForEach(MCPClientConfiguration.allCases) { configuration in
                                    Button(configuration.title) {
                                        selectedConfiguration = configuration
                                    }
                                    .buttonStyle(.plain)
                                    .font(Styles.Fonts.subheadlineSemibold)
                                    .foregroundStyle(
                                        selectedConfiguration == configuration
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary
                                    )
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(
                                                selectedConfiguration == configuration
                                                ? Color.white.opacity(0.16)
                                                : Color.clear
                                            )
                                    )
                                }
                            }
                            .padding(4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                                    }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GridRow(alignment: .top) {
                            MCPHeaderLabel(text: "Setup Commands")

                            VStack(alignment: .leading, spacing: 10) {
                                Text(selectedConfigurationText)
                                    .font(Styles.Fonts.bodyMonospaced)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.white.opacity(0.08))
                                    )

                                if selectedConfiguration == .openClaw {
                                    Text("For OpenClaw, `openclaw plugins install .` installs the native TaskTrace channel plugin. `openclaw mcp set ...` separately registers the TaskTrace stdio MCP server. `openclaw config unset tools.allow` clears stale upgrade-era allowlists. OpenClaw exposes both retrieval tools, `tasktrace_search` and `tasktrace_graph_search`, plus the TaskTrace feed tools `tasktrace_get_active_day_overviews`, `tasktrace_get_high_level_activities`, `tasktrace_get_detailed_activities`, `tasktrace_list_resources`, `tasktrace_list_resource_templates`, and `tasktrace_read_resource`.")
                                        .font(Styles.Fonts.footnote)
                                        .foregroundStyle(AppColors.textSecondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.26), lineWidth: 0.8)
                        }
                )

                VStack(alignment: .leading, spacing: 14) {
                    Text("Published Feeds")
                        .font(Styles.Fonts.headline)

                    MCPResourceRow(
                        title: "Overview Feed",
                        description: "Publishes the active day overview titles, summaries, and durations after activities have been grouped into overviews. Near zero risk of sensitive data exposure.",
                        uri: Vars.mcpOverviewResourceURI,
                        isOn: Binding(
                            get: { settingsStore.mcpConfiguration.overviewResourceEnabled },
                            set: settingsStore.setOverviewResourceEnabled
                        ),
                        count: .constant(nil)
                    )

                    MCPResourceRow(
                        title: "High Level Activity Feed",
                        description: "Publishes recent completed activities with top-level summaries only. This feed is lagged and has a low risk of exposing sensitive data.",
                        uri: Vars.mcpHighLevelActivityResourceURI,
                        isOn: Binding(
                            get: { settingsStore.mcpConfiguration.highLevelActivityResourceEnabled },
                            set: settingsStore.setHighLevelActivityResourceEnabled
                        ),
                        count: Binding(
                            get: { settingsStore.mcpConfiguration.highLevelActivityCount },
                            set: settingsStore.setHighLevelActivityCount
                        )
                    )

                    MCPResourceRow(
                        title: "Detailed Activity Feed",
                        description: "Publishes the eager recent-activity feed, including incomplete activities, keystrokes, transcript text, summaries, screenshots, and ocr.",
                        uri: """
                        \(Vars.mcpDetailedActivityResourceURI)
                        \(Vars.mcpActivityScreenshotResourceTemplateURI)
                        """,
                        isOn: Binding(
                            get: { settingsStore.mcpConfiguration.detailedActivityResourceEnabled },
                            set: settingsStore.setDetailedActivityResourceEnabled
                        ),
                        count: Binding(
                            get: { settingsStore.mcpConfiguration.detailedActivityCount },
                            set: settingsStore.setDetailedActivityCount
                        ),
                        warning: "Warning! Enabling will introduce sensitive data to your agents! FAFO 😉"
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Published Tools")
                        .font(Styles.Fonts.headline)

                    Text("Graph Search uses the knowledge directory currently selected in TaskTrace.")
                        .font(Styles.Fonts.footnote)
                        .foregroundStyle(AppColors.textSecondary)

                    MCPToolRow(
                        title: "Activity Search",
                        description: "Exposes activity search over TaskTrace data and returns ranked relevant descriptions of matching overviews, activities, and screenshots without generating a summary.",
                        name: Vars.mcpSearchToolName,
                        parameters: """
                        query: string
                        limit: number (optional, default 10, max 50)
                        """,
                        isOn: Binding(
                            get: { settingsStore.mcpConfiguration.searchToolEnabled },
                            set: settingsStore.setSearchToolEnabled
                        )
                    )

                    MCPToolRow(
                        title: "Graph Search",
                        description: "Exposes graph search over persisted knowledge communities, nodes, claims, and internal graph context for the currently selected knowledge directory. It returns ranked graph evidence without generating a summary.",
                        name: Vars.mcpGraphRAGToolName,
                        parameters: """
                        query: string
                        limit: number (optional, default 3, max 10)
                        """,
                        isOn: Binding(
                            get: { settingsStore.mcpConfiguration.graphSearchToolEnabled },
                            set: settingsStore.setGraphSearchToolEnabled
                        )
                    )
                }
                .opacity(settingsStore.mcpConfiguration.serverEnabled ? 1 : 0.6)
            }
            .padding(24)
        }
        .tint(AppColors.accent)
    }
}

private struct MCPToolRow: View {
    let title: String
    let description: String
    let name: String
    let parameters: String
    var showsToggle = true
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Styles.Fonts.headline)

                Text(description)
                    .foregroundStyle(AppColors.textSecondary)

                Text(name)
                    .font(Styles.Fonts.footnoteMonospaced)
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)

                Text(parameters)
                    .font(Styles.Fonts.footnoteMonospaced)
                    .foregroundStyle(AppColors.textSecondary)
                    .textSelection(.enabled)
            }
            .opacity(isOn ? 1 : 0.6)

            Spacer(minLength: 12)

            if showsToggle {
                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            } else {
                Text(isOn ? "Enabled" : "Disabled")
                    .font(Styles.Fonts.footnoteSemibold)
                    .foregroundStyle(isOn ? AppColors.textPrimary : AppColors.textSecondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                }
        )
    }
}

private enum MCPClientConfiguration: CaseIterable, Identifiable {
    case claudeMarketplace
    case claudeCodeMCP
    case codexMCP
    case openClaw

    var id: Self { self }

    var title: String {
        switch self {
        case .claudeMarketplace:
            "Claude Plugin"
        case .claudeCodeMCP:
            "Claude MCP"
        case .codexMCP:
            "Codex MCP"
        case .openClaw:
            "OpenClaw"
        }
    }
}

private struct MCPHeaderLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Styles.Fonts.subheadlineSemibold)
            .foregroundStyle(AppColors.textSecondary)
            .frame(width: 150, alignment: .leading)
    }
}

private struct MCPResourceRow: View {
    let title: String
    let description: String
    let uri: String
    @Binding var isOn: Bool
    @Binding var count: Int?
    let warning: String?

    init(
        title: String,
        description: String,
        uri: String,
        isOn: Binding<Bool>,
        count: Binding<Int?>,
        warning: String? = nil
    ) {
        self.title = title
        self.description = description
        self.uri = uri
        self._isOn = isOn
        self._count = count
        self.warning = warning
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Styles.Fonts.headline)

                Text(description)
                    .foregroundStyle(AppColors.textSecondary)

                Text(uri)
                    .font(Styles.Fonts.footnoteMonospaced)
                    .foregroundStyle(AppColors.textSecondary)
                    .textSelection(.enabled)

                if let warning {
                    Text(warning)
                        .font(Styles.Fonts.footnoteSemibold)
                        .foregroundStyle(AppColors.danger)
                }
            }

            Spacer(minLength: 12)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Items")
                            .font(Styles.Fonts.subheadlineSemibold)

                        Text(count.map(String.init) ?? "All")
                            .font(Styles.Fonts.subheadlineSemibold)
                            .foregroundStyle(isOn ? AppColors.textPrimary : AppColors.textSecondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(count ?? 11) },
                            set: { count = Int($0.rounded()) == 11 ? nil : Int($0.rounded()) }
                        ),
                        in: 1...11,
                        step: 1
                    )
                    .frame(width: 220)
                    .disabled(!isOn)

                    HStack {
                        Text("1")
                        Spacer()
                        Text("All")
                    }
                    .frame(width: 220)
                    .font(Styles.Fonts.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .opacity(isOn ? 1 : 0.55)
                }
                .opacity(isOn ? 1 : 0.55)

                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .frame(maxWidth: 320, alignment: .trailing)

        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                }
        )
    }
}
