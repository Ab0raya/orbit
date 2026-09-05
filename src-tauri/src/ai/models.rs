use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum AiAgent {
    Plan,
    Build,
}

impl AiAgent {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Plan => "plan",
            Self::Build => "build",
        }
    }

    pub fn from_str_loose(s: &str) -> Option<Self> {
        match s.trim().to_lowercase().as_str() {
            "plan" => Some(Self::Plan),
            "build" => Some(Self::Build),
            _ => None,
        }
    }

    pub fn is_read_only(&self) -> bool {
        matches!(self, Self::Plan)
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum AiTaskStatus {
    Queued,
    Running,
    Completed,
    Failed,
    Cancelled,
}

impl AiTaskStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Queued => "queued",
            Self::Running => "running",
            Self::Completed => "completed",
            Self::Failed => "failed",
            Self::Cancelled => "cancelled",
        }
    }

    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::Completed | Self::Failed | Self::Cancelled)
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum AiActivityType {
    Thinking,
    Reading,
    Writing,
    Command,
    Testing,
    Tool,
    Waiting,
    PermissionRequired,
    Completed,
    Error,
}

impl AiActivityType {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Thinking => "thinking",
            Self::Reading => "reading",
            Self::Writing => "writing",
            Self::Command => "command",
            Self::Testing => "testing",
            Self::Tool => "tool",
            Self::Waiting => "waiting",
            Self::PermissionRequired => "permission_required",
            Self::Completed => "completed",
            Self::Error => "error",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum AiActivityStatus {
    Running,
    Completed,
    Failed,
}

impl AiActivityStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Running => "running",
            Self::Completed => "completed",
            Self::Failed => "failed",
        }
    }
}

pub const MAX_ACTIVITIES_PER_TASK: usize = 500;
pub const MAX_OUTPUT_BYTES_PER_TASK: usize = 256 * 1024; // 256 KB

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AiActivity {
    pub activity_id: String,
    pub task_id: String,
    pub timestamp: u64,
    pub activity_type: AiActivityType,
    pub status: AiActivityStatus,
    pub title: String,
    pub detail: Option<String>,
    pub tool: Option<String>,
    pub command: Option<String>,
    pub file_path: Option<String>,
    pub duration_ms: Option<u64>,
    pub exit_code: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiTask {
    pub task_id: String,
    pub device_id: String,
    pub project_path: PathBuf,
    pub prompt: String,
    pub agent: AiAgent,
    pub read_only: bool,
    pub status: AiTaskStatus,
    pub open_code_session_id: Option<String>,
    pub child_pid: Option<u32>,
    pub started_at: u64,
    pub finished_at: Option<u64>,
    pub output: Option<String>,
    pub response: Option<String>,
    pub error: Option<String>,
    #[serde(default)]
    pub conversation_id: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub activities: Vec<AiActivity>,
}

impl AiTask {
    pub fn to_summary(&self) -> AiTaskSummary {
        AiTaskSummary {
            task_id: self.task_id.clone(),
            project_path: self.project_path.to_string_lossy().to_string(),
            status: self.status,
            agent: self.agent,
            read_only: self.read_only,
            open_code_session_id: self.open_code_session_id.clone(),
            started_at: self.started_at,
            finished_at: self.finished_at,
            activity_count: self.activities.len(),
            latest_activity: self.activities.last().map(|a| a.title.clone()),
            conversation_id: self.conversation_id.clone(),
            model: self.model.clone(),
        }
    }

    pub fn push_activity(&mut self, activity: AiActivity) {
        if self.activities.len() >= MAX_ACTIVITIES_PER_TASK {
            self.activities.remove(0);
        }
        self.activities.push(activity);
    }

    pub fn append_output(&mut self, chunk: &str) {
        let current = self.output.get_or_insert_with(String::new);
        current.push_str(chunk);
        if current.len() > MAX_OUTPUT_BYTES_PER_TASK {
            let excess = current.len() - MAX_OUTPUT_BYTES_PER_TASK;
            let mut boundary = excess;
            while !current.is_char_boundary(boundary) && boundary < current.len() {
                boundary += 1;
            }
            *current = current[boundary..].to_string();
        }
    }

    pub fn append_response(&mut self, chunk: &str) {
        let current = self.response.get_or_insert_with(String::new);
        current.push_str(chunk);
        if current.len() > MAX_OUTPUT_BYTES_PER_TASK {
            let excess = current.len() - MAX_OUTPUT_BYTES_PER_TASK;
            let mut boundary = excess;
            while !current.is_char_boundary(boundary) && boundary < current.len() {
                boundary += 1;
            }
            *current = current[boundary..].to_string();
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AiTaskSummary {
    pub task_id: String,
    pub project_path: String,
    pub status: AiTaskStatus,
    pub agent: AiAgent,
    pub read_only: bool,
    pub open_code_session_id: Option<String>,
    pub started_at: u64,
    pub finished_at: Option<u64>,
    #[serde(default)]
    pub activity_count: usize,
    pub latest_activity: Option<String>,
    #[serde(default)]
    pub conversation_id: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload", rename_all = "snake_case")]
pub enum AiBroadcastEvent {
    Created {
        task_id: String,
        device_id: String,
        project_path: String,
        agent: String,
        read_only: bool,
    },
    Started {
        task_id: String,
        device_id: String,
        open_code_session_id: Option<String>,
    },
    Updated {
        task_id: String,
        device_id: String,
        open_code_session_id: Option<String>,
        activity: String,
    },
    Activity {
        task_id: String,
        device_id: String,
        open_code_session_id: Option<String>,
        activity: AiActivity,
    },
    Output {
        task_id: String,
        device_id: String,
        open_code_session_id: Option<String>,
        text: String,
    },
    ResponseChunk {
        task_id: String,
        device_id: String,
        open_code_session_id: Option<String>,
        text: String,
    },
    ToolStarted {
        task_id: String,
        device_id: String,
        open_code_session_id: Option<String>,
        tool: String,
        status: String,
        title: Option<String>,
    },
    ToolFinished {
        task_id: String,
        device_id: String,
        open_code_session_id: Option<String>,
        tool: String,
        status: String,
        exit_code: Option<i32>,
    },
    Completed {
        task_id: String,
        device_id: String,
        open_code_session_id: Option<String>,
        duration_ms: u64,
    },
    Failed {
        task_id: String,
        device_id: String,
        open_code_session_id: Option<String>,
        error: String,
    },
    Cancelled {
        task_id: String,
        device_id: String,
        open_code_session_id: Option<String>,
    },
    PermissionRequested {
        task_id: String,
        device_id: String,
        open_code_session_id: Option<String>,
        permission_id: String,
        tool: String,
        action: String,
        target: String,
        patterns: Vec<String>,
        project_path: String,
        risk: String,
        created_at: u64,
        timeout_at: u64,
    },
    PermissionResolved {
        task_id: String,
        device_id: String,
        open_code_session_id: Option<String>,
        permission_id: String,
        decision: String,
        reply: String,
    },
}

impl AiBroadcastEvent {
    pub fn device_id(&self) -> &str {
        match self {
            Self::Created { device_id, .. } => device_id,
            Self::Started { device_id, .. } => device_id,
            Self::Updated { device_id, .. } => device_id,
            Self::Activity { device_id, .. } => device_id,
            Self::Output { device_id, .. } => device_id,
            Self::ResponseChunk { device_id, .. } => device_id,
            Self::ToolStarted { device_id, .. } => device_id,
            Self::ToolFinished { device_id, .. } => device_id,
            Self::Completed { device_id, .. } => device_id,
            Self::Failed { device_id, .. } => device_id,
            Self::Cancelled { device_id, .. } => device_id,
            Self::PermissionRequested { device_id, .. } => device_id,
            Self::PermissionResolved { device_id, .. } => device_id,
        }
    }

    pub fn task_id(&self) -> &str {
        match self {
            Self::Created { task_id, .. } => task_id,
            Self::Started { task_id, .. } => task_id,
            Self::Updated { task_id, .. } => task_id,
            Self::Activity { task_id, .. } => task_id,
            Self::Output { task_id, .. } => task_id,
            Self::ResponseChunk { task_id, .. } => task_id,
            Self::ToolStarted { task_id, .. } => task_id,
            Self::ToolFinished { task_id, .. } => task_id,
            Self::Completed { task_id, .. } => task_id,
            Self::Failed { task_id, .. } => task_id,
            Self::Cancelled { task_id, .. } => task_id,
            Self::PermissionRequested { task_id, .. } => task_id,
            Self::PermissionResolved { task_id, .. } => task_id,
        }
    }
}
