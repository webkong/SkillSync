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

    enum CodingKeys: String, CodingKey {
        case id, name, icon
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

struct OrganizedSkill: Codable, Identifiable {
    let id: String
    let sourceDir: String
    let agentSource: String
    let name: String
    let description: String
    let tags: String       // JSON array string from DB
    let compatibleAgents: String  // JSON array string from DB
    let version: String
    let isOrganized: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description, version
        case sourceDir = "source_dir"
        case agentSource = "agent_source"
        case tags
        case compatibleAgents = "compatible_agents"
        case isOrganized = "is_organized"
    }

    var tagsList: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(tags.utf8))) ?? []
    }

    var compatibleAgentsList: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(compatibleAgents.utf8))) ?? []
    }
}
