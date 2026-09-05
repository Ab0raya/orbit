use crate::agent::handlers::{ActionContext, ActionHandlers};
use crate::protocol::errors::ProtocolError;
use crate::protocol::events::OrbitEvent;
use crate::protocol::request::OrbitRequest;
use crate::protocol::response::OrbitResponse;

pub const MAX_MESSAGE_SIZE_BYTES: usize = 65_536; // 64 KB

pub struct MessageRouter;

impl MessageRouter {
    pub async fn route(
        raw_message: &str,
        ctx: &ActionContext,
    ) -> (OrbitResponse, Option<OrbitEvent>) {
        // 1. Enforce message size limit
        if raw_message.len() > MAX_MESSAGE_SIZE_BYTES {
            eprintln!(
                "[Orbit Protocol] Message from connection '{}' rejected: size {} exceeds limit",
                ctx.connection_id,
                raw_message.len()
            );
            return (
                OrbitResponse::error(
                    "unknown",
                    "unknown",
                    ProtocolError::message_too_large(raw_message.len(), MAX_MESSAGE_SIZE_BYTES),
                ),
                None,
            );
        }

        // 2. Parse into generic JSON Value first to salvage 'id' if malformed
        let json_val: serde_json::Value = match serde_json::from_str(raw_message) {
            Ok(v) => v,
            Err(e) => {
                eprintln!(
                    "[Orbit Protocol] Malformed JSON from connection '{}': {}",
                    ctx.connection_id, e
                );
                return (
                    OrbitResponse::error(
                        "unknown",
                        "unknown",
                        ProtocolError::malformed_message(format!("Invalid JSON: {}", e)),
                    ),
                    None,
                );
            }
        };

        let req_id = json_val
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();

        let msg_type = json_val
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        if msg_type != "request" {
            eprintln!(
                "[Orbit Protocol] Unsupported message type '{}' from connection '{}'",
                msg_type, ctx.connection_id
            );
            return (
                OrbitResponse::error(
                    &req_id,
                    "unknown",
                    ProtocolError::malformed_message("Expected message with 'type': 'request'"),
                ),
                None,
            );
        }

        // 3. Deserialize into OrbitRequest
        let request: OrbitRequest = match serde_json::from_value(json_val) {
            Ok(r) => r,
            Err(e) => {
                return (
                    OrbitResponse::error(
                        &req_id,
                        "unknown",
                        ProtocolError::malformed_message(format!(
                            "Invalid request envelope: {}",
                            e
                        )),
                    ),
                    None,
                );
            }
        };

        // 4. Check Authorization
        let is_paired = ctx.session_manager.is_session_paired(&ctx.connection_id);
        let action = request.action.as_str();

        let requires_pairing = !matches!(action, "ping" | "pairing.verify" | "session.resume");

        if requires_pairing && !is_paired {
            println!(
                "[Orbit Security] Unauthorized attempt on action '{}' from unpaired connection '{}'",
                action, ctx.connection_id
            );
            return (
                OrbitResponse::error(
                    &request.id,
                    &request.action,
                    ProtocolError::unauthorized(
                        "Device must be paired to access this resource.",
                    ),
                ),
                None,
            );
        }

        // 5. Route to appropriate action handler
        match action {
            "ping" => (ActionHandlers::handle_ping(&request), None),
            "pairing.verify" => ActionHandlers::handle_pairing_verify(&request, ctx),
            "session.resume" => ActionHandlers::handle_session_resume(&request, ctx),
            "system.info" => (ActionHandlers::handle_system_info(&request, ctx), None),
            "tailscale.info" => (ActionHandlers::handle_tailscale_info(&request, ctx), None),
            "agent.status" => (ActionHandlers::handle_agent_status(&request, ctx), None),
            "server.info" => (ActionHandlers::handle_server_info(&request, ctx), None),
            "devices.list" => (ActionHandlers::handle_devices_list(&request, ctx), None),
            "terminal.create" => ActionHandlers::handle_terminal_create(&request, ctx),
            "terminal.input" => (ActionHandlers::handle_terminal_input(&request, ctx), None),
            "terminal.resize" => (ActionHandlers::handle_terminal_resize(&request, ctx), None),
            "terminal.kill" => (ActionHandlers::handle_terminal_kill(&request, ctx), None),
            "terminal.list" => (ActionHandlers::handle_terminal_list(&request, ctx), None),
            "terminal.history" => (ActionHandlers::handle_terminal_history(&request, ctx), None),
            "files.roots" => (ActionHandlers::handle_files_roots(&request, ctx), None),
            "files.list" => (ActionHandlers::handle_files_list(&request, ctx), None),
            "files.read" => (ActionHandlers::handle_files_read(&request, ctx), None),
            "files.read_binary" => (ActionHandlers::handle_files_read_binary(&request, ctx), None),
            "files.write" => (ActionHandlers::handle_files_write(&request, ctx), None),
            "files.mkdir" => (ActionHandlers::handle_files_mkdir(&request, ctx), None),
            "files.rename" => (ActionHandlers::handle_files_rename(&request, ctx), None),
            "files.delete" => (ActionHandlers::handle_files_delete(&request, ctx), None),
            "files.search" | "search.files" => (ActionHandlers::handle_files_search(&request, ctx), None),
            "projects.roots" => (ActionHandlers::handle_projects_roots(&request, ctx), None),
            "projects.list" => (ActionHandlers::handle_projects_list(&request, ctx), None),
            "projects.info" => (ActionHandlers::handle_projects_info(&request, ctx), None),
            "git.status" => (ActionHandlers::handle_git_status(&request, ctx), None),
            "git.branches" => (ActionHandlers::handle_git_branches(&request, ctx), None),
            "git.checkout" => (ActionHandlers::handle_git_checkout(&request, ctx), None),
            "git.create_branch" => (ActionHandlers::handle_git_create_branch(&request, ctx), None),
            "git.stage" => (ActionHandlers::handle_git_stage(&request, ctx), None),
            "git.unstage" => (ActionHandlers::handle_git_unstage(&request, ctx), None),
            "git.commit" => (ActionHandlers::handle_git_commit(&request, ctx), None),
            "git.log" => (ActionHandlers::handle_git_log(&request, ctx), None),
            "ai.task.start" => (ActionHandlers::handle_ai_task_start(&request, ctx).await, None),
            "ai.task.resume" => (ActionHandlers::handle_ai_task_resume(&request, ctx).await, None),
            "ai.task.cancel" => (ActionHandlers::handle_ai_task_cancel(&request, ctx).await, None),
            "ai.task.list" => (ActionHandlers::handle_ai_task_list(&request, ctx), None),
            "ai.task.get" => (ActionHandlers::handle_ai_task_get(&request, ctx).await, None),
            "ai.permission.resolve" => (ActionHandlers::handle_ai_permission_resolve(&request, ctx).await, None),
            "ai.permission.list" => (ActionHandlers::handle_ai_permission_list(&request, ctx), None),
            "ai.conversation.create" => (ActionHandlers::handle_ai_conversation_create(&request, ctx), None),
            "ai.conversation.list" => (ActionHandlers::handle_ai_conversation_list(&request, ctx), None),
            "ai.conversation.get" => (ActionHandlers::handle_ai_conversation_get(&request, ctx), None),
            "ai.conversation.rename" => (ActionHandlers::handle_ai_conversation_rename(&request, ctx), None),
            "ai.conversation.delete" => (ActionHandlers::handle_ai_conversation_delete(&request, ctx), None),
            "ai.conversation.search" => (ActionHandlers::handle_ai_conversation_search(&request, ctx), None),
            "ai.conversation.export" => (ActionHandlers::handle_ai_conversation_export(&request, ctx), None),
            "ai.providers.list" => (ActionHandlers::handle_ai_providers_list(&request, ctx), None),
            "ai.provider.get" => (ActionHandlers::handle_ai_provider_get(&request, ctx), None),
            "ai.provider.auth_status" => (ActionHandlers::handle_ai_provider_auth_status(&request, ctx), None),
            "ai.provider.login" => (ActionHandlers::handle_ai_provider_login(&request, ctx), None),
            "ai.provider.logout" => (ActionHandlers::handle_ai_provider_logout(&request, ctx), None),
            "ai.provider.test" => (ActionHandlers::handle_ai_provider_test(&request, ctx).await, None),
            "ai.models.list" => (ActionHandlers::handle_ai_models_list(&request, ctx).await, None),
            "ai.model.set_default" => (ActionHandlers::handle_ai_model_set_default(&request, ctx), None),
            "ai.usage.get" => (ActionHandlers::handle_ai_usage_get(&request, ctx).await, None),
            "scripts.list" => (ActionHandlers::handle_scripts_list(&request, ctx), None),
            "scripts.get" => (ActionHandlers::handle_scripts_get(&request, ctx), None),
            "scripts.save" | "scripts.create" => (ActionHandlers::handle_scripts_save(&request, ctx), None),
            "scripts.delete" => (ActionHandlers::handle_scripts_delete(&request, ctx), None),
            unknown => {
                println!(
                    "[Orbit Protocol] Unknown action '{}' requested on connection '{}'",
                    unknown, ctx.connection_id
                );
                (
                    OrbitResponse::error(
                        &request.id,
                        &request.action,
                        ProtocolError::unknown_action(unknown),
                    ),
                    None,
                )
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{IpAddr, Ipv4Addr, SocketAddr};
    use std::sync::{Arc, RwLock};
    use crate::agent::pairing::PairingManager;
    use crate::agent::session::SessionManager;
    use crate::agent::system::SystemManager;
    use crate::ai::AiTaskManager;
    use crate::files::FileManager;
    use crate::projects::ProjectManager;
    use crate::terminal::TerminalManager;

    fn test_context(is_paired: bool) -> (ActionContext, String) {
        let pairing_mgr = Arc::new(RwLock::new(PairingManager::new()));
        let session_mgr = Arc::new(SessionManager::new());
        let system_mgr = Arc::new(SystemManager::new());
        let terminal_mgr = Arc::new(TerminalManager::new());
        let file_mgr = Arc::new(FileManager::new());
        let proj_mgr = Arc::new(ProjectManager::new());
        let ai_task_mgr = Arc::new(AiTaskManager::new(Arc::clone(&proj_mgr)));
        let script_mgr = Arc::new(crate::scripts::ScriptManager::new_in_memory().unwrap());

        let addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 12345);
        let conn_id = session_mgr.create_session(addr);

        if is_paired {
            session_mgr
                .mark_paired(&conn_id, "Test Phone", "android", None)
                .unwrap();
        }

        let ctx = ActionContext {
            connection_id: conn_id.clone(),
            pairing_manager: pairing_mgr,
            session_manager: session_mgr,
            system_manager: system_mgr,
            terminal_manager: terminal_mgr,
            file_manager: file_mgr,
            project_manager: proj_mgr,
            ai_task_manager: ai_task_mgr,
            script_manager: script_mgr,
            uptime_seconds: 100,
            server_port: 4371,
            bind_address: "0.0.0.0".to_string(),
        };

        (ctx, conn_id)
    }

    #[tokio::test]
    async fn test_route_ping() {
        let (ctx, _) = test_context(false);
        let req = r#"{"id":"req_1","type":"request","action":"ping","payload":{}}"#;
        let (res, event) = MessageRouter::route(req, &ctx).await;

        assert_eq!(res.id, "req_1");
        assert_eq!(res.action, "ping");
        assert!(res.success);
        assert!(event.is_none());
        assert!(res.payload.unwrap().get("timestamp").is_some());
    }

    #[tokio::test]
    async fn test_route_unpaired_rejected_for_system_info() {
        let (ctx, _) = test_context(false);
        let req = r#"{"id":"req_2","type":"request","action":"system.info","payload":{}}"#;
        let (res, _) = MessageRouter::route(req, &ctx).await;

        assert_eq!(res.id, "req_2");
        assert!(!res.success);
        assert_eq!(res.error.unwrap().code, "UNAUTHORIZED");
    }

    #[tokio::test]
    async fn test_route_unpaired_rejected_for_ai_task_start() {
        let (ctx, _) = test_context(false);
        let req = r#"{"id":"req_ai_1","type":"request","action":"ai.task.start","payload":{"projectPath":"/tmp","prompt":"hello"}}"#;
        let (res, _) = MessageRouter::route(req, &ctx).await;

        assert_eq!(res.id, "req_ai_1");
        assert!(!res.success);
        assert_eq!(res.error.unwrap().code, "UNAUTHORIZED");
    }

    #[tokio::test]
    async fn test_route_paired_accepted_for_system_info() {
        let (ctx, _) = test_context(true);
        let req = r#"{"id":"req_3","type":"request","action":"system.info","payload":{}}"#;
        let (res, _) = MessageRouter::route(req, &ctx).await;

        assert_eq!(res.id, "req_3");
        assert!(res.success);
        let payload = res.payload.unwrap();
        assert!(payload.get("hostname").is_some());
        assert!(payload.get("os").is_some());
    }

    #[tokio::test]
    async fn test_route_unknown_action() {
        let (ctx, _) = test_context(true);
        let req = r#"{"id":"req_4","type":"request","action":"invalid.action","payload":{}}"#;
        let (res, _) = MessageRouter::route(req, &ctx).await;

        assert!(!res.success);
        assert_eq!(res.error.unwrap().code, "UNKNOWN_ACTION");
    }

    #[tokio::test]
    async fn test_route_malformed_json() {
        let (ctx, _) = test_context(false);
        let (res, _) = MessageRouter::route("not-json", &ctx).await;

        assert!(!res.success);
        assert_eq!(res.error.unwrap().code, "MALFORMED_MESSAGE");
    }

    #[tokio::test]
    async fn test_route_oversized_message() {
        let (ctx, _) = test_context(false);
        let huge = "a".repeat(MAX_MESSAGE_SIZE_BYTES + 10);
        let (res, _) = MessageRouter::route(&huge, &ctx).await;

        assert!(!res.success);
        assert_eq!(res.error.unwrap().code, "MESSAGE_TOO_LARGE");
    }

    #[tokio::test]
    async fn test_pairing_verify_flow() {
        let (ctx, _) = test_context(false);
        let valid_code = ctx.pairing_manager.read().unwrap().get_info().code;

        // Invalid code
        let invalid_req = r#"{"id":"p1","type":"request","action":"pairing.verify","payload":{"code":"000000"}}"#;
        let (res, _) = MessageRouter::route(invalid_req, &ctx).await;
        assert!(!res.success);
        assert_eq!(res.error.unwrap().code, "INVALID_PAIRING_CODE");

        // Valid code
        let valid_req = format!(
            r#"{{"id":"p2","type":"request","action":"pairing.verify","payload":{{"code":"{}","name":"Pixel 8","platform":"android"}}}}"#,
            valid_code
        );
        let (res, event) = MessageRouter::route(&valid_req, &ctx).await;
        assert!(res.success);
        let res_payload = res.payload.unwrap();
        assert_eq!(res_payload["paired"], true);
        assert!(res_payload["deviceId"].is_string());

        let event = event.expect("Expected device.paired event");
        assert_eq!(event.event, "device.paired");
        assert_eq!(event.payload["name"], "Pixel 8");

        // Now session should be paired
        let sys_req = r#"{"id":"p3","type":"request","action":"agent.status","payload":{}}"#;
        let (res, _) = MessageRouter::route(sys_req, &ctx).await;
        assert!(res.success);
    }

    #[tokio::test]
    async fn test_expired_pairing() {
        use std::time::Duration;
        let pairing_mgr = Arc::new(RwLock::new(PairingManager::new_with_ttl(Duration::from_millis(5))));
        let code = pairing_mgr.read().unwrap().get_info().code;

        tokio::time::sleep(Duration::from_millis(15)).await; // Guarantee expiration

        let session_mgr = Arc::new(SessionManager::new());
        let system_mgr = Arc::new(SystemManager::new());
        let proj_mgr = Arc::new(ProjectManager::new());
        let ai_task_mgr = Arc::new(AiTaskManager::new(Arc::clone(&proj_mgr)));
        let addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 54321);
        let conn_id = session_mgr.create_session(addr);

        let ctx = ActionContext {
            connection_id: conn_id,
            pairing_manager: pairing_mgr,
            session_manager: session_mgr,
            system_manager: system_mgr,
            terminal_manager: Arc::new(TerminalManager::new()),
            file_manager: Arc::new(FileManager::new()),
            project_manager: proj_mgr,
            ai_task_manager: ai_task_mgr,
            script_manager: Arc::new(crate::scripts::ScriptManager::new_in_memory().unwrap()),
            uptime_seconds: 100,
            server_port: 4371,
            bind_address: "0.0.0.0".to_string(),
        };

        let req = format!(
            r#"{{"id":"p_exp","type":"request","action":"pairing.verify","payload":{{"code":"{}"}}}}"#,
            code
        );
        let (res, _) = MessageRouter::route(&req, &ctx).await;
        assert!(!res.success);
        assert_eq!(res.error.unwrap().code, "INVALID_PAIRING_CODE");
    }

    #[tokio::test]
    async fn test_route_tailscale_info_paired() {
        std::env::set_var("ORBIT_TAILSCALE_MOCK_STATE", "connected");
        std::env::set_var("ORBIT_TAILSCALE_MOCK_IP", "100.99.88.77");

        let pairing_mgr = Arc::new(RwLock::new(PairingManager::new()));
        let session_mgr = Arc::new(SessionManager::new());
        let system_mgr = Arc::new(SystemManager::new());
        let proj_mgr = Arc::new(ProjectManager::new());
        let ai_task_mgr = Arc::new(AiTaskManager::new(Arc::clone(&proj_mgr)));
        let addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 54321);
        let conn_id = session_mgr.create_session(addr);
        let _ = session_mgr.mark_paired(&conn_id, "test_ts_device", "mobile", None);

        let ctx = ActionContext {
            connection_id: conn_id,
            pairing_manager: pairing_mgr,
            session_manager: session_mgr,
            system_manager: system_mgr,
            terminal_manager: Arc::new(TerminalManager::new()),
            file_manager: Arc::new(FileManager::new()),
            project_manager: proj_mgr,
            ai_task_manager: ai_task_mgr,
            script_manager: Arc::new(crate::scripts::ScriptManager::new_in_memory().unwrap()),
            uptime_seconds: 100,
            server_port: 4371,
            bind_address: "0.0.0.0".to_string(),
        };

        // Test tailscale.info
        let req = r#"{"id":"req_ts","type":"request","action":"tailscale.info","payload":{}}"#;
        let (res, _) = MessageRouter::route(req, &ctx).await;
        assert!(res.success);
        let payload = res.payload.unwrap();
        assert_eq!(payload["state"], "connected");
        assert_eq!(payload["ip"], "100.99.88.77");
        assert_eq!(payload["installed"], true);

        // Test system.info includes tailscale
        let req_sys = r#"{"id":"req_sys","type":"request","action":"system.info","payload":{}}"#;
        let (res_sys, _) = MessageRouter::route(req_sys, &ctx).await;
        assert!(res_sys.success);
        let sys_payload = res_sys.payload.unwrap();
        assert_eq!(sys_payload["tailscale"]["state"], "connected");
        assert_eq!(sys_payload["tailscale"]["ip"], "100.99.88.77");

        std::env::remove_var("ORBIT_TAILSCALE_MOCK_STATE");
        std::env::remove_var("ORBIT_TAILSCALE_MOCK_IP");
    }

    #[tokio::test]
    async fn test_route_scripts_crud() {
        let (ctx, _) = test_context(true);

        // 1. Save script
        let save_req = r#"{
            "id": "s1",
            "type": "request",
            "action": "scripts.save",
            "payload": {
                "script": {
                    "name": "Test Script",
                    "description": "A test command",
                    "content": "echo Hello Orbit",
                    "workingDirectory": null,
                    "projectPath": null
                }
            }
        }"#;

        let (save_res, _) = MessageRouter::route(save_req, &ctx).await;
        assert!(save_res.success);
        let saved_script = save_res.payload.unwrap()["script"].clone();
        let script_id = saved_script["id"].as_str().unwrap().to_string();
        assert_eq!(saved_script["name"], "Test Script");

        // 2. List scripts
        let list_req = r#"{"id": "s2", "type": "request", "action": "scripts.list", "payload": {}}"#;
        let (list_res, _) = MessageRouter::route(list_req, &ctx).await;
        assert!(list_res.success);
        let scripts = list_res.payload.unwrap()["scripts"].as_array().unwrap().clone();
        assert_eq!(scripts.len(), 1);

        // 3. Get script
        let get_req = format!(
            r#"{{"id": "s3", "type": "request", "action": "scripts.get", "payload": {{"id": "{}"}}}}"#,
            script_id
        );
        let (get_res, _) = MessageRouter::route(&get_req, &ctx).await;
        assert!(get_res.success);
        assert_eq!(get_res.payload.unwrap()["script"]["name"], "Test Script");

        // 4. Delete script
        let del_req = format!(
            r#"{{"id": "s4", "type": "request", "action": "scripts.delete", "payload": {{"id": "{}"}}}}"#,
            script_id
        );
        let (del_res, _) = MessageRouter::route(&del_req, &ctx).await;
        assert!(del_res.success);
        assert_eq!(del_res.payload.unwrap()["deleted"], true);
    }
}

