use std::path::{Path, PathBuf};

/// Find a usable OpenCode binary using the detection priority:
/// 1. `OPENCODE_BIN` environment variable override (for development & testing)
/// 2. Orbit-managed binary (passed as `managed_path` at `%APPDATA%\Orbit\opencode\v<VERSION>\opencode.exe`)
/// 3. System PATH (`opencode.exe` on Windows / `opencode` on Unix) as an optional fallback
///
/// Production Orbit prefers the managed version over any ambient system PATH binary.
pub fn find_opencode(managed_path: &Path) -> Option<PathBuf> {
    // 1. Explicit override via OPENCODE_BIN env var (for development / testing)
    if let Some(env_override) = find_env_override() {
        log::debug!("[OpenCode] Using OPENCODE_BIN override: {:?}", env_override);
        return Some(env_override);
    }

    // 2. Orbit-managed binary
    if let Some(managed) = find_managed(managed_path) {
        log::debug!("[OpenCode] Using managed binary: {:?}", managed);
        return Some(managed);
    }

    // 3. System PATH search (optional fallback only)
    if let Some(system_bin) = find_system_path() {
        log::debug!("[OpenCode] Found system PATH fallback: {:?}", system_bin);
        return Some(system_bin);
    }

    log::debug!("[OpenCode] No binary found via any detection strategy.");
    None
}

/// Check if the managed binary exists at `managed_path`.
pub fn find_managed(managed_path: &Path) -> Option<PathBuf> {
    if managed_path.is_file() {
        Some(managed_path.to_path_buf())
    } else {
        None
    }
}

/// Check if `OPENCODE_BIN` is set and points to an existing file.
pub fn find_env_override() -> Option<PathBuf> {
    if let Ok(val) = std::env::var("OPENCODE_BIN") {
        let p = PathBuf::from(&val);
        if p.is_file() {
            return Some(p);
        }
        log::warn!(
            "[OpenCode] OPENCODE_BIN is set to '{}' but file does not exist.",
            val
        );
    }
    None
}

/// Check system PATH for `opencode.exe` (Windows) or `opencode` (Unix).
pub fn find_system_path() -> Option<PathBuf> {
    let exe_name = if cfg!(windows) {
        "opencode.exe"
    } else {
        "opencode"
    };

    if let Some(path_os) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&path_os) {
            let candidate = dir.join(exe_name);
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }

    #[cfg(unix)]
    {
        if let Ok(home) = std::env::var("HOME") {
            let shim = PathBuf::from(&home).join(".local/share/mise/shims/opencode");
            if shim.is_file() {
                return Some(shim);
            }
            let bun_path = PathBuf::from(&home).join(".bun/bin/opencode");
            if bun_path.is_file() {
                return Some(bun_path);
            }
        }
    }

    None
}
