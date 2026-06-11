import SwiftUI

enum GitProvider: String, CaseIterable {
    case github = "GitHub"
    case gitlab = "GitLab"
    case other = "Other"

    var host: String {
        switch self {
        case .github: return "github.com"
        case .gitlab: return "gitlab.com"
        case .other: return ""
        }
    }

    var hostPlaceholder: String {
        switch self {
        case .github: return "github.com"
        case .gitlab: return "gitlab.com"
        case .other: return "git.your-company.com"
        }
    }

    var tokenPlaceholder: String {
        switch self {
        case .github: return "ghp_xxxxxxxxxxxx"
        case .gitlab: return "glpat-xxxxxxxxxxxxxx"
        case .other: return "Personal access token"
        }
    }

    var icon: String {
        switch self {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .gitlab: return "fox"
        case .other: return "server.rack"
        }
    }
}

struct SyncView: View {
    @ObservedObject private var appState = AppState.shared
    @AppStorage("syncRepoURL") private var repoURL = ""
    @AppStorage("syncProvider") private var providerRaw = GitProvider.github.rawValue
    @AppStorage("syncToken_github") private var tokenGithub = ""
    @AppStorage("syncToken_gitlab") private var tokenGitlab = ""
    @AppStorage("syncToken_other") private var tokenOther = ""
    @AppStorage("syncTokenSaved_github") private var tokenSavedGithub = false
    @AppStorage("syncTokenSaved_gitlab") private var tokenSavedGitlab = false
    @AppStorage("syncTokenSaved_other") private var tokenSavedOther = false
    @State private var showAuthSheet = false

    private var provider: GitProvider {
        GitProvider(rawValue: providerRaw) ?? .github
    }

    private var tokenSaved: Bool {
        switch provider {
        case .github: return tokenSavedGithub
        case .gitlab: return tokenSavedGitlab
        case .other: return tokenSavedOther
        }
    }

    /// Compose repo URL placeholder based on provider
    private var repoPlaceholder: String {
        if provider == .other {
            return "https://git.example.com/user/skills-repo"
        }
        return "https://\(provider.host)/user/skills-repo"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sync")
                    .font(.headline)
                Spacer()
                Button {
                    showAuthSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: provider.icon)
                        Text(tokenSaved ? provider.rawValue : "Authorize")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tokenSaved ? Color.green.opacity(0.1) : Color.accentColor.opacity(0.1), in: Capsule())
                    .foregroundStyle(tokenSaved ? .green : .accentColor)
                }
                .buttonStyle(.plain)
                .quickHelp("Configure git provider and authorization")
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
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - Repository Config
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Repository")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            TextField(repoPlaceholder, text: $repoURL)
                                .textFieldStyle(.roundedBorder)

                            Text("Enter the \(provider.rawValue) repository URL where your skills are synced.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                    }

                    // MARK: - Status card
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

                    // MARK: - Pull & Push buttons
                    HStack(spacing: 12) {
                        Button {
                            appState.pullChanges()
                        } label: {
                            Label("Pull", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(repoURL.isEmpty || !tokenSaved)

                        Button {
                            appState.pushChanges()
                        } label: {
                            Label("Push", systemImage: "arrow.up.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(appState.gitStatus.status == "pushing" || repoURL.isEmpty || !tokenSaved)
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showAuthSheet) {
            AuthSheet(provider: $providerRaw)
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
            case "pushing", "pulling":
                ProgressView()
                    .scaleEffect(0.7)
            case "error":
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            default:
                Image(systemName: "circle.dashed")
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
        case "pulling": return "Pulling..."
        case "error": return "Error"
        default: return "Not Configured"
        }
    }
}

// MARK: - Auth Sheet

struct AuthSheet: View {
    @Binding var provider: String
    @AppStorage("syncToken_github") private var tokenGithub = ""
    @AppStorage("syncToken_gitlab") private var tokenGitlab = ""
    @AppStorage("syncToken_other") private var tokenOther = ""
    @AppStorage("syncTokenSaved_github") private var tokenSavedGithub = false
    @AppStorage("syncTokenSaved_gitlab") private var tokenSavedGitlab = false
    @AppStorage("syncTokenSaved_other") private var tokenSavedOther = false
    @AppStorage("syncCustomHost") private var customHost = ""
    @Environment(\.dismiss) private var dismiss

    private var currentProvider: GitProvider {
        GitProvider(rawValue: provider) ?? .github
    }

    private var tokenSaved: Bool {
        switch currentProvider {
        case .github: return tokenSavedGithub
        case .gitlab: return tokenSavedGitlab
        case .other: return tokenSavedOther
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Authorization")
                .font(.title2)
                .fontWeight(.bold)

            // Provider picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Git Provider")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("Provider", selection: $provider) {
                    ForEach(GitProvider.allCases, id: \.rawValue) { p in
                        Text(p.rawValue).tag(p.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Custom host for "Other" provider
            if currentProvider == .other {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Git Server Host")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("git.your-company.com", text: $customHost)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Token input — separate SecureField per provider
            VStack(alignment: .leading, spacing: 8) {
                Text("\(currentProvider.rawValue) Personal Access Token")
                    .font(.subheadline)
                    .fontWeight(.medium)

                switch currentProvider {
                case .github:
                    SecureField(currentProvider.tokenPlaceholder, text: $tokenGithub)
                        .textFieldStyle(.roundedBorder)
                case .gitlab:
                    SecureField(currentProvider.tokenPlaceholder, text: $tokenGitlab)
                        .textFieldStyle(.roundedBorder)
                case .other:
                    SecureField(currentProvider.tokenPlaceholder, text: $tokenOther)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield")
                            .font(.caption2)
                        Text("Token is stored locally and used only for git push/pull.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("Required scopes: repo (read/write)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if tokenSaved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Token saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if tokenSaved {
                    Button("Remove Token", role: .destructive) {
                        switch currentProvider {
                        case .github: tokenGithub = ""; tokenSavedGithub = false
                        case .gitlab: tokenGitlab = ""; tokenSavedGitlab = false
                        case .other: tokenOther = ""; tokenSavedOther = false
                        }
                    }
                }

                Button(tokenSaved ? "Update" : "Save") {
                    switch currentProvider {
                    case .github:
                        if !tokenGithub.isEmpty { tokenSavedGithub = true; dismiss() }
                    case .gitlab:
                        if !tokenGitlab.isEmpty { tokenSavedGitlab = true; dismiss() }
                    case .other:
                        if !tokenOther.isEmpty { tokenSavedOther = true; dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(
                    currentProvider == .github ? tokenGithub.isEmpty :
                    currentProvider == .gitlab ? tokenGitlab.isEmpty : tokenOther.isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 420, height: currentProvider == .other ? 380 : 320)
    }
}
