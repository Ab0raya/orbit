use std::path::{Component, Path};
use std::process::{Command, Output};

use super::models::{GitBranches, GitCommit, GitCommitResult, GitFileChange, GitStatus};

#[derive(Debug, thiserror::Error)]
pub enum GitError {
    #[error("Directory is not a Git repository: {0}")]
    NotAGitRepository(String),
    #[error("Git is not installed or not in system PATH")]
    GitNotInstalled,
    #[error("Git operation failed: {0}")]
    GitOperationFailed(String),
    #[error("Invalid branch name: {0}")]
    InvalidBranchName(String),
    #[error("Invalid file path: {0}")]
    InvalidFilePath(String),
    #[error("Commit message cannot be empty")]
    CommitMessageEmpty,
    #[error("Checkout conflict: local changes would be overwritten: {0}")]
    CheckoutConflict(String),
}

pub struct GitManager;

impl GitManager {
    /// Validates branch name according to git check-ref-format rules
    pub fn is_valid_branch_name(name: &str) -> bool {
        let name = name.trim();
        if name.is_empty()
            || name.starts_with('-')
            || name.starts_with('/')
            || name.ends_with('/')
            || name.ends_with('.')
            || name.contains("..")
            || name.contains("@{")
            || name.contains('~')
            || name.contains('^')
            || name.contains(':')
            || name.contains('?')
            || name.contains('*')
            || name.contains('[')
            || name.contains('\\')
            || name.contains("//")
            || name == "HEAD"
        {
            return false;
        }

        // Must not contain ASCII control characters or space
        !name
            .chars()
            .any(|c| c.is_ascii_control() || c.is_whitespace())
    }

    /// Validates that a file path is strictly relative and does not escape repo
    pub fn is_safe_relative_path(path_str: &str) -> bool {
        let path_str = path_str.trim();
        if path_str.is_empty() || path_str.starts_with('/') || path_str.starts_with('\\') {
            return false;
        }

        let path = Path::new(path_str);
        // No parent dir traversal
        for component in path.components() {
            match component {
                Component::ParentDir => return false,
                Component::RootDir | Component::Prefix(_) => return false,
                _ => {}
            }
        }

        true
    }

    /// Executes a Git command safely using argument vectors
    fn run_git(repo_path: &Path, args: &[&str]) -> Result<Output, GitError> {
        let mut cmd = Command::new("git");
        cmd.current_dir(repo_path)
            .args(args)
            .env("PAGER", "cat")
            .env("GIT_TERMINAL_PROMPT", "0");

        let output = cmd.output().map_err(|e| {
            if e.kind() == std::io::ErrorKind::NotFound {
                GitError::GitNotInstalled
            } else {
                GitError::GitOperationFailed(format!("Failed to spawn git: {}", e))
            }
        })?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            if stderr.contains("not a git repository") {
                return Err(GitError::NotAGitRepository(
                    repo_path.to_string_lossy().to_string(),
                ));
            }
            if stderr.contains("local changes") && stderr.contains("would be overwritten") {
                return Err(GitError::CheckoutConflict(stderr));
            }
            return Err(GitError::GitOperationFailed(stderr));
        }

        Ok(output)
    }

    /// Checks if a directory is a Git repository
    pub fn is_git_repo(path: &Path) -> bool {
        path.join(".git").exists()
    }

    /// Returns detailed Git status
    pub fn status(repo_path: &Path) -> Result<GitStatus, GitError> {
        let output = Self::run_git(repo_path, &["status", "--porcelain=v1", "-b"])?;
        let stdout = String::from_utf8_lossy(&output.stdout);

        let mut branch = "HEAD".to_string();
        let mut staged = Vec::new();
        let mut unstaged = Vec::new();
        let mut untracked = Vec::new();

        for line in stdout.lines() {
            if let Some(branch_line) = line.strip_prefix("## ") {
                // e.g. "main...origin/main [ahead 1]" or "main" or "HEAD (no branch)"
                let b = if let Some((name, _)) = branch_line.split_once("...") {
                    name.trim()
                } else if branch_line.starts_with("HEAD (no branch") {
                    "detached"
                } else {
                    branch_line.trim()
                };
                branch = b.to_string();
                continue;
            }

            if line.len() < 3 {
                continue;
            }

            let x = line.chars().next().unwrap_or(' ');
            let y = line.chars().nth(1).unwrap_or(' ');
            let file_path = line[3..].trim().to_string();

            // Untracked files
            if x == '?' && y == '?' {
                untracked.push(GitFileChange {
                    path: file_path,
                    status: "untracked".to_string(),
                });
                continue;
            }

            // Ignored files
            if x == '!' && y == '!' {
                continue;
            }

            // Staged changes (index)
            if x != ' ' && x != '?' {
                let status_str = match x {
                    'M' => "modified",
                    'A' => "added",
                    'D' => "deleted",
                    'R' => "renamed",
                    'C' => "copied",
                    _ => "modified",
                };
                staged.push(GitFileChange {
                    path: file_path.clone(),
                    status: status_str.to_string(),
                });
            }

            // Unstaged changes (worktree)
            if y != ' ' && y != '?' {
                let status_str = match y {
                    'M' => "modified",
                    'D' => "deleted",
                    _ => "modified",
                };
                unstaged.push(GitFileChange {
                    path: file_path,
                    status: status_str.to_string(),
                });
            }
        }

        let clean = staged.is_empty() && unstaged.is_empty() && untracked.is_empty();

        Ok(GitStatus {
            branch,
            clean,
            staged,
            unstaged,
            untracked,
        })
    }

    /// Returns local and remote branches
    pub fn branches(repo_path: &Path) -> Result<GitBranches, GitError> {
        let output = Self::run_git(repo_path, &["branch", "-a", "--no-color"])?;
        let stdout = String::from_utf8_lossy(&output.stdout);

        let mut current = "".to_string();
        let mut local = Vec::new();
        let mut remote = Vec::new();

        for line in stdout.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            let is_curr = line.starts_with('*');
            let branch_name = if is_curr {
                trimmed.strip_prefix('*').unwrap_or(trimmed).trim()
            } else {
                trimmed
            };

            if is_curr {
                current = branch_name.to_string();
            }

            if branch_name.starts_with("remotes/") {
                if !branch_name.contains("->") {
                    let clean_remote = branch_name.strip_prefix("remotes/").unwrap_or(branch_name);
                    remote.push(clean_remote.to_string());
                }
            } else {
                local.push(branch_name.to_string());
            }
        }

        if current.is_empty() && !local.is_empty() {
            current = local[0].clone();
        }

        Ok(GitBranches {
            current,
            local,
            remote,
        })
    }

    /// Switches branch safely
    pub fn checkout(repo_path: &Path, branch: &str) -> Result<GitStatus, GitError> {
        if !Self::is_valid_branch_name(branch) {
            return Err(GitError::InvalidBranchName(branch.to_string()));
        }

        Self::run_git(repo_path, &["checkout", branch])?;
        Self::status(repo_path)
    }

    /// Creates and switches to a new branch
    pub fn create_branch(repo_path: &Path, name: &str) -> Result<GitStatus, GitError> {
        if !Self::is_valid_branch_name(name) {
            return Err(GitError::InvalidBranchName(name.to_string()));
        }

        Self::run_git(repo_path, &["checkout", "-b", name])?;
        Self::status(repo_path)
    }

    /// Stages file paths
    pub fn stage(repo_path: &Path, paths: &[String]) -> Result<GitStatus, GitError> {
        if paths.is_empty() {
            return Self::status(repo_path);
        }

        for path in paths {
            if !Self::is_safe_relative_path(path) {
                return Err(GitError::InvalidFilePath(path.clone()));
            }
        }

        let mut args = vec!["add", "--"];
        args.extend(paths.iter().map(|s| s.as_str()));

        Self::run_git(repo_path, &args)?;
        Self::status(repo_path)
    }

    /// Unstages file paths
    pub fn unstage(repo_path: &Path, paths: &[String]) -> Result<GitStatus, GitError> {
        if paths.is_empty() {
            return Self::status(repo_path);
        }

        for path in paths {
            if !Self::is_safe_relative_path(path) {
                return Err(GitError::InvalidFilePath(path.clone()));
            }
        }

        let mut args = vec!["restore", "--staged", "--"];
        args.extend(paths.iter().map(|s| s.as_str()));

        if Self::run_git(repo_path, &args).is_err() {
            // Fallback for older git versions
            let mut reset_args = vec!["reset", "HEAD", "--"];
            reset_args.extend(paths.iter().map(|s| s.as_str()));
            Self::run_git(repo_path, &reset_args)?;
        }

        Self::status(repo_path)
    }

    /// Commits staged changes safely
    pub fn commit(repo_path: &Path, message: &str) -> Result<GitCommitResult, GitError> {
        let msg = message.trim();
        if msg.is_empty() {
            return Err(GitError::CommitMessageEmpty);
        }

        Self::run_git(repo_path, &["commit", "-m", msg])?;

        let hash_out = Self::run_git(repo_path, &["rev-parse", "HEAD"])?;
        let hash = String::from_utf8_lossy(&hash_out.stdout).trim().to_string();

        let branch_out = Self::run_git(repo_path, &["rev-parse", "--abbrev-ref", "HEAD"])?;
        let branch = String::from_utf8_lossy(&branch_out.stdout)
            .trim()
            .to_string();

        Ok(GitCommitResult {
            hash,
            branch,
            message: msg.to_string(),
        })
    }

    /// Returns recent commits
    pub fn log(repo_path: &Path, limit: usize) -> Result<Vec<GitCommit>, GitError> {
        let limit_val = limit.clamp(1, 100).to_string();
        let format_arg = "--format=%H|%h|%an|%at|%s";

        let output = Self::run_git(repo_path, &["log", "-n", &limit_val, format_arg])?;
        let stdout = String::from_utf8_lossy(&output.stdout);

        let mut commits = Vec::new();

        for line in stdout.lines() {
            let parts: Vec<&str> = line.splitn(5, '|').collect();
            if parts.len() == 5 {
                let timestamp = parts[3].parse::<u64>().unwrap_or(0);
                commits.push(GitCommit {
                    hash: parts[0].to_string(),
                    short_hash: parts[1].to_string(),
                    author: parts[2].to_string(),
                    timestamp,
                    message: parts[4].to_string(),
                });
            }
        }

        Ok(commits)
    }
}
