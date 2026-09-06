use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use tokio::sync::broadcast;

use super::platform::validate_dimensions;
use super::pty::PtySpawner;
use super::session::{TerminalSession, TerminalSessionSummary};
use crate::protocol::errors::ProtocolError;

#[derive(Debug, Clone)]
pub enum TerminalBroadcastEvent {
    Created {
        session_id: String,
        owner_device_id: String,
    },
    Output {
        session_id: String,
        owner_device_id: String,
        data: String,
    },
    Exited {
        session_id: String,
        owner_device_id: String,
        exit_code: Option<i32>,
    },
}

pub struct TerminalManager {
    sessions: Arc<RwLock<HashMap<String, Arc<TerminalSession>>>>,
    event_tx: broadcast::Sender<TerminalBroadcastEvent>,
}

impl TerminalManager {
    pub fn new() -> Self {
        let (event_tx, _) = broadcast::channel(1024);
        Self {
            sessions: Arc::new(RwLock::new(HashMap::new())),
            event_tx,
        }
    }

    pub fn subscribe_events(&self) -> broadcast::Receiver<TerminalBroadcastEvent> {
        self.event_tx.subscribe()
    }

    pub fn create_session(
        &self,
        owner_device_id: &str,
        requested_cwd: Option<&str>,
        cols: Option<u16>,
        rows: Option<u16>,
    ) -> Result<Arc<TerminalSession>, ProtocolError> {
        let session = PtySpawner::spawn_session(owner_device_id, requested_cwd, cols, rows)?;
        let session_id = session.session_id.clone();
        let owner_id = owner_device_id.to_string();

        // Broadcast created event
        let _ = self.event_tx.send(TerminalBroadcastEvent::Created {
            session_id: session_id.clone(),
            owner_device_id: owner_id.clone(),
        });

        // Bridge session output to manager event broadcaster
        let mut output_rx = session.output_tx.subscribe();
        let event_tx_clone = self.event_tx.clone();
        let s_id = session_id.clone();
        let o_id = owner_id.clone();

        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            handle.spawn(async move {
                while let Ok(data) = output_rx.recv().await {
                    let _ = event_tx_clone.send(TerminalBroadcastEvent::Output {
                        session_id: s_id.clone(),
                        owner_device_id: o_id.clone(),
                        data,
                    });
                }
            });
        }

        if let Ok(mut map) = self.sessions.write() {
            map.insert(session_id, Arc::clone(&session));
        }

        Ok(session)
    }

    pub fn get_session_with_ownership(
        &self,
        session_id: &str,
        owner_device_id: &str,
    ) -> Result<Arc<TerminalSession>, ProtocolError> {
        let session = {
            let map = self.sessions.read().map_err(|e| {
                ProtocolError::internal_error(format!("Failed to lock sessions: {}", e))
            })?;
            map.get(session_id).cloned().ok_or_else(|| {
                ProtocolError::new(
                    "INVALID_SESSION_ID",
                    format!("Terminal session '{}' not found.", session_id),
                )
            })?
        };

        if session.owner_device_id != owner_device_id {
            return Err(ProtocolError::unauthorized(
                "You do not own this terminal session.",
            ));
        }

        Ok(session)
    }

    pub fn write_input(
        &self,
        session_id: &str,
        owner_device_id: &str,
        data: &str,
    ) -> Result<(), ProtocolError> {
        let session = self.get_session_with_ownership(session_id, owner_device_id)?;
        session.write_input(data).map_err(|e| {
            ProtocolError::internal_error(format!("Failed to write to terminal: {}", e))
        })
    }

    pub fn resize(
        &self,
        session_id: &str,
        owner_device_id: &str,
        cols: u16,
        rows: u16,
    ) -> Result<(), ProtocolError> {
        let (valid_cols, valid_rows) = validate_dimensions(Some(cols), Some(rows))?;
        let session = self.get_session_with_ownership(session_id, owner_device_id)?;
        session
            .resize(valid_cols, valid_rows)
            .map_err(|e| ProtocolError::internal_error(format!("Failed to resize terminal: {}", e)))
    }

    pub fn kill_session(
        &self,
        session_id: &str,
        owner_device_id: &str,
    ) -> Result<(), ProtocolError> {
        let session = self.get_session_with_ownership(session_id, owner_device_id)?;
        session.kill().map_err(|e| {
            ProtocolError::internal_error(format!("Failed to kill terminal: {}", e))
        })?;

        // Broadcast exited event
        let _ = self.event_tx.send(TerminalBroadcastEvent::Exited {
            session_id: session_id.to_string(),
            owner_device_id: owner_device_id.to_string(),
            exit_code: Some(-1),
        });

        // Remove killed session from map so it is no longer returned in list_sessions
        if let Ok(mut map) = self.sessions.write() {
            map.remove(session_id);
        }

        Ok(())
    }

    pub fn get_history(
        &self,
        session_id: &str,
        owner_device_id: &str,
    ) -> Result<String, ProtocolError> {
        let session = self.get_session_with_ownership(session_id, owner_device_id)?;
        Ok(session.get_history())
    }

    pub fn list_sessions(&self, owner_device_id: &str) -> Vec<TerminalSessionSummary> {
        if let Ok(map) = self.sessions.read() {
            map.values()
                .filter(|s| s.owner_device_id == owner_device_id)
                .map(|s| s.to_summary())
                .collect()
        } else {
            Vec::new()
        }
    }

    pub fn list_all_sessions(&self) -> Vec<TerminalSessionSummary> {
        if let Ok(map) = self.sessions.read() {
            map.values().map(|s| s.to_summary()).collect()
        } else {
            Vec::new()
        }
    }

    pub fn get_session_by_id(&self, session_id: &str) -> Option<Arc<TerminalSession>> {
        if let Ok(map) = self.sessions.read() {
            map.get(session_id).cloned()
        } else {
            None
        }
    }
}

impl Default for TerminalManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_terminal_manager_creation_and_ownership() {
        let mgr = TerminalManager::new();
        let session = mgr
            .create_session("dev_user_1", None, Some(80), Some(24))
            .expect("Failed to create session");

        assert_eq!(session.owner_device_id, "dev_user_1");

        // Verify valid owner can access
        assert!(mgr
            .get_session_with_ownership(&session.session_id, "dev_user_1")
            .is_ok());

        // Verify unauthorized device cannot access
        let err = mgr.get_session_with_ownership(&session.session_id, "dev_intruder");
        assert!(err.is_err());
        assert_eq!(err.unwrap_err().code, "UNAUTHORIZED");

        // Verify listing matches owner
        let list1 = mgr.list_sessions("dev_user_1");
        assert_eq!(list1.len(), 1);
        assert_eq!(list1[0].session_id, session.session_id);

        let list2 = mgr.list_sessions("dev_intruder");
        assert_eq!(list2.len(), 0);

        // Clean up
        let _ = mgr.kill_session(&session.session_id, "dev_user_1");
    }
}
