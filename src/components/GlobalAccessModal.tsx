import React, { useState, useEffect } from "react";
import {
  Globe,
  X,
  CheckCircle2,
  AlertTriangle,
  XCircle,
  ExternalLink,
  RefreshCw,
  Laptop,
  Smartphone,
  ShieldCheck,
  Radio,
  ArrowRight,
} from "lucide-react";
import { TailscaleInfo } from "../types/agent";
import { agentService } from "../services/agentService";

interface GlobalAccessModalProps {
  isOpen: boolean;
  onClose: () => void;
  tailscaleInfo: TailscaleInfo | null;
  serverPort?: number;
  onRefresh: () => Promise<void> | void;
}

export const GlobalAccessModal: React.FC<GlobalAccessModalProps> = ({
  isOpen,
  onClose,
  tailscaleInfo,
  serverPort = 4371,
  onRefresh,
}) => {
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [testResult, setTestResult] = useState<{
    testing: boolean;
    success?: boolean;
    latencyMs?: number;
    message?: string;
  }>({ testing: false });

  // Escape key closes modal
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    if (isOpen) {
      window.addEventListener("keydown", handleKeyDown);
    }
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  const isConnected = tailscaleInfo?.state === "connected" && !!tailscaleInfo?.ip;
  const isNeedsLogin = tailscaleInfo?.state === "needs_login";
  const isStopped = tailscaleInfo?.state === "stopped";
  const isNotInstalled =
    !tailscaleInfo || tailscaleInfo.state === "not_installed" || !tailscaleInfo.installed;
  const isError = !isConnected && !isNeedsLogin && !isNotInstalled && !!tailscaleInfo?.error;

  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      await onRefresh();
    } finally {
      setTimeout(() => setIsRefreshing(false), 400);
    }
  };

  const handleInstallClick = () => {
    agentService.openTailscale("https://tailscale.com/download");
  };

  const handleSignInClick = () => {
    agentService.openTailscale("https://login.tailscale.com");
  };

  const handleOpenTailscale = () => {
    agentService.openTailscale("https://login.tailscale.com/admin/machines");
  };

  const handleTestConnection = async () => {
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
    <div className="orbit-modal-overlay" onClick={onClose}>
      <div
        className="orbit-modal-card global-access-modal"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
      >
        {/* Modal Header */}
        <div className="orbit-modal-header">
          <div className="orbit-modal-header-left">
            <div className="modal-icon-badge">
              <Globe size={18} />
            </div>
            <div>
              <h2 className="orbit-modal-title">GLOBAL ACCESS SETUP</h2>
              <p className="orbit-modal-subtitle">Connect to your PC from anywhere</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="orbit-modal-close-btn"
            title="Close modal"
            aria-label="Close"
          >
            <X size={18} />
          </button>
        </div>

        <div className="orbit-modal-body">
          {/* Explanation Banner */}
          <div className="global-modal-banner">
            <p className="global-modal-desc">
              Orbit uses Tailscale to create a private connection between your devices.
              You don&apos;t need to expose Orbit to the public internet or configure router
              port forwarding.
            </p>
          </div>

          {/* 3-Step Visual Flow */}
          <div className="global-flow-container">
            <div className="global-flow-step">
              <div className="flow-step-icon">
                <Laptop size={20} />
              </div>
              <div className="flow-step-label">1. PC</div>
              <div className="flow-step-sub font-mono">Port {serverPort}</div>
            </div>

            <div className="global-flow-connector">
              <div className="flow-connector-line" />
              <div className="flow-connector-badge font-mono">Mesh</div>
              <ArrowRight size={14} className="flow-arrow" />
            </div>

            <div className="global-flow-step active-step">
              <div className="flow-step-icon">
                <ShieldCheck size={20} />
              </div>
              <div className="flow-step-label">2. Tailscale</div>
              <div className="flow-step-sub font-mono">
                {isConnected ? tailscaleInfo.ip : "Encrypted VPN"}
              </div>
            </div>

            <div className="global-flow-connector">
              <div className="flow-connector-line" />
              <div className="flow-connector-badge font-mono">Private</div>
              <ArrowRight size={14} className="flow-arrow" />
            </div>

            <div className="global-flow-step">
              <div className="flow-step-icon">
                <Smartphone size={20} />
              </div>
              <div className="flow-step-label">3. Phone</div>
              <div className="flow-step-sub font-mono">Orbit Mobile</div>
            </div>
          </div>

          {/* Current Diagnostic Checklist */}
          <div className="global-checklist-section">
            <div className="checklist-header">CURRENT SETUP STATE</div>
            <div className="global-checklist-grid">
              {/* 1. Tailscale Installed */}
              <div className="checklist-row">
                <div className="checklist-left">
                  {tailscaleInfo?.installed ? (
                    <CheckCircle2 size={16} className="status-icon-check" />
                  ) : (
                    <XCircle size={16} className="status-icon-x" />
                  )}
                  <span className="checklist-label">Tailscale Installed</span>
                </div>
                <span className="checklist-val font-mono">
                  {tailscaleInfo?.installed ? "Installed" : "Not installed"}
                </span>
              </div>

              {/* 2. Tailscale Running */}
              <div className="checklist-row">
                <div className="checklist-left">
                  {tailscaleInfo?.running ? (
                    <CheckCircle2 size={16} className="status-icon-check" />
                  ) : (
                    <XCircle size={16} className="status-icon-x" />
                  )}
                  <span className="checklist-label">Daemon Running</span>
                </div>
                <span className="checklist-val font-mono">
                  {tailscaleInfo?.running ? "Running" : "Stopped"}
                </span>
              </div>

              {/* 3. Logged in */}
              <div className="checklist-row">
                <div className="checklist-left">
                  {isConnected ? (
                    <CheckCircle2 size={16} className="status-icon-check" />
                  ) : isNeedsLogin ? (
                    <AlertTriangle size={16} className="status-icon-warn" />
                  ) : (
                    <XCircle size={16} className="status-icon-x" />
                  )}
                  <span className="checklist-label">Tailnet Authentication</span>
                </div>
                <span className="checklist-val font-mono">
                  {isConnected
                    ? tailscaleInfo?.tailnet_name || "Signed in"
                    : isNeedsLogin
                    ? "Action required"
                    : "Not logged in"}
                </span>
              </div>

              {/* 4. Tailscale IP */}
              <div className="checklist-row">
                <div className="checklist-left">
                  {tailscaleInfo?.ip ? (
                    <CheckCircle2 size={16} className="status-icon-check" />
                  ) : (
                    <XCircle size={16} className="status-icon-x" />
                  )}
                  <span className="checklist-label">Tailscale Address</span>
                </div>
                <span className="checklist-val font-mono">
                  {tailscaleInfo?.ip || "None"}
                </span>
              </div>

              {/* 5. Device Name */}
              {tailscaleInfo?.device_name && (
                <div className="checklist-row">
                  <div className="checklist-left">
                    <Radio size={16} className="status-icon-check" />
                    <span className="checklist-label">Device Name / MagicDNS</span>
                  </div>
                  <span className="checklist-val font-mono">
                    {tailscaleInfo.device_name}
                  </span>
                </div>
              )}

              {/* 6. Ready for Remote Access */}
              <div className="checklist-row highlight-row">
                <div className="checklist-left">
                  {isConnected ? (
                    <CheckCircle2 size={16} className="status-icon-check" />
                  ) : (
                    <XCircle size={16} className="status-icon-x" />
                  )}
                  <span className="checklist-label font-bold">Orbit Remote Access</span>
                </div>
                <span
                  className={`checklist-val font-mono ${
                    isConnected ? "color-ready" : "color-pending"
                  }`}
                >
                  {isConnected ? "Ready" : "Setup incomplete"}
                </span>
              </div>
            </div>
          </div>

          {/* What to do next section */}
          <div className="global-next-step-card">
            <div className="next-step-title">WHAT YOU NEED TO DO NEXT</div>
            {isNotInstalled && (
              <div className="next-step-content">
                <p className="next-step-text">
                  Tailscale is not installed on this PC. Install Tailscale to enable
                  private global access from your mobile device without port forwarding.
                </p>
                <ol className="next-step-steps">
                  <li>Click <strong>Install Tailscale</strong> below to download the app for your OS.</li>
                  <li>Sign in on this PC.</li>
                  <li>Sign in on your phone with the same Tailscale account.</li>
                  <li>Click <strong>Check Again</strong> below. Orbit will detect the connection automatically.</li>
                </ol>
              </div>
            )}

            {isNeedsLogin && (
              <div className="next-step-content">
                <p className="next-step-text">
                  Tailscale is installed on this PC, but you need to sign in to your
                  tailnet to enable remote communication.
                </p>
                <ol className="next-step-steps">
                  <li>Click <strong>Sign in to Tailscale</strong> to authenticate this workstation.</li>
                  <li>Ensure your mobile phone is logged in to the same Tailnet account.</li>
                  <li>Click <strong>Check Again</strong> below.</li>
                </ol>
              </div>
            )}

            {isStopped && !isNeedsLogin && (
              <div className="next-step-content">
                <p className="next-step-text">
                  The Tailscale daemon is currently stopped on this computer.
                </p>
                <p className="next-step-subtext">
                  Start the Tailscale application or run <code>tailscale up</code> in your
                  terminal, then click <strong>Check Again</strong>.
                </p>
              </div>
            )}

            {isError && (
              <div className="next-step-content">
                <p className="next-step-text color-error">
                  Tailscale encountered a connection issue:
                </p>
                <div className="error-detail-box font-mono">
                  {tailscaleInfo?.error || "Tailscale daemon unavailable"}
                </div>
              </div>
            )}

            {isConnected && (
              <div className="next-step-content">
                <p className="next-step-text color-ready">
                  ✓ Your workstation is ready for remote access!
                </p>
                <p className="next-step-subtext">
                  Scan the pairing QR code from Orbit Mobile while on Tailscale, or connect
                  directly to <code>{tailscaleInfo?.ip}:{serverPort}</code> from your phone.
                </p>
              </div>
            )}
          </div>

          {/* Test Connection Results (when connected) */}
          {isConnected && (
            <div className="test-connection-panel">
              <div className="test-connection-row">
                <button
                  onClick={handleTestConnection}
                  disabled={testResult.testing}
                  className="orbit-btn test-btn"
                >
                  <Radio size={14} className={testResult.testing ? "spin-animation" : ""} />
                  <span>{testResult.testing ? "Testing..." : "Test Connection"}</span>
                </button>
                {testResult.success === true && (
                  <span className="test-success-pill font-mono">
                    ✓ Verified ({testResult.latencyMs}ms)
                  </span>
                )}
                {testResult.success === false && (
                  <span className="test-error-pill font-mono">
                    ✕ {testResult.message || "Unreachable"}
                  </span>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Modal Footer Actions */}
        <div className="orbit-modal-footer">
          <div className="modal-footer-left">
            <button
              onClick={handleRefresh}
              disabled={isRefreshing}
              className="orbit-btn secondary-btn"
              title="Re-query Tailscale status from OS"
            >
              <RefreshCw size={13} className={isRefreshing ? "spin-animation" : ""} />
              <span>{isRefreshing ? "Checking..." : "Check Again"}</span>
            </button>
          </div>

          <div className="modal-footer-right">
            {isNotInstalled && (
              <button onClick={handleInstallClick} className="orbit-btn primary-btn">
                <ExternalLink size={13} />
                <span>Install Tailscale</span>
              </button>
            )}

            {isNeedsLogin && (
              <button onClick={handleSignInClick} className="orbit-btn primary-btn">
                <ExternalLink size={13} />
                <span>Sign in to Tailscale</span>
              </button>
            )}

            {isConnected && (
              <button onClick={handleOpenTailscale} className="orbit-btn primary-btn">
                <ExternalLink size={13} />
                <span>Open Tailscale</span>
              </button>
            )}

            <button onClick={onClose} className="orbit-btn close-btn">
              <span>Done</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
