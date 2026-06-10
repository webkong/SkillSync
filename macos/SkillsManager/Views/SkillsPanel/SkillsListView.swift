import SwiftUI

struct SkillsListView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all

    var body: some View {
        VStack(spacing: 0) {
            // Search + Filter bar
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search skills...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 6))

                Picker("Filter", selection: $filterMode) {
                    ForEach(FilterMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Button {
                    appState.fetchAgentSkills()
                } label: {
                    HStack(spacing: 4) {
                        if appState.isLoading {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Fetch")
                    }
                }
                .disabled(appState.isLoading)
                .help("Scan all agent directories for skills")

                Button {
                    appState.organizeAll()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.gearshape")
                        Text("Organize")
                    }
                }
                .help("Move all skills to source directory and create symlinks")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Skill list
            if appState.organizedSkills.isEmpty {
                ContentUnavailableView(
                    "No Skills",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Click Fetch to scan agent directories")
                )
            } else {
                List {
                    ForEach(filteredSkills) { skill in
                        OrganizedSkillRowView(skill: skill)
                    }
                }
                .listStyle(.inset)
            }

            // Status bar
            HStack {
                Text("\(appState.organizedSkills.count) skills")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    private var filteredSkills: [OrganizedSkill] {
        var result = appState.organizedSkills

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch filterMode {
        case .all: break
        case .linked:
            result = result.filter { skill in
                appState.agents.contains { $0.linkedSkills.contains(skill.id) }
            }
        case .unlinked:
            result = result.filter { skill in
                !appState.agents.contains { $0.linkedSkills.contains(skill.id) }
            }
        }

        return result
    }

    enum FilterMode: String, CaseIterable {
        case all, linked, unlinked

        var label: String {
            switch self {
            case .all: return "All"
            case .linked: return "Linked"
            case .unlinked: return "Unlinked"
            }
        }
    }
}

// MARK: - Organized Skill Row

struct OrganizedSkillRowView: View {
    let skill: OrganizedSkill

    @ObservedObject private var appState = AppState.shared
    @AppStorage(AgentVisibilityStore.defaultsKey) private var visibleAgentsRaw = AgentVisibilityStore.defaultVisible.sorted().joined(separator: ",")

    private var visibleAgents: [AgentConfig] {
        let visibleIds = AgentVisibilityStore.visibleSet(from: visibleAgentsRaw)
        return appState.agents.filter { visibleIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Organize button (only for unorganized skills)
                if !skill.isOrganized {
                    Button {
                        appState.organizeSkill(skillId: skill.id, agentId: skill.agentSource)
                    } label: {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Move to source directory")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .fontWeight(.medium)
                    Text(skill.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    // Show source directory
                    Text(skill.sourceDir)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                // Agent toggle buttons
                HStack(spacing: 4) {
                    ForEach(visibleAgents) { agent in
                        let isLinked = agent.linkedSkills.contains(skill.id)
                        Button {
                            appState.toggleSkillLink(
                                skillId: skill.id,
                                agentId: agent.id,
                                enabled: !isLinked
                            )
                        } label: {
                            HStack(spacing: 3) {
                                AgentIconView(agentId: agent.id, size: 14)
                                Text(agent.name)
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isLinked ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                            .foregroundStyle(isLinked ? .green : .secondary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Tags
            if !skill.tagsList.isEmpty {
                HStack(spacing: 4) {
                    ForEach(skill.tagsList, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.08), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
