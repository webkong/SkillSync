use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use crate::models::{SkillEntry, SkillManifest};

pub struct Scanner {
    source_root: PathBuf,
}

impl Scanner {
    pub fn new(source_root: PathBuf) -> Self {
        Self { source_root }
    }

    /// Scan a single directory for skills (any path, not just source_root).
    pub fn scan_path(&self, path: &Path) -> Result<Vec<SkillEntry>, String> {
        let mut skills = Vec::new();

        if !path.exists() || !path.is_dir() {
            return Ok(skills);
        }

        let entries = fs::read_dir(path)
            .map_err(|e| format!("Failed to read {}: {}", path.display(), e))?;

        for entry in entries {
            let entry = match entry {
                Ok(e) => e,
                Err(_) => continue,
            };

            let sub_path = entry.path();
            if !sub_path.is_dir() {
                continue;
            }

            if let Some(name) = sub_path.file_name().and_then(|n| n.to_str()) {
                if name.starts_with('.') {
                    continue;
                }
            }

            if !Self::validate_skill_dir(&sub_path) {
                continue;
            }

            if let Ok(skill) = self.parse_skill_dir(&sub_path) {
                skills.push(skill);
            }
        }

        Ok(skills)
    }

    /// Scan all skill directories under source_root (one level deep).
    /// Returns all valid SkillEntry objects.
    pub fn scan_all(&self) -> Result<Vec<SkillEntry>, String> {
        let mut skills = Vec::new();

        let entries = fs::read_dir(&self.source_root)
            .map_err(|e| format!("Failed to read source root {}: {}", self.source_root.display(), e))?;

        for entry in entries {
            let entry = match entry {
                Ok(e) => e,
                Err(_) => continue,
            };

            let path = entry.path();
            if !path.is_dir() {
                continue;
            }

            // Skip hidden directories
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.starts_with('.') {
                    continue;
                }
            }

            if !Self::validate_skill_dir(&path) {
                continue;
            }

            if let Ok(skill) = self.parse_skill_dir(&path) {
                skills.push(skill);
            }
        }

        Ok(skills)
    }

    /// Detect new skills by comparing against a set of known skill IDs.
    pub fn detect_new(&self, known: &HashSet<String>) -> Result<Vec<SkillEntry>, String> {
        let all = self.scan_all()?;
        let new: Vec<SkillEntry> = all
            .into_iter()
            .filter(|s| !known.contains(&s.id))
            .collect();
        Ok(new)
    }

    /// Validate that a directory contains both manifest.json and SKILL.md.
    pub fn validate_skill_dir(path: &Path) -> bool {
        path.join("manifest.json").is_file() && path.join("SKILL.md").is_file()
    }

    /// Parse a skill directory into a SkillEntry.
    fn parse_skill_dir(&self, path: &Path) -> Result<SkillEntry, String> {
        let id = path
            .file_name()
            .and_then(|n| n.to_str())
            .ok_or_else(|| format!("Invalid directory name: {}", path.display()))?
            .to_string();

        let manifest_path = path.join("manifest.json");
        let manifest_content = fs::read_to_string(&manifest_path)
            .map_err(|e| format!("Failed to read {}: {}", manifest_path.display(), e))?;

        let manifest: SkillManifest = serde_json::from_str(&manifest_content)
            .map_err(|e| format!("Failed to parse {}: {}", manifest_path.display(), e))?;

        let installed_at = chrono::Utc::now().to_rfc3339();

        Ok(SkillEntry {
            id,
            manifest,
            source_dir: path.to_string_lossy().to_string(),
            installed_at,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;
    use std::fs;
    use tempfile::TempDir;

    fn create_test_skill(dir: &Path, name: &str, desc: &str) {
        let skill_dir = dir.join(name);
        fs::create_dir_all(&skill_dir).unwrap();

        // Create manifest.json
        let manifest = serde_json::json!({
            "name": name,
            "description": desc,
            "tags": ["test"],
            "compatible_agents": ["*"],
            "version": "1.0.0"
        });
        fs::write(
            skill_dir.join("manifest.json"),
            serde_json::to_string_pretty(&manifest).unwrap(),
        )
        .unwrap();

        // Create SKILL.md
        fs::write(skill_dir.join("SKILL.md"), "# Test Skill\n").unwrap();
    }

    #[test]
    fn test_scan_empty_directory() {
        let dir = TempDir::new().unwrap();
        let scanner = Scanner::new(dir.path().to_path_buf());
        let skills = scanner.scan_all().unwrap();
        assert!(skills.is_empty());
    }

    #[test]
    fn test_scan_with_skills() {
        let dir = TempDir::new().unwrap();
        create_test_skill(dir.path(), "code-review", "Review code");
        create_test_skill(dir.path(), "commit-msg", "Write commits");

        let scanner = Scanner::new(dir.path().to_path_buf());
        let skills = scanner.scan_all().unwrap();

        assert_eq!(skills.len(), 2);
        assert!(skills.iter().any(|s| s.id == "code-review"));
        assert!(skills.iter().any(|s| s.id == "commit-msg"));
    }

    #[test]
    fn test_scan_skips_invalid_dirs() {
        let dir = TempDir::new().unwrap();

        // Valid skill
        create_test_skill(dir.path(), "valid-skill", "Valid");

        // Missing manifest.json
        let missing_manifest = dir.path().join("no-manifest");
        fs::create_dir_all(&missing_manifest).unwrap();
        fs::write(missing_manifest.join("SKILL.md"), "# No manifest\n").unwrap();

        // Missing SKILL.md
        let missing_skill = dir.path().join("no-skill-md");
        fs::create_dir_all(&missing_skill).unwrap();
        fs::write(
            missing_skill.join("manifest.json"),
            r#"{"name":"no-skill","description":"x","tags":[],"compatible_agents":["*"],"version":"1.0"}"#,
        )
        .unwrap();

        // Hidden directory
        let hidden = dir.path().join(".hidden");
        create_test_skill(&hidden, ".hidden-skill", "Hidden");

        // File (not directory)
        fs::write(dir.path().join("some-file.txt"), "not a skill").unwrap();

        let scanner = Scanner::new(dir.path().to_path_buf());
        let skills = scanner.scan_all().unwrap();

        assert_eq!(skills.len(), 1);
        assert_eq!(skills[0].id, "valid-skill");
    }

    #[test]
    fn test_detect_new_skills() {
        let dir = TempDir::new().unwrap();
        create_test_skill(dir.path(), "existing", "Already known");
        create_test_skill(dir.path(), "new-one", "New skill");

        let scanner = Scanner::new(dir.path().to_path_buf());

        let mut known = HashSet::new();
        known.insert("existing".to_string());

        let new_skills = scanner.detect_new(&known).unwrap();
        assert_eq!(new_skills.len(), 1);
        assert_eq!(new_skills[0].id, "new-one");
    }

    #[test]
    fn test_validate_skill_dir() {
        let dir = TempDir::new().unwrap();

        let valid_dir = dir.path().join("valid");
        fs::create_dir_all(&valid_dir).unwrap();
        fs::write(valid_dir.join("manifest.json"), "{}").unwrap();
        fs::write(valid_dir.join("SKILL.md"), "# Skill").unwrap();

        assert!(Scanner::validate_skill_dir(&valid_dir));

        let invalid_dir = dir.path().join("invalid");
        fs::create_dir_all(&invalid_dir).unwrap();
        fs::write(invalid_dir.join("SKILL.md"), "# Skill").unwrap();

        assert!(!Scanner::validate_skill_dir(&invalid_dir));
    }

    #[test]
    fn test_scan_parses_manifest_fields() {
        let dir = TempDir::new().unwrap();
        create_test_skill(dir.path(), "refactor", "Refactor code safely");

        let scanner = Scanner::new(dir.path().to_path_buf());
        let skills = scanner.scan_all().unwrap();

        assert_eq!(skills.len(), 1);
        let skill = &skills[0];
        assert_eq!(skill.manifest.name, "refactor");
        assert_eq!(skill.manifest.description, "Refactor code safely");
        assert_eq!(skill.manifest.version, "1.0.0");
        assert!(!skill.installed_at.is_empty());
    }
}
