pub mod agent;
pub mod ai;
pub mod commands;
pub mod files;
pub mod opencode_manager;
pub mod projects;
pub mod protocol;
pub mod scripts;
pub mod terminal;

use std::sync::Arc;
use tauri::{Emitter, Manager};

use crate::agent::OrbitAgent;
use crate::commands::AppState;
use crate::opencode_manager::OpencodeManager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let agent = Arc::new(OrbitAgent::new(None));
    let agent_setup = Arc::clone(&agent);
    let agent_shutdown = Arc::clone(&agent);

    tauri::Builder::default()
        .setup(move |app| {
            // Determine the platform-native app data directory for Orbit
            let app_data_dir = app
                .path()
                .app_data_dir()
                .unwrap_or_else(|_| {
                    // Fallback: use temp dir during development
                    std::env::temp_dir().join("orbit-data")
                });

            // Create the OpenCode manager with the platform data dir
            let opencode_manager = Arc::new(OpencodeManager::new(app_data_dir.clone()));

            app.manage(AppState {
                agent: Arc::clone(&agent_setup),
                opencode_manager: Arc::clone(&opencode_manager),
            });

            // Start agent in background async runtime with retry loop
            let agent_bg = Arc::clone(&agent_setup);
            tauri::async_runtime::spawn(async move {
                let mut retry_count = 0;
                loop {
                    match agent_bg.start().await {
                        Ok(()) => {
                            println!("[Orbit Agent] Agent started successfully on port 4371");
                            break;
                        }
                        Err(e) => {
                            retry_count += 1;
                            if retry_count <= 10 {
                                eprintln!(
                                    "[Orbit Agent] Failed to start on port 4371: {}. Retrying in 2 seconds (attempt {})...",
                                    e, retry_count
                                );
                            }
                            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                        }
                    }
                }
            });

            // Ensure OpenCode is installed in the background (non-blocking)
            let oc_manager = Arc::clone(&opencode_manager);
            tauri::async_runtime::spawn(async move {
                oc_manager.ensure_ready().await;
            });

            // Forward terminal output events to Tauri webview
            let term_rx = agent_setup.terminal_manager().subscribe_events();
            let app_handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                let mut term_rx = term_rx;
                while let Ok(event) = term_rx.recv().await {
                    match event {
                        crate::terminal::manager::TerminalBroadcastEvent::Output {
                            session_id,
                            data,
                            ..
                        } => {
                            let _ = app_handle.emit(
                                "terminal-output",
                                serde_json::json!({
                                    "sessionId": session_id,
                                    "data": data,
                                }),
                            );
                        }
                        crate::terminal::manager::TerminalBroadcastEvent::Exited {
                            session_id,
                            exit_code,
                            ..
                        } => {
                            let _ = app_handle.emit(
                                "terminal-exited",
                                serde_json::json!({
                                    "sessionId": session_id,
                                    "exitCode": exit_code,
                                }),
                            );
                        }
                        _ => {}
                    }
                }
            });

            // Forward AI permission events to Tauri webview
            let ai_rx = agent_setup.ai_task_manager().subscribe_events();
            let app_handle_ai = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                let mut ai_rx = ai_rx;
                while let Ok(event) = ai_rx.recv().await {
                    match event {
                        crate::ai::models::AiBroadcastEvent::PermissionRequested {
                            task_id,
                            device_id,
                            open_code_session_id,
                            permission_id,
                            tool,
                            action,
                            target,
                            patterns,
                            project_path,
                            risk,
                            created_at,
                            timeout_at,
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-permission-requested",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "deviceId": device_id,
                                    "sessionId": open_code_session_id,
                                    "permissionId": permission_id,
                                    "tool": tool,
                                    "action": action,
                                    "target": target,
                                    "patterns": patterns,
                                    "projectPath": project_path,
                                    "risk": risk,
                                    "createdAt": created_at,
                                    "timeoutAt": timeout_at,
                                }),
                            );
                        }
                        crate::ai::models::AiBroadcastEvent::PermissionResolved {
                            task_id,
                            device_id,
                            open_code_session_id,
                            permission_id,
                            decision,
                            reply,
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-permission-resolved",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "deviceId": device_id,
                                    "sessionId": open_code_session_id,
                                    "permissionId": permission_id,
                                    "decision": decision,
                                    "reply": reply,
                                }),
                            );
                        }
                        crate::ai::models::AiBroadcastEvent::Activity {
                            task_id,
                            open_code_session_id,
                            activity,
                            ..
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-activity",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "sessionId": open_code_session_id,
                                    "activity": activity,
                                }),
                            );
                        }
                        crate::ai::models::AiBroadcastEvent::ResponseChunk {
                            task_id,
                            open_code_session_id,
                            text,
                            ..
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-response-chunk",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "sessionId": open_code_session_id,
                                    "text": text,
                                }),
                            );
                        }
                        crate::ai::models::AiBroadcastEvent::Completed {
                            task_id,
                            open_code_session_id,
                            duration_ms,
                            ..
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-completed",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "sessionId": open_code_session_id,
                                    "durationMs": duration_ms,
                                }),
                            );
                        }
                        crate::ai::models::AiBroadcastEvent::Failed {
                            task_id,
                            open_code_session_id,
                            error,
                            ..
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-failed",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "sessionId": open_code_session_id,
                                    "error": error,
                                }),
                            );
                        }
                        crate::ai::models::AiBroadcastEvent::Cancelled {
                            task_id,
                            open_code_session_id,
                            ..
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-cancelled",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "sessionId": open_code_session_id,
                                }),
                            );
                        }
                        _ => {}
                    }
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_agent_status,
            commands::get_system_info,
            commands::get_tailscale_info,
            commands::refresh_tailscale_info,
            commands::open_tailscale,
            commands::get_pairing_code,
            commands::regenerate_pairing_code,
            commands::get_server_info,
            commands::get_paired_devices,
            commands::create_terminal,
            commands::list_terminals,
            commands::kill_terminal,
            commands::get_terminal_history,
            commands::write_terminal_input,
            commands::resize_terminal,
            commands::get_file_roots,
            commands::list_directory,
            commands::read_file,
            commands::search_files,
            commands::list_pending_ai_permissions,
            commands::resolve_ai_permission,
            commands::list_ai_conversations,
            commands::get_ai_conversation,
            commands::create_ai_conversation,
            commands::rename_ai_conversation,
            commands::delete_ai_conversation,
            commands::search_ai_conversations,
            commands::export_ai_conversation,
            commands::start_ai_task,
            commands::resume_ai_task,
            commands::cancel_ai_task,
            commands::list_ai_providers,
            commands::set_ai_provider_key,
            commands::logout_ai_provider,
            commands::test_ai_provider,
            commands::list_ai_models,
            commands::get_ai_defaults,
            commands::set_ai_defaults,
            commands::get_ai_usage,
            commands::list_scripts,
            commands::get_script,
            commands::save_script,
            commands::delete_script,
            // OpenCode lifecycle management
            commands::get_opencode_status,
            commands::install_opencode,
            commands::update_opencode,
        ])
        .build(tauri::generate_context!())
        .expect("error while running tauri application")
        .run(move |_app_handle, event| {
            if let tauri::RunEvent::ExitRequested { .. } = event {
                println!("[Orbit Agent] Shutting down agent services...");
                agent_shutdown.stop();
            }
        });
}


#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let agent = Arc::new(OrbitAgent::new(None));
    let agent_setup = Arc::clone(&agent);
    let agent_shutdown = Arc::clone(&agent);

    tauri::Builder::default()
        .setup(move |app| {
            app.manage(AppState {
                agent: Arc::clone(&agent_setup),
            });

            // Start agent in background async runtime with retry loop
            let agent_bg = Arc::clone(&agent_setup);
            tauri::async_runtime::spawn(async move {
                let mut retry_count = 0;
                loop {
                    match agent_bg.start().await {
                        Ok(()) => {
                            println!("[Orbit Agent] Agent started successfully on port 4371");
                            break;
                        }
                        Err(e) => {
                            retry_count += 1;
                            if retry_count <= 10 {
                                eprintln!(
                                    "[Orbit Agent] Failed to start on port 4371: {}. Retrying in 2 seconds (attempt {})...",
                                    e, retry_count
                                );
                            }
                            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                        }
                    }
                }
            });

            // Forward terminal output events to Tauri webview
            let term_rx = agent_setup.terminal_manager().subscribe_events();
            let app_handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                let mut term_rx = term_rx;
                while let Ok(event) = term_rx.recv().await {
                    match event {
                        crate::terminal::manager::TerminalBroadcastEvent::Output {
                            session_id,
                            data,
                            ..
                        } => {
                            let _ = app_handle.emit(
                                "terminal-output",
                                serde_json::json!({
                                    "sessionId": session_id,
                                    "data": data,
                                }),
                            );
                        }
                        crate::terminal::manager::TerminalBroadcastEvent::Exited {
                            session_id,
                            exit_code,
                            ..
                        } => {
                            let _ = app_handle.emit(
                                "terminal-exited",
                                serde_json::json!({
                                    "sessionId": session_id,
                                    "exitCode": exit_code,
                                }),
                            );
                        }
                        _ => {}
                    }
                }
            });

            // Forward AI permission events to Tauri webview
            let ai_rx = agent_setup.ai_task_manager().subscribe_events();
            let app_handle_ai = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                let mut ai_rx = ai_rx;
                while let Ok(event) = ai_rx.recv().await {
                    match event {
                        crate::ai::models::AiBroadcastEvent::PermissionRequested {
                            task_id,
                            device_id,
                            open_code_session_id,
                            permission_id,
                            tool,
                            action,
                            target,
                            patterns,
                            project_path,
                            risk,
                            created_at,
                            timeout_at,
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-permission-requested",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "deviceId": device_id,
                                    "sessionId": open_code_session_id,
                                    "permissionId": permission_id,
                                    "tool": tool,
                                    "action": action,
                                    "target": target,
                                    "patterns": patterns,
                                    "projectPath": project_path,
                                    "risk": risk,
                                    "createdAt": created_at,
                                    "timeoutAt": timeout_at,
                                }),
                            );
                        }
                        crate::ai::models::AiBroadcastEvent::PermissionResolved {
                            task_id,
                            device_id,
                            open_code_session_id,
                            permission_id,
                            decision,
                            reply,
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-permission-resolved",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "deviceId": device_id,
                                    "sessionId": open_code_session_id,
                                    "permissionId": permission_id,
                                    "decision": decision,
                                    "reply": reply,
                                }),
                            );
                        }
                        crate::ai::models::AiBroadcastEvent::Activity {
                            task_id,
                            open_code_session_id,
                            activity,
                            ..
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-activity",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "sessionId": open_code_session_id,
                                    "activity": activity,
                                }),
                            );
                        }
                        crate::ai::models::AiBroadcastEvent::ResponseChunk {
                            task_id,
                            open_code_session_id,
                            text,
                            ..
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-response-chunk",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "sessionId": open_code_session_id,
                                    "text": text,
                                }),
                            );
                        }
                        crate::ai::models::AiBroadcastEvent::Completed {
                            task_id,
                            open_code_session_id,
                            duration_ms,
                            ..
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-completed",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "sessionId": open_code_session_id,
                                    "durationMs": duration_ms,
                                }),
                            );
                        }
                        crate::ai::models::AiBroadcastEvent::Failed {
                            task_id,
                            open_code_session_id,
                            error,
                            ..
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-failed",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "sessionId": open_code_session_id,
                                    "error": error,
                                }),
                            );
                        }
                        crate::ai::models::AiBroadcastEvent::Cancelled {
                            task_id,
                            open_code_session_id,
                            ..
                        } => {
                            let _ = app_handle_ai.emit(
                                "ai-cancelled",
                                serde_json::json!({
                                    "taskId": task_id,
                                    "sessionId": open_code_session_id,
                                }),
                            );
                        }
                        _ => {}
                    }
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_agent_status,
            commands::get_system_info,
            commands::get_tailscale_info,
            commands::refresh_tailscale_info,
            commands::open_tailscale,
            commands::get_pairing_code,
            commands::regenerate_pairing_code,
            commands::get_server_info,
            commands::get_paired_devices,
            commands::create_terminal,
            commands::list_terminals,
            commands::kill_terminal,
            commands::get_terminal_history,
            commands::write_terminal_input,
            commands::resize_terminal,
            commands::get_file_roots,
            commands::list_directory,
            commands::read_file,
            commands::search_files,
            commands::list_pending_ai_permissions,
            commands::resolve_ai_permission,
            commands::list_ai_conversations,
            commands::get_ai_conversation,
            commands::create_ai_conversation,
            commands::rename_ai_conversation,
            commands::delete_ai_conversation,
            commands::search_ai_conversations,
            commands::export_ai_conversation,
            commands::start_ai_task,
            commands::resume_ai_task,
            commands::cancel_ai_task,
            commands::list_ai_providers,
            commands::set_ai_provider_key,
            commands::logout_ai_provider,
            commands::test_ai_provider,
            commands::list_ai_models,
            commands::get_ai_defaults,
            commands::set_ai_defaults,
            commands::get_ai_usage,
            commands::list_scripts,
            commands::get_script,
            commands::save_script,
            commands::delete_script,
        ])
        .build(tauri::generate_context!())
        .expect("error while running tauri application")
        .run(move |_app_handle, event| {
            if let tauri::RunEvent::ExitRequested { .. } = event {
                println!("[Orbit Agent] Shutting down agent services...");
                agent_shutdown.stop();
            }
        });
}
