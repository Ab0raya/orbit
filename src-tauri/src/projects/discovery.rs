use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use super::git::GitManager;
use super::models::{ProjectGitSummary, ProjectSummary};

const MAX_DISCOVERY_DEPTH: usize = 4;

/// Returns allowed project browse roots (e.g. Home, Projects, Workspace)
pub fn default_project_roots() -> Vec<(String, PathBuf)> {
    let mut roots = Vec::new();

    // 1. Current workspace root
    if let Ok(cwd) = env::current_dir() {
        // In a Tauri desktop project, the backend runs from `src-tauri`.
        // If current directory is `src-tauri`, the actual project root is its parent.
        let ws = if cwd.file_name().map(|s| s == "src-tauri").unwrap_or(false) {
            cwd.parent().map(|p| p.to_path_buf()).unwrap_or(cwd)
        } else {
            cwd
        };
        roots.push(("Workspace".to_string(), ws));
    }

    // 2. Common developer directories under Home
    if let Ok(home) = env::var("HOME").or_else(|_| env::var("USERPROFILE")) {
        let home_path = PathBuf::from(&home);

        // Check for common project directories
        for sub in &["Projects", "Development", "Workspace", "Repos", "code"] {
            let candidate = home_path.join(sub);
            if candidate.exists()
                && candidate.is_dir()
                && !roots.iter().any(|(_, p)| p == &candidate)
            {
                roots.push((sub.to_string(), candidate));
            }
        }

        if !roots.iter().any(|(_, p)| p == &home_path) {
            roots.push(("Home".to_string(), home_path));
        }
    }

    if roots.is_empty() {
        roots.push(("Root".to_string(), PathBuf::from("/")));
    }

    roots
}

/// Detects project framework / technology based on marker files
pub fn detect_project_type(path: &Path) -> String {
    if path.join("pubspec.yaml").exists() {
        "flutter".to_string()
    } else if path.join("Cargo.toml").exists() {
        "rust".to_string()
    } else if path.join("package.json").exists() {
        "node".to_string()
    } else if path.join("pyproject.toml").exists() || path.join("requirements.txt").exists() {
        "python".to_string()
    } else if path.join("build.gradle").exists() || path.join("android").exists() {
        "android".to_string()
    } else {
        "generic".to_string()
    }
}

fn is_ignored_directory(name: &str) -> bool {
    if name.starts_with('.') {
        return true;
    }
    matches!(
        name,
        "node_modules"
            | "target"
            | "dist"
            | "build"
            | ".dart_tool"
            | "vendor"
            | "Pods"
            | "__pycache__"
            | ".next"
            | ".nuxt"
            | "out"
            | "coverage"
            | ".expo"
    )
}

fn evaluate_project(path: &Path) -> Option<ProjectSummary> {
    let is_git = GitManager::is_git_repo(path);
    let project_type = detect_project_type(path);

    let is_project = is_git || project_type != "generic";
    if is_project {
        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("project")
            .to_string();

        let git_summary = if is_git {
            GitManager::status(path)
                .ok()
                .map(|status| ProjectGitSummary {
                    branch: status.branch,
                    is_dirty: !status.clean,
                })
        } else {
            None
        };

        Some(ProjectSummary {
            name,
            path: path.to_string_lossy().to_string(),
            kind: if is_git {
                "git".to_string()
            } else {
                "directory".to_string()
            },
            project_type,
            git: git_summary,
        })
    } else {
        None
    }
}

fn scan_directory_recursive(
    dir: &Path,
    current_depth: usize,
    max_depth: usize,
    projects: &mut Vec<ProjectSummary>,
) {
    let read_dir = match fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return,
    };

    for entry_res in read_dir {
        let entry = match entry_res {
            Ok(e) => e,
            Err(_) => continue,
        };

        let path = entry.path();
        if !path.is_dir() {
            continue;
        }

        let name = entry.file_name().to_string_lossy().to_string();
        if is_ignored_directory(&name) {
            continue;
        }

        if let Some(summary) = evaluate_project(&path) {
            projects.push(summary);
        }

        if current_depth < max_depth {
            scan_directory_recursive(&path, current_depth + 1, max_depth, projects);
        }
    }
}

/// Discovers projects inside an allowed root (including root itself and nested directories)
pub fn discover_projects_in_root(root: &Path) -> Vec<ProjectSummary> {
    let mut projects = Vec::new();

    // 1. Check if the root directory itself is a project
    if let Some(root_summary) = evaluate_project(root) {
        projects.push(root_summary);
    }

    // 2. Discover projects in subdirectories recursively
    scan_directory_recursive(root, 1, MAX_DISCOVERY_DEPTH, &mut projects);

    projects.sort_by(|a, b| a.path.cmp(&b.path));
    projects.dedup_by(|a, b| a.path == b.path);
    projects.sort_by_key(|a| a.name.to_lowercase());
    projects
}
