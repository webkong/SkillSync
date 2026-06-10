import SwiftUI

struct OrganizePromptView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Organize Skills")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 10) {
                Text("Your Skills are currently scattered across different Agent directories. Organizing will move Skill files to the unified source directory (~/.agent/skills) and create symlinks at their original locations, so all Agents continue working normally.")

                Text("After organizing, you can:")
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 4) {
                    BulletPoint("Manage all Skills in one central location")
                    BulletPoint("Easily share Skills between Agents")
                    BulletPoint("Use Git for version control of your Skills")
                }
            }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button("Skip") {
                    appState.dismissOrganizePrompt()
                }
                .keyboardShortcut(.cancelAction)

                Button("Organize Now") {
                    appState.organizeAll()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct BulletPoint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
            Text(text)
        }
    }
}
