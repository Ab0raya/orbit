use std::path::PathBuf;
use std::sync::{Arc, RwLock};
use serde::{Deserialize, Serialize};

pub mod detector;
pub mod installer;

// ============================================================
// OpenCode version to manage. Update this single constant when
// Orbit requires a newer OpenCode version.
// ============================================================
pub const OPENCODE_MANAGED_VERSION: &str = "1.18.29";
pub const OPENCODE_GITHUB_OWNER: &str = "anomalyco";
pub const OPENCODE_GITHUB_REPO: &str = "opencode";

// ============================================================
// Status model
// ============================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum OpencodeStatus {
    Checking,
    Ready {
        version: String,
        path: String,
    },
    Installing {
        #[serde(skip_serializing_if = "Option::is_none")]
        progress: Option<String>,
    },
    Updating {
        #[serde(skip_serializing_if = "Option::is_none")]
        progress: Option<String>,
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
}

// ============================================================
// Manager
// ============================================================

pub struct OpencodeManager {
    status: Arc<RwLock<OpencodeStatus>>,
    /// Platform-native Orbit data directory (set at runtime from tauri::path)
    app_data_dir: PathBuf,
}

impl OpencodeManager {
    /// Create a new manager. `app_data_dir` should come from
    /// `tauri::Manager::path().app_data_dir()`.
    pub fn new(app_data_dir: PathBuf) -> Self {
        Self {
            status: Arc::new(RwLock::new(OpencodeStatus::Checking)),
            app_data_dir,
        }
    }

    /// Managed binary directory: <app_data>/opencode/v<VERSION>/
    pub fn managed_dir(&self) -> PathBuf {
        self.app_data_dir
            .join("opencode")
            .join(format!("v{}", OPENCODE_MANAGED_VERSION))
    }

    /// Full path to the managed binary.
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

    fn set_status(&self, s: OpencodeStatus) {
        let mut guard = self.status.write().unwrap();
        *guard = s;
    }

    /// Run the full detect → install flow. Call this once on startup.
    pub async fn ensure_ready(&self) {
        self.set_status(OpencodeStatus::Checking);

        // 1. Try to find existing binary (env override, managed, system PATH, mise)
        match detector::find_opencode(&self.managed_binary_path()) {
            Some(path) => {
                // Verify it is actually runnable and get version
                match installer::verify_binary(&path).await {
                    Ok(version) => {
                        log::info!(
                            "[OpenCode] Found usable binary at {:?} version {}",
                            path,
                            version
                        );
                        self.set_status(OpencodeStatus::Ready {
                            version,
                            path: path.to_string_lossy().to_string(),
                        });
                        return;
                    }
                    Err(e) => {
                        log::warn!(
                            "[OpenCode] Binary at {:?} failed verification: {}. Will re-install.",
                            path,
                            e
                        );
                    }
                }
            }
            None => {
                log::info!("[OpenCode] No binary found. Installing managed version.");
            }
        }

        // 2. Install
        self.run_install(false).await;
    }

    /// Internal install or update logic.
    async fn run_install(&self, is_update: bool) {
        let target_dir = self.managed_dir();
        let binary_path = self.managed_binary_path();

        let progress_label = if is_update {
            self.set_status(OpencodeStatus::Updating {
                progress: Some("Preparing update…".to_string()),
            });
            "update"
        } else {
            self.set_status(OpencodeStatus::Installing {
                progress: Some("Preparing download…".to_string()),
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
                self.set_status(OpencodeStatus::Error { message: e });
            }
        }
    }

    /// Explicitly trigger an update. Safe to call from UI.
    /// Will no-op if already at managed version.
    pub async fn update(&self) {
        // If already at managed version and binary is fine, skip
        if let OpencodeStatus::Ready { ref version, ref path } = self.status() {
            if version == OPENCODE_MANAGED_VERSION {
                let p = PathBuf::from(path);
                if let Ok(v) = installer::verify_binary(&p).await {
                    if v == OPENCODE_MANAGED_VERSION {
                        log::info!("[OpenCode] Already at managed version {}. No update needed.", OPENCODE_MANAGED_VERSION);
                        return;
                    }
                }
            }
        }
        self.run_install(true).await;
    }

    /// Resolve the binary path to use for spawning OpenCode.
    /// Returns the path if ready, or an error message.
    pub fn resolve_binary_path(&self) -> Result<PathBuf, String> {
        match self.status() {
            OpencodeStatus::Ready { path, .. } => Ok(PathBuf::from(path)),
            OpencodeStatus::Checking => {
                Err("OpenCode is still initializing. Please wait a moment and try again.".to_string())
            }
            OpencodeStatus::Installing { .. } | OpencodeStatus::Updating { .. } => {
                Err("OpenCode is being installed. Please wait for installation to complete.".to_string())
            }
            OpencodeStatus::Error { message } => {
                Err(format!("OpenCode is unavailable: {}", message))
            }
        }
    }
}
