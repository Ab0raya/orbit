pub mod handlers;
pub mod pairing;
pub mod router;
pub mod server;
pub mod session;
pub mod system;
pub mod tailscale;

use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, RwLock};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use self::pairing::{PairingInfo, PairingManager};
use self::server::{OrbitWsServer, ServerInfo, DEFAULT_WS_PORT};
use self::session::{PairedDevice, SessionManager};
use self::system::{SystemInfo, SystemManager};
use self::tailscale::TailscaleInfo;
use crate::ai::AiTaskManager;
use crate::files::FileManager;
use crate::projects::ProjectManager;
use crate::scripts::ScriptManager;
use crate::terminal::TerminalManager;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentStatus {
    pub status: String,
    pub uptime_seconds: u64,
    pub started_at: u64,
    pub connected_devices: usize,
    pub total_clients: usize,
}

pub struct OrbitAgent {
    is_running: Arc<AtomicBool>,
    start_instant: Instant,
    started_at_unix: u64,
    server: Arc<OrbitWsServer>,
    pairing_manager: Arc<RwLock<PairingManager>>,
    session_manager: Arc<SessionManager>,
    system_manager: Arc<SystemManager>,
    terminal_manager: Arc<TerminalManager>,
    file_manager: Arc<FileManager>,
    project_manager: Arc<ProjectManager>,
    opencode_manager: Arc<crate::opencode_manager::OpencodeManager>,
    ai_task_manager: Arc<AiTaskManager>,
    script_manager: Arc<ScriptManager>,
}

impl OrbitAgent {
    pub fn new(ws_port: Option<u16>) -> Self {
        let port = ws_port.unwrap_or(DEFAULT_WS_PORT);
        let started_at_unix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let start_instant = Instant::now();

        let session_manager = Arc::new(SessionManager::new());
        let pairing_manager = Arc::new(RwLock::new(PairingManager::new()));
        let system_manager = Arc::new(SystemManager::new());
        let terminal_manager = Arc::new(TerminalManager::new());
        let file_manager = Arc::new(FileManager::new());
        let project_manager = Arc::new(ProjectManager::new());
        let opencode_manager =
            Arc::new(crate::opencode_manager::OpencodeManager::with_default_dir());
        let ai_task_manager = Arc::new(AiTaskManager::with_opencode_manager(
            Arc::clone(&project_manager),
            Arc::clone(&opencode_manager),
        ));
        let script_manager = Arc::new(
            ScriptManager::new().unwrap_or_else(|e| {
                eprintln!("[Orbit ScriptManager] Warning: failed to init default store: {:?}, falling back to in-memory", e);
                ScriptManager::new_in_memory().expect("In-memory script store initialization failed")
            }),
        );

        let server = Arc::new(OrbitWsServer::new(
            Some(port),
            None,
            Arc::clone(&session_manager),
            Arc::clone(&pairing_manager),
            Arc::clone(&system_manager),
            Arc::clone(&terminal_manager),
            Arc::clone(&file_manager),
            Arc::clone(&project_manager),
            Arc::clone(&ai_task_manager),
            Arc::clone(&script_manager),
            start_instant,
        ));

        Self {
            is_running: Arc::new(AtomicBool::new(false)),
            start_instant,
            started_at_unix,
            server,
            pairing_manager,
            session_manager,
            system_manager,
            terminal_manager,
            file_manager,
            project_manager,
            opencode_manager,
            ai_task_manager,
            script_manager,
        }
    }

    pub async fn start(&self) -> Result<(), String> {
        self.server.start().await?;
        self.is_running.store(true, Ordering::SeqCst);
        Ok(())
    }

    pub fn stop(&self) {
        self.server.stop();
        self.is_running.store(false, Ordering::SeqCst);
    }

    pub fn get_status(&self) -> AgentStatus {
        let running = self.is_running.load(Ordering::SeqCst);
        let uptime_seconds = if running {
            self.start_instant.elapsed().as_secs()
        } else {
            0
        };

        AgentStatus {
            status: if running {
                "online".to_string()
            } else {
                "offline".to_string()
            },
            uptime_seconds,
            started_at: self.started_at_unix,
            connected_devices: self.session_manager.paired_connected_count(),
            total_clients: self.session_manager.connected_clients_count(),
        }
    }

    pub fn get_server_info(&self) -> ServerInfo {
        self.server.get_info()
    }

    pub fn get_pairing_info(&self) -> Result<PairingInfo, String> {
        let manager = self
            .pairing_manager
            .read()
            .map_err(|e| format!("Failed to acquire pairing lock: {}", e))?;
        Ok(manager.get_info())
    }

    pub fn regenerate_pairing_code(&self) -> Result<PairingInfo, String> {
        let mut manager = self
            .pairing_manager
            .write()
            .map_err(|e| format!("Failed to acquire pairing lock: {}", e))?;
        Ok(manager.generate_new_code())
    }

    pub fn get_system_info(&self) -> SystemInfo {
        self.system_manager.get_info()
    }

    pub fn get_tailscale_info(&self) -> TailscaleInfo {
        self.system_manager.tailscale_manager().get_info()
    }

    pub fn refresh_tailscale_info(&self) -> TailscaleInfo {
        self.system_manager.tailscale_manager().refresh()
    }

    pub fn get_paired_devices(&self) -> Vec<PairedDevice> {
        self.session_manager.get_paired_devices()
    }

    pub fn terminal_manager(&self) -> Arc<TerminalManager> {
        Arc::clone(&self.terminal_manager)
    }

    pub fn file_manager(&self) -> Arc<FileManager> {
        Arc::clone(&self.file_manager)
    }

    pub fn project_manager(&self) -> Arc<ProjectManager> {
        Arc::clone(&self.project_manager)
    }

    pub fn ai_task_manager(&self) -> Arc<AiTaskManager> {
        Arc::clone(&self.ai_task_manager)
    }

    pub fn opencode_manager(&self) -> Arc<crate::opencode_manager::OpencodeManager> {
        Arc::clone(&self.opencode_manager)
    }

    pub fn script_manager(&self) -> Arc<ScriptManager> {
        Arc::clone(&self.script_manager)
    }
}
