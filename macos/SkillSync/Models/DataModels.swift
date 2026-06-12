import Foundation

// MARK: - AgentConfig

struct AgentConfig: Codable, Identifiable {
    let id: String
    let name: String
    let skillsPath: String
    let linkType: LinkType
    let isBuiltin: Bool
    var isLinked: Bool
    var linkedSkills: [String]
    let icon: String?
    let exists: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, icon, exists
        case skillsPath = "skills_path"
        case linkType = "link_type"
        case isBuiltin = "is_builtin"
        case isLinked = "is_linked"
        case linkedSkills = "linked_skills"
    }
}

// MARK: - LinkType

enum LinkType: String, Codable, CaseIterable {
    case directory = "Directory"
    case singleFile = "SingleFile"
    case overlay = "Overlay"

    var displayName: String {
        switch self {
        case .directory: return "Directory"
        case .singleFile: return "Single File"
        case .overlay: return "Overlay"
        }
    }

    var description: String {
        switch self {
        case .directory:
            return "Symlink the entire skill directory to the agent's skills path"
        case .singleFile:
            return "Merge all SKILL.md files into a single file (for agents like Copilot)"
        case .overlay:
            return "Symlink individual files without overwriting existing content"
        }
    }
}

// MARK: - SkillEntry & SkillManifest

struct SkillEntry: Codable, Identifiable {
    let id: String
    let manifest: SkillManifest
    let sourceDir: String
    let installedAt: String

    enum CodingKeys: String, CodingKey {
        case id, manifest
        case sourceDir = "source_dir"
        case installedAt = "installed_at"
    }
}

struct SkillManifest: Codable {
    let name: String
    let description: String
    let tags: [String]
    let compatibleAgents: [String]
    let version: String

    enum CodingKeys: String, CodingKey {
        case name, description, tags, version
        case compatibleAgents = "compatible_agents"
    }
}

// MARK: - CustomAgentInput

struct CustomAgentInput: Codable {
    let name: String
    let skillsPath: String
    let linkType: LinkType

    enum CodingKeys: String, CodingKey {
        case name
        case skillsPath = "skills_path"
        case linkType = "link_type"
    }
}

// MARK: - GitStatusInfo

struct GitStatusInfo: Codable {
    let status: String
    let message: String?
}

// MARK: - GitConnectivity

struct GitConnectivity: Codable {
    let status: String       // "connected" | "disconnected"
    let message: String?
}

// MARK: - PendingChange

struct PendingChange: Codable, Identifiable {
    var id: String { filePath }
    let filePath: String
    let changeType: String

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case changeType = "change_type"
    }
}

// MARK: - WatcherEvent

struct WatcherEvent: Codable {
    let event: String
    let skillId: String

    enum CodingKeys: String, CodingKey {
        case event
        case skillId = "skill_id"
    }
}

// MARK: - OrganizedSkill

/// Describes a single Agent's relationship to a skill.
struct SkillAgentLink: Codable {
    let agentId: String
    let isSource: Bool
    let isSymlink: Bool
    let path: String

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case isSource = "is_source"
        case isSymlink = "is_symlink"
        case path
    }
}

struct OrganizedSkill: Codable, Identifiable, Equatable {
    static func == (lhs: OrganizedSkill, rhs: OrganizedSkill) -> Bool {
        lhs.id == rhs.id
    }
    let id: String
    let sourceDir: String
    let agentSource: String
    let name: String
    let description: String
    let tags: String       // JSON array string from DB
    let compatibleAgents: String  // JSON array string from DB
    let version: String
    let isOrganized: Bool
    let linkedAgents: String  // JSON: [SkillAgentLink]

    enum CodingKeys: String, CodingKey {
        case id, name, description, version
        case sourceDir = "source_dir"
        case agentSource = "agent_source"
        case tags
        case compatibleAgents = "compatible_agents"
        case isOrganized = "is_organized"
        case linkedAgents = "linked_agents"
    }

    var tagsList: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(tags.utf8))) ?? []
    }

    var compatibleAgentsList: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(compatibleAgents.utf8))) ?? []
    }

    var linkedAgentsList: [SkillAgentLink] {
        guard let data = linkedAgents.data(using: .utf8),
              let list = try? JSONDecoder().decode([SkillAgentLink].self, from: data) else {
            return []
        }
        return list
    }

    /// Whether this skill is located in the source root (has source tag).
    var isInSourceRoot: Bool {
        linkedAgentsList.contains { $0.isSource }
    }
}
