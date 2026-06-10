use serde::{Deserialize, Serialize};

// ── AgentConfig ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentConfig {
    pub id: String,
    pub name: String,
    pub skills_path: String,
    pub link_type: LinkType,
    pub is_builtin: bool,
    pub is_linked: bool,
    pub linked_skills: Vec<String>,
    pub icon: Option<String>,
    pub exists: bool,
}

impl AgentConfig {
    pub fn builtin(
        id: &str,
        name: &str,
        skills_path: &str,
        link_type: LinkType,
    ) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            skills_path: skills_path.to_string(),
            link_type,
            is_builtin: true,
            is_linked: false,
            linked_skills: Vec::new(),
            icon: None,
            exists: false,
        }
    }

    pub fn custom(
        id: &str,
        name: &str,
        skills_path: &str,
        link_type: LinkType,
    ) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            skills_path: skills_path.to_string(),
            link_type,
            is_builtin: false,
            is_linked: false,
            linked_skills: Vec::new(),
            icon: None,
            exists: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum LinkType {
    Directory,
    SingleFile,
    Overlay,
}

// ── SkillEntry & SkillManifest ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillEntry {
    pub id: String,
    pub manifest: SkillManifest,
    pub source_dir: String,
    pub installed_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillManifest {
    pub name: String,
    pub description: String,
    pub tags: Vec<String>,
    pub compatible_agents: Vec<String>,
    pub version: String,
}

// ── CustomAgentInput ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CustomAgentInput {
    pub name: String,
    pub skills_path: String,
    pub link_type: LinkType,
}

// ── OrganizedSkill ──

/// Describes a single Agent's relationship to a skill (source file, symlink, or both).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillAgentLink {
    pub agent_id: String,
    pub is_source: bool,    // skill is a real directory in source_root
    pub is_symlink: bool,   // skill is a symlink
    pub path: String,       // actual path in this agent's directory
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrganizedSkill {
    pub id: String,
    pub source_dir: String,
    pub agent_source: String,
    pub name: String,
    pub description: String,
    pub tags: String,
    pub compatible_agents: String,
    pub version: String,
    pub is_organized: bool,
    pub linked_agents: String,  // JSON: Vec<SkillAgentLink>
}

// ── GitStatus ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatusInfo {
    pub status: String,
    pub message: Option<String>,
}

impl GitStatusInfo {
    pub fn idle() -> Self {
        Self { status: "idle".into(), message: None }
    }
    pub fn modified(message: &str) -> Self {
        Self { status: "modified".into(), message: Some(message.into()) }
    }
    pub fn conflicted(message: &str) -> Self {
        Self { status: "conflicted".into(), message: Some(message.into()) }
    }
    pub fn pushing() -> Self {
        Self { status: "pushing".into(), message: None }
    }
    pub fn synced() -> Self {
        Self { status: "synced".into(), message: None }
    }
    pub fn error(message: &str) -> Self {
        Self { status: "error".into(), message: Some(message.into()) }
    }
}

// ── PendingChange ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingChange {
    pub file_path: String,
    pub change_type: String,
}

// ── WatcherEvent ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WatcherEvent {
    pub event: String,
    pub skill_id: String,
}

impl WatcherEvent {
    pub fn new_skill(skill_id: &str) -> Self {
        Self { event: "new_skill".into(), skill_id: skill_id.into() }
    }
    pub fn skill_changed(skill_id: &str) -> Self {
        Self { event: "skill_changed".into(), skill_id: skill_id.into() }
    }
    pub fn skill_removed(skill_id: &str) -> Self {
        Self { event: "skill_removed".into(), skill_id: skill_id.into() }
    }
}
