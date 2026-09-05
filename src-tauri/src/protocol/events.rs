use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct OrbitEvent {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub event: String,
    pub payload: serde_json::Value,
}

impl OrbitEvent {
    pub fn new(event: impl Into<String>, payload: serde_json::Value) -> Self {
        Self {
            msg_type: "event".to_string(),
            event: event.into(),
            payload,
        }
    }

    pub fn welcome(version: &str) -> Self {
        Self::new(
            "welcome",
            serde_json::json!({
                "server": "Orbit Desktop Agent",
                "version": version,
                "protocol": "1.0",
            }),
        )
    }

    pub fn device_paired(device_id: &str, device_name: &str, platform: &str, paired_at: u64) -> Self {
        Self::new(
            "device.paired",
            serde_json::json!({
                "deviceId": device_id,
                "name": device_name,
                "platform": platform,
                "pairedAt": paired_at,
            }),
        )
    }

    pub fn device_connected(connection_id: &str, connected_at: u64) -> Self {
        Self::new(
            "device.connected",
            serde_json::json!({
                "connectionId": connection_id,
                "connectedAt": connected_at,
            }),
        )
    }

    pub fn device_disconnected(connection_id: &str, device_id: Option<&str>) -> Self {
        Self::new(
            "device.disconnected",
            serde_json::json!({
                "connectionId": connection_id,
                "deviceId": device_id,
            }),
        )
    }

    pub fn terminal_created(session_id: &str) -> Self {
        Self::new(
            "terminal.created",
            serde_json::json!({
                "sessionId": session_id,
            }),
        )
    }

    pub fn terminal_output(session_id: &str, data: &str) -> Self {
        Self::new(
            "terminal.output",
            serde_json::json!({
                "sessionId": session_id,
                "data": data,
            }),
        )
    }

    pub fn terminal_exited(session_id: &str, exit_code: Option<i32>) -> Self {
        Self::new(
            "terminal.exited",
            serde_json::json!({
                "sessionId": session_id,
                "exitCode": exit_code,
            }),
        )
    }

    pub fn terminal_error(session_id: &str, error: &str) -> Self {
        Self::new(
            "terminal.error",
            serde_json::json!({
                "sessionId": session_id,
                "error": error,
            }),
        )
    }

    pub fn ai_task_created(
        task_id: &str,
        project_path: &str,
        agent: &str,
        read_only: bool,
    ) -> Self {
        Self::new(
            "ai.task.created",
            serde_json::json!({
                "taskId": task_id,
                "projectPath": project_path,
                "agent": agent,
                "readOnly": read_only,
            }),
        )
    }

    pub fn ai_task_started(task_id: &str, open_code_session_id: Option<&str>) -> Self {
        Self::new(
            "ai.task.started",
            serde_json::json!({
                "taskId": task_id,
                "openCodeSessionId": open_code_session_id,
            }),
        )
    }

    pub fn ai_task_updated(
        task_id: &str,
        open_code_session_id: Option<&str>,
        activity: &str,
    ) -> Self {
        Self::new(
            "ai.task.updated",
            serde_json::json!({
                "taskId": task_id,
                "openCodeSessionId": open_code_session_id,
                "activity": activity,
            }),
        )
    }

    pub fn ai_task_activity(
        task_id: &str,
        open_code_session_id: Option<&str>,
        activity: &crate::ai::models::AiActivity,
    ) -> Self {
        Self::new(
            "ai.task.activity",
            serde_json::json!({
                "taskId": task_id,
                "openCodeSessionId": open_code_session_id,
                "activity": activity,
            }),
        )
    }

    pub fn ai_task_output(
        task_id: &str,
        open_code_session_id: Option<&str>,
        text: &str,
    ) -> Self {
        Self::new(
            "ai.task.output",
            serde_json::json!({
                "taskId": task_id,
                "openCodeSessionId": open_code_session_id,
                "text": text,
            }),
        )
    }

    pub fn ai_task_response(
        task_id: &str,
        open_code_session_id: Option<&str>,
        delta: &str,
    ) -> Self {
        Self::new(
            "ai.task.response",
            serde_json::json!({
                "taskId": task_id,
                "openCodeSessionId": open_code_session_id,
                "delta": delta,
            }),
        )
    }

    pub fn ai_task_tool_started(
        task_id: &str,
        open_code_session_id: Option<&str>,
        tool: &str,
        status: &str,
        title: Option<&str>,
    ) -> Self {
        Self::new(
            "ai.task.tool_started",
            serde_json::json!({
                "taskId": task_id,
                "openCodeSessionId": open_code_session_id,
                "tool": tool,
                "status": status,
                "title": title,
            }),
        )
    }

    pub fn ai_task_tool_finished(
        task_id: &str,
        open_code_session_id: Option<&str>,
        tool: &str,
        status: &str,
        exit_code: Option<i32>,
    ) -> Self {
        Self::new(
            "ai.task.tool_finished",
            serde_json::json!({
                "taskId": task_id,
                "openCodeSessionId": open_code_session_id,
                "tool": tool,
                "status": status,
                "exitCode": exit_code,
            }),
        )
    }

    pub fn ai_task_completed(
        task_id: &str,
        open_code_session_id: Option<&str>,
        duration_ms: u64,
    ) -> Self {
        Self::new(
            "ai.task.completed",
            serde_json::json!({
                "taskId": task_id,
                "openCodeSessionId": open_code_session_id,
                "durationMs": duration_ms,
            }),
        )
    }

    pub fn ai_task_failed(
        task_id: &str,
        open_code_session_id: Option<&str>,
        error: &str,
    ) -> Self {
        Self::new(
            "ai.task.failed",
            serde_json::json!({
                "taskId": task_id,
                "openCodeSessionId": open_code_session_id,
                "error": error,
            }),
        )
    }

    pub fn ai_task_cancelled(task_id: &str, open_code_session_id: Option<&str>) -> Self {
        Self::new(
            "ai.task.cancelled",
            serde_json::json!({
                "taskId": task_id,
                "openCodeSessionId": open_code_session_id,
            }),
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub fn ai_permission_requested(
        permission_id: &str,
        task_id: &str,
        session_id: Option<&str>,
        tool: &str,
        action: &str,
        target: &str,
        patterns: &[String],
        project_path: &str,
        risk: &str,
        created_at: u64,
        timeout_at: u64,
    ) -> Self {
        Self::new(
            "ai.permission.requested",
            serde_json::json!({
                "permissionId": permission_id,
                "taskId": task_id,
                "sessionId": session_id,
                "tool": tool,
                "action": action,
                "target": target,
                "patterns": patterns,
                "projectPath": project_path,
                "risk": risk,
                "createdAt": created_at,
                "timeoutAt": timeout_at,
            }),
        )
    }

    pub fn ai_permission_resolved(
        permission_id: &str,
        task_id: &str,
        session_id: Option<&str>,
        decision: &str,
        reply: &str,
    ) -> Self {
        Self::new(
            "ai.permission.resolved",
            serde_json::json!({
                "permissionId": permission_id,
                "taskId": task_id,
                "sessionId": session_id,
                "decision": decision,
                "reply": reply,
            }),
        )
    }
}

