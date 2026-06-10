import Foundation

final class CoreBridge: @unchecked Sendable {
    static let shared = CoreBridge()

    private var handle: UnsafeMutableRawPointer?
    private let queue = DispatchQueue(label: "com.skills-manager.core")

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultRoot = "\(home)/.agent/skills"
        handle = defaultRoot.withCString { asm_init($0) }
        if handle == nil {
            print("[CoreBridge] Failed to initialize Rust core")
        }
    }

    deinit {
        if let h = handle {
            asm_destroy(h)
        }
    }

    // MARK: - Agent Management

    func listAgents() -> [AgentConfig] {
        return queue.sync {
            guard let h = handle,
                  let ptr = asm_list_agents(h) else { return [] }
            defer { asm_free_string(ptr) }
            let json = String(cString: ptr)
            return (try? JSONDecoder().decode([AgentConfig].self, from: Data(json.utf8))) ?? []
        }
    }

    func addCustomAgent(_ input: CustomAgentInput) -> AgentConfig? {
        return queue.sync {
            guard let h = handle,
                  let jsonData = try? JSONEncoder().encode(input),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else { return nil }
            guard let ptr = jsonStr.withCString({ asm_add_custom_agent(h, $0) }) else { return nil }
            defer { asm_free_string(ptr) }
            let result = String(cString: ptr)
            return try? JSONDecoder().decode(AgentConfig.self, from: Data(result.utf8))
        }
    }

    func removeCustomAgent(_ id: String) -> Bool {
        return queue.sync {
            guard let h = handle else { return false }
            return id.withCString { asm_remove_custom_agent(h, $0) } == 1
        }
    }

    // MARK: - Skill Management

    func listSkills() -> [SkillEntry] {
        return queue.sync {
            guard let h = handle,
                  let ptr = asm_list_skills(h) else { return [] }
            defer { asm_free_string(ptr) }
            let json = String(cString: ptr)
            return (try? JSONDecoder().decode([SkillEntry].self, from: Data(json.utf8))) ?? []
        }
    }

    func getSkill(_ id: String) -> SkillEntry? {
        return queue.sync {
            guard let h = handle,
                  let ptr = id.withCString({ asm_get_skill(h, $0) }) else { return nil }
            defer { asm_free_string(ptr) }
            let json = String(cString: ptr)
            return try? JSONDecoder().decode(SkillEntry.self, from: Data(json.utf8))
        }
    }

    func deleteSkill(_ id: String) -> Bool {
        return queue.sync {
            guard let h = handle else { return false }
            return id.withCString { asm_delete_skill(h, $0) } == 1
        }
    }

    func detectNewSkills() -> [SkillEntry] {
        return queue.sync {
            guard let h = handle,
                  let ptr = asm_detect_new_skills(h) else { return [] }
            defer { asm_free_string(ptr) }
            let json = String(cString: ptr)
            return (try? JSONDecoder().decode([SkillEntry].self, from: Data(json.utf8))) ?? []
        }
    }

    // MARK: - Symlink Operations

    func createSymlink(agentId: String, skillId: String) -> Bool {
        return queue.sync {
            guard let h = handle else { return false }
            return agentId.withCString { aid in
                skillId.withCString { sid in
                    asm_create_symlink(h, aid, sid)
                }
            } == 1
        }
    }

    func removeSymlink(agentId: String, skillId: String) -> Bool {
        return queue.sync {
            guard let h = handle else { return false }
            return agentId.withCString { aid in
                skillId.withCString { sid in
                    asm_remove_symlink(h, aid, sid)
                }
            } == 1
        }
    }

    // MARK: - Git Operations

    func getGitStatus() -> GitStatusInfo? {
        return queue.sync {
            guard let h = handle,
                  let ptr = asm_get_git_status(h) else { return nil }
            defer { asm_free_string(ptr) }
            let json = String(cString: ptr)
            return try? JSONDecoder().decode(GitStatusInfo.self, from: Data(json.utf8))
        }
    }

    func stageAndPush() -> GitStatusInfo? {
        return queue.sync {
            guard let h = handle,
                  let ptr = asm_stage_and_push(h) else { return nil }
            defer { asm_free_string(ptr) }
            let json = String(cString: ptr)
            return try? JSONDecoder().decode(GitStatusInfo.self, from: Data(json.utf8))
        }
    }

    func stageAndPushAsync() async -> GitStatusInfo? {
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let h = handle,
                      let ptr = asm_stage_and_push(h) else {
                    continuation.resume(returning: nil)
                    return
                }
                let json = String(cString: ptr)
                asm_free_string(ptr)
                let result = try? JSONDecoder().decode(GitStatusInfo.self, from: Data(json.utf8))
                continuation.resume(returning: result)
            }
        }
    }

    func getPendingChanges() -> [PendingChange] {
        return queue.sync {
            guard let h = handle,
                  let ptr = asm_get_pending_changes(h) else { return [] }
            defer { asm_free_string(ptr) }
            let json = String(cString: ptr)
            return (try? JSONDecoder().decode([PendingChange].self, from: Data(json.utf8))) ?? []
        }
    }

    // MARK: - File Watcher

    func startWatcher() -> Bool {
        return queue.sync { () -> Bool in
            guard let h = handle else { return false }
            return asm_start_watcher(h) == 1
        }
    }

    func stopWatcher() {
        queue.sync {
            guard let h = handle else { return }
            asm_stop_watcher(h)
        }
    }

    // MARK: - Path Utilities

    func expandPath(_ path: String) -> String {
        return queue.sync {
            guard let ptr = path.withCString({ asm_expand_path($0) }) else { return path }
            defer { asm_free_string(ptr) }
            return String(cString: ptr)
        }
    }
}
