import SwiftUI

struct AboutView: View {
    @State private var isCheckingUpdate = false
    @State private var updateMessage: String? = nil

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // App header
                    VStack(spacing: 8) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 64))
                            .foregroundStyle(.blue)
                        Text("Agent Skills Manager")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Manage AI agent skills across multiple platforms")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    // Version
                    GroupBox {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Version")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(appVersion) (\(buildNumber))")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }

                            Divider()

                            Button {
                                checkForUpdates()
                            } label: {
                                HStack {
                                    if isCheckingUpdate {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                    }
                                    Text("Check for Updates")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .disabled(isCheckingUpdate)

                            if let msg = updateMessage {
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                    }

                    // Author
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("webkong")
                                        .fontWeight(.medium)
                                    Link("github.com/webkong", destination: URL(string: "https://github.com/webkong")!)
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(12)
                    }

                    // License
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text.fill")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("MIT License")
                                        .fontWeight(.medium)
                                    Text("Copyright © 2026 webkong. All rights reserved.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Divider()

                            Text("Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.")

                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                    }
                }
                .padding(20)
            }
        }
    }

    private func checkForUpdates() {
        isCheckingUpdate = true
        updateMessage = nil
        // Check GitHub releases API for latest version
        guard let url = URL(string: "https://api.github.com/repos/webkong/AgentSkillsManager/releases/latest") else {
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
                if latestVersion > appVersion {
                    updateMessage = "Update available: \(latestVersion)"
                } else {
                    updateMessage = "You're up to date"
                }
            }
        }.resume()
    }
}
