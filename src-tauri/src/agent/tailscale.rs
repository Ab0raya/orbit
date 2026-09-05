use serde::{Deserialize, Serialize};
use std::net::IpAddr;
use std::path::Path;
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TailscaleState {
    NotInstalled,
    NeedsLogin,
    Stopped,
    Connected,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TailscaleInfo {
    pub installed: bool,
    pub running: bool,
    pub state: TailscaleState,
    pub ip: Option<String>,
    pub device_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tailnet_name: Option<String>,
    pub error: Option<String>,
}

impl Default for TailscaleInfo {
    fn default() -> Self {
        Self {
            installed: false,
            running: false,
            state: TailscaleState::NotInstalled,
            ip: None,
            device_name: None,
            tailnet_name: None,
            error: None,
        }
    }
}

pub struct TailscaleManager {
    cached: Arc<Mutex<Option<(TailscaleInfo, Instant)>>>,
    cache_ttl: Duration,
}

impl TailscaleManager {
    pub fn new() -> Self {
        Self {
            cached: Arc::new(Mutex::new(None)),
            cache_ttl: Duration::from_secs(4),
        }
    }

    pub fn get_info(&self) -> TailscaleInfo {
        if let Ok(guard) = self.cached.lock() {
            if let Some((info, timestamp)) = &*guard {
                if timestamp.elapsed() < self.cache_ttl {
                    return info.clone();
                }
            }
        }

        let info = Self::detect_status();

        if let Ok(mut guard) = self.cached.lock() {
            *guard = Some((info.clone(), Instant::now()));
        }

        info
    }

    pub fn clear_cache(&self) {
        if let Ok(mut guard) = self.cached.lock() {
            *guard = None;
        }
    }

    pub fn refresh(&self) -> TailscaleInfo {
        self.clear_cache();
        self.get_info()
    }

    fn detect_status() -> TailscaleInfo {
        // 1. Check test mock overrides
        if let Ok(mock_state) = std::env::var("ORBIT_TAILSCALE_MOCK_STATE") {
            let mock_ip = std::env::var("ORBIT_TAILSCALE_MOCK_IP")
                .ok()
                .or_else(|| Some("100.85.12.34".to_string()));
            let mock_device = std::env::var("ORBIT_TAILSCALE_MOCK_DEVICE")
                .ok()
                .or_else(|| Some("orbit-dev.tailnet.ts.net".to_string()));
            let mock_tailnet = std::env::var("ORBIT_TAILSCALE_MOCK_TAILNET")
                .ok()
                .or_else(|| Some("orbit-mesh.ts.net".to_string()));

            match mock_state.trim().to_lowercase().as_str() {
                "connected" => {
                    return TailscaleInfo {
                        installed: true,
                        running: true,
                        state: TailscaleState::Connected,
                        ip: mock_ip,
                        device_name: mock_device,
                        tailnet_name: mock_tailnet,
                        error: None,
                    };
                }
                "needs_login" => {
                    return TailscaleInfo {
                        installed: true,
                        running: true,
                        state: TailscaleState::NeedsLogin,
                        ip: None,
                        device_name: None,
                        tailnet_name: None,
                        error: None,
                    };
                }
                "stopped" => {
                    return TailscaleInfo {
                        installed: true,
                        running: false,
                        state: TailscaleState::Stopped,
                        ip: None,
                        device_name: None,
                        tailnet_name: None,
                        error: None,
                    };
                }
                "not_installed" => {
                    return TailscaleInfo {
                        installed: false,
                        running: false,
                        state: TailscaleState::NotInstalled,
                        ip: None,
                        device_name: None,
                        tailnet_name: None,
                        error: None,
                    };
                }
                _ => {}
            }
        }

        // 2. Find Tailscale executable path
        let binary_path = Self::find_executable();

        // 3. If binary found, query status
        if let Some(bin) = binary_path {
            let status_result = Self::query_cli_status(&bin);
            match status_result {
                Ok(info) => return info,
                Err(err_msg) => {
                    // Daemon might be stopped or connection refused
                    // Check fallback network interface before concluding
                    if let Some(iface_ip) = Self::detect_tailscale_interface() {
                        return TailscaleInfo {
                            installed: true,
                            running: true,
                            state: TailscaleState::Connected,
                            ip: Some(iface_ip),
                            device_name: None,
                            tailnet_name: None,
                            error: None,
                        };
                    }

                    return TailscaleInfo {
                        installed: true,
                        running: false,
                        state: TailscaleState::Stopped,
                        ip: None,
                        device_name: None,
                        tailnet_name: None,
                        error: Some(err_msg),
                    };
                }
            }
        }

        // 4. Fallback: Network interface check without CLI
        if let Some(iface_ip) = Self::detect_tailscale_interface() {
            return TailscaleInfo {
                installed: true,
                running: true,
                state: TailscaleState::Connected,
                ip: Some(iface_ip),
                device_name: None,
                tailnet_name: None,
                error: None,
            };
        }

        // 5. Not installed
        TailscaleInfo {
            installed: false,
            running: false,
            state: TailscaleState::NotInstalled,
            ip: None,
            device_name: None,
            tailnet_name: None,
            error: None,
        }
    }

    fn find_executable() -> Option<String> {
        let common_paths = [
            "/usr/bin/tailscale",
            "/usr/local/bin/tailscale",
            "/bin/tailscale",
            "/snap/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "C:\\Program Files\\Tailscale\\tailscale.exe",
            "C:\\Program Files (x86)\\Tailscale\\tailscale.exe",
        ];

        for path in &common_paths {
            if Path::new(path).exists() {
                return Some(path.to_string());
            }
        }

        // Check PATH via simple test
        if let Ok(output) = Command::new("tailscale").arg("--version").output() {
            if output.status.success() {
                return Some("tailscale".to_string());
            }
        }

        None
    }

    fn query_cli_status(bin: &str) -> Result<TailscaleInfo, String> {
        let output = Command::new(bin)
            .args(["status", "--json"])
            .output()
            .map_err(|e| format!("Failed to execute tailscale status: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!("Tailscale status failed: {}", stderr.trim()));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let parsed: serde_json::Value = serde_json::from_str(&stdout)
            .map_err(|e| format!("Failed to parse tailscale json: {}", e))?;

        let backend_state = parsed["BackendState"].as_str().unwrap_or("NoState");

        match backend_state {
            "Running" => {
                let mut ip = None;
                if let Some(ips) = parsed["Self"]["TailscaleIPs"].as_array() {
                    for val in ips {
                        if let Some(s) = val.as_str() {
                            // Prefer IPv4: Tailscale IPv4 is in 100.64.0.0/10
                            if s.contains('.') {
                                ip = Some(s.to_string());
                                break;
                            }
                        }
                    }
                }

                // Fallback to interface if JSON didn't report IPv4
                if ip.is_none() {
                    ip = Self::detect_tailscale_interface();
                }

                let dns_name = parsed["Self"]["DNSName"]
                    .as_str()
                    .map(|s| s.trim_end_matches('.').to_string())
                    .or_else(|| parsed["Self"]["HostName"].as_str().map(|s| s.to_string()));

                let tailnet_name = parsed["CurrentTailnet"]["Name"]
                    .as_str()
                    .map(|s| s.to_string())
                    .or_else(|| {
                        parsed["MagicDNSSuffix"]
                            .as_str()
                            .map(|s| s.trim_start_matches('.').to_string())
                    });

                Ok(TailscaleInfo {
                    installed: true,
                    running: true,
                    state: TailscaleState::Connected,
                    ip,
                    device_name: dns_name,
                    tailnet_name,
                    error: None,
                })
            }
            "NeedsLogin" => Ok(TailscaleInfo {
                installed: true,
                running: true,
                state: TailscaleState::NeedsLogin,
                ip: None,
                device_name: None,
                tailnet_name: None,
                error: None,
            }),
            "Stopped" | "Starting" | "NoState" => Ok(TailscaleInfo {
                installed: true,
                running: false,
                state: TailscaleState::Stopped,
                ip: None,
                device_name: None,
                tailnet_name: None,
                error: None,
            }),
            other => Ok(TailscaleInfo {
                installed: true,
                running: false,
                state: TailscaleState::Stopped,
                ip: None,
                device_name: None,
                tailnet_name: None,
                error: Some(format!("BackendState: {}", other)),
            }),
        }
    }

    /// Check if a network interface with a Tailscale CGNAT address (100.64.0.0/10) exists
    pub fn detect_tailscale_interface() -> Option<String> {
        if let Ok(interfaces) = local_ip_address::list_afinet_netifas() {
            for (name, ip) in interfaces {
                if let IpAddr::V4(ipv4) = ip {
                    let octets = ipv4.octets();
                    // Tailscale interface name or CGNAT IP range (100.64.0.0 - 100.127.255.255)
                    let is_cgnat = octets[0] == 100 && (64..=127).contains(&octets[1]);
                    let is_ts_name = name.starts_with("tailscale") || name.starts_with("utun");

                    if is_cgnat || (is_ts_name && !ipv4.is_loopback()) {
                        return Some(ipv4.to_string());
                    }
                }
            }
        }
        None
    }
}

impl Default for TailscaleManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tailscale_mock_connected() {
        std::env::set_var("ORBIT_TAILSCALE_MOCK_STATE", "connected");
        std::env::set_var("ORBIT_TAILSCALE_MOCK_IP", "100.64.1.2");
        std::env::set_var("ORBIT_TAILSCALE_MOCK_DEVICE", "my-laptop.ts.net");
        std::env::set_var("ORBIT_TAILSCALE_MOCK_TAILNET", "custom-net.ts.net");

        let manager = TailscaleManager::new();
        let info = manager.get_info();

        assert!(info.installed);
        assert!(info.running);
        assert_eq!(info.state, TailscaleState::Connected);
        assert_eq!(info.ip.as_deref(), Some("100.64.1.2"));
        assert_eq!(info.device_name.as_deref(), Some("my-laptop.ts.net"));
        assert_eq!(info.tailnet_name.as_deref(), Some("custom-net.ts.net"));

        // Test refresh
        let refreshed = manager.refresh();
        assert_eq!(refreshed.state, TailscaleState::Connected);

        std::env::remove_var("ORBIT_TAILSCALE_MOCK_STATE");
        std::env::remove_var("ORBIT_TAILSCALE_MOCK_IP");
        std::env::remove_var("ORBIT_TAILSCALE_MOCK_DEVICE");
        std::env::remove_var("ORBIT_TAILSCALE_MOCK_TAILNET");
    }

    #[test]
    fn test_tailscale_mock_needs_login() {
        std::env::set_var("ORBIT_TAILSCALE_MOCK_STATE", "needs_login");

        let manager = TailscaleManager::new();
        let info = manager.get_info();

        assert!(info.installed);
        assert!(info.running);
        assert_eq!(info.state, TailscaleState::NeedsLogin);
        assert_eq!(info.ip, None);

        std::env::remove_var("ORBIT_TAILSCALE_MOCK_STATE");
    }

    #[test]
    fn test_tailscale_mock_stopped() {
        std::env::set_var("ORBIT_TAILSCALE_MOCK_STATE", "stopped");

        let manager = TailscaleManager::new();
        let info = manager.get_info();

        assert!(info.installed);
        assert!(!info.running);
        assert_eq!(info.state, TailscaleState::Stopped);
        assert_eq!(info.ip, None);

        std::env::remove_var("ORBIT_TAILSCALE_MOCK_STATE");
    }

    #[test]
    fn test_tailscale_mock_not_installed() {
        std::env::set_var("ORBIT_TAILSCALE_MOCK_STATE", "not_installed");

        let manager = TailscaleManager::new();
        let info = manager.get_info();

        assert!(!info.installed);
        assert!(!info.running);
        assert_eq!(info.state, TailscaleState::NotInstalled);
        assert_eq!(info.ip, None);

        std::env::remove_var("ORBIT_TAILSCALE_MOCK_STATE");
    }
}
