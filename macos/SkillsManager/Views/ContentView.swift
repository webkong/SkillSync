import SwiftUI

struct ContentView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var selectedTab: SidebarTab = .skills

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } content: {
            contentArea
                .navigationSplitViewColumnWidth(min: 400, ideal: 500)
        } detail: {
            detailArea
        }
        .sheet(item: $appState.pendingNewSkill) { skill in
            NewSkillSheet(skill: skill) { agentIds in
                appState.enableNewSkill(forAgentIds: agentIds)
            } onDismiss: {
                appState.dismissNewSkill()
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedTab) {
            Label("Skills", systemImage: "puzzlepiece.extension")
                .tag(SidebarTab.skills)
            Label("Agents", systemImage: "rectangle.stack")
                .tag(SidebarTab.agents)
            Label("Sync", systemImage: "arrow.triangle.merge")
                .tag(SidebarTab.sync)
        }
        .listStyle(.sidebar)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch selectedTab {
        case .skills:
            SkillsListView()
        case .agents:
            AgentsListView()
        case .sync:
            SyncView()
        }
    }

    // MARK: - Detail Area

    @ViewBuilder
    private var detailArea: some View {
        switch selectedTab {
        case .skills:
            if let skill = appState.selectedSkill {
                SkillDetailView(skill: skill)
            } else {
                Text("Select a skill to view details")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        case .sync:
            if !appState.pendingChanges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pending Changes")
                        .font(.headline)
                    ForEach(appState.pendingChanges) { change in
                        HStack {
                            Image(systemName: change.changeType == "added" ? "plus.circle" :
                                    change.changeType == "deleted" ? "minus.circle" : "pencil.circle")
                                .foregroundStyle(.secondary)
                            Text(change.filePath)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                .padding()
            } else {
                Text("Select a skill or agent to view details")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        default:
            Text("Select a skill or agent to view details")
                .foregroundStyle(.secondary)
                .padding()
        }
    }

    enum SidebarTab: String, CaseIterable {
        case agents, skills, sync
    }
}

// MARK: - New Skill Sheet

struct NewSkillSheet: View {
    let skill: SkillEntry
    let onEnable: ([String]) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var appState = AppState.shared
    @AppStorage(AgentVisibilityStore.defaultsKey) private var visibleAgentsRaw = AgentVisibilityStore.defaultVisible.sorted().joined(separator: ",")

    @State private var selectedAgents: Set<String> = []

    private var visibleAgents: [AgentConfig] {
        let visibleIds = AgentVisibilityStore.visibleSet(from: visibleAgentsRaw)
        return appState.agents.filter { visibleIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("New Skill Detected")
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(skill.manifest.name)
                    .font(.headline)
                Text(skill.manifest.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                if !skill.manifest.tags.isEmpty {
                    HStack {
                        ForEach(skill.manifest.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))

            Text("Enable for:")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(visibleAgents) { agent in
                let isCompatible = skill.manifest.compatibleAgents.contains("*") ||
                    skill.manifest.compatibleAgents.contains(agent.id)
                HStack {
                    Text(agent.name)
                        .foregroundStyle(isCompatible ? .primary : .secondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { selectedAgents.contains(agent.id) },
                        set: { enabled in
                            if enabled {
                                selectedAgents.insert(agent.id)
                            } else {
                                selectedAgents.remove(agent.id)
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!isCompatible)
                }
                .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button("Skip") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Enable Selected") {
                    onEnable(Array(selectedAgents))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedAgents.isEmpty)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 400, height: 400)
        .onAppear {
            // Pre-select compatible agents
            for agent in appState.agents {
                let isCompatible = skill.manifest.compatibleAgents.contains("*") ||
                    skill.manifest.compatibleAgents.contains(agent.id)
                if isCompatible {
                    selectedAgents.insert(agent.id)
                }
            }
        }
    }
}
