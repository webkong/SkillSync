import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private let core = CoreBridge.shared

    @Published var agents: [AgentConfig] = []
    @Published var skills: [SkillEntry] = []
    @Published var showOrganizePrompt = false
    @Published var organizedSkills: [OrganizedSkill] = []
    @Published var gitStatus: GitStatusInfo = GitStatusInfo(status: "idle", message: nil)
    @Published var pendingChanges: [PendingChange] = []
    @Published var pendingNewSkill: SkillEntry? = nil
    @Published var isLoading = false
    @Published var isFetching = false
    @Published var showOrganizeConfirm = false
    @Published var selectedSkill: OrganizedSkill? = nil

    // MARK: - Initialization

    func loadInitialData() {
        isLoading = true
        defer { isLoading = false }

        agents = core.listAgents()

        // Refresh DB and get organized skill list
        _ = core.refreshSkillDb()
        organizedSkills = core.getSkillList()

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
                _ = core.refreshSkillDb()
                organizedSkills = core.getSkillList()
            }
        } else {
            if core.removeSymlink(agentId: agentId, skillId: skillId) {
                agents = core.listAgents()
                _ = core.refreshSkillDb()
                organizedSkills = core.getSkillList()
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

    func fetchAgentSkills() {
        isFetching = true
        agents = core.listAgents()
        _ = core.refreshSkillDb()
        organizedSkills = core.getSkillList()
        skills = core.listSkills()
        // Keep loading indicator visible for at least 1 second
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                isFetching = false
            }
        }
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

    // MARK: - Skill Organization

    func checkOrganizeStatus() {
        if !core.hasOrganized() {
            showOrganizePrompt = true
        }
    }

    func organizeAll() {
        isLoading = true
        if core.organizeAll() {
            _ = core.refreshSkillDb()
            organizedSkills = core.getSkillList()
            skills = core.listSkills()
            core.setOrganized()
            showOrganizePrompt = false
            showOrganizeConfirm = false
        }
        isLoading = false
    }

    func organizeSkill(skillId: String, agentId: String) {
        if core.organizeSkill(skillId: skillId, agentId: agentId) {
            _ = core.refreshSkillDb()
            organizedSkills = core.getSkillList()
            skills = core.listSkills()
        }
    }

    func dismissOrganizePrompt() {
        core.setOrganized()
        showOrganizePrompt = false
    }

    func restoreSkill(skillId: String) {
        if core.restoreSkill(skillId) {
            _ = core.refreshSkillDb()
            organizedSkills = core.getSkillList()
            agents = core.listAgents()
        }
    }

    // MARK: - Git Operations

    func pushChanges() {
        isLoading = true
        gitStatus = GitStatusInfo(status: "pushing", message: nil)
        Task {
            if let status = await core.stageAndPushAsync() {
                await MainActor.run {
                    gitStatus = status
                    isLoading = false
                    if status.status == "synced" {
                        pendingChanges = []
                    }
                }
            } else {
                await MainActor.run {
                    gitStatus = GitStatusInfo(status: "error", message: "Push failed")
                    isLoading = false
                }
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
