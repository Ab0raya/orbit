use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, RwLock};
use std::time::Instant;
use tokio::net::TcpListener;
use tokio::sync::{broadcast, mpsc};
use tokio_tungstenite::tungstenite::Message;

use crate::agent::handlers::ActionContext;
use crate::agent::pairing::PairingManager;
use crate::agent::router::MessageRouter;
use crate::agent::session::SessionManager;
use crate::agent::system::SystemManager;
use crate::ai::{AiBroadcastEvent, AiTaskManager};
use crate::files::FileManager;
use crate::projects::ProjectManager;
use crate::protocol::events::OrbitEvent;
use crate::scripts::ScriptManager;
use crate::terminal::{TerminalBroadcastEvent, TerminalManager};

pub const DEFAULT_WS_PORT: u16 = 4371;
pub const DEFAULT_BIND_ADDRESS: &str = "0.0.0.0";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerInfo {
    pub port: u16,
    pub is_listening: bool,
    pub bind_address: String,
    pub connected_clients: usize,
}

pub struct OrbitWsServer {
    port: u16,
    bind_address: String,
    is_listening: Arc<AtomicBool>,
    session_manager: Arc<SessionManager>,
    pairing_manager: Arc<RwLock<PairingManager>>,
    system_manager: Arc<SystemManager>,
    terminal_manager: Arc<TerminalManager>,
    file_manager: Arc<FileManager>,
    project_manager: Arc<ProjectManager>,
    ai_task_manager: Arc<AiTaskManager>,
    script_manager: Arc<ScriptManager>,
    start_instant: Instant,
    shutdown_tx: broadcast::Sender<()>,
}

impl OrbitWsServer {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        port: Option<u16>,
        bind_address: Option<String>,
        session_manager: Arc<SessionManager>,
        pairing_manager: Arc<RwLock<PairingManager>>,
        system_manager: Arc<SystemManager>,
        terminal_manager: Arc<TerminalManager>,
        file_manager: Arc<FileManager>,
        project_manager: Arc<ProjectManager>,
        ai_task_manager: Arc<AiTaskManager>,
        script_manager: Arc<ScriptManager>,
        start_instant: Instant,
    ) -> Self {
        let (shutdown_tx, _) = broadcast::channel(1);
        Self {
            port: port.unwrap_or(DEFAULT_WS_PORT),
            bind_address: bind_address.unwrap_or_else(|| DEFAULT_BIND_ADDRESS.to_string()),
            is_listening: Arc::new(AtomicBool::new(false)),
            session_manager,
            pairing_manager,
            system_manager,
            terminal_manager,
            file_manager,
            project_manager,
            ai_task_manager,
            script_manager,
            start_instant,
            shutdown_tx,
        }
    }

    pub fn get_info(&self) -> ServerInfo {
        ServerInfo {
            port: self.port,
            is_listening: self.is_listening.load(Ordering::SeqCst),
            bind_address: self.bind_address.clone(),
            connected_clients: self.session_manager.connected_clients_count(),
        }
    }

    pub fn connected_count(&self) -> usize {
        self.session_manager.connected_clients_count()
    }

    pub async fn start(&self) -> Result<(), String> {
        let addr = format!("{}:{}", self.bind_address, self.port);
        let listener = TcpListener::bind(&addr)
            .await
            .map_err(|e| format!("Failed to bind WebSocket server to {}: {}", addr, e))?;

        self.is_listening.store(true, Ordering::SeqCst);
        let is_listening = Arc::clone(&self.is_listening);
        let mut shutdown_rx = self.shutdown_tx.subscribe();

        let session_manager = Arc::clone(&self.session_manager);
        let pairing_manager = Arc::clone(&self.pairing_manager);
        let system_manager = Arc::clone(&self.system_manager);
        let terminal_manager = Arc::clone(&self.terminal_manager);
        let file_manager = Arc::clone(&self.file_manager);
        let project_manager = Arc::clone(&self.project_manager);
        let ai_task_manager = Arc::clone(&self.ai_task_manager);
        let script_manager = Arc::clone(&self.script_manager);
        let start_instant = self.start_instant;
        let port = self.port;
        let bind_address = self.bind_address.clone();

        tokio::spawn(async move {
            loop {
                tokio::select! {
                    accept_res = listener.accept() => {
                        match accept_res {
                            Ok((stream, peer_addr)) => {
                                let sess_mgr = Arc::clone(&session_manager);
                                let pair_mgr = Arc::clone(&pairing_manager);
                                let sys_mgr = Arc::clone(&system_manager);
                                let term_mgr = Arc::clone(&terminal_manager);
                                let file_mgr = Arc::clone(&file_manager);
                                let proj_mgr = Arc::clone(&project_manager);
                                let ai_mgr = Arc::clone(&ai_task_manager);
                                let script_mgr = Arc::clone(&script_manager);
                                let bind_addr = bind_address.clone();

                                tokio::spawn(async move {
                                    Self::handle_connection(
                                        stream,
                                        peer_addr,
                                        sess_mgr,
                                        pair_mgr,
                                        sys_mgr,
                                        term_mgr,
                                        file_mgr,
                                        proj_mgr,
                                        ai_mgr,
                                        script_mgr,
                                        start_instant,
                                        port,
                                        bind_addr,
                                    ).await;
                                });
                            }
                            Err(e) => {
                                eprintln!("[Orbit WS] Error accepting connection: {}", e);
                            }
                        }
                    }
                    _ = shutdown_rx.recv() => {
                        break;
                    }
                }
            }
            is_listening.store(false, Ordering::SeqCst);
        });

        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    async fn handle_connection(
        stream: tokio::net::TcpStream,
        peer_addr: SocketAddr,
        session_manager: Arc<SessionManager>,
        pairing_manager: Arc<RwLock<PairingManager>>,
        system_manager: Arc<SystemManager>,
        terminal_manager: Arc<TerminalManager>,
        file_manager: Arc<FileManager>,
        project_manager: Arc<ProjectManager>,
        ai_task_manager: Arc<AiTaskManager>,
        script_manager: Arc<ScriptManager>,
        start_instant: Instant,
        port: u16,
        bind_address: String,
    ) {
        match tokio_tungstenite::accept_async(stream).await {
            Ok(ws_stream) => {
                let conn_id = session_manager.create_session(peer_addr);
                println!(
                    "[Orbit WS] Client connected: session '{}' from '{}'",
                    conn_id, peer_addr
                );

                let (mut ws_sender, mut ws_receiver) = ws_stream.split();

                // Channel for outgoing messages to ws_sender
                let (out_tx, mut out_rx) = mpsc::channel::<Message>(256);

                let sender_task = tokio::spawn(async move {
                    while let Some(msg) = out_rx.recv().await {
                        if ws_sender.send(msg).await.is_err() {
                            break;
                        }
                    }
                });

                // Send protocol welcome event
                let welcome_event = OrbitEvent::welcome(env!("CARGO_PKG_VERSION"));
                if let Ok(welcome_str) = serde_json::to_string(&welcome_event) {
                    let _ = out_tx.send(Message::Text(welcome_str)).await;
                }

                // Subscribe to terminal events and stream output for owned sessions
                let mut term_rx = terminal_manager.subscribe_events();
                let sess_mgr_bridge = Arc::clone(&session_manager);
                let conn_id_bridge = conn_id.clone();
                let out_tx_bridge = out_tx.clone();

                let term_forwarder_task = tokio::spawn(async move {
                    while let Ok(event) = term_rx.recv().await {
                        let my_device_id = sess_mgr_bridge
                            .get_session(&conn_id_bridge)
                            .and_then(|s| s.device_id);

                        match event {
                            TerminalBroadcastEvent::Output {
                                session_id,
                                owner_device_id,
                                data,
                            } if my_device_id.as_deref() == Some(&owner_device_id) => {
                                let ev = OrbitEvent::terminal_output(&session_id, &data);
                                if let Ok(json) = serde_json::to_string(&ev) {
                                    if out_tx_bridge.send(Message::Text(json)).await.is_err() {
                                        break;
                                    }
                                }
                            }
                            TerminalBroadcastEvent::Exited {
                                session_id,
                                owner_device_id,
                                exit_code,
                            } if my_device_id.as_deref() == Some(&owner_device_id) => {
                                let ev = OrbitEvent::terminal_exited(&session_id, exit_code);
                                if let Ok(json) = serde_json::to_string(&ev) {
                                    if out_tx_bridge.send(Message::Text(json)).await.is_err() {
                                        break;
                                    }
                                }
                            }
                            _ => {}
                        }
                    }
                });

                // Subscribe to AI task events and stream output for owned tasks
                let mut ai_rx = ai_task_manager.subscribe_events();
                let sess_mgr_ai_bridge = Arc::clone(&session_manager);
                let conn_id_ai_bridge = conn_id.clone();
                let out_tx_ai_bridge = out_tx.clone();

                let ai_forwarder_task = tokio::spawn(async move {
                    while let Ok(event) = ai_rx.recv().await {
                        let my_device_id = sess_mgr_ai_bridge
                            .get_session(&conn_id_ai_bridge)
                            .and_then(|s| s.device_id);

                        if my_device_id.as_deref() == Some(event.device_id()) {
                            let orbit_ev = match event {
                                AiBroadcastEvent::Created {
                                    task_id,
                                    project_path,
                                    agent,
                                    read_only,
                                    ..
                                } => OrbitEvent::ai_task_created(&task_id, &project_path, &agent, read_only),
                                AiBroadcastEvent::Started {
                                    task_id,
                                    open_code_session_id,
                                    ..
                                } => OrbitEvent::ai_task_started(&task_id, open_code_session_id.as_deref()),
                                AiBroadcastEvent::Updated {
                                    task_id,
                                    open_code_session_id,
                                    activity,
                                    ..
                                } => OrbitEvent::ai_task_updated(&task_id, open_code_session_id.as_deref(), &activity),
                                AiBroadcastEvent::Activity {
                                    task_id,
                                    open_code_session_id,
                                    activity,
                                    ..
                                } => OrbitEvent::ai_task_activity(
                                    &task_id,
                                    open_code_session_id.as_deref(),
                                    &activity,
                                ),
                                AiBroadcastEvent::Output {
                                    task_id,
                                    open_code_session_id,
                                    text,
                                    ..
                                } => OrbitEvent::ai_task_output(&task_id, open_code_session_id.as_deref(), &text),
                                AiBroadcastEvent::ResponseChunk {
                                    task_id,
                                    open_code_session_id,
                                    text,
                                    ..
                                } => OrbitEvent::ai_task_response(&task_id, open_code_session_id.as_deref(), &text),
                                AiBroadcastEvent::ToolStarted {
                                    task_id,
                                    open_code_session_id,
                                    tool,
                                    status,
                                    title,
                                    ..
                                } => OrbitEvent::ai_task_tool_started(
                                    &task_id,
                                    open_code_session_id.as_deref(),
                                    &tool,
                                    &status,
                                    title.as_deref(),
                                ),
                                AiBroadcastEvent::ToolFinished {
                                    task_id,
                                    open_code_session_id,
                                    tool,
                                    status,
                                    exit_code,
                                    ..
                                } => OrbitEvent::ai_task_tool_finished(
                                    &task_id,
                                    open_code_session_id.as_deref(),
                                    &tool,
                                    &status,
                                    exit_code,
                                ),
                                AiBroadcastEvent::Completed {
                                    task_id,
                                    open_code_session_id,
                                    duration_ms,
                                    ..
                                } => OrbitEvent::ai_task_completed(
                                    &task_id,
                                    open_code_session_id.as_deref(),
                                    duration_ms,
                                ),
                                AiBroadcastEvent::Failed {
                                    task_id,
                                    open_code_session_id,
                                    error,
                                    ..
                                } => OrbitEvent::ai_task_failed(&task_id, open_code_session_id.as_deref(), &error),
                                AiBroadcastEvent::Cancelled {
                                    task_id,
                                    open_code_session_id,
                                    ..
                                } => OrbitEvent::ai_task_cancelled(&task_id, open_code_session_id.as_deref()),
                                AiBroadcastEvent::PermissionRequested {
                                    task_id,
                                    open_code_session_id,
                                    permission_id,
                                    tool,
                                    action,
                                    target,
                                    patterns,
                                    project_path,
                                    risk,
                                    created_at,
                                    timeout_at,
                                    ..
                                } => OrbitEvent::ai_permission_requested(
                                    &permission_id,
                                    &task_id,
                                    open_code_session_id.as_deref(),
                                    &tool,
                                    &action,
                                    &target,
                                    &patterns,
                                    &project_path,
                                    &risk,
                                    created_at,
                                    timeout_at,
                                ),
                                AiBroadcastEvent::PermissionResolved {
                                    task_id,
                                    open_code_session_id,
                                    permission_id,
                                    decision,
                                    reply,
                                    ..
                                } => OrbitEvent::ai_permission_resolved(
                                    &permission_id,
                                    &task_id,
                                    open_code_session_id.as_deref(),
                                    &decision,
                                    &reply,
                                ),
                            };

                            if let Ok(json) = serde_json::to_string(&orbit_ev) {
                                if out_tx_ai_bridge.send(Message::Text(json)).await.is_err() {
                                    break;
                                }
                            }
                        }
                    }
                });

                // Process incoming messages & route through MessageRouter
                while let Some(msg_result) = ws_receiver.next().await {
                    match msg_result {
                        Ok(Message::Text(text)) => {
                            session_manager.record_activity(&conn_id);

                            let ctx = ActionContext {
                                connection_id: conn_id.clone(),
                                pairing_manager: Arc::clone(&pairing_manager),
                                session_manager: Arc::clone(&session_manager),
                                system_manager: Arc::clone(&system_manager),
                                terminal_manager: Arc::clone(&terminal_manager),
                                file_manager: Arc::clone(&file_manager),
                                project_manager: Arc::clone(&project_manager),
                                ai_task_manager: Arc::clone(&ai_task_manager),
                                script_manager: Arc::clone(&script_manager),
                                uptime_seconds: start_instant.elapsed().as_secs(),
                                server_port: port,
                                bind_address: bind_address.clone(),
                            };

                            let (response, maybe_event) = MessageRouter::route(&text, &ctx).await;

                            // Send response
                            if let Ok(res_str) = serde_json::to_string(&response) {
                                if out_tx.send(Message::Text(res_str)).await.is_err() {
                                    break;
                                }
                            }

                            // If an event was generated (e.g. device.paired, terminal.created), send it
                            if let Some(event) = maybe_event {
                                if let Ok(event_str) = serde_json::to_string(&event) {
                                    if out_tx.send(Message::Text(event_str)).await.is_err() {
                                        break;
                                    }
                                }
                            }
                        }
                        Ok(Message::Ping(payload)) => {
                            if out_tx.send(Message::Pong(payload)).await.is_err() {
                                break;
                            }
                        }
                        Ok(Message::Close(_)) => {
                            break;
                        }
                        Err(e) => {
                            eprintln!(
                                "[Orbit WS] Error on connection '{}' ({}): {}",
                                conn_id, peer_addr, e
                            );
                            break;
                        }
                        _ => {}
                    }
                }

                // Clean up tasks and session
                term_forwarder_task.abort();
                ai_forwarder_task.abort();
                sender_task.abort();
                session_manager.remove_session(&conn_id);
                println!(
                    "[Orbit WS] Client disconnected: session '{}' from '{}'",
                    conn_id, peer_addr
                );
            }
            Err(e) => {
                eprintln!("[Orbit WS] WebSocket handshake failed for {}: {}", peer_addr, e);
            }
        }
    }

    pub fn stop(&self) {
        let _ = self.shutdown_tx.send(());
        self.is_listening.store(false, Ordering::SeqCst);
    }
}
