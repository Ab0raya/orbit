import React from "react";
import { Home, Folder, ChevronRight, Bell, ChevronDown, Minus, Square, X, Bot, ScrollText } from "lucide-react";

export type AppTab = "overview" | "files" | "terminal" | "ai" | "scripts" | "settings";

interface HeaderProps {
  agentOnline: boolean;
  onRefreshAll: () => void;
  isRefreshing: boolean;
  activeTab: AppTab;
  onSelectTab: (tab: AppTab) => void;
}

export const Header: React.FC<HeaderProps> = ({
  agentOnline,
  activeTab,
  onSelectTab,
}) => {
  return (
    <header className="orbit-desktop-topbar">
      {/* Left spacer so navigation is centrally anchored */}
      <div className="topbar-left" />

      {/* Floating Center Capsule Navigation */}
      <div className="topbar-nav-capsule">
        <button
          className={`capsule-tab ${activeTab === "overview" ? "capsule-tab-active" : ""}`}
          onClick={() => onSelectTab("overview")}
        >
          <Home size={14} />
          <span>Overview</span>
        </button>

        <button
          className={`capsule-tab ${activeTab === "files" ? "capsule-tab-active" : ""}`}
          onClick={() => onSelectTab("files")}
        >
          <Folder size={14} />
          <span>Files</span>
        </button>

        <button
          className={`capsule-tab ${activeTab === "terminal" ? "capsule-tab-active" : ""}`}
          onClick={() => onSelectTab("terminal")}
        >
          <ChevronRight size={14} />
          <span>Terminal</span>
        </button>

        <button
          className={`capsule-tab ${activeTab === "ai" ? "capsule-tab-active" : ""}`}
          onClick={() => onSelectTab("ai")}
        >
          <Bot size={14} />
          <span>AI</span>
        </button>

        <button
          className={`capsule-tab ${activeTab === "scripts" ? "capsule-tab-active" : ""}`}
          onClick={() => onSelectTab("scripts")}
        >
          <ScrollText size={14} />
          <span>Scripts</span>
        </button>
      </div>

      {/* Right Controls */}
      <div className="topbar-right">
        {/* Status Pill Badge */}
        <div className={`status-pill-badge ${agentOnline ? "status-online" : "status-offline"}`}>
          <span className="status-dot-pulse" />
          <span>{agentOnline ? "Online" : "Offline"}</span>
        </div>

        {/* Notifications Bell */}
        <button className="topbar-icon-btn" title="Notifications">
          <Bell size={15} />
          <span className="bell-badge-dot" />
        </button>

        {/* User Profile Avatar */}
        <div className="topbar-user-avatar" title="Workstation Account">
          <span className="avatar-letter">A</span>
          <ChevronDown size={12} className="avatar-chevron" />
        </div>

        {/* Window Controls */}
        <div className="window-controls">
          <button className="window-btn minimize" title="Minimize">
            <Minus size={12} />
          </button>
          <button className="window-btn maximize" title="Maximize">
            <Square size={10} />
          </button>
          <button className="window-btn close" title="Close">
            <X size={12} />
          </button>
        </div>
      </div>
    </header>
  );
};
