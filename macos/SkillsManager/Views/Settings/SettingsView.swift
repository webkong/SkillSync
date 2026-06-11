import SwiftUI

// MARK: - Agent Visibility Store

enum AgentVisibilityStore {
    static let defaultsKey = "visibleAgents"
    static let defaultVisible: Set<String> = ["claude-code", "codex"]

    static func visibleSet(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func rawValue(from visible: Set<String>, allSources: [String]) -> String {
        allSources.filter { visible.contains($0) }.joined(separator: ",")
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @AppStorage("sourceRoot") private var sourceRoot = ""
    @AppStorage(AgentVisibilityStore.defaultsKey) private var visibleAgentsRaw = AgentVisibilityStore.defaultVisible.sorted().joined(separator: ",")

    @ObservedObject private var appState = AppState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                generalSection
                agentsSection
            }
            .padding(20)
        }
    }

    // MARK: - General Section

    private var generalSection: some View {
        SettingsCard(title: "General") {
            VStack(alignment: .leading, spacing: 12) {
                sourceRootSection
            }
        }
    }

    private var sourceRootSection: some View {
        SettingsCard(title: "Skills Source Directory") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("~/path/to/skills", text: $sourceRoot)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            if sourceRoot.isEmpty {
                                let home = FileManager.default.homeDirectoryForCurrentUser.path
                                sourceRoot = "~/.agent/skills"
                            }
                        }

                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false

                        if panel.runModal() == .OK, let url = panel.url {
                            let home = FileManager.default.homeDirectoryForCurrentUser.path
                            var path = url.path
                            if path.hasPrefix(home) {
                                path = "~" + path.dropFirst(home.count)
                            }
                            sourceRoot = path
                        }
                    }
                }

                Text("This directory contains your skill definitions (each skill in its own subdirectory with SKILL.md)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Agents Tab

    private var agentsSection: some View {
        SettingsCard(title: "Agent Visibility") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select which agents appear in the Skills list. Dimmed agents have no local skills directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(itemSpacing: 8, rowSpacing: 8) {
                    ForEach(sortedAgents, id: \.id) { agent in
                        agentChip(agent: agent)
                    }
                }
            }
        }
    }

    private var sortedAgents: [AgentConfig] {
        appState.agents.sorted { a, b in
            if a.exists != b.exists { return a.exists } // existing first
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func agentChip(agent: AgentConfig) -> some View {
        let isVisible = visibleAgentIds.contains(agent.id)

        return Button {
            toggleAgent(agent.id)
        } label: {
            HStack(spacing: 5) {
                if agent.exists {
                    Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                } else {
                    Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                }
                Text(agent.name)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isVisible ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(agent.exists ? (isVisible ? .primary : .secondary) : .tertiary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isVisible ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .opacity(agent.exists ? 1.0 : 0.45)
    }

    private var visibleAgentIds: Set<String> {
        AgentVisibilityStore.visibleSet(from: visibleAgentsRaw)
    }

    private func toggleAgent(_ id: String) {
        var visible = visibleAgentIds
        if visible.contains(id) {
            visible.remove(id)
        } else {
            visible.insert(id)
        }
        visibleAgentsRaw = AgentVisibilityStore.rawValue(from: visible, allSources: appState.agents.map(\.id))
    }
}

// MARK: - SettingsCard

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    let itemSpacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, maxWidth: proposal.width ?? .infinity)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            if index > 0, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + rowSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + itemSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    private func layout(sizes: [CGSize], maxWidth: CGFloat) -> CGSize {
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0

        for size in sizes {
            if lineWidth + size.width > maxWidth && lineWidth > 0 {
                totalWidth = max(totalWidth, lineWidth)
                totalHeight += lineHeight + rowSpacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += size.width + itemSpacing
            lineHeight = max(lineHeight, size.height)
        }
        totalWidth = max(totalWidth, lineWidth)
        totalHeight += lineHeight
        return CGSize(width: totalWidth, height: totalHeight)
    }
}
