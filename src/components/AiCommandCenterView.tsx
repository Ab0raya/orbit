import React, { useState, useEffect, useRef, useMemo, useCallback } from "react";
import {
  Plus,
  Search,
  Bot,
  Send,
  Square,
  ChevronDown,
  ChevronRight,
  MoreVertical,
  Download,
  Trash2,
  Edit2,
  AlertTriangle,
  Folder,
  RefreshCw,
  Sparkles,
  Settings as SettingsIcon,
  CheckCircle2,
  XCircle,
  Cpu,
} from "lucide-react";
import {
  AiConversationSummary,
  AiConversationDetail,
  AiConversationMessage,
  AiModelSummary,
  AiActivity,
  AiTaskSummary,
  OpencodeStatusPayload,
} from "../types/ai";
import { aiService } from "../services/aiService";

interface AiCommandCenterViewProps {
  onOpenSettings?: () => void;
  defaultProjectPath?: string;
}

export const AiCommandCenterView: React.FC<AiCommandCenterViewProps> = ({
  onOpenSettings,
  defaultProjectPath = "/home/developer/orbit",
}) => {
  // State
  const [conversations, setConversations] = useState<AiConversationSummary[]>([]);
  const [activeConversationId, setActiveConversationId] = useState<string | null>(null);
  const [activeConversation, setActiveConversation] = useState<AiConversationDetail | null>(null);
  const [searchQuery, setSearchQuery] = useState<string>("");
  const [models, setModels] = useState<AiModelSummary[]>([]);
  const [selectedModel, setSelectedModel] = useState<string>("gpt-4o");
  const [contextType, setContextType] = useState<"none" | "project" | "directory">("project");
  const [contextPath, setContextPath] = useState<string>(defaultProjectPath);
  const [promptInput, setPromptInput] = useState<string>("");
  const [activeTask, setActiveTask] = useState<AiTaskSummary | null>(null);
  const [runningTaskId, setRunningTaskId] = useState<string | null>(null);
  const [isStreaming, setIsStreaming] = useState<boolean>(false);
  const [streamingContent, setStreamingContent] = useState<string>("");
  const [streamingActivities, setStreamingActivities] = useState<AiActivity[]>([]);
  const [editingTitle, setEditingTitle] = useState<boolean>(false);
  const [newTitle, setNewTitle] = useState<string>("");
  const [modelDropdownOpen, setModelDropdownOpen] = useState<boolean>(false);
  const [menuOpenId, setMenuOpenId] = useState<string | null>(null);
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null);
  const [deleteWithSession, setDeleteWithSession] = useState<boolean>(false);
  const [sessionUnavailable, setSessionUnavailable] = useState<boolean>(false);
  const [activitiesExpanded, setActivitiesExpanded] = useState<Record<string, boolean>>({});
  const [engineStatus, setEngineStatus] = useState<OpencodeStatusPayload | null>(null);

  const transcriptEndRef = useRef<HTMLDivElement>(null);
  const transcriptContainerRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const checkEngineStatus = useCallback(async () => {
    try {
      const s = await aiService.getOpencodeStatus();
      setEngineStatus(s);
      return s;
    } catch (err) {
      console.error("Failed to check AI engine status:", err);
      return null;
    }
  }, []);

  const handleRetryInstall = async () => {
    try {
      setEngineStatus({
        state: "installing",
        userMessage: "Preparing AI engine...",
        isReady: false,
      });
      const s = await aiService.installOpencode();
      setEngineStatus(s);
    } catch (err) {
      console.error("Failed to retry install:", err);
    }
  };

  useEffect(() => {
    let timer: any;
    const poll = async () => {
      const s = await checkEngineStatus();
      if (s && (s.state === "checking" || s.state === "installing" || s.state === "updating")) {
        timer = setTimeout(poll, 2000);
      }
    };
    poll();
    return () => clearTimeout(timer);
  }, [checkEngineStatus]);

  // Load initial conversations & models
  const loadConversations = useCallback(async () => {
    try {
      const list = await aiService.listConversations(100);
      setConversations(list);
      if (list.length > 0 && !activeConversationId) {
        setActiveConversationId(list[0].id);
      }
    } catch (err) {
      console.error("Failed to load conversations:", err);
    }
  }, [activeConversationId]);

  const loadModels = useCallback(async () => {
    try {
      const mList = await aiService.listModels();
      setModels(mList);
      const defaults = await aiService.getDefaults();
      if (defaults.default_model) {
        setSelectedModel(defaults.default_model);
      }
    } catch (err) {
      console.error("Failed to load models:", err);
    }
  }, []);

  useEffect(() => {
    loadConversations();
    loadModels();
  }, [loadConversations, loadModels]);

  // Load detail when activeConversationId changes
  useEffect(() => {
    if (!activeConversationId) {
      setActiveConversation(null);
      setSessionUnavailable(false);
      return;
    }
    aiService.getConversation(activeConversationId).then((detail) => {
      setActiveConversation(detail);
      if (detail?.model_id) {
        setSelectedModel(detail.model_id);
      }
      if (detail?.project_path) {
        setContextPath(detail.project_path);
      }
      if (detail?.context_type) {
        setContextType(detail.context_type as any);
      }
      setSessionUnavailable(false);
    }).catch((err) => {
      console.error("Failed to load conversation detail:", err);
    });
  }, [activeConversationId]);

  // Scroll to bottom on new messages
  useEffect(() => {
    if (transcriptContainerRef.current) {
      transcriptContainerRef.current.scrollTo({
        top: transcriptContainerRef.current.scrollHeight,
        behavior: "smooth",
      });
    }
  }, [activeConversation?.messages, streamingContent, streamingActivities]);

  // Listen to Tauri AI streaming events
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    aiService.onAiEvent((ev) => {
      if (!ev) return;
      if (ev.type === "ai.task.response" || ev.action === "ai.task.response") {
        const chunk = ev.payload?.chunk || ev.chunk || "";
        if (chunk) {
          setStreamingContent((prev) => prev + chunk);
        }
      } else if (ev.type === "ai.task.activity" || ev.action === "ai.task.activity") {
        const act: AiActivity = ev.payload || ev;
        if (act.tool) {
          setStreamingActivities((prev) => {
            const idx = prev.findIndex((a) => a.id === act.id);
            if (idx >= 0) {
              const updated = [...prev];
              updated[idx] = act;
              return updated;
            }
            return [...prev, act];
          });
        }
      } else if (ev.type === "ai.task.completed" || ev.event === "ai.task.completed") {
        setIsStreaming(false);
        setRunningTaskId(null);
        setActiveTask(null);
        loadConversations();
        if (activeConversationId) {
          aiService.getConversation(activeConversationId).then(setActiveConversation);
        }
      } else if (ev.type === "ai.task.failed" || ev.event === "ai.task.failed") {
        setIsStreaming(false);
        setRunningTaskId(null);
        setActiveTask(null);
        loadConversations();
        if (activeConversationId) {
          aiService.getConversation(activeConversationId).then(setActiveConversation);
        }
      }
    }).then((cleanup) => {
      unlisten = cleanup;
    }).catch(console.error);

    return () => {
      if (unlisten) unlisten();
    };
  }, [activeConversationId, loadConversations]);

  // Group conversations by date
  const categorizedConversations = useMemo(() => {
    const now = Date.now() / 1000;
    const oneDay = 86400;
    const sevenDays = 7 * oneDay;

    const today: AiConversationSummary[] = [];
    const yesterday: AiConversationSummary[] = [];
    const previous7Days: AiConversationSummary[] = [];
    const older: AiConversationSummary[] = [];

    const filtered = conversations.filter((c) => {
      if (!searchQuery.trim()) return true;
      const q = searchQuery.toLowerCase();
      return (
        c.title.toLowerCase().includes(q) ||
        (c.last_message_preview && c.last_message_preview.toLowerCase().includes(q)) ||
        (c.project_path && c.project_path.toLowerCase().includes(q)) ||
        (c.model_id && c.model_id.toLowerCase().includes(q))
      );
    });

    for (const conv of filtered) {
      const diff = now - conv.updated_at;
      if (diff < oneDay) {
        today.push(conv);
      } else if (diff < 2 * oneDay) {
        yesterday.push(conv);
      } else if (diff < sevenDays) {
        previous7Days.push(conv);
      } else {
        older.push(conv);
      }
    }

    return { today, yesterday, previous7Days, older };
  }, [conversations, searchQuery]);

  // Format relative timestamp
  const formatTime = (ts: number): string => {
    const d = new Date(ts * 1000);
    return d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  };

  // Actions
  const handleNewChat = async () => {
    try {
      const created = await aiService.createConversation({
        title: "New Conversation",
        projectPath: contextType === "project" ? contextPath : undefined,
        directoryPath: contextType === "directory" ? contextPath : undefined,
        contextType,
        modelId: selectedModel,
      });
      await loadConversations();
      setActiveConversationId(created.id);
      setPromptInput("");
      textareaRef.current?.focus();
    } catch (err) {
      console.error("Failed to create conversation:", err);
    }
  };

  const handleSendMessage = async (customPrompt?: string) => {
    const promptToSend = (customPrompt || promptInput).trim();
    if (!promptToSend || isStreaming) return;

    setPromptInput("");
    setIsStreaming(true);
    setStreamingContent("");
    setStreamingActivities([]);

    let convId = activeConversationId;
    let sessionId = activeConversation?.open_code_session_id;

    // If no active conversation, create one first
    if (!convId) {
      try {
        const created = await aiService.createConversation({
          title: promptToSend.slice(0, 40),
          projectPath: contextType === "project" ? contextPath : undefined,
          directoryPath: contextType === "directory" ? contextPath : undefined,
          contextType,
          modelId: selectedModel,
        });
        convId = created.id;
        setActiveConversationId(created.id);
        await loadConversations();
      } catch (err) {
        console.error("Failed to auto-create conversation:", err);
        setIsStreaming(false);
        return;
      }
    }

    // Check AI engine readiness
    if (engineStatus && !engineStatus.isReady) {
      if (engineStatus.state === "error") {
        alert("AI engine is currently unavailable. Please click Retry to install.");
      } else {
        alert(engineStatus.userMessage || "Preparing AI engine... Please wait a moment.");
      }
      setIsStreaming(false);
      return;
    }

    // Optimistically add user message into UI
    const optimisticUserMsg: AiConversationMessage = {
      id: "opt_user_" + Date.now(),
      conversation_id: convId,
      role: "user",
      content: promptToSend,
      created_at: Math.floor(Date.now() / 1000),
      status: "completed",
      activities: [],
    };

    setActiveConversation((prev) => {
      if (!prev) return null;
      return {
        ...prev,
        messages: [...prev.messages, optimisticUserMsg],
      };
    });

    try {
      let taskSummary: AiTaskSummary;
      if (sessionId && !sessionUnavailable) {
        try {
          taskSummary = await aiService.resumeTask({
            sessionId,
            prompt: promptToSend,
            projectPath: contextType !== "none" ? contextPath : undefined,
            conversationId: convId,
            model: selectedModel,
          });
        } catch (resumeErr: any) {
          // If session expired or unavailable, flag it and start new task
          if (resumeErr?.includes?.("SESSION_NOT_FOUND") || resumeErr?.includes?.("unavailable")) {
            setSessionUnavailable(true);
            taskSummary = await aiService.startTask({
              prompt: promptToSend,
              projectPath: contextType !== "none" ? contextPath : undefined,
              conversationId: convId,
              model: selectedModel,
            });
          } else {
            throw resumeErr;
          }
        }
      } else {
        taskSummary = await aiService.startTask({
          prompt: promptToSend,
          projectPath: contextType !== "none" ? contextPath : undefined,
          conversationId: convId,
          model: selectedModel,
        });
      }

      setActiveTask(taskSummary);
      setRunningTaskId(taskSummary.taskId);
    } catch (err: any) {
      console.error("Failed to send AI prompt:", err);
      setIsStreaming(false);
      setActiveTask(null);
      setRunningTaskId(null);

      // Append error message
      const errorMsg: AiConversationMessage = {
        id: "opt_err_" + Date.now(),
        conversation_id: convId,
        role: "assistant",
        content: "AI request failed.",
        created_at: Math.floor(Date.now() / 1000),
        status: "failed",
        error: typeof err === "string" ? err : err.message || "Failed to execute AI request",
        activities: [],
      };
      setActiveConversation((prev) => {
        if (!prev) return null;
        return {
          ...prev,
          messages: [...prev.messages, errorMsg],
        };
      });
    }
  };

  const handleCancelTask = async () => {
    if (!runningTaskId) return;
    try {
      await aiService.cancelTask(runningTaskId);
      setIsStreaming(false);
      setRunningTaskId(null);
      setActiveTask(null);
    } catch (err) {
      console.error("Failed to cancel task:", err);
    }
  };

  const handleRenameSave = async () => {
    if (!activeConversationId || !newTitle.trim()) return;
    try {
      await aiService.renameConversation(activeConversationId, newTitle.trim());
      setEditingTitle(false);
      await loadConversations();
      if (activeConversation) {
        setActiveConversation({ ...activeConversation, title: newTitle.trim() });
      }
    } catch (err) {
      console.error("Failed to rename:", err);
    }
  };

  const handleDeleteConversation = async (id: string, withSession: boolean) => {
    try {
      await aiService.deleteConversation(id, withSession);
      setConfirmDeleteId(null);
      setMenuOpenId(null);
      await loadConversations();
      if (activeConversationId === id) {
        const remaining = conversations.filter((c) => c.id !== id);
        setActiveConversationId(remaining.length > 0 ? remaining[0].id : null);
      }
    } catch (err) {
      console.error("Failed to delete conversation:", err);
    }
  };

  const handleExport = async (format: "markdown" | "json") => {
    if (!activeConversationId) return;
    try {
      const content = await aiService.exportConversation(activeConversationId, format);
      const blob = new Blob([content], {
        type: format === "json" ? "application/json" : "text/markdown",
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `conversation_${activeConversationId.slice(0, 8)}.${format === "json" ? "json" : "md"}`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      console.error("Export failed:", err);
    }
  };

  // Group models by provider for dropdown
  const modelsByProvider = useMemo(() => {
    const map: Record<string, AiModelSummary[]> = {};
    for (const m of models) {
      const prov = m.provider.toUpperCase();
      if (!map[prov]) map[prov] = [];
      map[prov].push(m);
    }
    return map;
  }, [models]);

  const toggleActivity = (msgId: string) => {
    setActivitiesExpanded((prev) => ({
      ...prev,
      [msgId]: !prev[msgId],
    }));
  };

  return (
    <div className="orbit-ai-command-center">
      {/* ============================================================ */}
      {/* LEFT SIDEBAR: Conversations, Search, History Categorization  */}
      {/* ============================================================ */}
      <div className="ai-sidebar">
        {/* Header with Title & + New Chat */}
        <div className="ai-sidebar-header">
          <div className="ai-sidebar-title-row">
            <div className="ai-badge-group">
              <Bot size={15} className="ai-spark-icon" />
              <span className="ai-sidebar-title font-mono">AI COMMAND CENTER</span>
            </div>
            {onOpenSettings && (
              <button
                className="ai-icon-btn"
                title="AI Settings & Providers"
                onClick={onOpenSettings}
              >
                <SettingsIcon size={14} />
              </button>
            )}
          </div>

          <button className="ai-new-chat-btn" onClick={handleNewChat}>
            <Plus size={14} />
            <span>New Chat</span>
          </button>
        </div>

        {/* Search Input */}
        <div className="ai-search-box">
          <Search size={13} className="ai-search-icon" />
          <input
            type="text"
            placeholder="Search conversations..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="ai-search-input"
          />
          {searchQuery && (
            <button className="ai-search-clear" onClick={() => setSearchQuery("")}>
              ✕
            </button>
          )}
        </div>

        {/* Conversation List categorized */}
        <div className="ai-conversation-list">
          {conversations.length === 0 ? (
            <div className="ai-sidebar-empty">
              <Sparkles size={20} className="ai-empty-sparkle" />
              <div className="ai-empty-title">No conversations yet</div>
              <div className="ai-empty-desc">Start a chat to inspect code, run tests, or debug.</div>
            </div>
          ) : (
            <>
              {/* TODAY */}
              {categorizedConversations.today.length > 0 && (
                <div className="ai-category-group">
                  <div className="ai-category-label font-mono">TODAY</div>
                  {categorizedConversations.today.map((conv) => (
                    <ConversationListItem
                      key={conv.id}
                      conv={conv}
                      isActive={conv.id === activeConversationId}
                      isRunning={conv.id === activeConversationId && isStreaming}
                      formatTime={formatTime}
                      onSelect={() => setActiveConversationId(conv.id)}
                      onOpenMenu={(e) => {
                        e.stopPropagation();
                        setMenuOpenId(menuOpenId === conv.id ? null : conv.id);
                      }}
                      menuOpen={menuOpenId === conv.id}
                      onRename={() => {
                        setActiveConversationId(conv.id);
                        setNewTitle(conv.title);
                        setEditingTitle(true);
                        setMenuOpenId(null);
                      }}
                      onDelete={() => {
                        setConfirmDeleteId(conv.id);
                        setMenuOpenId(null);
                      }}
                    />
                  ))}
                </div>
              )}

              {/* YESTERDAY */}
              {categorizedConversations.yesterday.length > 0 && (
                <div className="ai-category-group">
                  <div className="ai-category-label font-mono">YESTERDAY</div>
                  {categorizedConversations.yesterday.map((conv) => (
                    <ConversationListItem
                      key={conv.id}
                      conv={conv}
                      isActive={conv.id === activeConversationId}
                      isRunning={conv.id === activeConversationId && isStreaming}
                      formatTime={formatTime}
                      onSelect={() => setActiveConversationId(conv.id)}
                      onOpenMenu={(e) => {
                        e.stopPropagation();
                        setMenuOpenId(menuOpenId === conv.id ? null : conv.id);
                      }}
                      menuOpen={menuOpenId === conv.id}
                      onRename={() => {
                        setActiveConversationId(conv.id);
                        setNewTitle(conv.title);
                        setEditingTitle(true);
                        setMenuOpenId(null);
                      }}
                      onDelete={() => {
                        setConfirmDeleteId(conv.id);
                        setMenuOpenId(null);
                      }}
                    />
                  ))}
                </div>
              )}

              {/* PREVIOUS 7 DAYS */}
              {categorizedConversations.previous7Days.length > 0 && (
                <div className="ai-category-group">
                  <div className="ai-category-label font-mono">PREVIOUS 7 DAYS</div>
                  {categorizedConversations.previous7Days.map((conv) => (
                    <ConversationListItem
                      key={conv.id}
                      conv={conv}
                      isActive={conv.id === activeConversationId}
                      isRunning={conv.id === activeConversationId && isStreaming}
                      formatTime={formatTime}
                      onSelect={() => setActiveConversationId(conv.id)}
                      onOpenMenu={(e) => {
                        e.stopPropagation();
                        setMenuOpenId(menuOpenId === conv.id ? null : conv.id);
                      }}
                      menuOpen={menuOpenId === conv.id}
                      onRename={() => {
                        setActiveConversationId(conv.id);
                        setNewTitle(conv.title);
                        setEditingTitle(true);
                        setMenuOpenId(null);
                      }}
                      onDelete={() => {
                        setConfirmDeleteId(conv.id);
                        setMenuOpenId(null);
                      }}
                    />
                  ))}
                </div>
              )}

              {/* OLDER */}
              {categorizedConversations.older.length > 0 && (
                <div className="ai-category-group">
                  <div className="ai-category-label font-mono">OLDER</div>
                  {categorizedConversations.older.map((conv) => (
                    <ConversationListItem
                      key={conv.id}
                      conv={conv}
                      isActive={conv.id === activeConversationId}
                      isRunning={conv.id === activeConversationId && isStreaming}
                      formatTime={formatTime}
                      onSelect={() => setActiveConversationId(conv.id)}
                      onOpenMenu={(e) => {
                        e.stopPropagation();
                        setMenuOpenId(menuOpenId === conv.id ? null : conv.id);
                      }}
                      menuOpen={menuOpenId === conv.id}
                      onRename={() => {
                        setActiveConversationId(conv.id);
                        setNewTitle(conv.title);
                        setEditingTitle(true);
                        setMenuOpenId(null);
                      }}
                      onDelete={() => {
                        setConfirmDeleteId(conv.id);
                        setMenuOpenId(null);
                      }}
                    />
                  ))}
                </div>
              )}
            </>
          )}
        </div>
      </div>

      {/* ============================================================ */}
      {/* RIGHT PANEL: Header, Model Override, Transcript, Activity    */}
      {/* ============================================================ */}
      <div className="ai-workspace-main">
        {/* Conversation Header */}
        <div className="ai-workspace-header">
          <div className="ai-header-left">
            {editingTitle ? (
              <div className="ai-title-edit-form">
                <input
                  type="text"
                  value={newTitle}
                  onChange={(e) => setNewTitle(e.target.value)}
                  className="ai-title-input"
                  autoFocus
                  onKeyDown={(e) => {
                    if (e.key === "Enter") handleRenameSave();
                    if (e.key === "Escape") setEditingTitle(false);
                  }}
                />
                <button className="ai-btn-sm ai-btn-primary" onClick={handleRenameSave}>
                  Save
                </button>
                <button className="ai-btn-sm" onClick={() => setEditingTitle(false)}>
                  Cancel
                </button>
              </div>
            ) : (
              <div className="ai-title-display-row">
                <h2 className="ai-conversation-title">
                  {activeConversation?.title || "New Chat"}
                </h2>
                {activeConversation && (
                  <button
                    className="ai-edit-title-btn"
                    title="Rename conversation"
                    onClick={() => {
                      setNewTitle(activeConversation.title);
                      setEditingTitle(true);
                    }}
                  >
                    <Edit2 size={13} />
                  </button>
                )}
              </div>
            )}

            {/* Metadata Pills */}
            <div className="ai-header-meta">
              <span className="ai-meta-pill">
                <Folder size={11} />
                <span>
                  {activeConversation?.project_path
                    ? activeConversation.project_path.split("/").pop() || "Orbit"
                    : "No Context"}
                </span>
              </span>

              <span className="ai-meta-pill font-mono">
                <Cpu size={11} />
                <span>{selectedModel}</span>
              </span>

              {engineStatus && (
                <span
                  className={`ai-status-pill ${
                    engineStatus.isReady
                      ? "ai-status-completed"
                      : engineStatus.state === "error"
                      ? "ai-status-failed"
                      : "ai-status-running"
                  }`}
                  title={engineStatus.path || engineStatus.error || undefined}
                >
                  <span className={engineStatus.isReady ? "" : "status-dot-pulse"} />
                  <span>{engineStatus.userMessage}</span>
                </span>
              )}

              {isStreaming ? (
                <span className="ai-status-pill ai-status-running">
                  <span className="status-dot-pulse" />
                  <span>Running</span>
                </span>
              ) : (
                <span className="ai-status-pill ai-status-completed">
                  <CheckCircle2 size={11} />
                  <span>{activeConversation?.status || "Ready"}</span>
                </span>
              )}
            </div>
          </div>

          {/* Right Header Controls: Model Selector, Export, Delete */}
          <div className="ai-header-right">
            {/* Model Selector Dropdown */}
            <div className="ai-model-selector-container">
              <button
                className="ai-model-selector-btn"
                onClick={() => setModelDropdownOpen(!modelDropdownOpen)}
              >
                <span className="font-mono">{selectedModel}</span>
                <ChevronDown size={13} />
              </button>

              {modelDropdownOpen && (
                <div className="ai-model-dropdown-menu">
                  {Object.entries(modelsByProvider).map(([provider, mList]) => (
                    <div key={provider} className="ai-dropdown-group">
                      <div className="ai-dropdown-group-label font-mono">{provider}</div>
                      {mList.map((m) => (
                        <button
                          key={m.id}
                          className={`ai-dropdown-item ${m.id === selectedModel ? "ai-item-active" : ""}`}
                          onClick={() => {
                            setSelectedModel(m.id);
                            setModelDropdownOpen(false);
                          }}
                        >
                          <div className="ai-item-name font-mono">{m.name}</div>
                          {m.context_window && (
                            <div className="ai-item-meta font-mono">
                              {(m.context_window / 1000).toFixed(0)}k ctx
                            </div>
                          )}
                        </button>
                      ))}
                    </div>
                  ))}
                  {models.length === 0 && (
                    <div className="ai-dropdown-empty">No models configured</div>
                  )}
                </div>
              )}
            </div>

            {/* Export Dropdown / Buttons */}
            {activeConversation && (
              <div className="ai-export-btn-group">
                <button
                  className="ai-icon-btn"
                  title="Export Markdown"
                  onClick={() => handleExport("markdown")}
                >
                  <Download size={14} />
                  <span>MD</span>
                </button>
                <button
                  className="ai-icon-btn"
                  title="Export JSON"
                  onClick={() => handleExport("json")}
                >
                  <span>JSON</span>
                </button>
              </div>
            )}
          </div>
        </div>

        {/* Minimal Engine Provisioning Banner */}
        {engineStatus && !engineStatus.isReady && (
          <div
            className="ai-provisioning-banner"
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              padding: "10px 16px",
              background: engineStatus.state === "error" ? "rgba(239, 68, 68, 0.12)" : "rgba(99, 102, 241, 0.12)",
              borderBottom: engineStatus.state === "error" ? "1px solid rgba(239, 68, 68, 0.25)" : "1px solid rgba(99, 102, 241, 0.25)",
              fontSize: "13px",
              color: engineStatus.state === "error" ? "#fca5a5" : "#c7d2fe",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
              <span
                className="status-dot-pulse"
                style={{
                  background: engineStatus.state === "error" ? "#ef4444" : "#818cf8",
                }}
              />
              <span>{engineStatus.userMessage}</span>
            </div>
            {engineStatus.state === "error" && (
              <button
                onClick={handleRetryInstall}
                style={{
                  background: "#4f46e5",
                  color: "#fff",
                  border: "none",
                  padding: "4px 12px",
                  borderRadius: "4px",
                  cursor: "pointer",
                  fontSize: "12px",
                  fontWeight: 500,
                }}
              >
                Retry
              </button>
            )}
          </div>
        )}

        {/* Active Task Banner if running */}
        {isStreaming && (
          <div className="ai-active-task-banner">
            <div className="ai-banner-left">
              <span className="ai-banner-pulse" />
              <div className="ai-banner-text">
                <span className="ai-banner-status font-mono">● RUNNING</span>
                <span className="ai-banner-task font-mono">
                  {activeTask?.prompt || "Executing task with OpenCode..."}
                </span>
              </div>
            </div>
            <div className="ai-banner-right">
              <button className="ai-btn-sm ai-btn-danger" onClick={handleCancelTask}>
                <Square size={11} />
                <span>Cancel</span>
              </button>
            </div>
          </div>
        )}

        {/* Session Unavailable Notice */}
        {sessionUnavailable && (
          <div className="ai-session-warning-banner">
            <AlertTriangle size={14} className="ai-warning-icon" />
            <span>Execution session unavailable. Preserving conversation history.</span>
            <button
              className="ai-btn-sm ai-btn-primary"
              onClick={() => {
                setSessionUnavailable(false);
                handleSendMessage("Resume task in new session");
              }}
            >
              Start New Session
            </button>
          </div>
        )}

        {/* Workspace Body / Transcript */}
        <div className="ai-transcript-area" ref={transcriptContainerRef}>
          {!activeConversation || activeConversation.messages.length === 0 ? (
            /* Clean Empty State */
            <div className="ai-empty-hero">
              <div className="ai-hero-icon-wrap">
                <Sparkles size={28} className="ai-hero-sparkle" />
              </div>
              <h1 className="ai-hero-title">WHAT CAN I HELP YOU BUILD?</h1>
              <p className="ai-hero-subtitle">
                Ask about your codebase, inspect files, run commands, debug issues, or make changes.
              </p>

              {/* Context Selector */}
              <div className="ai-context-selector-card">
                <span className="ai-context-label font-mono">CONTEXT</span>
                <div className="ai-context-capsules">
                  <button
                    className={`ai-context-capsule ${contextType === "none" ? "capsule-active" : ""}`}
                    onClick={() => setContextType("none")}
                  >
                    ○ No context
                  </button>
                  <button
                    className={`ai-context-capsule ${contextType === "project" ? "capsule-active" : ""}`}
                    onClick={() => setContextType("project")}
                  >
                    ● Project ({defaultProjectPath.split("/").pop() || "orbit"})
                  </button>
                  <button
                    className={`ai-context-capsule ${contextType === "directory" ? "capsule-active" : ""}`}
                    onClick={() => setContextType("directory")}
                  >
                    ○ Directory
                  </button>
                </div>
              </div>

              {/* Suggested Prompts */}
              <div className="ai-suggested-prompts-grid">
                {[
                  "Explain this project",
                  "Find a bug",
                  "Review recent changes",
                  "Analyze the build",
                  "Improve this code",
                ].map((prompt) => (
                  <button
                    key={prompt}
                    className="ai-prompt-pill"
                    onClick={() => handleSendMessage(prompt)}
                  >
                    <ChevronRight size={13} className="ai-prompt-chevron" />
                    <span>{prompt}</span>
                  </button>
                ))}
              </div>
            </div>
          ) : (
            /* Transcript Messages */
            <div className="ai-messages-list">
              {activeConversation.messages.map((msg) => (
                <div key={msg.id} className={`ai-message-row ai-msg-${msg.role}`}>
                  <div className="ai-message-avatar font-mono">
                    {msg.role === "user" ? "YOU" : "ORBIT"}
                  </div>

                  <div className="ai-message-body">
                    <div className="ai-message-header">
                      <span className="ai-msg-author font-mono">
                        {msg.role === "user" ? "User" : "Orbit Assistant"}
                      </span>
                      {msg.model_id && (
                        <span className="ai-msg-model font-mono">{msg.model_id}</span>
                      )}
                      <span className="ai-msg-time font-mono">
                        {formatTime(msg.created_at)}
                      </span>
                    </div>

                    {/* Message Content */}
                    <div className="ai-message-content">
                      {msg.content}
                    </div>

                    {/* Normalized Activity Section */}
                    {msg.activities && msg.activities.length > 0 && (
                      <div className="ai-activity-container">
                        <button
                          className="ai-activity-header-toggle"
                          onClick={() => toggleActivity(msg.id)}
                        >
                          <div className="ai-activity-toggle-left">
                            <span className="ai-activity-tag font-mono">ACTIVITY</span>
                            <span className="ai-activity-stats font-mono">
                              {msg.activities.length} action{msg.activities.length > 1 ? "s" : ""}
                              {msg.activities.some((a) => a.duration_ms > 0) &&
                                ` · ${Math.round(
                                  msg.activities.reduce((acc, a) => acc + (a.duration_ms || 0), 0) / 1000
                                )}s`}
                              {msg.activities.some((a) => a.files_changed) &&
                                ` · ${msg.activities.reduce((acc, a) => acc + (a.files_changed || 0), 0)} files changed`}
                            </span>
                          </div>
                          {activitiesExpanded[msg.id] ? (
                            <ChevronDown size={14} />
                          ) : (
                            <ChevronRight size={14} />
                          )}
                        </button>

                        {activitiesExpanded[msg.id] && (
                          <div className="ai-activity-items-list">
                            {msg.activities.map((act) => (
                              <div key={act.id} className="ai-activity-item">
                                <div className="ai-act-status">
                                  {act.status === "success" ? (
                                    <CheckCircle2 size={13} className="ai-icon-success" />
                                  ) : act.status === "failed" ? (
                                    <XCircle size={13} className="ai-icon-failed" />
                                  ) : (
                                    <span className="status-dot-pulse" />
                                  )}
                                </div>
                                <div className="ai-act-tool font-mono">{act.tool}</div>
                                <div className="ai-act-target font-mono">{act.target || ""}</div>
                                {act.duration_ms > 0 && (
                                  <div className="ai-act-duration font-mono">
                                    {(act.duration_ms / 1000).toFixed(1)}s
                                  </div>
                                )}
                              </div>
                            ))}
                          </div>
                        )}
                      </div>
                    )}

                    {/* Error State Card */}
                    {msg.error && (
                      <div className="ai-message-error-card">
                        <div className="ai-error-header">
                          <AlertTriangle size={15} className="ai-error-icon" />
                          <span className="ai-error-title font-mono">AI REQUEST FAILED</span>
                        </div>
                        <div className="ai-error-body">
                          <div><strong>Provider:</strong> {msg.provider_id || "OpenAI"}</div>
                          <div><strong>Reason:</strong> {msg.error}</div>
                        </div>
                        <div className="ai-error-actions">
                          {onOpenSettings && (
                            <button className="ai-btn-sm" onClick={onOpenSettings}>
                              Manage Provider
                            </button>
                          )}
                          <button
                            className="ai-btn-sm"
                            onClick={() => setModelDropdownOpen(true)}
                          >
                            Change Model
                          </button>
                          <button
                            className="ai-btn-sm ai-btn-primary"
                            onClick={() => handleSendMessage("Retry previous request")}
                          >
                            <RefreshCw size={12} />
                            <span>Retry</span>
                          </button>
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              ))}

              {/* Streaming Live Response */}
              {isStreaming && (
                <div className="ai-message-row ai-msg-assistant">
                  <div className="ai-message-avatar font-mono">ORBIT</div>
                  <div className="ai-message-body">
                    <div className="ai-message-header">
                      <span className="ai-msg-author font-mono">Orbit Assistant</span>
                      <span className="ai-msg-model font-mono">{selectedModel}</span>
                      <span className="ai-status-pill ai-status-running">
                        <span className="status-dot-pulse" />
                        <span>Generating...</span>
                      </span>
                    </div>

                    <div className="ai-message-content">
                      {streamingContent || (
                        <span className="ai-cursor-blink">▍</span>
                      )}
                    </div>

                    {/* Live streaming activities */}
                    {streamingActivities.length > 0 && (
                      <div className="ai-activity-container">
                        <div className="ai-activity-header-toggle">
                          <div className="ai-activity-toggle-left">
                            <span className="ai-activity-tag font-mono">ACTIVITY</span>
                            <span className="ai-activity-stats font-mono">
                              {streamingActivities.length} step(s) in progress
                            </span>
                          </div>
                        </div>
                        <div className="ai-activity-items-list">
                          {streamingActivities.map((act) => (
                            <div key={act.id} className="ai-activity-item">
                              <div className="ai-act-status">
                                {act.status === "success" ? (
                                  <CheckCircle2 size={13} className="ai-icon-success" />
                                ) : (
                                  <span className="status-dot-pulse" />
                                )}
                              </div>
                              <div className="ai-act-tool font-mono">{act.tool}</div>
                              <div className="ai-act-target font-mono">{act.target || ""}</div>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              )}

              <div ref={transcriptEndRef} />
            </div>
          )}
        </div>

        {/* Composer / Follow-up Input */}
        <div className="ai-composer-container">
          <div className="ai-composer-box">
            <textarea
              ref={textareaRef}
              rows={2}
              placeholder={
                activeConversation && activeConversation.messages.length > 0
                  ? "Ask a follow-up..."
                  : "Ask Orbit anything about your codebase..."
              }
              value={promptInput}
              onChange={(e) => setPromptInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  handleSendMessage();
                }
              }}
              className="ai-composer-textarea"
              disabled={isStreaming}
            />

            <div className="ai-composer-footer">
              <div className="ai-composer-meta">
                <span className="ai-composer-pill font-mono">
                  {selectedModel}
                </span>
                <span className="ai-composer-pill font-mono">
                  {contextType === "project"
                    ? "Project: Orbit"
                    : contextType === "directory"
                    ? "Dir: " + contextPath.split("/").pop()
                    : "No Context"}
                </span>
                <span className="ai-composer-hint font-mono">
                  Return to send · Shift+Return for newline
                </span>
              </div>

              <div className="ai-composer-actions">
                {isStreaming ? (
                  <button className="ai-send-btn ai-btn-danger" onClick={handleCancelTask}>
                    <Square size={13} />
                    <span>Stop</span>
                  </button>
                ) : (
                  <button
                    className="ai-send-btn ai-btn-primary"
                    disabled={!promptInput.trim()}
                    onClick={() => handleSendMessage()}
                  >
                    <Send size={13} />
                    <span>Send</span>
                  </button>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Delete Confirmation Modal */}
      {confirmDeleteId && (
        <div className="orbit-modal-backdrop">
          <div className="orbit-modal-content">
            <h3 className="orbit-modal-title">Delete conversation?</h3>
            <p className="orbit-modal-desc">
              This removes the Orbit conversation transcript and stored activity history.
            </p>

            <div className="orbit-modal-checkbox-row">
              <label className="orbit-checkbox-label">
                <input
                  type="checkbox"
                  checked={deleteWithSession}
                  onChange={(e) => setDeleteWithSession(e.target.checked)}
                />
                <span>Also terminate OpenCode execution session if active</span>
              </label>
            </div>

            <div className="orbit-modal-actions">
              <button
                className="ai-btn-sm"
                onClick={() => setConfirmDeleteId(null)}
              >
                Cancel
              </button>
              <button
                className="ai-btn-sm ai-btn-danger"
                onClick={() => handleDeleteConversation(confirmDeleteId, deleteWithSession)}
              >
                <Trash2 size={13} />
                <span>Delete</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

interface ConversationListItemProps {
  conv: AiConversationSummary;
  isActive: boolean;
  isRunning: boolean;
  formatTime: (ts: number) => string;
  onSelect: () => void;
  onOpenMenu: (e: React.MouseEvent) => void;
  menuOpen: boolean;
  onRename: () => void;
  onDelete: () => void;
}

const ConversationListItem: React.FC<ConversationListItemProps> = ({
  conv,
  isActive,
  isRunning,
  formatTime,
  onSelect,
  onOpenMenu,
  menuOpen,
  onRename,
  onDelete,
}) => {
  return (
    <div
      className={`ai-conv-item ${isActive ? "ai-conv-active" : ""}`}
      onClick={onSelect}
    >
      <div className="ai-conv-main">
        <div className="ai-conv-title-row">
          <span className="ai-conv-title">{conv.title}</span>
          {isRunning && <span className="status-dot-pulse" title="Task running" />}
        </div>

        <div className="ai-conv-meta-row font-mono">
          <span className="ai-conv-time">{formatTime(conv.updated_at)}</span>
          {conv.project_path && (
            <span className="ai-conv-project">
              {conv.project_path.split("/").pop() || "Orbit"}
            </span>
          )}
          {conv.model_id && (
            <span className="ai-conv-model">{conv.model_id}</span>
          )}
        </div>
      </div>

      <div className="ai-conv-actions">
        <button className="ai-conv-menu-btn" onClick={onOpenMenu}>
          <MoreVertical size={13} />
        </button>

        {menuOpen && (
          <div className="ai-conv-dropdown-menu">
            <button className="ai-dropdown-action" onClick={onRename}>
              <Edit2 size={12} />
              <span>Rename</span>
            </button>
            <button className="ai-dropdown-action ai-action-danger" onClick={onDelete}>
              <Trash2 size={12} />
              <span>Delete</span>
            </button>
          </div>
        )}
      </div>
    </div>
  );
};
