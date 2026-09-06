use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use std::io::Read;
use std::sync::Arc;
use uuid::Uuid;

use super::platform::{detect_default_shell, validate_cwd, validate_dimensions};
use super::session::TerminalSession;
use crate::protocol::errors::ProtocolError;

pub struct PtySpawner;

impl PtySpawner {
    pub fn spawn_session(
        owner_device_id: &str,
        requested_cwd: Option<&str>,
        cols: Option<u16>,
        rows: Option<u16>,
    ) -> Result<Arc<TerminalSession>, ProtocolError> {
        let (valid_cols, valid_rows) = validate_dimensions(cols, rows)?;
        let valid_cwd = validate_cwd(requested_cwd)?;
        let shell = detect_default_shell();

        let session_id = format!("term_{}", Uuid::new_v4().simple());

        let pty_system = native_pty_system();
        let pair = pty_system
            .openpty(PtySize {
                rows: valid_rows,
                cols: valid_cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| ProtocolError::internal_error(format!("Failed to allocate PTY: {}", e)))?;

        let mut cmd = CommandBuilder::new(&shell);
        cmd.cwd(&valid_cwd);
        cmd.env("TERM", "xterm-256color");
        cmd.env("COLORTERM", "truecolor");

        let child = pair.slave.spawn_command(cmd).map_err(|e| {
            ProtocolError::internal_error(format!("Failed to spawn shell '{}': {}", shell, e))
        })?;

        let writer = pair.master.take_writer().map_err(|e| {
            ProtocolError::internal_error(format!("Failed to take PTY writer: {}", e))
        })?;

        let mut reader = pair.master.try_clone_reader().map_err(|e| {
            ProtocolError::internal_error(format!("Failed to clone PTY reader: {}", e))
        })?;

        let killer = child.clone_killer();

        let session = Arc::new(TerminalSession::new(
            session_id,
            owner_device_id.to_string(),
            valid_cwd,
            shell,
            valid_cols,
            valid_rows,
            writer,
            pair.master,
            killer,
        ));

        session.mark_running();

        // 1. Background Reader Thread
        let reader_session = Arc::clone(&session);
        std::thread::Builder::new()
            .name(format!("pty-read-{}", reader_session.session_id))
            .spawn(move || {
                let mut buffer = [0u8; 4096];
                loop {
                    match reader.read(&mut buffer) {
                        Ok(0) => {
                            // EOF
                            break;
                        }
                        Ok(n) => {
                            let text = String::from_utf8_lossy(&buffer[..n]);
                            reader_session.append_output(&text);
                        }
                        Err(e) => {
                            // Read error or PTY closed
                            if e.kind() != std::io::ErrorKind::Interrupted {
                                break;
                            }
                        }
                    }
                }
            })
            .map_err(|e| {
                ProtocolError::internal_error(format!("Failed to spawn reader thread: {}", e))
            })?;

        // 2. Background Child Process Waiter Thread
        let waiter_session = Arc::clone(&session);
        let mut child = child;
        std::thread::Builder::new()
            .name(format!("pty-wait-{}", waiter_session.session_id))
            .spawn(move || {
                // Wait on child process exit without holding locks
                let exit_code = match child.wait() {
                    Ok(status) => Some(status.exit_code() as i32),
                    Err(_) => None,
                };

                waiter_session.mark_exited(exit_code);
            })
            .map_err(|e| {
                ProtocolError::internal_error(format!("Failed to spawn waiter thread: {}", e))
            })?;

        Ok(session)
    }
}
