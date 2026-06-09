import SwiftUI

struct AgentsListView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agents")
                    .font(.headline)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Agent", systemImage: "plus")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if appState.agents.isEmpty {
                ContentUnavailableView(
                    "No Agents",
                    systemImage: "rectangle.stack",
                    description: Text("Add an agent to manage its skills")
                )
            } else {
                List {
                    ForEach(appState.agents) { agent in
                        AgentRowView(agent: agent)
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Text("\(appState.agents.count) agents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .sheet(isPresented: $showAddSheet) {
            AddAgentSheet { input in
                _ = appState.addCustomAgent(input)
                showAddSheet = false
            }
        }
    }
}

// MARK: - Agent Row

struct AgentRowView: View {
    let agent: AgentConfig

    @ObservedObject private var appState = AppState.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: agent.icon ?? "puzzlepiece")
                .frame(width: 28, height: 28)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(agent.name)
                        .fontWeight(.medium)
                    if !agent.isBuiltin {
                        Text("Custom")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                Text(agent.skillsPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text("\(agent.linkedSkills.count) skills")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quinary, in: Capsule())
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Show in Finder") {
                let expanded = CoreBridge.shared.expandPath(agent.skillsPath)
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: expanded)
            }
            if !agent.isBuiltin {
                Divider()
                Button("Delete", role: .destructive) {
                    appState.removeCustomAgent(agent.id)
                }
            }
        }
    }
}
