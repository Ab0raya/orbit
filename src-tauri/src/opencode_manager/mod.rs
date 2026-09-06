use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::{Arc, RwLock};

pub mod command;
pub mod detector;
pub mod installer;
#[cfg(test)]
pub mod tests;

pub use command::{
    configure_std_command, configure_tokio_command, new_std_command, new_tokio_command,
};

// ============================================================
// Managed OpenCode Configuration
// Update this single constant when Orbit requires a newer version.
// ============================================================
pub const OPENCODE_MANAGED_VERSION: &str = "1.18.29";
pub const OPENCODE_GITHUB_OWNER: &str = "anomalyco";
pub const OPENCODE_GITHUB_REPO: &str = "opencode";

/// Resolve platform-native default Orbit data directory:
/// Windows: `%APPDATA%\Orbit`
/// Unix: `~/.orbit`
pub fn default_app_data_dir() -> PathBuf {
    #[cfg(windows)]
    {
        if let Ok(appdata) = std::env::var("APPDATA") {
            return PathBuf::from(appdata).join("Orbit");
        }
    }

    #[cfg(unix)]
    {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home).join(".orbit");
        }
    }

    if let Ok(userprofile) = std::env::var("USERPROFILE") {
        return PathBuf::from(userprofile).join(".orbit");
    }

    std::env::temp_dir().join("Orbit")
}

// ============================================================
// Status Models
// ============================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum OpencodeStatus {
    Checking,
    Installing {
        #[serde(skip_serializing_if = "Option::is_none")]
        progress: Option<String>,
    },
    Updating {
        #[serde(skip_serializing_if = "Option::is_none")]
        progress: Option<String>,
    },
    Ready {
        version: String,
        path: String,
    },
    Error {
        message: String,
    },
}

impl OpencodeStatus {
    pub fn is_ready(&self) -> bool {
        matches!(self, OpencodeStatus::Ready { .. })
    }

    pub fn ready_path(&self) -> Option<PathBuf> {
        match self {
            OpencodeStatus::Ready { path, .. } => Some(PathBuf::from(path)),
            _ => None,
        }
    }

    /// User-friendly desktop message avoiding technical clutter
    pub fn user_message(&self) -> String {
        match self {
            OpencodeStatus::Checking => "Preparing AI engine...".to_string(),
            OpencodeStatus::Installing { progress } => progress
                .clone()
                .unwrap_or_else(|| "Preparing AI engine...".to_string()),
            OpencodeStatus::Updating { progress } => progress
                .clone()
                .unwrap_or_else(|| "Updating AI engine...".to_string()),
            OpencodeStatus::Ready { .. } => "AI engine ready.".to_string(),
            OpencodeStatus::Error { message } => format!("AI engine error: {}", message),
        }
    }
}

/// DTO for frontend status consumption
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OpencodeStatusPayload {
    pub state: String,
    pub user_message: String,
    pub is_ready: bool,
    pub version: Option<String>,
    pub path: Option<String>,
    pub progress: Option<String>,
    pub error: Option<String>,
}

impl From<&OpencodeStatus> for OpencodeStatusPayload {
    fn from(status: &OpencodeStatus) -> Self {
        match status {
            OpencodeStatus::Checking => Self {
                state: "checking".to_string(),
                user_message: "Preparing AI engine...".to_string(),
                is_ready: false,
                version: None,
                path: None,
                progress: None,
                error: None,
            },
            OpencodeStatus::Installing { progress } => Self {
                state: "installing".to_string(),
                user_message: "Preparing AI engine...".to_string(),
                is_ready: false,
                version: None,
                path: None,
                progress: progress.clone(),
                error: None,
            },
            OpencodeStatus::Updating { progress } => Self {
                state: "updating".to_string(),
                user_message: "Updating AI engine...".to_string(),
                is_ready: false,
                version: None,
                path: None,
                progress: progress.clone(),
                error: None,
            },
            OpencodeStatus::Ready { version, path } => Self {
                state: "ready".to_string(),
                user_message: "AI engine ready.".to_string(),
                is_ready: true,
                version: Some(version.clone()),
                path: Some(path.clone()),
                progress: None,
                error: None,
            },
            OpencodeStatus::Error { message } => Self {
                state: "error".to_string(),
                user_message: "AI engine unavailable.".to_string(),
                is_ready: false,
                version: None,
                path: None,
                progress: None,
                error: Some(message.clone()),
            },
        }
    }
}

// ============================================================
// OpencodeManager
// ============================================================

pub struct OpencodeManager {
    status: Arc<RwLock<OpencodeStatus>>,
    /// Platform data directory (%APPDATA%\Orbit on Windows)
    app_data_dir: PathBuf,
}

impl OpencodeManager {
    /// Create manager with explicit data directory.
    pub fn new(app_data_dir: PathBuf) -> Self {
        Self {
            status: Arc::new(RwLock::new(OpencodeStatus::Checking)),
            app_data_dir,
        }
    }

    /// Create manager using platform default data directory.
    pub fn with_default_dir() -> Self {
        Self::new(default_app_data_dir())
    }

    /// Managed binary directory: `%APPDATA%\Orbit\opencode\v<VERSION>\`
    pub fn managed_dir(&self) -> PathBuf {
        self.app_data_dir
            .join("opencode")
            .join(format!("v{}", OPENCODE_MANAGED_VERSION))
    }

    /// Full path to the managed binary:
    /// Windows: `%APPDATA%\Orbit\opencode\v<VERSION>\opencode.exe`
    pub fn managed_binary_path(&self) -> PathBuf {
        let dir = self.managed_dir();
        if cfg!(windows) {
            dir.join("opencode.exe")
        } else {
            dir.join("opencode")
        }
    }

    pub fn status(&self) -> OpencodeStatus {
        self.status.read().unwrap().clone()
    }

    pub fn status_payload(&self) -> OpencodeStatusPayload {
        OpencodeStatusPayload::from(&self.status())
    }

    pub fn set_status(&self, s: OpencodeStatus) {
        let mut guard = self.status.write().unwrap();
        *guard = s;
    }

    /// Run detection and background provisioning on startup.
    /// Does NOT re-download if a valid managed binary already exists.
    pub async fn ensure_ready(&self) {
        self.set_status(OpencodeStatus::Checking);

        // 1. Check OPENCODE_BIN env override (for development / testing)
        if let Some(env_override) = detector::find_env_override() {
            match installer::verify_binary(&env_override).await {
                Ok(version) => {
                    log::info!(
                        "[OpenCode] OPENCODE_BIN override active at {:?} (version {})",
                        env_override,
                        version
                    );
                    self.set_status(OpencodeStatus::Ready {
                        version,
                        path: env_override.to_string_lossy().to_string(),
                    });
                    return;
                }
                Err(e) => {
                    log::warn!(
                        "[OpenCode] OPENCODE_BIN at {:?} failed verification: {}. Falling back.",
                        env_override,
                        e
                    );
                }
            }
        }

        // 2. Check managed binary at `%APPDATA%\Orbit\opencode\v<VERSION>\opencode.exe`
        let managed_path = self.managed_binary_path();
        if managed_path.is_file() {
            match installer::verify_binary(&managed_path).await {
                Ok(version) => {
                    if version == OPENCODE_MANAGED_VERSION {
                        log::info!(
                            "[OpenCode] Verified existing managed binary at {:?} (v{})",
                            managed_path,
                            version
                        );
                        self.set_status(OpencodeStatus::Ready {
                            version,
                            path: managed_path.to_string_lossy().to_string(),
                        });
                        return;
                    } else {
                        log::warn!(
                            "[OpenCode] Managed binary version mismatch (found '{}', expected '{}'). Will re-install.",
                            version,
                            OPENCODE_MANAGED_VERSION
                        );
                    }
                }
                Err(e) => {
                    log::warn!(
                        "[OpenCode] Managed binary at {:?} failed verification: {}. Will re-install.",
                        managed_path,
                        e
                    );
                }
            }
        } else {
            log::info!(
                "[OpenCode] Managed binary missing at {:?}. Starting automatic background provisioning.",
                managed_path
            );
        }

        // 3. Managed version missing or corrupted: download and install
        self.run_install(false).await;
    }

    /// Internal install/update logic with progress tracking
    async fn run_install(&self, is_update: bool) {
        let target_dir = self.managed_dir();
        let binary_path = self.managed_binary_path();

        let progress_label = if is_update {
            self.set_status(OpencodeStatus::Updating {
                progress: Some("Preparing update...".to_string()),
            });
            "update"
        } else {
            self.set_status(OpencodeStatus::Installing {
                progress: Some("Preparing download...".to_string()),
            });
            "install"
        };

        log::info!("[OpenCode] Starting {} to {:?}", progress_label, target_dir);

        let update_status = {
            let status_arc = Arc::clone(&self.status);
            let is_update = is_update;
            move |msg: String| {
                let mut guard = status_arc.write().unwrap();
                *guard = if is_update {
                    OpencodeStatus::Updating {
                        progress: Some(msg),
                    }
                } else {
                    OpencodeStatus::Installing {
                        progress: Some(msg),
                    }
                };
            }
        };

        match installer::install_opencode(
            OPENCODE_MANAGED_VERSION,
            OPENCODE_GITHUB_OWNER,
            OPENCODE_GITHUB_REPO,
            &target_dir,
            &binary_path,
            update_status,
        )
        .await
        {
            Ok(version) => {
                log::info!("[OpenCode] Installation complete. Version: {}", version);
                self.set_status(OpencodeStatus::Ready {
                    version,
                    path: binary_path.to_string_lossy().to_string(),
                });
            }
            Err(e) => {
                log::error!("[OpenCode] Installation failed: {}", e);

                // Preserve previous working binary if one already exists and is runnable
                if binary_path.is_file() {
                    if let Ok(prev_version) = installer::verify_binary(&binary_path).await {
                        log::info!(
                            "[OpenCode] Preserving previous working binary at {:?} (v{})",
                            binary_path,
                            prev_version
                        );
                        self.set_status(OpencodeStatus::Ready {
                            version: prev_version,
                            path: binary_path.to_string_lossy().to_string(),
                        });
                        return;
                    }
                }

                // Or fallback to system PATH if available
                if let Some(system_path) = detector::find_system_path() {
                    if let Ok(sys_version) = installer::verify_binary(&system_path).await {
                        log::info!(
                            "[OpenCode] Using system PATH fallback at {:?} (v{})",
                            system_path,
                            sys_version
                        );
                        self.set_status(OpencodeStatus::Ready {
                            version: sys_version,
                            path: system_path.to_string_lossy().to_string(),
                        });
                        return;
                    }
                }

                self.set_status(OpencodeStatus::Error { message: e });
            }
        }
    }

    /// Trigger explicit install / retry.
    pub async fn install(&self) {
        self.run_install(false).await;
    }

    /// Trigger explicit update. No-ops if already at managed version.
    pub async fn update(&self) {
        if let OpencodeStatus::Ready {
            ref version,
            ref path,
        } = self.status()
        {
            if version == OPENCODE_MANAGED_VERSION {
                let p = PathBuf::from(path);
                if let Ok(v) = installer::verify_binary(&p).await {
                    if v == OPENCODE_MANAGED_VERSION {
                        log::info!(
                            "[OpenCode] Already at managed version {}. No update needed.",
                            OPENCODE_MANAGED_VERSION
                        );
                        return;
                    }
                }
            }
        }
        self.run_install(true).await;
    }

    /// Resolve the executable path to use for launching OpenCode.
    pub fn resolve_binary_path(&self) -> Result<PathBuf, String> {
        // If ready, return verified path
        if let OpencodeStatus::Ready { ref path, .. } = self.status() {
            return Ok(PathBuf::from(path));
        }

        // Check if OPENCODE_BIN is set
        if let Some(env_override) = detector::find_env_override() {
            return Ok(env_override);
        }

        // Check managed binary on disk
        let managed = self.managed_binary_path();
        if managed.is_file() {
            return Ok(managed);
        }

        // Fallback to system PATH if available
        if let Some(sys) = detector::find_system_path() {
            return Ok(sys);
        }

        match self.status() {
            OpencodeStatus::Checking => Err(
                "OpenCode is still initializing. Please wait a moment and try again.".to_string(),
            ),
            OpencodeStatus::Installing { .. } | OpencodeStatus::Updating { .. } => Err(
                "OpenCode is being installed. Please wait for installation to complete."
                    .to_string(),
            ),
            OpencodeStatus::Error { message } => {
                Err(format!("OpenCode is unavailable: {}", message))
            }
            OpencodeStatus::Ready { path, .. } => Ok(PathBuf::from(path)),
        }
    }
}
