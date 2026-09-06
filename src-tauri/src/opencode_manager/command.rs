use std::path::Path;

/// Win32 process creation flag to prevent console window allocation.
/// When a console-subsystem binary (like OpenCode CLI) is spawned by a GUI application
/// on Windows, Windows allocates a new console window unless `CREATE_NO_WINDOW` is set.
#[cfg(windows)]
pub const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// Create a new `tokio::process::Command` for OpenCode subprocess invocations,
/// configured with `CREATE_NO_WINDOW` on Windows to suppress any console window.
pub fn new_tokio_command<P: AsRef<Path>>(binary_path: P) -> tokio::process::Command {
    let mut cmd = tokio::process::Command::new(binary_path.as_ref());
    configure_tokio_command(&mut cmd);
    cmd
}

/// Apply `CREATE_NO_WINDOW` to a `tokio::process::Command` on Windows.
/// Preserves default platform behavior on Unix/macOS.
pub fn configure_tokio_command(cmd: &mut tokio::process::Command) {
    #[cfg(windows)]
    {
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    #[cfg(not(windows))]
    {
        let _ = cmd;
    }
}

/// Create a new `std::process::Command` for OpenCode subprocess invocations,
/// configured with `CREATE_NO_WINDOW` on Windows to suppress any console window.
pub fn new_std_command<P: AsRef<Path>>(binary_path: P) -> std::process::Command {
    let mut cmd = std::process::Command::new(binary_path.as_ref());
    configure_std_command(&mut cmd);
    cmd
}

/// Apply `CREATE_NO_WINDOW` to a `std::process::Command` on Windows.
/// Preserves default platform behavior on Unix/macOS.
pub fn configure_std_command(cmd: &mut std::process::Command) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    #[cfg(not(windows))]
    {
        let _ = cmd;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[cfg(windows)]
    fn test_create_no_window_constant() {
        assert_eq!(CREATE_NO_WINDOW, 0x0800_0000);
    }

    #[test]
    fn test_new_std_command_executes_and_captures_stdout() {
        let (prog, args) = if cfg!(windows) {
            ("cmd", vec!["/c", "echo", "orbit_hidden_test"])
        } else {
            ("echo", vec!["orbit_hidden_test"])
        };

        let mut cmd = new_std_command(prog);
        cmd.args(&args);
        let output = cmd.output().expect("Failed to execute test command");
        assert!(output.status.success());
        let stdout = String::from_utf8_lossy(&output.stdout);
        assert!(stdout.contains("orbit_hidden_test"));
    }

    #[tokio::test]
    async fn test_new_tokio_command_executes_and_captures_stdout() {
        let (prog, args) = if cfg!(windows) {
            ("cmd", vec!["/c", "echo", "orbit_tokio_hidden_test"])
        } else {
            ("echo", vec!["orbit_tokio_hidden_test"])
        };

        let mut cmd = new_tokio_command(prog);
        cmd.args(&args);
        let output = cmd
            .output()
            .await
            .expect("Failed to execute tokio test command");
        assert!(output.status.success());
        let stdout = String::from_utf8_lossy(&output.stdout);
        assert!(stdout.contains("orbit_tokio_hidden_test"));
    }
}
