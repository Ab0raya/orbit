use std::sync::{Arc, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::agent::pairing::PairingManager;
use crate::agent::session::SessionManager;
use crate::agent::system::SystemManager;
use crate::ai::AiTaskManager;
use crate::files::{FileError, FileManager};
use crate::projects::{GitError, ProjectError, ProjectManager};
use crate::protocol::errors::ProtocolError;
use crate::protocol::events::OrbitEvent;
use crate::protocol::request::OrbitRequest;
use crate::protocol::response::OrbitResponse;
use crate::scripts::ScriptManager;
use crate::terminal::TerminalManager;

pub struct ActionContext {
    pub connection_id: String,
    pub pairing_manager: Arc<RwLock<PairingManager>>,
    pub session_manager: Arc<SessionManager>,
    pub system_manager: Arc<SystemManager>,
    pub terminal_manager: Arc<TerminalManager>,
    pub file_manager: Arc<FileManager>,
    pub project_manager: Arc<ProjectManager>,
    pub ai_task_manager: Arc<AiTaskManager>,
    pub script_manager: Arc<ScriptManager>,
    pub uptime_seconds: u64,
    pub server_port: u16,
    pub bind_address: String,
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn get_authenticated_device_id(ctx: &ActionContext) -> Result<String, ProtocolError> {
    ctx.session_manager
        .get_session(&ctx.connection_id)
        .and_then(|s| s.device_id)
        .ok_or_else(|| ProtocolError::unauthorized("Device must be paired to execute this action."))
}

pub struct ActionHandlers;

impl ActionHandlers {
    pub fn handle_ping(req: &OrbitRequest) -> OrbitResponse {
        OrbitResponse::success(
            &req.id,
            &req.action,
            serde_json::json!({
                "timestamp": now_unix()
            }),
        )
    }

    pub fn handle_pairing_verify(
        req: &OrbitRequest,
        ctx: &ActionContext,
    ) -> (OrbitResponse, Option<OrbitEvent>) {
        let conn_id = &ctx.connection_id;

        // Check rate limiting on failed attempts
        if ctx.session_manager.is_rate_limited(conn_id) {
            eprintln!(
                "[Orbit Security] Rate limit triggered for connection '{}' on pairing attempts",
                conn_id
            );
            return (
                OrbitResponse::error(&req.id, &req.action, ProtocolError::rate_limited()),
                None,
            );
        }

        // Extract code from payload
        let code = match req.payload.get("code").and_then(|v| v.as_str()) {
            Some(c) => c,
            None => {
                ctx.session_manager.increment_failed_attempts(conn_id);
                return (
                    OrbitResponse::error(
                        &req.id,
                        &req.action,
                        ProtocolError::invalid_pairing_code(),
                    ),
                    None,
                );
            }
        };

        // Validate pairing code against PairingManager
        let is_valid = {
            if let Ok(lock) = ctx.pairing_manager.read() {
                lock.verify_code(code)
            } else {
                false
            }
        };

        if !is_valid {
            let attempts = ctx.session_manager.increment_failed_attempts(conn_id);
            println!(
                "[Orbit Security] Pairing failed on connection '{}' (failed attempt {}/{})",
                conn_id, attempts, crate::agent::session::MAX_PAIRING_ATTEMPTS
            );
            return (
                OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::invalid_pairing_code(),
                ),
                None,
            );
        }

        // Pairing code is valid - extract client metadata (device name, platform)
        let device_name = req
            .payload
            .get("name")
            .or_else(|| req.payload.get("deviceName"))
            .and_then(|v| v.as_str())
            .unwrap_or("Mobile Device");

        let platform = req
            .payload
            .get("platform")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");

        let existing_device_id = req
            .payload
            .get("deviceId")
            .and_then(|v| v.as_str());

        match ctx.session_manager.mark_paired(conn_id, device_name, platform, existing_device_id) {
            Ok(paired_device) => {
                println!(
                    "[Orbit Security] Pairing SUCCESS: device '{}' ({}) paired with ID '{}' on connection '{}'",
                    paired_device.name, paired_device.platform, paired_device.device_id, conn_id
                );

                let event = OrbitEvent::device_paired(
                    &paired_device.device_id,
                    &paired_device.name,
                    &paired_device.platform,
                    paired_device.paired_at,
                );

                let response = OrbitResponse::success(
                    &req.id,
                    &req.action,
                    serde_json::json!({
                        "paired": true,
                        "deviceId": paired_device.device_id,
                    }),
                );

                (response, Some(event))
            }
            Err(e) => {
                eprintln!("[Orbit Security] Internal error during pairing registration: {}", e);
                (
                    OrbitResponse::error(
                        &req.id,
                        &req.action,
                        ProtocolError::internal_error("Failed to register paired device"),
                    ),
                    None,
                )
            }
        }
    }

    pub fn handle_session_resume(req: &OrbitRequest, ctx: &ActionContext) -> (OrbitResponse, Option<OrbitEvent>) {
        let conn_id = &ctx.connection_id;
        let device_id = match req.payload.get("deviceId").and_then(|v| v.as_str()) {
            Some(id) if !id.trim().is_empty() => id.trim(),
            _ => {
                return (
                    OrbitResponse::error(
                        &req.id,
                        &req.action,
                        ProtocolError::unauthorized("Missing or invalid 'deviceId' for session resume"),
                    ),
                    None,
                );
            }
        };

        match ctx.session_manager.resume_session(conn_id, device_id) {
            Ok(paired_device) => {
                println!(
                    "[Orbit Security] Session RESUME success: device '{}' ({}) reconnected with ID '{}' on connection '{}'",
                    paired_device.name, paired_device.platform, paired_device.device_id, conn_id
                );

                let event = OrbitEvent::device_paired(
                    &paired_device.device_id,
                    &paired_device.name,
                    &paired_device.platform,
                    paired_device.paired_at,
                );

                let response = OrbitResponse::success(
                    &req.id,
                    &req.action,
                    serde_json::json!({
                        "resumed": true,
                        "deviceId": paired_device.device_id,
                        "name": paired_device.name,
                        "platform": paired_device.platform,
                    }),
                );

                (response, Some(event))
            }
            Err(err_msg) => {
                println!(
                    "[Orbit Security] Session resume failed for device '{}' on connection '{}': {}",
                    device_id, conn_id, err_msg
                );
                (
                    OrbitResponse::error(
                        &req.id,
                        &req.action,
                        ProtocolError::unauthorized(&err_msg),
                    ),
                    None,
                )
            }
        }
    }

    pub fn handle_system_info(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let refresh = req
            .payload
            .get("refresh")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        if refresh {
            ctx.system_manager.tailscale_manager().clear_cache();
        }
        let sys = ctx.system_manager.get_info();
        OrbitResponse::success(
            &req.id,
            &req.action,
            serde_json::json!({
                "hostname": sys.device_name,
                "os": sys.os,
                "osVersion": sys.os_version,
                "architecture": sys.arch,
                "primaryIp": sys.primary_ip,
                "network": sys.local_ips,
                "tailscale": sys.tailscale,
            }),
        )
    }

    pub fn handle_tailscale_info(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let refresh = req
            .payload
            .get("refresh")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        if refresh {
            ctx.system_manager.tailscale_manager().clear_cache();
        }
        let ts = ctx.system_manager.tailscale_manager().get_info();
        OrbitResponse::success(
            &req.id,
            &req.action,
            serde_json::to_value(&ts).unwrap_or(serde_json::json!({
                "installed": false,
                "running": false,
                "state": "not_installed",
                "ip": null,
                "device_name": null,
                "tailnet_name": null,
                "error": null
            })),
        )
    }

    pub fn handle_agent_status(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        OrbitResponse::success(
            &req.id,
            &req.action,
            serde_json::json!({
                "status": "online",
                "uptimeSeconds": ctx.uptime_seconds,
                "version": env!("CARGO_PKG_VERSION"),
                "connectedDevices": ctx.session_manager.paired_connected_count(),
            }),
        )
    }

    pub fn handle_server_info(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        OrbitResponse::success(
            &req.id,
            &req.action,
            serde_json::json!({
                "port": ctx.server_port,
                "isListening": true,
                "bindAddress": ctx.bind_address,
                "connectedClients": ctx.session_manager.connected_clients_count(),
            }),
        )
    }

    pub fn handle_devices_list(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let devices: Vec<serde_json::Value> = ctx
            .session_manager
            .get_paired_devices()
            .into_iter()
            .map(|d| {
                serde_json::json!({
                    "deviceId": d.device_id,
                    "device_id": d.device_id,
                    "name": d.name,
                    "platform": d.platform,
                    "pairedAt": d.paired_at,
                    "lastSeenAt": d.last_seen_at,
                    "connected": d.connected,
                })
            })
            .collect();
        OrbitResponse::success(
            &req.id,
            &req.action,
            serde_json::json!({
                "devices": devices,
                "pairedCount": ctx.session_manager.paired_devices_total_count(),
                "connectedCount": ctx.session_manager.paired_connected_count(),
            }),
        )
    }

    // Terminal Handlers
    pub fn handle_terminal_create(
        req: &OrbitRequest,
        ctx: &ActionContext,
    ) -> (OrbitResponse, Option<OrbitEvent>) {
        let device_id = match get_authenticated_device_id(ctx) {
            Ok(id) => id,
            Err(err) => return (OrbitResponse::error(&req.id, &req.action, err), None),
        };

        let cwd = req.payload.get("cwd").and_then(|v| v.as_str());
        let cols = req.payload.get("cols").and_then(|v| v.as_u64()).map(|v| v as u16);
        let rows = req.payload.get("rows").and_then(|v| v.as_u64()).map(|v| v as u16);

        match ctx.terminal_manager.create_session(&device_id, cwd, cols, rows) {
            Ok(session) => {
                let summary = session.to_summary();
                let event = OrbitEvent::terminal_created(&summary.session_id);
                let response = OrbitResponse::success(
                    &req.id,
                    &req.action,
                    serde_json::json!({
                        "sessionId": summary.session_id,
                        "cwd": summary.cwd,
                        "shell": summary.shell,
                        "rows": summary.rows,
                        "cols": summary.cols,
                    }),
                );
                (response, Some(event))
            }
            Err(err) => (OrbitResponse::error(&req.id, &req.action, err), None),
        }
    }

    pub fn handle_terminal_input(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let device_id = match get_authenticated_device_id(ctx) {
            Ok(id) => id,
            Err(err) => return OrbitResponse::error(&req.id, &req.action, err),
        };

        let session_id = match req.payload.get("sessionId").and_then(|v| v.as_str()) {
            Some(id) => id,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'sessionId' in terminal.input payload"),
                )
            }
        };

        let data = match req.payload.get("data").and_then(|v| v.as_str()) {
            Some(d) => d,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'data' in terminal.input payload"),
                )
            }
        };

        match ctx.terminal_manager.write_input(session_id, &device_id, data) {
            Ok(()) => OrbitResponse::success(&req.id, &req.action, serde_json::json!({ "success": true })),
            Err(err) => OrbitResponse::error(&req.id, &req.action, err),
        }
    }

    pub fn handle_terminal_resize(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let device_id = match get_authenticated_device_id(ctx) {
            Ok(id) => id,
            Err(err) => return OrbitResponse::error(&req.id, &req.action, err),
        };

        let session_id = match req.payload.get("sessionId").and_then(|v| v.as_str()) {
            Some(id) => id,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'sessionId' in terminal.resize payload"),
                )
            }
        };

        let cols = match req.payload.get("cols").and_then(|v| v.as_u64()) {
            Some(c) => c as u16,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'cols' in terminal.resize payload"),
                )
            }
        };

        let rows = match req.payload.get("rows").and_then(|v| v.as_u64()) {
            Some(r) => r as u16,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'rows' in terminal.resize payload"),
                )
            }
        };

        match ctx.terminal_manager.resize(session_id, &device_id, cols, rows) {
            Ok(()) => OrbitResponse::success(&req.id, &req.action, serde_json::json!({ "success": true })),
            Err(err) => OrbitResponse::error(&req.id, &req.action, err),
        }
    }

    pub fn handle_terminal_kill(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let device_id = match get_authenticated_device_id(ctx) {
            Ok(id) => id,
            Err(err) => return OrbitResponse::error(&req.id, &req.action, err),
        };

        let session_id = match req.payload.get("sessionId").and_then(|v| v.as_str()) {
            Some(id) => id,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'sessionId' in terminal.kill payload"),
                )
            }
        };

        match ctx.terminal_manager.kill_session(session_id, &device_id) {
            Ok(()) => OrbitResponse::success(&req.id, &req.action, serde_json::json!({ "success": true })),
            Err(err) => OrbitResponse::error(&req.id, &req.action, err),
        }
    }

    pub fn handle_terminal_list(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let device_id = match get_authenticated_device_id(ctx) {
            Ok(id) => id,
            Err(err) => return OrbitResponse::error(&req.id, &req.action, err),
        };

        let sessions = ctx.terminal_manager.list_sessions(&device_id);
        OrbitResponse::success(
            &req.id,
            &req.action,
            serde_json::json!({
                "sessions": sessions,
            }),
        )
    }

    pub fn handle_terminal_history(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let device_id = match get_authenticated_device_id(ctx) {
            Ok(id) => id,
            Err(err) => return OrbitResponse::error(&req.id, &req.action, err),
        };

        let session_id = match req.payload.get("sessionId").and_then(|v| v.as_str()) {
            Some(id) => id,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'sessionId' in terminal.history payload"),
                )
            }
        };

        match ctx.terminal_manager.get_history(session_id, &device_id) {
            Ok(history) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::json!({
                    "sessionId": session_id,
                    "data": history,
                }),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, err),
        }
    }

    // ==========================================
    // Remote File Explorer Handlers
    // ==========================================

    pub fn handle_files_roots(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let roots = ctx.file_manager.roots();
        OrbitResponse::success(
            &req.id,
            &req.action,
            serde_json::json!({
                "roots": roots,
            }),
        )
    }

    pub fn handle_files_list(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = req.payload.get("path").and_then(|v| v.as_str()).unwrap_or("");
        match ctx.file_manager.list(path) {
            Ok(res) => OrbitResponse::success(&req.id, &req.action, serde_json::to_value(res).unwrap()),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_file_error(err)),
        }
    }

    pub fn handle_files_read(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in files.read payload"),
                )
            }
        };

        match ctx.file_manager.read(path) {
            Ok(res) => OrbitResponse::success(&req.id, &req.action, serde_json::to_value(res).unwrap()),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_file_error(err)),
        }
    }

    pub fn handle_files_read_binary(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in files.read_binary payload"),
                )
            }
        };

        let max_bytes = req.payload.get("maxBytes").and_then(|v| v.as_u64());

        match ctx.file_manager.read_binary(path, max_bytes) {
            Ok(res) => OrbitResponse::success(&req.id, &req.action, serde_json::to_value(res).unwrap()),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_file_error(err)),
        }
    }

    pub fn handle_files_write(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in files.write payload"),
                )
            }
        };

        let content = match req.payload.get("content").and_then(|v| v.as_str()) {
            Some(c) => c,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'content' in files.write payload"),
                )
            }
        };

        match ctx.file_manager.write(path, content) {
            Ok(res) => OrbitResponse::success(&req.id, &req.action, serde_json::to_value(res).unwrap()),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_file_error(err)),
        }
    }

    pub fn handle_files_mkdir(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in files.mkdir payload"),
                )
            }
        };

        match ctx.file_manager.mkdir(path) {
            Ok(created_path) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::json!({
                    "path": created_path,
                    "success": true,
                }),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_file_error(err)),
        }
    }

    pub fn handle_files_rename(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let from = match req.payload.get("from").and_then(|v| v.as_str()) {
            Some(f) if !f.trim().is_empty() => f,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'from' in files.rename payload"),
                )
            }
        };

        let to = match req.payload.get("to").and_then(|v| v.as_str()) {
            Some(t) if !t.trim().is_empty() => t,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'to' in files.rename payload"),
                )
            }
        };

        match ctx.file_manager.rename(from, to) {
            Ok(()) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::json!({
                    "from": from,
                    "to": to,
                    "success": true,
                }),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_file_error(err)),
        }
    }

    pub fn handle_files_delete(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in files.delete payload"),
                )
            }
        };

        match ctx.file_manager.delete(path) {
            Ok(deleted_path) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::json!({
                    "path": deleted_path,
                    "success": true,
                }),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_file_error(err)),
        }
    }

    pub fn handle_files_search(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let root = match req.payload.get("root").and_then(|v| v.as_str()) {
            Some(r) if !r.trim().is_empty() => r,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'root' in files.search payload"),
                );
            }
        };

        let query = req
            .payload
            .get("query")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let mode = req
            .payload
            .get("mode")
            .and_then(|v| v.as_str())
            .unwrap_or("name");

        let max_results = req
            .payload
            .get("maxResults")
            .and_then(|v| v.as_u64())
            .map(|n| n as usize);

        match ctx.file_manager.search(root, query, mode, max_results) {
            Ok(search_result) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::to_value(search_result).unwrap_or_default(),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_file_error(err)),
        }
    }

    // ==========================================
    // Projects & Git Handlers
    // ==========================================

    pub fn handle_projects_roots(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let roots = ctx.project_manager.roots();
        OrbitResponse::success(
            &req.id,
            &req.action,
            serde_json::json!({
                "roots": roots,
            }),
        )
    }

    pub fn handle_projects_list(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let root_path = req.payload.get("path").and_then(|v| v.as_str());
        match ctx.project_manager.list(root_path) {
            Ok(projects) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::json!({
                    "projects": projects,
                }),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_project_error(err)),
        }
    }

    pub fn handle_projects_info(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in projects.info payload"),
                )
            }
        };

        match ctx.project_manager.info(path) {
            Ok(info) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::to_value(info).unwrap(),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_project_error(err)),
        }
    }

    pub fn handle_git_status(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in git.status payload"),
                )
            }
        };

        match ctx.project_manager.git_status(path) {
            Ok(status) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::to_value(status).unwrap(),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_project_error(err)),
        }
    }

    pub fn handle_git_branches(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in git.branches payload"),
                )
            }
        };

        match ctx.project_manager.git_branches(path) {
            Ok(branches) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::to_value(branches).unwrap(),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_project_error(err)),
        }
    }

    pub fn handle_git_checkout(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in git.checkout payload"),
                )
            }
        };

        let branch = match req.payload.get("branch").and_then(|v| v.as_str()) {
            Some(b) if !b.trim().is_empty() => b,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'branch' in git.checkout payload"),
                )
            }
        };

        match ctx.project_manager.git_checkout(path, branch) {
            Ok(status) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::to_value(status).unwrap(),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_project_error(err)),
        }
    }

    pub fn handle_git_create_branch(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in git.create_branch payload"),
                )
            }
        };

        let name = match req.payload.get("name").and_then(|v| v.as_str()) {
            Some(n) if !n.trim().is_empty() => n,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'name' in git.create_branch payload"),
                )
            }
        };

        match ctx.project_manager.git_create_branch(path, name) {
            Ok(status) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::to_value(status).unwrap(),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_project_error(err)),
        }
    }

    pub fn handle_git_stage(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in git.stage payload"),
                )
            }
        };

        let paths_val = req.payload.get("paths").and_then(|v| v.as_array());
        let paths: Vec<String> = paths_val
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(|s| s.to_string()))
                    .collect()
            })
            .unwrap_or_default();

        match ctx.project_manager.git_stage(path, &paths) {
            Ok(status) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::to_value(status).unwrap(),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_project_error(err)),
        }
    }

    pub fn handle_git_unstage(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in git.unstage payload"),
                )
            }
        };

        let paths_val = req.payload.get("paths").and_then(|v| v.as_array());
        let paths: Vec<String> = paths_val
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(|s| s.to_string()))
                    .collect()
            })
            .unwrap_or_default();

        match ctx.project_manager.git_unstage(path, &paths) {
            Ok(status) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::to_value(status).unwrap(),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_project_error(err)),
        }
    }

    pub fn handle_git_commit(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in git.commit payload"),
                )
            }
        };

        let message = match req.payload.get("message").and_then(|v| v.as_str()) {
            Some(m) if !m.trim().is_empty() => m,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::commit_message_empty(),
                )
            }
        };

        match ctx.project_manager.git_commit(path, message) {
            Ok(res) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::to_value(res).unwrap(),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_project_error(err)),
        }
    }

    pub fn handle_git_log(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let path = match req.payload.get("path").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'path' in git.log payload"),
                )
            }
        };

        let limit = req.payload.get("limit").and_then(|v| v.as_u64()).unwrap_or(20) as usize;

        match ctx.project_manager.git_log(path, limit) {
            Ok(commits) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::json!({
                    "commits": commits,
                }),
            ),
            Err(err) => OrbitResponse::error(&req.id, &req.action, map_project_error(err)),
        }
    }

    pub async fn handle_ai_task_start(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let device_id = match get_authenticated_device_id(ctx) {
            Ok(d) => d,
            Err(e) => return OrbitResponse::error(&req.id, &req.action, e),
        };

        let project_path = req.payload.get("projectPath").and_then(|v| v.as_str()).unwrap_or("");

        let prompt = match req.payload.get("prompt").and_then(|v| v.as_str()) {
            Some(p) => p,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::ai_task_invalid_prompt("Missing 'prompt' parameter"),
                )
            }
        };

        let agent = req.payload.get("agent").and_then(|v| v.as_str());
        let read_only = req.payload.get("readOnly").and_then(|v| v.as_bool());
        let conversation_id = req.payload.get("conversationId").and_then(|v| v.as_str()).map(|s| s.to_string());
        let model = req.payload.get("model").or_else(|| req.payload.get("modelId")).and_then(|v| v.as_str()).map(|s| s.to_string());

        match ctx
            .ai_task_manager
            .start_task_extended(&device_id, project_path, prompt, agent, read_only, conversation_id, model)
            .await
        {
            Ok(summary) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::to_value(&summary).unwrap_or_default(),
            ),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub async fn handle_ai_task_resume(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let device_id = match get_authenticated_device_id(ctx) {
            Ok(d) => d,
            Err(e) => return OrbitResponse::error(&req.id, &req.action, e),
        };

        let session_id = match req.payload.get("openCodeSessionId").and_then(|v| v.as_str()) {
            Some(s) => s,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::ai_session_not_found("Missing 'openCodeSessionId' parameter"),
                )
            }
        };

        let project_path = req.payload.get("projectPath").and_then(|v| v.as_str()).unwrap_or("");

        let prompt = match req.payload.get("prompt").and_then(|v| v.as_str()) {
            Some(p) => p,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::ai_task_invalid_prompt("Missing 'prompt' parameter"),
                )
            }
        };

        let agent = req.payload.get("agent").and_then(|v| v.as_str());
        let read_only = req.payload.get("readOnly").and_then(|v| v.as_bool());
        let conversation_id = req.payload.get("conversationId").and_then(|v| v.as_str()).map(|s| s.to_string());
        let model = req.payload.get("model").or_else(|| req.payload.get("modelId")).and_then(|v| v.as_str()).map(|s| s.to_string());

        match ctx
            .ai_task_manager
            .resume_task_extended(&device_id, session_id, project_path, prompt, agent, read_only, conversation_id, model)
            .await
        {
            Ok(summary) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::to_value(&summary).unwrap_or_default(),
            ),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub async fn handle_ai_task_cancel(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let device_id = match get_authenticated_device_id(ctx) {
            Ok(d) => d,
            Err(e) => return OrbitResponse::error(&req.id, &req.action, e),
        };

        let task_id = match req.payload.get("taskId").and_then(|v| v.as_str()) {
            Some(t) => t,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::ai_task_not_found("Missing 'taskId' parameter"),
                )
            }
        };

        match ctx.ai_task_manager.cancel_task(task_id, &device_id).await {
            Ok(()) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::json!({
                    "taskId": task_id,
                    "status": "cancelled",
                }),
            ),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_ai_task_list(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let device_id = match get_authenticated_device_id(ctx) {
            Ok(d) => d,
            Err(e) => return OrbitResponse::error(&req.id, &req.action, e),
        };

        let summaries = ctx.ai_task_manager.list_tasks(&device_id);
        OrbitResponse::success(
            &req.id,
            &req.action,
            serde_json::json!({
                "tasks": summaries,
            }),
        )
    }

    pub async fn handle_ai_task_get(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let device_id = match get_authenticated_device_id(ctx) {
            Ok(d) => d,
            Err(e) => return OrbitResponse::error(&req.id, &req.action, e),
        };

        let task_id = match req.payload.get("taskId").and_then(|v| v.as_str()) {
            Some(t) => t,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::ai_task_not_found("Missing 'taskId' parameter"),
                )
            }
        };

        match ctx.ai_task_manager.get_task(task_id, &device_id).await {
            Ok(task) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::to_value(&task).unwrap_or_default(),
            ),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub async fn handle_ai_permission_resolve(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let device_id = match get_authenticated_device_id(ctx) {
            Ok(d) => d,
            Err(e) => return OrbitResponse::error(&req.id, &req.action, e),
        };

        let permission_id = match req.payload.get("permissionId").and_then(|v| v.as_str()) {
            Some(p) if !p.trim().is_empty() => p,
            _ => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'permissionId' parameter"),
                );
            }
        };

        let decision_str = match req.payload.get("decision").and_then(|v| v.as_str()) {
            Some(d) => d.to_lowercase(),
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message("Missing 'decision' parameter ('allow', 'always', or 'deny')"),
                );
            }
        };

        let decision = match decision_str.as_str() {
            "allow" | "once" | "approved" => crate::ai::permission::AiPermissionDecision::Allow,
            "always" => crate::ai::permission::AiPermissionDecision::Always,
            "deny" | "reject" | "denied" => crate::ai::permission::AiPermissionDecision::Deny,
            unknown => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::malformed_message(format!(
                        "Invalid decision '{}'. Expected 'allow', 'always', or 'deny'.",
                        unknown
                    )),
                );
            }
        };

        match ctx.ai_task_manager.resolve_permission(&device_id, permission_id, decision).await {
            Ok(resolved_req) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::to_value(resolved_req).unwrap_or_default(),
            ),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_ai_permission_list(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let device_id = match get_authenticated_device_id(ctx) {
            Ok(d) => d,
            Err(e) => return OrbitResponse::error(&req.id, &req.action, e),
        };

        let pending = ctx.ai_task_manager.list_pending_permissions(&device_id);
        OrbitResponse::success(
            &req.id,
            &req.action,
            serde_json::json!({
                "permissions": pending,
            }),
        )
    }

    pub fn handle_ai_conversation_create(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let title = req.payload.get("title").and_then(|v| v.as_str());
        let project_path = req.payload.get("projectPath").and_then(|v| v.as_str());
        let directory_path = req.payload.get("directoryPath").and_then(|v| v.as_str());
        let context_type = req.payload.get("contextType").and_then(|v| v.as_str());
        let provider_id = req.payload.get("providerId").and_then(|v| v.as_str());
        let model_id = req.payload.get("modelId").and_then(|v| v.as_str());

        match ctx.ai_task_manager.conversation_store().create_conversation(
            title,
            project_path,
            directory_path,
            context_type,
            provider_id,
            model_id,
        ) {
            Ok(summary) => OrbitResponse::success(&req.id, &req.action, serde_json::to_value(&summary).unwrap_or_default()),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_ai_conversation_list(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let limit = req.payload.get("limit").and_then(|v| v.as_u64()).unwrap_or(50) as usize;
        let offset = req.payload.get("offset").and_then(|v| v.as_u64()).unwrap_or(0) as usize;

        match ctx.ai_task_manager.conversation_store().list_conversations(limit, offset) {
            Ok(list) => OrbitResponse::success(&req.id, &req.action, serde_json::json!({ "conversations": list })),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_ai_conversation_get(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let conv_id = match req
            .payload
            .get("conversationId")
            .or_else(|| req.payload.get("id"))
            .or_else(|| req.payload.get("conversation_id"))
            .and_then(|v| v.as_str())
        {
            Some(id) => id,
            None => return OrbitResponse::error(&req.id, &req.action, ProtocolError::malformed_message("Missing 'conversationId'")),
        };

        match ctx.ai_task_manager.conversation_store().get_conversation(conv_id) {
            Ok(Some(detail)) => OrbitResponse::success(&req.id, &req.action, serde_json::to_value(&detail).unwrap_or_default()),
            Ok(None) => OrbitResponse::error(&req.id, &req.action, ProtocolError::internal_error("Conversation not found")),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_ai_conversation_rename(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let conv_id = match req
            .payload
            .get("conversationId")
            .or_else(|| req.payload.get("id"))
            .or_else(|| req.payload.get("conversation_id"))
            .and_then(|v| v.as_str())
        {
            Some(id) => id,
            None => return OrbitResponse::error(&req.id, &req.action, ProtocolError::malformed_message("Missing 'conversationId'")),
        };
        let title = match req.payload.get("title").and_then(|v| v.as_str()) {
            Some(t) => t,
            None => return OrbitResponse::error(&req.id, &req.action, ProtocolError::malformed_message("Missing 'title'")),
        };

        match ctx.ai_task_manager.conversation_store().update_title(conv_id, title) {
            Ok(()) => OrbitResponse::success(&req.id, &req.action, serde_json::json!({ "success": true })),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_ai_conversation_delete(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let conv_id = match req
            .payload
            .get("conversationId")
            .or_else(|| req.payload.get("id"))
            .or_else(|| req.payload.get("conversation_id"))
            .and_then(|v| v.as_str())
        {
            Some(id) => id,
            None => return OrbitResponse::error(&req.id, &req.action, ProtocolError::malformed_message("Missing 'conversationId'")),
        };

        let delete_session = req.payload.get("deleteSession").and_then(|v| v.as_bool()).unwrap_or(false);
        if delete_session {
            if let Ok(Some(detail)) = ctx.ai_task_manager.conversation_store().get_conversation(conv_id) {
                if let Some(ref sid) = detail.open_code_session_id {
                    if let Ok(bin) = crate::ai::process::find_opencode_binary() {
                        let _ = std::process::Command::new(bin)
                            .args(["session", "delete", sid])
                            .output();
                    }
                }
            }
        }

        match ctx.ai_task_manager.conversation_store().delete_conversation(conv_id) {
            Ok(()) => OrbitResponse::success(&req.id, &req.action, serde_json::json!({ "success": true })),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_ai_conversation_search(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let query = req.payload.get("query").and_then(|v| v.as_str()).unwrap_or("");
        let limit = req.payload.get("limit").and_then(|v| v.as_u64()).unwrap_or(20) as usize;

        match ctx.ai_task_manager.conversation_store().search_conversations(query, limit) {
            Ok(results) => OrbitResponse::success(&req.id, &req.action, serde_json::json!({ "results": results, "conversations": results })),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_ai_conversation_export(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let conv_id = match req
            .payload
            .get("conversationId")
            .or_else(|| req.payload.get("id"))
            .or_else(|| req.payload.get("conversation_id"))
            .and_then(|v| v.as_str())
        {
            Some(id) => id,
            None => return OrbitResponse::error(&req.id, &req.action, ProtocolError::malformed_message("Missing 'conversationId'")),
        };
        let format = req.payload.get("format").and_then(|v| v.as_str()).unwrap_or("markdown");

        let res = match format.to_lowercase().as_str() {
            "json" => ctx.ai_task_manager.conversation_store().export_json(conv_id),
            _ => ctx.ai_task_manager.conversation_store().export_markdown(conv_id),
        };

        match res {
            Ok(content) => OrbitResponse::success(&req.id, &req.action, serde_json::json!({ "content": content, "format": format })),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_ai_providers_list(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        match ctx.ai_task_manager.provider_manager().list_providers() {
            Ok(providers) => OrbitResponse::success(&req.id, &req.action, serde_json::json!({ "providers": providers })),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_ai_provider_get(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let provider_id = match req.payload.get("providerId").and_then(|v| v.as_str()) {
            Some(id) => id,
            None => return OrbitResponse::error(&req.id, &req.action, ProtocolError::malformed_message("Missing 'providerId'")),
        };

        match ctx.ai_task_manager.provider_manager().list_providers() {
            Ok(providers) => {
                if let Some(p) = providers.into_iter().find(|p| p.provider_id == provider_id) {
                    OrbitResponse::success(&req.id, &req.action, serde_json::to_value(&p).unwrap_or_default())
                } else {
                    OrbitResponse::error(&req.id, &req.action, ProtocolError::internal_error("Provider not found"))
                }
            }
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_ai_provider_auth_status(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        Self::handle_ai_provider_get(req, ctx)
    }

    pub fn handle_ai_provider_login(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let provider_id = match req.payload.get("providerId").and_then(|v| v.as_str()) {
            Some(id) => id,
            None => return OrbitResponse::error(&req.id, &req.action, ProtocolError::malformed_message("Missing 'providerId'")),
        };
        let api_key = match req.payload.get("apiKey").and_then(|v| v.as_str()) {
            Some(k) => k,
            None => return OrbitResponse::error(&req.id, &req.action, ProtocolError::malformed_message("Missing 'apiKey'")),
        };

        match ctx.ai_task_manager.provider_manager().set_provider_key(provider_id, api_key) {
            Ok(summary) => OrbitResponse::success(&req.id, &req.action, serde_json::to_value(&summary).unwrap_or_default()),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_ai_provider_logout(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let provider_id = match req.payload.get("providerId").and_then(|v| v.as_str()) {
            Some(id) => id,
            None => return OrbitResponse::error(&req.id, &req.action, ProtocolError::malformed_message("Missing 'providerId'")),
        };

        match ctx.ai_task_manager.provider_manager().logout_provider(provider_id) {
            Ok(()) => OrbitResponse::success(&req.id, &req.action, serde_json::json!({ "success": true })),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub async fn handle_ai_provider_test(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let provider_id = match req.payload.get("providerId").and_then(|v| v.as_str()) {
            Some(id) => id,
            None => return OrbitResponse::error(&req.id, &req.action, ProtocolError::malformed_message("Missing 'providerId'")),
        };

        match ctx.ai_task_manager.provider_manager().test_provider(provider_id).await {
            Ok(success) => OrbitResponse::success(&req.id, &req.action, serde_json::json!({ "success": success })),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub async fn handle_ai_models_list(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let provider_filter = req.payload.get("providerId").or_else(|| req.payload.get("provider")).and_then(|v| v.as_str());

        match ctx.ai_task_manager.provider_manager().list_models(provider_filter).await {
            Ok(models) => OrbitResponse::success(&req.id, &req.action, serde_json::json!({ "models": models })),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_ai_model_set_default(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let provider_id = match req.payload.get("providerId").and_then(|v| v.as_str()) {
            Some(id) => id,
            None => return OrbitResponse::error(&req.id, &req.action, ProtocolError::malformed_message("Missing 'providerId'")),
        };
        let model_id = match req.payload.get("modelId").and_then(|v| v.as_str()) {
            Some(id) => id,
            None => return OrbitResponse::error(&req.id, &req.action, ProtocolError::malformed_message("Missing 'modelId'")),
        };
        let agent = req.payload.get("agent").and_then(|v| v.as_str()).unwrap_or("plan");
        let context_behavior = req.payload.get("contextBehavior").or_else(|| req.payload.get("context")).and_then(|v| v.as_str()).unwrap_or("none");

        let defaults = crate::ai::storage::AiDefaults {
            provider_id: provider_id.to_string(),
            model_id: model_id.to_string(),
            agent: agent.to_string(),
            context_behavior: context_behavior.to_string(),
        };

        match ctx.ai_task_manager.conversation_store().set_defaults(&defaults) {
            Ok(()) => OrbitResponse::success(&req.id, &req.action, serde_json::to_value(&defaults).unwrap_or_default()),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub async fn handle_ai_usage_get(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let days = req.payload.get("days").and_then(|v| v.as_u64()).map(|d| d as u32);

        match ctx.ai_task_manager.provider_manager().get_usage_stats(days).await {
            Ok(stats) => OrbitResponse::success(&req.id, &req.action, serde_json::to_value(&stats).unwrap_or_default()),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_scripts_list(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let project_path = req.payload.get("projectPath").and_then(|v| v.as_str());
        match ctx.script_manager.list(project_path) {
            Ok(scripts) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::json!({ "scripts": scripts }),
            ),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_scripts_get(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let id = match req.payload.get("id").and_then(|v| v.as_str()) {
            Some(id) => id,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::invalid_params("Missing 'id' parameter"),
                )
            }
        };
        match ctx.script_manager.get(id) {
            Ok(Some(script)) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::json!({ "script": script }),
            ),
            Ok(None) => OrbitResponse::error(
                &req.id,
                &req.action,
                ProtocolError::not_found("Script not found"),
            ),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_scripts_save(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let script_val = match req.payload.get("script") {
            Some(v) => v,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::invalid_params("Missing 'script' parameter"),
                )
            }
        };
        let input: crate::scripts::ScriptInput = match serde_json::from_value(script_val.clone()) {
            Ok(inp) => inp,
            Err(e) => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::invalid_params(format!("Invalid script data: {}", e)),
                )
            }
        };
        match ctx.script_manager.save(input) {
            Ok(script) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::json!({ "script": script }),
            ),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }

    pub fn handle_scripts_delete(req: &OrbitRequest, ctx: &ActionContext) -> OrbitResponse {
        let id = match req.payload.get("id").and_then(|v| v.as_str()) {
            Some(id) => id,
            None => {
                return OrbitResponse::error(
                    &req.id,
                    &req.action,
                    ProtocolError::invalid_params("Missing 'id' parameter"),
                )
            }
        };
        match ctx.script_manager.delete(id) {
            Ok(deleted) => OrbitResponse::success(
                &req.id,
                &req.action,
                serde_json::json!({ "deleted": deleted }),
            ),
            Err(e) => OrbitResponse::error(&req.id, &req.action, e),
        }
    }
}

fn map_file_error(err: FileError) -> ProtocolError {
    match err {
        FileError::NotFound(p) => ProtocolError::path_not_found(p),
        FileError::PermissionDenied(m) => ProtocolError::permission_denied(m),
        FileError::InvalidPath(m) => ProtocolError::invalid_path(m),
        FileError::FileTooLarge(size) => {
            ProtocolError::file_too_large(size, crate::files::operations::DEFAULT_MAX_READ_BYTES)
        }
        FileError::UnsupportedFileType => ProtocolError::unsupported_file_type(
            "Only UTF-8 encoded text files are supported for remote editing.",
        ),
        FileError::AlreadyExists(p) => ProtocolError::already_exists(p),
        FileError::DirectoryNotEmpty(m) => ProtocolError::operation_failed(m),
        FileError::Io(m) => ProtocolError::operation_failed(m),
    }
}

fn map_project_error(err: ProjectError) -> ProtocolError {
    match err {
        ProjectError::ProjectNotFound(p) => ProtocolError::project_not_found(p),
        ProjectError::ProjectNotAllowed(p) => ProtocolError::project_not_allowed(p),
        ProjectError::NotAGitRepository(p) => ProtocolError::not_a_git_repository(p),
        ProjectError::Git(git_err) => match git_err {
            GitError::NotAGitRepository(p) => ProtocolError::not_a_git_repository(p),
            GitError::GitNotInstalled => ProtocolError::git_not_installed(),
            GitError::GitOperationFailed(m) => ProtocolError::git_operation_failed(m),
            GitError::InvalidBranchName(b) => ProtocolError::invalid_branch_name(b),
            GitError::InvalidFilePath(p) => ProtocolError::invalid_file_path(p),
            GitError::CommitMessageEmpty => ProtocolError::commit_message_empty(),
            GitError::CheckoutConflict(m) => ProtocolError::checkout_conflict(m),
        },
    }
}
