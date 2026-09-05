use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

pub const MAX_PAIRING_ATTEMPTS: usize = 5;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub connection_id: String,
    pub peer_addr: String,
    pub connected_at: u64,
    pub last_activity: u64,
    pub is_paired: bool,
    pub device_id: Option<String>,
    pub device_name: Option<String>,
    pub platform: Option<String>,
    pub failed_pairing_attempts: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PairedDevice {
    pub device_id: String,
    pub name: String,
    pub platform: String,
    pub paired_at: u64,
    pub last_seen_at: u64,
    pub connected: bool,
}

pub struct SessionManager {
    sessions: Arc<RwLock<HashMap<String, Session>>>,
    paired_devices: Arc<RwLock<HashMap<String, PairedDevice>>>,
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

impl SessionManager {
    pub fn new() -> Self {
        #[cfg(not(test))]
        let loaded_devices = {
            let mut map = HashMap::new();
            if let Ok(content) = std::fs::read_to_string(".orbit_paired_devices.json") {
                if let Ok(devices) = serde_json::from_str::<HashMap<String, PairedDevice>>(&content) {
                    for (id, mut dev) in devices {
                        dev.connected = false;
                        map.insert(id, dev);
                    }
                }
            }
            map
        };

        #[cfg(test)]
        let loaded_devices = HashMap::new();

        Self {
            sessions: Arc::new(RwLock::new(HashMap::new())),
            paired_devices: Arc::new(RwLock::new(loaded_devices)),
        }
    }

    pub fn persist_paired_devices(&self) {
        #[cfg(not(test))]
        if let Ok(lock) = self.paired_devices.read() {
            if let Ok(content) = serde_json::to_string_pretty(&*lock) {
                let _ = std::fs::write(".orbit_paired_devices.json", content);
            }
        }
    }

    pub fn create_session(&self, peer_addr: SocketAddr) -> String {
        let connection_id = format!("conn_{}", Uuid::new_v4().simple());
        let now = now_unix();

        let session = Session {
            connection_id: connection_id.clone(),
            peer_addr: peer_addr.to_string(),
            connected_at: now,
            last_activity: now,
            is_paired: false,
            device_id: None,
            device_name: None,
            platform: None,
            failed_pairing_attempts: 0,
        };

        if let Ok(mut lock) = self.sessions.write() {
            lock.insert(connection_id.clone(), session);
        }

        connection_id
    }

    pub fn get_session(&self, connection_id: &str) -> Option<Session> {
        let lock = self.sessions.read().ok()?;
        lock.get(connection_id).cloned()
    }

    pub fn remove_session(&self, connection_id: &str) -> Option<Session> {
        let session = {
            let mut lock = self.sessions.write().ok()?;
            lock.remove(connection_id)
        }?;

        // If this session had a paired device, update device connected status
        if let Some(ref dev_id) = session.device_id {
            if let Ok(mut dev_lock) = self.paired_devices.write() {
                if let Some(dev) = dev_lock.get_mut(dev_id) {
                    // Check if other active sessions exist for this device
                    let other_connected = if let Ok(sess_lock) = self.sessions.read() {
                        sess_lock
                            .values()
                            .any(|s| s.device_id.as_deref() == Some(dev_id))
                    } else {
                        false
                    };

                    dev.connected = other_connected;
                    dev.last_seen_at = now_unix();
                }
            }
            self.persist_paired_devices();
        }

        Some(session)
    }

    pub fn record_activity(&self, connection_id: &str) {
        let now = now_unix();
        if let Ok(mut lock) = self.sessions.write() {
            if let Some(session) = lock.get_mut(connection_id) {
                session.last_activity = now;
            }
        }
    }

    pub fn increment_failed_attempts(&self, connection_id: &str) -> usize {
        if let Ok(mut lock) = self.sessions.write() {
            if let Some(session) = lock.get_mut(connection_id) {
                session.failed_pairing_attempts += 1;
                return session.failed_pairing_attempts;
            }
        }
        0
    }

    pub fn is_rate_limited(&self, connection_id: &str) -> bool {
        if let Ok(lock) = self.sessions.read() {
            if let Some(session) = lock.get(connection_id) {
                return session.failed_pairing_attempts >= MAX_PAIRING_ATTEMPTS;
            }
        }
        false
    }

    pub fn mark_paired(
        &self,
        connection_id: &str,
        device_name: &str,
        platform: &str,
        existing_device_id: Option<&str>,
    ) -> Result<PairedDevice, String> {
        let now = now_unix();
        let device_id = match existing_device_id {
            Some(id) if !id.trim().is_empty() => id.to_string(),
            _ => format!("dev_{}", Uuid::new_v4().simple()),
        };

        // Update session and clean up previous stale sessions for the same deviceId
        {
            let mut lock = self
                .sessions
                .write()
                .map_err(|e| format!("Failed to acquire sessions lock: {}", e))?;

            // Unpair and unbind prior sessions for this device ID to prevent duplicates
            let stale_connections: Vec<String> = lock
                .iter()
                .filter(|(cid, s)| s.device_id.as_deref() == Some(&device_id) && cid.as_str() != connection_id)
                .map(|(cid, _)| cid.clone())
                .collect();

            for stale_cid in stale_connections {
                if let Some(stale_session) = lock.get_mut(&stale_cid) {
                    stale_session.is_paired = false;
                    stale_session.device_id = None;
                }
            }

            let session = lock
                .get_mut(connection_id)
                .ok_or_else(|| format!("Session '{}' not found", connection_id))?;

            session.is_paired = true;
            session.device_id = Some(device_id.clone());
            session.device_name = Some(device_name.to_string());
            session.platform = Some(platform.to_string());
            session.last_activity = now;
            session.failed_pairing_attempts = 0;
        }

        // Register or update in paired_devices
        let paired_device = {
            let mut dev_lock = self
                .paired_devices
                .write()
                .map_err(|e| format!("Failed to acquire devices lock: {}", e))?;

            let dev = dev_lock
                .entry(device_id.clone())
                .and_modify(|d| {
                    d.name = device_name.to_string();
                    d.platform = platform.to_string();
                    d.last_seen_at = now;
                    d.connected = true;
                })
                .or_insert_with(|| PairedDevice {
                    device_id: device_id.clone(),
                    name: device_name.to_string(),
                    platform: platform.to_string(),
                    paired_at: now,
                    last_seen_at: now,
                    connected: true,
                });

            dev.clone()
        };

        self.persist_paired_devices();
        Ok(paired_device)
    }

    pub fn resume_session(
        &self,
        connection_id: &str,
        device_id: &str,
    ) -> Result<PairedDevice, String> {
        let now = now_unix();

        // 1. Verify device exists in paired_devices
        let mut paired_dev = {
            let dev_lock = self
                .paired_devices
                .read()
                .map_err(|e| format!("Failed to acquire devices lock: {}", e))?;
            dev_lock
                .get(device_id)
                .cloned()
                .ok_or_else(|| format!("Device '{}' is not registered as a paired device", device_id))?
        };

        // 2. Associate session and supersede any older connection for this device
        {
            let mut lock = self
                .sessions
                .write()
                .map_err(|e| format!("Failed to acquire sessions lock: {}", e))?;

            let stale_connections: Vec<String> = lock
                .iter()
                .filter(|(cid, s)| s.device_id.as_deref() == Some(device_id) && cid.as_str() != connection_id)
                .map(|(cid, _)| cid.clone())
                .collect();

            for stale_cid in stale_connections {
                if let Some(stale_session) = lock.get_mut(&stale_cid) {
                    stale_session.is_paired = false;
                    stale_session.device_id = None;
                }
            }

            let session = lock
                .get_mut(connection_id)
                .ok_or_else(|| format!("Session '{}' not found", connection_id))?;

            session.is_paired = true;
            session.device_id = Some(device_id.to_string());
            session.device_name = Some(paired_dev.name.clone());
            session.platform = Some(paired_dev.platform.clone());
            session.last_activity = now;
            session.failed_pairing_attempts = 0;
        }

        // 3. Mark device connected
        {
            let mut dev_lock = self
                .paired_devices
                .write()
                .map_err(|e| format!("Failed to acquire devices lock: {}", e))?;
            if let Some(dev) = dev_lock.get_mut(device_id) {
                dev.connected = true;
                dev.last_seen_at = now;
                paired_dev = dev.clone();
            }
        }

        self.persist_paired_devices();
        Ok(paired_dev)
    }

    pub fn is_session_paired(&self, connection_id: &str) -> bool {
        if let Ok(lock) = self.sessions.read() {
            if let Some(session) = lock.get(connection_id) {
                return session.is_paired;
            }
        }
        false
    }

    pub fn get_paired_devices(&self) -> Vec<PairedDevice> {
        if let Ok(lock) = self.paired_devices.read() {
            lock.values().cloned().collect()
        } else {
            Vec::new()
        }
    }

    pub fn connected_clients_count(&self) -> usize {
        if let Ok(lock) = self.sessions.read() {
            lock.len()
        } else {
            0
        }
    }

    pub fn paired_connected_count(&self) -> usize {
        if let Ok(lock) = self.sessions.read() {
            let unique_devs: std::collections::HashSet<_> = lock
                .values()
                .filter(|s| s.is_paired)
                .filter_map(|s| s.device_id.as_deref())
                .collect();
            unique_devs.len()
        } else {
            0
        }
    }

    pub fn paired_devices_total_count(&self) -> usize {
        if let Ok(lock) = self.paired_devices.read() {
            lock.len()
        } else {
            0
        }
    }
}

impl Default for SessionManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{IpAddr, Ipv4Addr};

    #[test]
    fn test_session_lifecycle_and_pairing() {
        let mgr = SessionManager::new();
        let addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 54321);

        let conn_id = mgr.create_session(addr);
        assert_eq!(mgr.connected_clients_count(), 1);
        assert_eq!(mgr.paired_connected_count(), 0);
        assert!(!mgr.is_session_paired(&conn_id));

        // Rate limiting test
        for _ in 0..MAX_PAIRING_ATTEMPTS - 1 {
            mgr.increment_failed_attempts(&conn_id);
            assert!(!mgr.is_rate_limited(&conn_id));
        }
        mgr.increment_failed_attempts(&conn_id);
        assert!(mgr.is_rate_limited(&conn_id));

        // Pair device
        let paired = mgr
            .mark_paired(&conn_id, "iPhone 15 Pro", "ios", None)
            .expect("Failed to pair");
        assert_eq!(paired.name, "iPhone 15 Pro");
        assert_eq!(paired.platform, "ios");
        assert!(paired.connected);
        assert!(mgr.is_session_paired(&conn_id));
        assert_eq!(mgr.paired_connected_count(), 1);

        // Disconnect session
        let removed = mgr.remove_session(&conn_id);
        assert!(removed.is_some());
        assert_eq!(mgr.connected_clients_count(), 0);

        let devices = mgr.get_paired_devices();
        assert_eq!(devices.len(), 1);
        assert!(!devices[0].connected);
    }

    #[test]
    fn test_duplicate_connection_replacement_and_stable_identity() {
        let mgr = SessionManager::new();
        let addr1 = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(192, 168, 1, 10)), 50001);
        let addr2 = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(192, 168, 1, 10)), 50002);

        let conn1 = mgr.create_session(addr1);
        let dev = mgr
            .mark_paired(&conn1, "Pixel 8", "android", Some("dev_pixel_stable"))
            .expect("Pair failed");
        assert_eq!(dev.device_id, "dev_pixel_stable");
        assert_eq!(mgr.paired_connected_count(), 1);
        assert_eq!(mgr.paired_devices_total_count(), 1);

        // Second connection from same deviceId arrives before conn1 is removed
        let conn2 = mgr.create_session(addr2);
        assert_eq!(mgr.connected_clients_count(), 2);

        // Pairing conn2 with the same stable deviceId replaces conn1's session
        let dev2 = mgr
            .mark_paired(&conn2, "Pixel 8", "android", Some("dev_pixel_stable"))
            .expect("Re-pair failed");
        assert_eq!(dev2.device_id, "dev_pixel_stable");

        // Exactly one paired device in registry and exactly 1 active connected device
        assert_eq!(mgr.paired_devices_total_count(), 1);
        assert_eq!(mgr.paired_connected_count(), 1);
        assert!(!mgr.is_session_paired(&conn1), "conn1 should have been superseded");
        assert!(mgr.is_session_paired(&conn2), "conn2 should be active");
    }

    #[test]
    fn test_session_resume_flow() {
        let mgr = SessionManager::new();
        let addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(192, 168, 1, 20)), 50001);

        let conn1 = mgr.create_session(addr);
        let paired = mgr
            .mark_paired(&conn1, "Galaxy S24", "android", Some("dev_galaxy_s24"))
            .expect("Initial pair failed");
        assert_eq!(paired.device_id, "dev_galaxy_s24");

        // Disconnect
        mgr.remove_session(&conn1);
        assert_eq!(mgr.paired_connected_count(), 0);
        assert_eq!(mgr.paired_devices_total_count(), 1);

        // Reconnect on new connection
        let conn2 = mgr.create_session(addr);
        assert!(!mgr.is_session_paired(&conn2));

        // Unknown device ID should fail to resume
        let failed_resume = mgr.resume_session(&conn2, "dev_unknown_id");
        assert!(failed_resume.is_err());
        assert!(!mgr.is_session_paired(&conn2));

        // Known device ID succeeds and restores paired state
        let resumed = mgr
            .resume_session(&conn2, "dev_galaxy_s24")
            .expect("Resume failed");
        assert_eq!(resumed.device_id, "dev_galaxy_s24");
        assert!(resumed.connected);
        assert!(mgr.is_session_paired(&conn2));
        assert_eq!(mgr.paired_connected_count(), 1);
        assert_eq!(mgr.paired_devices_total_count(), 1);
    }
}
