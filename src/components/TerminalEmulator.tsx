import { useEffect, useRef, useState, useCallback, useImperativeHandle, forwardRef } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { SearchAddon } from "@xterm/addon-search";
import { WebLinksAddon } from "@xterm/addon-web-links";
import "@xterm/xterm/css/xterm.css";
import { agentService } from "../services/agentService";
import { Search, ChevronDown, ChevronUp, X } from "lucide-react";

export interface TerminalEmulatorHandle {
  clear: () => void;
  focus: () => void;
  fit: () => void;
  toggleSearch: () => void;
}

interface TerminalEmulatorProps {
  sessionId: string;
  onDimensionsChange?: (cols: number, rows: number) => void;
  onTitleChange?: (title: string) => void;
}

const ORBIT_TERMINAL_THEME = {
  background: "#080C12",
  foreground: "#E6EDF3",
  cursor: "#00F5A0",
  cursorAccent: "#080C12",
  selectionBackground: "rgba(0, 229, 255, 0.28)",
  selectionForeground: "#FFFFFF",
  black: "#0B0F14",
  red: "#FF6B6B",
  green: "#7EE787",
  yellow: "#F2CC60",
  blue: "#79C0FF",
  magenta: "#D2A8FF",
  cyan: "#56D4DD",
  white: "#E6EDF3",
  brightBlack: "#484F58",
  brightRed: "#FF7B72",
  brightGreen: "#7EE787",
  brightYellow: "#F2CC60",
  brightBlue: "#79C0FF",
  brightMagenta: "#D2A8FF",
  brightCyan: "#56D4DD",
  brightWhite: "#FFFFFF",
};

export const TerminalEmulator = forwardRef<TerminalEmulatorHandle, TerminalEmulatorProps>(
  ({ sessionId, onDimensionsChange, onTitleChange }, ref) => {
    const containerRef = useRef<HTMLDivElement>(null);
    const termRef = useRef<Terminal | null>(null);
    const fitAddonRef = useRef<FitAddon | null>(null);
    const searchAddonRef = useRef<SearchAddon | null>(null);
    const lastDimensionsRef = useRef<{ cols: number; rows: number }>({ cols: 0, rows: 0 });

    const [isSearchOpen, setIsSearchOpen] = useState(false);
    const [searchQuery, setSearchQuery] = useState("");
    const searchInputRef = useRef<HTMLInputElement>(null);

    // Imperative methods exposed to parent
    useImperativeHandle(ref, () => ({
      clear: () => {
        if (termRef.current) {
          termRef.current.clear();
        }
      },
      focus: () => {
        termRef.current?.focus();
      },
      fit: () => {
        if (fitAddonRef.current && termRef.current && containerRef.current) {
          try {
            fitAddonRef.current.fit();
            const { cols, rows } = termRef.current;
            if (cols > 0 && rows > 0) {
              onDimensionsChange?.(cols, rows);
              agentService.resizeTerminal(sessionId, cols, rows).catch(() => {});
            }
          } catch (e) {
            console.error("Failed to fit terminal:", e);
          }
        }
      },
      toggleSearch: () => {
        setIsSearchOpen((prev) => {
          const next = !prev;
          if (next) {
            setTimeout(() => searchInputRef.current?.select(), 50);
          } else {
            searchAddonRef.current?.clearDecorations();
            termRef.current?.focus();
          }
          return next;
        });
      },
    }), [sessionId, onDimensionsChange]);

    const handleSearchNext = useCallback(() => {
      if (searchAddonRef.current && searchQuery) {
        searchAddonRef.current.findNext(searchQuery, {
          incremental: false,
          decorations: {
            matchBackground: "#234155",
            matchBorder: "#00E5FF",
            matchOverviewRuler: "#00E5FF",
            activeMatchBackground: "#00F5A0",
            activeMatchBorder: "#FFFFFF",
            activeMatchColorOverviewRuler: "#00F5A0",
          },
        });
      }
    }, [searchQuery]);

    const handleSearchPrev = useCallback(() => {
      if (searchAddonRef.current && searchQuery) {
        searchAddonRef.current.findPrevious(searchQuery, {
          incremental: false,
          decorations: {
            matchBackground: "#234155",
            matchBorder: "#00E5FF",
            matchOverviewRuler: "#00E5FF",
            activeMatchBackground: "#00F5A0",
            activeMatchBorder: "#FFFFFF",
            activeMatchColorOverviewRuler: "#00F5A0",
          },
        });
      }
    }, [searchQuery]);

    const handleCloseSearch = useCallback(() => {
      setIsSearchOpen(false);
      searchAddonRef.current?.clearDecorations();
      termRef.current?.focus();
    }, []);

    useEffect(() => {
      if (!containerRef.current) return;

      // 1. Initialize Terminal
      const term = new Terminal({
        theme: ORBIT_TERMINAL_THEME,
        fontFamily: "'JetBrains Mono', 'Fira Code', 'Cascadia Code', 'SF Mono', Menlo, Monaco, 'Courier New', monospace",
        fontSize: 13,
        lineHeight: 1.25,
        cursorBlink: true,
        cursorStyle: "block",
        scrollback: 10000,
        allowTransparency: false,
        convertEol: true,
      });

      // 2. Load Addons
      const fitAddon = new FitAddon();
      const searchAddon = new SearchAddon();
      const webLinksAddon = new WebLinksAddon((_event, uri) => {
        window.open(uri, "_blank");
      });

      term.loadAddon(fitAddon);
      term.loadAddon(searchAddon);
      term.loadAddon(webLinksAddon);

      termRef.current = term;
      fitAddonRef.current = fitAddon;
      searchAddonRef.current = searchAddon;

      // 3. Open in container DOM
      term.open(containerRef.current);

      // 4. Attach custom key event handler for Copy / Paste / Search
      term.attachCustomKeyEventHandler((event: KeyboardEvent) => {
        if (event.type !== "keydown") return true;

        const isCtrlOrCmd = event.ctrlKey || event.metaKey;

        // Ctrl+C / Cmd+C: Copy if selection exists, otherwise send \x03 to PTY
        if (isCtrlOrCmd && event.key.toLowerCase() === "c") {
          if (term.hasSelection()) {
            navigator.clipboard.writeText(term.getSelection()).catch(() => {});
            return false; // Don't send \x03 to terminal when user is copying!
          }
          return true; // No selection: forward to PTY as SIGINT (\x03)
        }

        // Ctrl+V / Cmd+V: Paste from clipboard
        if (isCtrlOrCmd && event.key.toLowerCase() === "v") {
          navigator.clipboard.readText().then((clipText) => {
            if (clipText) {
              agentService.writeTerminalInput(sessionId, clipText).catch(() => {});
            }
          }).catch(() => {});
          return false;
        }

        // Ctrl+F / Cmd+F: Toggle search
        if (isCtrlOrCmd && event.key.toLowerCase() === "f") {
          event.preventDefault();
          setIsSearchOpen((prev) => {
            const next = !prev;
            if (next) {
              setTimeout(() => searchInputRef.current?.select(), 50);
            } else {
              searchAddon.clearDecorations();
              term.focus();
            }
            return next;
          });
          return false;
        }

        return true;
      });

      // 5. Handle Title Change
      if (onTitleChange) {
        term.onTitleChange(onTitleChange);
      }

      // 6. Connect Input to Backend PTY
      const onDataDisposable = term.onData((data) => {
        agentService.writeTerminalInput(sessionId, data).catch((err) => {
          console.error("Failed to write terminal input:", err);
        });
      });

      // 7. Load History & Subscribe to Live Output
      let isSubscribed = true;
      let unlistenOutput: (() => void) | null = null;

      agentService.getTerminalHistory(sessionId).then((history) => {
        if (isSubscribed && history) {
          term.write(history);
        }
      }).catch((err) => {
        console.error("Failed to fetch initial terminal history:", err);
      });

      agentService.onTerminalOutput((payload) => {
        if (isSubscribed && payload.sessionId === sessionId) {
          term.write(payload.data);
        }
      }).then((unlisten) => {
        if (isSubscribed) {
          unlistenOutput = unlisten;
        } else {
          unlisten();
        }
      }).catch((err) => {
        console.error("Failed to subscribe to terminal output:", err);
      });

      // 8. Fit & Resize handling
      const performFit = () => {
        if (!containerRef.current || !fitAddonRef.current || !termRef.current) return;
        try {
          fitAddon.fit();
          const { cols, rows } = term;
          if (cols > 0 && rows > 0) {
            if (
              cols !== lastDimensionsRef.current.cols ||
              rows !== lastDimensionsRef.current.rows
            ) {
              lastDimensionsRef.current = { cols, rows };
              onDimensionsChange?.(cols, rows);
              agentService.resizeTerminal(sessionId, cols, rows).catch(() => {});
            }
          }
        } catch (err) {
          // ignore layout transient sizing issues
        }
      };

      // Initial fit after DOM layout
      const initialFitTimer = setTimeout(() => {
        performFit();
        term.focus();
      }, 50);

      // Debounced ResizeObserver
      let resizeTimeout: ReturnType<typeof setTimeout> | null = null;
      const resizeObserver = new ResizeObserver(() => {
        if (resizeTimeout) clearTimeout(resizeTimeout);
        resizeTimeout = setTimeout(() => {
          performFit();
        }, 80);
      });

      resizeObserver.observe(containerRef.current);

      // 9. Cleanup
      return () => {
        isSubscribed = false;
        clearTimeout(initialFitTimer);
        if (resizeTimeout) clearTimeout(resizeTimeout);
        resizeObserver.disconnect();
        if (unlistenOutput) unlistenOutput();
        onDataDisposable.dispose();
        term.dispose();
        termRef.current = null;
        fitAddonRef.current = null;
        searchAddonRef.current = null;
      };
    }, [sessionId]);

    return (
      <div className="terminal-emulator-wrapper">
        {isSearchOpen && (
          <div className="terminal-search-bar">
            <Search size={14} className="text-secondary" />
            <input
              ref={searchInputRef}
              type="text"
              placeholder="Find in terminal..."
              value={searchQuery}
              onChange={(e) => {
                const val = e.target.value;
                setSearchQuery(val);
                if (val && searchAddonRef.current) {
                  searchAddonRef.current.findNext(val, {
                    incremental: true,
                    decorations: {
                      matchBackground: "#234155",
                      matchBorder: "#00E5FF",
                      matchOverviewRuler: "#00E5FF",
                      activeMatchBackground: "#00F5A0",
                      activeMatchBorder: "#FFFFFF",
                      activeMatchColorOverviewRuler: "#00F5A0",
                    },
                  });
                } else {
                  searchAddonRef.current?.clearDecorations();
                }
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  if (e.shiftKey) {
                    handleSearchPrev();
                  } else {
                    handleSearchNext();
                  }
                } else if (e.key === "Escape") {
                  handleCloseSearch();
                }
              }}
              className="terminal-search-input font-mono"
              autoFocus
            />
            <button
              onClick={handleSearchPrev}
              title="Previous Match (Shift+Enter)"
              className="terminal-search-btn"
            >
              <ChevronUp size={14} />
            </button>
            <button
              onClick={handleSearchNext}
              title="Next Match (Enter)"
              className="terminal-search-btn"
            >
              <ChevronDown size={14} />
            </button>
            <button
              onClick={handleCloseSearch}
              title="Close (Esc)"
              className="terminal-search-btn"
            >
              <X size={14} />
            </button>
          </div>
        )}
        <div ref={containerRef} className="xterm-container" />
      </div>
    );
  }
);

TerminalEmulator.displayName = "TerminalEmulator";
