use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::{Instant, SystemTime, UNIX_EPOCH};
use tokio::io::AsyncBufReadExt;
use tokio::sync::{broadcast, oneshot, Mutex};
use uuid::Uuid;

use super::models::{AiAgent, AiBroadcastEvent, AiTask, AiTaskStatus, AiTaskSummary};
use super::parser::{redact_secrets, OpenCodeEventParser, ParsedOpenCodeItem};
use super::process::OpenCodeRunner;
use crate::projects::ProjectManager;
use crate::protocol::errors::ProtocolError;

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub struct AiTaskManager {
    tasks: Arc<RwLock<HashMap<String, Arc<Mutex<AiTask>>>>>,
    cancel_handles: Arc<Mutex<HashMap<String, oneshot::Sender<()>>>>,
    event_sender: broadcast::Sender<AiBroadcastEvent>,
    project_manager: Arc<ProjectManager>,
    permission_manager: Arc<super::permission::PermissionManager>,
    conversation_store: Arc<super::storage::AiConversationStore>,
    provider_manager: Arc<super::provider_manager::AiProviderManager>,
    opencode_manager: Arc<crate::opencode_manager::OpencodeManager>,
}

impl AiTaskManager {
    pub fn new(project_manager: Arc<ProjectManager>) -> Self {
        let store = super::storage::AiConversationStore::default_store().unwrap_or_else(|_| {
            super::storage::AiConversationStore::new_in_memory().expect("in-memory sqlite")
        });
        let opencode_manager =
            Arc::new(crate::opencode_manager::OpencodeManager::with_default_dir());
        Self::with_all(project_manager, Arc::new(store), opencode_manager)
    }

    pub fn with_store(
        project_manager: Arc<ProjectManager>,
        conversation_store: Arc<super::storage::AiConversationStore>,
    ) -> Self {
        let opencode_manager =
            Arc::new(crate::opencode_manager::OpencodeManager::with_default_dir());
        Self::with_all(project_manager, conversation_store, opencode_manager)
    }

    pub fn with_opencode_manager(
        project_manager: Arc<ProjectManager>,
        opencode_manager: Arc<crate::opencode_manager::OpencodeManager>,
    ) -> Self {
        let store = super::storage::AiConversationStore::default_store().unwrap_or_else(|_| {
            super::storage::AiConversationStore::new_in_memory().expect("in-memory sqlite")
        });
        Self::with_all(project_manager, Arc::new(store), opencode_manager)
    }

    pub fn with_all(
        project_manager: Arc<ProjectManager>,
        conversation_store: Arc<super::storage::AiConversationStore>,
        opencode_manager: Arc<crate::opencode_manager::OpencodeManager>,
    ) -> Self {
        let (event_sender, _) = broadcast::channel(512);
        Self {
            tasks: Arc::new(RwLock::new(HashMap::new())),
            cancel_handles: Arc::new(Mutex::new(HashMap::new())),
            event_sender,
            project_manager,
            permission_manager: Arc::new(super::permission::PermissionManager::new()),
            conversation_store,
            provider_manager: Arc::new(super::provider_manager::AiProviderManager::new()),
            opencode_manager,
        }
    }

    pub fn opencode_manager(&self) -> Arc<crate::opencode_manager::OpencodeManager> {
        Arc::clone(&self.opencode_manager)
    }

    pub fn conversation_store(&self) -> Arc<super::storage::AiConversationStore> {
        Arc::clone(&self.conversation_store)
    }

    pub fn provider_manager(&self) -> Arc<super::provider_manager::AiProviderManager> {
        Arc::clone(&self.provider_manager)
    }

    pub fn permission_manager(&self) -> Arc<super::permission::PermissionManager> {
        Arc::clone(&self.permission_manager)
    }

    pub fn subscribe_events(&self) -> broadcast::Receiver<AiBroadcastEvent> {
        self.event_sender.subscribe()
    }

    pub fn list_tasks(&self, device_id: &str) -> Vec<AiTaskSummary> {
        let tasks_guard = self.tasks.read().unwrap();
        let mut summaries = Vec::new();

        for task_arc in tasks_guard.values() {
            if let Ok(task) = task_arc.try_lock() {
                if task.device_id == device_id {
                    summaries.push(task.to_summary());
                }
            }
        }

        summaries.sort_by_key(|a| std::cmp::Reverse(a.started_at));
        summaries
    }

    pub async fn get_task(&self, task_id: &str, device_id: &str) -> Result<AiTask, ProtocolError> {
        let task_arc = {
            let tasks_guard = self.tasks.read().unwrap();
            tasks_guard
                .get(task_id)
                .cloned()
                .ok_or_else(|| ProtocolError::ai_task_not_found(task_id))?
        };

        let task = task_arc.lock().await.clone();
        if task.device_id != device_id {
            return Err(ProtocolError::unauthorized(
                "Access denied: task belongs to another device.",
            ));
        }

        Ok(task)
    }

    pub fn list_pending_permissions(
        &self,
        device_id: &str,
    ) -> Vec<super::permission::AiPermissionRequest> {
        self.permission_manager.list_pending(device_id)
    }

    pub async fn resolve_permission(
        &self,
        device_id: &str,
        permission_id: &str,
        decision: super::permission::AiPermissionDecision,
    ) -> Result<super::permission::AiPermissionRequest, ProtocolError> {
        let req = self
            .permission_manager
            .resolve_request(device_id, permission_id, decision)
            .await?;

        let reply_str = match decision {
            super::permission::AiPermissionDecision::Allow => "once",
            super::permission::AiPermissionDecision::Always => "always",
            super::permission::AiPermissionDecision::Deny => "reject",
        };

        let decision_str = match decision {
            super::permission::AiPermissionDecision::Allow => "approved",
            super::permission::AiPermissionDecision::Always => "approved",
            super::permission::AiPermissionDecision::Deny => "denied",
        };

        let _ = self
            .event_sender
            .send(AiBroadcastEvent::PermissionResolved {
                task_id: req.task_id.clone(),
                device_id: req.device_id.clone(),
                open_code_session_id: req.session_id.clone(),
                permission_id: req.permission_id.clone(),
                decision: decision_str.to_string(),
                reply: reply_str.to_string(),
            });

        // Add activity record to the task
        let task_arc_opt = {
            let tasks_guard = self.tasks.read().unwrap();
            tasks_guard.get(&req.task_id).cloned()
        };

        if let Some(task_arc) = task_arc_opt {
            let mut task = task_arc.lock().await;
            let act_id = format!("act_{}_perm_res", now_unix());
            let title = format!("Permission {}: {}", decision_str, req.target);
            let activity = super::models::AiActivity {
                activity_id: act_id,
                task_id: req.task_id.clone(),
                timestamp: now_unix(),
                activity_type: super::models::AiActivityType::PermissionRequired,
                status: if decision_str == "approved" {
                    super::models::AiActivityStatus::Completed
                } else {
                    super::models::AiActivityStatus::Failed
                },
                title: title.clone(),
                detail: Some(format!("Action '{}' on {}", req.action, req.project_path)),
                tool: Some(req.tool.clone()),
                command: if req.tool == "bash" {
                    Some(req.target.clone())
                } else {
                    None
                },
                file_path: if req.tool != "bash" {
                    Some(req.target.clone())
                } else {
                    None
                },
                duration_ms: None,
                exit_code: None,
            };
            task.push_activity(activity.clone());

            let _ = self.event_sender.send(AiBroadcastEvent::Activity {
                task_id: req.task_id.clone(),
                device_id: req.device_id.clone(),
                open_code_session_id: req.session_id.clone(),
                activity,
            });

            let _ = self.event_sender.send(AiBroadcastEvent::Updated {
                task_id: req.task_id.clone(),
                device_id: req.device_id.clone(),
                open_code_session_id: req.session_id.clone(),
                activity: title,
            });
        }

        Ok(req)
    }

    pub async fn start_task(
        &self,
        device_id: &str,
        raw_project_path: &str,
        prompt: &str,
        agent_str: Option<&str>,
        read_only_opt: Option<bool>,
    ) -> Result<AiTaskSummary, ProtocolError> {
        self.launch_task_internal(
            device_id,
            raw_project_path,
            prompt,
            agent_str,
            read_only_opt,
            None,
            None,
            None,
        )
        .await
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn start_task_extended(
        &self,
        device_id: &str,
        raw_project_path: &str,
        prompt: &str,
        agent_str: Option<&str>,
        read_only_opt: Option<bool>,
        conversation_id_opt: Option<String>,
        model_override: Option<String>,
    ) -> Result<AiTaskSummary, ProtocolError> {
        self.launch_task_internal(
            device_id,
            raw_project_path,
            prompt,
            agent_str,
            read_only_opt,
            None,
            conversation_id_opt,
            model_override,
        )
        .await
    }

    pub async fn resume_task(
        &self,
        device_id: &str,
        session_id: &str,
        raw_project_path: &str,
        prompt: &str,
        agent_str: Option<&str>,
        read_only_opt: Option<bool>,
    ) -> Result<AiTaskSummary, ProtocolError> {
        self.resume_task_extended(
            device_id,
            session_id,
            raw_project_path,
            prompt,
            agent_str,
            read_only_opt,
            None,
            None,
        )
        .await
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn resume_task_extended(
        &self,
        device_id: &str,
        session_id: &str,
        raw_project_path: &str,
        prompt: &str,
        agent_str: Option<&str>,
        read_only_opt: Option<bool>,
        conversation_id_opt: Option<String>,
        model_override: Option<String>,
    ) -> Result<AiTaskSummary, ProtocolError> {
        let trimmed_session = session_id.trim();
        if trimmed_session.is_empty() || !trimmed_session.starts_with("ses_") {
            return Err(ProtocolError::ai_session_not_found(session_id));
        }

        // Validate session ownership if known
        {
            let tasks_guard = self.tasks.read().unwrap();
            for task_arc in tasks_guard.values() {
                if let Ok(task) = task_arc.try_lock() {
                    if task.open_code_session_id.as_deref() == Some(trimmed_session)
                        && task.device_id != device_id
                    {
                        return Err(ProtocolError::ai_session_not_allowed(
                            "Session belongs to another paired device.",
                        ));
                    }
                }
            }
        }

        self.launch_task_internal(
            device_id,
            raw_project_path,
            prompt,
            agent_str,
            read_only_opt,
            Some(trimmed_session.to_string()),
            conversation_id_opt,
            model_override,
        )
        .await
    }

    #[allow(clippy::too_many_arguments)]
    async fn launch_task_internal(
        &self,
        device_id: &str,
        raw_project_path: &str,
        prompt: &str,
        agent_str: Option<&str>,
        read_only_opt: Option<bool>,
        resume_session_id: Option<String>,
        conversation_id_opt: Option<String>,
        model_override: Option<String>,
    ) -> Result<AiTaskSummary, ProtocolError> {
        // 1. Validate prompt
        let prompt_trimmed = prompt.trim();
        if prompt_trimmed.is_empty() {
            return Err(ProtocolError::ai_task_invalid_prompt(
                "Prompt cannot be empty.",
            ));
        }

        // 2. Resolve & validate agent mode
        let agent = if let Some(a_str) = agent_str {
            AiAgent::from_str_loose(a_str).ok_or_else(|| {
                ProtocolError::ai_task_invalid_agent(format!(
                    "Unknown agent '{}'. Expected 'plan' or 'build'.",
                    a_str
                ))
            })?
        } else {
            AiAgent::Plan
        };

        // Determine read_only status: plan must always be read_only
        let read_only = match agent {
            AiAgent::Plan => true,
            AiAgent::Build => read_only_opt.unwrap_or(false),
        };

        // 3. Validate working context via validate_ai_working_directory
        let (execution_path, reported_project_path) =
            match super::context::validate_ai_working_directory(
                raw_project_path,
                &self.project_manager,
            ) {
                Ok(super::context::ValidatedAiContext::NoContext) => {
                    let sandbox = std::env::temp_dir().join("orbit_ai_sandbox");
                    let _ = std::fs::create_dir_all(&sandbox);
                    (sandbox, std::path::PathBuf::from(""))
                }
                Ok(super::context::ValidatedAiContext::Directory(p)) => (p.clone(), p),
                Err(e) => return Err(e),
            };

        // 4. Resolve OpenCode binary from OpencodeManager
        let binary_path = self
            .opencode_manager
            .resolve_binary_path()
            .map_err(|e| ProtocolError::opencode_not_found_with_msg(e))?;

        // 5. Conversation resolution and SQLite record
        // Authoritative model resolution, identical for Desktop and Mobile:
        // explicit override > conversation model > stored Orbit defaults.
        // A conversation without a model must NOT yield "unknown" — it
        // resolves to the default model instead.
        let default_model = self
            .conversation_store
            .get_defaults()
            .ok()
            .map(|d| d.model_id)
            .filter(|m| !m.trim().is_empty());
        let (conversation_id, effective_session_id, effective_model) = {
            let store = &self.conversation_store;
            if let Some(ref cid) = conversation_id_opt {
                if let Ok(Some(conv)) = store.get_conversation(cid) {
                    let s_id = resume_session_id.or(conv.open_code_session_id);
                    let m_id = model_override.or(conv.model_id).or(default_model.clone());
                    (cid.clone(), s_id, m_id)
                } else {
                    (
                        cid.clone(),
                        resume_session_id,
                        model_override.or(default_model.clone()),
                    )
                }
            } else if let Some(ref sid) = resume_session_id {
                if let Ok(Some(conv)) = store.get_conversation_by_session_id(sid) {
                    (
                        conv.id,
                        Some(sid.clone()),
                        model_override.or(conv.model_id).or(default_model.clone()),
                    )
                } else {
                    let summary = store.create_conversation(
                        Some(&super::storage::AiConversationStore::generate_safe_title(
                            prompt_trimmed,
                        )),
                        if raw_project_path.is_empty() {
                            None
                        } else {
                            Some(raw_project_path)
                        },
                        None,
                        Some(if raw_project_path.is_empty() {
                            "none"
                        } else {
                            "project"
                        }),
                        None,
                        model_override.as_deref(),
                    )?;
                    let _ = store.update_session_mapping(&summary.id, sid);
                    (
                        summary.id,
                        Some(sid.clone()),
                        model_override.or(default_model.clone()),
                    )
                }
            } else {
                let defs = store.get_defaults().unwrap_or_default();
                let chosen_model = model_override.unwrap_or(defs.model_id);
                let summary = store.create_conversation(
                    Some(&super::storage::AiConversationStore::generate_safe_title(
                        prompt_trimmed,
                    )),
                    if raw_project_path.is_empty() {
                        None
                    } else {
                        Some(raw_project_path)
                    },
                    None,
                    Some(if raw_project_path.is_empty() {
                        "none"
                    } else {
                        "project"
                    }),
                    Some(&defs.provider_id),
                    Some(&chosen_model),
                )?;
                (summary.id, None, Some(chosen_model))
            }
        };

        // 6. Generate unique Orbit Task ID
        let task_id = format!("task_{}", Uuid::new_v4().simple());
        let started_at = now_unix();

        // Record user message in SQLite
        let user_msg_id = format!("msg_{}", Uuid::new_v4().simple());
        let _ = self
            .conversation_store
            .add_message(&super::storage::AiConversationMessage {
                id: user_msg_id,
                conversation_id: conversation_id.clone(),
                role: "user".to_string(),
                content: prompt_trimmed.to_string(),
                created_at: chrono::Utc::now().timestamp(),
                status: "completed".to_string(),
                task_id: Some(task_id.clone()),
                provider_id: None,
                model_id: effective_model.clone(),
                activities: Vec::new(),
                error: None,
            });
        let _ = self
            .conversation_store
            .update_status(&conversation_id, "running");

        let task = AiTask {
            task_id: task_id.clone(),
            device_id: device_id.to_string(),
            project_path: reported_project_path.clone(),
            prompt: prompt_trimmed.to_string(),
            agent,
            read_only,
            status: AiTaskStatus::Queued,
            open_code_session_id: effective_session_id.clone(),
            child_pid: None,
            started_at,
            finished_at: None,
            output: None,
            response: None,
            error: None,
            conversation_id: Some(conversation_id.clone()),
            model: effective_model.clone(),
            activities: Vec::new(),
        };

        let summary = task.to_summary();
        let task_arc = Arc::new(Mutex::new(task));

        // Store task
        {
            let mut tasks_guard = self.tasks.write().unwrap();
            tasks_guard.insert(task_id.clone(), Arc::clone(&task_arc));
        }

        // Setup cancellation channel
        let (cancel_tx, cancel_rx) = oneshot::channel::<()>();
        {
            let mut handles = self.cancel_handles.lock().await;
            handles.insert(task_id.clone(), cancel_tx);
        }

        // Emit Created event
        let _ = self.event_sender.send(AiBroadcastEvent::Created {
            task_id: task_id.clone(),
            device_id: device_id.to_string(),
            project_path: reported_project_path.to_string_lossy().to_string(),
            agent: agent.as_str().to_string(),
            read_only,
        });

        // Spawn runner background task
        let event_tx = self.event_sender.clone();
        let cancel_handles_clone = Arc::clone(&self.cancel_handles);
        let task_id_clone = task_id.clone();
        let device_id_clone = device_id.to_string();
        let prompt_string = prompt_trimmed.to_string();
        let permission_manager_clone = Arc::clone(&self.permission_manager);
        let conversation_store_clone = Arc::clone(&self.conversation_store);
        let conversation_id_clone = conversation_id.clone();
        let model_clone = effective_model.clone();

        tokio::spawn(async move {
            Self::run_task_lifecycle(
                task_id_clone,
                device_id_clone,
                binary_path,
                execution_path,
                prompt_string,
                agent,
                effective_session_id,
                task_arc,
                cancel_rx,
                cancel_handles_clone,
                event_tx,
                permission_manager_clone,
                conversation_store_clone,
                conversation_id_clone,
                model_clone,
            )
            .await;
        });

        Ok(summary)
    }

    #[allow(clippy::too_many_arguments)]
    async fn run_task_lifecycle(
        task_id: String,
        device_id: String,
        binary_path: std::path::PathBuf,
        project_path: std::path::PathBuf,
        prompt: String,
        agent: AiAgent,
        session_id: Option<String>,
        task_arc: Arc<Mutex<AiTask>>,
        mut cancel_rx: oneshot::Receiver<()>,
        cancel_handles: Arc<Mutex<HashMap<String, oneshot::Sender<()>>>>,
        event_tx: broadcast::Sender<AiBroadcastEvent>,
        permission_manager: Arc<super::permission::PermissionManager>,
        conversation_store: Arc<super::storage::AiConversationStore>,
        conversation_id: String,
        model: Option<String>,
    ) {
        let start_time = Instant::now();

        // 1. Spawn child process
        let mut spawn_res = match OpenCodeRunner::spawn(
            &binary_path,
            &project_path,
            &prompt,
            agent,
            session_id.as_deref(),
            model.as_deref(),
        ) {
            Ok(res) => res,
            Err(e) => {
                let mut task = task_arc.lock().await;
                task.status = AiTaskStatus::Failed;
                task.finished_at = Some(now_unix());
                task.error = Some(e.message.clone());

                let _ = conversation_store.add_message(&super::storage::AiConversationMessage {
                    id: format!("msg_{}", Uuid::new_v4().simple()),
                    conversation_id: conversation_id.clone(),
                    role: "assistant".to_string(),
                    content: format!("Failed to spawn OpenCode: {}", e.message),
                    created_at: chrono::Utc::now().timestamp(),
                    status: "failed".to_string(),
                    task_id: Some(task_id.clone()),
                    provider_id: None,
                    model_id: model.clone(),
                    activities: Vec::new(),
                    error: Some(e.message.clone()),
                });
                let _ = conversation_store.update_status(&conversation_id, "failed");

                let _ = event_tx.send(AiBroadcastEvent::Failed {
                    task_id: task_id.clone(),
                    device_id,
                    open_code_session_id: session_id,
                    error: e.message,
                });

                let mut handles = cancel_handles.lock().await;
                handles.remove(&task_id);
                return;
            }
        };

        // Update task status to Running
        {
            let mut task = task_arc.lock().await;
            task.status = AiTaskStatus::Running;
            task.child_pid = spawn_res.pid;
        }

        let mut current_session_id = session_id.clone();

        let _ = event_tx.send(AiBroadcastEvent::Started {
            task_id: task_id.clone(),
            device_id: device_id.clone(),
            open_code_session_id: current_session_id.clone(),
        });

        let mut lines = spawn_res.stdout_reader.lines();
        let mut was_cancelled = false;
        let mut activity_seq: u64 = 0;
        // Last upstream provider/model error reported by OpenCode itself
        // (message is pre-sanitized by the parser; no secrets).
        let mut upstream_error: Option<(String, Option<i64>)> = None;

        loop {
            tokio::select! {
                _ = &mut cancel_rx => {
                    was_cancelled = true;
                    OpenCodeRunner::cancel_child(&mut spawn_res.child, spawn_res.pid).await;
                    break;
                }
                line_res = lines.next_line() => {
                    match line_res {
                        Ok(Some(line)) => {
                            if current_session_id.is_none() {
                                if let Ok(json_val) = serde_json::from_str::<serde_json::Value>(&line) {
                                    if let Some(sid) = OpenCodeEventParser::extract_session_id(&json_val) {
                                        current_session_id = Some(sid.clone());
                                        let mut task = task_arc.lock().await;
                                        task.open_code_session_id = Some(sid.clone());
                                        let _ = conversation_store.update_session_mapping(&conversation_id, &sid);
                                    }
                                }
                            }

                            match OpenCodeEventParser::parse_line_with_project(&line, Some(&project_path)) {
                                ParsedOpenCodeItem::UpstreamError { message, status_code } => {
                                    // Keep the most recent upstream reason for failure reporting.
                                    upstream_error = Some((message, status_code));
                                }
                                ParsedOpenCodeItem::SessionIdDiscovered(sid) => {
                                    current_session_id = Some(sid.clone());
                                    let mut task = task_arc.lock().await;
                                    task.open_code_session_id = Some(sid.clone());
                                    let _ = conversation_store.update_session_mapping(&conversation_id, &sid);
                                }
                                ParsedOpenCodeItem::Activity(info) => {
                                    activity_seq += 1;
                                    let activity = super::models::AiActivity {
                                        activity_id: format!("act_{}_{}", now_unix(), activity_seq),
                                        task_id: task_id.clone(),
                                        timestamp: now_unix(),
                                        activity_type: info.activity_type,
                                        status: info.status,
                                        title: info.title.clone(),
                                        detail: info.detail,
                                        tool: info.tool,
                                        command: info.command,
                                        file_path: info.file_path,
                                        duration_ms: info.duration_ms,
                                        exit_code: info.exit_code,
                                    };

                                    {
                                        let mut task = task_arc.lock().await;
                                        task.push_activity(activity.clone());
                                    }

                                    let _ = event_tx.send(AiBroadcastEvent::Activity {
                                        task_id: task_id.clone(),
                                        device_id: device_id.clone(),
                                        open_code_session_id: current_session_id.clone(),
                                        activity,
                                    });

                                    let _ = event_tx.send(AiBroadcastEvent::Updated {
                                        task_id: task_id.clone(),
                                        device_id: device_id.clone(),
                                        open_code_session_id: current_session_id.clone(),
                                        activity: info.title,
                                    });
                                }
                                ParsedOpenCodeItem::ToolStarted { tool, status, title, command, file_path } => {
                                    activity_seq += 1;
                                    let activity_type = if tool == "bash" || command.is_some() {
                                        if command.as_deref().unwrap_or("").contains("test")
                                            || command.as_deref().unwrap_or("").contains("analyze")
                                        {
                                            super::models::AiActivityType::Testing
                                        } else {
                                            super::models::AiActivityType::Command
                                        }
                                    } else if tool.contains("read") {
                                        super::models::AiActivityType::Reading
                                    } else if tool.contains("write") || tool.contains("edit") {
                                        super::models::AiActivityType::Writing
                                    } else {
                                        super::models::AiActivityType::Tool
                                    };

                                    let act_title = if tool == "bash" || command.is_some() {
                                        let cmd = command.as_deref().unwrap_or("command");
                                        let short_cmd = if cmd.len() > 45 {
                                            format!("{}...", &cmd[..42])
                                        } else {
                                            cmd.to_string()
                                        };
                                        format!("Running {}", short_cmd)
                                    } else if tool.contains("read") {
                                        let f = file_path.as_deref().unwrap_or("file");
                                        format!("Reading {}", f)
                                    } else if tool.contains("write") || tool.contains("edit") {
                                        let f = file_path.as_deref().unwrap_or("file");
                                        format!("Updating {}", f)
                                    } else if tool.contains("list") || tool.contains("search") || tool.contains("glob") {
                                        let target = file_path.as_deref().or(command.as_deref()).unwrap_or("files");
                                        format!("Searching {}", target)
                                    } else if let Some(ref t) = title {
                                        t.clone()
                                    } else {
                                        format!("Running {}", tool)
                                    };

                                    let activity = super::models::AiActivity {
                                        activity_id: format!("act_{}_{}", now_unix(), activity_seq),
                                        task_id: task_id.clone(),
                                        timestamp: now_unix(),
                                        activity_type,
                                        status: super::models::AiActivityStatus::Running,
                                        title: act_title,
                                        detail: command.clone().or_else(|| file_path.clone()),
                                        tool: Some(tool.clone()),
                                        command: command.clone(),
                                        file_path: file_path.clone(),
                                        duration_ms: None,
                                        exit_code: None,
                                    };

                                    {
                                        let mut task = task_arc.lock().await;
                                        task.push_activity(activity.clone());
                                    }

                                    let _ = event_tx.send(AiBroadcastEvent::Activity {
                                        task_id: task_id.clone(),
                                        device_id: device_id.clone(),
                                        open_code_session_id: current_session_id.clone(),
                                        activity,
                                    });

                                    let _ = event_tx.send(AiBroadcastEvent::ToolStarted {
                                        task_id: task_id.clone(),
                                        device_id: device_id.clone(),
                                        open_code_session_id: current_session_id.clone(),
                                        tool,
                                        status,
                                        title,
                                    });
                                }
                                ParsedOpenCodeItem::ToolFinished { tool, status, exit_code, duration_ms, command, file_path } => {
                                    activity_seq += 1;
                                    let act_status = if status == "error" || exit_code.unwrap_or(0) != 0 {
                                        super::models::AiActivityStatus::Failed
                                    } else {
                                        super::models::AiActivityStatus::Completed
                                    };

                                    let activity_type = if tool == "bash" || command.is_some() {
                                        if command.as_deref().unwrap_or("").contains("test")
                                            || command.as_deref().unwrap_or("").contains("analyze")
                                        {
                                            super::models::AiActivityType::Testing
                                        } else {
                                            super::models::AiActivityType::Command
                                        }
                                    } else if tool.contains("read") {
                                        super::models::AiActivityType::Reading
                                    } else if tool.contains("write") || tool.contains("edit") {
                                        super::models::AiActivityType::Writing
                                    } else {
                                        super::models::AiActivityType::Tool
                                    };

                                    let act_title = if let Some(ref c) = command {
                                        format!("Command {} finished", c)
                                    } else if let Some(ref f) = file_path {
                                        format!("File {} finished", f)
                                    } else {
                                        format!("Tool {} finished", tool)
                                    };

                                    let activity = super::models::AiActivity {
                                        activity_id: format!("act_{}_{}", now_unix(), activity_seq),
                                        task_id: task_id.clone(),
                                        timestamp: now_unix(),
                                        activity_type,
                                        status: act_status,
                                        title: act_title,
                                        detail: command.clone().or_else(|| file_path.clone()),
                                        tool: Some(tool.clone()),
                                        command,
                                        file_path,
                                        duration_ms,
                                        exit_code,
                                    };

                                    {
                                        let mut task = task_arc.lock().await;
                                        task.push_activity(activity.clone());
                                    }

                                    let _ = event_tx.send(AiBroadcastEvent::Activity {
                                        task_id: task_id.clone(),
                                        device_id: device_id.clone(),
                                        open_code_session_id: current_session_id.clone(),
                                        activity,
                                    });

                                    let _ = event_tx.send(AiBroadcastEvent::ToolFinished {
                                        task_id: task_id.clone(),
                                        device_id: device_id.clone(),
                                        open_code_session_id: current_session_id.clone(),
                                        tool,
                                        status,
                                        exit_code,
                                    });
                                }
                                ParsedOpenCodeItem::ResponseChunk(chunk) => {
                                    {
                                        let mut task = task_arc.lock().await;
                                        task.append_response(&chunk);
                                        task.append_output(&chunk);
                                    }
                                    let _ = event_tx.send(AiBroadcastEvent::ResponseChunk {
                                        task_id: task_id.clone(),
                                        device_id: device_id.clone(),
                                        open_code_session_id: current_session_id.clone(),
                                        text: chunk.clone(),
                                    });
                                    let _ = event_tx.send(AiBroadcastEvent::Output {
                                        task_id: task_id.clone(),
                                        device_id: device_id.clone(),
                                        open_code_session_id: current_session_id.clone(),
                                        text: chunk,
                                    });
                                }
                                ParsedOpenCodeItem::OutputChunk(chunk) => {
                                    {
                                        let mut task = task_arc.lock().await;
                                        task.append_output(&chunk);
                                    }
                                    let _ = event_tx.send(AiBroadcastEvent::Output {
                                        task_id: task_id.clone(),
                                        device_id: device_id.clone(),
                                        open_code_session_id: current_session_id.clone(),
                                        text: chunk,
                                    });
                                }
                                 ParsedOpenCodeItem::PermissionRequested {
                                    id,
                                    session_id: perm_sid,
                                    permission,
                                    patterns,
                                    metadata,
                                    always: _,
                                } => {
                                    if current_session_id.is_none() && perm_sid.is_some() {
                                        current_session_id = perm_sid.clone();
                                        let mut task = task_arc.lock().await;
                                        task.open_code_session_id = perm_sid.clone();
                                    }

                                    activity_seq += 1;
                                    let (req, mut rx) = permission_manager
                                        .create_request(
                                            id.clone(),
                                            task_id.clone(),
                                            device_id.clone(),
                                            current_session_id.clone(),
                                            permission.clone(),
                                            patterns.clone(),
                                            metadata.clone(),
                                            project_path.to_string_lossy().to_string(),
                                        )
                                        .await;

                                    let act_title = format!("Permission required: {}", req.action);
                                    let activity = super::models::AiActivity {
                                        activity_id: format!("act_{}_{}", now_unix(), activity_seq),
                                        task_id: task_id.clone(),
                                        timestamp: now_unix(),
                                        activity_type: super::models::AiActivityType::PermissionRequired,
                                        status: super::models::AiActivityStatus::Running,
                                        title: act_title.clone(),
                                        detail: Some(format!("Risk level: {}", req.risk.as_str())),
                                        tool: Some(permission.clone()),
                                        command: if permission == "bash" { Some(req.target.clone()) } else { None },
                                        file_path: if permission != "bash" { Some(req.target.clone()) } else { None },
                                        duration_ms: None,
                                        exit_code: None,
                                    };

                                    {
                                        let mut task = task_arc.lock().await;
                                        task.push_activity(activity.clone());
                                    }

                                    let _ = event_tx.send(AiBroadcastEvent::Activity {
                                        task_id: task_id.clone(),
                                        device_id: device_id.clone(),
                                        open_code_session_id: current_session_id.clone(),
                                        activity,
                                    });

                                    let _ = event_tx.send(AiBroadcastEvent::Updated {
                                        task_id: task_id.clone(),
                                        device_id: device_id.clone(),
                                        open_code_session_id: current_session_id.clone(),
                                        activity: act_title,
                                    });

                                    let _ = event_tx.send(AiBroadcastEvent::PermissionRequested {
                                        task_id: task_id.clone(),
                                        device_id: device_id.clone(),
                                        open_code_session_id: current_session_id.clone(),
                                        permission_id: id.clone(),
                                        tool: permission.clone(),
                                        action: req.action.clone(),
                                        target: req.target.clone(),
                                        patterns: patterns.clone(),
                                        project_path: req.project_path.clone(),
                                        risk: req.risk.as_str().to_string(),
                                        created_at: req.created_at,
                                        timeout_at: req.timeout_at,
                                    });

                                    // Wait for approval/rejection or task cancellation
                                    tokio::select! {
                                        _ = &mut cancel_rx => {
                                            was_cancelled = true;
                                            OpenCodeRunner::cancel_child(&mut spawn_res.child, spawn_res.pid).await;
                                            break;
                                        }
                                        res = &mut rx => {
                                            match res {
                                                Ok(super::permission::AiPermissionDecision::Allow)
                                                | Ok(super::permission::AiPermissionDecision::Always) => {
                                                    println!("[Orbit AI] Permission '{}' approved for task '{}'", id, task_id);
                                                }
                                                Ok(super::permission::AiPermissionDecision::Deny) => {
                                                    println!("[Orbit AI] Permission '{}' denied for task '{}'", id, task_id);
                                                }
                                                Err(_) => {
                                                    println!("[Orbit AI] Permission resolver dropped for task '{}'", task_id);
                                                }
                                            }
                                        }
                                    }
                                }
                                ParsedOpenCodeItem::PermissionReplied { id, session_id: rep_sid, reply } => {
                                    let decision_str = if reply == "reject" { "denied" } else { "approved" };
                                    let _ = event_tx.send(AiBroadcastEvent::PermissionResolved {
                                        task_id: task_id.clone(),
                                        device_id: device_id.clone(),
                                        open_code_session_id: rep_sid.or_else(|| current_session_id.clone()),
                                        permission_id: id,
                                        decision: decision_str.to_string(),
                                        reply,
                                    });
                                }
                                ParsedOpenCodeItem::Ignored => {}
                            }
                        }
                        Ok(None) => break, // EOF reached
                        Err(e) => {
                            eprintln!("[AiTaskManager] Error reading OpenCode stream: {}", e);
                            break;
                        }
                    }
                }
            }
        }

        // Wait for child process exit status
        let exit_status = spawn_res.child.wait().await;
        let duration_ms = start_time.elapsed().as_millis() as u64;
        let finished_at = now_unix();

        let mut task = task_arc.lock().await;
        task.finished_at = Some(finished_at);

        // Enforce deterministic cancellation and state transition
        if was_cancelled || task.status == AiTaskStatus::Cancelled {
            task.status = AiTaskStatus::Cancelled;
            let cancel_act = super::models::AiActivity {
                activity_id: format!("act_{}_cancel", finished_at),
                task_id: task_id.clone(),
                timestamp: finished_at,
                activity_type: super::models::AiActivityType::Completed,
                status: super::models::AiActivityStatus::Completed,
                title: "Task cancelled".to_string(),
                detail: Some("The AI task was stopped by user request".to_string()),
                tool: None,
                command: None,
                file_path: None,
                duration_ms: Some(duration_ms),
                exit_code: None,
            };
            task.push_activity(cancel_act.clone());

            let _ = event_tx.send(AiBroadcastEvent::Activity {
                task_id: task_id.clone(),
                device_id: device_id.clone(),
                open_code_session_id: current_session_id.clone(),
                activity: cancel_act,
            });

            let _ = event_tx.send(AiBroadcastEvent::Cancelled {
                task_id: task_id.clone(),
                device_id,
                open_code_session_id: current_session_id,
            });
        } else {
            match exit_status {
                Ok(status) if status.success() => {
                    task.status = AiTaskStatus::Completed;
                    let comp_act = super::models::AiActivity {
                        activity_id: format!("act_{}_complete", finished_at),
                        task_id: task_id.clone(),
                        timestamp: finished_at,
                        activity_type: super::models::AiActivityType::Completed,
                        status: super::models::AiActivityStatus::Completed,
                        title: "Task completed successfully".to_string(),
                        detail: None,
                        tool: None,
                        command: None,
                        file_path: None,
                        duration_ms: Some(duration_ms),
                        exit_code: Some(0),
                    };
                    task.push_activity(comp_act.clone());

                    let _ = event_tx.send(AiBroadcastEvent::Activity {
                        task_id: task_id.clone(),
                        device_id: device_id.clone(),
                        open_code_session_id: current_session_id.clone(),
                        activity: comp_act,
                    });

                    if task.response.as_ref().is_none_or(|r| r.trim().is_empty()) {
                        if let Some(out) = &task.output {
                            if !out.trim().is_empty() {
                                task.response = Some(out.clone());
                            }
                        }
                    }

                    let _ = event_tx.send(AiBroadcastEvent::Completed {
                        task_id: task_id.clone(),
                        device_id,
                        open_code_session_id: current_session_id,
                        duration_ms,
                    });
                }
                Ok(status) => {
                    // Prefer the real upstream reason (opencode error event),
                    // then the retained stderr tail, and only then the bare
                    // exit status — never a misleading generic rate-limit note
                    // when a safe, specific reason is available.
                    let mut reason: Option<String> = upstream_error.map(|(m, c)| match c {
                        Some(code) => format!("{} (HTTP {})", m, code),
                        None => m,
                    });
                    if reason.is_none() {
                        if let Ok(guard) = spawn_res.stderr_tail.lock() {
                            let tail = redact_secrets(guard.trim());
                            if !tail.is_empty() {
                                const MAX_REASON: usize = 800;
                                let mut short = tail;
                                if short.len() > MAX_REASON {
                                    short.truncate(MAX_REASON);
                                    short.push('…');
                                }
                                reason = Some(short);
                            }
                        }
                    }

                    // Provider/model labels for the normalized report. The
                    // conversation record is authoritative; the model id
                    // prefix (e.g. "openrouter" in "openrouter/...") is only
                    // a fallback. No credentials are ever read here.
                    let provider_label = conversation_store
                        .get_conversation(&conversation_id)
                        .ok()
                        .flatten()
                        .and_then(|c| c.provider_id)
                        .filter(|s| !s.trim().is_empty())
                        .or_else(|| {
                            model
                                .as_ref()
                                .and_then(|m| m.split('/').next().map(|s| s.to_string()))
                                .filter(|s| !s.trim().is_empty())
                        })
                        .unwrap_or_else(|| "unknown".to_string());
                    let model_label = model
                        .clone()
                        .filter(|m| !m.trim().is_empty())
                        .unwrap_or_else(|| "unknown".to_string());

                    let has_reason = reason.is_some();
                    let err_msg = match reason {
                        Some(r) => format!(
                            "Provider request failed\n\nProvider:\n{}\n\nModel:\n{}\n\nReason:\n{}",
                            provider_label, model_label, r
                        ),
                        None => format!("OpenCode process exited with status: {}", status),
                    };
                    task.status = AiTaskStatus::Failed;
                    task.error = Some(err_msg.clone());

                    if task.response.as_ref().is_none_or(|r| r.trim().is_empty()) {
                        let explanation = if has_reason {
                            err_msg.clone()
                        } else {
                            "I was unable to complete this task due to an upstream provider error (such as an API rate limit). Please verify your model provider settings or quota, then try again.".to_string()
                        };
                        task.response = Some(explanation.clone());
                        let _ = event_tx.send(AiBroadcastEvent::ResponseChunk {
                            task_id: task_id.clone(),
                            device_id: device_id.clone(),
                            open_code_session_id: current_session_id.clone(),
                            text: explanation,
                        });
                    }

                    let fail_act = super::models::AiActivity {
                        activity_id: format!("act_{}_fail", finished_at),
                        task_id: task_id.clone(),
                        timestamp: finished_at,
                        activity_type: super::models::AiActivityType::Error,
                        status: super::models::AiActivityStatus::Failed,
                        title: "Task execution failed".to_string(),
                        detail: Some(err_msg.clone()),
                        tool: None,
                        command: None,
                        file_path: None,
                        duration_ms: Some(duration_ms),
                        exit_code: status.code(),
                    };
                    task.push_activity(fail_act.clone());

                    let _ = event_tx.send(AiBroadcastEvent::Activity {
                        task_id: task_id.clone(),
                        device_id: device_id.clone(),
                        open_code_session_id: current_session_id.clone(),
                        activity: fail_act,
                    });

                    let _ = event_tx.send(AiBroadcastEvent::Failed {
                        task_id: task_id.clone(),
                        device_id,
                        open_code_session_id: current_session_id,
                        error: err_msg,
                    });
                }
                Err(e) => {
                    let err_msg = format!("Failed to wait for OpenCode process: {}", e);
                    task.status = AiTaskStatus::Failed;
                    task.error = Some(err_msg.clone());
                    let _ = event_tx.send(AiBroadcastEvent::Failed {
                        task_id: task_id.clone(),
                        device_id,
                        open_code_session_id: current_session_id,
                        error: err_msg,
                    });
                }
            }
        }

        // Persist assistant message in conversation store
        let asst_msg_id = format!("msg_{}", Uuid::new_v4().simple());
        let asst_content = task.response.clone().unwrap_or_else(|| {
            if task.status == AiTaskStatus::Cancelled {
                "Task was stopped by user request.".to_string()
            } else if let Some(ref err) = task.error {
                format!("Error: {}", err)
            } else {
                "Task completed without output.".to_string()
            }
        });
        let _ = conversation_store.add_message(&super::storage::AiConversationMessage {
            id: asst_msg_id,
            conversation_id: conversation_id.clone(),
            role: "assistant".to_string(),
            content: asst_content,
            created_at: chrono::Utc::now().timestamp(),
            status: task.status.as_str().to_string(),
            task_id: Some(task_id.clone()),
            provider_id: None,
            model_id: model.clone(),
            activities: task.activities.clone(),
            error: task.error.clone(),
        });
        let _ = conversation_store.update_status(&conversation_id, task.status.as_str());

        // Clean up cancel handle
        let mut handles = cancel_handles.lock().await;
        handles.remove(&task_id);
    }

    pub async fn cancel_task(&self, task_id: &str, device_id: &str) -> Result<(), ProtocolError> {
        let task_arc = {
            let tasks_guard = self.tasks.read().unwrap();
            tasks_guard
                .get(task_id)
                .cloned()
                .ok_or_else(|| ProtocolError::ai_task_not_found(task_id))?
        };

        let mut task = task_arc.lock().await;

        // Verify device ownership
        if task.device_id != device_id {
            return Err(ProtocolError::unauthorized(
                "Access denied: only the device that started this task may cancel it.",
            ));
        }

        if task.status.is_terminal() {
            return Ok(());
        }

        // Signal runner cancel
        let mut handles = self.cancel_handles.lock().await;
        if let Some(cancel_tx) = handles.remove(task_id) {
            let _ = cancel_tx.send(());
        }

        task.status = AiTaskStatus::Cancelled;
        task.finished_at = Some(now_unix());

        let _ = self.event_sender.send(AiBroadcastEvent::Cancelled {
            task_id: task_id.to_string(),
            device_id: device_id.to_string(),
            open_code_session_id: task.open_code_session_id.clone(),
        });

        // Cancel all pending permissions for this task
        let cancelled_perms = self.permission_manager.cancel_task_requests(task_id).await;
        for perm in cancelled_perms {
            let _ = self
                .event_sender
                .send(AiBroadcastEvent::PermissionResolved {
                    task_id: perm.task_id,
                    device_id: perm.device_id,
                    open_code_session_id: perm.session_id,
                    permission_id: perm.permission_id,
                    decision: "cancelled".to_string(),
                    reply: "reject".to_string(),
                });
        }

        Ok(())
    }
}
