import React from "react";

interface StatusBadgeProps {
  status: "online" | "listening" | "offline" | "expired" | string;
  label?: string;
  size?: "sm" | "md";
}

export const StatusBadge: React.FC<StatusBadgeProps> = ({
  status,
  label,
  size = "md",
}) => {
  const isPositive = status === "online" || status === "listening";
  const isWarning = status === "expired";

  const displayLabel =
    label || (status.charAt(0).toUpperCase() + status.slice(1));

  const dotColorClass = isPositive
    ? "bg-emerald-400 shadow-[0_0_8px_#34d399]"
    : isWarning
    ? "bg-amber-400 shadow-[0_0_8px_#fbbf24]"
    : "bg-slate-400";

  return (
    <span
      className={`status-badge ${
        isPositive ? "status-positive" : isWarning ? "status-warning" : "status-neutral"
      } ${size === "sm" ? "text-xs px-2 py-0.5" : "text-sm px-2.5 py-1"}`}
    >
      <span className={`status-dot ${dotColorClass}`} />
      <span className="status-label">{displayLabel}</span>
    </span>
  );
};
