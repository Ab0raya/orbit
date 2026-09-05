import React from "react";
import { Server, Smartphone } from "lucide-react";
import { ServerInfo, PairedDevice } from "../types/agent";

interface ServerCardProps {
  serverInfo: ServerInfo | null;
  connectedDevices: number;
  pairedDevices: PairedDevice[];
  totalClients?: number;
}

export const ServerCard: React.FC<ServerCardProps> = ({
  serverInfo,
  connectedDevices,
  pairedDevices,
}) => {
  const isListening = serverInfo?.is_listening ?? true;
  const port = serverInfo?.port ?? 4371;
  const bindAddress = serverInfo?.bind_address ?? "0.0.0.0";

  // Check active connected devices
  const activePaired = pairedDevices.filter((d) => d.connected);
  const primaryDevice = activePaired[0] || pairedDevices[0];

  return (
    <div className="orbit-server-card">
      {/* Header */}
      <div className="server-card-header">
        <div className="server-card-header-left">
          <Server size={16} className="server-header-icon" />
          <span className="server-header-title">WEBSOCKET SERVER</span>
        </div>
        <div className={`listening-pill ${isListening ? "status-active" : "status-inactive"}`}>
          <span>{isListening ? "Listening" : "Offline"}</span>
        </div>
      </div>

      {/* Metrics Row */}
      <div className="server-metrics-row">
        {/* Port Tile */}
        <div className="server-metric-tile">
          <span className="metric-tile-label">PORT</span>
          <span className="metric-tile-value font-mono">{port}</span>
          <span className="metric-tile-sub font-mono">{bindAddress}:{port}</span>
        </div>

        {/* Connected Devices Tile */}
        <div className="server-metric-tile">
          <span className="metric-tile-label">CONNECTED DEVICES</span>
          <div className="metric-device-value-row">
            <Smartphone size={18} className="metric-phone-icon" />
            <span className="metric-tile-value font-mono">{connectedDevices}</span>
          </div>
          <span className="metric-tile-sub">
            {connectedDevices > 0 && primaryDevice
              ? `${primaryDevice.name} connected`
              : "Awaiting mobile connection"}
          </span>
        </div>
      </div>
    </div>
  );
};
