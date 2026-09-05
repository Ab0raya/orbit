use crate::agent::tailscale::{TailscaleInfo, TailscaleManager};
use serde::{Deserialize, Serialize};
use std::net::IpAddr;
use std::sync::Arc;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkAddress {
    pub interface_name: String,
    pub ip: String,
    pub is_ipv4: bool,
    pub is_loopback: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemInfo {
    pub device_name: String,
    pub os: String,
    pub os_version: String,
    pub arch: String,
    pub local_ips: Vec<NetworkAddress>,
    pub primary_ip: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tailscale: Option<TailscaleInfo>,
}

pub struct SystemManager {
    tailscale_manager: Arc<TailscaleManager>,
}

impl SystemManager {
    pub fn new() -> Self {
        Self {
            tailscale_manager: Arc::new(TailscaleManager::new()),
        }
    }

    pub fn with_tailscale(tailscale_manager: Arc<TailscaleManager>) -> Self {
        Self { tailscale_manager }
    }

    pub fn tailscale_manager(&self) -> Arc<TailscaleManager> {
        Arc::clone(&self.tailscale_manager)
    }

    pub fn get_info(&self) -> SystemInfo {
        // Device / Hostname
        let device_name = hostname::get()
            .map(|h| h.to_string_lossy().to_string())
            .unwrap_or_else(|_| "Unknown Device".to_string());

        // OS and Architecture
        let os = sysinfo::System::name().unwrap_or_else(|| std::env::consts::OS.to_string());
        let os_version = sysinfo::System::os_version().unwrap_or_else(|| "Unknown".to_string());
        let arch = std::env::consts::ARCH.to_string();

        // Primary local IP
        let primary_ip = local_ip_address::local_ip()
            .ok()
            .map(|ip| ip.to_string());

        // Network interfaces and IP addresses
        let mut local_ips = Vec::new();
        if let Ok(interfaces) = local_ip_address::list_afinet_netifas() {
            for (name, ip) in interfaces {
                let is_ipv4 = matches!(ip, IpAddr::V4(_));
                let is_loopback = ip.is_loopback();
                local_ips.push(NetworkAddress {
                    interface_name: name,
                    ip: ip.to_string(),
                    is_ipv4,
                    is_loopback,
                });
            }
        }

        let tailscale = Some(self.tailscale_manager.get_info());

        SystemInfo {
            device_name,
            os,
            os_version,
            arch,
            local_ips,
            primary_ip,
            tailscale,
        }
    }
}

impl Default for SystemManager {
    fn default() -> Self {
        Self::new()
    }
}

