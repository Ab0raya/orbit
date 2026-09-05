export interface NetworkAddress {
  interface_name: string;
  ip: string;
  is_ipv4: boolean;
  is_loopback: boolean;
}

export type TailscaleState = "not_installed" | "needs_login" | "stopped" | "connected";

export interface TailscaleInfo {
  installed: boolean;
  running: boolean;
  state: TailscaleState;
  ip: string | null;
  device_name: string | null;
  tailnet_name?: string | null;
  error: string | null;
}

export interface SystemInfo {
  device_name: string;
  os: string;
  os_version: string;
  arch: string;
  local_ips: NetworkAddress[];
  primary_ip: string | null;
  tailscale?: TailscaleInfo | null;
}

export interface AgentStatus {
  status: "online" | "offline" | string;
  uptime_seconds: number;
  started_at: number;
  connected_devices: number;
  total_clients?: number;
}

export interface ServerInfo {
  port: number;
  is_listening: boolean;
  bind_address: string;
  connected_clients: number;
}

export interface PairingInfo {
  code: string;
  expires_at: number;
  ttl_seconds: number;
  seconds_remaining: number;
  is_expired: boolean;
}

export interface PairedDevice {
  device_id: string;
  name: string;
  platform: string;
  paired_at: number;
  last_seen_at: number;
  connected: boolean;
}
