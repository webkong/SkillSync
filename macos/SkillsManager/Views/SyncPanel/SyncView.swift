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
    @State private var isCheckingConnectivity = false

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

    private var repoPlaceholder: String {
        if provider == .other {
            return "https://git.example.com/user/skills-repo"
        }
        return "https://\(provider.host)/user/skills-repo"
    }

    private var isConnected: Bool {
        appState.gitConnectivity?.status == "connected"
    }

    private var isDisconnected: Bool {
        appState.gitConnectivity?.status == "disconnected"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sync")
                    .font(.headline)
                Spacer()
                connectivityDot
                Button {
                    showAuthSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
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
                    checkConnectivity()
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

                    HStack(spacing: 12) {
                        Button {
                            checkConnectivity()
                            appState.pullChanges()
                        } label: {
                            Label("Pull", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(repoURL.isEmpty || !tokenSaved)

                        Button {
                            checkConnectivity()
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

    @ViewBuilder
    private var connectivityDot: some View {
        if isCheckingConnectivity {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Checking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 4)
        } else if isConnected {
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.green)
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 4)
        } else if isDisconnected {
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.red)
                Text("Disconnected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 4)
        }
    }

    private func checkConnectivity() {
        isCheckingConnectivity = true
        appState.checkGitConnectivity()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isCheckingConnectivity = false
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
    var onSave: (() -> Void)?

    @AppStorage("syncToken_github") private var tokenGithub = ""
    @AppStorage("syncToken_gitlab") private var tokenGitlab = ""
    @AppStorage("syncToken_other") private var tokenOther = ""
    @AppStorage("syncTokenSaved_github") private var tokenSavedGithub = false
    @AppStorage("syncTokenSaved_gitlab") private var tokenSavedGitlab = false
    @AppStorage("syncTokenSaved_other") private var tokenSavedOther = false
    @AppStorage("syncCustomHost") private var customHost = ""
    @Environment(\.dismiss) private var dismiss
    @State private var showTokenHelp = false

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

    @ViewBuilder
    private var tokenHelpContent: some View {
        switch currentProvider {
        case .github:
            VStack(alignment: .leading, spacing: 10) {
                Text("How to create a GitHub Token")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    HelpStep("1", "Go to github.com/settings/tokens")
                    HelpStep("2", "Click Generate new token \u{2192} Classic")
                    HelpStep("3", "Select scope: repo (full control)")
                    HelpStep("4", "Copy the token and paste it here")
                }
                Divider()
                Text("For private repos, the token must have repo scope.\nFor organization repos, enable SSO for the token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 280)
        case .gitlab:
            VStack(alignment: .leading, spacing: 10) {
                Text("How to create a GitLab Token")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    HelpStep("1", "Go to gitlab.com/-/user_settings/personal_access_tokens")
                    HelpStep("2", "Give it a name and expiration date")
                    HelpStep("3", "Select scopes: read_repository, write_repository")
                    HelpStep("4", "Copy the token and paste it here")
                }
            }
            .padding(16)
            .frame(width: 280)
        case .other:
            VStack(alignment: .leading, spacing: 10) {
                Text("How to create a Token")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    HelpStep("1", "Log in to your self-hosted Git server")
                    HelpStep("2", "Go to Settings \u{2192} Access Tokens")
                    HelpStep("3", "Create a token with api/repo access")
                    HelpStep("4", "Copy the token and paste it here")
                }
            }
            .padding(16)
            .frame(width: 280)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Authorization")
                .font(.title2)
                .fontWeight(.bold)

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

            if currentProvider == .other {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Git Server Host")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("git.your-company.com", text: $customHost)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("\(currentProvider.rawValue) Personal Access Token")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Button {
                        showTokenHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showTokenHelp) {
                        tokenHelpContent
                    }
                }

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
                        if !tokenGithub.isEmpty { tokenSavedGithub = true }
                    case .gitlab:
                        if !tokenGitlab.isEmpty { tokenSavedGitlab = true }
                    case .other:
                        if !tokenOther.isEmpty { tokenSavedOther = true }
                    }
                    onSave?()
                    dismiss()
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

// MARK: - Token Help

struct HelpStep: View {
    let number: String
    let text: String

    init(_ number: String, _ text: String) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
