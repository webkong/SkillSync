import AppKit
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
                        if appState.isFetching {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Fetch")
                    }
                }
                .disabled(appState.isFetching)
                .quickHelp("Scan all agent directories for skills")

                Button {
                    appState.showOrganizeConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.gearshape")
                        Text("Organize")
                    }
                }
                .quickHelp("Move all skills to source directory and create symlinks")
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
                List(filteredSkills) { skill in
                    OrganizedSkillRowView(skill: skill)
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
    @State private var showDeleteConfirmation = false

    private let actionColumnWidth: CGFloat = 120
    private let agentsColumnWidth: CGFloat = 300

    private var visibleAgents: [AgentConfig] {
        let visibleIds = AgentVisibilityStore.visibleSet(from: visibleAgentsRaw)
        return appState.agents.filter { visibleIds.contains($0.id) }
    }

    /// Find the link info for a specific agent for this skill.
    private func linkInfo(for agentId: String) -> SkillAgentLink? {
        skill.linkedAgentsList.first { $0.agentId == agentId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    appState.selectedSkill = skill
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Text(skill.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        // Source tag or directory path
                        sourceIndicator
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                actionColumn
                    .frame(width: actionColumnWidth, alignment: .leading)

                agentsColumn
                    .frame(width: agentsColumnWidth, alignment: .leading)
            }

            // Tags row: manifest tags
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
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
            dimensions[.trailing]
        }
        .alert("Delete Skill?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                appState.deleteSkill(skillId: skill.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the skill files for \(skill.name) and remove all linked symlinks.")
        }
    }

    // MARK: - Action Button

    private var actionColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !skill.isOrganized || skill.isInSourceRoot {
                actionButton
            }
            deleteButton
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if !skill.isOrganized {
            // Organize button
            Button {
                appState.organizeSkill(skillId: skill.id, agentId: skill.agentSource)
            } label: {
                Label("Organize", systemImage: "arrow.triangle.swap")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(.blue)
                    .background(.blue.opacity(0.10), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(.blue.opacity(0.18), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .quickHelp("Move to source directory")
        } else if skill.isInSourceRoot {
            // Restore button (only when organized and in source root)
            Button {
                appState.restoreSkill(skillId: skill.id)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(.orange)
                    .background(.orange.opacity(0.10), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(.orange.opacity(0.18), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .quickHelp("Restore back to original agent directory")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(.red)
                .background(.red.opacity(0.10), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.red.opacity(0.18), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .quickHelp("Delete this skill and remove all linked symlinks")
    }

    private var agentsColumn: some View {
        AgentTagClusterView(
            agents: visibleAgents,
            maxWidth: agentsColumnWidth
        ) { agent in
            agentTag(for: agent)
        }
    }

    // MARK: - Source Indicator

    /// Find the agent name for a given agent ID.
    private func agentName(for agentId: String) -> String {
        appState.agents.first(where: { $0.id == agentId })?.name ?? agentId
    }

    @ViewBuilder
    private var sourceIndicator: some View {
        if skill.isInSourceRoot {
            HStack(spacing: 4) {
                Text("v\(skill.version)")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.gray.opacity(0.1), in: Capsule())
                    .foregroundStyle(.secondary)
                Text("Global")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.blue.opacity(0.1), in: Capsule())
                    .foregroundStyle(.blue)
                if skill.agentSource == "claude-code" {
                    Text("Claude Code")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.1), in: Capsule())
                        .foregroundStyle(.orange)
                        .quickHelp("This skill originated from Claude Code and may not be compatible with other agents")
                }
            }
        } else {
            HStack(spacing: 4) {
                Text("v\(skill.version)")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.gray.opacity(0.1), in: Capsule())
                    .foregroundStyle(.secondary)
                Text(agentName(for: skill.agentSource))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.gray.opacity(0.1), in: Capsule())
                    .foregroundStyle(.secondary)
                if skill.agentSource == "claude-code" {
                    Text("Claude Code")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.1), in: Capsule())
                        .foregroundStyle(.orange)
                        .quickHelp("This skill originated from Claude Code and may not be compatible with other agents")
                }
            }
        }
    }

    // MARK: - Agent Tag

    private func agentTag(for agent: AgentConfig) -> some View {
        let link = linkInfo(for: agent.id)
        let isLinked = link?.isSymlink == true
        let isSource = link?.isSource == true && link?.isSymlink == false

        return Button {
            if isLinked {
                // Click linked agent → remove symlink
                appState.toggleSkillLink(skillId: skill.id, agentId: agent.id, enabled: false)
            } else {
                // Click unlinked or source agent → create symlink
                appState.toggleSkillLink(skillId: skill.id, agentId: agent.id, enabled: true)
            }
        } label: {
            HStack(spacing: 3) {
                AgentIconView(agentId: agent.id, size: 14)
                Text(agent.name)
                    .font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tagBackground(isLinked: isLinked, isSource: isSource))
            .foregroundStyle(tagForeground(isLinked: isLinked, isSource: isSource))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .quickHelp(tagTooltip(isLinked: isLinked, isSource: isSource, agent: agent))
    }

    private func tagBackground(isLinked: Bool, isSource: Bool) -> Color {
        if isLinked {
            return Color.green.opacity(0.15)
        } else if isSource {
            return Color.purple.opacity(0.1)
        } else {
            return Color.gray.opacity(0.1)
        }
    }

    private func tagForeground(isLinked: Bool, isSource: Bool) -> Color {
        if isLinked {
            return .green
        } else if isSource {
            return .purple
        } else {
            return .secondary
        }
    }

    private func tagTooltip(isLinked: Bool, isSource: Bool, agent: AgentConfig) -> String {
        if isLinked {
            return "Click to remove symlink for \(agent.name)"
        } else if isSource {
            return "Source skill in \(agent.name) — click to create symlink"
        } else {
            return "Click to create symlink for \(agent.name)"
        }
    }
}

private struct AgentTagClusterView<Content: View>: View {
    let agents: [AgentConfig]
    let maxWidth: CGFloat
    let tagContent: (AgentConfig) -> Content

    private let itemSpacing: CGFloat = 4
    private let rowSpacing: CGFloat = 4

    var body: some View {
        let layout = AgentTagClusterLayout(
            agents: agents,
            maxWidth: maxWidth,
            itemSpacing: itemSpacing
        )

        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(Array(layout.rows.enumerated()), id: \.offset) { index, rowAgents in
                HStack(spacing: itemSpacing) {
                    ForEach(rowAgents) { agent in
                        tagContent(agent)
                    }

                    if index == layout.rows.count - 1, layout.hiddenCount > 0 {
                        Text("+\(layout.hiddenCount)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.gray.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentTagClusterLayout {
    let rows: [[AgentConfig]]
    let hiddenCount: Int

    init(agents: [AgentConfig], maxWidth: CGFloat, itemSpacing: CGFloat) {
        let badgeFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let badgeWidths = agents.map { agent in
            let textWidth = agent.name.size(withAttributes: [.font: badgeFont]).width
            return ceil(textWidth + 37)
        }

        var firstRow: [AgentConfig] = []
        var secondRow: [AgentConfig] = []
        var firstWidth: CGFloat = 0
        var secondWidth: CGFloat = 0
        var hidden = 0

        func rowWidth(_ current: CGFloat, adding itemWidth: CGFloat, isEmpty: Bool) -> CGFloat {
            isEmpty ? itemWidth : current + itemSpacing + itemWidth
        }

        func overflowWidth(for hiddenCount: Int) -> CGFloat {
            let text = "+\(hiddenCount)"
            let width = text.size(withAttributes: [.font: badgeFont]).width
            return ceil(width + 16)
        }

        for (index, agent) in agents.enumerated() {
            let itemWidth = badgeWidths[index]
            let remainingAfter = agents.count - index - 1

            let firstCandidate = rowWidth(firstWidth, adding: itemWidth, isEmpty: firstRow.isEmpty)
            let firstReserve = remainingAfter > 0 ? itemSpacing + overflowWidth(for: remainingAfter) : 0
            if firstCandidate + firstReserve <= maxWidth {
                firstRow.append(agent)
                firstWidth = firstCandidate
                continue
            }

            let secondCandidate = rowWidth(secondWidth, adding: itemWidth, isEmpty: secondRow.isEmpty)
            let secondReserve = remainingAfter > 0 ? itemSpacing + overflowWidth(for: remainingAfter) : 0
            if secondCandidate + secondReserve <= maxWidth {
                secondRow.append(agent)
                secondWidth = secondCandidate
                continue
            }

            hidden = agents.count - index
            break
        }

        let computedRows = [firstRow, secondRow].filter { !$0.isEmpty }
        rows = computedRows.isEmpty ? [[]] : computedRows
        hiddenCount = hidden
    }
}
