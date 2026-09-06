use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::RwLock;

use super::operations::{self, FileEntry, FileError, DEFAULT_MAX_READ_BYTES};
use super::path::{discover_system_roots, is_within_scopes, normalize_path};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct FileRoot {
    pub name: String,
    pub path: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub is_removable: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FileListResult {
    pub path: String,
    pub entries: Vec<FileEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FileReadResult {
    pub path: String,
    pub content: String,
    pub encoding: String,
    pub size: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FileWriteResult {
    pub path: String,
    pub size: u64,
    pub success: bool,
}

pub struct FileManager {
    allowed_scopes: RwLock<Vec<PathBuf>>,
    max_read_bytes: u64,
}

impl Default for FileManager {
    fn default() -> Self {
        Self::new()
    }
}

impl FileManager {
    pub fn new() -> Self {
        let roots = discover_system_roots();
        let mut scopes: Vec<PathBuf> = roots.into_iter().map(|r| r.path).collect();
        if let Ok(cwd) = std::env::current_dir() {
            if !scopes.contains(&cwd) {
                scopes.push(cwd);
            }
        }
        Self {
            allowed_scopes: RwLock::new(scopes),
            max_read_bytes: DEFAULT_MAX_READ_BYTES,
        }
    }

    pub fn with_scopes(scopes: Vec<PathBuf>) -> Self {
        Self {
            allowed_scopes: RwLock::new(scopes),
            max_read_bytes: DEFAULT_MAX_READ_BYTES,
        }
    }

    pub fn roots(&self) -> Vec<FileRoot> {
        let discovered = discover_system_roots();
        if let Ok(mut scopes) = self.allowed_scopes.write() {
            for r in &discovered {
                if !scopes.contains(&r.path) {
                    scopes.push(r.path.clone());
                }
            }
        }
        discovered
            .into_iter()
            .map(|r| FileRoot {
                name: r.name,
                path: r.path.to_string_lossy().to_string(),
                label: r.label,
                kind: Some(r.kind),
                is_removable: Some(r.is_removable),
            })
            .collect()
    }

    fn validate_and_resolve(&self, raw_path: &str) -> Result<PathBuf, FileError> {
        let normalized = normalize_path(raw_path);
        let scopes = self.allowed_scopes.read().unwrap();

        if !is_within_scopes(&normalized, &scopes) {
            return Err(FileError::PermissionDenied(format!(
                "Path '{}' is outside allowed filesystem scope",
                raw_path
            )));
        }

        Ok(normalized)
    }

    pub fn list(&self, raw_path: &str) -> Result<FileListResult, FileError> {
        let path = self.validate_and_resolve(raw_path)?;
        let entries = operations::list_directory(&path)?;
        Ok(FileListResult {
            path: path.to_string_lossy().to_string(),
            entries,
        })
    }

    pub fn read(&self, raw_path: &str) -> Result<FileReadResult, FileError> {
        let path = self.validate_and_resolve(raw_path)?;
        let (content, size) = operations::read_text_file(&path, self.max_read_bytes)?;
        Ok(FileReadResult {
            path: path.to_string_lossy().to_string(),
            content,
            encoding: "utf8".to_string(),
            size,
        })
    }

    pub fn read_binary(
        &self,
        raw_path: &str,
        max_bytes: Option<u64>,
    ) -> Result<operations::BinaryReadResult, FileError> {
        let path = self.validate_and_resolve(raw_path)?;
        let limit = max_bytes.unwrap_or(self.max_read_bytes);
        operations::read_binary_file(&path, limit)
    }

    pub fn write(&self, raw_path: &str, content: &str) -> Result<FileWriteResult, FileError> {
        let path = self.validate_and_resolve(raw_path)?;
        let size = operations::write_text_file_atomic(&path, content)?;
        Ok(FileWriteResult {
            path: path.to_string_lossy().to_string(),
            size,
            success: true,
        })
    }

    pub fn mkdir(&self, raw_path: &str) -> Result<String, FileError> {
        let path = self.validate_and_resolve(raw_path)?;
        operations::create_dir(&path)?;
        Ok(path.to_string_lossy().to_string())
    }

    pub fn rename(&self, from: &str, to: &str) -> Result<(), FileError> {
        let from_path = self.validate_and_resolve(from)?;
        let to_path = self.validate_and_resolve(to)?;
        operations::rename_path(&from_path, &to_path)
    }

    pub fn delete(&self, raw_path: &str) -> Result<String, FileError> {
        let path = self.validate_and_resolve(raw_path)?;
        operations::delete_path(&path)?;
        Ok(path.to_string_lossy().to_string())
    }

    pub fn search(
        &self,
        raw_root: &str,
        query: &str,
        mode: &str,
        max_results: Option<usize>,
    ) -> Result<operations::FileSearchResult, FileError> {
        let root = self.validate_and_resolve(raw_root)?;
        let limit = max_results.unwrap_or(operations::MAX_SEARCH_RESULTS);
        operations::search_files(&root, query, mode, limit)
    }
}
