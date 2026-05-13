import SwiftUI

struct AgentsView: View {
    @ObservedObject var navigationStore: TaskTraceNavigationStore
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var skillsStore: SkillsStore
    let onShowTimelineForActivity: (Int64, Date) -> Void

    var body: some View {
        activeTabContent
            .tint(AppColors.accent)
            .navigationTitle("Agents")
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch navigationStore.selectedAgentsTab {
        case .skills:
            SkillsView(
                skillsStore: skillsStore,
                onShowTimelineForActivity: onShowTimelineForActivity
            )
        case .mcp:
            MCPView(settingsStore: settingsStore)
        }
    }
}

extension AgentsView {
    enum Tab: String, CaseIterable, Identifiable {
        case skills
        case mcp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .skills:
                "Skills"
            case .mcp:
                "MCP"
            }
        }
    }
}
