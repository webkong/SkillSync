use std::path::Path;

use git2::{Repository, Status, StatusOptions};

use crate::models::{GitStatusInfo, PendingChange};

pub struct GitEngine {
    repo: Repository,
}

impl GitEngine {
    /// Open an existing git repository.
    pub fn open(repo_path: &Path) -> Result<Self, String> {
        let repo = Repository::open(repo_path)
            .map_err(|e| format!("Failed to open git repository at {}: {}", repo_path.display(), e))?;
        Ok(Self { repo })
    }

    /// Get the current git status.
    pub fn get_status(&self) -> Result<GitStatusInfo, String> {
        let statuses = self.repo.statuses(Some(
            StatusOptions::new()
                .include_untracked(true)
                .renames_head_to_index(true),
        ))
        .map_err(|e| format!("Failed to get status: {}", e))?;

        if statuses.is_empty() {
            return Ok(GitStatusInfo::idle());
        }

        let has_conflicts = statuses.iter().any(|s| {
            let status = s.status();
            status.contains(Status::CONFLICTED)
        });

        if has_conflicts {
            let count = statuses.iter().filter(|s| s.status().contains(Status::CONFLICTED)).count();
            return Ok(GitStatusInfo::conflicted(&format!("{} file(s) have merge conflicts", count)));
        }

        let modified_count = statuses.len();
        Ok(GitStatusInfo::modified(&format!("{} file(s) modified", modified_count)))
    }

    /// Get a list of pending changes (modified, added, deleted files).
    pub fn get_pending_changes(&self) -> Result<Vec<PendingChange>, String> {
        let statuses = self.repo.statuses(Some(
            StatusOptions::new()
                .include_untracked(true)
                .renames_head_to_index(true),
        ))
        .map_err(|e| format!("Failed to get status: {}", e))?;

        let changes: Vec<PendingChange> = statuses
            .iter()
            .filter_map(|s| {
                let path = s.path()?.to_string();
                let status = s.status();

                let change_type = if status.contains(Status::INDEX_NEW) || status.contains(Status::WT_NEW) {
                    "added"
                } else if status.contains(Status::INDEX_DELETED) || status.contains(Status::WT_DELETED) {
                    "deleted"
                } else {
                    "modified"
                };

                Some(PendingChange {
                    file_path: path,
                    change_type: change_type.to_string(),
                })
            })
            .collect();

        Ok(changes)
    }

    /// Stage all changes, commit with message, and push.
    /// Uses git pull --rebase before push to handle upstream changes.
    pub fn stage_and_push(&self, message: &str) -> Result<GitStatusInfo, String> {
        // Step 1: Stage all changes
        let mut index = self.repo.index()
            .map_err(|e| format!("Failed to get index: {}", e))?;

        index.add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)
            .map_err(|e| format!("Failed to stage files: {}", e))?;

        index.write()
            .map_err(|e| format!("Failed to write index: {}", e))?;

        let tree_oid = index.write_tree()
            .map_err(|e| format!("Failed to write tree: {}", e))?;
        let tree = self.repo.find_tree(tree_oid)
            .map_err(|e| format!("Failed to find tree: {}", e))?;

        // Step 2: Create commit
        let signature = self.repo.signature()
            .map_err(|e| format!("Failed to get signature: {}", e))?;

        let head = self.repo.head()
            .map_err(|e| format!("Failed to get HEAD: {}", e))?;
        let parent = self.repo.find_commit(head.target().ok_or("HEAD has no target")?)
            .map_err(|e| format!("Failed to find parent commit: {}", e))?;

        self.repo.commit(
            Some("HEAD"),
            &signature,
            &signature,
            message,
            &tree,
            &[&parent],
        )
        .map_err(|e| format!("Failed to commit: {}", e))?;

        // Step 3: Pull --rebase (if there's a remote)
        if self.has_remote() {
            if let Err(e) = self.pull_rebase() {
                return Ok(GitStatusInfo::error(&format!("Pull rebase failed: {}", e)));
            }
        }

        // Step 4: Push
        if self.has_remote() {
            self.push()?;
        }

        Ok(GitStatusInfo::synced())
    }

    /// Check if the repository has a remote configured.
    fn has_remote(&self) -> bool {
        self.repo.find_remote("origin").is_ok()
    }

    /// Execute git pull --rebase.
    fn pull_rebase(&self) -> Result<(), String> {
        let mut remote = self.repo.find_remote("origin")
            .map_err(|e| format!("Failed to find remote 'origin': {}", e))?;

        // Fetch from origin
        let mut fetch_options = git2::FetchOptions::new();
        remote.fetch(&["main"], Some(&mut fetch_options), None)
            .map_err(|e| format!("Failed to fetch from origin: {}", e))?;

        // Get the FETCH_HEAD
        let fetch_head = self.repo.find_reference("FETCH_HEAD")
            .map_err(|e| format!("Failed to find FETCH_HEAD: {}", e))?;
        let fetch_commit = self.repo.reference_to_annotated_commit(&fetch_head)
            .map_err(|e| format!("Failed to resolve FETCH_HEAD: {}", e))?;

        // Rebase onto fetched commit
        let mut rebase_options = git2::RebaseOptions::new();
        self.repo.rebase(
            None,
            Some(&fetch_commit),
            None,
            Some(&mut rebase_options),
        )
        .map_err(|e| format!("Failed to rebase: {}", e))?;

        Ok(())
    }

    /// Push to origin.
    fn push(&self) -> Result<(), String> {
        let mut remote = self.repo.find_remote("origin")
            .map_err(|e| format!("Failed to find remote 'origin': {}", e))?;

        let mut push_options = git2::PushOptions::new();

        remote.push(&["refs/heads/main:refs/heads/main"], Some(&mut push_options))
            .map_err(|e| format!("Failed to push: {}", e))?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::process::Command;
    use tempfile::TempDir;

    fn init_git_repo(path: &Path) {
        Command::new("git")
            .args(["init"])
            .current_dir(path)
            .output()
            .expect("Failed to git init");

        // Configure git user for commits
        Command::new("git")
            .args(["config", "user.email", "test@test.com"])
            .current_dir(path)
            .output()
            .unwrap();
        Command::new("git")
            .args(["config", "user.name", "Test User"])
            .current_dir(path)
            .output()
            .unwrap();

        // Create initial commit
        fs::write(path.join("README.md"), "# Test\n").unwrap();
        Command::new("git")
            .args(["add", "."])
            .current_dir(path)
            .output()
            .unwrap();
        Command::new("git")
            .args(["commit", "-m", "Initial commit"])
            .current_dir(path)
            .output()
            .unwrap();
    }

    #[test]
    fn test_open_existing_repo() {
        let dir = TempDir::new().unwrap();
        init_git_repo(dir.path());

        let engine = GitEngine::open(dir.path());
        assert!(engine.is_ok());
    }

    #[test]
    fn test_get_idle_status() {
        let dir = TempDir::new().unwrap();
        init_git_repo(dir.path());

        let engine = GitEngine::open(dir.path()).unwrap();
        let status = engine.get_status().unwrap();
        assert_eq!(status.status, "idle");
    }

    #[test]
    fn test_get_modified_status() {
        let dir = TempDir::new().unwrap();
        init_git_repo(dir.path());

        // Modify a file
        fs::write(dir.path().join("README.md"), "# Modified\n").unwrap();

        let engine = GitEngine::open(dir.path()).unwrap();
        let status = engine.get_status().unwrap();
        assert_eq!(status.status, "modified");
    }

    #[test]
    fn test_get_pending_changes() {
        let dir = TempDir::new().unwrap();
        init_git_repo(dir.path());

        // Create and modify files
        fs::write(dir.path().join("README.md"), "# Modified\n").unwrap();
        fs::write(dir.path().join("new-file.txt"), "new\n").unwrap();

        let engine = GitEngine::open(dir.path()).unwrap();
        let changes = engine.get_pending_changes().unwrap();

        assert!(!changes.is_empty());
        assert!(changes.iter().any(|c| c.file_path == "README.md"));
    }

    #[test]
    fn test_stage_and_commit() {
        let dir = TempDir::new().unwrap();
        init_git_repo(dir.path());

        // Modify a file
        fs::write(dir.path().join("README.md"), "# Updated\n").unwrap();

        let engine = GitEngine::open(dir.path()).unwrap();

        // Stage and commit (no remote, so skip push)
        let result = engine.stage_and_push("test: update README");
        // This might fail on push if no remote, but commit should work
        // The synced status indicates success (push skipped when no remote)
        assert!(result.is_ok());

        // Verify status is now idle
        let status = engine.get_status().unwrap();
        assert_eq!(status.status, "idle");
    }
}
