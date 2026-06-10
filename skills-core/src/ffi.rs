use std::collections::HashSet;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;

use crate::agent_registry::AgentRegistry;
use crate::git_engine::GitEngine;
use crate::models::{CustomAgentInput, GitStatusInfo, PendingChange, WatcherEvent};
use crate::scanner::Scanner;
use crate::symlink::SymlinkManager;
use crate::watcher::SkillWatcher;

pub struct CoreHandle {
    pub registry: AgentRegistry,
    pub scanner: Scanner,
    pub symlink: SymlinkManager,
    pub git: Option<GitEngine>,
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
        git,
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
    to_json_cstring(&h.registry.all())
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
    let h = unsafe { &*handle };

    match &h.git {
        Some(git) => match git.stage_and_push("skill: sync from Agent Skills Manager") {
            Ok(status) => to_json_cstring(&status),
            Err(e) => to_json_cstring(&GitStatusInfo::error(&e)),
        },
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
