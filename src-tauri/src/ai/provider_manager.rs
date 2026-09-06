use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use crate::ai::process::find_opencode_binary;
use crate::protocol::errors::ProtocolError;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiProviderSummary {
    pub provider_id: String,
    pub name: String,
    pub connected: bool,
    pub auth_method: String,
    pub masked_credential: Option<String>,
    pub status: String,
    pub last_verified: Option<i64>,
    pub models_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiModelSummary {
    pub model_id: String,
    pub provider_id: String,
    pub name: String,
    pub context_window: Option<u64>,
    pub supports_tools: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiModelUsage {
    pub model: String,
    pub messages: u64,
    pub input_tokens: String,
    pub output_tokens: String,
    pub cost: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiToolUsage {
    pub tool: String,
    pub count: u64,
    pub percentage: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiUsageStats {
    pub sessions_count: u64,
    pub messages_count: u64,
    pub days_count: u64,
    pub total_cost: String,
    pub avg_cost_per_day: String,
    pub input_tokens: String,
    pub output_tokens: String,
    pub cache_read_tokens: String,
    pub cache_write_tokens: String,
    pub models: Vec<AiModelUsage>,
    pub tools: Vec<AiToolUsage>,
}

type ModelsCacheMap = HashMap<String, (i64, Vec<AiModelSummary>)>;

#[derive(Clone)]
pub struct AiProviderManager {
    #[allow(clippy::type_complexity)]
    models_cache: Arc<Mutex<ModelsCacheMap>>,
}

impl Default for AiProviderManager {
    fn default() -> Self {
        Self::new()
    }
}

impl AiProviderManager {
    pub fn new() -> Self {
        Self {
            models_cache: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    fn auth_file_path() -> PathBuf {
        let base_dir = std::env::var("HOME")
            .or_else(|_| std::env::var("USERPROFILE"))
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                if cfg!(windows) {
                    std::env::var("APPDATA")
                        .map(PathBuf::from)
                        .unwrap_or_else(|_| PathBuf::from("."))
                } else {
                    PathBuf::from("/tmp")
                }
            });
        base_dir
            .join(".local")
            .join("share")
            .join("opencode")
            .join("auth.json")
    }

    pub fn canonical_provider_id(provider_id: &str) -> &str {
        match provider_id {
            "opencode-zen" | "opencode_zen" => "opencode",
            other => other,
        }
    }

    pub fn mask_key(key: &str) -> String {
        let trimmed = key.trim();
        if trimmed.len() <= 4 {
            "••••••••".to_string()
        } else {
            let last4 = &trimmed[trimmed.len() - 4..];
            format!("••••••••{}", last4)
        }
    }

    pub fn get_known_providers() -> Vec<(&'static str, &'static str)> {
        vec![
            ("openrouter", "OpenRouter"),
            ("openai", "OpenAI"),
            ("anthropic", "Anthropic"),
            ("google", "Google Gemini"),
            ("deepseek", "DeepSeek"),
            ("opencode", "OpenCode Zen"),
            ("groq", "Groq"),
            ("mistral", "Mistral AI"),
        ]
    }

    pub fn list_providers(&self) -> Result<Vec<AiProviderSummary>, ProtocolError> {
        let auth_path = Self::auth_file_path();
        let mut configured: HashMap<String, serde_json::Value> = if auth_path.is_file() {
            match std::fs::read_to_string(&auth_path) {
                Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
                Err(_) => HashMap::new(),
            }
        } else {
            HashMap::new()
        };

        // If legacy "opencode-zen" or "opencode_zen" exists but canonical "opencode" does not,
        // transparently migrate it so OpenCode CLI runtime can immediately authenticate.
        if !configured.contains_key("opencode") {
            if let Some(legacy) = configured
                .get("opencode-zen")
                .or_else(|| configured.get("opencode_zen"))
                .cloned()
            {
                configured.insert("opencode".to_string(), legacy);
                if let Ok(serialized) = serde_json::to_string_pretty(&configured) {
                    let temp_path = auth_path.with_extension("tmp");
                    if std::fs::write(&temp_path, &serialized).is_ok() {
                        #[cfg(unix)]
                        {
                            use std::os::unix::fs::PermissionsExt;
                            let _ = std::fs::set_permissions(
                                &temp_path,
                                std::fs::Permissions::from_mode(0o600),
                            );
                        }
                        let _ = std::fs::rename(&temp_path, &auth_path);
                    }
                }
            }
        }

        let mut result = Vec::new();
        let known = Self::get_known_providers();

        for (p_id, p_name) in &known {
            let entry = configured.get(*p_id).or_else(|| {
                if *p_id == "opencode" {
                    configured
                        .get("opencode-zen")
                        .or_else(|| configured.get("opencode_zen"))
                } else {
                    None
                }
            });

            if let Some(entry) = entry {
                let key_str = entry.get("key").and_then(|k| k.as_str()).unwrap_or("");
                let masked = if !key_str.is_empty() {
                    Some(Self::mask_key(key_str))
                } else {
                    Some("Configured".to_string())
                };

                let auth_type = entry.get("type").and_then(|t| t.as_str()).unwrap_or("api");
                let auth_method = match auth_type {
                    "api" | "api_key" => "API Key",
                    "oauth" => "OAuth",
                    _ => "Configured",
                };

                result.push(AiProviderSummary {
                    provider_id: p_id.to_string(),
                    name: p_name.to_string(),
                    connected: true,
                    auth_method: auth_method.to_string(),
                    masked_credential: masked,
                    status: "connected".to_string(),
                    last_verified: Some(chrono::Utc::now().timestamp()),
                    models_count: 0,
                });
            } else {
                result.push(AiProviderSummary {
                    provider_id: p_id.to_string(),
                    name: p_name.to_string(),
                    connected: false,
                    auth_method: "None".to_string(),
                    masked_credential: None,
                    status: "not_configured".to_string(),
                    last_verified: None,
                    models_count: 0,
                });
            }
        }

        // Also check if any configured provider in auth.json is not in known list
        for (k, entry) in &configured {
            // Ignore legacy aliases
            if k == "opencode-zen" || k == "opencode_zen" {
                continue;
            }
            if !known.iter().any(|(id, _)| *id == k.as_str()) {
                let key_str = entry.get("key").and_then(|val| val.as_str()).unwrap_or("");
                result.push(AiProviderSummary {
                    provider_id: k.clone(),
                    name: Self::capitalize(k),
                    connected: true,
                    auth_method: "API Key".to_string(),
                    masked_credential: Some(Self::mask_key(key_str)),
                    status: "connected".to_string(),
                    last_verified: Some(chrono::Utc::now().timestamp()),
                    models_count: 0,
                });
            }
        }

        Ok(result)
    }

    fn capitalize(s: &str) -> String {
        let mut c = s.chars();
        match c.next() {
            None => String::new(),
            Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
        }
    }

    pub fn set_provider_key(
        &self,
        provider_id: &str,
        api_key: &str,
    ) -> Result<AiProviderSummary, ProtocolError> {
        let canonical_id = Self::canonical_provider_id(provider_id);
        let trimmed_key = api_key.trim();
        if trimmed_key.is_empty() {
            return Err(ProtocolError::internal_error("API key cannot be empty"));
        }

        let auth_path = Self::auth_file_path();
        if let Some(parent) = auth_path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        let mut map: HashMap<String, serde_json::Value> = if auth_path.is_file() {
            std::fs::read_to_string(&auth_path)
                .ok()
                .and_then(|c| serde_json::from_str(&c).ok())
                .unwrap_or_default()
        } else {
            HashMap::new()
        };

        let entry = serde_json::json!({
            "type": "api",
            "key": trimmed_key,
        });
        map.insert(canonical_id.to_string(), entry);

        // Keep auth.json clean: if configuring opencode, remove legacy aliases
        if canonical_id == "opencode" {
            map.remove("opencode-zen");
            map.remove("opencode_zen");
        }

        let serialized = serde_json::to_string_pretty(&map).map_err(|e| {
            ProtocolError::internal_error(format!("Failed to serialize auth.json: {}", e))
        })?;

        // Atomic write with restricted file permissions
        let temp_path = auth_path.with_extension("tmp");
        std::fs::write(&temp_path, serialized).map_err(|e| {
            ProtocolError::internal_error(format!("Failed to write temporary auth file: {}", e))
        })?;

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let perms = std::fs::Permissions::from_mode(0o600);
            let _ = std::fs::set_permissions(&temp_path, perms);
        }

        std::fs::rename(&temp_path, &auth_path).map_err(|e| {
            ProtocolError::internal_error(format!("Failed to save auth.json: {}", e))
        })?;

        // Clear models cache for this provider to allow refresh
        {
            let mut cache = self.models_cache.lock().unwrap();
            cache.remove(canonical_id);
            cache.remove(provider_id);
            cache.remove("all");
        }

        let name = Self::get_known_providers()
            .into_iter()
            .find(|(id, _)| *id == canonical_id)
            .map(|(_, n)| n.to_string())
            .unwrap_or_else(|| Self::capitalize(canonical_id));

        Ok(AiProviderSummary {
            provider_id: canonical_id.to_string(),
            name,
            connected: true,
            auth_method: "API Key".to_string(),
            masked_credential: Some(Self::mask_key(trimmed_key)),
            status: "connected".to_string(),
            last_verified: Some(chrono::Utc::now().timestamp()),
            models_count: 0,
        })
    }

    pub fn logout_provider(&self, provider_id: &str) -> Result<(), ProtocolError> {
        let canonical_id = Self::canonical_provider_id(provider_id);
        let auth_path = Self::auth_file_path();
        if !auth_path.is_file() {
            return Ok(());
        }

        let mut map: HashMap<String, serde_json::Value> = std::fs::read_to_string(&auth_path)
            .ok()
            .and_then(|c| serde_json::from_str(&c).ok())
            .unwrap_or_default();

        let mut changed = map.remove(canonical_id).is_some();
        if canonical_id == "opencode" {
            if map.remove("opencode-zen").is_some() {
                changed = true;
            }
            if map.remove("opencode_zen").is_some() {
                changed = true;
            }
        }
        if provider_id != canonical_id && map.remove(provider_id).is_some() {
            changed = true;
        }

        if changed {
            let serialized = serde_json::to_string_pretty(&map).map_err(|e| {
                ProtocolError::internal_error(format!("Failed to serialize auth: {}", e))
            })?;

            std::fs::write(&auth_path, serialized).map_err(|e| {
                ProtocolError::internal_error(format!("Failed to update auth file: {}", e))
            })?;

            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let perms = std::fs::Permissions::from_mode(0o600);
                let _ = std::fs::set_permissions(&auth_path, perms);
            }
        }

        let mut cache = self.models_cache.lock().unwrap();
        cache.remove(canonical_id);
        cache.remove(provider_id);
        cache.remove("all");

        Ok(())
    }

    pub async fn test_provider(&self, provider_id: &str) -> Result<bool, ProtocolError> {
        let canonical_id = Self::canonical_provider_id(provider_id);
        let binary_path = find_opencode_binary()?;
        let output = crate::opencode_manager::new_tokio_command(binary_path)
            .arg("models")
            .arg(canonical_id)
            .output()
            .await
            .map_err(|e| {
                ProtocolError::internal_error(format!("Failed to test provider: {}", e))
            })?;

        Ok(output.status.success())
    }

    pub async fn list_models(
        &self,
        provider_filter: Option<&str>,
    ) -> Result<Vec<AiModelSummary>, ProtocolError> {
        let canonical_filter = provider_filter.map(Self::canonical_provider_id);
        let cache_key = canonical_filter.unwrap_or("all").to_string();
        let now = chrono::Utc::now().timestamp();

        // Check cache (valid for 5 minutes)
        {
            let cache = self.models_cache.lock().unwrap();
            if let Some((cached_at, models)) = cache.get(&cache_key) {
                if now - cached_at < 300 {
                    return Ok(models.clone());
                }
            }
        }

        let binary_path = match find_opencode_binary() {
            Ok(p) => p,
            Err(_) => return Ok(self.fallback_models(canonical_filter)),
        };

        let mut cmd = crate::opencode_manager::new_tokio_command(binary_path);
        cmd.arg("models");
        if let Some(p) = canonical_filter {
            cmd.arg(p);
        }

        let output = cmd.output().await;
        let mut result = Vec::new();

        if let Ok(out) = output {
            if out.status.success() {
                let stdout = String::from_utf8_lossy(&out.stdout);
                for line in stdout.lines() {
                    let trimmed = line.trim();
                    if trimmed.is_empty() || trimmed.starts_with('#') {
                        continue;
                    }
                    let parts: Vec<&str> = trimmed.splitn(2, '/').collect();
                    let prov = if parts.len() == 2 {
                        parts[0]
                    } else {
                        "opencode"
                    };
                    let name = if parts.len() == 2 { parts[1] } else { trimmed };

                    result.push(AiModelSummary {
                        model_id: trimmed.to_string(),
                        provider_id: prov.to_string(),
                        name: name.to_string(),
                        context_window: Some(128_000),
                        supports_tools: true,
                    });
                }
            }
        }

        if result.is_empty() {
            result = self.fallback_models(canonical_filter);
        }

        // Limit to reasonable list if huge
        if result.len() > 100 {
            result.truncate(100);
        }

        // Save to cache
        {
            let mut cache = self.models_cache.lock().unwrap();
            cache.insert(cache_key, (now, result.clone()));
        }

        Ok(result)
    }

    fn fallback_models(&self, provider_filter: Option<&str>) -> Vec<AiModelSummary> {
        let all = vec![
            (
                "openrouter/openrouter/free",
                "openrouter",
                "OpenRouter Free (Auto)",
            ),
            (
                "openrouter/anthropic/claude-3.7-sonnet",
                "openrouter",
                "Claude 3.7 Sonnet (OpenRouter)",
            ),
            (
                "openrouter/openai/gpt-4o",
                "openrouter",
                "GPT-4o (OpenRouter)",
            ),
            ("openai/gpt-4o", "openai", "GPT-4o"),
            ("openai/gpt-4o-mini", "openai", "GPT-4o Mini"),
            ("openai/o3-mini", "openai", "o3-mini"),
            (
                "anthropic/claude-3-7-sonnet-latest",
                "anthropic",
                "Claude 3.7 Sonnet",
            ),
            (
                "anthropic/claude-3-5-haiku-latest",
                "anthropic",
                "Claude 3.5 Haiku",
            ),
            ("google/gemini-2.0-flash", "google", "Gemini 2.0 Flash"),
            ("deepseek/deepseek-chat", "deepseek", "DeepSeek V3"),
        ];

        all.into_iter()
            .filter(|(m_id, prov, _)| {
                if let Some(f) = provider_filter {
                    *prov == f || m_id.starts_with(f)
                } else {
                    true
                }
            })
            .map(|(m_id, prov, name)| AiModelSummary {
                model_id: m_id.to_string(),
                provider_id: prov.to_string(),
                name: name.to_string(),
                context_window: Some(128_000),
                supports_tools: true,
            })
            .collect()
    }

    pub async fn get_usage_stats(&self, days: Option<u32>) -> Result<AiUsageStats, ProtocolError> {
        let binary_path = find_opencode_binary()?;
        let mut cmd = crate::opencode_manager::new_tokio_command(binary_path);
        cmd.arg("stats");
        cmd.arg("--models");
        if let Some(d) = days {
            cmd.arg("--days");
            cmd.arg(d.to_string());
        }

        let output = cmd.output().await.map_err(|e| {
            ProtocolError::internal_error(format!("Failed to run opencode stats: {}", e))
        })?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        Ok(Self::parse_stats_output(&stdout))
    }

    pub fn parse_stats_output(stdout: &str) -> AiUsageStats {
        let mut sessions = 0;
        let mut messages = 0;
        let mut days = 0;
        let mut total_cost = "$0.00".to_string();
        let mut avg_cost = "$0.00".to_string();
        let mut input_tokens = "0".to_string();
        let mut output_tokens = "0".to_string();
        let mut cache_read = "0".to_string();
        let mut cache_write = "0".to_string();

        let mut models = Vec::new();
        let mut tools = Vec::new();

        let mut current_section = "";
        let mut current_model: Option<AiModelUsage> = None;

        for line in stdout.lines() {
            let clean = line.replace(['┌', '┐', '└', '┘', '├', '┤', '─', '│'], " ");
            let trimmed = clean.trim();

            if trimmed.contains("OVERVIEW") {
                current_section = "OVERVIEW";
                continue;
            } else if trimmed.contains("COST & TOKENS") {
                current_section = "COST";
                continue;
            } else if trimmed.contains("MODEL USAGE") {
                current_section = "MODEL";
                continue;
            } else if trimmed.contains("TOOL USAGE") {
                current_section = "TOOL";
                if let Some(m) = current_model.take() {
                    models.push(m);
                }
                continue;
            }

            if trimmed.is_empty() {
                continue;
            }

            match current_section {
                "OVERVIEW" => {
                    if trimmed.starts_with("Sessions") {
                        sessions = trimmed
                            .split_whitespace()
                            .last()
                            .and_then(|s| s.parse().ok())
                            .unwrap_or(0);
                    } else if trimmed.starts_with("Messages") {
                        messages = trimmed
                            .split_whitespace()
                            .last()
                            .and_then(|s| s.parse().ok())
                            .unwrap_or(0);
                    } else if trimmed.starts_with("Days") {
                        days = trimmed
                            .split_whitespace()
                            .last()
                            .and_then(|s| s.parse().ok())
                            .unwrap_or(0);
                    }
                }
                "COST" => {
                    if trimmed.starts_with("Total Cost") {
                        total_cost = trimmed
                            .split_whitespace()
                            .last()
                            .unwrap_or("$0.00")
                            .to_string();
                    } else if trimmed.starts_with("Avg Cost/Day") {
                        avg_cost = trimmed
                            .split_whitespace()
                            .last()
                            .unwrap_or("$0.00")
                            .to_string();
                    } else if trimmed.starts_with("Input") {
                        input_tokens = trimmed.split_whitespace().last().unwrap_or("0").to_string();
                    } else if trimmed.starts_with("Output") {
                        output_tokens =
                            trimmed.split_whitespace().last().unwrap_or("0").to_string();
                    } else if trimmed.starts_with("Cache Read") {
                        cache_read = trimmed.split_whitespace().last().unwrap_or("0").to_string();
                    } else if trimmed.starts_with("Cache Write") {
                        cache_write = trimmed.split_whitespace().last().unwrap_or("0").to_string();
                    }
                }
                "MODEL" => {
                    // Check if this line is a model name (e.g. contains '/')
                    if trimmed.contains('/')
                        && !trimmed.contains("Tokens")
                        && !trimmed.contains("Messages")
                    {
                        if let Some(m) = current_model.take() {
                            models.push(m);
                        }
                        current_model = Some(AiModelUsage {
                            model: trimmed.to_string(),
                            messages: 0,
                            input_tokens: "0".to_string(),
                            output_tokens: "0".to_string(),
                            cost: "$0.0000".to_string(),
                        });
                    } else if let Some(ref mut m) = current_model {
                        if trimmed.starts_with("Messages") {
                            m.messages = trimmed
                                .split_whitespace()
                                .last()
                                .and_then(|s| s.parse().ok())
                                .unwrap_or(0);
                        } else if trimmed.starts_with("Input Tokens") {
                            m.input_tokens =
                                trimmed.split_whitespace().last().unwrap_or("0").to_string();
                        } else if trimmed.starts_with("Output Tokens") {
                            m.output_tokens =
                                trimmed.split_whitespace().last().unwrap_or("0").to_string();
                        } else if trimmed.starts_with("Cost") {
                            m.cost = trimmed
                                .split_whitespace()
                                .last()
                                .unwrap_or("$0.00")
                                .to_string();
                        }
                    }
                }
                "TOOL" => {
                    // Lines look like: read ██████████ 381 (67.6%)
                    let parts: Vec<&str> = trimmed.split_whitespace().collect();
                    if parts.len() >= 3 {
                        let tool_name = parts[0].to_string();
                        let count = parts
                            .iter()
                            .rev()
                            .nth(1)
                            .and_then(|c| c.parse().ok())
                            .unwrap_or(0);
                        let percentage = parts
                            .last()
                            .unwrap_or(&"")
                            .trim_matches(['(', ')'])
                            .to_string();
                        tools.push(AiToolUsage {
                            tool: tool_name,
                            count,
                            percentage,
                        });
                    }
                }
                _ => {}
            }
        }

        if let Some(m) = current_model.take() {
            models.push(m);
        }

        AiUsageStats {
            sessions_count: sessions,
            messages_count: messages,
            days_count: days,
            total_cost,
            avg_cost_per_day: avg_cost,
            input_tokens,
            output_tokens,
            cache_read_tokens: cache_read,
            cache_write_tokens: cache_write,
            models,
            tools,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mask_key() {
        assert_eq!(AiProviderManager::mask_key("sk-1234567890"), "••••••••7890");
        assert_eq!(AiProviderManager::mask_key("123"), "••••••••");
        assert_eq!(
            AiProviderManager::mask_key("sk-ant-api03-abcdef12"),
            "••••••••ef12"
        );
    }

    static ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    /// Run `f` with HOME pointed at a fresh temp dir. Serialized via a
    /// process-wide lock because env vars are global to the test process.
    fn with_isolated_home(f: impl FnOnce(&std::path::Path)) {
        let _guard = ENV_LOCK.lock().unwrap();
        let prev_home = std::env::var_os("HOME");
        let prev_userprofile = std::env::var_os("USERPROFILE");
        let dir = std::env::temp_dir().join(format!(
            "orbit_test_home_{}_{}",
            std::process::id(),
            chrono::Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        std::fs::create_dir_all(&dir).expect("create isolated home");
        std::env::set_var("HOME", &dir);
        std::env::set_var("USERPROFILE", &dir);
        f(&dir);
        match prev_home {
            Some(v) => std::env::set_var("HOME", v),
            None => std::env::remove_var("HOME"),
        }
        match prev_userprofile {
            Some(v) => std::env::set_var("USERPROFILE", v),
            None => std::env::remove_var("USERPROFILE"),
        }
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_canonical_provider_id() {
        assert_eq!(
            AiProviderManager::canonical_provider_id("opencode-zen"),
            "opencode"
        );
        assert_eq!(
            AiProviderManager::canonical_provider_id("opencode_zen"),
            "opencode"
        );
        assert_eq!(
            AiProviderManager::canonical_provider_id("opencode"),
            "opencode"
        );
        assert_eq!(
            AiProviderManager::canonical_provider_id("openrouter"),
            "openrouter"
        );
        assert_eq!(AiProviderManager::canonical_provider_id("openai"), "openai");
    }

    #[test]
    fn test_set_provider_key_canonicalizes_zen() {
        with_isolated_home(|_home| {
            let mgr = AiProviderManager::new();

            let summary = mgr
                .set_provider_key("opencode-zen", "sk-zen-testkey1234567890")
                .expect("valid save succeeds");
            assert_eq!(summary.provider_id, "opencode");
            assert_eq!(summary.name, "OpenCode Zen");
            assert!(summary.connected);

            // Stored under "opencode", legacy alias removed
            let auth_path = AiProviderManager::auth_file_path();
            let content = std::fs::read_to_string(&auth_path).expect("auth.json written");
            let parsed: serde_json::Value = serde_json::from_str(&content).expect("valid json");
            assert_eq!(
                parsed
                    .get("opencode")
                    .and_then(|e| e.get("key"))
                    .and_then(|k| k.as_str()),
                Some("sk-zen-testkey1234567890")
            );
            assert!(parsed.get("opencode-zen").is_none());
        });
    }

    #[test]
    fn test_list_providers_reads_legacy_zen_and_migrates() {
        with_isolated_home(|_home| {
            let mgr = AiProviderManager::new();
            let auth_path = AiProviderManager::auth_file_path();
            if let Some(parent) = auth_path.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            let legacy_json = serde_json::json!({
                "opencode-zen": {
                    "type": "api",
                    "key": "sk-zen-legacy12345678"
                }
            });
            std::fs::write(
                &auth_path,
                serde_json::to_string_pretty(&legacy_json).unwrap(),
            )
            .unwrap();

            let providers = mgr.list_providers().expect("list succeeds");
            let opencode_prov = providers
                .iter()
                .find(|p| p.provider_id == "opencode")
                .expect("opencode found");
            assert!(opencode_prov.connected);
            assert_eq!(opencode_prov.name, "OpenCode Zen");
            assert!(opencode_prov
                .masked_credential
                .as_deref()
                .unwrap()
                .ends_with("5678"));

            // Check that auth.json was migrated to include "opencode"
            let content = std::fs::read_to_string(&auth_path).expect("auth.json readable");
            let parsed: serde_json::Value = serde_json::from_str(&content).expect("valid json");
            assert_eq!(
                parsed
                    .get("opencode")
                    .and_then(|e| e.get("key"))
                    .and_then(|k| k.as_str()),
                Some("sk-zen-legacy12345678")
            );
        });
    }

    #[test]
    fn test_set_provider_key_round_trip() {
        with_isolated_home(|_home| {
            let mgr = AiProviderManager::new();

            // Empty / whitespace keys are rejected, never written.
            assert!(mgr.set_provider_key("openrouter", "").is_err());
            assert!(mgr.set_provider_key("openrouter", "   ").is_err());

            let summary = mgr
                .set_provider_key("openrouter", "sk-or-v1-testkey1234567890")
                .expect("valid save succeeds");
            assert_eq!(summary.provider_id, "openrouter");
            assert!(summary.connected);
            // Masked only: the raw key must never appear in the summary.
            let debug = format!("{:?}", summary);
            assert!(
                !debug.contains("sk-or-v1-testkey1234567890"),
                "raw key leaked into summary"
            );
            assert!(
                summary
                    .masked_credential
                    .as_deref()
                    .unwrap_or("")
                    .ends_with("7890"),
                "expected masked credential, got {:?}",
                summary.masked_credential
            );

            // Vault file holds the entry with restricted permissions.
            let auth_path = AiProviderManager::auth_file_path();
            let content = std::fs::read_to_string(&auth_path).expect("auth.json written");
            let parsed: serde_json::Value = serde_json::from_str(&content).expect("valid json");
            assert_eq!(
                parsed
                    .get("openrouter")
                    .and_then(|e| e.get("key"))
                    .and_then(|k| k.as_str()),
                Some("sk-or-v1-testkey1234567890")
            );
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let mode = std::fs::metadata(&auth_path)
                    .expect("stat")
                    .permissions()
                    .mode()
                    & 0o777;
                assert_eq!(mode, 0o600, "auth.json must be owner-only, got {:o}", mode);
            }

            // Overwrite path preserves other providers and re-masks.
            mgr.set_provider_key("openai", "sk-test-openai-abcdef")
                .expect("second provider saves");
            let again = mgr
                .set_provider_key("openrouter", "sk-or-v1-rotated0000000007")
                .expect("overwrite succeeds");
            assert!(again
                .masked_credential
                .as_deref()
                .unwrap_or("")
                .ends_with("0007"));
            let content = std::fs::read_to_string(&auth_path).expect("auth.json readable");
            let parsed: serde_json::Value = serde_json::from_str(&content).expect("valid json");
            assert_eq!(
                parsed
                    .get("openai")
                    .and_then(|e| e.get("key"))
                    .and_then(|k| k.as_str()),
                Some("sk-test-openai-abcdef")
            );

            // list_providers reflects the stored credential, masked only.
            let listed: Vec<AiProviderSummary> = mgr.list_providers().expect("list works");
            let or = listed
                .iter()
                .find(|p| p.provider_id == "openrouter")
                .expect("openrouter listed");
            assert!(or.connected);
            let listed_debug = format!("{:?}", or);
            assert!(
                !listed_debug.contains("sk-or-v1-rotated0000000007"),
                "raw key leaked into list"
            );
        });
    }

    #[test]
    fn test_known_providers() {
        let providers = AiProviderManager::get_known_providers();
        assert!(providers.iter().any(|(id, _)| *id == "openai"));
        assert!(providers.iter().any(|(id, _)| *id == "anthropic"));
        assert!(providers.iter().any(|(id, _)| *id == "openrouter"));
        assert!(providers.iter().any(|(id, _)| *id == "opencode"));
    }

    #[test]
    fn test_parse_stats_output() {
        let sample = r#"
┌────────────────────────────────────────────────────────┐
│                       OVERVIEW                         │
├────────────────────────────────────────────────────────┤
│Sessions                                             42 │
│Messages                                            150 │
│Days                                                  3 │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│                    COST & TOKENS                       │
├────────────────────────────────────────────────────────┤
│Total Cost                                        $1.25 │
│Avg Cost/Day                                      $0.41 │
│Input                                            500.0K │
│Output                                            25.0K │
│Cache Read                                         1.0M │
│Cache Write                                           0 │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│                      MODEL USAGE                       │
├────────────────────────────────────────────────────────┤
│ openrouter/openai/gpt-4o                               │
│  Messages                                          100 │
│  Input Tokens                                   400.0K │
│  Output Tokens                                   20.0K │
│  Cost                                            $1.00 │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│                      TOOL USAGE                        │
├────────────────────────────────────────────────────────┤
│ read               ████████████████████  80 (80.0%)    │
│ bash               ████                  20 (20.0%)    │
└────────────────────────────────────────────────────────┘
        "#;

        let stats = AiProviderManager::parse_stats_output(sample);
        assert_eq!(stats.sessions_count, 42);
        assert_eq!(stats.messages_count, 150);
        assert_eq!(stats.days_count, 3);
        assert_eq!(stats.total_cost, "$1.25");
        assert_eq!(stats.input_tokens, "500.0K");
        assert_eq!(stats.models.len(), 1);
        assert_eq!(stats.models[0].model, "openrouter/openai/gpt-4o");
        assert_eq!(stats.models[0].messages, 100);
        assert_eq!(stats.tools.len(), 2);
        assert_eq!(stats.tools[0].tool, "read");
        assert_eq!(stats.tools[0].count, 80);
    }

    #[tokio::test]
    async fn test_provider_opencode_and_zen_alias() {
        let mgr = AiProviderManager::new();
        let ok = mgr
            .test_provider("opencode")
            .await
            .expect("test_provider succeeds");
        assert!(ok, "test_provider(opencode) should be true");

        let ok_alias = mgr
            .test_provider("opencode-zen")
            .await
            .expect("test_provider alias succeeds");
        assert!(ok_alias, "test_provider(opencode-zen) should be true");
    }

    #[tokio::test]
    async fn test_list_models_opencode_dynamic() {
        let mgr = AiProviderManager::new();
        let models = mgr
            .list_models(Some("opencode"))
            .await
            .expect("list_models succeeds");
        assert!(!models.is_empty(), "expected models from opencode CLI");
        assert!(models
            .iter()
            .any(|m| m.model_id.contains("free") || m.model_id.contains("pickle")));
        for m in &models {
            assert_eq!(m.provider_id, "opencode");
        }
    }
}
