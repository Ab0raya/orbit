import React from "react";

export interface OrbitLogoProps {
  size?: number;
  className?: string;
  variant?: "silver" | "solid";
}

export const OrbitLogo: React.FC<OrbitLogoProps> = ({
  size = 32,
  className = "",
  variant = "silver",
}) => {
  const imageSrc =
    variant === "silver"
      ? "/orbit_logo_silver_square.png"
      : "/orbit_logo_solid_square.png";

  return (
    <div
      className={`orbit-logo-container ${className}`}
      style={{
        width: size,
        height: size,
        position: "relative",
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        flexShrink: 0,
      }}
    >
      <img
        src={imageSrc}
        alt="Orbit"
        width={size}
        height={size}
        style={{
          width: "100%",
          height: "100%",
          objectFit: "contain",
          filter:
            variant === "silver"
              ? "drop-shadow(0 2px 10px rgba(255, 255, 255, 0.12))"
              : "none",
        }}
        draggable={false}
      />
    </div>
  );
};
