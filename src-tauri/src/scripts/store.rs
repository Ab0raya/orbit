use rusqlite::{params, Connection, OptionalExtension};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use crate::protocol::errors::ProtocolError;
use crate::scripts::models::Script;

pub struct ScriptStore {
    conn: Arc<Mutex<Connection>>,
    db_path: Option<PathBuf>,
}

impl ScriptStore {
    pub fn new_in_memory() -> Result<Self, ProtocolError> {
        let conn = Connection::open_in_memory().map_err(|e| {
            ProtocolError::internal_error(format!(
                "Failed to open in-memory SQLite for scripts: {}",
                e
            ))
        })?;
        let store = Self {
            conn: Arc::new(Mutex::new(conn)),
            db_path: None,
        };
        store.init_tables()?;
        Ok(store)
    }

    pub fn new_at_path(path: &Path) -> Result<Self, ProtocolError> {
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let conn = Connection::open(path).map_err(|e| {
            ProtocolError::internal_error(format!(
                "Failed to open SQLite database at {:?}: {}",
                path, e
            ))
        })?;
        let store = Self {
            conn: Arc::new(Mutex::new(conn)),
            db_path: Some(path.to_path_buf()),
        };
        store.init_tables()?;
        Ok(store)
    }

    pub fn default_store() -> Result<Self, ProtocolError> {
        let orbit_dir = match std::env::var("HOME") {
            Ok(h) => PathBuf::from(h).join(".orbit"),
            Err(_) => std::env::temp_dir().join(".orbit"),
        };
        let _ = std::fs::create_dir_all(&orbit_dir);
        let db_path = orbit_dir.join("scripts.db");
        Self::new_at_path(&db_path)
    }

    pub fn db_path(&self) -> Option<&Path> {
        self.db_path.as_deref()
    }

    fn init_tables(&self) -> Result<(), ProtocolError> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS scripts (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT,
                content TEXT NOT NULL,
                working_directory TEXT,
                project_path TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_scripts_project_path ON scripts(project_path);
            CREATE INDEX IF NOT EXISTS idx_scripts_updated_at ON scripts(updated_at DESC);
            "#,
        )
        .map_err(|e| {
            ProtocolError::internal_error(format!("Failed to init scripts tables: {}", e))
        })?;

        Ok(())
    }

    pub fn list(&self, project_path: Option<&str>) -> Result<Vec<Script>, ProtocolError> {
        let conn = self.conn.lock().unwrap();
        let mut scripts = Vec::new();

        if let Some(proj) = project_path {
            let mut stmt = conn.prepare(
                r#"
                SELECT id, name, description, content, working_directory, project_path, created_at, updated_at
                FROM scripts
                WHERE project_path = ?1 OR project_path IS NULL
                ORDER BY updated_at DESC
                "#,
            )
            .map_err(|e| ProtocolError::internal_error(e.to_string()))?;

            let rows = stmt
                .query_map(params![proj], |row| {
                    Ok(Script {
                        id: row.get(0)?,
                        name: row.get(1)?,
                        description: row.get(2)?,
                        content: row.get(3)?,
                        working_directory: row.get(4)?,
                        project_path: row.get(5)?,
                        created_at: row.get(6)?,
                        updated_at: row.get(7)?,
                    })
                })
                .map_err(|e| ProtocolError::internal_error(e.to_string()))?;

            for row in rows {
                scripts.push(row.map_err(|e| ProtocolError::internal_error(e.to_string()))?);
            }
        } else {
            let mut stmt = conn.prepare(
                r#"
                SELECT id, name, description, content, working_directory, project_path, created_at, updated_at
                FROM scripts
                ORDER BY updated_at DESC
                "#,
            )
            .map_err(|e| ProtocolError::internal_error(e.to_string()))?;

            let rows = stmt
                .query_map([], |row| {
                    Ok(Script {
                        id: row.get(0)?,
                        name: row.get(1)?,
                        description: row.get(2)?,
                        content: row.get(3)?,
                        working_directory: row.get(4)?,
                        project_path: row.get(5)?,
                        created_at: row.get(6)?,
                        updated_at: row.get(7)?,
                    })
                })
                .map_err(|e| ProtocolError::internal_error(e.to_string()))?;

            for row in rows {
                scripts.push(row.map_err(|e| ProtocolError::internal_error(e.to_string()))?);
            }
        }

        Ok(scripts)
    }

    pub fn get(&self, id: &str) -> Result<Option<Script>, ProtocolError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            r#"
            SELECT id, name, description, content, working_directory, project_path, created_at, updated_at
            FROM scripts
            WHERE id = ?1
            "#,
        )
        .map_err(|e| ProtocolError::internal_error(e.to_string()))?;

        let script = stmt
            .query_row(params![id], |row| {
                Ok(Script {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    description: row.get(2)?,
                    content: row.get(3)?,
                    working_directory: row.get(4)?,
                    project_path: row.get(5)?,
                    created_at: row.get(6)?,
                    updated_at: row.get(7)?,
                })
            })
            .optional()
            .map_err(|e| ProtocolError::internal_error(e.to_string()))?;

        Ok(script)
    }

    pub fn save(&self, script: &Script) -> Result<(), ProtocolError> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            r#"
            INSERT INTO scripts (
                id, name, description, content, working_directory, project_path, created_at, updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                description = excluded.description,
                content = excluded.content,
                working_directory = excluded.working_directory,
                project_path = excluded.project_path,
                updated_at = excluded.updated_at
            "#,
            params![
                script.id,
                script.name,
                script.description,
                script.content,
                script.working_directory,
                script.project_path,
                script.created_at,
                script.updated_at
            ],
        )
        .map_err(|e| ProtocolError::internal_error(format!("Failed to save script: {}", e)))?;

        Ok(())
    }

    pub fn delete(&self, id: &str) -> Result<bool, ProtocolError> {
        let conn = self.conn.lock().unwrap();
        let affected = conn
            .execute("DELETE FROM scripts WHERE id = ?1", params![id])
            .map_err(|e| {
                ProtocolError::internal_error(format!("Failed to delete script: {}", e))
            })?;

        Ok(affected > 0)
    }
}
