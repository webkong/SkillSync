import SwiftUI

struct AddAgentSheet: View {
    let onAdd: (CustomAgentInput) -> Void

    @State private var name = ""
    @State private var rawPath = ""
    @State private var linkType: LinkType = .directory
    @State private var pathValid = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Custom Agent")
                .font(.headline)
                .padding()

            Form {
                Section("Agent Information") {
                    TextField("Name (e.g. My Zed)", text: $name)
                }

                Section("Skills Path") {
                    HStack {
                        TextField("~/path/to/agent/skills", text: $rawPath)
                            .onChange(of: rawPath) { _, newValue in
                                validatePath(newValue)
                            }

                        Button("Browse...") {
                            showFilePicker()
                        }
                    }

                    if !rawPath.isEmpty {
                        HStack {
                            Image(systemName: pathValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(pathValid ? .green : .red)
                            Text(expandedPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Section("Link Type") {
                    Picker("Type", selection: $linkType) {
                        ForEach(LinkType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(linkType.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Agent") {
                    let input = CustomAgentInput(
                        name: name,
                        skillsPath: rawPath,
                        linkType: linkType
                    )
                    onAdd(input)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || !pathValid)
            }
            .padding()
        }
        .frame(width: 450, height: 380)
    }

    private var expandedPath: String {
        CoreBridge.shared.expandPath(rawPath)
    }

    private func validatePath(_ path: String) {
        let expanded = CoreBridge.shared.expandPath(path)
        var isDir: ObjCBool = false
        pathValid = FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) && isDir.boolValue
    }

    private func showFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = linkType == .singleFile
        panel.canChooseDirectories = linkType != .singleFile
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            var path = url.path
            if path.hasPrefix(home) {
                path = "~" + path.dropFirst(home.count)
            }
            rawPath = path
        }
    }
}
