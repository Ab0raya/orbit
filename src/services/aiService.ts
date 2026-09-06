import { invoke, isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
  AiActivity,
  AiConversationDetail,
  AiConversationMessage,
  AiConversationSummary,
  AiDefaultsConfig,
  AiModelSummary,
  AiProviderSummary,
  AiTaskSummary,
  AiUsageStats,
  OpencodeStatusPayload,
} from "../types/ai";

export const isTauriEnvironment = (): boolean => {
  if (typeof window === "undefined") return false;
  try {
    return isTauri() || "__TAURI_INTERNALS__" in window;
  } catch {
    return false;
  }
};

// ---------------------------------------------------------------------------
// Backend contract notes (src-tauri/src/commands.rs + ai/*):
// - Tauri converts `#[tauri::command]` argument names to lowerCamelCase by
//   default (tauri-macros ArgumentCase::Camel; none of Orbit's commands
//   override it with rename_all). So invoke keys MUST be camelCase
//   (e.g. conversationId, providerId, deleteSession) even though the Rust
//   parameter names are snake_case. Sending snake_case keys fails with
//   "missing required key <camelCaseName>".
// - Return payloads for the ai/* structs are serialized with serde
//   rename_all = "camelCase" (e.g. createdAt, projectPath).
// The normalizers below translate backend shapes into the snake_case
// frontend types used by the AI Command Center UI. The UI itself is
// untouched; this is purely a compatibility layer.
// ---------------------------------------------------------------------------

const asNumber = (v: unknown, fallback = 0): number => {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
};

const parseTokenCount = (v: unknown): number => {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v.replace(/[^0-9]/g, ""));
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
};

const normalizeActivity = (b: any): AiActivity => {
  const rawStatus = b?.status;
  const status =
    rawStatus === "completed" || rawStatus === "success"
      ? "success"
      : rawStatus === "failed"
        ? "failed"
        : "running";
  return {
    id: b?.activityId ?? b?.id ?? `act_${Math.random().toString(36).slice(2, 9)}`,
    tool: b?.tool ?? b?.command ?? "tool",
    target: b?.filePath ?? b?.command ?? b?.detail ?? null,
    action_type: b?.activityType ?? b?.action_type ?? "tool",
    duration_ms: asNumber(b?.durationMs ?? b?.duration_ms, 0),
    result_summary: b?.detail ?? b?.result_summary ?? b?.title ?? null,
    status: status as AiActivity["status"],
    timestamp: asNumber(b?.timestamp, Math.floor(Date.now() / 1000)),
  };
};

const normalizeMessage = (b: any): AiConversationMessage => ({
  id: b?.id ?? `msg_${Math.random().toString(36).slice(2, 9)}`,
  conversation_id: b?.conversationId ?? b?.conversation_id ?? "",
  role: b?.role === "user" || b?.role === "assistant" || b?.role === "system" ? b.role : "assistant",
  content: b?.content ?? "",
  created_at: asNumber(b?.createdAt ?? b?.created_at, Math.floor(Date.now() / 1000)),
  status: b?.status ?? "completed",
  task_id: b?.taskId ?? b?.task_id ?? null,
  provider_id: b?.providerId ?? b?.provider_id ?? null,
  model_id: b?.modelId ?? b?.model_id ?? null,
  activities: Array.isArray(b?.activities) ? b.activities.map(normalizeActivity) : [],
  error: b?.error ?? null,
});

const normalizeSummary = (b: any): AiConversationSummary => ({
  id: b?.id ?? "",
  title: b?.title ?? "Untitled",
  created_at: asNumber(b?.createdAt ?? b?.created_at, 0),
  updated_at: asNumber(b?.updatedAt ?? b?.updated_at, 0),
  project_path: b?.projectPath ?? b?.project_path ?? null,
  directory_path: b?.directoryPath ?? b?.directory_path ?? null,
  context_type: b?.contextType ?? b?.context_type ?? "project",
  open_code_session_id: b?.openCodeSessionId ?? b?.open_code_session_id ?? null,
  provider_id: b?.providerId ?? b?.provider_id ?? null,
  model_id: b?.modelId ?? b?.model_id ?? null,
  status: b?.status ?? "active",
  last_message_preview: b?.lastMessagePreview ?? b?.last_message_preview ?? null,
  message_count: asNumber(b?.messageCount ?? b?.message_count, 0),
});

const normalizeDetail = (b: any): AiConversationDetail => ({
  ...normalizeSummary(b),
  messages: Array.isArray(b?.messages) ? b.messages.map(normalizeMessage) : [],
});

const normalizeProvider = (b: any): AiProviderSummary => {
  const method = b?.authMethod ?? b?.auth_method ?? "";
  const auth_method =
    method === "oauth" || method === "OAuth"
      ? "oauth"
      : method === "none" || method === "None"
        ? "none"
        : "api_key";
  const lastVerified = b?.lastVerified ?? b?.last_verified;
  return {
    provider_id: b?.providerId ?? b?.provider_id ?? "",
    name: b?.name ?? "",
    connected: !!b?.connected,
    auth_method,
    masked_credential: b?.maskedCredential ?? b?.masked_credential ?? null,
    last_verified:
      typeof lastVerified === "number"
        ? new Date(lastVerified * 1000).toLocaleString()
        : (lastVerified ?? null),
    error: b?.error ?? null,
  };
};

const normalizeModel = (b: any): AiModelSummary => ({
  id: b?.modelId ?? b?.id ?? "",
  name: b?.name ?? b?.modelId ?? b?.id ?? "",
  provider: b?.providerId ?? b?.provider ?? "",
  context_window: b?.contextWindow ?? b?.context_window ?? null,
  supports_tools: b?.supportsTools ?? b?.supports_tools ?? true,
  supports_streaming: b?.supportsStreaming ?? b?.supports_streaming ?? true,
  default_model: b?.defaultModel ?? b?.default_model ?? false,
});

const normalizeDefaults = (b: any): AiDefaultsConfig => ({
  default_provider: b?.providerId ?? b?.default_provider ?? "openai",
  default_model: b?.modelId ?? b?.default_model ?? "gpt-4o",
  default_agent: b?.agent ?? b?.default_agent ?? "build",
  default_context_behavior: b?.contextBehavior ?? b?.default_context_behavior ?? "project",
});

const normalizeUsage = (b: any): AiUsageStats => ({
  total_cost_reported: b?.totalCost ?? null,
  today_cost: b?.avgCostPerDay ?? null,
  week_cost: b?.totalCost ?? null,
  month_cost: b?.totalCost ?? null,
  total_requests: asNumber(b?.messagesCount ?? b?.total_requests, 0),
  input_tokens: String(b?.inputTokens ?? b?.input_tokens ?? "0"),
  output_tokens: String(b?.outputTokens ?? b?.output_tokens ?? "0"),
  cache_read_tokens: String(b?.cacheReadTokens ?? b?.cache_read_tokens ?? "0"),
  cache_write_tokens: String(b?.cacheWriteTokens ?? b?.cache_write_tokens ?? "0"),
  models: Array.isArray(b?.models)
    ? b.models.map((m: any) => ({
        model_id: m?.model ?? m?.model_id ?? "",
        provider_id: m?.providerId ?? m?.provider_id ?? "",
        requests: asNumber(m?.messages ?? m?.requests, 0),
        input_tokens: parseTokenCount(m?.inputTokens ?? m?.input_tokens),
        output_tokens: parseTokenCount(m?.outputTokens ?? m?.output_tokens),
        cost: m?.cost ?? null,
      }))
    : [],
  tools: Array.isArray(b?.tools)
    ? b.tools.map((t: any) => ({
        tool_name: t?.tool ?? t?.tool_name ?? "",
        calls: asNumber(t?.count ?? t?.calls, 0),
      }))
    : [],
});

const normalizeTask = (b: any, promptFallback: string): AiTaskSummary => {
  const rawStatus = b?.status;
  const status =
    rawStatus === "queued" || rawStatus === "pending"
      ? "pending"
      : rawStatus === "running" || rawStatus === "completed" || rawStatus === "failed" || rawStatus === "cancelled"
        ? rawStatus
        : "running";
  return {
    taskId: b?.taskId ?? b?.task_id ?? "",
    status,
    prompt: promptFallback,
    projectPath: b?.projectPath ?? b?.project_path,
    agent: typeof b?.agent === "string" ? b.agent : "build",
    readOnly: !!b?.readOnly,
    createdAt: asNumber(b?.startedAt ?? b?.createdAt, Math.floor(Date.now() / 1000)),
    finishedAt: b?.finishedAt ?? undefined,
    conversationId: b?.conversationId ?? undefined,
    model: b?.model ?? undefined,
  };
};

let mockConversations: AiConversationDetail[] = [
  {
    id: "conv_default_1",
    title: "Explain README architecture",
    created_at: Math.floor(Date.now() / 1000) - 3600,
    updated_at: Math.floor(Date.now() / 1000) - 1800,
    project_path: "/home/developer/orbit",
    directory_path: null,
    context_type: "project",
    open_code_session_id: "ses_demo_123",
    provider_id: "openai",
    model_id: "gpt-4o",
    status: "completed",
    last_message_preview: "The README details the dual-layer architecture...",
    message_count: 2,
    messages: [
      {
        id: "msg_1",
        conversation_id: "conv_default_1",
        role: "user",
        content: "Explain the architecture described in README.md",
        created_at: Math.floor(Date.now() / 1000) - 3600,
        status: "completed",
        activities: [],
      },
      {
        id: "msg_2",
        conversation_id: "conv_default_1",
        role: "assistant",
        content: "The Orbit architecture consists of a Rust/Tauri desktop workstation daemon and a Flutter mobile client communicating securely via paired WebSockets.",
        created_at: Math.floor(Date.now() / 1000) - 3550,
        status: "completed",
        provider_id: "openai",
        model_id: "gpt-4o",
        activities: [
          {
            id: "act_1",
            tool: "read_file",
            target: "README.md",
            action_type: "file_read",
            duration_ms: 240,
            result_summary: "Read 248 lines",
            status: "success",
            timestamp: Math.floor(Date.now() / 1000) - 3580,
          },
        ],
      },
    ],
  },
];

export const aiService = {
  async listConversations(limit = 50, offset = 0): Promise<AiConversationSummary[]> {
    if (!isTauriEnvironment()) {
      return mockConversations.map(({ messages, ...summary }) => summary);
    }
    const raw = await invoke<any[]>("list_ai_conversations", { limit, offset });
    return (raw ?? []).map(normalizeSummary);
  },

  async getConversation(id: string): Promise<AiConversationDetail | null> {
    if (!isTauriEnvironment()) {
      return mockConversations.find((c) => c.id === id) || null;
    }
    const raw = await invoke<any | null>("get_ai_conversation", { conversationId: id });
    return raw ? normalizeDetail(raw) : null;
  },

  async createConversation(params: {
    title?: string;
    projectPath?: string;
    directoryPath?: string;
    contextType?: string;
    providerId?: string;
    modelId?: string;
  }): Promise<AiConversationSummary> {
    if (!isTauriEnvironment()) {
      const newConv: AiConversationDetail = {
        id: "conv_" + Math.random().toString(36).substring(2, 9),
        title: params.title || "New Conversation",
        created_at: Math.floor(Date.now() / 1000),
        updated_at: Math.floor(Date.now() / 1000),
        project_path: params.projectPath || null,
        directory_path: params.directoryPath || null,
        context_type: params.contextType || "project",
        open_code_session_id: null,
        provider_id: params.providerId || "openai",
        model_id: params.modelId || "gpt-4o",
        status: "active",
        last_message_preview: null,
        message_count: 0,
        messages: [],
      };
      mockConversations.unshift(newConv);
      const { messages, ...summary } = newConv;
      return summary;
    }
    const raw = await invoke<any>("create_ai_conversation", {
      title: params.title,
      projectPath: params.projectPath,
      directoryPath: params.directoryPath,
      contextType: params.contextType,
      providerId: params.providerId,
      modelId: params.modelId,
    });
    return normalizeSummary(raw);
  },

  async renameConversation(id: string, title: string): Promise<void> {
    if (!isTauriEnvironment()) {
      const c = mockConversations.find((conv) => conv.id === id);
      if (c) c.title = title;
      return;
    }
    await invoke("rename_ai_conversation", { conversationId: id, title });
  },

  async deleteConversation(id: string, deleteSession = false): Promise<void> {
    if (!isTauriEnvironment()) {
      mockConversations = mockConversations.filter((c) => c.id !== id);
      return;
    }
    await invoke("delete_ai_conversation", { conversationId: id, deleteSession });
  },

  async searchConversations(query: string, limit = 20): Promise<AiConversationSummary[]> {
    if (!isTauriEnvironment()) {
      const q = query.toLowerCase();
      return mockConversations
        .filter((c) => c.title.toLowerCase().includes(q))
        .map(({ messages, ...summary }) => summary);
    }
    const raw = await invoke<any[]>("search_ai_conversations", { query, limit });
    // Backend returns search-result rows; project them onto summaries.
    return (raw ?? []).map((r: any) =>
      normalizeSummary({
        id: r?.conversationId ?? r?.id,
        title: r?.title,
        createdAt: r?.updatedAt ?? r?.updated_at,
        updatedAt: r?.updatedAt ?? r?.updated_at,
        projectPath: r?.projectPath ?? r?.project_path,
        modelId: r?.modelId ?? r?.model_id,
        status: "active",
        lastMessagePreview: r?.snippet,
        messageCount: 0,
      })
    );
  },

  async exportConversation(conversationId: string, format = "markdown"): Promise<string> {
    if (!isTauriEnvironment()) {
      return `# Conversation Export (${format})\nExported content for mock environment.`;
    }
    return await invoke<string>("export_ai_conversation", { conversationId, format });
  },

  async listProviders(): Promise<AiProviderSummary[]> {
    if (!isTauriEnvironment()) {
      return [
        {
          provider_id: "openai",
          name: "OpenAI",
          connected: true,
          auth_method: "api_key",
          masked_credential: "••••••••sk42",
          last_verified: "Today",
        },
        {
          provider_id: "anthropic",
          name: "Anthropic",
          connected: false,
          auth_method: "api_key",
        },
        {
          provider_id: "openrouter",
          name: "OpenRouter",
          connected: false,
          auth_method: "api_key",
        },
        {
          provider_id: "opencode_zen",
          name: "OpenCode Zen",
          connected: false,
          auth_method: "oauth",
        },
      ];
    }
    const raw = await invoke<any[]>("list_ai_providers");
    return (raw ?? []).map(normalizeProvider);
  },

  async configureProvider(providerId: string, apiKey: string, _endpoint?: string): Promise<AiProviderSummary> {
    if (!isTauriEnvironment()) {
      return {
        provider_id: providerId,
        name: providerId.toUpperCase(),
        connected: true,
        auth_method: "api_key",
        masked_credential: "••••••••" + apiKey.slice(-4),
        last_verified: "Just now",
      };
    }
    // Backend stores the key in OpenCode's local credential vault; it has
    // no custom-endpoint parameter, so _endpoint is intentionally unused.
    const raw = await invoke<any>("set_ai_provider_key", { providerId, apiKey });
    return normalizeProvider(raw);
  },

  async disconnectProvider(providerId: string): Promise<AiProviderSummary> {
    if (!isTauriEnvironment()) {
      return {
        provider_id: providerId,
        name: providerId,
        connected: false,
        auth_method: "api_key",
      };
    }
    await invoke("logout_ai_provider", { providerId });
    return {
      provider_id: providerId,
      name: providerId,
      connected: false,
      auth_method: "api_key",
    };
  },

  async testProvider(providerId: string): Promise<{ success: boolean; message: string; latency_ms?: number }> {
    if (!isTauriEnvironment()) {
      return { success: true, message: "Connected successfully", latency_ms: 120 };
    }
    const start = performance.now();
    const ok = await invoke<boolean>("test_ai_provider", { providerId });
    const latency_ms = Math.round(performance.now() - start);
    return ok
      ? { success: true, message: "Connected successfully", latency_ms }
      : { success: false, message: "Provider test failed", latency_ms };
  },

  async listModels(providerId?: string): Promise<AiModelSummary[]> {
    if (!isTauriEnvironment()) {
      return [
        { id: "gpt-4o", name: "GPT-4o", provider: "openai", context_window: 128000, supports_tools: true, supports_streaming: true, default_model: true },
        { id: "gpt-4o-mini", name: "GPT-4o Mini", provider: "openai", context_window: 128000, supports_tools: true, supports_streaming: true, default_model: false },
        { id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", provider: "anthropic", context_window: 200000, supports_tools: true, supports_streaming: true, default_model: false },
      ];
    }
    const raw = await invoke<any[]>("list_ai_models", { provider: providerId ?? null });
    return (raw ?? []).map(normalizeModel);
  },

  async getDefaults(): Promise<AiDefaultsConfig> {
    if (!isTauriEnvironment()) {
      return {
        default_provider: "openai",
        default_model: "gpt-4o",
        default_agent: "build",
        default_context_behavior: "project",
      };
    }
    const raw = await invoke<any>("get_ai_defaults");
    return normalizeDefaults(raw);
  },

  async saveDefaults(config: AiDefaultsConfig): Promise<void> {
    if (!isTauriEnvironment()) {
      return;
    }
    // Merge over current defaults so unset fields are never clobbered.
    const current = await this.getDefaults();
    await invoke("set_ai_defaults", {
      providerId: config.default_provider ?? current.default_provider ?? "openai",
      modelId: config.default_model ?? current.default_model ?? "gpt-4o",
      agent: config.default_agent ?? current.default_agent ?? "build",
      contextBehavior: config.default_context_behavior ?? current.default_context_behavior ?? "project",
    });
  },

  async getUsageStats(): Promise<AiUsageStats> {
    if (!isTauriEnvironment()) {
      return {
        total_cost_reported: "$0.42",
        today_cost: "$0.08",
        week_cost: "$0.42",
        month_cost: "$1.20",
        total_requests: 18,
        input_tokens: "45,210",
        output_tokens: "12,480",
        cache_read_tokens: "120,500",
        cache_write_tokens: "0",
        models: [
          {
            model_id: "gpt-4o",
            provider_id: "openai",
            requests: 14,
            input_tokens: 38000,
            output_tokens: 10200,
            cost: "$0.36",
          },
        ],
        tools: [
          { tool_name: "read_file", calls: 24 },
          { tool_name: "write_file", calls: 8 },
          { tool_name: "run_terminal", calls: 6 },
        ],
      };
    }
    const raw = await invoke<any>("get_ai_usage", {});
    return normalizeUsage(raw);
  },

  async startTask(params: {
    prompt: string;
    projectPath?: string;
    agent?: string;
    readOnly?: boolean;
    conversationId?: string;
    model?: string;
  }): Promise<AiTaskSummary> {
    if (!isTauriEnvironment()) {
      return {
        taskId: "task_mock_" + Math.random().toString(36).substring(2, 8),
        status: "running",
        prompt: params.prompt,
        projectPath: params.projectPath,
        agent: params.agent || "build",
        readOnly: params.readOnly || false,
        createdAt: Math.floor(Date.now() / 1000),
        conversationId: params.conversationId,
        model: params.model,
      };
    }
    const raw = await invoke<any>("start_ai_task", {
      prompt: params.prompt,
      projectPath: params.projectPath,
      agent: params.agent,
      readOnly: params.readOnly,
      conversationId: params.conversationId,
      model: params.model,
    });
    return normalizeTask(raw, params.prompt);
  },

  async resumeTask(params: {
    sessionId: string;
    prompt: string;
    projectPath?: string;
    agent?: string;
    readOnly?: boolean;
    conversationId?: string;
    model?: string;
  }): Promise<AiTaskSummary> {
    if (!isTauriEnvironment()) {
      return {
        taskId: "task_mock_" + Math.random().toString(36).substring(2, 8),
        status: "running",
        prompt: params.prompt,
        projectPath: params.projectPath,
        agent: params.agent || "build",
        readOnly: params.readOnly || false,
        createdAt: Math.floor(Date.now() / 1000),
        conversationId: params.conversationId,
        model: params.model,
      };
    }
    const raw = await invoke<any>("resume_ai_task", {
      sessionId: params.sessionId,
      prompt: params.prompt,
      projectPath: params.projectPath,
      agent: params.agent,
      readOnly: params.readOnly,
      conversationId: params.conversationId,
      model: params.model,
    });
    return normalizeTask(raw, params.prompt);
  },

  async cancelTask(taskId: string): Promise<void> {
    if (!isTauriEnvironment()) {
      return;
    }
    await invoke("cancel_ai_task", { taskId });
  },

  async onAiEvent(callback: (payload: any) => void): Promise<() => void> {
    if (!isTauriEnvironment()) {
      return () => {};
    }
    // The backend emits one Tauri event per AI broadcast kind (see
    // lib.rs: ai-response-chunk, ai-activity, ai-completed, ai-failed,
    // ai-cancelled). Fan them in and translate to the shapes the
    // AI Command Center view already handles.
    const unsubs: Array<() => void> = [];
    const on = async (event: string, handler: (p: any) => void) => {
      try {
        const unsub = await listen<any>(event, (e) => {
          try {
            handler(e.payload);
          } catch (err) {
            console.error(`[Orbit AI] Failed to handle ${event}:`, err);
          }
        });
        unsubs.push(unsub);
      } catch (err) {
        console.error(`[Orbit AI] Failed to subscribe to ${event}:`, err);
      }
    };

    await on("ai-response-chunk", (p) =>
      callback({
        type: "ai.task.response",
        taskId: p?.taskId,
        sessionId: p?.sessionId,
        payload: { chunk: p?.text ?? "" },
      })
    );
    await on("ai-activity", (p) =>
      callback({
        type: "ai.task.activity",
        taskId: p?.taskId,
        sessionId: p?.sessionId,
        payload: normalizeActivity(p?.activity ?? {}),
      })
    );
    await on("ai-completed", (p) =>
      callback({
        type: "ai.task.completed",
        taskId: p?.taskId,
        sessionId: p?.sessionId,
        payload: { durationMs: p?.durationMs },
      })
    );
    await on("ai-failed", (p) =>
      callback({
        type: "ai.task.failed",
        taskId: p?.taskId,
        sessionId: p?.sessionId,
        payload: { error: p?.error ?? "AI task failed" },
      })
    );
    // A cancelled task must also stop the streaming UI; the view treats
    // completion as "stop + reload", which is safe for cancellations too.
    await on("ai-cancelled", (p) =>
      callback({
        type: "ai.task.completed",
        taskId: p?.taskId,
        sessionId: p?.sessionId,
        cancelled: true,
      })
    );

    return () => {
      for (const u of unsubs) {
        try {
          u();
        } catch {
          // ignore unsubscribe errors during teardown
        }
      }
    };
  },

  async getOpencodeStatus(): Promise<OpencodeStatusPayload> {
    if (!isTauriEnvironment()) {
      return {
        state: "ready",
        userMessage: "AI engine ready.",
        isReady: true,
        version: "1.18.29",
      };
    }
    return invoke<OpencodeStatusPayload>("get_opencode_status");
  },

  async installOpencode(): Promise<OpencodeStatusPayload> {
    if (!isTauriEnvironment()) {
      return {
        state: "ready",
        userMessage: "AI engine ready.",
        isReady: true,
        version: "1.18.29",
      };
    }
    return invoke<OpencodeStatusPayload>("install_opencode");
  },

  async updateOpencode(): Promise<OpencodeStatusPayload> {
    if (!isTauriEnvironment()) {
      return {
        state: "ready",
        userMessage: "AI engine ready.",
        isReady: true,
        version: "1.18.29",
      };
    }
    return invoke<OpencodeStatusPayload>("update_opencode");
  },
};

