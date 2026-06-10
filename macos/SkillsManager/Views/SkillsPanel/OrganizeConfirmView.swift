import SwiftUI

/// Confirmation dialog before organizing all skills.
struct OrganizeConfirmView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Organize All Skills?")
                .font(.title2)
                .fontWeight(.bold)

            Text("This will move all skill files to the unified source directory (~/.agent/skills) and create symlinks at their original locations. All agents will continue to work normally.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Cancel") {
                    appState.showOrganizeConfirm = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Organize") {
                    appState.organizeAll()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
