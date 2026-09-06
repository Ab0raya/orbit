use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ProtocolError {
    pub code: String,
    pub message: String,
}

impl ProtocolError {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }

    pub fn malformed_message(msg: impl Into<String>) -> Self {
        Self::new("MALFORMED_MESSAGE", msg)
    }

    pub fn unknown_action(action: impl Into<String>) -> Self {
        Self::new(
            "UNKNOWN_ACTION",
            format!("Action '{}' is not supported by this agent.", action.into()),
        )
    }

    pub fn unauthorized(msg: impl Into<String>) -> Self {
        Self::new("UNAUTHORIZED", msg)
    }

    pub fn invalid_pairing_code() -> Self {
        Self::new(
            "INVALID_PAIRING_CODE",
            "The pairing code is invalid or expired.",
        )
    }

    pub fn rate_limited() -> Self {
        Self::new(
            "RATE_LIMITED",
            "Too many failed pairing attempts. Please wait before retrying.",
        )
    }

    pub fn message_too_large(size: usize, max: usize) -> Self {
        Self::new(
            "MESSAGE_TOO_LARGE",
            format!(
                "Message size of {} bytes exceeds limit of {} bytes.",
                size, max
            ),
        )
    }

    pub fn internal_error(msg: impl Into<String>) -> Self {
        Self::new("INTERNAL_ERROR", msg)
    }

    pub fn path_not_found(path: impl Into<String>) -> Self {
        Self::new(
            "PATH_NOT_FOUND",
            format!("Path '{}' was not found.", path.into()),
        )
    }

    pub fn permission_denied(msg: impl Into<String>) -> Self {
        Self::new("PERMISSION_DENIED", msg)
    }

    pub fn invalid_path(msg: impl Into<String>) -> Self {
        Self::new("INVALID_PATH", msg)
    }

    pub fn file_too_large(size: u64, max: u64) -> Self {
        Self::new(
            "FILE_TOO_LARGE",
            format!(
                "File size ({} bytes) exceeds maximum permitted limit ({} bytes).",
                size, max
            ),
        )
    }

    pub fn unsupported_file_type(msg: impl Into<String>) -> Self {
        Self::new("UNSUPPORTED_FILE_TYPE", msg)
    }

    pub fn already_exists(path: impl Into<String>) -> Self {
        Self::new(
            "ALREADY_EXISTS",
            format!("Path '{}' already exists.", path.into()),
        )
    }

    pub fn operation_failed(msg: impl Into<String>) -> Self {
        Self::new("OPERATION_FAILED", msg)
    }

    pub fn project_not_found(path: impl Into<String>) -> Self {
        Self::new(
            "PROJECT_NOT_FOUND",
            format!("Project path '{}' was not found.", path.into()),
        )
    }

    pub fn project_not_allowed(path: impl Into<String>) -> Self {
        Self::new(
            "PROJECT_NOT_ALLOWED",
            format!(
                "Project path '{}' is outside allowed project roots.",
                path.into()
            ),
        )
    }

    pub fn not_a_git_repository(path: impl Into<String>) -> Self {
        Self::new(
            "NOT_A_GIT_REPOSITORY",
            format!("Directory '{}' is not a Git repository.", path.into()),
        )
    }

    pub fn git_not_installed() -> Self {
        Self::new(
            "GIT_NOT_INSTALLED",
            "Git is not installed on the workstation or not in PATH.",
        )
    }

    pub fn git_operation_failed(msg: impl Into<String>) -> Self {
        Self::new("GIT_OPERATION_FAILED", msg)
    }

    pub fn git_dirty_worktree(msg: impl Into<String>) -> Self {
        Self::new("GIT_DIRTY_WORKTREE", msg)
    }

    pub fn invalid_branch_name(name: impl Into<String>) -> Self {
        Self::new(
            "INVALID_BRANCH_NAME",
            format!("Branch name '{}' is invalid.", name.into()),
        )
    }

    pub fn invalid_file_path(path: impl Into<String>) -> Self {
        Self::new(
            "INVALID_FILE_PATH",
            format!(
                "File path '{}' is invalid or escapes repository.",
                path.into()
            ),
        )
    }

    pub fn commit_message_empty() -> Self {
        Self::new("COMMIT_MESSAGE_EMPTY", "Commit message cannot be empty.")
    }

    pub fn checkout_conflict(msg: impl Into<String>) -> Self {
        Self::new("CHECKOUT_CONFLICT", msg)
    }

    pub fn opencode_not_found() -> Self {
        Self::new(
            "OPENCODE_NOT_FOUND",
            "OpenCode CLI executable was not found on the workstation.",
        )
    }

    pub fn opencode_not_found_with_msg(msg: impl Into<String>) -> Self {
        Self::new("OPENCODE_NOT_FOUND", msg)
    }

    pub fn ai_task_not_found(task_id: impl Into<String>) -> Self {
        Self::new(
            "AI_TASK_NOT_FOUND",
            format!("AI task '{}' was not found.", task_id.into()),
        )
    }

    pub fn ai_task_already_running(task_id: impl Into<String>) -> Self {
        Self::new(
            "AI_TASK_ALREADY_RUNNING",
            format!("AI task '{}' is already running.", task_id.into()),
        )
    }

    pub fn ai_task_not_allowed(msg: impl Into<String>) -> Self {
        Self::new("AI_TASK_NOT_ALLOWED", msg)
    }

    pub fn ai_task_invalid_prompt(msg: impl Into<String>) -> Self {
        Self::new("AI_TASK_INVALID_PROMPT", msg)
    }

    pub fn ai_task_invalid_agent(msg: impl Into<String>) -> Self {
        Self::new("AI_TASK_INVALID_AGENT", msg)
    }

    pub fn ai_task_failed(msg: impl Into<String>) -> Self {
        Self::new("AI_TASK_FAILED", msg)
    }

    pub fn ai_task_cancel_failed(msg: impl Into<String>) -> Self {
        Self::new("AI_TASK_CANCEL_FAILED", msg)
    }

    pub fn ai_session_not_found(session_id: impl Into<String>) -> Self {
        Self::new(
            "AI_SESSION_NOT_FOUND",
            format!("OpenCode session '{}' was not found.", session_id.into()),
        )
    }

    pub fn ai_session_not_allowed(msg: impl Into<String>) -> Self {
        Self::new("AI_SESSION_NOT_ALLOWED", msg)
    }

    pub fn invalid_params(msg: impl Into<String>) -> Self {
        Self::new("INVALID_PARAMS", msg)
    }

    pub fn not_found(msg: impl Into<String>) -> Self {
        Self::new("NOT_FOUND", msg)
    }
}
