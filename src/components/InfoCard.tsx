import React, { ReactNode } from "react";

interface InfoCardProps {
  icon: ReactNode;
  label: string;
  value?: ReactNode;
  badge?: ReactNode;
  meta?: ReactNode;
  className?: string;
  children?: ReactNode;
}

export const InfoCard: React.FC<InfoCardProps> = ({
  icon,
  label,
  value,
  badge,
  meta,
  className = "",
  children,
}) => {
  return (
    <div className={`info-card ${className}`}>
      <div className="card-header">
        <div className="card-header-left">
          <span className="card-icon">{icon}</span>
          <span className="card-label">{label}</span>
        </div>
        {badge && <div className="card-header-right">{badge}</div>}
      </div>

      {value !== undefined && <div className="card-value">{value}</div>}

      {meta && <div className="card-meta">{meta}</div>}

      {children && <div className="card-body">{children}</div>}
    </div>
  );
};
