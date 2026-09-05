import React from "react";
import "./OrbitLoadingIndicator.css";

interface OrbitLoadingIndicatorProps {
  size?: number;
  label?: string;
  /** Speed of one full pulse cycle in milliseconds. Default: 1100 */
  speed?: number;
  /** Min opacity at the bottom of the pulse. Default: 0.12 */
  minOpacity?: number;
}

/**
 * Orbit pulsing logo loading indicator.
 * Shows the solid Orbit logo with a smooth breathing opacity animation.
 *
 * Usage:
 * ```tsx
 * <OrbitLoadingIndicator />                     // 48px default
 * <OrbitLoadingIndicator size={72} label="Loading..." />
 * ```
 */
export const OrbitLoadingIndicator: React.FC<OrbitLoadingIndicatorProps> = ({
  size = 48,
  label,
  speed = 1100,
  minOpacity = 0.12,
}) => {
  return (
    <div className="orbit-loading-indicator" style={{ "--orbit-pulse-speed": `${speed}ms`, "--orbit-pulse-min": minOpacity } as React.CSSProperties}>
      <img
        src="/orbit_logo_solid_square.png"
        alt="Loading…"
        className="orbit-loading-logo"
        style={{ width: size, height: size }}
        draggable={false}
      />
      {label && <span className="orbit-loading-label">{label}</span>}
    </div>
  );
};

/** Full-area centered loading overlay. Drop inside a positioned container. */
export const OrbitLoadingOverlay: React.FC<{
  visible: boolean;
  label?: string;
  size?: number;
}> = ({ visible, label, size = 56 }) => {
  if (!visible) return null;
  return (
    <div className="orbit-loading-overlay">
      <OrbitLoadingIndicator size={size} label={label} />
    </div>
  );
};
