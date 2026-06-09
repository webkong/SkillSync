import SwiftUI

struct SkillsListView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all
    @State private var skillToDelete: SkillEntry? = nil

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
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Skill list
            if filteredSkills.isEmpty {
                ContentUnavailableView(
                    "No Skills",
                    systemImage: "puzzlepiece.extension",
                    description: Text(searchText.isEmpty ? "Add skills to your source directory" : "No skills match your search")
                )
            } else {
                List {
                    ForEach(filteredSkills) { skill in
                        SkillRowView(skill: skill, onDelete: {
                            skillToDelete = skill
                        })
                    }
                }
                .listStyle(.inset)
            }

            // Status bar
            HStack {
                Text("\(filteredSkills.count) skills")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .alert("Delete Skill", isPresented: Binding(
            get: { skillToDelete != nil },
            set: { if !$0 { skillToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                skillToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let skill = skillToDelete {
                    appState.deleteSkill(skillId: skill.id)
                    skillToDelete = nil
                }
            }
        } message: {
            if let skill = skillToDelete {
                Text("This will delete \"\(skill.manifest.name)\" and remove all agent links. This action cannot be undone.")
            }
        }
    }

    private var filteredSkills: [SkillEntry] {
        var result = appState.skills

        if !searchText.isEmpty {
            result = result.filter {
                $0.manifest.name.localizedCaseInsensitiveContains(searchText) ||
                $0.manifest.description.localizedCaseInsensitiveContains(searchText)
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

// MARK: - Skill Row

struct SkillRowView: View {
    let skill: SkillEntry
    let onDelete: () -> Void

    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.manifest.name)
                        .fontWeight(.medium)
                    Text(skill.manifest.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Agent toggle buttons
                HStack(spacing: 4) {
                    ForEach(appState.agents) { agent in
                        let isLinked = agent.linkedSkills.contains(skill.id)
                        Button {
                            appState.toggleSkillLink(
                                skillId: skill.id,
                                agentId: agent.id,
                                enabled: !isLinked
                            )
                        } label: {
                            Text(agent.name)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isLinked ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                                .foregroundStyle(isLinked ? .green : .secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete skill")
            }

            // Tags
            if !skill.manifest.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(skill.manifest.tags, id: \.self) { tag in
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
