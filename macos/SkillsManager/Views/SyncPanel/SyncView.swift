import SwiftUI

struct SyncView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sync")
                    .font(.headline)
                Spacer()
                Button {
                    appState.refreshGitStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .quickHelp("Refresh status")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Status card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                statusIcon
                                Text(statusTitle)
                                    .font(.headline)
                            }

                            if let message = appState.gitStatus.message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }

                    // Pending changes
                    if !appState.pendingChanges.isEmpty {
                        GroupBox("Pending Changes") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(appState.pendingChanges) { change in
                                    HStack {
                                        Image(systemName: change.changeType == "added" ? "plus.circle.fill" :
                                                change.changeType == "deleted" ? "minus.circle.fill" : "pencil.circle.fill")
                                            .foregroundStyle(change.changeType == "added" ? .green :
                                                    change.changeType == "deleted" ? .red : .orange)
                                        Text(change.filePath)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(change.changeType.capitalized)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .padding(8)
                        }
                    }

                    // Push button
                    Button {
                        appState.pushChanges()
                    } label: {
                        Label("Sync & Push", systemImage: "arrow.up.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appState.gitStatus.status == "pushing")
                }
                .padding()
            }
        }
    }

    private var statusIcon: some View {
        Group {
            switch appState.gitStatus.status {
            case "synced":
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case "modified":
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            case "conflicted":
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case "pushing":
                ProgressView()
                    .scaleEffect(0.7)
            default:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title2)
    }

    private var statusTitle: String {
        switch appState.gitStatus.status {
        case "synced": return "Up to Date"
        case "modified": return "Changes Pending"
        case "conflicted": return "Merge Conflicts"
        case "pushing": return "Pushing..."
        case "error": return "Error"
        default: return "Idle"
        }
    }
}
