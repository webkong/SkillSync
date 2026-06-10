import SwiftUI

struct AgentIconView: View {
    let agentId: String
    let size: CGFloat

    var body: some View {
        if let image = logoImage() {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "puzzlepiece")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.6, height: size * 0.6)
                .frame(width: size, height: size)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func logoImage() -> NSImage? {
        let fileName = logoFileName(for: agentId)
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "svg")
                ?? Bundle.main.url(forResource: fileName, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func logoFileName(for id: String) -> String {
        switch id {
        case "claude-code": return "claude-code"
        case "cursor": return "cursor"
        case "codex": return "codex"
        case "windsurf": return "windsurf"
        case "openclaw": return "openclaw"
        case "opencode": return "opencode"
        case "gemini": return "gemini"
        case "codebuddy": return "codebuddy"
        case "kiro": return "kiro"
        case "qoder": return "qoder"
        case "hermes": return "hermes"
        default: return id
        }
    }
}
