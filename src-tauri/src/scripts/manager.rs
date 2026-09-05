use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

use crate::protocol::errors::ProtocolError;
use crate::scripts::models::{Script, ScriptInput};
use crate::scripts::store::ScriptStore;

fn now_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

pub struct ScriptManager {
    store: ScriptStore,
}

impl ScriptManager {
    pub fn new() -> Result<Self, ProtocolError> {
        let store = ScriptStore::default_store()?;
        Ok(Self { store })
    }

    pub fn new_in_memory() -> Result<Self, ProtocolError> {
        let store = ScriptStore::new_in_memory()?;
        Ok(Self { store })
    }

    pub fn new_at_path(path: &Path) -> Result<Self, ProtocolError> {
        let store = ScriptStore::new_at_path(path)?;
        Ok(Self { store })
    }

    pub fn list(&self, project_path: Option<&str>) -> Result<Vec<Script>, ProtocolError> {
        self.store.list(project_path)
    }

    pub fn get(&self, id: &str) -> Result<Option<Script>, ProtocolError> {
        self.store.get(id)
    }

    pub fn save(&self, input: ScriptInput) -> Result<Script, ProtocolError> {
        let name = input.name.trim();
        if name.is_empty() {
            return Err(ProtocolError::invalid_params("Script name cannot be empty."));
        }

        let content = input.content.trim();
        if content.is_empty() {
            return Err(ProtocolError::invalid_params("Script content cannot be empty."));
        }

        // Validate working directory if specified
        if let Some(ref cwd) = input.working_directory {
            let path = PathBuf::from(cwd);
            if !path.exists() {
                return Err(ProtocolError::invalid_params(format!(
                    "Working directory does not exist: {}",
                    cwd
                )));
            }
            if !path.is_dir() {
                return Err(ProtocolError::invalid_params(format!(
                    "Working directory path is not a directory: {}",
                    cwd
                )));
            }
        }

        // Validate project path if specified
        if let Some(ref proj) = input.project_path {
            let path = PathBuf::from(proj);
            if !path.exists() {
                return Err(ProtocolError::invalid_params(format!(
                    "Project directory does not exist: {}",
                    proj
                )));
            }
        }

        let now = now_unix();
        let script = if let Some(ref id) = input.id {
            if let Some(existing) = self.store.get(id)? {
                Script {
                    id: existing.id,
                    name: name.to_string(),
                    description: input.description.map(|d| d.trim().to_string()).filter(|d| !d.is_empty()),
                    content: input.content,
                    working_directory: input.working_directory.map(|w| w.trim().to_string()).filter(|w| !w.is_empty()),
                    project_path: input.project_path.map(|p| p.trim().to_string()).filter(|p| !p.is_empty()),
                    created_at: existing.created_at,
                    updated_at: now,
                }
            } else {
                Script {
                    id: id.clone(),
                    name: name.to_string(),
                    description: input.description.map(|d| d.trim().to_string()).filter(|d| !d.is_empty()),
                    content: input.content,
                    working_directory: input.working_directory.map(|w| w.trim().to_string()).filter(|w| !w.is_empty()),
                    project_path: input.project_path.map(|p| p.trim().to_string()).filter(|p| !p.is_empty()),
                    created_at: now,
                    updated_at: now,
                }
            }
        } else {
            Script {
                id: Uuid::new_v4().to_string(),
                name: name.to_string(),
                description: input.description.map(|d| d.trim().to_string()).filter(|d| !d.is_empty()),
                content: input.content,
                working_directory: input.working_directory.map(|w| w.trim().to_string()).filter(|w| !w.is_empty()),
                project_path: input.project_path.map(|p| p.trim().to_string()).filter(|p| !p.is_empty()),
                created_at: now,
                updated_at: now,
            }
        };

        self.store.save(&script)?;
        Ok(script)
    }

    pub fn delete(&self, id: &str) -> Result<bool, ProtocolError> {
        self.store.delete(id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_script_crud() {
        let mgr = ScriptManager::new_in_memory().unwrap();

        // 1. Create global script
        let created = mgr
            .save(ScriptInput {
                id: None,
                name: "Build All".to_string(),
                description: Some("Build release".to_string()),
                content: "cargo build --release".to_string(),
                working_directory: None,
                project_path: None,
            })
            .unwrap();

        assert_eq!(created.name, "Build All");
        assert_eq!(created.description, Some("Build release".to_string()));
        assert_eq!(created.content, "cargo build --release");
        assert!(created.project_path.is_none());

        // 2. Get script
        let fetched = mgr.get(&created.id).unwrap().unwrap();
        assert_eq!(fetched.id, created.id);

        // 3. List scripts
        let list = mgr.list(None).unwrap();
        assert_eq!(list.len(), 1);

        // 4. Update script
        let updated = mgr
            .save(ScriptInput {
                id: Some(created.id.clone()),
                name: "Build Optimized".to_string(),
                description: None,
                content: "cargo build --release --locked".to_string(),
                working_directory: None,
                project_path: None,
            })
            .unwrap();

        assert_eq!(updated.id, created.id);
        assert_eq!(updated.name, "Build Optimized");
        assert_eq!(updated.description, None);
        assert_eq!(updated.created_at, created.created_at);

        // 5. Delete script
        let deleted = mgr.delete(&created.id).unwrap();
        assert!(deleted);
        assert!(mgr.get(&created.id).unwrap().is_none());
        assert_eq!(mgr.list(None).unwrap().len(), 0);
    }

    #[test]
    fn test_empty_validation() {
        let mgr = ScriptManager::new_in_memory().unwrap();

        // Empty name
        let res = mgr.save(ScriptInput {
            id: None,
            name: "   ".to_string(),
            description: None,
            content: "echo hello".to_string(),
            working_directory: None,
            project_path: None,
        });
        assert!(res.is_err());

        // Empty content
        let res = mgr.save(ScriptInput {
            id: None,
            name: "Valid Name".to_string(),
            description: None,
            content: "   ".to_string(),
            working_directory: None,
            project_path: None,
        });
        assert!(res.is_err());
    }

    #[test]
    fn test_project_scope_filtering() {
        let mgr = ScriptManager::new_in_memory().unwrap();

        // Global script
        let global = mgr
            .save(ScriptInput {
                id: None,
                name: "Global Clean".to_string(),
                description: None,
                content: "rm -rf /tmp/test".to_string(),
                working_directory: None,
                project_path: None,
            })
            .unwrap();

        // Project script (use temp dir as existing project path)
        let temp_dir = std::env::temp_dir();
        let temp_str = temp_dir.to_str().unwrap().to_string();

        let proj_script = mgr
            .save(ScriptInput {
                id: None,
                name: "Project Test".to_string(),
                description: None,
                content: "pytest".to_string(),
                working_directory: None,
                project_path: Some(temp_str.clone()),
            })
            .unwrap();

        // List with project path: includes both project-scoped and global
        let list_proj = mgr.list(Some(&temp_str)).unwrap();
        assert_eq!(list_proj.len(), 2);
        assert!(list_proj.iter().any(|s| s.id == global.id));
        assert!(list_proj.iter().any(|s| s.id == proj_script.id));

        // List with different project path: includes only global
        let list_other = mgr.list(Some("/nonexistent/fake/path")).unwrap();
        assert_eq!(list_other.len(), 1);
        assert_eq!(list_other[0].id, global.id);

        // List all
        let list_all = mgr.list(None).unwrap();
        assert_eq!(list_all.len(), 2);
    }
}
