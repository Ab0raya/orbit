import React, { useState, useEffect, useCallback } from "react";
import {
  Cpu,
  Key,
  Database,
  BarChart3,
  CheckCircle2,
  XCircle,
  AlertTriangle,
  RefreshCw,
  Save,
  Layers,
} from "lucide-react";
import {
  AiProviderSummary,
  AiModelSummary,
  AiDefaultsConfig,
  AiUsageStats,
} from "../types/ai";
import { aiService } from "../services/aiService";
import { OrbitDropdown, OrbitDropdownOption } from "./OrbitDropdown";

export type AiSettingsSection = "general" | "providers" | "models" | "usage" | "sessions";

interface AiSettingsViewProps {
  onBack?: () => void;
}

export const AiSettingsView: React.FC<AiSettingsViewProps> = ({ onBack }) => {
  const [activeSection, setActiveSection] = useState<AiSettingsSection>("general");

  // State
  const [providers, setProviders] = useState<AiProviderSummary[]>([]);
  const [models, setModels] = useState<AiModelSummary[]>([]);
  const [defaults, setDefaults] = useState<AiDefaultsConfig>({
    default_provider: "openai",
    default_model: "gpt-4o",
    default_agent: "build",
    default_context_behavior: "project",
  });
  const [usageStats, setUsageStats] = useState<AiUsageStats | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [savingDefaults, setSavingDefaults] = useState<boolean>(false);
  const [saveSuccessMsg, setSaveSuccessMsg] = useState<string | null>(null);

  // Key configuration modal state
  const [configureProviderId, setConfigureProviderId] = useState<string | null>(null);
  const [apiKeyInput, setApiKeyInput] = useState<string>("");
  const [endpointInput, setEndpointInput] = useState<string>("");
  const [savingApiKey, setSavingApiKey] = useState<boolean>(false);
  const [apiKeyError, setApiKeyError] = useState<string | null>(null);
  const [providerNotice, setProviderNotice] = useState<{ providerId: string; message: string } | null>(null);
  const [testResult, setTestResult] = useState<{ providerId: string; success: boolean; message: string } | null>(null);
  const [testingProvider, setTestingProvider] = useState<string | null>(null);

  const loadAll = useCallback(async () => {
    setLoading(true);
    try {
      const [provList, modelList, defConfig, stats] = await Promise.all([
        aiService.listProviders(),
        aiService.listModels(),
        aiService.getDefaults(),
        aiService.getUsageStats().catch(() => null),
      ]);
      setProviders(provList);
      setModels(modelList);
      setDefaults(defConfig);
      setUsageStats(stats);
    } catch (err) {
      console.error("Failed to load AI settings:", err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadAll();
  }, [loadAll]);

  // ---- General tab: real provider/model data for the Orbit dropdowns ----
  const selectedProviderId = defaults.default_provider || "";
  const selectedProvider = providers.find((p) => p.provider_id === selectedProviderId) || null;

  const providerOptions: OrbitDropdownOption[] = providers.map((p) => ({
    value: p.provider_id,
    label: p.name,
    sub: p.connected ? "Connected" : "Not configured",
  }));
  if (selectedProviderId && !providerOptions.some((o) => o.value === selectedProviderId)) {
    // Preserve a stored value the backend no longer lists (e.g. legacy id).
    providerOptions.unshift({ value: selectedProviderId, label: selectedProviderId, sub: "Unavailable" });
  }

  const providerModels = models.filter((m) => m.provider === selectedProviderId);
  const selectedModelId = defaults.default_model || "";
  const modelOptions: OrbitDropdownOption[] = providerModels.map((m) => ({
    value: m.id,
    label: m.name,
    sub: m.id !== m.name ? m.id : undefined,
  }));
  if (selectedModelId && !modelOptions.some((o) => o.value === selectedModelId)) {
    // Keep showing the stored model instead of dropping the selection.
    modelOptions.unshift({ value: selectedModelId, label: selectedModelId, sub: "Unavailable" });
  }
  const showModelNotConfigured =
    !loading && providerModels.length === 0 && !(selectedProvider && selectedProvider.connected);

  const handleProviderChange = (providerId: string) => {
    setDefaults((prev) => {
      const currentModel = prev.default_model || "";
      const nextModels = models.filter((m) => m.provider === providerId);
      const keepModel = nextModels.some((m) => m.id === currentModel);
      return {
        ...prev,
        default_provider: providerId,
        default_model: keepModel ? currentModel : nextModels[0]?.id || currentModel,
      };
    });
  };

  const handleSaveDefaults = async () => {
    setSavingDefaults(true);
    setSaveSuccessMsg(null);
    try {
      await aiService.saveDefaults(defaults);
      setSaveSuccessMsg("AI Defaults saved successfully.");
      setTimeout(() => setSaveSuccessMsg(null), 3000);
    } catch (err) {
      console.error("Failed to save defaults:", err);
    } finally {
      setSavingDefaults(false);
    }
  };

  /** Mask any accidental echo of the entered key before display. The
   *  backend never includes the key in errors; this is defense in depth. */
  const sanitizeKeyError = (raw: string, key: string): string => {
    const trimmed = key.trim();
    if (!trimmed) return raw;
    return raw.split(trimmed).join("••••••••");
  };

  const closeApiKeyModal = () => {
    setConfigureProviderId(null);
    setApiKeyInput("");
    setEndpointInput("");
    setApiKeyError(null);
    setSavingApiKey(false);
  };

  const handleSaveApiKey = async () => {
    if (savingApiKey) return; // prevent double submission
    const providerId = configureProviderId;
    const key = apiKeyInput.trim();
    if (!providerId) return;
    if (!key) {
      setApiKeyError("API key cannot be empty. Paste your provider key to continue.");
      return;
    }
    setSavingApiKey(true);
    setApiKeyError(null);
    try {
      // NOTE: the custom endpoint field is intentionally NOT sent. The
      // backend command set_ai_provider_key(provider_id, api_key) has no
      // endpoint parameter, and empty means "use the provider default".
      // Never force an OpenAI endpoint onto other providers.
      await aiService.configureProvider(providerId, key);
      closeApiKeyModal();
      await loadAll();
      setProviderNotice({ providerId, message: "API key saved" });
      window.setTimeout(() => {
        setProviderNotice((prev) => (prev?.providerId === providerId ? null : prev));
      }, 4000);
    } catch (err) {
      const raw = typeof err === "string" ? err : err instanceof Error ? err.message : "Failed to save API key";
      setApiKeyError(`Unable to save API key. ${sanitizeKeyError(raw, key)}`);
    } finally {
      setSavingApiKey(false);
    }
  };

  const handleDisconnect = async (providerId: string) => {
    try {
      await aiService.disconnectProvider(providerId);
      await loadAll();
    } catch (err) {
      console.error("Failed to disconnect provider:", err);
    }
  };

  const handleTestProvider = async (providerId: string) => {
    setTestingProvider(providerId);
    setTestResult(null);
    try {
      const res = await aiService.testProvider(providerId);
      setTestResult({
        providerId,
        success: res.success,
        message: res.message + (res.latency_ms ? ` (${res.latency_ms}ms)` : ""),
      });
    } catch (err: any) {
      setTestResult({
        providerId,
        success: false,
        message: typeof err === "string" ? err : err.message || "Failed test",
      });
    } finally {
      setTestingProvider(null);
    }
  };

  return (
    <div className="orbit-ai-settings-view">
      {/* Settings Navigation Bar */}
      <div className="ai-settings-topbar">
        <div className="ai-settings-title-group">
          {onBack && (
            <button className="ai-btn-sm" onClick={onBack}>
              ← Back to Command Center
            </button>
          )}
          <h1 className="ai-settings-main-title font-mono">SETTINGS → AI WORKSPACE</h1>
        </div>

        <div className="ai-settings-nav-capsules">
          <button
            className={`ai-nav-capsule ${activeSection === "general" ? "capsule-active" : ""}`}
            onClick={() => setActiveSection("general")}
          >
            <Cpu size={13} />
            <span>GENERAL</span>
          </button>
          <button
            className={`ai-nav-capsule ${activeSection === "providers" ? "capsule-active" : ""}`}
            onClick={() => setActiveSection("providers")}
          >
            <Key size={13} />
            <span>PROVIDERS</span>
          </button>
          <button
            className={`ai-nav-capsule ${activeSection === "models" ? "capsule-active" : ""}`}
            onClick={() => setActiveSection("models")}
          >
            <Layers size={13} />
            <span>MODELS</span>
          </button>
          <button
            className={`ai-nav-capsule ${activeSection === "usage" ? "capsule-active" : ""}`}
            onClick={() => setActiveSection("usage")}
          >
            <BarChart3 size={13} />
            <span>USAGE & STATS</span>
          </button>
          <button
            className={`ai-nav-capsule ${activeSection === "sessions" ? "capsule-active" : ""}`}
            onClick={() => setActiveSection("sessions")}
          >
            <Database size={13} />
            <span>SESSIONS</span>
          </button>
        </div>
      </div>

      {/* Main Settings Content Pane */}
      <div className="ai-settings-content-scroll">
        {/* ============================================================ */}
        {/* SECTION 1: GENERAL DEFAULTS                                  */}
        {/* ============================================================ */}
        {activeSection === "general" && (
          <div className="ai-settings-section-card">
            <div className="ai-section-header">
              <h2 className="ai-section-title font-mono">AI DEFAULTS</h2>
              <p className="ai-section-desc">
                Configure default models, agent modes, and project context behavior for newly created conversations.
              </p>
            </div>

            <div className="ai-settings-form-grid">
              <div className="ai-form-group">
                <label className="ai-form-label font-mono" id="ai-default-provider-label">DEFAULT PROVIDER</label>
                <OrbitDropdown
                  value={selectedProviderId}
                  options={providerOptions}
                  onChange={handleProviderChange}
                  placeholder={loading ? "Loading..." : "Select provider"}
                  loading={loading && providers.length === 0}
                  loadingText="Loading..."
                  ariaLabel="Default Provider"
                  dataTestId="ai-default-provider"
                />
              </div>

              <div className="ai-form-group">
                <label className="ai-form-label font-mono" id="ai-default-model-label">DEFAULT MODEL</label>
                <OrbitDropdown
                  value={showModelNotConfigured ? "" : selectedModelId}
                  options={
                    showModelNotConfigured
                      ? [{ value: "", label: "Not configured", disabled: true }]
                      : modelOptions
                  }
                  onChange={(v) => setDefaults({ ...defaults, default_model: v })}
                  placeholder="Not configured"
                  loading={loading}
                  loadingText="Loading models..."
                  ariaLabel="Default Model"
                  dataTestId="ai-default-model"
                />
              </div>

              <div className="ai-form-group">
                <label className="ai-form-label font-mono" id="ai-default-agent-label">DEFAULT AGENT MODE</label>
                <OrbitDropdown
                  value={defaults.default_agent || "build"}
                  options={[
                    { value: "build", label: "Build", sub: "Full workspace & execution tools" },
                    { value: "plan", label: "Plan", sub: "Read-only analysis & safe review" },
                  ]}
                  onChange={(v) => setDefaults({ ...defaults, default_agent: v })}
                  ariaLabel="Default Agent Mode"
                  dataTestId="ai-default-agent"
                />
              </div>

              <div className="ai-form-group">
                <label className="ai-form-label font-mono" id="ai-default-context-label">DEFAULT CONTEXT BEHAVIOR</label>
                <OrbitDropdown
                  value={defaults.default_context_behavior || "project"}
                  options={[
                    { value: "project", label: "Auto-detect Active Project" },
                    { value: "directory", label: "Explicit Directory" },
                    { value: "none", label: "No Context" },
                    { value: "ask", label: "Ask per conversation" },
                  ]}
                  onChange={(v) => setDefaults({ ...defaults, default_context_behavior: v })}
                  ariaLabel="Default Context Behavior"
                  dataTestId="ai-default-context"
                />
              </div>
            </div>

            <div className="ai-settings-actions-row">
              <button
                className="ai-save-defaults-btn"
                onClick={handleSaveDefaults}
                disabled={savingDefaults}
                data-testid="ai-save-defaults"
              >
                <Save size={13} aria-hidden="true" />
                <span>{savingDefaults ? "Saving..." : "Save Defaults"}</span>
              </button>

              {saveSuccessMsg && (
                <span className="ai-save-success-pill font-mono">
                  <CheckCircle2 size={13} />
                  <span>{saveSuccessMsg}</span>
                </span>
              )}
            </div>
          </div>
        )}

        {/* ============================================================ */}
        {/* SECTION 2: AI PROVIDERS MANAGEMENT                           */}
        {/* ============================================================ */}
        {activeSection === "providers" && (
          <div className="ai-settings-section-card">
            <div className="ai-section-header">
              <h2 className="ai-section-title font-mono">AI PROVIDERS</h2>
              <p className="ai-section-desc">
                Orbit interfaces securely through OpenCode's provider engine. Credentials remain stored strictly locally and are never persisted in SQLite or sent across the network to mobile clients.
              </p>
              {providerNotice && (
                <div className="ai-save-success-pill font-mono" data-testid="provider-notice">
                  <CheckCircle2 size={13} aria-hidden="true" />
                  <span>{providerNotice.message}</span>
                </div>
              )}
            </div>

            <div className="ai-providers-grid">
              {providers.map((prov) => (
                <div key={prov.provider_id} className="ai-provider-card">
                  <div className="ai-prov-card-header">
                    <div className="ai-prov-identity">
                      <span className="ai-prov-name font-mono">{prov.name}</span>
                      <span className="ai-prov-method font-mono">
                        {prov.auth_method === "api_key" ? "API Key" : "OAuth / Account"}
                      </span>
                    </div>

                    <div className="ai-prov-status-pill">
                      {prov.connected ? (
                        <span className="status-badge-connected">
                          <CheckCircle2 size={12} />
                          <span>Connected</span>
                        </span>
                      ) : (
                        <span className="status-badge-disconnected">
                          <span className="status-dot-off" />
                          <span>Not Configured</span>
                        </span>
                      )}
                    </div>
                  </div>

                  <div className="ai-prov-details">
                    <div className="ai-prov-detail-row font-mono">
                      <span className="detail-label">AUTHENTICATION:</span>
                      <span className="detail-val">
                        {prov.masked_credential || (prov.connected ? "Active Credentials" : "None")}
                      </span>
                    </div>

                    {prov.last_verified && (
                      <div className="ai-prov-detail-row font-mono">
                        <span className="detail-label">VERIFIED:</span>
                        <span className="detail-val">{prov.last_verified}</span>
                      </div>
                    )}

                    {prov.error && (
                      <div className="ai-prov-error-row font-mono">
                        <AlertTriangle size={12} />
                        <span>{prov.error}</span>
                      </div>
                    )}

                    {testResult && testResult.providerId === prov.provider_id && (
                      <div
                        className={`ai-prov-test-feedback font-mono ${
                          testResult.success ? "feedback-success" : "feedback-error"
                        }`}
                      >
                        {testResult.success ? <CheckCircle2 size={12} /> : <XCircle size={12} />}
                        <span>{testResult.message}</span>
                      </div>
                    )}
                  </div>

                  <div className="ai-prov-card-actions">
                    <button
                      className="ai-btn-sm ai-btn-primary"
                      onClick={() => {
                        setConfigureProviderId(prov.provider_id);
                        setApiKeyInput("");
                        setEndpointInput("");
                      }}
                    >
                      <Key size={12} />
                      <span>{prov.connected ? "Change API Key" : "Configure Key"}</span>
                    </button>

                    {prov.connected && (
                      <>
                        <button
                          className="ai-btn-sm"
                          disabled={testingProvider === prov.provider_id}
                          onClick={() => handleTestProvider(prov.provider_id)}
                        >
                          <RefreshCw
                            size={12}
                            className={testingProvider === prov.provider_id ? "spin" : ""}
                          />
                          <span>Test Connection</span>
                        </button>

                        <button
                          className="ai-btn-sm ai-btn-danger"
                          onClick={() => handleDisconnect(prov.provider_id)}
                        >
                          Disconnect
                        </button>
                      </>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* ============================================================ */}
        {/* SECTION 3: AVAILABLE MODELS CATALOG                          */}
        {/* ============================================================ */}
        {activeSection === "models" && (
          <div className="ai-settings-section-card">
            <div className="ai-section-header">
              <h2 className="ai-section-title font-mono">AVAILABLE MODELS</h2>
              <p className="ai-section-desc">
                Discovered through configured providers and local OpenCode engine. Select a model to set it as default.
              </p>
            </div>

            <div className="ai-models-table-container">
              <table className="ai-models-table font-mono">
                <thead>
                  <tr>
                    <th>MODEL</th>
                    <th>PROVIDER</th>
                    <th>CONTEXT WINDOW</th>
                    <th>CAPABILITIES</th>
                    <th>STATUS</th>
                    <th>ACTION</th>
                  </tr>
                </thead>
                <tbody>
                  {models.map((m) => {
                    const isDefault = defaults.default_model === m.id;
                    return (
                      <tr key={m.id} className={isDefault ? "row-default" : ""}>
                        <td className="cell-model-name">
                          <strong>{m.name}</strong>
                          <span className="sub-model-id">{m.id}</span>
                        </td>
                        <td>{m.provider.toUpperCase()}</td>
                        <td>{m.context_window ? `${(m.context_window / 1000).toFixed(0)}k tokens` : "Unknown"}</td>
                        <td>
                          <div className="capabilities-tags">
                            {m.supports_tools && <span className="cap-tag">Tools</span>}
                            {m.supports_streaming && <span className="cap-tag">Streaming</span>}
                          </div>
                        </td>
                        <td>
                          {isDefault ? (
                            <span className="status-badge-default">Default</span>
                          ) : (
                            <span className="status-badge-available">Available</span>
                          )}
                        </td>
                        <td>
                          {!isDefault && (
                            <button
                              className="ai-btn-xs"
                              onClick={() => {
                                setDefaults({ ...defaults, default_model: m.id });
                                aiService.saveDefaults({ ...defaults, default_model: m.id });
                              }}
                            >
                              Set Default
                            </button>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
              {models.length === 0 && (
                <div className="ai-table-empty font-mono">
                  No models discovered. Connect a provider like OpenAI or Anthropic above.
                </div>
              )}
            </div>
          </div>
        )}

        {/* ============================================================ */}
        {/* SECTION 4: USAGE & COST REPORTING                            */}
        {/* ============================================================ */}
        {activeSection === "usage" && (
          <div className="ai-settings-section-card">
            <div className="ai-section-header">
              <h2 className="ai-section-title font-mono">AI USAGE & TELEMETRY</h2>
              <p className="ai-section-desc">
                Real statistics reported by OpenCode stats engine. Orbit displays only verifiable metrics and never invents synthetic billing figures.
              </p>
            </div>

            {usageStats ? (
              <div className="ai-usage-dashboard">
                {/* Cost & Requests Metrics Cards */}
                <div className="ai-usage-metrics-grid font-mono">
                  <div className="usage-card">
                    <span className="usage-card-label">TODAY ESTIMATE</span>
                    <div className="usage-card-val">{usageStats.today_cost || "Usage data unavailable"}</div>
                    <span className="usage-card-sub">From OpenCode stats</span>
                  </div>

                  <div className="usage-card">
                    <span className="usage-card-label">THIS WEEK</span>
                    <div className="usage-card-val">{usageStats.week_cost || "Usage data unavailable"}</div>
                    <span className="usage-card-sub">Last 7 days active</span>
                  </div>

                  <div className="usage-card">
                    <span className="usage-card-label">TOTAL REQUESTS</span>
                    <div className="usage-card-val">{usageStats.total_requests}</div>
                    <span className="usage-card-sub">AI task completions</span>
                  </div>

                  <div className="usage-card">
                    <span className="usage-card-label">TOTAL TOKENS</span>
                    <div className="usage-card-val">
                      In: {usageStats.input_tokens} · Out: {usageStats.output_tokens}
                    </div>
                    <span className="usage-card-sub">
                      Cache read: {usageStats.cache_read_tokens}
                    </span>
                  </div>
                </div>

                {/* Model Breakdown */}
                {usageStats.models.length > 0 && (
                  <div className="ai-usage-subtable">
                    <h3 className="ai-subtable-title font-mono">MODEL USAGE BREAKDOWN</h3>
                    <table className="ai-models-table font-mono">
                      <thead>
                        <tr>
                          <th>MODEL</th>
                          <th>REQUESTS</th>
                          <th>INPUT TOKENS</th>
                          <th>OUTPUT TOKENS</th>
                          <th>COST</th>
                        </tr>
                      </thead>
                      <tbody>
                        {usageStats.models.map((mu) => (
                          <tr key={mu.model_id}>
                            <td>{mu.model_id}</td>
                            <td>{mu.requests}</td>
                            <td>{mu.input_tokens.toLocaleString()}</td>
                            <td>{mu.output_tokens.toLocaleString()}</td>
                            <td>{mu.cost || "Included / Unavailable"}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}

                {/* Tools Breakdown */}
                {usageStats.tools.length > 0 && (
                  <div className="ai-usage-subtable">
                    <h3 className="ai-subtable-title font-mono">TOOL INVOCATIONS</h3>
                    <div className="ai-tools-chips font-mono">
                      {usageStats.tools.map((t) => (
                        <div key={t.tool_name} className="tool-chip">
                          <span className="tool-name">{t.tool_name}</span>
                          <span className="tool-calls">{t.calls} calls</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            ) : (
              <div className="ai-usage-empty font-mono">
                <BarChart3 size={32} />
                <p>Usage data unavailable. Run an AI command to populate OpenCode telemetry.</p>
              </div>
            )}
          </div>
        )}

        {/* ============================================================ */}
        {/* SECTION 5: SESSIONS & CLEANUP                                */}
        {/* ============================================================ */}
        {activeSection === "sessions" && (
          <div className="ai-settings-section-card">
            <div className="ai-section-header">
              <h2 className="ai-section-title font-mono">OPENCODE SESSIONS</h2>
              <p className="ai-section-desc">
                Orbit maintains a 1:1 mapping between Orbit conversations and underlying OpenCode sessions for seamless conversation resumption.
              </p>
            </div>

            <div className="ai-sessions-status-box font-mono">
              <div className="ai-session-row">
                <span className="session-label">PERSISTENCE STORAGE:</span>
                <span className="session-val">SQLite (~/.orbit/conversations.db)</span>
              </div>
              <div className="ai-session-row">
                <span className="session-label">CREDENTIAL STORAGE:</span>
                <span className="session-val">OpenCode Local Vault (~/.local/share/opencode/auth.json)</span>
              </div>
              <div className="ai-session-row">
                <span className="session-label">MOBILE MAPPING:</span>
                <span className="session-val">Zero Plaintext Secrets Protocol</span>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* API Key Modal */}
      {configureProviderId && (
        <div className="orbit-modal-backdrop">
          <div className="orbit-modal-content">
            <h3 className="orbit-modal-title font-mono">
              CONFIGURE {configureProviderId.toUpperCase()}
            </h3>
            <p className="orbit-modal-desc">
              Enter your API credentials. Keys are saved securely into OpenCode's local credential storage and never displayed again in plaintext.
            </p>

            <div className="ai-modal-form-group">
              <label className="ai-form-label font-mono">API KEY</label>
              <input
                type="password"
                placeholder="sk-..."
                value={apiKeyInput}
                onChange={(e) => {
                  setApiKeyInput(e.target.value);
                  if (apiKeyError) setApiKeyError(null);
                }}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && apiKeyInput.trim() && !savingApiKey) {
                    e.preventDefault();
                    handleSaveApiKey();
                  }
                }}
                className="ai-modal-input font-mono"
                autoFocus
                disabled={savingApiKey}
              />
            </div>

            <div className="ai-modal-form-group">
              <label className="ai-form-label font-mono">CUSTOM ENDPOINT (OPTIONAL)</label>
              <input
                type="text"
                placeholder="Leave empty to use the provider default"
                value={endpointInput}
                onChange={(e) => setEndpointInput(e.target.value)}
                className="ai-modal-input font-mono"
                disabled={savingApiKey}
              />
            </div>

            {apiKeyError && (
              <div className="ai-modal-error font-mono" role="alert" data-testid="api-key-error">
                <AlertTriangle size={12} aria-hidden="true" />
                <span>{apiKeyError}</span>
              </div>
            )}

            <div className="orbit-modal-actions">
              <button
                className="ai-btn-sm"
                onClick={closeApiKeyModal}
                disabled={savingApiKey}
              >
                Cancel
              </button>
              <button
                className="ai-btn-sm ai-btn-primary"
                disabled={!apiKeyInput.trim() || savingApiKey}
                onClick={handleSaveApiKey}
                data-testid="api-key-save"
              >
                <Save size={13} aria-hidden="true" />
                <span>{savingApiKey ? "Saving..." : "Save Key"}</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
