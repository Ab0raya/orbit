import React, { useEffect, useState, useCallback } from "react";
import {
  Folder,
  File,
  FileCode,
  FileText,
  Image as ImageIcon,
  HardDrive,
  Search,
  ArrowUp,
  RefreshCw,
  Sparkles,
  ChevronRight,
  AlertCircle,
  Eye,
  EyeOff,
  ArrowLeft,
} from "lucide-react";
import { agentService } from "../services/agentService";
import {
  FileEntry,
  FileRoot,
  FileSearchResult,
  getFileCategory,
} from "../types/files";
import { MarkdownViewer } from "./MarkdownViewer";

export const FileExplorerView: React.FC = () => {
  const [roots, setRoots] = useState<FileRoot[]>([]);
  const [currentPath, setCurrentPath] = useState<string>("");
  const [entries, setEntries] = useState<FileEntry[]>([]);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  // Search state
  const [searchQuery, setSearchQuery] = useState<string>("");
  const [searchMode, setSearchMode] = useState<"name" | "content">("name");
  const [isSearching, setIsSearching] = useState<boolean>(false);
  const [searchResults, setSearchResults] = useState<FileSearchResult | null>(null);

  // Hidden files toggle
  const [showHidden, setShowHidden] = useState<boolean>(false);

  // Active viewed file state
  const [activeFile, setActiveFile] = useState<{
    path: string;
    name: string;
    content: string;
    category: "markdown" | "code" | "text" | "image" | "binary";
  } | null>(null);

  // 1. Initial load: get roots
  useEffect(() => {
    agentService
      .getFileRoots()
      .then((r) => {
        setRoots(r);
        if (r.length > 0) {
          loadDirectory(r[0].path);
        }
      })
      .catch((err) => {
        console.error("Failed to load roots:", err);
        setError("Failed to load filesystem roots");
      });
  }, []);

  // 2. Load directory contents
  const loadDirectory = useCallback(async (dirPath: string) => {
    setIsLoading(true);
    setError(null);
    try {
      const res = await agentService.listDirectory(dirPath);
      setCurrentPath(res.path);
      setEntries(res.entries);
    } catch (err: any) {
      console.error("Failed to list directory:", err);
      setError(typeof err === "string" ? err : "Permission denied or directory not found");
    } finally {
      setIsLoading(false);
    }
  }, []);

  // 3. Navigate up one directory
  const handleNavigateUp = () => {
    if (!currentPath) return;
    const separator = currentPath.includes("\\") ? "\\" : "/";
    const parts = currentPath.split(separator).filter(Boolean);
    if (parts.length <= 1) return;
    parts.pop();
    const parent = (currentPath.startsWith(separator) ? separator : "") + parts.join(separator);
    loadDirectory(parent);
  };

  // 4. Open file handler (routes to appropriate viewer)
  const handleOpenFile = async (entryPath: string, fileName: string) => {
    const category = getFileCategory(fileName);
    try {
      if (category === "image" || category === "binary") {
        setActiveFile({
          path: entryPath,
          name: fileName,
          content: "",
          category,
        });
      } else {
        const fileRes = await agentService.readFile(entryPath);
        setActiveFile({
          path: entryPath,
          name: fileName,
          content: fileRes.content,
          category,
        });
      }
    } catch (err: any) {
      console.error("Failed to read file:", err);
      alert(`Could not open file: ${err}`);
    }
  };

  // 5. Execute search
  const handleSearch = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if (!searchQuery.trim() || !currentPath) return;

    setIsSearching(true);
    setError(null);
    try {
      const results = await agentService.searchFiles(
        currentPath,
        searchQuery.trim(),
        searchMode,
        100
      );
      setSearchResults(results);
    } catch (err: any) {
      console.error("Search failed:", err);
      setError(typeof err === "string" ? err : "Search failed");
    } finally {
      setIsSearching(false);
    }
  };

  const handleClearSearch = () => {
    setSearchQuery("");
    setSearchResults(null);
  };

  // 6. Ask Orbit AI for a file
  const handleAskOrbitAi = (path: string, fileName: string, snippet?: string) => {
    const prompt = snippet
      ? `Analyzing file ${path} at matching lines:\n\n${snippet}`
      : `Analyzing file: ${path}`;
    navigator.clipboard.writeText(prompt);
    alert(`File context for '${fileName}' copied to clipboard for Orbit AI.`);
  };

  const getFileIcon = (name: string, isDirectory: boolean) => {
    if (isDirectory) return <Folder size={14} className="text-folder" />;
    const cat = getFileCategory(name);
    switch (cat) {
      case "markdown":
        return <FileText size={14} className="text-accent" />;
      case "code":
        return <FileCode size={14} className="text-cyan" />;
      case "image":
        return <ImageIcon size={14} className="text-purple" />;
      default:
        return <File size={14} className="text-muted-icon" />;
    }
  };

  const formatSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  // Filter entries based on showHidden
  const visibleEntries = showHidden
    ? entries
    : entries.filter((e) => !e.name.startsWith("."));

  // Build breadcrumb segments from currentPath
  const buildBreadcrumbs = () => {
    if (!currentPath) return [];
    const sep = currentPath.includes("\\") ? "\\" : "/";
    const parts = currentPath.split(sep).filter(Boolean);
    return parts.map((part, idx) => {
      const subPath = (currentPath.startsWith(sep) ? sep : "") + parts.slice(0, idx + 1).join(sep);
      return { label: part, path: subPath, isLast: idx === parts.length - 1 };
    });
  };

  const breadcrumbs = buildBreadcrumbs();

  return (
    <div className="file-explorer-layout">
      {/* Sidebar: Navigation & Roots */}
      <div className="file-explorer-sidebar">
        <div className="sidebar-section-title">
          <HardDrive size={12} />
          <span>Locations</span>
        </div>
        <div className="roots-list">
          {roots.map((r) => (
            <button
              key={r.path}
              className={`root-item ${currentPath.startsWith(r.path) ? "active" : ""}`}
              onClick={() => {
                handleClearSearch();
                loadDirectory(r.path);
              }}
            >
              <Folder size={13} />
              <span className="root-name">{r.name}</span>
            </button>
          ))}
        </div>

        <div className="sidebar-divider" />

        {/* Search Files section */}
        <div className="sidebar-section-title" style={{ paddingTop: 10 }}>
          <Search size={12} />
          <span>Search</span>
        </div>
        <div className="sidebar-search-section">
          <form onSubmit={handleSearch} className="search-form">
            <div className="search-input-wrapper">
              <input
                type="text"
                placeholder="Search files..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="search-input"
              />
              <button
                type="submit"
                disabled={isSearching || !searchQuery.trim()}
                className="search-submit-btn"
                title="Search"
              >
                <Search size={12} />
              </button>
            </div>

            {/* Segmented Search Mode */}
            <div className="search-mode-selector">
              <label className={`mode-pill ${searchMode === "name" ? "selected" : ""}`}>
                <input
                  type="radio"
                  name="searchMode"
                  value="name"
                  checked={searchMode === "name"}
                  onChange={() => setSearchMode("name")}
                />
                <span>Name</span>
              </label>
              <label className={`mode-pill ${searchMode === "content" ? "selected" : ""}`}>
                <input
                  type="radio"
                  name="searchMode"
                  value="content"
                  checked={searchMode === "content"}
                  onChange={() => setSearchMode("content")}
                />
                <span>Content</span>
              </label>
            </div>
          </form>

          {searchResults && (
            <div className="search-results-summary">
              <span>{searchResults.totalMatches} matches</span>
              {searchResults.truncated && <span className="truncated-badge">(capped)</span>}
              <button className="clear-link" onClick={handleClearSearch}>
                Clear
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Main Panel */}
      <div className="file-explorer-main">
        {/* Path bar with breadcrumb + controls */}
        <div className="explorer-path-bar">
          <button
            className="nav-up-btn"
            onClick={handleNavigateUp}
            title="Go up one folder"
          >
            <ArrowUp size={13} />
          </button>

          <div className="path-breadcrumbs" title={currentPath}>
            {breadcrumbs.map((crumb, idx) => (
              <span key={idx} className="breadcrumb-segment">
                <span
                  className="breadcrumb-text"
                  onClick={() => {
                    if (!crumb.isLast) {
                      handleClearSearch();
                      loadDirectory(crumb.path);
                    }
                  }}
                  style={crumb.isLast ? { cursor: "default" } : undefined}
                >
                  {crumb.label}
                </span>
                {!crumb.isLast && (
                  <ChevronRight size={11} className="breadcrumb-sep" />
                )}
              </span>
            ))}
          </div>

          {/* Hidden files toggle */}
          <button
            className={`hidden-toggle-btn ${showHidden ? "active" : ""}`}
            onClick={() => setShowHidden((v) => !v)}
            title={showHidden ? "Hide dotfiles" : "Show hidden files"}
          >
            {showHidden ? <Eye size={13} /> : <EyeOff size={13} />}
          </button>

          <button
            className="refresh-btn"
            onClick={() => loadDirectory(currentPath)}
            title="Refresh directory"
          >
            <RefreshCw size={12} className={isLoading ? "animate-spin" : ""} />
          </button>
        </div>

        {error && (
          <div className="explorer-error-banner">
            <AlertCircle size={13} />
            <span>{error}</span>
          </div>
        )}

        {/* Content: Active Viewer or Directory List or Search Results */}
        {activeFile ? (
          <div className="file-viewer-wrapper">
            <div className="viewer-close-bar">
              <button
                className="back-to-list-btn"
                onClick={() => setActiveFile(null)}
              >
                <ArrowLeft size={12} />
                Back to Files
              </button>
            </div>

            {activeFile.category === "markdown" ? (
              <MarkdownViewer
                fileName={activeFile.name}
                filePath={activeFile.path}
                content={activeFile.content}
                onContentChange={(newC) =>
                  setActiveFile({ ...activeFile, content: newC })
                }
                onAskAi={(p, c) => handleAskOrbitAi(p, activeFile.name, c.slice(0, 500))}
                onClose={() => setActiveFile(null)}
              />
            ) : activeFile.category === "code" || activeFile.category === "text" ? (
              <div className="generic-editor-container">
                <div className="generic-editor-header">
                  <div className="header-meta">
                    <FileCode size={14} className="text-cyan" />
                    <span className="file-name">{activeFile.name}</span>
                    <span className="file-path">{activeFile.path}</span>
                  </div>
                  <button
                    className="btn-ai-small"
                    onClick={() =>
                      handleAskOrbitAi(activeFile.path, activeFile.name, activeFile.content.slice(0, 500))
                    }
                  >
                    <Sparkles size={12} />
                    <span>Ask Orbit AI</span>
                  </button>
                </div>
                <textarea
                  className="code-editor-textarea"
                  value={activeFile.content}
                  readOnly
                  spellCheck={false}
                />
              </div>
            ) : (
              <div className="binary-viewer-container">
                <div className="binary-card">
                  <HardDrive size={28} style={{ color: "var(--text-muted)" }} />
                  <h3>{activeFile.name}</h3>
                  <span className="file-path">{activeFile.path}</span>
                  <p className="binary-notice">
                    {activeFile.category === "image"
                      ? "Image preview available on Orbit Mobile."
                      : "Binary file cannot be viewed as plain text."}
                  </p>
                  <button
                    className="btn-ai-small"
                    onClick={() => handleAskOrbitAi(activeFile.path, activeFile.name)}
                  >
                    <Sparkles size={12} />
                    <span>Ask Orbit AI about this file</span>
                  </button>
                </div>
              </div>
            )}
          </div>
        ) : searchResults ? (
          /* Search Results List */
          <div className="search-results-container">
            <div className="results-header">
              <h3>
                &ldquo;{searchResults.query}&rdquo; &mdash; {searchResults.totalMatches} {searchResults.mode} result{searchResults.totalMatches !== 1 ? "s" : ""}
              </h3>
            </div>

            {searchResults.results.length === 0 ? (
              <div className="empty-results">No files matched your search.</div>
            ) : (
              <div className="results-list">
                {searchResults.results.map((res, i) => (
                  <div
                    key={i}
                    className="search-result-item"
                    onClick={() => {
                      if (!res.isDirectory) {
                        handleOpenFile(res.path, res.name);
                      } else {
                        loadDirectory(res.path);
                        handleClearSearch();
                      }
                    }}
                  >
                    <div className="result-left">
                      {getFileIcon(res.name, res.isDirectory)}
                      <div className="result-info">
                        <div className="result-name-row">
                          <span className="result-filename">{res.name}</span>
                          <span className="result-category">
                            {res.isDirectory ? "dir" : getFileCategory(res.name)}
                          </span>
                        </div>
                        <span className="result-relative-path">
                          {res.relativePath}
                        </span>
                        {res.lineNumber !== undefined && res.lineContent && (
                          <div className="result-snippet">
                            <span className="snippet-line-num">L{res.lineNumber}:</span>
                            <span className="snippet-text">{res.lineContent}</span>
                          </div>
                        )}
                      </div>
                    </div>

                    <button
                      className="result-ai-btn"
                      onClick={(e) => {
                        e.stopPropagation();
                        handleAskOrbitAi(res.path, res.name, res.lineContent);
                      }}
                      title="Ask Orbit AI"
                    >
                      <Sparkles size={11} />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>
        ) : (
          /* Normal Directory Listing */
          <div className="explorer-entries-list">
            <div className="entries-header-row">
              <span className="col-name">Name</span>
              <span className="col-size">Size</span>
            </div>

            {visibleEntries.length === 0 ? (
              <div className="empty-folder">
                {isLoading ? "Loading…" : "This folder is empty"}
              </div>
            ) : (
              visibleEntries.map((entry) => (
                <div
                  key={entry.path}
                  className="entry-row"
                  onClick={() => {
                    if (entry.kind === "directory") {
                      loadDirectory(entry.path);
                    } else {
                      handleOpenFile(entry.path, entry.name);
                    }
                  }}
                >
                  <div className="entry-left">
                    {getFileIcon(entry.name, entry.kind === "directory")}
                    <span className="entry-name">{entry.name}</span>
                  </div>

                  <div className="entry-right">
                    <span className="entry-size">
                      {entry.kind === "directory" ? "—" : formatSize(entry.size)}
                    </span>
                    {entry.kind !== "directory" && (
                      <button
                        className="entry-ai-btn"
                        onClick={(e) => {
                          e.stopPropagation();
                          handleAskOrbitAi(entry.path, entry.name);
                        }}
                        title="Ask Orbit AI"
                      >
                        <Sparkles size={11} />
                      </button>
                    )}
                  </div>
                </div>
              ))
            )}
          </div>
        )}
      </div>
    </div>
  );
};
