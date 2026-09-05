import React, { useState } from "react";
import {
  Globe,
  AlertTriangle,
  ExternalLink,
  RefreshCw,
  Sliders,
  Radio,
  HelpCircle,
} from "lucide-react";
import { TailscaleInfo } from "../types/agent";
import { agentService } from "../services/agentService";
import { GlobalAccessModal } from "./GlobalAccessModal";

interface GlobalAccessCardProps {
  tailscaleInfo: TailscaleInfo | null;
  serverPort?: number;
  onRefresh?: () => Promise<void> | void;
}

export const GlobalAccessCard: React.FC<GlobalAccessCardProps> = ({
  tailscaleInfo,
  serverPort = 4371,
  onRefresh,
}) => {
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [testResult, setTestResult] = useState<{
    testing: boolean;
    success?: boolean;
    latencyMs?: number;
    message?: string;
  }>({ testing: false });

  const isConnected = tailscaleInfo?.state === "connected" && !!tailscaleInfo?.ip;
  const isNeedsLogin = tailscaleInfo?.state === "needs_login";
  const isStopped = tailscaleInfo?.state === "stopped";
  const isNotInstalled =
    !tailscaleInfo || tailscaleInfo.state === "not_installed" || !tailscaleInfo.installed;
  const isError = !isConnected && !isNeedsLogin && !isNotInstalled && !!tailscaleInfo?.error;

  const handleRefresh = async (e?: React.MouseEvent) => {
    if (e) e.stopPropagation();
    setIsRefreshing(true);
    try {
      if (onRefresh) {
        await onRefresh();
      } else {
        await agentService.getTailscaleInfo(true);
      }
    } finally {
      setTimeout(() => setIsRefreshing(false), 400);
    }
  };

  const handleInstallClick = (e: React.MouseEvent) => {
    e.stopPropagation();
    agentService.openTailscale("https://tailscale.com/download");
  };

  const handleSignInClick = (e: React.MouseEvent) => {
    e.stopPropagation();
    agentService.openTailscale("https://login.tailscale.com");
  };

  const handleOpenTailscale = (e: React.MouseEvent) => {
    e.stopPropagation();
    agentService.openTailscale("https://login.tailscale.com/admin/machines");
  };

  const handleTestConnection = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!tailscaleInfo?.ip) return;
    setTestResult({ testing: true });
    const res = await agentService.testConnection(tailscaleInfo.ip, serverPort);
    setTestResult({
      testing: false,
      success: res.success,
      latencyMs: res.latencyMs,
      message: res.message,
    });
  };

  return (
    <>
      <div className={`orbit-network-card global-access-card ${isConnected ? "card-ready-glow" : ""}`}>
        {/* Header */}
        <div className="network-card-header">
          <div className="network-card-header-left">
            <Globe size={16} className="network-header-icon" />
            <span className="network-header-title">GLOBAL ACCESS</span>
          </div>

          <div className="tailscale-status-badge">
            {isConnected ? (
              <span className="global-status-pill status-ready">
                <span className="status-dot green-dot" />
                <span>Ready</span>
              </span>
            ) : isNotInstalled ? (
              <span className="global-status-pill status-not-configured">
                <span className="status-dot circle-dot" />
                <span>Not configured</span>
              </span>
            ) : isNeedsLogin ? (
              <span className="global-status-pill status-setup">
                <AlertTriangle size={11} />
                <span>Action required</span>
              </span>
            ) : isStopped ? (
              <span className="global-status-pill status-setup">
                <AlertTriangle size={11} />
                <span>Daemon stopped</span>
              </span>
            ) : (
              <span className="global-status-pill status-error">
                <span className="status-dot red-dot" />
                <span>Connection problem</span>
              </span>
            )}
          </div>
        </div>

        {/* STATE A: NOT INSTALLED */}
        {isNotInstalled && (
          <div className="global-access-content state-not-installed">
            <p className="global-setup-desc">
              Access this workstation from anywhere. Orbit uses Tailscale for a private
              remote connection without port forwarding.
            </p>

            <div className="global-status-kv-box">
              <div className="kv-row">
                <span className="kv-key">Tailscale:</span>
                <span className="kv-val font-mono text-muted">Not installed</span>
              </div>
            </div>

            <div className="global-how-it-works-box">
              <div className="how-it-works-title">
                <HelpCircle size={12} />
                <span>How it works:</span>
              </div>
              <ol className="how-it-works-steps">
                <li>Install Tailscale</li>
                <li>Sign in on this PC</li>
                <li>Sign in on your phone</li>
                <li>Orbit detects the connection automatically</li>
              </ol>
            </div>

            <div className="global-card-actions">
              <button
                onClick={handleInstallClick}
                className="global-action-btn primary-action-btn"
                title="Download Tailscale installer"
              >
                <ExternalLink size={13} />
                <span>Install Tailscale</span>
              </button>
              <button
                onClick={() => setIsModalOpen(true)}
                className="global-action-btn secondary-action-btn"
                title="Open Global Access setup guide"
              >
                <Sliders size={13} />
                <span>Set up</span>
              </button>
              <button
                onClick={handleRefresh}
                disabled={isRefreshing}
                className="global-action-btn icon-action-btn"
                title="Check again"
              >
                <RefreshCw size={13} className={isRefreshing ? "spin-animation" : ""} />
              </button>
            </div>
          </div>
        )}

        {/* STATE B: INSTALLED BUT NOT LOGGED IN / STOPPED */}
        {(isNeedsLogin || (isStopped && !isError)) && (
          <div className="global-access-content state-action-required">
            <p className="global-setup-desc">
              {isNeedsLogin
                ? "Tailscale is installed but this PC is not connected to a Tailnet."
                : "Tailscale daemon is stopped. Connect or start Tailscale to enable global access."}
            </p>

            <div className="global-status-kv-box">
              <div className="kv-row">
                <span className="kv-key">Tailscale:</span>
                <span className="kv-val font-mono text-ready">Installed</span>
              </div>
              <div className="kv-row">
                <span className="kv-key">Status:</span>
                <span className="kv-val font-mono text-warn">
                  {isNeedsLogin ? "Authentication required" : "Service stopped"}
                </span>
              </div>
            </div>

            <div className="global-card-actions">
              {isNeedsLogin ? (
                <button
                  onClick={handleSignInClick}
                  className="global-action-btn primary-action-btn"
                  title="Sign in to your Tailnet"
                >
                  <ExternalLink size={13} />
                  <span>Sign in to Tailscale</span>
                </button>
              ) : (
                <button
                  onClick={handleSignInClick}
                  className="global-action-btn primary-action-btn"
                  title="Start or connect Tailscale"
                >
                  <ExternalLink size={13} />
                  <span>Connect Tailscale</span>
                </button>
              )}
              <button
                onClick={handleRefresh}
                disabled={isRefreshing}
                className="global-action-btn secondary-action-btn"
                title="Retry checking status"
              >
                <RefreshCw size={13} className={isRefreshing ? "spin-animation" : ""} />
                <span>{isRefreshing ? "Checking..." : "Retry"}</span>
              </button>
              <button
                onClick={() => setIsModalOpen(true)}
                className="global-action-btn secondary-action-btn"
                title="Open setup details"
              >
                <Sliders size={13} />
                <span>Set up</span>
              </button>
            </div>
          </div>
        )}

        {/* STATE C: CONNECTED / READY */}
        {isConnected && (
          <div className="global-access-content state-ready">
            <div className="global-ready-banner">
              <span className="ready-subtext">Private remote access via Tailscale</span>
              <span className="network-primary-value font-mono highlight-ip">
                {tailscaleInfo.ip}
              </span>
              <span className="ready-caption">Phone can connect from anywhere</span>
            </div>

            <div className="global-status-kv-box">
              <div className="kv-row">
                <span className="kv-key">Tailscale:</span>
                <span className="kv-val font-mono text-ready">Connected</span>
              </div>
              {tailscaleInfo.device_name && (
                <div className="kv-row">
                  <span className="kv-key">Device:</span>
                  <span className="kv-val font-mono text-white">{tailscaleInfo.device_name}</span>
                </div>
              )}
              {tailscaleInfo.tailnet_name && (
                <div className="kv-row">
                  <span className="kv-key">Tailnet:</span>
                  <span className="kv-val font-mono text-secondary">
                    {tailscaleInfo.tailnet_name}
                  </span>
                </div>
              )}
            </div>

            {/* Test Connection Live Ping Row */}
            <div className="connection-test-row">
              <button
                onClick={handleTestConnection}
                disabled={testResult.testing}
                className="test-connection-mini-btn"
                title="Verify WebSocket reachability on Tailscale IP"
              >
                <Radio size={12} className={testResult.testing ? "spin-animation" : ""} />
                <span>{testResult.testing ? "Testing..." : "Test Connection"}</span>
              </button>
              {testResult.success === true && (
                <span className="test-verified-text font-mono">
                  ✓ Verified ({testResult.latencyMs}ms)
                </span>
              )}
              {testResult.success === false && (
                <span className="test-failed-text font-mono">
                  ✕ {testResult.message || "Unreachable"}
                </span>
              )}
            </div>

            <div className="global-card-actions">
              <button
                onClick={handleOpenTailscale}
                className="global-action-btn secondary-action-btn"
                title="Open Tailscale admin/machines"
              >
                <ExternalLink size={13} />
                <span>Open Tailscale</span>
              </button>
              <button
                onClick={() => setIsModalOpen(true)}
                className="global-action-btn primary-action-btn"
                title="Manage Global Access configuration"
              >
                <Sliders size={13} />
                <span>Manage</span>
              </button>
              <button
                onClick={handleRefresh}
                disabled={isRefreshing}
                className="global-action-btn icon-action-btn"
                title="Check again"
              >
                <RefreshCw size={13} className={isRefreshing ? "spin-animation" : ""} />
              </button>
            </div>
          </div>
        )}

        {/* STATE D: CONNECTION ERROR / UNAVAILABLE */}
        {isError && (
          <div className="global-access-content state-error">
            <p className="global-setup-desc">
              Tailscale is installed but currently unavailable.
            </p>

            {tailscaleInfo?.error && (
              <div className="error-detail-box font-mono">
                {tailscaleInfo.error}
              </div>
            )}

            <div className="global-card-actions">
              <button
                onClick={handleRefresh}
                disabled={isRefreshing}
                className="global-action-btn primary-action-btn"
                title="Retry checking status"
              >
                <RefreshCw size={13} className={isRefreshing ? "spin-animation" : ""} />
                <span>{isRefreshing ? "Checking..." : "Retry"}</span>
              </button>
              <button
                onClick={() => setIsModalOpen(true)}
                className="global-action-btn secondary-action-btn"
                title="Open setup details"
              >
                <Sliders size={13} />
                <span>Details</span>
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Global Access Detailed Setup Modal */}
      <GlobalAccessModal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        tailscaleInfo={tailscaleInfo}
        serverPort={serverPort}
        onRefresh={handleRefresh}
      />
    </>
  );
};
