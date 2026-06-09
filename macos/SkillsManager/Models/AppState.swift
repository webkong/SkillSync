import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private let core = CoreBridge.shared

    @Published var agents: [AgentConfig] = []
    @Published var skills: [SkillEntry] = []
    @Published var gitStatus: GitStatusInfo = GitStatusInfo(status: "idle", message: nil)
    @Published var pendingChanges: [PendingChange] = []
    @Published var pendingNewSkill: SkillEntry? = nil
    @Published var isLoading = false

    // MARK: - Initialization

    func loadInitialData() {
        isLoading = true
        defer { isLoading = false }

        agents = core.listAgents()
        skills = core.listSkills()
        if let status = core.getGitStatus() {
            gitStatus = status
        }
        pendingChanges = core.getPendingChanges()

        // Check for new skills
        let newSkills = core.detectNewSkills()
        if !newSkills.isEmpty {
            pendingNewSkill = newSkills.first
        }
    }

    func refresh() {
        loadInitialData()
    }

    // MARK: - Agent Operations

    func addCustomAgent(_ input: CustomAgentInput) -> AgentConfig? {
        guard let agent = core.addCustomAgent(input) else { return nil }
        agents = core.listAgents()
        return agent
    }

    func removeCustomAgent(_ id: String) {
        if core.removeCustomAgent(id) {
            agents = core.listAgents()
        }
    }

    // MARK: - Skill Operations

    func toggleSkillLink(skillId: String, agentId: String, enabled: Bool) {
        if enabled {
            if core.createSymlink(agentId: agentId, skillId: skillId) {
                agents = core.listAgents()
            }
        } else {
            if core.removeSymlink(agentId: agentId, skillId: skillId) {
                agents = core.listAgents()
            }
        }
    }

    func deleteSkill(skillId: String) {
        if core.deleteSkill(skillId) {
            skills = core.listSkills()
            agents = core.listAgents()
        }
    }

    func dismissNewSkill() {
        pendingNewSkill = nil
    }

    func enableNewSkill(forAgentIds agentIds: [String]) {
        guard let skill = pendingNewSkill else { return }
        for agentId in agentIds {
            core.createSymlink(agentId: agentId, skillId: skill.id)
        }
        pendingNewSkill = nil
        agents = core.listAgents()
        skills = core.listSkills()
    }

    // MARK: - Git Operations

    func pushChanges() {
        if let status = core.stageAndPush() {
            gitStatus = status
            if status.status == "synced" {
                pendingChanges = []
            }
        }
    }

    func refreshGitStatus() {
        if let status = core.getGitStatus() {
            gitStatus = status
        }
        pendingChanges = core.getPendingChanges()
    }
}
