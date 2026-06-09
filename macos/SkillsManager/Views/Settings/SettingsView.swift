import SwiftUI

struct SettingsView: View {
    @AppStorage("sourceRoot") private var sourceRoot = ""

    var body: some View {
        TabView {
            Form {
                Section("Skills Source Directory") {
                    HStack {
                        TextField("~/path/to/skills", text: $sourceRoot)
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

                    Text("This directory contains your skill definitions (each skill in its own subdirectory with SKILL.md and manifest.json)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding()
            .tabItem {
                Label("General", systemImage: "gear")
            }

            Form {
                Section("About") {
                    LabeledContent("Version", value: "0.1.0")
                    LabeledContent("Build", value: "1")
                }
            }
            .formStyle(.grouped)
            .padding()
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 450, height: 300)
    }
}
