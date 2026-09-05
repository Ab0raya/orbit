import React, { useState } from "react";
import { Wifi, ChevronDown, ChevronUp } from "lucide-react";
import { NetworkAddress } from "../types/agent";

interface NetworkCardProps {
  primaryIp: string | null;
  interfaces: NetworkAddress[];
}

export const NetworkCard: React.FC<NetworkCardProps> = ({
  primaryIp,
  interfaces,
}) => {
  const [showAll, setShowAll] = useState(false);

  const nonLoopback = interfaces.filter((i) => !i.is_loopback && i.is_ipv4);
  const displayInterfaces = showAll
    ? interfaces
    : nonLoopback.length > 0
    ? nonLoopback
    : interfaces.slice(0, 2);

  const effectivePrimaryIp = primaryIp || (nonLoopback[0]?.ip) || "192.168.100.4";

  return (
    <div className="orbit-network-card">
      {/* Header */}
      <div className="network-card-header">
        <div className="network-card-header-left">
          <Wifi size={16} className="network-header-icon" />
          <span className="network-header-title">LOCAL NETWORK</span>
        </div>

        {interfaces.length > 0 && (
          <button
            onClick={() => setShowAll(!showAll)}
            className="network-dropdown-btn"
          >
            <span>All interfaces ({interfaces.length || 4})</span>
            {showAll ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
          </button>
        )}
      </div>

      {/* Primary IP Row */}
      <div className="network-primary-row">
        <span className="network-primary-label">Primary LAN IP:</span>
        <span className="network-primary-value font-mono">{effectivePrimaryIp}</span>
      </div>

      {/* Interface Rows */}
      <div className="network-interfaces-list">
        {displayInterfaces.map((iface, idx) => (
          <div key={`${iface.interface_name}-${idx}`} className="network-interface-row">
            <div className="interface-left">
              <span className="interface-name font-mono">{iface.interface_name}</span>
              <span className="interface-tag-pill">
                {iface.is_loopback ? "loopback" : iface.is_ipv4 ? "IPv4" : "IPv6"}
              </span>
            </div>
            <span className="interface-ip-addr font-mono">{iface.ip}</span>
          </div>
        ))}
      </div>
    </div>
  );
};
