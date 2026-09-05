import React, { useEffect, useState, useCallback } from "react";
import {
  Activity,
  Laptop,
  HardDrive,
  ChevronRight,
  ShieldAlert,
  Check,
  X,
} from "lucide-react";
import {
  AgentStatus,
  SystemInfo,
  ServerInfo,
  PairingInfo,
  PairedDevice,
  TailscaleInfo,
} from "../types/agent";
import { agentService } from "../services/agentService";
import { Header, AppTab } from "../components/Header";
import { Sidebar } from "../components/Sidebar";
import { PairingCard } from "../components/PairingCard";
import { NetworkCard } from "../components/NetworkCard";
import { ServerCard } from "../components/ServerCard";
import { GlobalAccessCard } from "../components/GlobalAccessCard";
import { TerminalView } from "../components/TerminalView";
import { FileExplorerView } from "../components/FileExplorerView";
import { AiCommandCenterView } from "../components/AiCommandCenterView";
import { AiSettingsView } from "../components/AiSettingsView";
import { ScriptsView } from "../components/ScriptsView";
import { Script } from "../types/script";
import { AiPermissionRequest } from "../types/permission";

export const OverviewPage: React.FC = () => {
  const [activeTab, setActiveTab] = useState<AppTab>("overview");
  const [runningScriptSessionId, setRunningScriptSessionId] = useState<string | null>(null);
  const [runningScriptName, setRunningScriptName] = useState<string | null>(null);
  const [agentStatus, setAgentStatus] = useState<AgentStatus | null>(null);
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [serverInfo, setServerInfo] = useState<ServerInfo | null>(null);
  const [pairingInfo, setPairingInfo] = useState<PairingInfo | null>(null);
  const [tailscaleInfo, setTailscaleInfo] = useState<TailscaleInfo | null>(null);
  const [pairedDevices, setPairedDevices] = useState<PairedDevice[]>([]);
  const [pendingPermissions, setPendingPermissions] = useState<AiPermissionRequest[]>([]);
  const [, setError] = useState<string | null>(null);
  const [isRefreshing, setIsRefreshing] = useState<boolean>(false);
  const [isRegenerating, setIsRegenerating] = useState<boolean>(false);

  const handleRunScript = async (script: Script) => {
    try {
      const cwd = script.workingDirectory || script.projectPath || undefined;
      const session = await agentService.createTerminal(cwd);
      const content = script.content.endsWith("\n") ? script.content : script.content + "\n";
      await agentService.writeTerminalInput(session.sessionId, content);
      setRunningScriptSessionId(session.sessionId);
      setRunningScriptName(script.name);
      setActiveTab("terminal");
    } catch (err) {
      console.error("Failed to run script:", err);
    }
  };

  const fetchAllData = useCallback(async () => {
    try {
      console.log("[Orbit UI] OverviewPage: fetchAllData starting");
      fetch("http://127.0.0.1:9999/stage", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ stage: "Overview fetchAllData starting", time: Date.now() }),
      }).catch(() => {});

      const [status, sys, srv, pair, ts, devices, perms] = await Promise.all([
        agentService.getAgentStatus(),
        agentService.getSystemInfo(),
        agentService.getServerInfo(),
        agentService.getPairingCode(),
        agentService.getTailscaleInfo().catch(() => null),
        agentService.getPairedDevices(),
        agentService.listPendingAiPermissions().catch(() => []),
      ]);

      console.log("[Orbit UI] OverviewPage: fetchAllData finished", { status, sys, srv, pair });
      fetch("http://127.0.0.1:9999/stage", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          stage: "Overview fetchAllData success",
          detail: `Status: ${status?.status}, Devices: ${devices?.length}, Code: ${pair?.code}`,
          time: Date.now(),
        }),
      }).catch(() => {});

      setAgentStatus(status);
      setSystemInfo(sys);
      setServerInfo(srv);
      setPairingInfo(pair);
      setTailscaleInfo(ts);
      setPairedDevices(devices);
      setPendingPermissions(perms);
      setError(null);
    } catch (err) {
      console.error("Failed to load Orbit Agent status:", err);
      fetch("http://127.0.0.1:9999/stage", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ stage: "Overview fetchAllData error", detail: String(err), time: Date.now() }),
      }).catch(() => {});
      setError(typeof err === "string" ? err : "Failed to communicate with Orbit Agent");
    }
  }, []);

  const handleManualRefresh = async () => {
    setIsRefreshing(true);
    await fetchAllData();
    setIsRefreshing(false);
  };

  const handleResolvePermission = async (deviceId: string, permissionId: string, decision: "once" | "always" | "reject") => {
    try {
      await agentService.resolveAiPermission(deviceId, permissionId, decision);
      setPendingPermissions((prev) => prev.filter((p) => p.permissionId !== permissionId));
    } catch (err) {
      console.error("Failed to resolve AI permission:", err);
    }
  };

  const handleRegeneratePairing = async () => {
    setIsRegenerating(true);
    try {
      const newPairing = await agentService.regeneratePairingCode();
      setPairingInfo(newPairing);
    } catch (err) {
      console.error("Failed to regenerate pairing code:", err);
      setError("Failed to regenerate pairing code");
    } finally {
      setIsRegenerating(false);
    }
  };

  useEffect(() => {
    fetchAllData();

    let cleanupReq: (() => void) | undefined;
    let cleanupRes: (() => void) | undefined;

    agentService.onAiPermissionRequested((req) => {
      setPendingPermissions((prev) => {
        if (prev.some((p) => p.permissionId === req.permissionId)) return prev;
        return [...prev, req];
      });
    }).then((unsub) => {
      cleanupReq = unsub;
    }).catch(console.error);

    agentService.onAiPermissionResolved((ev) => {
      setPendingPermissions((prev) => prev.filter((p) => p.permissionId !== ev.permissionId));
    }).then((unsub) => {
      cleanupRes = unsub;
    }).catch(console.error);

    const interval = setInterval(() => {
      Promise.all([
        agentService.getAgentStatus().then(setAgentStatus).catch(() => {}),
        agentService.getPairingCode().then(setPairingInfo).catch(() => {}),
        agentService.getTailscaleInfo().then(setTailscaleInfo).catch(() => {}),
        agentService.getPairedDevices().then(setPairedDevices).catch(() => {}),
        agentService.listPendingAiPermissions().then(setPendingPermissions).catch(() => {}),
      ]);
    }, 1500);

    return () => {
      clearInterval(interval);
      cleanupReq?.();
      cleanupRes?.();
    };
  }, [fetchAllData]);

  const uptimeFormatted = agentStatus
    ? agentService.formatUptime(agentStatus.uptime_seconds)
    : "00:08:22";

  const isOnline = agentStatus?.status === "online" || true;
  const deviceName = systemInfo?.device_name || "Aburaya";
  const osArch = `${systemInfo?.os || "Omarchy"} • ${systemInfo?.arch || "x86_64"}`;
  const connectedCount = agentStatus?.connected_devices ?? 0;

  return (
    <div className="orbit-desktop-window">
      {/* Sidebar Navigation */}
      <Sidebar activeTab={activeTab} onSelectTab={setActiveTab} />

      {/* Main App Viewport */}
      <div className="orbit-main-viewport">
        {/* Top bar */}
        <Header
          agentOnline={isOnline}
          onRefreshAll={handleManualRefresh}
          isRefreshing={isRefreshing}
          activeTab={activeTab}
          onSelectTab={setActiveTab}
        />

        {/* Workstation Canvas Area */}
        <main className="orbit-content-canvas">
          {/* Active AI Permission Banner */}
          {pendingPermissions.length > 0 && (
            <div className="orbit-permission-banner">
              <div className="permission-banner-left">
                <ShieldAlert size={18} className="permission-shield-icon" />
                <div className="permission-banner-info">
                  <span className="permission-banner-title">
                    AI PERMISSION REQUIRED {pendingPermissions.length > 1 ? `(${pendingPermissions.length})` : ""}
                  </span>
                  <span className="permission-banner-desc">
                    <strong>{pendingPermissions[0].tool}</strong> wants to run <code>{pendingPermissions[0].target}</code>
                    <span className="permission-waiting-tag">— Waiting for mobile approval...</span>
                  </span>
                </div>
              </div>
              <div className="permission-banner-actions">
                <button
                  className="permission-btn-deny"
                  onClick={() => handleResolvePermission(pendingPermissions[0].deviceId, pendingPermissions[0].permissionId, "reject")}
                >
                  <X size={13} />
                  <span>Deny</span>
                </button>
                <button
                  className="permission-btn-allow"
                  onClick={() => handleResolvePermission(pendingPermissions[0].deviceId, pendingPermissions[0].permissionId, "once")}
                >
                  <Check size={13} />
                  <span>Allow</span>
                </button>
              </div>
            </div>
          )}

          {activeTab === "terminal" ? (
            <TerminalView
              initialSessionId={runningScriptSessionId}
              runningScriptName={runningScriptName}
              onClearRunningScript={() => setRunningScriptName(null)}
            />
          ) : activeTab === "scripts" ? (
            <ScriptsView onRunScript={handleRunScript} />
          ) : activeTab === "files" ? (
            <FileExplorerView />
          ) : activeTab === "ai" ? (
            <AiCommandCenterView onOpenSettings={() => setActiveTab("settings")} />
          ) : activeTab === "settings" ? (
            <AiSettingsView onBack={() => setActiveTab("ai")} />
          ) : (
            <div className="overview-scroll-container">
              {/* Headline & Top 3 Metrics Row */}
              <div className="overview-hero-row">
                {/* Hero Editorial Headline */}
                <div className="overview-headline-section">
                  <h1 className="overview-hero-headline">
                    Keep Your<br />
                    Dev Environment<br />
                    Online.<span className="headline-dot">•</span>
                  </h1>
                  <p className="overview-hero-subtitle font-mono">
                    Connect. Develop. Deploy. Anywhere.
                  </p>
                </div>

                {/* Top 3 Metric Cards */}
                <div className="overview-metrics-grid">
                  {/* Card 1: AGENT UPTIME */}
                  <div className="metric-card">
                    <div className="metric-card-header">
                      <div className="metric-header-left">
                        <Activity size={14} className="metric-icon" />
                        <span className="metric-header-label">AGENT UPTIME</span>
                      </div>
                      <span className="metric-status-pill">Online</span>
                    </div>
                    <div className="metric-main-value font-mono">{uptimeFormatted}</div>
                    <div className="metric-sub-value font-mono">
                      Started {agentStatus?.started_at ? new Date(agentStatus.started_at * 1000).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' }) : "4:17:01 PM"}
                    </div>
                  </div>

                  {/* Card 2: DEVICE */}
                  <div className="metric-card">
                    <div className="metric-card-header">
                      <div className="metric-header-left">
                        <Laptop size={14} className="metric-icon" />
                        <span className="metric-header-label">DEVICE</span>
                      </div>
                      <ChevronRight size={14} className="metric-chevron" />
                    </div>
                    <div className="metric-main-value">{deviceName}</div>
                    <div className="metric-sub-value font-mono">{osArch}</div>
                  </div>

                  {/* Card 3: WEBSOCKET SERVER */}
                  <div className="metric-card">
                    <div className="metric-card-header">
                      <div className="metric-header-left">
                        <HardDrive size={14} className="metric-icon" />
                        <span className="metric-header-label">WEBSOCKET SERVER</span>
                      </div>
                      <span className="metric-status-pill">Listening</span>
                    </div>
                    <div className="metric-main-value font-mono">Port {serverInfo?.port || 4371}</div>
                    <div className="metric-sub-value font-mono">{connectedCount} connected device(s)</div>
                  </div>
                </div>
              </div>

              {/* Middle Section: Pairing Code & QR Hero Card */}
              <PairingCard
                pairingInfo={pairingInfo}
                onRegenerate={handleRegeneratePairing}
                isRegenerating={isRegenerating}
                primaryIp={systemInfo?.primary_ip}
                tailscaleIp={tailscaleInfo?.ip}
                port={serverInfo?.port}
              />

              {/* Bottom Row: WebSocket Server, Local Network & Global Access Cards */}
              <div className="overview-bottom-grid">
                <ServerCard
                  serverInfo={serverInfo}
                  connectedDevices={connectedCount}
                  pairedDevices={pairedDevices}
                  totalClients={agentStatus?.total_clients ?? 0}
                />

                <NetworkCard
                  primaryIp={systemInfo?.primary_ip || null}
                  interfaces={systemInfo?.local_ips || []}
                />

                <GlobalAccessCard
                  tailscaleInfo={tailscaleInfo}
                  serverPort={serverInfo?.port}
                  onRefresh={async () => {
                    const ts = await agentService.getTailscaleInfo(true);
                    setTailscaleInfo(ts);
                  }}
                />
              </div>
            </div>
          )}
        </main>
      </div>
    </div>
  );
};
