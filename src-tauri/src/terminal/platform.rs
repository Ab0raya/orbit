use std::path::{Path, PathBuf};
use crate::protocol::errors::ProtocolError;

pub const MIN_COLS: u16 = 20;
pub const MAX_COLS: u16 = 500;
pub const DEFAULT_COLS: u16 = 120;

pub const MIN_ROWS: u16 = 5;
pub const MAX_ROWS: u16 = 200;
pub const DEFAULT_ROWS: u16 = 30;

/// Detects the platform default interactive shell.
pub fn detect_default_shell() -> String {
    #[cfg(target_os = "windows")]
    {
        if let Ok(path) = std::env::var("COMSPEC") {
            if !path.is_empty() {
                return path;
            }
        }
        "powershell.exe".to_string()
    }

    #[cfg(target_os = "macos")]
    {
        if let Ok(shell) = std::env::var("SHELL") {
            if !shell.is_empty() && Path::new(&shell).exists() {
                return shell;
            }
        }
        if Path::new("/bin/zsh").exists() {
            return "/bin/zsh".to_string();
        }
        "/bin/bash".to_string()
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        if let Ok(shell) = std::env::var("SHELL") {
            if !shell.is_empty() && Path::new(&shell).exists() {
                return shell;
            }
        }
        if Path::new("/bin/bash").exists() {
            return "/bin/bash".to_string();
        }
        "/bin/sh".to_string()
    }
}

/// Validates or defaults the requested working directory.
pub fn validate_cwd(requested_cwd: Option<&str>) -> Result<String, ProtocolError> {
    match requested_cwd {
        Some(path_str) if !path_str.trim().is_empty() => {
            let path = PathBuf::from(path_str.trim());
            if !path.exists() {
                return Err(ProtocolError::new(
                    "INVALID_CWD",
                    format!("Path '{}' does not exist.", path_str),
                ));
            }
            if !path.is_dir() {
                return Err(ProtocolError::new(
                    "INVALID_CWD",
                    format!("Path '{}' is not a directory.", path_str),
                ));
            }
            // Return canonicalized or normalized absolute path
            let resolved = path
                .canonicalize()
                .unwrap_or(path)
                .to_string_lossy()
                .to_string();
            Ok(resolved)
        }
        _ => {
            // Default to user home directory
            let home = std::env::var("HOME")
                .ok()
                .map(PathBuf::from)
                .or_else(|| std::env::var("USERPROFILE").ok().map(PathBuf::from))
                .unwrap_or_else(|| PathBuf::from("."));

            let resolved = home
                .canonicalize()
                .unwrap_or(home)
                .to_string_lossy()
                .to_string();
            Ok(resolved)
        }
    }
}

/// Validates terminal dimensions against allowed bounds.
pub fn validate_dimensions(
    cols: Option<u16>,
    rows: Option<u16>,
) -> Result<(u16, u16), ProtocolError> {
    let c = cols.unwrap_or(DEFAULT_COLS);
    let r = rows.unwrap_or(DEFAULT_ROWS);

    if !(MIN_COLS..=MAX_COLS).contains(&c) {
        return Err(ProtocolError::new(
            "INVALID_DIMENSIONS",
            format!(
                "Terminal cols must be between {} and {} (requested: {}).",
                MIN_COLS, MAX_COLS, c
            ),
        ));
    }

    if !(MIN_ROWS..=MAX_ROWS).contains(&r) {
        return Err(ProtocolError::new(
            "INVALID_DIMENSIONS",
            format!(
                "Terminal rows must be between {} and {} (requested: {}).",
                MIN_ROWS, MAX_ROWS, r
            ),
        ));
    }

    Ok((c, r))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_shell_detection() {
        let shell = detect_default_shell();
        assert!(!shell.is_empty());
    }

    #[test]
    fn test_validate_cwd_default() {
        let cwd = validate_cwd(None).expect("Failed to get default cwd");
        assert!(!cwd.is_empty());
        assert!(Path::new(&cwd).is_dir());
    }

    #[test]
    fn test_validate_cwd_valid() {
        let current = std::env::current_dir().unwrap().to_string_lossy().to_string();
        let validated = validate_cwd(Some(&current)).expect("Failed to validate current dir");
        assert_eq!(validated, current);
    }

    #[test]
    fn test_validate_cwd_invalid() {
        let err = validate_cwd(Some("/nonexistent/directory/path/here/12345"))
            .expect_err("Should fail on invalid path");
        assert_eq!(err.code, "INVALID_CWD");
    }

    #[test]
    fn test_dimension_validation() {
        assert!(validate_dimensions(Some(120), Some(30)).is_ok());
        assert!(validate_dimensions(None, None).is_ok());

        let err_cols = validate_dimensions(Some(10), Some(30)).unwrap_err();
        assert_eq!(err_cols.code, "INVALID_DIMENSIONS");

        let err_rows = validate_dimensions(Some(120), Some(2)).unwrap_err();
        assert_eq!(err_rows.code, "INVALID_DIMENSIONS");
    }
}
