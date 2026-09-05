use std::sync::Arc;
use tauri::State;

use crate::agent::pairing::PairingInfo;
use crate::agent::server::ServerInfo;
use crate::agent::session::PairedDevice;
use crate::agent::system::SystemInfo;
use crate::agent::tailscale::TailscaleInfo;
use crate::agent::{AgentStatus, OrbitAgent};
use crate::terminal::TerminalSessionSummary;

pub const DESKTOP_LOCAL_OWNER: &str = "orbit_desktop_local";

pub struct AppState {
    pub agent: Arc<OrbitAgent>,
}

#[tauri::command]
pub fn get_agent_status(state: State<'_, AppState>) -> Result<AgentStatus, String> {
    Ok(state.agent.get_status())
}

#[tauri::command]
pub fn get_system_info(state: State<'_, AppState>) -> Result<SystemInfo, String> {
    Ok(state.agent.get_system_info())
}

#[tauri::command]
pub fn get_tailscale_info(state: State<'_, AppState>) -> Result<TailscaleInfo, String> {
    Ok(state.agent.get_tailscale_info())
}

#[tauri::command]
pub fn refresh_tailscale_info(state: State<'_, AppState>) -> Result<TailscaleInfo, String> {
    Ok(state.agent.refresh_tailscale_info())
}

#[tauri::command]
pub fn open_tailscale(url: Option<String>) -> Result<(), String> {
    let target = url.unwrap_or_else(|| "https://login.tailscale.com".to_string());
    #[cfg(target_os = "windows")]
    {
        let _ = std::process::Command::new("cmd")
            .args(["/C", "start", &target])
            .spawn();
    }
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("open")
            .arg(&target)
            .spawn();
    }
    #[cfg(target_os = "linux")]
    {
        let _ = std::process::Command::new("xdg-open")
            .arg(&target)
            .spawn();
    }
    Ok(())
}

#[tauri::command]
pub fn get_pairing_code(state: State<'_, AppState>) -> Result<PairingInfo, String> {
    state.agent.get_pairing_info()
}

#[tauri::command]
pub fn regenerate_pairing_code(state: State<'_, AppState>) -> Result<PairingInfo, String> {
    state.agent.regenerate_pairing_code()
}

#[tauri::command]
pub fn get_server_info(state: State<'_, AppState>) -> Result<ServerInfo, String> {
    Ok(state.agent.get_server_info())
}

#[tauri::command]
pub fn get_paired_devices(state: State<'_, AppState>) -> Result<Vec<PairedDevice>, String> {
    Ok(state.agent.get_paired_devices())
}

#[tauri::command]
pub fn create_terminal(
    state: State<'_, AppState>,
    cwd: Option<String>,
    cols: Option<u16>,
    rows: Option<u16>,
) -> Result<TerminalSessionSummary, String> {
    let term_mgr = state.agent.terminal_manager();
    let session = term_mgr
        .create_session(DESKTOP_LOCAL_OWNER, cwd.as_deref(), cols, rows)
        .map_err(|e| e.message)?;
    Ok(session.to_summary())
}

#[tauri::command]
pub fn list_terminals(state: State<'_, AppState>) -> Result<Vec<TerminalSessionSummary>, String> {
    let term_mgr = state.agent.terminal_manager();
    Ok(term_mgr.list_all_sessions())
}

#[tauri::command]
pub fn kill_terminal(state: State<'_, AppState>, session_id: String) -> Result<(), String> {
    let term_mgr = state.agent.terminal_manager();
    // Desktop admin can kill any session
    if let Some(session) = term_mgr.get_session_by_id(&session_id) {
        session.kill()?;
        Ok(())
    } else {
        Err(format!("Terminal session '{}' not found", session_id))
    }
}

#[tauri::command]
pub fn get_terminal_history(
    state: State<'_, AppState>,
    session_id: String,
) -> Result<String, String> {
    let term_mgr = state.agent.terminal_manager();
    if let Some(session) = term_mgr.get_session_by_id(&session_id) {
        Ok(session.get_history())
    } else {
        Err(format!("Terminal session '{}' not found", session_id))
    }
}

#[tauri::command]
pub fn write_terminal_input(
    state: State<'_, AppState>,
    session_id: String,
    data: String,
) -> Result<(), String> {
    let term_mgr = state.agent.terminal_manager();
    term_mgr
        .write_input(&session_id, DESKTOP_LOCAL_OWNER, &data)
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn resize_terminal(
    state: State<'_, AppState>,
    session_id: String,
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    let term_mgr = state.agent.terminal_manager();
    term_mgr
        .resize(&session_id, DESKTOP_LOCAL_OWNER, cols, rows)
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn get_file_roots(state: State<'_, AppState>) -> Result<Vec<crate::files::manager::FileRoot>, String> {
    Ok(state.agent.file_manager().roots())
}

#[tauri::command]
pub fn list_directory(
    state: State<'_, AppState>,
    path: String,
) -> Result<crate::files::manager::FileListResult, String> {
    state
        .agent
        .file_manager()
        .list(&path)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn read_file(
    state: State<'_, AppState>,
    path: String,
) -> Result<crate::files::manager::FileReadResult, String> {
    state
        .agent
        .file_manager()
        .read(&path)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn search_files(
    state: State<'_, AppState>,
    root: String,
    query: String,
    mode: String,
    max_results: Option<usize>,
) -> Result<crate::files::operations::FileSearchResult, String> {
    state
        .agent
        .file_manager()
        .search(&root, &query, &mode, max_results)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn list_pending_ai_permissions(
    state: State<'_, AppState>,
) -> Result<Vec<crate::ai::permission::AiPermissionRequest>, String> {
    // Return all pending permissions across devices for desktop visibility
    let pm = state.agent.ai_task_manager().permission_manager();
    pm.check_and_expire();
    let mut list = Vec::new();
    // list_pending filters by device, so we check requests directly or check all
    let reqs = pm.list_pending(DESKTOP_LOCAL_OWNER);
    list.extend(reqs);
    // Also include any other device requests so desktop can observe mobile permissions
    for dev in state.agent.get_paired_devices() {
        let perms = pm.list_pending(&dev.device_id);
        list.extend(perms);
    }
    Ok(list)
}

#[tauri::command]
pub async fn resolve_ai_permission(
    state: State<'_, AppState>,
    device_id: String,
    permission_id: String,
    decision: String,
) -> Result<crate::ai::permission::AiPermissionRequest, String> {
    let dec = match decision.to_lowercase().as_str() {
        "allow" | "once" => crate::ai::permission::AiPermissionDecision::Allow,
        "always" => crate::ai::permission::AiPermissionDecision::Always,
        "deny" | "reject" => crate::ai::permission::AiPermissionDecision::Deny,
        other => return Err(format!("Invalid decision '{}'", other)),
    };

    state
        .agent
        .ai_task_manager()
        .resolve_permission(&device_id, &permission_id, dec)
        .await
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn list_ai_conversations(
    state: State<'_, AppState>,
    limit: Option<usize>,
    offset: Option<usize>,
) -> Result<Vec<crate::ai::storage::AiConversationSummary>, String> {
    state
        .agent
        .ai_task_manager()
        .conversation_store()
        .list_conversations(limit.unwrap_or(50), offset.unwrap_or(0))
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn get_ai_conversation(
    state: State<'_, AppState>,
    conversation_id: String,
) -> Result<Option<crate::ai::storage::AiConversationDetail>, String> {
    state
        .agent
        .ai_task_manager()
        .conversation_store()
        .get_conversation(&conversation_id)
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn create_ai_conversation(
    state: State<'_, AppState>,
    title: Option<String>,
    project_path: Option<String>,
    directory_path: Option<String>,
    context_type: Option<String>,
    provider_id: Option<String>,
    model_id: Option<String>,
) -> Result<crate::ai::storage::AiConversationSummary, String> {
    state
        .agent
        .ai_task_manager()
        .conversation_store()
        .create_conversation(
            title.as_deref(),
            project_path.as_deref(),
            directory_path.as_deref(),
            context_type.as_deref(),
            provider_id.as_deref(),
            model_id.as_deref(),
        )
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn rename_ai_conversation(
    state: State<'_, AppState>,
    conversation_id: String,
    title: String,
) -> Result<(), String> {
    state
        .agent
        .ai_task_manager()
        .conversation_store()
        .update_title(&conversation_id, &title)
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn delete_ai_conversation(
    state: State<'_, AppState>,
    conversation_id: String,
    delete_session: Option<bool>,
) -> Result<(), String> {
    if delete_session.unwrap_or(false) {
        if let Ok(Some(conv)) = state.agent.ai_task_manager().conversation_store().get_conversation(&conversation_id) {
            if let Some(ref sid) = conv.open_code_session_id {
                if let Ok(bin) = crate::ai::process::find_opencode_binary() {
                    let _ = std::process::Command::new(bin)
                        .args(["session", "delete", sid])
                        .output();
                }
            }
        }
    }
    state
        .agent
        .ai_task_manager()
        .conversation_store()
        .delete_conversation(&conversation_id)
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn search_ai_conversations(
    state: State<'_, AppState>,
    query: String,
    limit: Option<usize>,
) -> Result<Vec<crate::ai::storage::AiConversationSearchResult>, String> {
    state
        .agent
        .ai_task_manager()
        .conversation_store()
        .search_conversations(&query, limit.unwrap_or(20))
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn export_ai_conversation(
    state: State<'_, AppState>,
    conversation_id: String,
    format: Option<String>,
) -> Result<String, String> {
    let store = state.agent.ai_task_manager().conversation_store();
    match format.as_deref().unwrap_or("markdown").to_lowercase().as_str() {
        "json" => store.export_json(&conversation_id).map_err(|e| e.message),
        _ => store.export_markdown(&conversation_id).map_err(|e| e.message),
    }
}

#[tauri::command]
#[allow(clippy::too_many_arguments)]
pub async fn start_ai_task(
    state: State<'_, AppState>,
    prompt: String,
    project_path: Option<String>,
    agent: Option<String>,
    read_only: Option<bool>,
    conversation_id: Option<String>,
    model: Option<String>,
) -> Result<crate::ai::models::AiTaskSummary, String> {
    let p_path = project_path.unwrap_or_default();
    state
        .agent
        .ai_task_manager()
        .start_task_extended(
            DESKTOP_LOCAL_OWNER,
            &p_path,
            &prompt,
            agent.as_deref(),
            read_only,
            conversation_id,
            model,
        )
        .await
        .map_err(|e| e.message)
}

#[tauri::command]
#[allow(clippy::too_many_arguments)]
pub async fn resume_ai_task(
    state: State<'_, AppState>,
    session_id: String,
    prompt: String,
    project_path: Option<String>,
    agent: Option<String>,
    read_only: Option<bool>,
    conversation_id: Option<String>,
    model: Option<String>,
) -> Result<crate::ai::models::AiTaskSummary, String> {
    let p_path = project_path.unwrap_or_default();
    state
        .agent
        .ai_task_manager()
        .resume_task_extended(
            DESKTOP_LOCAL_OWNER,
            &session_id,
            &p_path,
            &prompt,
            agent.as_deref(),
            read_only,
            conversation_id,
            model,
        )
        .await
        .map_err(|e| e.message)
}

#[tauri::command]
pub async fn cancel_ai_task(
    state: State<'_, AppState>,
    task_id: String,
) -> Result<(), String> {
    state
        .agent
        .ai_task_manager()
        .cancel_task(&task_id, DESKTOP_LOCAL_OWNER)
        .await
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn list_ai_providers(
    state: State<'_, AppState>,
) -> Result<Vec<crate::ai::provider_manager::AiProviderSummary>, String> {
    state
        .agent
        .ai_task_manager()
        .provider_manager()
        .list_providers()
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn set_ai_provider_key(
    state: State<'_, AppState>,
    provider_id: String,
    api_key: String,
) -> Result<crate::ai::provider_manager::AiProviderSummary, String> {
    state
        .agent
        .ai_task_manager()
        .provider_manager()
        .set_provider_key(&provider_id, &api_key)
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn logout_ai_provider(
    state: State<'_, AppState>,
    provider_id: String,
) -> Result<(), String> {
    state
        .agent
        .ai_task_manager()
        .provider_manager()
        .logout_provider(&provider_id)
        .map_err(|e| e.message)
}

#[tauri::command]
pub async fn test_ai_provider(
    state: State<'_, AppState>,
    provider_id: String,
) -> Result<bool, String> {
    state
        .agent
        .ai_task_manager()
        .provider_manager()
        .test_provider(&provider_id)
        .await
        .map_err(|e| e.message)
}

#[tauri::command]
pub async fn list_ai_models(
    state: State<'_, AppState>,
    provider: Option<String>,
) -> Result<Vec<crate::ai::provider_manager::AiModelSummary>, String> {
    state
        .agent
        .ai_task_manager()
        .provider_manager()
        .list_models(provider.as_deref())
        .await
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn get_ai_defaults(
    state: State<'_, AppState>,
) -> Result<crate::ai::storage::AiDefaults, String> {
    state
        .agent
        .ai_task_manager()
        .conversation_store()
        .get_defaults()
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn set_ai_defaults(
    state: State<'_, AppState>,
    provider_id: String,
    model_id: String,
    agent: Option<String>,
    context_behavior: Option<String>,
) -> Result<crate::ai::storage::AiDefaults, String> {
    let defaults = crate::ai::storage::AiDefaults {
        provider_id,
        model_id,
        agent: agent.unwrap_or_else(|| "plan".to_string()),
        context_behavior: context_behavior.unwrap_or_else(|| "none".to_string()),
    };
    state
        .agent
        .ai_task_manager()
        .conversation_store()
        .set_defaults(&defaults)
        .map_err(|e| e.message)?;
    Ok(defaults)
}

#[tauri::command]
pub async fn get_ai_usage(
    state: State<'_, AppState>,
    days: Option<u32>,
) -> Result<crate::ai::provider_manager::AiUsageStats, String> {
    state
        .agent
        .ai_task_manager()
        .provider_manager()
        .get_usage_stats(days)
        .await
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn list_scripts(
    state: State<'_, AppState>,
    project_path: Option<String>,
) -> Result<Vec<crate::scripts::Script>, String> {
    state
        .agent
        .script_manager()
        .list(project_path.as_deref())
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn get_script(
    state: State<'_, AppState>,
    id: String,
) -> Result<Option<crate::scripts::Script>, String> {
    state
        .agent
        .script_manager()
        .get(&id)
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn save_script(
    state: State<'_, AppState>,
    script: crate::scripts::ScriptInput,
) -> Result<crate::scripts::Script, String> {
    state
        .agent
        .script_manager()
        .save(script)
        .map_err(|e| e.message)
}

#[tauri::command]
pub fn delete_script(
    state: State<'_, AppState>,
    id: String,
) -> Result<bool, String> {
    state
        .agent
        .script_manager()
        .delete(&id)
        .map_err(|e| e.message)
}

