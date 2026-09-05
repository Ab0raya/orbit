use orbit_desktop_lib::agent::OrbitAgent;
use std::sync::Arc;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let agent = Arc::new(OrbitAgent::new(None));
    println!("[Orbit Daemon] Starting Orbit Agent on port 4371...");
    agent.start().await?;
    let pairing_info = agent.get_pairing_info()?;
    let sys_info = agent.get_system_info();
    let host = sys_info.primary_ip.unwrap_or_else(|| "127.0.0.1".to_string());
    let ts_info = agent.get_tailscale_info();
    let ts_param = if let (true, Some(ip)) = (ts_info.running, ts_info.ip.as_ref()) {
        format!("&ts_host={}", ip)
    } else {
        String::new()
    };
    println!("[Orbit Daemon] Agent listening on port 4371.");
    println!("[Orbit Daemon] Pairing Code: {}", pairing_info.code);
    println!("[Orbit Daemon] Pairing URI:  orbit://pair/v1?host={}&port=4371&code={}&expires={}{}", host, pairing_info.code, pairing_info.expires_at * 1000, ts_param);
    println!("[Orbit Daemon] Press Ctrl+C to stop.");
    tokio::signal::ctrl_c().await?;
    println!("[Orbit Daemon] Stopping agent...");
    agent.stop();
    Ok(())
}
