import SwiftUI

struct AboutView: View {
    @State private var isCheckingUpdate = false
    @State private var updateMessage: String?

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("About")
                    .font(.system(size: 24, weight: .bold))

                SettingsCard(title: "SkillSync") {
                    VStack(spacing: 6) {
                        settingsRow("Version", "v\(appVersion) (\(buildNumber))")
                        Divider()
                        settingsRow("Engine", "SkillSync Engine (Rust)")
                        Divider()
                        settingsRow("Storage", "SQLite \u{00b7} local-only")
                        Divider()
                        HStack {
                            Text("Repository")
                                .font(.system(size: 13))
                            Spacer()
                            Button("webkong/SkillSync") {
                                if let u = URL(string: "https://github.com/webkong/SkillSync") {
                                    NSWorkspace.shared.open(u)
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                        }
                    }
                }

                SettingsCard(title: "Updates") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Software Update")
                                    .font(.system(size: 13))
                                if let msg = updateMessage, !msg.isEmpty {
                                    Text(updateMessage!)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            updateActionView
                        }
                    }
                }
            }
            .padding(20)

            Text("Copyright \u{00a9} 2026 webkong. All rights reserved.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
            Button("skillsync.webkong.top") {
                if let u = URL(string: "https://skillsync.webkong.top") {
                    NSWorkspace.shared.open(u)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func settingsRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var updateActionView: some View {
        if isCheckingUpdate {
            ProgressView()
                .controlSize(.small)
        } else {
            Button("Check Now") { checkForUpdates() }
        }
    }

    private func checkForUpdates() {
        isCheckingUpdate = true
        updateMessage = nil
        guard let url = URL(string: "https://api.github.com/repos/webkong/SkillSync/releases/latest") else {
            isCheckingUpdate = false
            updateMessage = "Invalid update URL"
            return
        }
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isCheckingUpdate = false
                if let error = error {
                    updateMessage = "Update check failed: \(error.localizedDescription)"
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    updateMessage = "Could not parse update info"
                    return
                }
                let latestVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                if compareVersion(latestVersion, appVersion) > 0 {
                    updateMessage = "Update available: v\(latestVersion)"
                } else {
                    updateMessage = "You're up to date (v\(appVersion))"
                }
            }
        }.resume()
    }

    private func compareVersion(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
}
