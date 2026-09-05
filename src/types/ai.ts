export interface AiActivity {
  id: string;
  tool: string;
  target?: string | null;
  action_type: string;
  duration_ms: number;
  result_summary?: string | null;
  status: "running" | "success" | "failed";
  files_changed?: number;
  timestamp: number;
}

export interface AiConversationSummary {
  id: string;
  title: string;
  created_at: number;
  updated_at: number;
  project_path?: string | null;
  directory_path?: string | null;
  context_type: string;
  open_code_session_id?: string | null;
  provider_id?: string | null;
  model_id?: string | null;
  status: string;
  last_message_preview?: string | null;
  message_count: number;
}

export interface AiConversationMessage {
  id: string;
  conversation_id: string;
  role: "user" | "assistant" | "system";
  content: string;
  created_at: number;
  status: string;
  task_id?: string | null;
  provider_id?: string | null;
  model_id?: string | null;
  activities: AiActivity[];
  error?: string | null;
}

export interface AiConversationDetail {
  id: string;
  title: string;
  created_at: number;
  updated_at: number;
  project_path?: string | null;
  directory_path?: string | null;
  context_type: string;
  open_code_session_id?: string | null;
  provider_id?: string | null;
  model_id?: string | null;
  status: string;
  last_message_preview?: string | null;
  message_count: number;
  messages: AiConversationMessage[];
}

export interface AiProviderSummary {
  provider_id: string;
  name: string;
  connected: boolean;
  auth_method: string;
  masked_credential?: string | null;
  last_verified?: string | null;
  error?: string | null;
}

export interface AiModelSummary {
  id: string;
  name: string;
  provider: string;
  context_window?: number | null;
  supports_tools: boolean;
  supports_streaming: boolean;
  default_model: boolean;
}

export interface AiDefaultsConfig {
  default_provider?: string | null;
  default_model?: string | null;
  default_agent?: string | null;
  default_context_behavior?: string | null;
}

export interface AiModelUsage {
  model_id: string;
  provider_id: string;
  requests: number;
  input_tokens: number;
  output_tokens: number;
  cost?: string | null;
}

export interface AiToolUsage {
  tool_name: string;
  calls: number;
}

export interface AiUsageStats {
  total_cost_reported?: string | null;
  today_cost?: string | null;
  week_cost?: string | null;
  month_cost?: string | null;
  total_requests: number;
  input_tokens: string;
  output_tokens: string;
  cache_read_tokens: string;
  cache_write_tokens: string;
  models: AiModelUsage[];
  tools: AiToolUsage[];
}

export interface AiTaskSummary {
  taskId: string;
  status: "pending" | "running" | "completed" | "failed" | "cancelled";
  prompt: string;
  projectPath?: string;
  agent: string;
  readOnly: boolean;
  createdAt: number;
  finishedAt?: number;
  conversationId?: string;
  model?: string;
}
