use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::RwLock;

use super::discovery::{default_project_roots, detect_project_type, discover_projects_in_root};
use super::git::{GitError, GitManager};
use super::models::{
    GitBranches, GitCommit, GitCommitResult, GitStatus, ProjectInfo, ProjectSummary,
};
use crate::files::path::{is_within_scopes, normalize_path};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProjectRoot {
    pub name: String,
    pub path: String,
}

#[derive(Debug, thiserror::Error)]
pub enum ProjectError {
    #[error("Project not found: {0}")]
    ProjectNotFound(String),
    #[error("Project path is outside allowed project roots: {0}")]
    ProjectNotAllowed(String),
    #[error("Directory is not a Git repository: {0}")]
    NotAGitRepository(String),
    #[error(transparent)]
    Git(#[from] GitError),
}

pub struct ProjectManager {
    allowed_roots: RwLock<Vec<PathBuf>>,
}

impl Default for ProjectManager {
    fn default() -> Self {
        Self::new()
    }
}

impl ProjectManager {
    pub fn new() -> Self {
        let roots = default_project_roots();
        let mut scopes: Vec<PathBuf> = roots.into_iter().map(|(_, p)| p).collect();
        if let Ok(cwd) = std::env::current_dir() {
            if !scopes.contains(&cwd) {
                scopes.push(cwd);
            }
        }
        Self {
            allowed_roots: RwLock::new(scopes),
        }
    }

    pub fn with_roots(roots: Vec<PathBuf>) -> Self {
        Self {
            allowed_roots: RwLock::new(roots),
        }
    }

    pub fn roots(&self) -> Vec<ProjectRoot> {
        default_project_roots()
            .into_iter()
            .map(|(name, path)| ProjectRoot {
                name,
                path: path.to_string_lossy().to_string(),
            })
            .collect()
    }

    pub fn allowed_roots(&self) -> Vec<PathBuf> {
        self.allowed_roots.read().unwrap().clone()
    }

    pub fn validate_project_path(&self, raw_path: &str) -> Result<PathBuf, ProjectError> {
        let normalized = normalize_path(raw_path);
        let roots = self.allowed_roots.read().unwrap();

        if !is_within_scopes(&normalized, &roots) {
            return Err(ProjectError::ProjectNotAllowed(format!(
                "Path '{}' is not within any allowed project root.",
                raw_path
            )));
        }

        if !normalized.exists() || !normalized.is_dir() {
            return Err(ProjectError::ProjectNotFound(
                normalized.to_string_lossy().to_string(),
            ));
        }

        Ok(normalized)
    }

    pub fn list(&self, raw_root_path: Option<&str>) -> Result<Vec<ProjectSummary>, ProjectError> {
        if let Some(root_str) = raw_root_path {
            let path = self.validate_project_path(root_str)?;
            Ok(discover_projects_in_root(&path))
        } else {
            // Aggregate from all allowed roots
            let roots = self.allowed_roots.read().unwrap();
            let mut all_projects = Vec::new();
            for root in roots.iter() {
                if root.exists() && root.is_dir() {
                    let mut found = discover_projects_in_root(root);
                    all_projects.append(&mut found);
                }
            }
            all_projects.sort_by(|a, b| a.path.cmp(&b.path));
            all_projects.dedup_by(|a, b| a.path == b.path);
            all_projects.sort_by_key(|a| a.name.to_lowercase());
            Ok(all_projects)
        }
    }

    pub fn info(&self, raw_path: &str) -> Result<ProjectInfo, ProjectError> {
        let path = self.validate_project_path(raw_path)?;
        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unnamed")
            .to_string();

        let is_git = GitManager::is_git_repo(&path);
        let project_type = detect_project_type(&path);

        let git_status = if is_git {
            GitManager::status(&path).ok()
        } else {
            None
        };

        Ok(ProjectInfo {
            name,
            path: path.to_string_lossy().to_string(),
            kind: if is_git { "git".to_string() } else { "directory".to_string() },
            project_type,
            git: git_status,
        })
    }

    // ==========================================
    // Git Operations Delegations
    // ==========================================

    fn get_git_repo(&self, raw_path: &str) -> Result<PathBuf, ProjectError> {
        let path = self.validate_project_path(raw_path)?;
        if !GitManager::is_git_repo(&path) {
            return Err(ProjectError::NotAGitRepository(
                path.to_string_lossy().to_string(),
            ));
        }
        Ok(path)
    }

    pub fn git_status(&self, raw_path: &str) -> Result<GitStatus, ProjectError> {
        let path = self.get_git_repo(raw_path)?;
        Ok(GitManager::status(&path)?)
    }

    pub fn git_branches(&self, raw_path: &str) -> Result<GitBranches, ProjectError> {
        let path = self.get_git_repo(raw_path)?;
        Ok(GitManager::branches(&path)?)
    }

    pub fn git_checkout(&self, raw_path: &str, branch: &str) -> Result<GitStatus, ProjectError> {
        let path = self.get_git_repo(raw_path)?;
        Ok(GitManager::checkout(&path, branch)?)
    }

    pub fn git_create_branch(&self, raw_path: &str, name: &str) -> Result<GitStatus, ProjectError> {
        let path = self.get_git_repo(raw_path)?;
        Ok(GitManager::create_branch(&path, name)?)
    }

    pub fn git_stage(&self, raw_path: &str, paths: &[String]) -> Result<GitStatus, ProjectError> {
        let path = self.get_git_repo(raw_path)?;
        Ok(GitManager::stage(&path, paths)?)
    }

    pub fn git_unstage(&self, raw_path: &str, paths: &[String]) -> Result<GitStatus, ProjectError> {
        let path = self.get_git_repo(raw_path)?;
        Ok(GitManager::unstage(&path, paths)?)
    }

    pub fn git_commit(&self, raw_path: &str, message: &str) -> Result<GitCommitResult, ProjectError> {
        let path = self.get_git_repo(raw_path)?;
        Ok(GitManager::commit(&path, message)?)
    }

    pub fn git_log(&self, raw_path: &str, limit: usize) -> Result<Vec<GitCommit>, ProjectError> {
        let path = self.get_git_repo(raw_path)?;
        Ok(GitManager::log(&path, limit)?)
    }
}
