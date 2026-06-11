use std::collections::HashSet;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;

use crate::agent_registry::AgentRegistry;
use crate::git_engine::GitEngine;
use crate::models::{CustomAgentInput, GitConnectivity, GitStatusInfo, PendingChange, WatcherEvent};
use crate::scanner::Scanner;
use crate::storage::db::Database;
use crate::symlink::SymlinkManager;
use crate::watcher::SkillWatcher;

pub struct CoreHandle {
    pub registry: AgentRegistry,
    pub scanner: Scanner,
    pub symlink: SymlinkManager,
    pub db: Database,
    pub git: Option<GitEngine>,
    pub git_auth: Option<crate::models::GitAuthInfo>,
    pub watcher: Option<SkillWatcher>,
    pub config_dir: PathBuf,
    pub known_skill_ids: HashSet<String>,
}

// ── Helper: serialize to JSON CString ──

fn to_json_cstring<T: serde::Serialize>(value: &T) -> *mut c_char {
    match serde_json::to_string(value) {
        Ok(json) => match CString::new(json) {
            Ok(c) => c.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

fn to_json_cstring_opt<T: serde::Serialize>(value: Option<&T>) -> *mut c_char {
    match value {
        Some(v) => to_json_cstring(v),
        None => std::ptr::null_mut(),
    }
}

fn from_cstring_json<'a, T: serde::Deserialize<'a>>(ptr: *const c_char) -> Result<T, String> {
    if ptr.is_null() {
        return Err("null pointer".to_string());
    }
    let c_str = unsafe { CStr::from_ptr(ptr) };
    let json = c_str.to_str().map_err(|e| format!("Invalid UTF-8: {}", e))?;
    serde_json::from_str(json).map_err(|e| format!("JSON parse error: {}", e))
}

fn from_cstring(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string()
}

// ── Memory management ──

/// Initialize the core. `source_root` is the skills source directory.
/// Returns an opaque handle, or null on failure.
#[no_mangle]
pub extern "C" fn asm_init(source_root: *const c_char) -> *mut CoreHandle {
    let root_str = from_cstring(source_root);
    let source_root = PathBuf::from(&root_str);
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/tmp"));
    let config_dir = home.join(".agent");

    let registry = match AgentRegistry::new(&config_dir) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("asm_init: failed to create registry: {}", e);
            return std::ptr::null_mut();
        }
    };

    let scanner = Scanner::new(source_root.clone());
    let symlink = SymlinkManager::new(source_root.clone());

    let db = Database::open().unwrap_or_else(|e| {
        eprintln!("asm_init: failed to open database: {}", e);
        panic!("Cannot initialize database");
    });

    // Try to open git repo if source_root is a git directory
    let git = GitEngine::open(&source_root).ok();

    // Build initial known_skill_ids set
    let known_skill_ids: HashSet<String> = scanner
        .scan_all()
        .unwrap_or_default()
        .into_iter()
        .map(|s| s.id)
        .collect();

    let handle = Box::new(CoreHandle {
        registry,
        scanner,
        symlink,
        db,
        git,
        git_auth: None,
        watcher: None,
        config_dir,
        known_skill_ids,
    });

    Box::into_raw(handle)
}

/// Destroy the core handle and free all resources.
#[no_mangle]
pub extern "C" fn asm_destroy(handle: *mut CoreHandle) {
    if handle.is_null() {
        return;
    }
    unsafe {
        // Drop the handle, which drops watcher and all resources
        let _ = Box::from_raw(handle);
    }
}

/// Free a string returned by any asm_* function.
#[no_mangle]
pub extern "C" fn asm_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

/// Expand a path (handle ~ expansion).
/// Returns a JSON string of the expanded path, or null on error.
#[no_mangle]
pub extern "C" fn asm_expand_path(path: *const c_char) -> *mut c_char {
    let raw = from_cstring(path);
    match crate::agent_registry::expand_path(&raw) {
        Ok(expanded) => to_json_cstring(&expanded.to_string_lossy().to_string()),
        Err(e) => to_json_cstring(&e),
    }
}

// ── Agent management ──

/// List all agents (builtin + custom).
/// Returns JSON array of AgentConfig, or null on error.
#[no_mangle]
pub extern "C" fn asm_list_agents(handle: *mut CoreHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };
    let mut agents = h.registry.all();
    // Check which agent skill directories actually exist on disk, and count skills
    for agent in &mut agents {
        agent.exists = crate::agent_registry::expand_path(&agent.skills_path)
            .map(|p| p.exists() && p.is_dir())
            .unwrap_or(false);
        // Count skills in this agent's directory (real dirs + symlinks)
        if let Ok(expanded) = crate::agent_registry::expand_path(&agent.skills_path) {
            if let Ok(skills) = h.scanner.scan_path(&expanded) {
                agent.linked_skills = skills.iter().map(|s| s.id.clone()).collect();
            }
        }
    }
    to_json_cstring(&agents)
}

/// Add a custom agent.
/// `json` is a JSON string of CustomAgentInput.
/// Returns JSON of the created AgentConfig, or null on error.
#[no_mangle]
pub extern "C" fn asm_add_custom_agent(handle: *mut CoreHandle, json: *const c_char) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &mut *handle };

    let input: CustomAgentInput = match from_cstring_json(json) {
        Ok(i) => i,
        Err(e) => return to_json_cstring(&e),
    };

    match h.registry.add_custom(input) {
        Ok(agent) => to_json_cstring(&agent),
        Err(e) => to_json_cstring(&e),
    }
}

/// Remove a custom agent by ID.
/// Returns 1 on success, 0 on failure.
#[no_mangle]
pub extern "C" fn asm_remove_custom_agent(handle: *mut CoreHandle, agent_id: *const c_char) -> u8 {
    if handle.is_null() {
        return 0;
    }
    let h = unsafe { &mut *handle };
    let id = from_cstring(agent_id);

    match h.registry.remove_custom(&id) {
        Ok(()) => 1,
        Err(e) => {
            eprintln!("asm_remove_custom_agent: {}", e);
            0
        }
    }
}

// ── Skill management ──

/// List all skills found in source_root.
/// Returns JSON array of SkillEntry, or null on error.
#[no_mangle]
pub extern "C" fn asm_list_skills(handle: *mut CoreHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };
    match h.scanner.scan_all() {
        Ok(skills) => to_json_cstring(&skills),
        Err(e) => to_json_cstring(&e),
    }
}

/// Get a single skill by ID.
/// Returns JSON of SkillEntry, or null if not found.
#[no_mangle]
pub extern "C" fn asm_get_skill(handle: *mut CoreHandle, skill_id: *const c_char) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };
    let id = from_cstring(skill_id);

    match h.scanner.scan_all() {
        Ok(skills) => {
            let found = skills.into_iter().find(|s| s.id == id);
            to_json_cstring_opt(found.as_ref())
        }
        Err(_) => std::ptr::null_mut(),
    }
}

/// Delete a skill: remove the skill directory and all symlinks.
/// Returns 1 on success, 0 on failure.
#[no_mangle]
pub extern "C" fn asm_delete_skill(handle: *mut CoreHandle, skill_id: *const c_char) -> u8 {
    if handle.is_null() {
        return 0;
    }
    let h = unsafe { &mut *handle };
    let id = from_cstring(skill_id);

    // Remove symlinks from all agents
    for agent in h.registry.all() {
        if agent.linked_skills.contains(&id) {
            h.symlink.remove_skill_link(&agent, &id).ok();
            h.registry.unlink_skill(&agent.id, &id).ok();
        }
    }

    // Remove skill directory
    let skill_dir = h.scanner.scan_all()
        .ok()
        .and_then(|skills| skills.into_iter().find(|s| s.id == id))
        .map(|s| PathBuf::from(s.source_dir));

    if let Some(dir) = skill_dir {
        if dir.exists() {
            std::fs::remove_dir_all(&dir).ok();
        }
    }

    // Update known skills
    h.known_skill_ids.remove(&id);

    1
}

// ── Symlink operations ──

/// Create a symlink for a skill to an agent.
/// Also updates the registry's linked_skills.
/// Returns 1 on success, 0 on failure.
#[no_mangle]
pub extern "C" fn asm_create_symlink(
    handle: *mut CoreHandle,
    agent_id: *const c_char,
    skill_id: *const c_char,
) -> u8 {
    if handle.is_null() {
        return 0;
    }
    let h = unsafe { &mut *handle };
    let aid = from_cstring(agent_id);
    let sid = from_cstring(skill_id);

    // Find the agent
    let agent = match h.registry.find(&aid) {
        Some(a) => a.clone(),
        None => {
            eprintln!("asm_create_symlink: agent not found: {}", aid);
            return 0;
        }
    };

    // Create the symlink
    if let Err(e) = h.symlink.create_skill_link(&agent, &sid) {
        eprintln!("asm_create_symlink: symlink failed: {}", e);
        return 0;
    }

    // Update registry
    h.registry.link_skill(&aid, &sid).ok();

    1
}

/// Remove a symlink for a skill from an agent.
/// Also updates the registry's linked_skills.
/// Returns 1 on success, 0 on failure.
#[no_mangle]
pub extern "C" fn asm_remove_symlink(
    handle: *mut CoreHandle,
    agent_id: *const c_char,
    skill_id: *const c_char,
) -> u8 {
    if handle.is_null() {
        return 0;
    }
    let h = unsafe { &mut *handle };
    let aid = from_cstring(agent_id);
    let sid = from_cstring(skill_id);

    let agent = match h.registry.find(&aid) {
        Some(a) => a.clone(),
        None => {
            eprintln!("asm_remove_symlink: agent not found: {}", aid);
            return 0;
        }
    };

    h.symlink.remove_skill_link(&agent, &sid).ok();
    h.registry.unlink_skill(&aid, &sid).ok();

    1
}

// ── Git operations ──

/// Get current git status.
/// Returns JSON of GitStatusInfo, or null on error.
#[no_mangle]
pub extern "C" fn asm_get_git_status(handle: *mut CoreHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };

    match &h.git {
        Some(git) => match git.get_status() {
            Ok(status) => to_json_cstring(&status),
            Err(e) => to_json_cstring(&GitStatusInfo::error(&e)),
        },
        None => to_json_cstring(&GitStatusInfo::idle()),
    }
}

/// Stage all changes, commit, and push.
/// Returns JSON of GitStatusInfo.
#[no_mangle]
pub extern "C" fn asm_stage_and_push(handle: *mut CoreHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &mut *handle };

    match &mut h.git {
        Some(git) => {
            let token = h.git_auth.as_ref().map(|a| a.token.as_str());
            match git.stage_and_push("skill: sync from Agent Skills Manager", token) {
                Ok(status) => to_json_cstring(&status),
                Err(e) => to_json_cstring(&GitStatusInfo::error(&e)),
            }
        }
        None => to_json_cstring(&GitStatusInfo::error("No git repository configured")),
    }
}

/// Get list of pending changes.
/// Returns JSON array of PendingChange.
#[no_mangle]
pub extern "C" fn asm_get_pending_changes(handle: *mut CoreHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };

    match &h.git {
        Some(git) => match git.get_pending_changes() {
            Ok(changes) => to_json_cstring(&changes),
            Err(e) => {
                eprintln!("asm_get_pending_changes: {}", e);
                std::ptr::null_mut()
            }
        },
        None => {
            // No git repo → empty changes
            let empty: Vec<PendingChange> = Vec::new();
            to_json_cstring(&empty)
        }
    }
}

/// Set git authentication info (PAT token + remote URL).
/// If no git repo exists at source_root, automatically initializes one.
/// Also sets the remote URL on the repository if provided.
/// Returns 1 on success, 0 on failure.
#[no_mangle]
pub extern "C" fn asm_set_git_auth(
    handle: *mut CoreHandle,
    token: *const c_char,
    remote_url: *const c_char,
) -> u8 {
    if handle.is_null() {
        return 0;
    }
    let h = unsafe { &mut *handle };

    let token_str = from_cstring(token);
    let url_str = from_cstring(remote_url);

    if token_str.is_empty() {
        return 0;
    }

    // Auto-init git repo if it doesn't exist yet
    if h.git.is_none() {
        let source_root = h.scanner.source_root();
        match GitEngine::open_or_init(&source_root) {
            Ok(engine) => h.git = Some(engine),
            Err(e) => {
                eprintln!("asm_set_git_auth: failed to init git repo: {}", e);
                return 0;
            }
        }
    }

    // Set remote URL on repo
    if let Some(git) = &h.git {
        if !url_str.is_empty() {
            if let Err(e) = git.set_remote_url(&url_str) {
                eprintln!("asm_set_git_auth: failed to set remote URL: {}", e);
                return 0;
            }
        }
    }

    h.git_auth = Some(crate::models::GitAuthInfo {
        token: token_str,
        remote_url: url_str,
    });

    1
}

/// Pull (fetch + rebase) from origin using stored auth.
/// Returns JSON of GitStatusInfo.
#[no_mangle]
pub extern "C" fn asm_pull(handle: *mut CoreHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &mut *handle };

    match &mut h.git {
        Some(git) => {
            let token = h.git_auth.as_ref().map(|a| a.token.as_str());
            match git.pull(token) {
                Ok(status) => to_json_cstring(&status),
                Err(e) => to_json_cstring(&GitStatusInfo::error(&e)),
            }
        }
        None => to_json_cstring(&GitStatusInfo::error("No git repository configured")),
    }
}

/// Check if the git remote is reachable with the current auth token.
/// Returns JSON of GitConnectivity: {"status":"connected"/"disconnected", "message":...}
#[no_mangle]
pub extern "C" fn asm_check_git_connectivity(handle: *mut CoreHandle) -> *mut c_char {
    if handle.is_null() {
        return to_json_cstring(&GitConnectivity {
            status: "disconnected".into(),
            message: Some("Core not initialized".into()),
        });
    }
    let h = unsafe { &*handle };

    match &h.git {
        Some(git) => {
            let token = h.git_auth.as_ref().map(|a| a.token.as_str());
            match git.check_connectivity(token) {
                Ok(conn) => to_json_cstring(&conn),
                Err(e) => to_json_cstring(&GitConnectivity {
                    status: "disconnected".into(),
                    message: Some(e),
                }),
            }
        }
        None => to_json_cstring(&GitConnectivity {
            status: "disconnected".into(),
            message: Some("No git repository".into()),
        }),
    }
}

/// Set the git remote URL for "origin".
/// Returns 1 on success, 0 on failure.
#[no_mangle]
pub extern "C" fn asm_set_remote_url(handle: *mut CoreHandle, url: *const c_char) -> u8 {
    if handle.is_null() {
        return 0;
    }
    let h = unsafe { &*handle };
    let url_str = from_cstring(url);

    match &h.git {
        Some(git) => match git.set_remote_url(&url_str) {
            Ok(()) => 1,
            Err(e) => {
                eprintln!("asm_set_remote_url: {}", e);
                0
            }
        },
        None => 0,
    }
}

// ── File watcher ──

/// Start watching the source_root for skill changes.
/// Detects new skills and reports them via the callback.
/// Returns 1 on success, 0 on failure.
#[no_mangle]
pub extern "C" fn asm_start_watcher(
    handle: *mut CoreHandle,
    callback: Option<extern "C" fn(*const c_char)>,
) -> u8 {
    if handle.is_null() {
        return 0;
    }
    let h = unsafe { &mut *handle };

    // Get source_root from the first scanned skill's parent directory
    let source_root = h.scanner.scan_all()
        .ok()
        .and_then(|skills| skills.first().map(|s| {
            PathBuf::from(s.source_dir.clone())
                .parent()
                .unwrap()
                .to_path_buf()
        }))
        .unwrap_or_else(|| PathBuf::from("."));

    let mut watcher = SkillWatcher::new(source_root);

    if let Some(cb) = callback {
        let _known = h.known_skill_ids.clone();
        match watcher.start(move |event: WatcherEvent| {
            let json = serde_json::to_string(&event).unwrap_or_default();
            if let Ok(c) = CString::new(json) {
                cb(c.as_ptr());
            }
        }) {
            Ok(()) => {
                h.watcher = Some(watcher);
                1
            }
            Err(e) => {
                eprintln!("asm_start_watcher: {}", e);
                0
            }
        }
    } else {
        // No callback, still start watcher but events are dropped
        match watcher.start(|_event| {}) {
            Ok(()) => {
                h.watcher = Some(watcher);
                1
            }
            Err(e) => {
                eprintln!("asm_start_watcher: {}", e);
                0
            }
        }
    }
}

/// Stop watching.
#[no_mangle]
pub extern "C" fn asm_stop_watcher(handle: *mut CoreHandle) {
    if handle.is_null() {
        return;
    }
    let h = unsafe { &mut *handle };
    h.watcher = None; // Drop triggers watcher stop
}

/// Check for new skills and return them.
/// Returns JSON array of new SkillEntry.
#[no_mangle]
pub extern "C" fn asm_detect_new_skills(handle: *mut CoreHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &mut *handle };

    match h.scanner.detect_new(&h.known_skill_ids) {
        Ok(new_skills) => {
            // Update known IDs
            for skill in &new_skills {
                h.known_skill_ids.insert(skill.id.clone());
            }
            to_json_cstring(&new_skills)
        }
        Err(e) => {
            eprintln!("asm_detect_new_skills: {}", e);
            std::ptr::null_mut()
        }
    }
}

/// Scan all built-in agent skills_path directories for skills.
/// Returns JSON array of SkillEntry found across all agents.
#[no_mangle]
pub extern "C" fn asm_fetch_agent_skills(handle: *mut CoreHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };

    let agents = h.registry.all();
    let mut all_skills: Vec<crate::models::SkillEntry> = Vec::new();
    let mut seen_ids: HashSet<String> = HashSet::new();

    for agent in &agents {
        let expanded = match crate::agent_registry::expand_path(&agent.skills_path) {
            Ok(p) => p,
            Err(_) => continue,
        };

        if let Ok(skills) = h.scanner.scan_path(&expanded) {
            for skill in skills {
                if !seen_ids.contains(&skill.id) {
                    seen_ids.insert(skill.id.clone());
                    all_skills.push(skill);
                }
            }
        }
    }

    // Also scan the default ~/.agent/skills directory
    let default_skills = match crate::agent_registry::expand_path("~/.agent/skills") {
        Ok(p) => p,
        Err(_) => PathBuf::from(""),
    };
    if !default_skills.as_os_str().is_empty() && default_skills.exists() {
        if let Ok(skills) = h.scanner.scan_path(&default_skills) {
            for skill in skills {
                if !seen_ids.contains(&skill.id) {
                    seen_ids.insert(skill.id.clone());
                    all_skills.push(skill);
                }
            }
        }
    }

    to_json_cstring(&all_skills)
}

/// Organize a single skill from an agent's directory to source_root.
#[no_mangle]
pub extern "C" fn asm_organize_skill(
    handle: *mut CoreHandle,
    skill_id: *const c_char,
    agent_id: *const c_char,
) -> u8 {
    if handle.is_null() { return 0; }
    let h = unsafe { &*handle };
    let sid = from_cstring(skill_id);
    let aid = from_cstring(agent_id);

    let agent = match h.registry.find(&aid) {
        Some(a) => a.clone(),
        None => { eprintln!("Agent not found: {}", aid); return 0; }
    };

    match h.symlink.organize_skill(&agent, &sid) {
        Ok(()) => {
            h.db.set_organized(&sid).ok();
            h.db.set_has_organized().ok();
            1
        }
        Err(e) => {
            eprintln!("Organize skill failed: {}", e);
            0
        }
    }
}

/// Organize all skills from all agents.
/// Returns JSON array of [skill_id, agent_id] pairs that were organized.
#[no_mangle]
pub extern "C" fn asm_organize_all(handle: *mut CoreHandle) -> *mut c_char {
    if handle.is_null() { return std::ptr::null_mut(); }
    let h = unsafe { &*handle };
    let agents = h.registry.all();

    match h.symlink.organize_all(&agents, &h.scanner) {
        Ok(organized) => {
            for (skill_id, _) in &organized {
                h.db.set_organized(skill_id).ok();
            }
            h.db.set_has_organized().ok();
            to_json_cstring(&organized)
        }
        Err(e) => {
            eprintln!("Organize all failed: {}", e);
            std::ptr::null_mut()
        }
    }
}

/// Get the full skill list from database (with organize status).
#[no_mangle]
pub extern "C" fn asm_get_skill_list(handle: *mut CoreHandle) -> *mut c_char {
    if handle.is_null() { return std::ptr::null_mut(); }
    let h = unsafe { &*handle };
    match h.db.get_all_skills() {
        Ok(skills) => to_json_cstring(&skills),
        Err(e) => {
            eprintln!("Get skill list failed: {}", e);
            std::ptr::null_mut()
        }
    }
}

/// Check if user has ever organized skills.
#[no_mangle]
pub extern "C" fn asm_has_organized(handle: *mut CoreHandle) -> u8 {
    if handle.is_null() { return 0; }
    let h = unsafe { &*handle };
    h.db.has_organized().unwrap_or(false) as u8
}

/// Mark that user has organized skills.
#[no_mangle]
pub extern "C" fn asm_set_organized(handle: *mut CoreHandle) {
    if handle.is_null() { return; }
    let h = unsafe { &*handle };
    h.db.set_has_organized().ok();
}

/// Scan all agents and upsert skills into the database.
/// This populates the DB with fresh scan data.
/// Each skill records its relationship to all agents (source/symlink/path).
#[no_mangle]
pub extern "C" fn asm_refresh_skill_db(handle: *mut CoreHandle) -> u8 {
    if handle.is_null() { return 0; }
    let h = unsafe { &*handle };

    let agents = h.registry.all();
    let source_root_str = h.scanner.source_root().to_string_lossy().to_string();
    let mut seen_ids: HashSet<String> = HashSet::new();

    // Phase 1: collect all skill occurrences across all agents
    // Map: skill_id -> Vec<(agent_id, is_symlink, path)>
    let mut skill_occurrences: std::collections::HashMap<String, Vec<(String, bool, String)>> =
        std::collections::HashMap::new();

    for agent in &agents {
        let expanded = match crate::agent_registry::expand_path(&agent.skills_path) {
            Ok(p) => p,
            Err(_) => continue,
        };

        if let Ok(skills) = h.scanner.scan_path(&expanded) {
            for skill in skills {
                let source_dir = PathBuf::from(&skill.source_dir);
                let is_symlink = source_dir.is_symlink();
                let path = skill.source_dir.clone();

                skill_occurrences
                    .entry(skill.id.clone())
                    .or_default()
                    .push((agent.id.clone(), is_symlink, path));
            }
        }
    }

    // Also scan default ~/.agent/skills
    if let Ok(default_skills_path) = crate::agent_registry::expand_path("~/.agent/skills") {
        if default_skills_path.exists() {
            if let Ok(skills) = h.scanner.scan_path(&default_skills_path) {
                for skill in skills {
                    let source_dir = PathBuf::from(&skill.source_dir);
                    let is_symlink = source_dir.is_symlink();
                    let path = skill.source_dir.clone();

                    skill_occurrences
                        .entry(skill.id.clone())
                        .or_default()
                        .push(("default".to_string(), is_symlink, path));
                }
            }
        }
    }

    // Phase 2: For each skill, find the canonical source_dir and build linked_agents
    // Priority: non-symlink > symlink, first found wins
    for (skill_id, occurrences) in &skill_occurrences {
        if seen_ids.contains(skill_id) {
            continue;
        }
        seen_ids.insert(skill_id.clone());

        // Find canonical source_dir (prefer non-symlink)
        let mut canonical_dir = String::new();
        let mut canonical_agent = String::new();
        for (agent_id, is_symlink, path) in occurrences {
            if canonical_dir.is_empty() || (!is_symlink && canonical_dir.is_empty()) {
                canonical_dir = path.clone();
                canonical_agent = agent_id.clone();
            }
            if !is_symlink && canonical_dir.is_empty() {
                canonical_dir = path.clone();
                canonical_agent = agent_id.clone();
            }
        }

        if canonical_dir.is_empty() {
            continue;
        }

        // Build linked_agents JSON
        let mut links: Vec<crate::models::SkillAgentLink> = Vec::new();
        for (agent_id, is_symlink, path) in occurrences {
            let is_source = path.starts_with(&source_root_str);
            links.push(crate::models::SkillAgentLink {
                agent_id: agent_id.clone(),
                is_source,
                is_symlink: *is_symlink,
                path: path.clone(),
            });
        }

        let linked_agents_json = serde_json::to_string(&links).unwrap_or_else(|_| "[]".to_string());

        // Read skill metadata from the canonical directory
        let skill_path = PathBuf::from(&canonical_dir);
        let manifest_path = skill_path.join("manifest.json");
        let (name, description, tags, compatible_agents, version) = if manifest_path.is_file() {
            match std::fs::read_to_string(&manifest_path) {
                Ok(content) => {
                    let manifest: crate::models::SkillManifest = serde_json::from_str(&content)
                        .unwrap_or_else(|_| crate::models::SkillManifest {
                            name: skill_id.clone(),
                            description: format!("{} skill", skill_id),
                            tags: vec![],
                            compatible_agents: vec!["*".to_string()],
                            version: "0.1.0".to_string(),
                        });
                    let desc = crate::scanner::extract_description(
                        &skill_path.join("SKILL.md")
                    );
                    (
                        manifest.name,
                        if desc.is_empty() { manifest.description } else { desc },
                        serde_json::to_string(&manifest.tags).unwrap_or_default(),
                        serde_json::to_string(&manifest.compatible_agents).unwrap_or_default(),
                        manifest.version,
                    )
                }
                Err(_) => (
                    skill_id.clone(),
                    format!("{} skill", skill_id),
                    "[]".to_string(),
                    "[\"*\"]".to_string(),
                    "0.1.0".to_string(),
                ),
            }
        } else {
            let desc = crate::scanner::extract_description(&skill_path.join("SKILL.md"));
            (
                skill_id.clone(),
                if desc.is_empty() { format!("{} skill", skill_id) } else { desc },
                "[]".to_string(),
                "[\"*\"]".to_string(),
                "0.1.0".to_string(),
            )
        };

        // Determine is_organized
        let is_in_source = canonical_dir.starts_with(&source_root_str);
        let is_symlink = PathBuf::from(&canonical_dir).is_symlink();
        let is_organized = is_in_source || is_symlink;

        h.db.upsert_skill_with_agent(
            &skill_id,
            &canonical_dir,
            &canonical_agent,
            &name,
            &description,
            &tags,
            &compatible_agents,
            &version,
            &linked_agents_json,
        ).ok();

        if is_organized {
            h.db.set_organized(&skill_id).ok();
        }
    }

    seen_ids.len() as u8
}

/// Restore an organized skill back to its original agent directory.
/// Returns 1 on success, 0 on failure.
#[no_mangle]
pub extern "C" fn asm_restore_skill(
    handle: *mut CoreHandle,
    skill_id: *const c_char,
) -> u8 {
    if handle.is_null() { return 0; }
    let h = unsafe { &mut *handle };
    let sid = from_cstring(skill_id);

    // Get the skill's current info from DB
    let skills = h.db.get_all_skills().unwrap_or_default();
    let skill = match skills.iter().find(|s| s.id == sid) {
        Some(s) => s.clone(),
        None => { eprintln!("Skill not found in DB: {}", sid); return 0; }
    };

    if !skill.is_organized {
        eprintln!("Skill is not organized: {}", sid);
        return 0;
    }

    // Parse linked_agents to find the source agent and other linked agents
    let links: Vec<crate::models::SkillAgentLink> = 
        serde_json::from_str(&skill.linked_agents).unwrap_or_default();

    let source_agent_id = &skill.agent_source;
    let source_agent = match h.registry.find(source_agent_id) {
        Some(a) => a.clone(),
        None => { eprintln!("Source agent not found: {}", source_agent_id); return 0; }
    };

    let other_linked: Vec<String> = links
        .iter()
        .filter(|l| l.agent_id != *source_agent_id && l.is_symlink)
        .map(|l| l.agent_id.clone())
        .collect();

    // Restore: move directory back, remove symlink
    match h.symlink.restore_skill(&sid, &source_agent, &other_linked) {
        Ok(()) => {
            // Remove broken symlinks from other agents
            for agent_id in &other_linked {
                if let Some(other_agent) = h.registry.find(agent_id) {
                    let other_agent = other_agent.clone();
                    h.symlink.remove_skill_link(&other_agent, &sid).ok();
                    h.registry.unlink_skill(agent_id, &sid).ok();
                }
            }

            // Update DB: new source_dir is in the agent's directory
            let target_base = match crate::agent_registry::expand_path(&source_agent.skills_path) {
                Ok(p) => p,
                Err(_) => { eprintln!("Failed to expand agent path"); return 0; }
            };
            let new_source_dir = target_base.join(&sid).to_string_lossy().to_string();

            // Build updated linked_agents: only the source agent, not a symlink, not in source_root
            let new_links = vec![crate::models::SkillAgentLink {
                agent_id: source_agent_id.clone(),
                is_source: false,
                is_symlink: false,
                path: new_source_dir.clone(),
            }];
            let new_linked_json = serde_json::to_string(&new_links).unwrap_or_else(|_| "[]".to_string());

            h.db.update_skill_location(
                &sid,
                &new_source_dir,
                source_agent_id,
                false, // no longer organized
                &new_linked_json,
            ).ok();

            1
        }
        Err(e) => {
            eprintln!("Restore skill failed: {}", e);
            0
        }
    }
}
