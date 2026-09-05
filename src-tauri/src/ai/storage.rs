use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::ai::models::AiActivity;
use crate::protocol::errors::ProtocolError;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiConversationSummary {
    pub id: String,
    pub title: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub project_path: Option<String>,
    pub directory_path: Option<String>,
    pub context_type: String,
    pub open_code_session_id: Option<String>,
    pub provider_id: Option<String>,
    pub model_id: Option<String>,
    pub status: String,
    pub last_message_preview: Option<String>,
    pub message_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiConversationDetail {
    pub id: String,
    pub title: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub project_path: Option<String>,
    pub directory_path: Option<String>,
    pub context_type: String,
    pub open_code_session_id: Option<String>,
    pub provider_id: Option<String>,
    pub model_id: Option<String>,
    pub status: String,
    pub last_message_preview: Option<String>,
    pub message_count: usize,
    pub messages: Vec<AiConversationMessage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiConversationMessage {
    pub id: String,
    pub conversation_id: String,
    pub role: String,
    pub content: String,
    pub created_at: i64,
    pub status: String,
    pub task_id: Option<String>,
    pub provider_id: Option<String>,
    pub model_id: Option<String>,
    pub activities: Vec<AiActivity>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiConversationSearchResult {
    pub conversation_id: String,
    pub title: String,
    pub matched_field: String,
    pub snippet: String,
    pub updated_at: i64,
    pub project_path: Option<String>,
    pub model_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiDefaults {
    pub provider_id: String,
    pub model_id: String,
    pub agent: String,
    pub context_behavior: String,
}

impl Default for AiDefaults {
    fn default() -> Self {
        Self {
            provider_id: "openrouter".to_string(),
            model_id: "openrouter/openrouter/free".to_string(),
            agent: "plan".to_string(),
            context_behavior: "none".to_string(),
        }
    }
}

pub struct AiConversationStore {
    conn: Arc<Mutex<Connection>>,
    db_path: Option<PathBuf>,
}

impl AiConversationStore {
    pub fn new_in_memory() -> Result<Self, ProtocolError> {
        let conn = Connection::open_in_memory()
            .map_err(|e| ProtocolError::internal_error(format!("Failed to open in-memory SQLite: {}", e)))?;
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
        let conn = Connection::open(path)
            .map_err(|e| ProtocolError::internal_error(format!("Failed to open SQLite database at {:?}: {}", path, e)))?;
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
        let db_path = orbit_dir.join("conversations.db");
        Self::new_at_path(&db_path)
    }

    pub fn db_path(&self) -> Option<&Path> {
        self.db_path.as_deref()
    }

    fn init_tables(&self) -> Result<(), ProtocolError> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                project_path TEXT,
                directory_path TEXT,
                context_type TEXT NOT NULL DEFAULT 'none',
                open_code_session_id TEXT,
                provider_id TEXT,
                model_id TEXT,
                status TEXT NOT NULL DEFAULT 'idle',
                last_message_preview TEXT,
                message_count INTEGER NOT NULL DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_conversations_session ON conversations(open_code_session_id);

            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                conversation_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                status TEXT NOT NULL DEFAULT 'completed',
                task_id TEXT,
                provider_id TEXT,
                model_id TEXT,
                activities_json TEXT,
                error TEXT,
                FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_messages_conv_created ON messages(conversation_id, created_at ASC);

            CREATE TABLE IF NOT EXISTS ai_defaults (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                provider_id TEXT NOT NULL,
                model_id TEXT NOT NULL,
                agent TEXT NOT NULL,
                context_behavior TEXT NOT NULL
            );

            INSERT OR IGNORE INTO ai_defaults (id, provider_id, model_id, agent, context_behavior)
            VALUES (1, 'openrouter', 'openrouter/openrouter/free', 'plan', 'none');
            "#,
        )
        .map_err(|e| ProtocolError::internal_error(format!("Failed to initialize database tables: {}", e)))?;

        Ok(())
    }

    pub fn generate_safe_title(prompt: &str) -> String {
        let trimmed = prompt.trim();
        if trimmed.is_empty() {
            return "New Conversation".to_string();
        }

        // Strip markdown header hashes or quotes
        let clean = trimmed.trim_start_matches(['#', '>', '*', '`']).trim();

        // Limit to first line
        let first_line = clean.lines().next().unwrap_or(clean).trim();

        if first_line.chars().count() <= 48 {
            Self::capitalize_title(first_line)
        } else {
            let truncated: String = first_line.chars().take(48).collect();
            if let Some(last_space) = truncated.rfind(' ') {
                format!("{}...", Self::capitalize_title(&truncated[..last_space]))
            } else {
                format!("{}...", Self::capitalize_title(&truncated))
            }
        }
    }

    fn capitalize_title(s: &str) -> String {
        let mut chars = s.chars();
        match chars.next() {
            None => String::new(),
            Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
        }
    }

    pub fn create_conversation(
        &self,
        title: Option<&str>,
        project_path: Option<&str>,
        directory_path: Option<&str>,
        context_type: Option<&str>,
        provider_id: Option<&str>,
        model_id: Option<&str>,
    ) -> Result<AiConversationSummary, ProtocolError> {
        let id = format!("conv_{}", Uuid::new_v4().simple());
        let now = chrono::Utc::now().timestamp();
        let safe_title = match title {
            Some(t) if !t.trim().is_empty() => t.trim().to_string(),
            _ => "New Chat".to_string(),
        };

        let ctx_type = context_type.unwrap_or("none");
        let conn = self.conn.lock().unwrap();

        conn.execute(
            r#"
            INSERT INTO conversations (
                id, title, created_at, updated_at, project_path, directory_path,
                context_type, open_code_session_id, provider_id, model_id, status,
                last_message_preview, message_count
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, NULL, ?8, ?9, 'idle', NULL, 0)
            "#,
            params![
                id,
                safe_title,
                now,
                now,
                project_path,
                directory_path,
                ctx_type,
                provider_id,
                model_id,
            ],
        )
        .map_err(|e| ProtocolError::internal_error(format!("Failed to create conversation: {}", e)))?;

        Ok(AiConversationSummary {
            id,
            title: safe_title,
            created_at: now,
            updated_at: now,
            project_path: project_path.map(|s| s.to_string()),
            directory_path: directory_path.map(|s| s.to_string()),
            context_type: ctx_type.to_string(),
            open_code_session_id: None,
            provider_id: provider_id.map(|s| s.to_string()),
            model_id: model_id.map(|s| s.to_string()),
            status: "idle".to_string(),
            last_message_preview: None,
            message_count: 0,
        })
    }

    pub fn list_conversations(&self, limit: usize, offset: usize) -> Result<Vec<AiConversationSummary>, ProtocolError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn
            .prepare(
                r#"
                SELECT id, title, created_at, updated_at, project_path, directory_path,
                       context_type, open_code_session_id, provider_id, model_id, status,
                       last_message_preview, message_count
                FROM conversations
                ORDER BY updated_at DESC
                LIMIT ?1 OFFSET ?2
                "#,
            )
            .map_err(|e| ProtocolError::internal_error(format!("Failed to prepare list query: {}", e)))?;

        let rows = stmt
            .query_map(params![limit as i64, offset as i64], |row| {
                Ok(AiConversationSummary {
                    id: row.get(0)?,
                    title: row.get(1)?,
                    created_at: row.get(2)?,
                    updated_at: row.get(3)?,
                    project_path: row.get(4)?,
                    directory_path: row.get(5)?,
                    context_type: row.get(6)?,
                    open_code_session_id: row.get(7)?,
                    provider_id: row.get(8)?,
                    model_id: row.get(9)?,
                    status: row.get(10)?,
                    last_message_preview: row.get(11)?,
                    message_count: row.get::<_, i64>(12)? as usize,
                })
            })
            .map_err(|e| ProtocolError::internal_error(format!("Failed to execute list query: {}", e)))?;

        let mut result = Vec::new();
        for conv in rows.flatten() {
            result.push(conv);
        }

        Ok(result)
    }

    pub fn get_conversation(&self, id: &str) -> Result<Option<AiConversationDetail>, ProtocolError> {
        let conn = self.conn.lock().unwrap();
        let mut conv_stmt = conn
            .prepare(
                r#"
                SELECT id, title, created_at, updated_at, project_path, directory_path,
                       context_type, open_code_session_id, provider_id, model_id, status,
                       last_message_preview, message_count
                FROM conversations
                WHERE id = ?1
                "#,
            )
            .map_err(|e| ProtocolError::internal_error(format!("Failed to prepare get query: {}", e)))?;

        let summary: Option<AiConversationSummary> = conv_stmt
            .query_row(params![id], |row| {
                Ok(AiConversationSummary {
                    id: row.get(0)?,
                    title: row.get(1)?,
                    created_at: row.get(2)?,
                    updated_at: row.get(3)?,
                    project_path: row.get(4)?,
                    directory_path: row.get(5)?,
                    context_type: row.get(6)?,
                    open_code_session_id: row.get(7)?,
                    provider_id: row.get(8)?,
                    model_id: row.get(9)?,
                    status: row.get(10)?,
                    last_message_preview: row.get(11)?,
                    message_count: row.get::<_, i64>(12)? as usize,
                })
            })
            .optional()
            .map_err(|e| ProtocolError::internal_error(format!("Failed to query conversation: {}", e)))?;

        let s = match summary {
            Some(s) => s,
            None => return Ok(None),
        };

        let mut msg_stmt = conn
            .prepare(
                r#"
                SELECT id, conversation_id, role, content, created_at, status,
                       task_id, provider_id, model_id, activities_json, error
                FROM messages
                WHERE conversation_id = ?1
                ORDER BY created_at ASC
                "#,
            )
            .map_err(|e| ProtocolError::internal_error(format!("Failed to prepare message query: {}", e)))?;

        let msg_rows = msg_stmt
            .query_map(params![id], |row| {
                let act_json: Option<String> = row.get(9)?;
                let activities: Vec<AiActivity> = act_json
                    .as_deref()
                    .and_then(|j| serde_json::from_str(j).ok())
                    .unwrap_or_default();

                Ok(AiConversationMessage {
                    id: row.get(0)?,
                    conversation_id: row.get(1)?,
                    role: row.get(2)?,
                    content: row.get(3)?,
                    created_at: row.get(4)?,
                    status: row.get(5)?,
                    task_id: row.get(6)?,
                    provider_id: row.get(7)?,
                    model_id: row.get(8)?,
                    activities,
                    error: row.get(10)?,
                })
            })
            .map_err(|e| ProtocolError::internal_error(format!("Failed to execute message query: {}", e)))?;

        let mut messages = Vec::new();
        for msg in msg_rows.flatten() {
            messages.push(msg);
        }

        Ok(Some(AiConversationDetail {
            id: s.id,
            title: s.title,
            created_at: s.created_at,
            updated_at: s.updated_at,
            project_path: s.project_path,
            directory_path: s.directory_path,
            context_type: s.context_type,
            open_code_session_id: s.open_code_session_id,
            provider_id: s.provider_id,
            model_id: s.model_id,
            status: s.status,
            last_message_preview: s.last_message_preview,
            message_count: s.message_count,
            messages,
        }))
    }

    pub fn update_title(&self, id: &str, title: &str) -> Result<(), ProtocolError> {
        let conn = self.conn.lock().unwrap();
        let now = chrono::Utc::now().timestamp();
        conn.execute(
            "UPDATE conversations SET title = ?1, updated_at = ?2 WHERE id = ?3",
            params![title.trim(), now, id],
        )
        .map_err(|e| ProtocolError::internal_error(format!("Failed to update title: {}", e)))?;
        Ok(())
    }

    pub fn update_status(&self, id: &str, status: &str) -> Result<(), ProtocolError> {
        let conn = self.conn.lock().unwrap();
        let now = chrono::Utc::now().timestamp();
        conn.execute(
            "UPDATE conversations SET status = ?1, updated_at = ?2 WHERE id = ?3",
            params![status, now, id],
        )
        .map_err(|e| ProtocolError::internal_error(format!("Failed to update status: {}", e)))?;
        Ok(())
    }

    pub fn update_model(&self, id: &str, provider_id: Option<&str>, model_id: Option<&str>) -> Result<(), ProtocolError> {
        let conn = self.conn.lock().unwrap();
        let now = chrono::Utc::now().timestamp();
        conn.execute(
            "UPDATE conversations SET provider_id = ?1, model_id = ?2, updated_at = ?3 WHERE id = ?4",
            params![provider_id, model_id, now, id],
        )
        .map_err(|e| ProtocolError::internal_error(format!("Failed to update model: {}", e)))?;
        Ok(())
    }

    pub fn update_session_mapping(&self, id: &str, session_id: &str) -> Result<(), ProtocolError> {
        let conn = self.conn.lock().unwrap();
        let now = chrono::Utc::now().timestamp();
        conn.execute(
            "UPDATE conversations SET open_code_session_id = ?1, updated_at = ?2 WHERE id = ?3",
            params![session_id, now, id],
        )
        .map_err(|e| ProtocolError::internal_error(format!("Failed to update session mapping: {}", e)))?;
        Ok(())
    }

    pub fn get_conversation_by_session_id(&self, session_id: &str) -> Result<Option<AiConversationSummary>, ProtocolError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn
            .prepare(
                r#"
                SELECT id, title, created_at, updated_at, project_path, directory_path,
                       context_type, open_code_session_id, provider_id, model_id, status,
                       last_message_preview, message_count
                FROM conversations
                WHERE open_code_session_id = ?1
                LIMIT 1
                "#,
            )
            .map_err(|e| ProtocolError::internal_error(format!("Failed to prepare query by session ID: {}", e)))?;

        let res = stmt
            .query_row(params![session_id], |row| {
                Ok(AiConversationSummary {
                    id: row.get(0)?,
                    title: row.get(1)?,
                    created_at: row.get(2)?,
                    updated_at: row.get(3)?,
                    project_path: row.get(4)?,
                    directory_path: row.get(5)?,
                    context_type: row.get(6)?,
                    open_code_session_id: row.get(7)?,
                    provider_id: row.get(8)?,
                    model_id: row.get(9)?,
                    status: row.get(10)?,
                    last_message_preview: row.get(11)?,
                    message_count: row.get::<_, i64>(12)? as usize,
                })
            })
            .optional()
            .map_err(|e| ProtocolError::internal_error(format!("Failed to query conversation by session: {}", e)))?;

        Ok(res)
    }

    pub fn delete_conversation(&self, id: &str) -> Result<(), ProtocolError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM messages WHERE conversation_id = ?1", params![id])
            .map_err(|e| ProtocolError::internal_error(format!("Failed to delete messages: {}", e)))?;
        conn.execute("DELETE FROM conversations WHERE id = ?1", params![id])
            .map_err(|e| ProtocolError::internal_error(format!("Failed to delete conversation: {}", e)))?;
        Ok(())
    }

    pub fn add_message(&self, msg: &AiConversationMessage) -> Result<(), ProtocolError> {
        let conn = self.conn.lock().unwrap();
        let act_json = if msg.activities.is_empty() {
            None
        } else {
            serde_json::to_string(&msg.activities).ok()
        };

        conn.execute(
            r#"
            INSERT INTO messages (
                id, conversation_id, role, content, created_at, status,
                task_id, provider_id, model_id, activities_json, error
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
            "#,
            params![
                msg.id,
                msg.conversation_id,
                msg.role,
                msg.content,
                msg.created_at,
                msg.status,
                msg.task_id,
                msg.provider_id,
                msg.model_id,
                act_json,
                msg.error,
            ],
        )
        .map_err(|e| ProtocolError::internal_error(format!("Failed to insert message: {}", e)))?;

        // Update preview and count in conversation
        let preview: String = msg.content.chars().take(80).collect();
        let now = chrono::Utc::now().timestamp();

        conn.execute(
            r#"
            UPDATE conversations
            SET last_message_preview = ?1,
                message_count = (SELECT COUNT(*) FROM messages WHERE conversation_id = ?2),
                updated_at = ?3
            WHERE id = ?2
            "#,
            params![preview, msg.conversation_id, now],
        )
        .map_err(|e| ProtocolError::internal_error(format!("Failed to update conversation preview: {}", e)))?;

        Ok(())
    }

    pub fn update_message(
        &self,
        message_id: &str,
        content: &str,
        status: &str,
        activities: &[AiActivity],
        error: Option<&str>,
    ) -> Result<(), ProtocolError> {
        let conn = self.conn.lock().unwrap();
        let act_json = if activities.is_empty() {
            None
        } else {
            serde_json::to_string(activities).ok()
        };

        conn.execute(
            r#"
            UPDATE messages
            SET content = ?1, status = ?2, activities_json = ?3, error = ?4
            WHERE id = ?5
            "#,
            params![content, status, act_json, error, message_id],
        )
        .map_err(|e| ProtocolError::internal_error(format!("Failed to update message: {}", e)))?;

        Ok(())
    }

    pub fn search_conversations(&self, query: &str, limit: usize) -> Result<Vec<AiConversationSearchResult>, ProtocolError> {
        let q = query.trim();
        if q.is_empty() {
            return Ok(Vec::new());
        }

        let conn = self.conn.lock().unwrap();
        let sql_like = format!("%{}%", q);
        let mut results = Vec::new();

        // 1. Search titles
        {
            let mut stmt = conn
                .prepare(
                    r#"
                    SELECT id, title, updated_at, project_path, model_id
                    FROM conversations
                    WHERE title LIKE ?1 OR project_path LIKE ?1 OR model_id LIKE ?1
                    ORDER BY updated_at DESC
                    LIMIT ?2
                    "#,
                )
                .map_err(|e| ProtocolError::internal_error(format!("Search title failed: {}", e)))?;

            let rows = stmt
                .query_map(params![sql_like, limit as i64], |row| {
                    let conv_id: String = row.get(0)?;
                    let title: String = row.get(1)?;
                    let updated_at: i64 = row.get(2)?;
                    let project_path: Option<String> = row.get(3)?;
                    let model_id: Option<String> = row.get(4)?;

                    let field = if title.to_lowercase().contains(&q.to_lowercase()) {
                        "title"
                    } else if project_path.as_deref().unwrap_or("").to_lowercase().contains(&q.to_lowercase()) {
                        "project"
                    } else {
                        "model"
                    };

                    Ok(AiConversationSearchResult {
                        conversation_id: conv_id,
                        title,
                        matched_field: field.to_string(),
                        snippet: format!("Matched {}", field),
                        updated_at,
                        project_path,
                        model_id,
                    })
                })
                .map_err(|e| ProtocolError::internal_error(format!("Query failed: {}", e)))?;

            for r in rows.flatten() {
                results.push(r);
            }
        }

        // 2. Search message contents if limit not reached
        if results.len() < limit {
            let remaining = limit - results.len();
            let mut stmt = conn
                .prepare(
                    r#"
                    SELECT m.conversation_id, c.title, m.content, c.updated_at, c.project_path, c.model_id
                    FROM messages m
                    JOIN conversations c ON m.conversation_id = c.id
                    WHERE m.content LIKE ?1
                    ORDER BY m.created_at DESC
                    LIMIT ?2
                    "#,
                )
                .map_err(|e| ProtocolError::internal_error(format!("Search messages failed: {}", e)))?;

            let rows = stmt
                .query_map(params![sql_like, remaining as i64], |row| {
                    let conv_id: String = row.get(0)?;
                    let title: String = row.get(1)?;
                    let content: String = row.get(2)?;
                    let updated_at: i64 = row.get(3)?;
                    let project_path: Option<String> = row.get(4)?;
                    let model_id: Option<String> = row.get(5)?;

                    // Generate a snippet around match
                    let snippet = if let Some(idx) = content.to_lowercase().find(&q.to_lowercase()) {
                        let start = idx.saturating_sub(20);
                        let end = (idx + q.len() + 30).min(content.len());
                        format!("...{}...", &content[start..end])
                    } else {
                        content.chars().take(50).collect()
                    };

                    Ok(AiConversationSearchResult {
                        conversation_id: conv_id,
                        title,
                        matched_field: "message".to_string(),
                        snippet,
                        updated_at,
                        project_path,
                        model_id,
                    })
                })
                .map_err(|e| ProtocolError::internal_error(format!("Query failed: {}", e)))?;

            for r in rows.flatten() {
                if !results.iter().any(|existing| existing.conversation_id == r.conversation_id) {
                    results.push(r);
                }
            }
        }

        Ok(results)
    }

    pub fn get_defaults(&self) -> Result<AiDefaults, ProtocolError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn
            .prepare("SELECT provider_id, model_id, agent, context_behavior FROM ai_defaults WHERE id = 1")
            .map_err(|e| ProtocolError::internal_error(format!("Failed to prepare defaults query: {}", e)))?;

        let res = stmt
            .query_row([], |row| {
                Ok(AiDefaults {
                    provider_id: row.get(0)?,
                    model_id: row.get(1)?,
                    agent: row.get(2)?,
                    context_behavior: row.get(3)?,
                })
            })
            .optional()
            .map_err(|e| ProtocolError::internal_error(format!("Failed to query defaults: {}", e)))?;

        Ok(res.unwrap_or_default())
    }

    pub fn set_defaults(&self, defaults: &AiDefaults) -> Result<(), ProtocolError> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            r#"
            INSERT INTO ai_defaults (id, provider_id, model_id, agent, context_behavior)
            VALUES (1, ?1, ?2, ?3, ?4)
            ON CONFLICT(id) DO UPDATE SET
                provider_id = excluded.provider_id,
                model_id = excluded.model_id,
                agent = excluded.agent,
                context_behavior = excluded.context_behavior
            "#,
            params![
                defaults.provider_id,
                defaults.model_id,
                defaults.agent,
                defaults.context_behavior
            ],
        )
        .map_err(|e| ProtocolError::internal_error(format!("Failed to update defaults: {}", e)))?;

        Ok(())
    }

    pub fn export_markdown(&self, conversation_id: &str) -> Result<String, ProtocolError> {
        let detail = match self.get_conversation(conversation_id)? {
            Some(d) => d,
            None => return Err(ProtocolError::internal_error("Conversation not found")),
        };

        let date_str = chrono::DateTime::from_timestamp(detail.created_at, 0)
            .map(|dt| dt.format("%Y-%m-%d %H:%M:%S UTC").to_string())
            .unwrap_or_else(|| "Unknown date".to_string());

        let mut md = String::new();
        md.push_str(&format!("# {}\n\n", detail.title));
        md.push_str(&format!("- **Date**: {}\n", date_str));
        if let Some(ref p) = detail.project_path {
            md.push_str(&format!("- **Project**: `{}`\n", p));
        }
        if let Some(ref m) = detail.model_id {
            md.push_str(&format!("- **Model**: `{}`\n", m));
        }
        md.push_str(&format!("- **Status**: {}\n\n---\n\n", detail.status));

        for msg in &detail.messages {
            let role_label = match msg.role.as_str() {
                "user" => "### User",
                "assistant" => "### Orbit AI",
                _ => "### System",
            };
            md.push_str(&format!("{}\n\n{}\n\n", role_label, msg.content.trim()));

            if !msg.activities.is_empty() {
                md.push_str("<details>\n<summary>Activity Timeline</summary>\n\n");
                for act in &msg.activities {
                    let icon = match act.status.as_str() {
                        "completed" => "✓",
                        "failed" => "✗",
                        _ => "●",
                    };
                    let duration = act.duration_ms.map(|d| format!(" ({}ms)", d)).unwrap_or_default();
                    md.push_str(&format!("- {} {}{}\n", icon, act.title, duration));
                }
                md.push_str("\n</details>\n\n");
            }
        }

        Ok(md)
    }

    pub fn export_json(&self, conversation_id: &str) -> Result<String, ProtocolError> {
        let detail = match self.get_conversation(conversation_id)? {
            Some(d) => d,
            None => return Err(ProtocolError::internal_error("Conversation not found")),
        };

        serde_json::to_string_pretty(&detail)
            .map_err(|e| ProtocolError::internal_error(format!("Failed to serialize conversation JSON: {}", e)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::models::{AiActivity, AiActivityStatus, AiActivityType};

    #[test]
    fn test_generate_safe_title() {
        assert_eq!(AiConversationStore::generate_safe_title("explain README architecture"), "Explain README architecture");
        assert_eq!(AiConversationStore::generate_safe_title("### Fix terminal cursor issue"), "Fix terminal cursor issue");
        let long_prompt = "This is an extremely long user prompt that exceeds the forty-eight character limit easily";
        let safe = AiConversationStore::generate_safe_title(long_prompt);
        assert!(safe.ends_with("..."));
        assert!(safe.len() <= 55);
    }

    #[test]
    fn test_conversation_crud() {
        let store = AiConversationStore::new_in_memory().expect("in-memory db");
        let conv = store.create_conversation(
            Some("Initial Title"),
            Some("/path/to/project"),
            None,
            Some("project"),
            Some("openrouter"),
            Some("openrouter/openrouter/free"),
        ).expect("created");

        assert_eq!(conv.title, "Initial Title");
        assert_eq!(conv.project_path.as_deref(), Some("/path/to/project"));

        let list = store.list_conversations(10, 0).expect("list");
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].id, conv.id);

        store.update_title(&conv.id, "Renamed Title").expect("rename");
        let detail = store.get_conversation(&conv.id).expect("get").expect("found");
        assert_eq!(detail.title, "Renamed Title");

        store.delete_conversation(&conv.id).expect("delete");
        let after = store.get_conversation(&conv.id).expect("get");
        assert!(after.is_none());
    }

    #[test]
    fn test_message_and_activity_persistence() {
        let store = AiConversationStore::new_in_memory().expect("in-memory db");
        let conv = store.create_conversation(Some("Chat"), None, None, None, None, None).expect("create");

        let user_msg = AiConversationMessage {
            id: "msg_user_1".to_string(),
            conversation_id: conv.id.clone(),
            role: "user".to_string(),
            content: "Fix the cursor".to_string(),
            created_at: 1000,
            status: "completed".to_string(),
            task_id: Some("task_1".to_string()),
            provider_id: None,
            model_id: None,
            activities: Vec::new(),
            error: None,
        };
        store.add_message(&user_msg).expect("add user msg");

        let activity = AiActivity {
            activity_id: "act_1".to_string(),
            task_id: "task_1".to_string(),
            timestamp: 1001,
            activity_type: AiActivityType::Reading,
            status: AiActivityStatus::Completed,
            title: "Reading TerminalEmulator.tsx".to_string(),
            detail: None,
            tool: Some("read".to_string()),
            command: None,
            file_path: Some("TerminalEmulator.tsx".to_string()),
            duration_ms: Some(42),
            exit_code: Some(0),
        };

        let asst_msg = AiConversationMessage {
            id: "msg_asst_1".to_string(),
            conversation_id: conv.id.clone(),
            role: "assistant".to_string(),
            content: "I have fixed the cursor issue.".to_string(),
            created_at: 1002,
            status: "completed".to_string(),
            task_id: Some("task_1".to_string()),
            provider_id: Some("openrouter".to_string()),
            model_id: Some("openrouter/free".to_string()),
            activities: vec![activity],
            error: None,
        };
        store.add_message(&asst_msg).expect("add asst msg");

        let detail = store.get_conversation(&conv.id).expect("get").expect("found");
        assert_eq!(detail.message_count, 2);
        assert_eq!(detail.messages.len(), 2);
        assert_eq!(detail.messages[1].activities.len(), 1);
        assert_eq!(detail.messages[1].activities[0].title, "Reading TerminalEmulator.tsx");

        // Export markdown
        let md = store.export_markdown(&conv.id).expect("export markdown");
        assert!(md.contains("# Chat"));
        assert!(md.contains("Reading TerminalEmulator.tsx"));
        assert!(md.contains("Fix the cursor"));

        // Export JSON
        let json = store.export_json(&conv.id).expect("export json");
        assert!(json.contains("msg_user_1"));
    }

    #[test]
    fn test_search_conversations() {
        let store = AiConversationStore::new_in_memory().expect("in-memory db");
        let conv = store.create_conversation(Some("Architecture overview"), Some("/home/orbit"), None, None, None, None).expect("create");

        let msg = AiConversationMessage {
            id: "msg_1".to_string(),
            conversation_id: conv.id.clone(),
            role: "user".to_string(),
            content: "Please explain the WebSocket protocol.".to_string(),
            created_at: 1000,
            status: "completed".to_string(),
            task_id: None,
            provider_id: None,
            model_id: None,
            activities: Vec::new(),
            error: None,
        };
        store.add_message(&msg).expect("add msg");

        let res_title = store.search_conversations("Architecture", 10).expect("search");
        assert_eq!(res_title.len(), 1);
        assert_eq!(res_title[0].conversation_id, conv.id);

        let res_content = store.search_conversations("WebSocket", 10).expect("search");
        assert_eq!(res_content.len(), 1);
        assert_eq!(res_content[0].conversation_id, conv.id);
        assert_eq!(res_content[0].matched_field, "message");
    }

    #[test]
    fn test_session_mapping_resumption() {
        let store = AiConversationStore::new_in_memory().expect("in-memory db");
        let conv = store.create_conversation(Some("Session test"), None, None, None, None, None).expect("create");
        store.update_session_mapping(&conv.id, "ses_test123").expect("update session");

        let found = store.get_conversation_by_session_id("ses_test123").expect("query").expect("found");
        assert_eq!(found.id, conv.id);
    }
}
