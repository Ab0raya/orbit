pub mod discovery;
pub mod git;
pub mod manager;
pub mod models;

pub use git::{GitError, GitManager};
pub use manager::{ProjectError, ProjectManager, ProjectRoot};
pub use models::*;

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use std::process::Command;

    struct TestSandbox {
        root: PathBuf,
        project_dir: PathBuf,
        manager: ProjectManager,
    }

    impl TestSandbox {
        fn new() -> Self {
            let temp_id = uuid::Uuid::new_v4();
            let root = std::env::temp_dir().join(format!("orbit_proj_test_{}", temp_id));
            fs::create_dir_all(&root).unwrap();

            let project_dir = root.join("my_app");
            fs::create_dir_all(&project_dir).unwrap();

            // Configure git repo inside project_dir
            Command::new("git")
                .args(["init", "-b", "main"])
                .current_dir(&project_dir)
                .output()
                .unwrap();

            Command::new("git")
                .args(["config", "user.name", "Orbit Tester"])
                .current_dir(&project_dir)
                .output()
                .unwrap();

            Command::new("git")
                .args(["config", "user.email", "tester@orbit.local"])
                .current_dir(&project_dir)
                .output()
                .unwrap();

            // Initial commit so we have a valid HEAD
            let init_file = project_dir.join("README.md");
            fs::write(&init_file, "# Orbit Test App").unwrap();

            Command::new("git")
                .args(["add", "README.md"])
                .current_dir(&project_dir)
                .output()
                .unwrap();

            Command::new("git")
                .args(["commit", "-m", "Initial commit"])
                .current_dir(&project_dir)
                .output()
                .unwrap();

            let manager = ProjectManager::with_roots(vec![root.clone()]);

            Self {
                root,
                project_dir,
                manager,
            }
        }
    }

    impl Drop for TestSandbox {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.root);
        }
    }

    #[test]
    fn test_branch_validation() {
        assert!(GitManager::is_valid_branch_name("main"));
        assert!(GitManager::is_valid_branch_name("feature/login"));
        assert!(GitManager::is_valid_branch_name("bugfix-123"));

        assert!(!GitManager::is_valid_branch_name(""));
        assert!(!GitManager::is_valid_branch_name("HEAD"));
        assert!(!GitManager::is_valid_branch_name("-invalid"));
        assert!(!GitManager::is_valid_branch_name("feature..branch"));
        assert!(!GitManager::is_valid_branch_name("feature branch"));
        assert!(!GitManager::is_valid_branch_name("feature/"));
        assert!(!GitManager::is_valid_branch_name("~test"));
        assert!(!GitManager::is_valid_branch_name("test:1"));
    }

    #[test]
    fn test_relative_path_validation() {
        assert!(GitManager::is_safe_relative_path("lib/main.dart"));
        assert!(GitManager::is_safe_relative_path("README.md"));
        assert!(GitManager::is_safe_relative_path("src/nested/file.rs"));

        assert!(!GitManager::is_safe_relative_path("/etc/passwd"));
        assert!(!GitManager::is_safe_relative_path("../outside.txt"));
        assert!(!GitManager::is_safe_relative_path("lib/../../outside.txt"));
        assert!(!GitManager::is_safe_relative_path(""));
    }

    #[test]
    fn test_project_discovery_and_framework_detection() {
        let sandbox = TestSandbox::new();

        // Create Flutter marker
        let pubspec = sandbox.project_dir.join("pubspec.yaml");
        fs::write(&pubspec, "name: my_app").unwrap();

        // Create a non-git Rust project
        let rust_proj = sandbox.root.join("rust_tool");
        fs::create_dir_all(&rust_proj).unwrap();
        fs::write(
            rust_proj.join("Cargo.toml"),
            "[package]\nname = \"rust_tool\"",
        )
        .unwrap();

        let list = sandbox
            .manager
            .list(Some(&sandbox.root.to_string_lossy()))
            .unwrap();

        assert_eq!(list.len(), 2);

        let p1 = list.iter().find(|p| p.name == "my_app").unwrap();
        assert_eq!(p1.kind, "git");
        assert_eq!(p1.project_type, "flutter");
        assert!(p1.git.is_some());

        let p2 = list.iter().find(|p| p.name == "rust_tool").unwrap();
        assert_eq!(p2.kind, "directory");
        assert_eq!(p2.project_type, "rust");
        assert!(p2.git.is_none());
    }

    #[test]
    fn test_recursive_nested_project_discovery() {
        let temp_id = uuid::Uuid::new_v4();
        let root = std::env::temp_dir().join(format!("orbit_nested_test_{}", temp_id));
        fs::create_dir_all(&root).unwrap();

        // 1. Nested project inside a category directory (like desktop_projects/my_project)
        let cat_proj = root.join("category_a").join("nested_node_app");
        fs::create_dir_all(&cat_proj).unwrap();
        fs::write(
            cat_proj.join("package.json"),
            "{\"name\": \"nested_node_app\"}",
        )
        .unwrap();

        // 2. Deeper nested project (depth 3)
        let deep_proj = root
            .join("category_b")
            .join("sub_category")
            .join("deep_rust_app");
        fs::create_dir_all(&deep_proj).unwrap();
        fs::write(
            deep_proj.join("Cargo.toml"),
            "[package]\nname = \"deep_rust_app\"",
        )
        .unwrap();

        // 3. Ignored directory that has a fake project marker (should NOT be discovered)
        let ignored_node_modules = cat_proj.join("node_modules").join("fake_dependency");
        fs::create_dir_all(&ignored_node_modules).unwrap();
        fs::write(
            ignored_node_modules.join("package.json"),
            "{\"name\": \"fake_dep\"}",
        )
        .unwrap();

        let manager = ProjectManager::with_roots(vec![root.clone()]);
        let list = manager.list(Some(&root.to_string_lossy())).unwrap();

        // Should find nested_node_app and deep_rust_app, but NOT fake_dependency
        assert!(list
            .iter()
            .any(|p| p.name == "nested_node_app" && p.project_type == "node"));
        assert!(list
            .iter()
            .any(|p| p.name == "deep_rust_app" && p.project_type == "rust"));
        assert!(!list.iter().any(|p| p.name == "fake_dependency"));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn test_root_itself_discovered_as_project() {
        let temp_id = uuid::Uuid::new_v4();
        let root = std::env::temp_dir().join(format!("orbit_root_proj_test_{}", temp_id));
        fs::create_dir_all(&root).unwrap();

        // Root directory itself has package.json
        fs::write(root.join("package.json"), "{\"name\": \"root_project\"}").unwrap();

        // Plus a subproject
        let sub_proj = root.join("packages").join("sub_tool");
        fs::create_dir_all(&sub_proj).unwrap();
        fs::write(
            sub_proj.join("Cargo.toml"),
            "[package]\nname = \"sub_tool\"",
        )
        .unwrap();

        let manager = ProjectManager::with_roots(vec![root.clone()]);
        let list = manager.list(Some(&root.to_string_lossy())).unwrap();

        assert!(list.iter().any(|p| p.path == root.to_string_lossy()));
        assert!(list.iter().any(|p| p.name == "sub_tool"));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn test_current_workspace_discovers_orbit_and_icons() {
        let manager = ProjectManager::new();
        let roots = manager.roots();
        let ws_root = roots.iter().find(|r| r.name == "Workspace").unwrap();
        let list = manager.list(Some(&ws_root.path)).unwrap();

        // Must discover Orbit itself
        assert!(
            list.iter().any(|p| p.path.ends_with("orbit")),
            "Expected Orbit project in workspace listing, got: {:?}",
            list.iter().map(|p| &p.path).collect::<Vec<_>>()
        );

        // Must still discover existing subprojects such as icons
        assert!(
            list.iter().any(|p| p.name == "icons"),
            "Expected icons project in workspace listing, got: {:?}",
            list.iter().map(|p| &p.name).collect::<Vec<_>>()
        );
    }

    #[test]
    fn test_projects_root_discovers_nested_orbit() {
        let manager = ProjectManager::new();
        let roots = manager.roots();
        if let Some(proj_root) = roots.iter().find(|r| r.name == "Projects") {
            let list = manager.list(Some(&proj_root.path)).unwrap();
            assert!(
                list.iter()
                    .any(|p| p.path.ends_with("desktop_projects/orbit")),
                "Expected Orbit project under Projects root, got: {:?}",
                list.iter().map(|p| &p.path).collect::<Vec<_>>()
            );
        }
    }

    #[test]
    fn test_git_status_stage_unstage_commit() {
        let sandbox = TestSandbox::new();
        let proj_path = sandbox.project_dir.to_string_lossy();

        // 1. Initial status is clean
        let status = sandbox.manager.git_status(&proj_path).unwrap();
        assert!(status.clean);
        assert_eq!(status.staged.len(), 0);
        assert_eq!(status.unstaged.len(), 0);
        assert_eq!(status.untracked.len(), 0);

        // 2. Create new file -> shows in untracked
        let new_file = sandbox.project_dir.join("notes.txt");
        fs::write(&new_file, "Remote Git Testing").unwrap();

        let status2 = sandbox.manager.git_status(&proj_path).unwrap();
        assert!(!status2.clean);
        assert_eq!(status2.untracked.len(), 1);
        assert_eq!(status2.untracked[0].path, "notes.txt");

        // 3. Stage file
        let status3 = sandbox
            .manager
            .git_stage(&proj_path, &["notes.txt".to_string()])
            .unwrap();
        assert_eq!(status3.staged.len(), 1);
        assert_eq!(status3.staged[0].path, "notes.txt");
        assert_eq!(status3.untracked.len(), 0);

        // 4. Unstage file
        let status4 = sandbox
            .manager
            .git_unstage(&proj_path, &["notes.txt".to_string()])
            .unwrap();
        assert_eq!(status4.staged.len(), 0);
        assert_eq!(status4.untracked.len(), 1);

        // 5. Stage again and commit
        sandbox
            .manager
            .git_stage(&proj_path, &["notes.txt".to_string()])
            .unwrap();

        let commit_res = sandbox
            .manager
            .git_commit(&proj_path, "Add notes.txt test file")
            .unwrap();
        assert_eq!(commit_res.message, "Add notes.txt test file");
        assert!(!commit_res.hash.is_empty());

        // 6. Verify clean after commit
        let status5 = sandbox.manager.git_status(&proj_path).unwrap();
        assert!(status5.clean);

        // 7. Verify commit appears in log
        let logs = sandbox.manager.git_log(&proj_path, 10).unwrap();
        assert!(logs.len() >= 2);
        assert_eq!(logs[0].message, "Add notes.txt test file");
    }

    #[test]
    fn test_git_branch_creation_and_checkout() {
        let sandbox = TestSandbox::new();
        let proj_path = sandbox.project_dir.to_string_lossy();

        // 1. Check initial branches
        let branches = sandbox.manager.git_branches(&proj_path).unwrap();
        assert_eq!(branches.current, "main");

        // 2. Create new branch
        let status = sandbox
            .manager
            .git_create_branch(&proj_path, "feature/orbit-mobile")
            .unwrap();
        assert_eq!(status.branch, "feature/orbit-mobile");

        let branches2 = sandbox.manager.git_branches(&proj_path).unwrap();
        assert_eq!(branches2.current, "feature/orbit-mobile");
        assert!(branches2.local.contains(&"main".to_string()));
        assert!(branches2
            .local
            .contains(&"feature/orbit-mobile".to_string()));

        // 3. Checkout main
        let status_main = sandbox.manager.git_checkout(&proj_path, "main").unwrap();
        assert_eq!(status_main.branch, "main");
    }

    #[test]
    fn test_security_scope_rejection() {
        let sandbox = TestSandbox::new();

        // Attempt to inspect path outside allowed roots
        let outside = std::env::temp_dir();
        let res = sandbox.manager.info(&outside.to_string_lossy());
        assert!(res.is_err());
        match res.unwrap_err() {
            ProjectError::ProjectNotAllowed(_) => {}
            other => panic!("Expected ProjectNotAllowed, got {:?}", other),
        }
    }
}
