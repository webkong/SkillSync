use std::path::Path;

use git2::{Cred, RemoteCallbacks, Repository, Status, StatusOptions};

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

    /// Initialize a new git repository at the given path.
    /// Creates the repo, sets up .gitignore, and makes an initial commit.
    pub fn init(repo_path: &Path) -> Result<Self, String> {
        // Create directory if it doesn't exist
        std::fs::create_dir_all(repo_path)
            .map_err(|e| format!("Failed to create directory {}: {}", repo_path.display(), e))?;

        let mut repo = Repository::init(repo_path)
            .map_err(|e| format!("Failed to init git repo at {}: {}", repo_path.display(), e))?;

        // Configure local user for commits
        let mut config = repo.config()
            .map_err(|e| format!("Failed to get repo config: {}", e))?;
        config.set_str("user.name", "Agent Skills Manager")
            .map_err(|e| format!("Failed to set user.name: {}", e))?;
        config.set_str("user.email", "asm@local")
            .map_err(|e| format!("Failed to set user.email: {}", e))?;
        drop(config);

        // Create .gitignore if it doesn't exist
        let gitignore_path = repo_path.join(".gitignore");
        if !gitignore_path.exists() {
            std::fs::write(&gitignore_path, ".DS_Store\n*.swp\n")
                .map_err(|e| format!("Failed to write .gitignore: {}", e))?;
        }

        // Stage and make initial commit
        let mut index = repo.index()
            .map_err(|e| format!("Failed to get index: {}", e))?;
        index.add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)
            .map_err(|e| format!("Failed to stage files: {}", e))?;
        index.write()
            .map_err(|e| format!("Failed to write index: {}", e))?;

        let tree_oid = index.write_tree()
            .map_err(|e| format!("Failed to write tree: {}", e))?;
        drop(index);

        let tree = repo.find_tree(tree_oid)
            .map_err(|e| format!("Failed to find tree: {}", e))?;
        let sig = repo.signature()
            .map_err(|e| format!("Failed to get signature: {}", e))?;

        // Create initial commit (HEAD is unborn in a fresh repo, so no parent)
        repo.commit(Some("HEAD"), &sig, &sig, "Initial commit", &tree, &[])
            .map_err(|e| format!("Failed to create initial commit: {}", e))?;

        drop(tree);
        drop(sig);

        Ok(Self { repo })
    }

    /// Open an existing repo, or initialize a new one if it doesn't exist.
    pub fn open_or_init(repo_path: &Path) -> Result<Self, String> {
        if repo_path.join(".git").exists() {
            Self::open(repo_path)
        } else {
            Self::init(repo_path)
        }
    }

    /// Build RemoteCallbacks with PAT token authentication.
    fn make_remote_callbacks(token: &str) -> RemoteCallbacks<'static> {
        let token = token.to_string();
        let mut callbacks = RemoteCallbacks::new();

        let token_clone = token.clone();
        callbacks.credentials(move |_url, username_from_url, _allowed_types| {
            let user = username_from_url
                .map(|u| u.to_string())
                .unwrap_or_else(|| "x-access-token".to_string());
            Cred::userpass_plaintext(&user, &token_clone)
        });

        // Allow self-signed certs (needed for self-hosted GitLab / Other)
        callbacks.certificate_check(|_cert, _host| Ok(git2::CertificateCheckStatus::CertificateOk));

        callbacks
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

    /// Set (or create) the "origin" remote URL.
    pub fn set_remote_url(&self, url: &str) -> Result<(), String> {
        if self.repo.find_remote("origin").is_ok() {
            self.repo.remote_set_url("origin", url)
                .map_err(|e| format!("Failed to set remote URL: {}", e))?;
        } else {
            self.repo.remote("origin", url)
                .map_err(|e| format!("Failed to create remote 'origin': {}", e))?;
        }
        Ok(())
    }

    /// Detect the current branch name.
    fn current_branch(&self) -> Result<String, String> {
        let head = self.repo.head()
            .map_err(|e| format!("Failed to get HEAD: {}", e))?;
        let name = head.shorthand()
            .ok_or("HEAD is not on a branch")?;
        Ok(name.to_string())
    }

    /// Fetch from origin using the given token for auth (or no auth if None).
    fn fetch_origin(&self, branch: &str, token: Option<&str>) -> Result<(), String> {
        let mut remote = self.repo.find_remote("origin")
            .map_err(|e| format!("Failed to find remote 'origin': {}", e))?;

        let mut fetch_options = git2::FetchOptions::new();
        if let Some(tok) = token {
            fetch_options.remote_callbacks(Self::make_remote_callbacks(tok));
        }

        remote.fetch(&[branch], Some(&mut fetch_options), None)
            .map_err(|e| format!("Failed to fetch from origin: {}", e))?;

        Ok(())
    }

    /// Check if working directory has local changes (unstaged or untracked).
    fn has_local_changes(&self) -> Result<bool, String> {
        let statuses = self.repo.statuses(Some(
            StatusOptions::new().include_untracked(true),
        ))
        .map_err(|e| format!("Failed to check status: {}", e))?;
        Ok(statuses.iter().any(|s| !s.status().is_empty()))
    }

    /// Pull (fetch + rebase) from origin. Does NOT stage, commit, or push.
    pub fn pull(&mut self, token: Option<&str>) -> Result<GitStatusInfo, String> {
        let branch = self.current_branch()?;

        // Stash any local changes before pulling
        let need_stash = self.has_local_changes()?;

        if need_stash {
            let sig = self.repo.signature()
                .map_err(|e| format!("Failed to get signature: {}", e))?;
            self.repo.stash_save(&sig, "auto-stash before pull", None::<git2::StashFlags>)
                .map_err(|e| format!("Failed to stash: {}", e))?;
        }

        // Fetch
        self.fetch_origin(&branch, token)?;

        // Rebase onto FETCH_HEAD — scoped to release all borrows before stash_pop
        {
            let fetch_head = self.repo.find_reference("FETCH_HEAD")
                .map_err(|e| format!("Failed to find FETCH_HEAD: {}", e))?;
            let upstream = self.repo.reference_to_annotated_commit(&fetch_head)
                .map_err(|e| format!("Failed to resolve FETCH_HEAD: {}", e))?;
            drop(fetch_head);

            let mut rebase = self.repo.rebase(
                None,
                Some(&upstream),
                None,
                Some(&mut git2::RebaseOptions::new()),
            )
            .map_err(|e| format!("Failed to start rebase: {}", e))?;

            let sig = self.repo.signature()
                .map_err(|e| format!("Failed to get signature: {}", e))?;

            while let Some(op) = rebase.next() {
                op.map_err(|e| format!("Rebase step failed: {}", e))?;
                if rebase.commit(None, &sig, None).is_err() {
                    // Nothing to commit for this step, skip
                }
            }

            rebase.finish(None)
                .map_err(|e| format!("Failed to finish rebase: {}", e))?;
        }
        // All borrows released here

        // Pop stash if we stashed
        if need_stash {
            let _ = self.repo.stash_pop(0, None);
        }

        Ok(GitStatusInfo::synced())
    }

    /// Stage all changes, commit with message, and push.
    pub fn stage_and_push(&mut self, message: &str, token: Option<&str>) -> Result<GitStatusInfo, String> {
        // Step 1: Stage all changes
        let mut index = self.repo.index()
            .map_err(|e| format!("Failed to get index: {}", e))?;

        index.add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)
            .map_err(|e| format!("Failed to stage files: {}", e))?;

        index.write()
            .map_err(|e| format!("Failed to write index: {}", e))?;

        let tree_oid = index.write_tree()
            .map_err(|e| format!("Failed to write tree: {}", e))?;

        // Drop index before subsequent repo operations
        drop(index);

        let tree = self.repo.find_tree(tree_oid)
            .map_err(|e| format!("Failed to find tree: {}", e))?;

        // Step 2: Create commit
        let signature = self.repo.signature()
            .map_err(|e| format!("Failed to get signature: {}", e))?;

        let head = self.repo.head()
            .map_err(|e| format!("Failed to get HEAD: {}", e))?;
        let parent_oid = head.target().ok_or("HEAD has no target")?;
        drop(head);

        let parent = self.repo.find_commit(parent_oid)
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

        // Drop tree and parent before pull_rebase needs &mut self
        drop(tree);
        drop(parent);

        // Step 3: Pull --rebase (if there's a remote)
        if self.has_remote() {
            if let Err(e) = self.pull_rebase(token) {
                return Ok(GitStatusInfo::error(&format!("Pull rebase failed: {}", e)));
            }
        }

        // Step 4: Push
        if self.has_remote() {
            self.push(token)?;
        }

        Ok(GitStatusInfo::synced())
    }

    /// Check if the repository has a remote configured.
    fn has_remote(&self) -> bool {
        self.repo.find_remote("origin").is_ok()
    }

    /// Execute git pull --rebase (fetch + rebase).
    fn pull_rebase(&mut self, token: Option<&str>) -> Result<(), String> {
        let branch = self.current_branch()?;

        // Fetch from origin
        self.fetch_origin(&branch, token)?;

        // Get the FETCH_HEAD
        let fetch_head = self.repo.find_reference("FETCH_HEAD")
            .map_err(|e| format!("Failed to find FETCH_HEAD: {}", e))?;
        let upstream = self.repo.reference_to_annotated_commit(&fetch_head)
            .map_err(|e| format!("Failed to resolve FETCH_HEAD: {}", e))?;

        // Drop fetch_head before rebase
        drop(fetch_head);

        // Rebase onto fetched commit
        let mut rebase = self.repo.rebase(
            None,
            Some(&upstream),
            None,
            Some(&mut git2::RebaseOptions::new()),
        )
        .map_err(|e| format!("Failed to start rebase: {}", e))?;

        let sig = self.repo.signature()
            .map_err(|e| format!("Failed to get signature: {}", e))?;

        // Iterate rebase steps
        while let Some(op) = rebase.next() {
            op.map_err(|e| format!("Rebase step failed: {}", e))?;
            if rebase.commit(None, &sig, None).is_err() {
                // Nothing to commit, skip
            }
        }

        rebase.finish(None)
            .map_err(|e| format!("Failed to finish rebase: {}", e))?;

        Ok(())
    }

    /// Push to origin.
    fn push(&self, token: Option<&str>) -> Result<(), String> {
        let mut remote = self.repo.find_remote("origin")
            .map_err(|e| format!("Failed to find remote 'origin': {}", e))?;

        let branch = self.current_branch().unwrap_or_else(|_| "main".to_string());
        let refspec = format!("refs/heads/{branch}:refs/heads/{branch}");

        let mut push_options = git2::PushOptions::new();
        if let Some(tok) = token {
            push_options.remote_callbacks(Self::make_remote_callbacks(tok));
        }

        remote.push(&[&refspec], Some(&mut push_options))
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
        fs::write(dir.path().join("README.md"), "# Modified\n").unwrap();
        let engine = GitEngine::open(dir.path()).unwrap();
        let status = engine.get_status().unwrap();
        assert_eq!(status.status, "modified");
    }

    #[test]
    fn test_get_pending_changes() {
        let dir = TempDir::new().unwrap();
        init_git_repo(dir.path());
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
        fs::write(dir.path().join("README.md"), "# Updated\n").unwrap();
        let mut engine = GitEngine::open(dir.path()).unwrap();
        let result = engine.stage_and_push("test: update README", None);
        assert!(result.is_ok());
        let status = engine.get_status().unwrap();
        assert_eq!(status.status, "idle");
    }

    #[test]
    fn test_set_remote_url() {
        let dir = TempDir::new().unwrap();
        init_git_repo(dir.path());
        let engine = GitEngine::open(dir.path()).unwrap();
        engine.set_remote_url("https://github.com/test/repo.git").unwrap();
        let remote = engine.repo.find_remote("origin").unwrap();
        assert_eq!(remote.url().unwrap(), "https://github.com/test/repo.git");
    }

    #[test]
    fn test_update_remote_url() {
        let dir = TempDir::new().unwrap();
        init_git_repo(dir.path());
        let engine = GitEngine::open(dir.path()).unwrap();
        engine.set_remote_url("https://github.com/test/repo.git").unwrap();
        engine.set_remote_url("https://gitlab.com/test/repo.git").unwrap();
        let remote = engine.repo.find_remote("origin").unwrap();
        assert_eq!(remote.url().unwrap(), "https://gitlab.com/test/repo.git");
    }
}
