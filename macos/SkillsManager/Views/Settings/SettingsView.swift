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
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            agentsTab
                .tabItem { Label("Agents", systemImage: "rectangle.stack") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 480)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.title)
                    .fontWeight(.bold)

                sourceRootSection
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
                                sourceRoot = "\(home)/.agent/skills"
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

    private var agentsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Agent Visibility")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Select which agents appear in the Skills list. Only visible agents can have skills linked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingsCard(title: "Visible Agents") {
                    FlowLayout(itemSpacing: 8, rowSpacing: 8) {
                        ForEach(appState.agents, id: \.id) { agent in
                            agentChip(agent: agent)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func agentChip(agent: AgentConfig) -> some View {
        let isVisible = visibleAgentIds.contains(agent.id)

        return Button {
            toggleAgent(agent.id)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                Text(agent.name)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isVisible ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isVisible ? .primary : .secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isVisible ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
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

    // MARK: - About Tab

    private var aboutTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("About")
                    .font(.title)
                    .fontWeight(.bold)

                SettingsCard(title: "Agent Skills Manager") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Version", value: "0.1.0")
                        LabeledContent("Build", value: "1")
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
