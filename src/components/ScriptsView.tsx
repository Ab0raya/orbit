import React, { useState, useEffect, useMemo, useCallback } from "react";
import {
  Play,
  Plus,
  Search,
  ScrollText,
  Trash2,
  Edit2,
  Folder,
  Globe,
  X,
  AlertCircle,
  Terminal,
  Layers,
} from "lucide-react";
import { Script, ScriptInput } from "../types/script";
import { agentService } from "../services/agentService";

interface ScriptsViewProps {
  onRunScript: (script: Script) => void;
}

export const ScriptsView: React.FC<ScriptsViewProps> = ({ onRunScript }) => {
  const [scripts, setScripts] = useState<Script[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState<string>("");
  const [scopeFilter, setScopeFilter] = useState<"all" | "global" | "project">("all");

  // Editor modal state
  const [isModalOpen, setIsModalOpen] = useState<boolean>(false);
  const [editingScript, setEditingScript] = useState<Script | null>(null);
  const [formName, setFormName] = useState<string>("");
  const [formDescription, setFormDescription] = useState<string>("");
  const [formContent, setFormContent] = useState<string>("");
  const [formScope, setFormScope] = useState<"global" | "project">("global");
  const [formWorkingDirectory, setFormWorkingDirectory] = useState<string>("");
  const [formProjectPath, setFormProjectPath] = useState<string>("");
  const [formError, setFormError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState<boolean>(false);

  // Delete confirmation
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const fetchScripts = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const list = await agentService.listScripts();
      setScripts(list);
    } catch (err: any) {
      console.error("Failed to load scripts:", err);
      setError(typeof err === "string" ? err : err.message || "Failed to load scripts");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchScripts();
  }, [fetchScripts]);

  const filteredScripts = useMemo(() => {
    return scripts.filter((s) => {
      // Scope filter
      if (scopeFilter === "global" && s.projectPath) return false;
      if (scopeFilter === "project" && !s.projectPath) return false;

      // Search filter
      if (!searchQuery.trim()) return true;
      const q = searchQuery.toLowerCase();
      return (
        s.name.toLowerCase().includes(q) ||
        (s.description && s.description.toLowerCase().includes(q)) ||
        s.content.toLowerCase().includes(q) ||
        (s.workingDirectory && s.workingDirectory.toLowerCase().includes(q))
      );
    });
  }, [scripts, scopeFilter, searchQuery]);

  const openCreateModal = () => {
    setEditingScript(null);
    setFormName("");
    setFormDescription("");
    setFormContent("");
    setFormScope("global");
    setFormWorkingDirectory("");
    setFormProjectPath("");
    setFormError(null);
    setIsModalOpen(true);
  };

  const openEditModal = (script: Script) => {
    setEditingScript(script);
    setFormName(script.name);
    setFormDescription(script.description || "");
    setFormContent(script.content);
    setFormScope(script.projectPath ? "project" : "global");
    setFormWorkingDirectory(script.workingDirectory || "");
    setFormProjectPath(script.projectPath || "");
    setFormError(null);
    setIsModalOpen(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formName.trim()) {
      setFormError("Please enter a script name.");
      return;
    }
    if (!formContent.trim()) {
      setFormError("Script content cannot be empty.");
      return;
    }

    try {
      setIsSaving(true);
      setFormError(null);

      const input: ScriptInput = {
        id: editingScript?.id || null,
        name: formName.trim(),
        description: formDescription.trim() || null,
        content: formContent,
        workingDirectory: formWorkingDirectory.trim() || null,
        projectPath: formScope === "project" ? formProjectPath.trim() || formWorkingDirectory.trim() || null : null,
      };

      await agentService.saveScript(input);
      setIsModalOpen(false);
      await fetchScripts();
    } catch (err: any) {
      console.error("Failed to save script:", err);
      setFormError(typeof err === "string" ? err : err.message || "Failed to save script");
    } finally {
      setIsSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    try {
      setDeletingId(id);
      await agentService.deleteScript(id);
      await fetchScripts();
    } catch (err: any) {
      console.error("Failed to delete script:", err);
      setError(typeof err === "string" ? err : err.message || "Failed to delete script");
    } finally {
      setDeletingId(null);
    }
  };

  const handleTextareaKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Tab") {
      e.preventDefault();
      const textarea = e.currentTarget;
      const start = textarea.selectionStart;
      const end = textarea.selectionEnd;
      const value = textarea.value;
      const newValue = value.substring(0, start) + "  " + value.substring(end);
      setFormContent(newValue);
      setTimeout(() => {
        textarea.selectionStart = textarea.selectionEnd = start + 2;
      }, 0);
    }
  };

  return (
    <div className="orbit-content-canvas scripts-view-container">
      {/* Top Controls Header */}
      <div className="scripts-header">
        <div className="scripts-header-left">
          <div className="scripts-title-row">
            <ScrollText size={20} className="scripts-title-icon" />
            <h1 className="scripts-title">SCRIPTS</h1>
          </div>
          <p className="scripts-subtitle font-mono">
            Save and run custom terminal commands on demand
          </p>
        </div>

        <div className="scripts-header-right">
          <button className="orbit-btn-primary scripts-new-btn" onClick={openCreateModal}>
            <Plus size={15} />
            <span>New Script</span>
          </button>
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div className="scripts-toolbar">
        <div className="scripts-search-box">
          <Search size={14} className="scripts-search-icon" />
          <input
            type="text"
            placeholder="Filter saved scripts..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="scripts-search-input"
          />
          {searchQuery && (
            <button className="scripts-search-clear" onClick={() => setSearchQuery("")}>
              <X size={12} />
            </button>
          )}
        </div>

        <div className="scripts-scope-pills">
          <button
            className={`scope-pill ${scopeFilter === "all" ? "scope-pill-active" : ""}`}
            onClick={() => setScopeFilter("all")}
          >
            All ({scripts.length})
          </button>
          <button
            className={`scope-pill ${scopeFilter === "global" ? "scope-pill-active" : ""}`}
            onClick={() => setScopeFilter("global")}
          >
            <Globe size={12} />
            <span>Global</span>
          </button>
          <button
            className={`scope-pill ${scopeFilter === "project" ? "scope-pill-active" : ""}`}
            onClick={() => setScopeFilter("project")}
          >
            <Folder size={12} />
            <span>Project</span>
          </button>
        </div>
      </div>

      {/* Error alert banner */}
      {error && (
        <div className="scripts-error-banner">
          <AlertCircle size={15} />
          <span>{error}</span>
          <button className="scripts-error-dismiss" onClick={() => setError(null)}>
            <X size={13} />
          </button>
        </div>
      )}

      {/* Content Area */}
      {loading ? (
        <div className="scripts-loading-state">
          <div className="status-dot-pulse" style={{ width: 10, height: 10 }} />
          <span>Loading scripts...</span>
        </div>
      ) : filteredScripts.length === 0 ? (
        <div className="scripts-empty-state">
          <div className="scripts-empty-icon-wrap">
            <ScrollText size={32} />
          </div>
          <h2 className="scripts-empty-title">No scripts yet</h2>
          <p className="scripts-empty-desc">
            Save commands you use often and run them from Orbit whenever you need.
          </p>
          <button className="orbit-btn-primary scripts-empty-cta" onClick={openCreateModal}>
            <Plus size={15} />
            <span>New Script</span>
          </button>
        </div>
      ) : (
        <div className="scripts-grid">
          {filteredScripts.map((script) => (
            <div key={script.id} className="script-card">
              {/* Left: Quick Run Button */}
              <button
                className="script-run-btn"
                title={`Run "${script.name}" in Terminal`}
                onClick={() => onRunScript(script)}
              >
                <Play size={18} className="script-run-icon" />
              </button>

              {/* Center: Script Details */}
              <div className="script-info" onClick={() => openEditModal(script)}>
                <div className="script-name-row">
                  <span className="script-name">{script.name}</span>
                  {script.projectPath ? (
                    <span className="script-badge script-badge-project" title={`Project: ${script.projectPath}`}>
                      <Folder size={11} />
                      <span>{script.projectPath.split("/").filter(Boolean).pop() || "Project"}</span>
                    </span>
                  ) : (
                    <span className="script-badge script-badge-global">
                      <Globe size={11} />
                      <span>Global</span>
                    </span>
                  )}
                </div>

                {script.description && (
                  <p className="script-description">{script.description}</p>
                )}

                <div className="script-meta-row font-mono">
                  {script.workingDirectory ? (
                    <span className="script-meta-item" title={`Working Directory: ${script.workingDirectory}`}>
                      <Terminal size={11} />
                      <span className="script-meta-cwd">{script.workingDirectory}</span>
                    </span>
                  ) : (
                    <span className="script-meta-item script-meta-cwd-default">
                      <Terminal size={11} />
                      <span>Default CWD</span>
                    </span>
                  )}

                  <span className="script-meta-item" title="Line count">
                    <Layers size={11} />
                    <span>{script.content.split("\n").filter((l) => l.trim().length > 0).length} lines</span>
                  </span>
                </div>
              </div>

              {/* Right: Actions */}
              <div className="script-actions">
                <button
                  className="script-action-btn"
                  title="Edit script"
                  onClick={() => openEditModal(script)}
                >
                  <Edit2 size={14} />
                </button>
                <button
                  className="script-action-btn script-delete-btn"
                  title="Delete script"
                  disabled={deletingId === script.id}
                  onClick={() => {
                    if (window.confirm(`Delete script "${script.name}"?`)) {
                      handleDelete(script.id);
                    }
                  }}
                >
                  <Trash2 size={14} />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Create / Edit Modal Dialog */}
      {isModalOpen && (
        <div className="orbit-modal-overlay" onClick={() => setIsModalOpen(false)}>
          <div className="orbit-modal-card scripts-editor-modal" onClick={(e) => e.stopPropagation()}>
            <div className="orbit-modal-header">
              <div className="orbit-modal-header-left">
                <div className="modal-icon-badge">
                  <ScrollText size={16} />
                </div>
                <div>
                  <h3 className="orbit-modal-title">
                    {editingScript ? "Edit Script" : "New Script"}
                  </h3>
                  <p className="orbit-modal-subtitle">
                    Configure command and target working directory
                  </p>
                </div>
              </div>
              <button
                className="orbit-modal-close-btn"
                onClick={() => setIsModalOpen(false)}
              >
                <X size={16} />
              </button>
            </div>

            <form onSubmit={handleSave}>
              <div className="orbit-modal-body scripts-editor-body">
                {formError && (
                  <div className="scripts-form-error">
                    <AlertCircle size={14} />
                    <span>{formError}</span>
                  </div>
                )}

                {/* Name */}
                <div className="scripts-form-group">
                  <label className="scripts-form-label">NAME</label>
                  <input
                    type="text"
                    className="scripts-form-input font-sans"
                    placeholder="e.g., Build Android, Run Tests, Deploy Staging"
                    value={formName}
                    onChange={(e) => setFormName(e.target.value)}
                    autoFocus
                  />
                </div>

                {/* Description */}
                <div className="scripts-form-group">
                  <label className="scripts-form-label">DESCRIPTION (OPTIONAL)</label>
                  <input
                    type="text"
                    className="scripts-form-input font-sans"
                    placeholder="Brief description of what this command does"
                    value={formDescription}
                    onChange={(e) => setFormDescription(e.target.value)}
                  />
                </div>

                {/* Scope Selection */}
                <div className="scripts-form-group">
                  <label className="scripts-form-label">SCOPE</label>
                  <div className="scripts-scope-selector">
                    <button
                      type="button"
                      className={`scope-select-btn ${formScope === "global" ? "scope-select-active" : ""}`}
                      onClick={() => setFormScope("global")}
                    >
                      <Globe size={14} />
                      <span>Global (All Projects)</span>
                    </button>
                    <button
                      type="button"
                      className={`scope-select-btn ${formScope === "project" ? "scope-select-active" : ""}`}
                      onClick={() => setFormScope("project")}
                    >
                      <Folder size={14} />
                      <span>Project-Specific</span>
                    </button>
                  </div>
                </div>

                {/* Project Path if project scoped */}
                {formScope === "project" && (
                  <div className="scripts-form-group">
                    <label className="scripts-form-label">PROJECT PATH</label>
                    <input
                      type="text"
                      className="scripts-form-input font-mono"
                      placeholder="/home/user/my-project"
                      value={formProjectPath}
                      onChange={(e) => {
                        setFormProjectPath(e.target.value);
                        if (!formWorkingDirectory) {
                          setFormWorkingDirectory(e.target.value);
                        }
                      }}
                    />
                  </div>
                )}

                {/* Working Directory */}
                <div className="scripts-form-group">
                  <label className="scripts-form-label">
                    WORKING DIRECTORY {formScope === "project" ? "(DEFAULTS TO PROJECT PATH)" : "(OPTIONAL)"}
                  </label>
                  <input
                    type="text"
                    className="scripts-form-input font-mono"
                    placeholder={formScope === "project" ? formProjectPath || "/path/to/project" : "/home/user"}
                    value={formWorkingDirectory}
                    onChange={(e) => setFormWorkingDirectory(e.target.value)}
                  />
                </div>

                {/* Monospace Script Content Editor */}
                <div className="scripts-form-group">
                  <label className="scripts-form-label">SCRIPT COMMAND(S)</label>
                  <div className="scripts-editor-wrapper">
                    <textarea
                      className="scripts-code-textarea font-mono"
                      rows={7}
                      placeholder={`# Enter terminal command(s) to execute\nflutter clean\nflutter pub get\nflutter build apk --release`}
                      value={formContent}
                      onChange={(e) => setFormContent(e.target.value)}
                      onKeyDown={handleTextareaKeyDown}
                      spellCheck={false}
                    />
                  </div>
                </div>
              </div>

              <div className="orbit-modal-footer">
                <button
                  type="button"
                  className="scripts-btn-cancel"
                  onClick={() => setIsModalOpen(false)}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="orbit-btn-primary scripts-btn-save"
                  disabled={isSaving}
                >
                  {isSaving ? "Saving..." : editingScript ? "Update Script" : "Save Script"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
