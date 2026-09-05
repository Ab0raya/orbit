use std::path::{Path, PathBuf};

/// Find a usable OpenCode binary using the following priority:
/// 1. `OPENCODE_BIN` environment variable override
/// 2. Orbit-managed binary (passed as `managed_path`)
/// 3. System PATH (`opencode` / `opencode.exe`)
/// 4. Legacy mise shim (`~/.local/share/mise/shims/opencode`)
pub fn find_opencode(managed_path: &Path) -> Option<PathBuf> {
    // 1. Explicit override via OPENCODE_BIN env var
    if let Ok(val) = std::env::var("OPENCODE_BIN") {
        let p = PathBuf::from(&val);
        if p.is_file() {
            log::debug!("[OpenCode] Using OPENCODE_BIN override: {:?}", p);
            return Some(p);
        }
        log::warn!(
            "[OpenCode] OPENCODE_BIN is set to '{}' but file does not exist.",
            val
        );
    }

    // 2. Orbit-managed binary
    if managed_path.is_file() {
        log::debug!("[OpenCode] Using managed binary: {:?}", managed_path);
        return Some(managed_path.to_path_buf());
    }

    // 3. System PATH search
    let exe_name = if cfg!(windows) {
        "opencode.exe"
    } else {
        "opencode"
    };

    if let Some(path_os) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&path_os) {
            let candidate = dir.join(exe_name);
            if candidate.is_file() {
                log::debug!("[OpenCode] Found on PATH: {:?}", candidate);
                return Some(candidate);
            }
        }
    }

    // 4. Legacy mise shim (Linux/macOS only)
    #[cfg(unix)]
    {
        if let Ok(home) = std::env::var("HOME") {
            let shim = PathBuf::from(&home).join(".local/share/mise/shims/opencode");
            if shim.is_file() {
                log::debug!("[OpenCode] Found mise shim: {:?}", shim);
                return Some(shim);
            }
            // Also check ~/.bun/bin/opencode (common on some setups)
            let bun_path = PathBuf::from(&home).join(".bun/bin/opencode");
            if bun_path.is_file() {
                log::debug!("[OpenCode] Found bun install: {:?}", bun_path);
                return Some(bun_path);
            }
        }
    }

    log::debug!("[OpenCode] No binary found via any detection strategy.");
    None
}
