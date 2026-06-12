import SwiftUI

struct SkillDetailView: View {
    let skill: OrganizedSkill
    @State private var skillMDContent: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(skill.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Paths
                VStack(alignment: .leading, spacing: 8) {
                    pathRow(
                        label: "Current Path",
                        path: skill.sourceDir,
                        systemImage: "folder"
                    )

                    // Source path: the linked_agents list may have source info
                    ForEach(skill.linkedAgentsList.filter { $0.isSource }, id: \.agentId) { link in
                        pathRow(
                            label: "Source (\(agentName(for: link.agentId)))",
                            path: link.path,
                            systemImage: "house"
                        )
                    }
                }

                Divider()

                // Version & Tags
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version: \(skill.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !skill.tagsList.isEmpty {
                        HStack(spacing: 4) {
                            Text("Tags:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

                Divider()

                // SKILL.md content
                VStack(alignment: .leading, spacing: 4) {
                    Text("SKILL.md")
                        .font(.headline)

                    if skillMDContent.isEmpty {
                        Text("No content")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(skillMDContent)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            loadSkillMD()
        }
        .onChange(of: skill.id) { _ in
            loadSkillMD()
        }
    }

    // MARK: - Helpers

    private func pathRow(label: String, path: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.caption)
                    Text(path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "arrow.up.forward.app")
                        .font(.caption2)
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
    }

    private func agentName(for agentId: String) -> String {
        AppState.shared.agents.first(where: { $0.id == agentId })?.name ?? agentId
    }

    private func loadSkillMD() {
        let skillMDPath = (skill.sourceDir as NSString).appendingPathComponent("SKILL.md")
        if let content = try? String(contentsOfFile: skillMDPath, encoding: .utf8) {
            skillMDContent = content
        } else {
            skillMDContent = ""
        }
    }
}
