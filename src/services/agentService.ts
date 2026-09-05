import { invoke, isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
  AgentStatus,
  SystemInfo,
  ServerInfo,
  PairingInfo,
  TailscaleInfo,
} from "../types/agent";

export const isTauriEnvironment = (): boolean => {
  if (typeof window === "undefined") return false;
  try {
    return isTauri() || "__TAURI_INTERNALS__" in window;
  } catch {
    return false;
  }
};

export const agentService = {
  async getAgentStatus(): Promise<AgentStatus> {
    if (!isTauriEnvironment()) {
      return {
        status: "online",
        uptime_seconds: 42,
        started_at: Math.floor(Date.now() / 1000) - 42,
        connected_devices: 0,
      };
    }
    return await invoke<AgentStatus>("get_agent_status");
  },

  async getSystemInfo(): Promise<SystemInfo> {
    if (!isTauriEnvironment()) {
      const hostname = typeof window !== "undefined" ? window.location.hostname : "127.0.0.1";
      const detectedIp = hostname && hostname !== "localhost" && hostname !== "127.0.0.1" ? hostname : "192.168.100.4";
      return {
        device_name: "Developer-PC",
        os: "Linux",
        os_version: "Omarchy 4.0",
        arch: "x86_64",
        local_ips: [
          {
            interface_name: "wlan0",
            ip: detectedIp,
            is_ipv4: true,
            is_loopback: false,
          },
        ],
        primary_ip: detectedIp,
      };
    }
    return await invoke<SystemInfo>("get_system_info");
  },

  async getTailscaleInfo(refresh = false): Promise<TailscaleInfo> {
    if (!isTauriEnvironment()) {
      // In browser preview, query local daemon WebSocket if available, else return real default
      try {
        return await new Promise<TailscaleInfo>((resolve) => {
          const ws = new WebSocket("ws://127.0.0.1:4371");
          const timer = setTimeout(() => {
            try { ws.close(); } catch {}
            resolve({
              installed: false,
              running: false,
              state: "not_installed",
              ip: null,
              device_name: null,
              tailnet_name: null,
              error: null,
            });
          }, 800);
          ws.onopen = () => {
            ws.send(
              JSON.stringify({
                id: "ts_query_" + Date.now(),
                type: "request",
                action: "tailscale.info",
                payload: { refresh },
              })
            );
          };
          ws.onmessage = (event) => {
            try {
              const data = JSON.parse(event.data);
              if (data.action === "tailscale.info" && data.payload) {
                clearTimeout(timer);
                ws.close();
                resolve(data.payload as TailscaleInfo);
              }
            } catch {
              // ignore
            }
          };
          ws.onerror = () => {
            clearTimeout(timer);
            resolve({
              installed: false,
              running: false,
              state: "not_installed",
              ip: null,
              device_name: null,
              tailnet_name: null,
              error: null,
            });
          };
        });
      } catch {
        return {
          installed: false,
          running: false,
          state: "not_installed",
          ip: null,
          device_name: null,
          tailnet_name: null,
          error: null,
        };
      }
    }
    return refresh
      ? await invoke<TailscaleInfo>("refresh_tailscale_info")
      : await invoke<TailscaleInfo>("get_tailscale_info");
  },

  async openTailscale(url?: string): Promise<void> {
    if (!isTauriEnvironment()) {
      window.open(url || "https://login.tailscale.com", "_blank", "noopener,noreferrer");
      return;
    }
    await invoke("open_tailscale", { url });
  },

  async testConnection(
    ip: string,
    port = 4371
  ): Promise<{ success: boolean; latencyMs?: number; message?: string }> {
    const startTime = performance.now();
    try {
      return await new Promise((resolve) => {
        const ws = new WebSocket(`ws://${ip}:${port}`);
        const timeout = setTimeout(() => {
          try { ws.close(); } catch {}
          resolve({
            success: false,
            message: `Connection to ${ip}:${port} timed out after 3000ms`,
          });
        }, 3000);

        ws.onopen = () => {
          const latency = Math.round(performance.now() - startTime);
          clearTimeout(timeout);
          ws.close();
          resolve({ success: true, latencyMs: latency });
        };

        ws.onerror = () => {
          clearTimeout(timeout);
          resolve({
            success: false,
            message: `Unable to reach Orbit WebSocket at ${ip}:${port}`,
          });
        };
      });
    } catch (e: any) {
      return { success: false, message: e.message || "Network error" };
    }
  },

  async getServerInfo(): Promise<ServerInfo> {
    if (!isTauriEnvironment()) {
      return {
        port: 4371,
        is_listening: true,
        bind_address: "0.0.0.0",
        connected_clients: 0,
      };
    }
    return await invoke<ServerInfo>("get_server_info");
  },

  async getPairingCode(): Promise<PairingInfo> {
    if (!isTauriEnvironment()) {
      return {
        code: "842917",
        expires_at: Math.floor(Date.now() / 1000) + 540,
        ttl_seconds: 600,
        seconds_remaining: 540,
        is_expired: false,
      };
    }
    return await invoke<PairingInfo>("get_pairing_code");
  },

  async regeneratePairingCode(): Promise<PairingInfo> {
    if (!isTauriEnvironment()) {
      const randomCode = Math.floor(100000 + Math.random() * 900000).toString();
      return {
        code: randomCode,
        expires_at: Math.floor(Date.now() / 1000) + 600,
        ttl_seconds: 600,
        seconds_remaining: 600,
        is_expired: false,
      };
    }
    return await invoke<PairingInfo>("regenerate_pairing_code");
  },

  async getPairedDevices(): Promise<import("../types/agent").PairedDevice[]> {
    if (!isTauriEnvironment()) {
      return [];
    }
    return await invoke<import("../types/agent").PairedDevice[]>("get_paired_devices");
  },

  async createTerminal(cwd?: string, cols?: number, rows?: number): Promise<import("../types/protocol").TerminalSessionSummary> {
    if (!isTauriEnvironment()) {
      return {
        sessionId: "term_mock_" + Math.random().toString(36).substring(2, 8),
        status: "running",
        cwd: cwd || "/home/developer",
        shell: "/bin/bash",
        rows: rows || 30,
        cols: cols || 120,
        createdAt: Math.floor(Date.now() / 1000),
        lastActivityAt: Math.floor(Date.now() / 1000),
        ownerDeviceId: "orbit_desktop_local",
      };
    }
    return await invoke<import("../types/protocol").TerminalSessionSummary>("create_terminal", { cwd, cols, rows });
  },

  async listTerminals(): Promise<import("../types/protocol").TerminalSessionSummary[]> {
    if (!isTauriEnvironment()) {
      return [];
    }
    return await invoke<import("../types/protocol").TerminalSessionSummary[]>("list_terminals");
  },

  async killTerminal(sessionId: string): Promise<void> {
    if (!isTauriEnvironment()) {
      return;
    }
    await invoke("kill_terminal", { sessionId });
  },

  async getTerminalHistory(sessionId: string): Promise<string> {
    if (!isTauriEnvironment()) {
      return "Mock terminal output\n$ echo Hello Orbit\nHello Orbit\n";
    }
    return await invoke<string>("get_terminal_history", { sessionId });
  },

  async writeTerminalInput(sessionId: string, data: string): Promise<void> {
    if (!isTauriEnvironment()) {
      return;
    }
    await invoke("write_terminal_input", { sessionId, data });
  },

  async resizeTerminal(sessionId: string, cols: number, rows: number): Promise<void> {
    if (!isTauriEnvironment()) {
      return;
    }
    await invoke("resize_terminal", { sessionId, cols, rows });
  },

  async onTerminalOutput(callback: (payload: { sessionId: string; data: string }) => void): Promise<() => void> {
    if (!isTauriEnvironment()) {
      return () => {};
    }
    return await listen<{ sessionId: string; data: string }>("terminal-output", (event) => {
      callback(event.payload);
    });
  },

  async onTerminalExited(callback: (payload: { sessionId: string; exitCode?: number }) => void): Promise<() => void> {
    if (!isTauriEnvironment()) {
      return () => {};
    }
    return await listen<{ sessionId: string; exitCode?: number }>("terminal-exited", (event) => {
      callback(event.payload);
    });
  },

  async getFileRoots(): Promise<import("../types/files").FileRoot[]> {
    if (!isTauriEnvironment()) {
      return [{ name: "Home", path: "/home/developer" }];
    }
    return await invoke<import("../types/files").FileRoot[]>("get_file_roots");
  },

  async listDirectory(path: string): Promise<import("../types/files").FileListResult> {
    if (!isTauriEnvironment()) {
      return { path, entries: [] };
    }
    return await invoke<import("../types/files").FileListResult>("list_directory", { path });
  },

  async readFile(path: string): Promise<import("../types/files").FileReadResult> {
    if (!isTauriEnvironment()) {
      return { path, content: "# Welcome to Orbit\n\nOrbit remote development daemon.\n\n```bash\nflutter analyze\n```\n", encoding: "utf8", size: 68 };
    }
    return await invoke<import("../types/files").FileReadResult>("read_file", { path });
  },

  async searchFiles(
    root: string,
    query: string,
    mode: "name" | "content",
    maxResults?: number
  ): Promise<import("../types/files").FileSearchResult> {
    if (!isTauriEnvironment()) {
      return { root, query, mode, totalMatches: 0, truncated: false, results: [] };
    }
    return await invoke<import("../types/files").FileSearchResult>("search_files", { root, query, mode, maxResults });
  },

  async listPendingAiPermissions(): Promise<import("../types/permission").AiPermissionRequest[]> {
    if (!isTauriEnvironment()) {
      return [];
    }
    return await invoke<import("../types/permission").AiPermissionRequest[]>("list_pending_ai_permissions");
  },

  async resolveAiPermission(
    deviceId: string,
    permissionId: string,
    decision: string
  ): Promise<import("../types/permission").AiPermissionRequest> {
    if (!isTauriEnvironment()) {
      throw new Error("Tauri not available");
    }
    return await invoke<import("../types/permission").AiPermissionRequest>("resolve_ai_permission", {
      deviceId,
      permissionId,
      decision,
    });
  },

  async onAiPermissionRequested(
    callback: (payload: import("../types/permission").AiPermissionRequest) => void
  ): Promise<() => void> {
    if (!isTauriEnvironment()) {
      return () => {};
    }
    return await listen<import("../types/permission").AiPermissionRequest>("ai-permission-requested", (event) => {
      callback(event.payload);
    });
  },

  async onAiPermissionResolved(
    callback: (payload: { permissionId: string; decision: string; reply: string }) => void
  ): Promise<() => void> {
    if (!isTauriEnvironment()) {
      return () => {};
    }
    return await listen<{ permissionId: string; decision: string; reply: string }>("ai-permission-resolved", (event) => {
      callback(event.payload);
    });
  },

  formatUptime(totalSeconds: number): string {
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    const pad = (n: number) => n.toString().padStart(2, "0");
    return `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`;
  },

  formatRemainingTime(seconds: number): string {
    if (seconds <= 0) return "Expired";
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}m ${secs.toString().padStart(2, "0")}s remaining`;
  },

  async listScripts(projectPath?: string): Promise<import("../types/script").Script[]> {
    if (!isTauriEnvironment()) {
      const stored = localStorage.getItem("orbit_mock_scripts");
      const list: import("../types/script").Script[] = stored ? JSON.parse(stored) : [];
      if (projectPath) {
        return list.filter((s) => s.projectPath === projectPath || !s.projectPath);
      }
      return list;
    }
    return await invoke<import("../types/script").Script[]>("list_scripts", { projectPath });
  },

  async getScript(id: string): Promise<import("../types/script").Script | null> {
    if (!isTauriEnvironment()) {
      const stored = localStorage.getItem("orbit_mock_scripts");
      const list: import("../types/script").Script[] = stored ? JSON.parse(stored) : [];
      return list.find((s) => s.id === id) || null;
    }
    return await invoke<import("../types/script").Script | null>("get_script", { id });
  },

  async saveScript(script: import("../types/script").ScriptInput): Promise<import("../types/script").Script> {
    if (!isTauriEnvironment()) {
      const stored = localStorage.getItem("orbit_mock_scripts");
      const list: import("../types/script").Script[] = stored ? JSON.parse(stored) : [];
      const now = Math.floor(Date.now() / 1000);
      let updated: import("../types/script").Script;
      if (script.id) {
        const idx = list.findIndex((s) => s.id === script.id);
        if (idx >= 0) {
          updated = {
            ...list[idx],
            name: script.name,
            description: script.description,
            content: script.content,
            workingDirectory: script.workingDirectory,
            projectPath: script.projectPath,
            updatedAt: now,
          };
          list[idx] = updated;
        } else {
          updated = {
            id: script.id,
            name: script.name,
            description: script.description,
            content: script.content,
            workingDirectory: script.workingDirectory,
            projectPath: script.projectPath,
            createdAt: now,
            updatedAt: now,
          };
          list.unshift(updated);
        }
      } else {
        updated = {
          id: "script_" + Math.random().toString(36).substring(2, 9),
          name: script.name,
          description: script.description,
          content: script.content,
          workingDirectory: script.workingDirectory,
          projectPath: script.projectPath,
          createdAt: now,
          updatedAt: now,
        };
        list.unshift(updated);
      }
      localStorage.setItem("orbit_mock_scripts", JSON.stringify(list));
      return updated;
    }
    return await invoke<import("../types/script").Script>("save_script", { script });
  },

  async deleteScript(id: string): Promise<boolean> {
    if (!isTauriEnvironment()) {
      const stored = localStorage.getItem("orbit_mock_scripts");
      const list: import("../types/script").Script[] = stored ? JSON.parse(stored) : [];
      const filtered = list.filter((s) => s.id !== id);
      localStorage.setItem("orbit_mock_scripts", JSON.stringify(filtered));
      return true;
    }
    return await invoke<boolean>("delete_script", { id });
  },
};
