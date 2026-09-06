pub mod buffer;
pub mod manager;
pub mod platform;
pub mod pty;
pub mod session;

pub use buffer::RollingBuffer;
pub use manager::{TerminalBroadcastEvent, TerminalManager};
pub use session::{TerminalSession, TerminalSessionSummary, TerminalStatus};

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_terminal_session_lifecycle_and_security() {
        let mgr = TerminalManager::new();

        // 1. Invalid dimensions
        let dim_err = mgr.create_session("dev_1", None, Some(10), Some(24));
        assert!(dim_err.is_err());
        assert_eq!(dim_err.unwrap_err().code, "INVALID_DIMENSIONS");

        // 2. Invalid cwd
        let cwd_err = mgr.create_session(
            "dev_1",
            Some("/nonexistent/random/dir/xyz"),
            Some(80),
            Some(24),
        );
        assert!(cwd_err.is_err());
        assert_eq!(cwd_err.unwrap_err().code, "INVALID_CWD");

        // 3. Valid creation
        let session = mgr
            .create_session("dev_1", None, Some(100), Some(30))
            .expect("Failed to create valid session");
        assert_eq!(session.owner_device_id, "dev_1");

        // 4. Invalid session ID
        let not_found_err = mgr.write_input("term_invalid_id_999", "dev_1", "ls\n");
        assert_eq!(not_found_err.unwrap_err().code, "INVALID_SESSION_ID");

        // 5. Unauthorized access by another device
        let unauth_err = mgr.write_input(&session.session_id, "dev_attacker", "rm -rf /\n");
        assert_eq!(unauth_err.unwrap_err().code, "UNAUTHORIZED");

        // 6. Resize validation
        let resize_dim_err = mgr.resize(&session.session_id, "dev_1", 10, 30);
        assert_eq!(resize_dim_err.unwrap_err().code, "INVALID_DIMENSIONS");

        let resize_ok = mgr.resize(&session.session_id, "dev_1", 120, 35);
        assert!(resize_ok.is_ok());

        // 7. Write input & History buffer
        let write_ok = mgr.write_input(&session.session_id, "dev_1", "echo ORBIT_UNIT_TEST\n");
        assert!(write_ok.is_ok());

        // Wait a short moment for PTY to process echo
        std::thread::sleep(std::time::Duration::from_millis(150));

        let history = mgr
            .get_history(&session.session_id, "dev_1")
            .expect("Failed to get history");
        assert!(history.contains("ORBIT_UNIT_TEST"));

        // 8. Kill session
        let kill_ok = mgr.kill_session(&session.session_id, "dev_1");
        assert!(kill_ok.is_ok());

        let summary = session.to_summary();
        assert_eq!(summary.status, TerminalStatus::Killed);
    }

    #[tokio::test]
    async fn test_terminal_raw_ansi_color_stream() {
        let mgr = TerminalManager::new();
        let session = mgr
            .create_session("dev_ansi", None, Some(80), Some(24))
            .expect("Failed to create session");

        // Execute printf with ANSI escape sequences
        let cmd = "printf '\\033[31mRED\\033[0m \\033[32mGREEN\\033[0m \\033[34mBLUE\\033[0m\\n'\n";
        mgr.write_input(&session.session_id, "dev_ansi", cmd)
            .expect("Failed to write input");

        // Wait briefly for shell to execute and buffer output
        let mut found = false;
        for _ in 0..20 {
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
            if let Ok(history) = mgr.get_history(&session.session_id, "dev_ansi") {
                if history.contains("RED") {
                    found = true;
                    break;
                }
            }
        }
        assert!(
            found,
            "PTY should preserve and stream raw ANSI sequences for emulator consumption"
        );

        let _ = mgr.kill_session(&session.session_id, "dev_ansi");
    }
}
