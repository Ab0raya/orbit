use crate::files::path::{is_within_scopes, normalize_path};
use crate::projects::ProjectManager;
use crate::protocol::errors::ProtocolError;
use std::env;
use std::path::{Component, Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ValidatedAiContext {
    NoContext,
    Directory(PathBuf),
}

/// Checks whether a normalized path points directly to the filesystem root,
/// user home directory root, or a system/credential directory that must never
/// be used as an AI execution context.
pub fn is_sensitive_or_system_dir(path: &Path) -> bool {
    let canonical = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());

    // 1. Filesystem root check
    #[cfg(unix)]
    if canonical == Path::new("/") {
        return true;
    }
    #[cfg(windows)]
    if canonical.parent().is_none() {
        return true;
    }

    // 2. User Home directory directly
    if let Ok(home) = env::var("HOME").or_else(|_| env::var("USERPROFILE")) {
        let home_path = PathBuf::from(&home);
        if let Ok(canon_home) = home_path.canonicalize() {
            if canonical == canon_home {
                return true;
            }
        } else if canonical == home_path {
            return true;
        }
    }

    // 3. System directories (Unix)
    #[cfg(unix)]
    {
        let system_prefixes = [
            "/etc", "/root", "/bin", "/sbin", "/usr", "/var", "/sys", "/proc", "/dev", "/boot",
            "/run",
        ];
        for prefix in &system_prefixes {
            let p = Path::new(prefix);
            if canonical == p || canonical.starts_with(p) {
                return true;
            }
        }
    }

    // 3. System directories (Windows)
    #[cfg(windows)]
    {
        if let Ok(win_dir) = env::var("WINDIR").or_else(|_| env::var("SystemRoot")) {
            let win_path = PathBuf::from(win_dir);
            if canonical.starts_with(&win_path) {
                return true;
            }
        }
    }

    // 4. Credential / sensitive components anywhere in path
    let sensitive_names = [
        ".ssh",
        ".aws",
        ".gnupg",
        ".credentials",
        ".git-credentials",
        ".password-store",
    ];

    for component in canonical.components() {
        if let Component::Normal(os_str) = component {
            let name = os_str.to_string_lossy().to_lowercase();
            if sensitive_names.iter().any(|s| name == *s) {
                return true;
            }
        }
    }

    false
}

/// Validates an AI working directory against Orbit workstation boundaries.
///
/// Rules:
/// - If `raw_path` is empty or `"none"`, returns `ValidatedAiContext::NoContext`.
/// - Normalizes the path without shell expansion.
/// - Rejects system/sensitive directories (root, home root, /etc, /root, ~/.ssh).
/// - Ensures the target exists and is a directory.
/// - Ensures the target is contained within an allowed workstation project/browse root.
/// - Does NOT require Git or project marker files.
pub fn validate_ai_working_directory(
    raw_path: &str,
    project_manager: &ProjectManager,
) -> Result<ValidatedAiContext, ProtocolError> {
    let trimmed = raw_path.trim();
    if trimmed.is_empty() || trimmed.eq_ignore_ascii_case("none") {
        return Ok(ValidatedAiContext::NoContext);
    }

    let normalized = normalize_path(trimmed);

    // Check sensitive / system boundaries
    if is_sensitive_or_system_dir(&normalized) {
        return Err(ProtocolError::project_not_allowed(format!(
            "Path '{}' is a system or sensitive directory and cannot be used as an AI working directory.",
            trimmed
        )));
    }

    // Check existence and directory status
    if !normalized.exists() || !normalized.is_dir() {
        return Err(ProtocolError::project_not_found(format!(
            "Directory not found: '{}'",
            trimmed
        )));
    }

    // Check containment within allowed project browse roots
    let roots = project_manager.allowed_roots();

    if !is_within_scopes(&normalized, &roots) {
        return Err(ProtocolError::project_not_allowed(format!(
            "Path '{}' is outside allowed workstation project roots.",
            trimmed
        )));
    }

    let canonical = normalized.canonicalize().unwrap_or(normalized);
    Ok(ValidatedAiContext::Directory(canonical))
}
