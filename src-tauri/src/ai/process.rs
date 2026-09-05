use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use tokio::io::BufReader;
use tokio::process::{Child, ChildStdout, Command};

use super::models::AiAgent;
use crate::protocol::errors::ProtocolError;

/// Upper bound for retained stderr text per task (tail-kept).
pub const MAX_STDERR_TAIL_CHARS: usize = 4096;

pub fn find_opencode_binary() -> Result<PathBuf, ProtocolError> {
    // 1. Explicit override via OPENCODE_BIN env var
    if let Ok(val) = std::env::var("OPENCODE_BIN") {
        let p = PathBuf::from(val);
        if p.is_file() {
            return Ok(p);
        }
    }

    // 2. Check system PATH
    if let Some(path_os) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&path_os) {
            let candidate = dir.join("opencode");
            if candidate.is_file() {
                return Ok(candidate);
            }
        }
    }

    // 3. Check user home mise shim fallback (~/.local/share/mise/shims/opencode)
    if let Ok(home) = std::env::var("HOME") {
        let candidate = PathBuf::from(home).join(".local/share/mise/shims/opencode");
        if candidate.is_file() {
            return Ok(candidate);
        }
    }

    Err(ProtocolError::opencode_not_found())
}

pub struct OpenCodeSpawnResult {
    pub child: Child,
    pub stdout_reader: BufReader<ChildStdout>,
    pub pid: Option<u32>,
    /// Tail of the child's stderr output (plain log lines). Read it only
    /// after the child has exited; lines are still mirrored to the server
    /// log as before.
    pub stderr_tail: Arc<Mutex<String>>,
}

pub struct OpenCodeRunner;

impl OpenCodeRunner {
    pub fn spawn(
        binary_path: &Path,
        project_path: &Path,
        prompt: &str,
        agent: AiAgent,
        session_id: Option<&str>,
        model_override: Option<&str>,
    ) -> Result<OpenCodeSpawnResult, ProtocolError> {
        let mut cmd = Command::new(binary_path);

        cmd.current_dir(project_path);
        cmd.arg("run");
        cmd.arg(prompt);
        cmd.arg("--dir");
        cmd.arg(project_path);
        cmd.arg("--agent");
        cmd.arg(agent.as_str());
        cmd.arg("--format");
        cmd.arg("json");
        cmd.arg("--auto");

        let model = model_override
            .map(|s| s.to_string())
            .or_else(|| std::env::var("OPENCODE_MODEL").ok())
            .unwrap_or_else(|| "openrouter/openrouter/free".to_string());
        cmd.arg("-m");
        cmd.arg(model);

        if let Some(s_id) = session_id {
            cmd.arg("--session");
            cmd.arg(s_id);
        }

        // Isolate stdout for NDJSON streaming, pipe stderr to avoid blocking
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::piped());
        cmd.stdin(Stdio::null());

        let mut child = cmd
            .spawn()
            .map_err(|e| ProtocolError::ai_task_failed(format!("Failed to spawn OpenCode: {}", e)))?;

        let pid = child.id();
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| ProtocolError::ai_task_failed("Failed to capture OpenCode stdout"))?;

        // Asynchronously drain stderr to prevent pipe deadlock.
        // Lines are mirrored to the server log AND retained (tail-kept) so
        // task failure reporting can include the real upstream reason.
        let stderr_tail: Arc<Mutex<String>> = Arc::new(Mutex::new(String::new()));
        if let Some(stderr) = child.stderr.take() {
            let tail_clone = Arc::clone(&stderr_tail);
            tokio::spawn(async move {
                use tokio::io::AsyncBufReadExt;
                let mut reader = BufReader::new(stderr);
                let mut line = String::new();
                while let Ok(n) = reader.read_line(&mut line).await {
                    if n == 0 {
                        break;
                    }
                    eprintln!("[OpenCode stderr] {}", line.trim_end());
                    if let Ok(mut guard) = tail_clone.lock() {
                        guard.push_str(&line);
                        if guard.len() > MAX_STDERR_TAIL_CHARS {
                            let excess = guard.len() - MAX_STDERR_TAIL_CHARS;
                            let mut boundary = excess;
                            while !guard.is_char_boundary(boundary) && boundary < guard.len() {
                                boundary += 1;
                            }
                            guard.drain(..boundary);
                        }
                    }
                    line.clear();
                }
            });
        }

        let stdout_reader = BufReader::new(stdout);

        Ok(OpenCodeSpawnResult {
            child,
            stdout_reader,
            pid,
            stderr_tail,
        })
    }

    pub async fn cancel_child(child: &mut Child, pid: Option<u32>) {
        if let Some(p) = pid {
            // Send SIGINT for graceful shutdown
            let _ = std::process::Command::new("kill")
                .args(["-INT", &p.to_string()])
                .status();

            // Allow up to 2 seconds for graceful exit
            let timeout = tokio::time::Duration::from_millis(2000);
            if tokio::time::timeout(timeout, child.wait()).await.is_err() {
                // Force kill if process hasn't exited
                let _ = child.start_kill();
                let _ = child.wait().await;
            }
        } else {
            let _ = child.start_kill();
            let _ = child.wait().await;
        }
    }
}
