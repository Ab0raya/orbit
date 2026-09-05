use portable_pty::{ChildKiller, MasterPty};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::broadcast;

use super::buffer::RollingBuffer;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum TerminalStatus {
    Starting,
    Running,
    Exited,
    Killed,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TerminalSessionSummary {
    #[serde(rename = "sessionId")]
    pub session_id: String,
    pub status: TerminalStatus,
    pub cwd: String,
    pub shell: String,
    pub rows: u16,
    pub cols: u16,
    #[serde(rename = "createdAt")]
    pub created_at: u64,
    #[serde(rename = "lastActivityAt")]
    pub last_activity_at: u64,
    #[serde(rename = "exitCode", skip_serializing_if = "Option::is_none")]
    pub exit_code: Option<i32>,
    #[serde(rename = "ownerDeviceId")]
    pub owner_device_id: String,
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub struct TerminalSession {
    pub session_id: String,
    pub owner_device_id: String,
    pub status: Arc<RwLock<TerminalStatus>>,
    pub exit_code: Arc<RwLock<Option<i32>>>,
    pub cwd: String,
    pub shell: String,
    pub rows: Arc<RwLock<u16>>,
    pub cols: Arc<RwLock<u16>>,
    pub created_at: u64,
    pub last_activity_at: Arc<RwLock<u64>>,
    pub writer: Arc<Mutex<Box<dyn std::io::Write + Send>>>,
    pub master: Arc<Mutex<Box<dyn MasterPty + Send>>>,
    pub killer: Arc<Mutex<Box<dyn ChildKiller + Send + Sync>>>,
    pub history_buffer: Arc<RwLock<RollingBuffer>>,
    pub output_tx: broadcast::Sender<String>,
}

impl std::fmt::Debug for TerminalSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TerminalSession")
            .field("session_id", &self.session_id)
            .field("owner_device_id", &self.owner_device_id)
            .field("cwd", &self.cwd)
            .field("shell", &self.shell)
            .finish()
    }
}

impl Drop for TerminalSession {
    fn drop(&mut self) {
        if let Ok(mut killer_guard) = self.killer.lock() {
            let _ = killer_guard.kill();
        }
    }
}

impl TerminalSession {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        session_id: String,
        owner_device_id: String,
        cwd: String,
        shell: String,
        cols: u16,
        rows: u16,
        writer: Box<dyn std::io::Write + Send>,
        master: Box<dyn MasterPty + Send>,
        killer: Box<dyn ChildKiller + Send + Sync>,
    ) -> Self {
        let now = now_unix();
        let (output_tx, _) = broadcast::channel(512);

        Self {
            session_id,
            owner_device_id,
            status: Arc::new(RwLock::new(TerminalStatus::Starting)),
            exit_code: Arc::new(RwLock::new(None)),
            cwd,
            shell,
            rows: Arc::new(RwLock::new(rows)),
            cols: Arc::new(RwLock::new(cols)),
            created_at: now,
            last_activity_at: Arc::new(RwLock::new(now)),
            writer: Arc::new(Mutex::new(writer)),
            master: Arc::new(Mutex::new(master)),
            killer: Arc::new(Mutex::new(killer)),
            history_buffer: Arc::new(RwLock::new(RollingBuffer::default())),
            output_tx,
        }
    }

    pub fn to_summary(&self) -> TerminalSessionSummary {
        let status = self
            .status
            .read()
            .map(|s| s.clone())
            .unwrap_or(TerminalStatus::Failed);
        let exit_code = self.exit_code.read().ok().and_then(|c| *c);
        let rows = self.rows.read().ok().map(|r| *r).unwrap_or(30);
        let cols = self.cols.read().ok().map(|c| *c).unwrap_or(120);
        let last_activity_at = self.last_activity_at.read().ok().map(|t| *t).unwrap_or(0);

        TerminalSessionSummary {
            session_id: self.session_id.clone(),
            status,
            cwd: self.cwd.clone(),
            shell: self.shell.clone(),
            rows,
            cols,
            created_at: self.created_at,
            last_activity_at,
            exit_code,
            owner_device_id: self.owner_device_id.clone(),
        }
    }

    pub fn mark_running(&self) {
        if let Ok(mut s) = self.status.write() {
            *s = TerminalStatus::Running;
        }
    }

    pub fn mark_exited(&self, code: Option<i32>) {
        if let Ok(mut s) = self.status.write() {
            *s = TerminalStatus::Exited;
        }
        if let Ok(mut c) = self.exit_code.write() {
            *c = code;
        }
    }

    pub fn mark_killed(&self) {
        if let Ok(mut s) = self.status.write() {
            *s = TerminalStatus::Killed;
        }
    }

    pub fn record_activity(&self) {
        if let Ok(mut t) = self.last_activity_at.write() {
            *t = now_unix();
        }
    }

    pub fn write_input(&self, data: &str) -> Result<(), String> {
        self.record_activity();
        let mut writer_guard = self
            .writer
            .lock()
            .map_err(|e| format!("Failed to lock terminal writer: {}", e))?;

        use std::io::Write;
        writer_guard
            .write_all(data.as_bytes())
            .map_err(|e| format!("Failed to write to terminal stdin: {}", e))?;
        writer_guard
            .flush()
            .map_err(|e| format!("Failed to flush terminal stdin: {}", e))?;

        Ok(())
    }

    pub fn resize(&self, cols: u16, rows: u16) -> Result<(), String> {
        self.record_activity();
        let master_guard = self
            .master
            .lock()
            .map_err(|e| format!("Failed to lock master PTY: {}", e))?;

        master_guard
            .resize(portable_pty::PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| format!("Failed to resize PTY: {}", e))?;

        if let Ok(mut c) = self.cols.write() {
            *c = cols;
        }
        if let Ok(mut r) = self.rows.write() {
            *r = rows;
        }

        Ok(())
    }

    pub fn kill(&self) -> Result<(), String> {
        self.record_activity();
        self.mark_killed();
        let mut killer_guard = self
            .killer
            .lock()
            .map_err(|e| format!("Failed to lock child killer: {}", e))?;

        killer_guard
            .kill()
            .map_err(|e| format!("Failed to kill child process: {}", e))?;

        Ok(())
    }

    pub fn append_output(&self, text: &str) {
        if let Ok(mut buf) = self.history_buffer.write() {
            buf.append(text.as_bytes());
        }
        // Broadcast output to any active listeners (subscribers)
        let _ = self.output_tx.send(text.to_string());
    }

    pub fn get_history(&self) -> String {
        if let Ok(buf) = self.history_buffer.read() {
            buf.get_history()
        } else {
            String::new()
        }
    }
}
