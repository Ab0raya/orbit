import React, { useState } from "react";
import { Link2, Copy, Check, RefreshCw, Clock } from "lucide-react";
import { QRCodeSVG } from "qrcode.react";
import { PairingInfo } from "../types/agent";
import { agentService } from "../services/agentService";

interface PairingCardProps {
  pairingInfo: PairingInfo | null;
  onRegenerate: () => Promise<void>;
  isRegenerating: boolean;
  primaryIp?: string | null;
  tailscaleIp?: string | null;
  port?: number;
}

export const PairingCard: React.FC<PairingCardProps> = ({
  pairingInfo,
  onRegenerate,
  isRegenerating,
  primaryIp,
  tailscaleIp,
  port = 4371,
}) => {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    if (!pairingInfo?.code) return;
    try {
      await navigator.clipboard.writeText(pairingInfo.code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (err) {
      console.error("Failed to copy code to clipboard", err);
    }
  };

  const code = pairingInfo?.code || "359042";
  const secondsRemaining = pairingInfo?.seconds_remaining ?? 0;
  const isExpired = pairingInfo?.is_expired || secondsRemaining <= 0;

  const resolvedHost = primaryIp && primaryIp !== "0.0.0.0" ? primaryIp : "127.0.0.1";
  const expireTimestamp = Date.now() + secondsRemaining * 1000;
  const tsParam = tailscaleIp ? `&ts_host=${encodeURIComponent(tailscaleIp)}` : "";
  const pairingUri = `orbit://pair/v1?host=${resolvedHost}&port=${port}&code=${code}&expires=${expireTimestamp}${tsParam}`;

  return (
    <div className="orbit-hero-pairing-card">
      {/* Header */}
      <div className="pairing-hero-header">
        <div className="pairing-header-left">
          <div className="pairing-link-icon">
            <Link2 size={18} />
          </div>
          <div className="pairing-title-group">
            <h3 className="pairing-card-title">PAIRING CODE & QR</h3>
            <p className="pairing-card-subtitle">Connect Orbit Mobile to this device</p>
          </div>
        </div>

        <div className="pairing-header-right">
          <div className={`countdown-pill-badge ${isExpired ? "countdown-expired" : ""}`}>
            <Clock size={13} />
            <span>{agentService.formatRemainingTime(secondsRemaining)}</span>
          </div>
        </div>
      </div>

      {/* Code digits and action buttons row */}
      <div className="pairing-code-actions-row">
        <div className="digits-container">
          {code.split("").map((digit, idx) => (
            <div key={idx} className="digit-box">
              <span className="digit-number">{digit}</span>
            </div>
          ))}
        </div>

        <div className="digits-actions-group">
          <button
            onClick={handleCopy}
            className="orbit-action-btn copy-action-btn"
            title="Copy 6-digit code"
            disabled={isExpired}
          >
            {copied ? (
              <>
                <Check size={14} className="action-icon-check" />
                <span>Copied</span>
              </>
            ) : (
              <>
                <Copy size={14} />
                <span>Copy</span>
              </>
            )}
          </button>

          <button
            onClick={onRegenerate}
            disabled={isRegenerating}
            className="orbit-action-btn regen-action-btn"
            title="Generate new pairing code"
          >
            <RefreshCw
              size={14}
              className={isRegenerating ? "spin-animation" : ""}
            />
            <span>Regenerate</span>
          </button>
        </div>
      </div>

      {/* Dark Technical QR Section */}
      <div className="technical-qr-canvas">
        <div className="qr-mesh-background" />
        <div className="qr-inner-frame">
          {isExpired ? (
            <div className="qr-expired-message">
              <span>Code Expired</span>
              <button onClick={onRegenerate} className="qr-expired-regen-btn">
                Click Regenerate
              </button>
            </div>
          ) : (
            <div className="qr-svg-wrapper">
              <QRCodeSVG
                value={pairingUri}
                size={116}
                level="M"
                bgColor="#FFFFFF"
                fgColor="#000000"
              />
            </div>
          )}
        </div>
        <span className="qr-caption-text">Scan with Orbit Mobile to pair instantly</span>
      </div>

      {/* Footer Instructions */}
      <p className="pairing-footer-note">
        Scan the QR code or enter this 6-digit code in Orbit Mobile on the same local network.
      </p>
    </div>
  );
};
