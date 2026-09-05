use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::{oneshot, Mutex};

use crate::protocol::errors::ProtocolError;

pub const DEFAULT_PERMISSION_TIMEOUT_SECS: u64 = 300; // 5 minutes

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AiPermissionRisk {
    Low,
    Medium,
    High,
}

impl AiPermissionRisk {
    pub fn as_str(&self) -> &'static str {
        match self {
            AiPermissionRisk::Low => "low",
            AiPermissionRisk::Medium => "medium",
            AiPermissionRisk::High => "high",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AiPermissionDecision {
    Allow,
    Always,
    Deny,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AiPermissionState {
    Pending,
    Approved,
    Denied,
    Expired,
    Cancelled,
}

impl AiPermissionState {
    pub fn as_str(&self) -> &'static str {
        match self {
            AiPermissionState::Pending => "pending",
            AiPermissionState::Approved => "approved",
            AiPermissionState::Denied => "denied",
            AiPermissionState::Expired => "expired",
            AiPermissionState::Cancelled => "cancelled",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiPermissionRequest {
    pub permission_id: String,
    pub task_id: String,
    pub device_id: String,
    pub session_id: Option<String>,
    pub tool: String,
    pub action: String,
    pub target: String,
    pub patterns: Vec<String>,
    pub project_path: String,
    pub risk: AiPermissionRisk,
    pub state: AiPermissionState,
    pub metadata: serde_json::Value,
    pub created_at: u64,
    pub timeout_at: u64,
}

pub struct PermissionManager {
    requests: Arc<RwLock<HashMap<String, AiPermissionRequest>>>,
    resolvers: Arc<Mutex<HashMap<String, oneshot::Sender<AiPermissionDecision>>>>,
}

impl Default for PermissionManager {
    fn default() -> Self {
        Self::new()
    }
}

impl PermissionManager {
    pub fn new() -> Self {
        Self {
            requests: Arc::new(RwLock::new(HashMap::new())),
            resolvers: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Classify action risk independently based on tool and patterns.
    pub fn classify_risk(tool: &str, patterns: &[String], _metadata: &serde_json::Value) -> AiPermissionRisk {
        let tool_lower = tool.to_lowercase();

        // Destructive file deletion or tool actions
        if tool_lower == "delete"
            || tool_lower == "file_delete"
            || tool_lower == "remove_file"
            || tool_lower == "rm"
        {
            return AiPermissionRisk::High;
        }

        // Bash commands analysis
        if tool_lower == "bash" || tool_lower == "terminal" || tool_lower == "cmd" || tool_lower == "sh" {
            for pattern in patterns {
                let p = pattern.trim().to_lowercase();
                // Destructive patterns
                if p.starts_with("rm ")
                    || p.contains(" rm ")
                    || p.contains("rm -rf")
                    || p.contains("rm -r")
                    || p.starts_with("rmdir")
                    || p.contains("git reset --hard")
                    || p.contains("git clean -f")
                    || p.contains("git checkout -- .")
                    || p.contains("git restore .")
                    || p.starts_with("chmod")
                    || p.contains(" chmod ")
                    || p.starts_with("chown")
                    || p.contains(" chown ")
                    || p.starts_with("dd ")
                    || p.contains("mkfs")
                    || p.contains("fdisk")
                    || p.contains("> /dev/")
                    || p.contains("/etc/")
                    || p.contains("/usr/")
                    || p.contains("/boot/")
                    || p.contains("/sys/")
                    || p.contains("/proc/")
                {
                    return AiPermissionRisk::High;
                }
            }
            return AiPermissionRisk::Medium;
        }

        // Edit or write tools
        if tool_lower == "edit"
            || tool_lower == "write"
            || tool_lower == "apply_patch"
            || tool_lower == "patch"
        {
            return AiPermissionRisk::Medium;
        }

        // Read / inspect tools
        if tool_lower == "read"
            || tool_lower == "view"
            || tool_lower == "list"
            || tool_lower == "list_dir"
            || tool_lower == "glob"
            || tool_lower == "grep"
        {
            return AiPermissionRisk::Low;
        }

        AiPermissionRisk::Medium
    }

    /// Derive a human-readable action description.
    pub fn derive_action_description(tool: &str, target: &str) -> String {
        let tool_lower = tool.to_lowercase();
        if tool_lower == "bash" || tool_lower == "terminal" || tool_lower == "cmd" || tool_lower == "sh" {
            format!("run command: {}", target)
        } else if tool_lower == "edit" || tool_lower == "write" || tool_lower == "patch" {
            format!("modify file: {}", target)
        } else if tool_lower.contains("delete") || tool_lower.contains("remove") {
            format!("delete file: {}", target)
        } else if tool_lower == "read" || tool_lower == "view" {
            format!("read file: {}", target)
        } else {
            format!("{}: {}", tool, target)
        }
    }

    /// Create and register a new permission request. Returns the request and a receiver that fires when resolved.
    #[allow(clippy::too_many_arguments)]
    pub async fn create_request(
        &self,
        permission_id: String,
        task_id: String,
        device_id: String,
        session_id: Option<String>,
        tool: String,
        patterns: Vec<String>,
        metadata: serde_json::Value,
        project_path: String,
    ) -> (AiPermissionRequest, oneshot::Receiver<AiPermissionDecision>) {
        let target = patterns
            .first()
            .cloned()
            .or_else(|| {
                metadata
                    .get("command")
                    .or_else(|| metadata.get("path"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string())
            })
            .unwrap_or_else(|| tool.clone());

        let risk = Self::classify_risk(&tool, &patterns, &metadata);
        let action = Self::derive_action_description(&tool, &target);
        let created_at = now_unix();
        let timeout_at = created_at + DEFAULT_PERMISSION_TIMEOUT_SECS;

        let request = AiPermissionRequest {
            permission_id: permission_id.clone(),
            task_id,
            device_id,
            session_id,
            tool,
            action,
            target,
            patterns,
            project_path,
            risk,
            state: AiPermissionState::Pending,
            metadata,
            created_at,
            timeout_at,
        };

        let (tx, rx) = oneshot::channel();

        // Store request
        {
            let mut reqs = self.requests.write().unwrap();
            reqs.insert(permission_id.clone(), request.clone());
        }

        // Store resolver channel
        {
            let mut resolvers = self.resolvers.lock().await;
            resolvers.insert(permission_id, tx);
        }

        (request, rx)
    }

    /// Resolve a permission request. Validates device ownership, state, and prevents "Always" for high-risk actions.
    pub async fn resolve_request(
        &self,
        calling_device_id: &str,
        permission_id: &str,
        decision: AiPermissionDecision,
    ) -> Result<AiPermissionRequest, ProtocolError> {
        let updated_req = {
            let mut reqs = self.requests.write().unwrap();
            let req = reqs
                .get_mut(permission_id)
                .ok_or_else(|| ProtocolError::ai_task_failed(format!("Permission request '{}' not found", permission_id)))?;

            // 1. Ownership check: calling device MUST match the device that initiated the task
            if req.device_id != calling_device_id {
                return Err(ProtocolError::unauthorized(
                    "Access denied: permission request belongs to another device.",
                ));
            }

            // 2. Check if still pending
            if req.state != AiPermissionState::Pending {
                return Err(ProtocolError::ai_task_failed(format!(
                    "Permission request is no longer pending (current state: {})",
                    req.state.as_str()
                )));
            }

            // 3. Timeout check
            if now_unix() > req.timeout_at {
                req.state = AiPermissionState::Expired;
                return Err(ProtocolError::ai_task_failed(
                    "Permission request has expired.",
                ));
            }

            // 4. Safety rule: High-risk destructive actions CANNOT be "Always Allowed"
            if decision == AiPermissionDecision::Always && req.risk == AiPermissionRisk::High {
                return Err(ProtocolError::ai_task_failed(
                    "High-risk destructive actions cannot be permanently allowed. Choose 'Allow' once instead.",
                ));
            }

            // 5. Update state
            match decision {
                AiPermissionDecision::Allow | AiPermissionDecision::Always => {
                    req.state = AiPermissionState::Approved;
                }
                AiPermissionDecision::Deny => {
                    req.state = AiPermissionState::Denied;
                }
            }

            req.clone()
        };

        // Notify resolver channel
        let tx_opt = {
            let mut resolvers = self.resolvers.lock().await;
            resolvers.remove(permission_id)
        };

        if let Some(tx) = tx_opt {
            let _ = tx.send(decision);
        }

        Ok(updated_req)
    }

    /// List all pending permission requests belonging to the given device.
    pub fn list_pending(&self, device_id: &str) -> Vec<AiPermissionRequest> {
        self.check_and_expire();
        let reqs = self.requests.read().unwrap();
        let mut list: Vec<AiPermissionRequest> = reqs
            .values()
            .filter(|r| r.device_id == device_id && r.state == AiPermissionState::Pending)
            .cloned()
            .collect();
        list.sort_by_key(|r| r.created_at);
        list
    }

    /// Get a permission request by ID with ownership check.
    pub fn get_request(&self, device_id: &str, permission_id: &str) -> Result<AiPermissionRequest, ProtocolError> {
        self.check_and_expire();
        let reqs = self.requests.read().unwrap();
        let req = reqs
            .get(permission_id)
            .ok_or_else(|| ProtocolError::ai_task_failed(format!("Permission request '{}' not found", permission_id)))?;

        if req.device_id != device_id {
            return Err(ProtocolError::unauthorized(
                "Access denied: permission request belongs to another device.",
            ));
        }

        Ok(req.clone())
    }

    /// Cancel all pending requests for a specific task.
    pub async fn cancel_task_requests(&self, task_id: &str) -> Vec<AiPermissionRequest> {
        let mut cancelled = Vec::new();
        let mut to_drop_resolvers = Vec::new();

        {
            let mut reqs = self.requests.write().unwrap();
            for req in reqs.values_mut() {
                if req.task_id == task_id && req.state == AiPermissionState::Pending {
                    req.state = AiPermissionState::Cancelled;
                    cancelled.push(req.clone());
                    to_drop_resolvers.push(req.permission_id.clone());
                }
            }
        }

        let mut resolvers = self.resolvers.lock().await;
        for id in to_drop_resolvers {
            if let Some(tx) = resolvers.remove(&id) {
                let _ = tx.send(AiPermissionDecision::Deny);
            }
        }

        cancelled
    }

    /// Check timeouts and mark expired requests.
    pub fn check_and_expire(&self) -> Vec<AiPermissionRequest> {
        let current_time = now_unix();
        let mut expired = Vec::new();

        let mut reqs = self.requests.write().unwrap();
        for req in reqs.values_mut() {
            if req.state == AiPermissionState::Pending && current_time > req.timeout_at {
                req.state = AiPermissionState::Expired;
                expired.push(req.clone());
            }
        }

        expired
    }
}
