import SwiftUI

struct MCPView: View {
    @ObservedObject var settingsStore: SettingsStore
    @State private var selectedConfiguration = MCPClientConfiguration.claudeMarketplace

    var body: some View {
        let commandPath = Bundle.main.executableURL?.path ?? "/Applications/TaskTrace.app/Contents/MacOS/TaskTrace"
        let selectedConfigurationText = switch selectedConfiguration {
        case .claudeMarketplace:
            """
            git clone https://github.com/warrenronsiek/TaskTrace.git
            cd TaskTrace/TaskTraceMCPPlugin

            # Then run inside Claude Code:
            /plugin marketplace add .
            /plugin install tasktrace-mcp@tasktrace-mcp
            /reload-plugins
            /mcp
            """
        case .claudeCodeMCP:
            "claude mcp add --transport stdio --scope user tasktrace -- \(commandPath) \(Vars.mcpStdioLaunchArgument)"
        case .codexMCP:
            "codex mcp add tasktrace \(commandPath) \(Vars.mcpStdioLaunchArgument)"
        case .openClaw:
            """
            git clone https://github.com/warrenronsiek/TaskTrace.git
            cd TaskTrace/TaskTraceMCPPlugin
            openclaw plugins install .
            openclaw mcp set tasktrace '{"command":"\(commandPath)","args":["\(Vars.mcpStdioLaunchArgument)"]}'
            openclaw config set tools.profile '"full"' --strict-json
            openclaw config unset tools.allow
            openclaw gateway restart
            openclaw mcp list
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
                                    Text("For OpenClaw, `openclaw plugins install .` installs the native TaskTrace MCP plugin. `openclaw mcp set ...` registers the TaskTrace stdio MCP server. `openclaw config unset tools.allow` clears stale upgrade-era allowlists. OpenClaw exposes `tasktrace_search`, `tasktrace_graph_search`, `tasktrace_add_todo`, `tasktrace_add_goal`, and `tasktrace_push_message`, plus the TaskTrace feed tools `tasktrace_get_active_day_overviews`, `tasktrace_get_high_level_activities`, `tasktrace_get_detailed_activities`, `tasktrace_list_resources`, `tasktrace_list_resource_templates`, and `tasktrace_read_resource`.")
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
                        )
                    )

                    MCPResourceRow(
                        title: "High Level Activity Feed",
                        description: "Publishes recent completed activities with top-level summaries only. This feed is lagged and has a low risk of exposing sensitive data.",
                        uri: Vars.mcpHighLevelActivityResourceURI,
                        isOn: Binding(
                            get: { settingsStore.mcpConfiguration.highLevelActivityResourceEnabled },
                            set: settingsStore.setHighLevelActivityResourceEnabled
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
                        warning: "Warning! Enabling will introduce sensitive data to your agents! FAFO 😉"
                    )

                    MCPResourceRow(
                        title: "Today Todos Feed",
                        description: "Publishes the current day's todos with status, repeat settings, daily targets, goal linkage, and tracked duration.",
                        uri: Vars.mcpTodayTodosResourceURI,
                        isOn: Binding(
                            get: { settingsStore.mcpConfiguration.todayTodosResourceEnabled },
                            set: settingsStore.setTodayTodosResourceEnabled
                        )
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Published Tools")
                        .font(Styles.Fonts.headline)

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

                    MCPToolRow(
                        title: "Add Todo",
                        description: "Lets an agent create an open todo for today, optionally attached to an existing goal with repeat and daily target settings.",
                        name: Vars.mcpAddTodoToolName,
                        parameters: """
                        name: string
                        goal_id: number (optional)
                        repeating: boolean (optional, default false)
                        target_date: string (optional, YYYY-MM-DD, default today)
                        daily_target_minutes: number (optional)
                        daily_target_mode: string (optional, minimum or maximum)
                        """,
                        isOn: Binding(
                            get: { settingsStore.mcpConfiguration.addTodoToolEnabled },
                            set: settingsStore.setAddTodoToolEnabled
                        )
                    )

                    MCPToolRow(
                        title: "Add Goal",
                        description: "Lets an agent create a goal with a name and optional description.",
                        name: Vars.mcpAddGoalToolName,
                        parameters: """
                        name: string
                        description: string (optional)
                        """,
                        isOn: Binding(
                            get: { settingsStore.mcpConfiguration.addGoalToolEnabled },
                            set: settingsStore.setAddGoalToolEnabled
                        )
                    )

                    MCPToolRow(
                        title: "Push Message",
                        description: "Lets an agent show a macOS notification through the running TaskTrace app without creating saved messages.",
                        name: Vars.mcpPushMessageToolName,
                        parameters: """
                        message: string
                        title: string (optional, default TaskTrace)
                        source: string (optional)
                        """,
                        isOn: Binding(
                            get: { settingsStore.mcpConfiguration.pushMessageToolEnabled },
                            set: settingsStore.setPushMessageToolEnabled
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
        HStack(alignment: .center, spacing: 18) {
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
    let warning: String?

    init(
        title: String,
        description: String,
        uri: String,
        isOn: Binding<Bool>,
        warning: String? = nil
    ) {
        self.title = title
        self.description = description
        self.uri = uri
        self._isOn = isOn
        self.warning = warning
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
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

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)

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
