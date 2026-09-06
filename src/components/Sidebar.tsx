import React, { useEffect, useState, useCallback } from "react";
import {
  Home,
  Folder,
  Terminal,
  Settings,
  HelpCircle,
  Search,
  Bot,
  ScrollText,
} from "lucide-react";
import { AppTab } from "./Header";
import { OrbitLogo } from "./OrbitLogo";
import { aiService } from "../services/aiService";
import { OpencodeStatusPayload } from "../types/ai";

interface SidebarProps {
  activeTab: AppTab;
  onSelectTab: (tab: AppTab) => void;
}

export const Sidebar: React.FC<SidebarProps> = ({ activeTab, onSelectTab }) => {
  const [opencodeStatus, setOpencodeStatus] = useState<OpencodeStatusPayload | null>(null);

  const checkStatus = useCallback(async () => {
    try {
      const status = await aiService.getOpencodeStatus();
      setOpencodeStatus(status);
    } catch (err: any) {
      console.warn("Failed to query OpenCode status in sidebar:", err);
    }
  }, []);

  useEffect(() => {
    checkStatus();
    const interval = setInterval(checkStatus, 10000);
    return () => clearInterval(interval);
  }, [checkStatus]);

  const isReady = opencodeStatus?.isReady === true;

  return (
    <aside className="orbit-desktop-sidebar">
      {/* Brand Header */}
      <div className="sidebar-brand">
        <OrbitLogo size={32} />
        <div className="sidebar-brand-text">
          <span className="sidebar-brand-title">ORBIT</span>
          <span className="sidebar-brand-subtitle">Remote Development Companion</span>
        </div>
      </div>

      {/* Search Bar */}
      <div className="sidebar-search-container">
        <Search size={14} className="sidebar-search-icon" />
        <input
          type="text"
          placeholder="Search..."
          className="sidebar-search-input"
          readOnly
          onClick={() => onSelectTab("files")}
        />
        <kbd className="sidebar-search-kbd">Ctrl K</kbd>
      </div>

      {/* Main Navigation */}
      <nav className="sidebar-nav-group">
        <button
          className={`sidebar-nav-item ${activeTab === "overview" ? "sidebar-nav-active" : ""}`}
          onClick={() => onSelectTab("overview")}
        >
          <Home size={16} />
          <span>Overview</span>
        </button>

        <button
          className={`sidebar-nav-item ${activeTab === "files" ? "sidebar-nav-active" : ""}`}
          onClick={() => onSelectTab("files")}
        >
          <Folder size={16} />
          <span>Files</span>
        </button>

        <button
          className={`sidebar-nav-item ${activeTab === "terminal" ? "sidebar-nav-active" : ""}`}
          onClick={() => onSelectTab("terminal")}
        >
          <Terminal size={16} />
          <span>Terminal</span>
        </button>

        <button
          className={`sidebar-nav-item ${activeTab === "ai" ? "sidebar-nav-active" : ""}`}
          onClick={() => onSelectTab("ai")}
        >
          <Bot size={16} />
          <span>AI</span>
        </button>

        <button
          className={`sidebar-nav-item ${activeTab === "scripts" ? "sidebar-nav-active" : ""}`}
          onClick={() => onSelectTab("scripts")}
        >
          <ScrollText size={16} />
          <span>Scripts</span>
        </button>
      </nav>

      <div className="sidebar-divider" />

      {/* Secondary Navigation */}
      <nav className="sidebar-nav-group">
        <button
          className={`sidebar-nav-item secondary-nav ${activeTab === "settings" ? "sidebar-nav-active" : ""}`}
          title="Settings"
          onClick={() => onSelectTab("settings")}
        >
          <Settings size={16} />
          <span>Settings</span>
        </button>

        <button className="sidebar-nav-item secondary-nav" title="Help & Documentation">
          <HelpCircle size={16} />
          <span>Help</span>
        </button>
      </nav>

      <div className="sidebar-spacer" />

      {/* OpenCode AI Notification Card (Cosmic Aesthetic with Abstract Glowing Orbs) */}
      <div className="sidebar-cosmic-card sidebar-ai-card sidebar-opencode-card" data-testid="sidebar-opencode-card">
        <div className="cosmic-orbs-group" aria-hidden="true">
          <div className="cosmic-orb orb-large-top-right" />
          <div className="cosmic-orb orb-emerald-ambient" />
          <div className="cosmic-orb orb-medium-bottom-left" />
          <div className="cosmic-orb orb-mid-right" />
          <div className="cosmic-orb orb-small-bottom" />
          <div className="cosmic-orb orb-micro-1" />
          <div className="cosmic-orb orb-micro-2" />
          <div className="cosmic-orb orb-micro-3" />
        </div>
        <div className="cosmic-content">
          <div className="cosmic-title">
            Unlock<br />
            Orbit AI
          </div>
          <p className="cosmic-description">
            Install OpenCode to get the full Orbit experience.
          </p>
          <div className={`cosmic-status-line ${isReady ? "status-ready" : "status-required"}`}>
            <span className="cosmic-status-dot" />
            <span className="cosmic-status-text">
              {isReady ? "OpenCode ready" : "OpenCode required"}
            </span>
          </div>
        </div>
      </div>

      {/* Bottom Cosmic Feature */}
      <div className="sidebar-cosmic-card">
        <div className="cosmic-glow-arc" />
        <div className="cosmic-content">
          <div className="cosmic-title">
            Build<br />
            From Anywhere
          </div>
          <p className="cosmic-description">
            Your development environment, always within reach.
          </p>
        </div>
      </div>
    </aside>
  );
};
