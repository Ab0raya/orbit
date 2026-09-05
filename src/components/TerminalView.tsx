import React, { useState, useEffect, useRef, useCallback } from "react";
import {
  Terminal as TerminalIcon,
  Plus,
  Trash2,
  RefreshCw,
  Search,
  Folder,
  AlertCircle,
  X,
  RotateCcw,
} from "lucide-react";
import { TerminalSessionSummary } from "../types/protocol";
import { agentService } from "../services/agentService";
import { TerminalEmulator, TerminalEmulatorHandle } from "./TerminalEmulator";

interface TerminalViewProps {
  initialSessionId?: string | null;
  runningScriptName?: string | null;
  onClearRunningScript?: () => void;
}

export const TerminalView: React.FC<TerminalViewProps> = ({
  initialSessionId,
  runningScriptName,
  onClearRunningScript,
}) => {
  const [sessions, setSessions] = useState<TerminalSessionSummary[]>([]);
  const [selectedSessionId, setSelectedSessionId] = useState<string | null>(initialSessionId || null);
  const [isCreating, setIsCreating] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [dimensions, setDimensions] = useState<{ cols: number; rows: number }>({ cols: 0, rows: 0 });
  const emulatorRef = useRef<TerminalEmulatorHandle>(null);

  useEffect(() => {
    if (initialSessionId) {
      setSelectedSessionId(initialSessionId);
    }
  }, [initialSessionId]);

  const fetchSessions = useCallback(async (autoSelect = false) => {
    try {
      const list = await agentService.listTerminals();
      setSessions(list);
      setError(null);

      if (list.length > 0) {
        setSelectedSessionId((current) => {
          if (current && list.some((s) => s.sessionId === current)) {
            return current;
          }
          return list[0].sessionId;
        });
      } else if (autoSelect) {
        // Auto-create initial session if none exist
        handleCreateTerminal();
      } else {
        setSelectedSessionId(null);
      }
    } catch (err) {
      console.error("Failed to load terminal sessions:", err);
      setError(typeof err === "string" ? err : "Failed to load terminal sessions");
    }
  }, []);

  const handleCreateTerminal = async () => {
    setIsCreating(true);
    setError(null);
    try {
      const newSession = await agentService.createTerminal();
      const list = await agentService.listTerminals();
      setSessions(list);
      setSelectedSessionId(newSession.sessionId);
    } catch (err) {
      console.error("Failed to create terminal:", err);
      setError(typeof err === "string" ? err : "Failed to create terminal");
    } finally {
      setIsCreating(false);
    }
  };

  const handleKillTerminal = async (sessionId: string) => {
    try {
      await agentService.killTerminal(sessionId);
      const list = await agentService.listTerminals();
      setSessions(list);
      if (selectedSessionId === sessionId) {
        const remaining = list.filter((s) => s.sessionId !== sessionId);
        setSelectedSessionId(remaining.length > 0 ? remaining[0].sessionId : null);
      }
    } catch (err) {
      console.error("Failed to kill terminal:", err);
      setError(typeof err === "string" ? err : "Failed to kill terminal");
    }
  };

  const handleClearTerminal = () => {
    emulatorRef.current?.clear();
  };

  const handleToggleSearch = () => {
    emulatorRef.current?.toggleSearch();
  };

  // Initial load and periodic session check
  useEffect(() => {
    fetchSessions();
    const interval = setInterval(() => fetchSessions(false), 3000);
    return () => clearInterval(interval);
  }, [fetchSessions]);

  // Listen to terminal exit events
  useEffect(() => {
    let unlisten: (() => void) | null = null;
    agentService.onTerminalExited((payload) => {
      setSessions((prev) =>
        prev.map((s) =>
          s.sessionId === payload.sessionId
            ? { ...s, status: "exited", exitCode: payload.exitCode }
            : s
        )
      );
    }).then((fn) => {
      unlisten = fn;
    }).catch((err) => {
      console.error("Failed to listen for terminal exited event:", err);
    });

    return () => {
      if (unlisten) unlisten();
    };
  }, []);

  const currentSession = sessions.find((s) => s.sessionId === selectedSessionId);
  const isRunning = currentSession?.status === "running";

  return (
    <div className="terminal-view-root">
      {/* Compact Top Toolbar */}
      <div className="terminal-compact-toolbar">
        {/* Left Side: Sessions & Status & CWD */}
        <div className="toolbar-left">
          {sessions.length > 1 ? (
            <div className="toolbar-session-tabs">
              {sessions.map((s, idx) => {
                const isSelected = s.sessionId === selectedSessionId;
                return (
                  <div
                    key={s.sessionId}
                    className={`session-tab-chip ${isSelected ? "session-tab-active" : ""}`}
                    onClick={() => setSelectedSessionId(s.sessionId)}
                  >
                    <span className={`session-tab-dot ${s.status === "running" ? "dot-online" : "dot-exited"}`} />
                    <span className="session-tab-name font-mono">
                      #{idx + 1} {s.shell.split("/").pop() || "sh"}
                    </span>
                    <button
                      className="session-tab-close"
                      onClick={(e) => {
                        e.stopPropagation();
                        handleKillTerminal(s.sessionId);
                      }}
                      title="Kill session"
                    >
                      <X size={10} />
                    </button>
                  </div>
                );
              })}
              <button
                className="toolbar-action-icon-btn session-add-btn"
                onClick={handleCreateTerminal}
                disabled={isCreating}
                title="New Terminal Session"
              >
                <Plus size={13} />
              </button>
            </div>
          ) : (
            <div className="toolbar-status-badge">
              <span className={`toolbar-dot ${isRunning ? "dot-online" : "dot-exited"}`} />
              <span className="toolbar-status-label">
                {currentSession ? (isRunning ? "Connected" : "Exited") : "No Session"}
              </span>
            </div>
          )}

          {currentSession && (
            <div className="toolbar-cwd-badge" title={currentSession.cwd}>
              <Folder size={11} style={{ color: "var(--text-dim)", flexShrink: 0 }} />
              <span className="toolbar-cwd-text">{currentSession.cwd}</span>
            </div>
          )}

          {runningScriptName && (
            <div className="toolbar-running-script-badge">
              <span className="status-dot-pulse" />
              <span>Script: {runningScriptName}</span>
              {onClearRunningScript && (
                <button
                  onClick={onClearRunningScript}
                  style={{ background: "transparent", border: "none", color: "inherit", cursor: "pointer", display: "flex", padding: 0, marginLeft: 2 }}
                  title="Dismiss badge"
                >
                  <X size={10} />
                </button>
              )}
            </div>
          )}
        </div>

        {/* Right Side: Dimensions & Controls */}
        <div className="toolbar-right">
          {dimensions.cols > 0 && dimensions.rows > 0 && (
            <span className="toolbar-dim-pill">
              {dimensions.cols}×{dimensions.rows}
            </span>
          )}

          <button
            className="toolbar-action-icon-btn"
            onClick={handleToggleSearch}
            title="Search (Ctrl+F)"
            disabled={!selectedSessionId}
          >
            <Search size={14} />
          </button>

          <button
            className="toolbar-action-icon-btn"
            onClick={handleClearTerminal}
            title="Clear Terminal"
            disabled={!selectedSessionId}
          >
            <RotateCcw size={13} />
          </button>

          {sessions.length <= 1 && (
            <button
              className="toolbar-action-icon-btn"
              onClick={handleCreateTerminal}
              disabled={isCreating}
              title="New Terminal"
            >
              <Plus size={14} />
            </button>
          )}

          <button
            className="toolbar-action-icon-btn"
            onClick={() => fetchSessions(false)}
            title="Refresh Sessions"
          >
            <RefreshCw size={13} />
          </button>

          {selectedSessionId && (
            <button
              className="toolbar-action-icon-btn btn-danger"
              onClick={() => handleKillTerminal(selectedSessionId)}
              title="Kill Terminal Session"
            >
              <Trash2 size={13} />
            </button>
          )}
        </div>
      </div>

      {error && (
        <div className="terminal-inline-error">
          <AlertCircle size={13} />
          <span>{error}</span>
          <button className="error-close-btn" onClick={() => setError(null)}>
            <X size={11} />
          </button>
        </div>
      )}

      {/* Terminal Viewport Canvas */}
      <div className="terminal-canvas-container">
        {selectedSessionId ? (
          <TerminalEmulator
            key={selectedSessionId}
            ref={emulatorRef}
            sessionId={selectedSessionId}
            onDimensionsChange={(cols, rows) => setDimensions({ cols, rows })}
          />
        ) : (
          <div className="terminal-empty-state">
            <div className="terminal-empty-content">
              <div className="terminal-empty-icon-wrap">
                <TerminalIcon size={22} className="text-emerald" />
              </div>
              <h3>No Terminal Session</h3>
              <p>Spawn an interactive PTY shell directly on your host machine</p>
              <button
                className="create-term-btn empty-create-btn"
                onClick={handleCreateTerminal}
                disabled={isCreating}
              >
                <Plus size={14} />
                {isCreating ? "Spawning Shell…" : "Launch Shell"}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
