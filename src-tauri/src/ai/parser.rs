use serde_json::Value;
use std::path::Path;

use super::models::{AiActivityStatus, AiActivityType};

/// Mask credential-like material in otherwise displayable text.
///
/// Masks `sk-*` style tokens and `Bearer <token>` values. Case-insensitive
/// for the `bearer` scheme. This is defense in depth: callers must already
/// avoid selecting secret-bearing fields (see [`OpenCodeEventParser::extract_upstream_error`]).
pub fn redact_secrets(text: &str) -> String {
    let masked_bearer = mask_bearer_tokens(text);
    mask_sk_tokens(&masked_bearer)
}

fn mask_bearer_tokens(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    loop {
        let lower = rest.to_lowercase();
        let Some(pos) = lower.find("bearer ") else {
            out.push_str(rest);
            break;
        };
        out.push_str(&rest[..pos + "bearer ".len()]);
        let token_start = pos + "bearer ".len();
        let token_len = rest[token_start..]
            .find(|c: char| c.is_whitespace() || c == '"' || c == '\'' || c == ',' || c == '}' || c == ']')
            .unwrap_or(rest[token_start..].len());
        if token_len >= 4 {
            out.push_str("••••");
        } else {
            out.push_str(&rest[token_start..token_start + token_len]);
        }
        rest = &rest[token_start + token_len..];
    }
    out
}

fn is_token_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.'
}

fn mask_sk_tokens(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < text.len() {
        let remaining = &text[i..];
        let is_sk = remaining
            .get(..3)
            .map(|prefix| prefix.eq_ignore_ascii_case("sk-"))
            .unwrap_or(false);
        if is_sk {
            let mut end = i + 3;
            while let Some(ch) = text[end..].chars().next() {
                if !is_token_char(ch) {
                    break;
                }
                end += ch.len_utf8();
            }
            if end - (i + 3) >= 4 {
                out.push_str("sk-••••");
                i = end;
                continue;
            }
        }
        match text[i..].chars().next() {
            Some(ch) => {
                out.push(ch);
                i += ch.len_utf8();
            }
            None => break,
        }
    }
    out
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedActivityInfo {
    pub activity_type: AiActivityType,
    pub status: AiActivityStatus,
    pub title: String,
    pub detail: Option<String>,
    pub tool: Option<String>,
    pub command: Option<String>,
    pub file_path: Option<String>,
    pub duration_ms: Option<u64>,
    pub exit_code: Option<i32>,
}

impl ParsedActivityInfo {
    pub fn new(activity_type: AiActivityType, status: AiActivityStatus, title: impl Into<String>) -> Self {
        Self {
            activity_type,
            status,
            title: title.into(),
            detail: None,
            tool: None,
            command: None,
            file_path: None,
            duration_ms: None,
            exit_code: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParsedOpenCodeItem {
    SessionIdDiscovered(String),
    /// Upstream provider/model failure reported by OpenCode itself
    /// (e.g. `{"type":"error",...}`). Carries a SAFE, displayable message
    /// plus an optional HTTP-style status code. Never contains secrets:
    /// only the `message`/`statusCode` fields are extracted.
    UpstreamError {
        message: String,
        status_code: Option<i64>,
    },
    Activity(ParsedActivityInfo),
    ToolStarted {
        tool: String,
        status: String,
        title: Option<String>,
        command: Option<String>,
        file_path: Option<String>,
    },
    ToolFinished {
        tool: String,
        status: String,
        exit_code: Option<i32>,
        duration_ms: Option<u64>,
        command: Option<String>,
        file_path: Option<String>,
    },
    OutputChunk(String),
    ResponseChunk(String),
    PermissionRequested {
        id: String,
        session_id: Option<String>,
        permission: String,
        patterns: Vec<String>,
        metadata: serde_json::Value,
        always: Vec<String>,
    },
    PermissionReplied {
        id: String,
        session_id: Option<String>,
        reply: String,
    },
    Ignored,
}

pub struct OpenCodeEventParser;

impl OpenCodeEventParser {
    pub fn parse_line(line: &str) -> ParsedOpenCodeItem {
        Self::parse_line_with_project(line, None)
    }

    pub fn parse_line_with_project(line: &str, project_path: Option<&Path>) -> ParsedOpenCodeItem {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            return ParsedOpenCodeItem::Ignored;
        }

        // Attempt JSON parse
        let json: Value = match serde_json::from_str(trimmed) {
            Ok(v) => v,
            Err(_) => {
                // Non-JSON line (e.g. stderr/log banner)
                return ParsedOpenCodeItem::Ignored;
            }
        };

        // Check for part updates (contains user-facing text, tool activity, steps)
        if let Some(part) = Self::extract_part(&json) {
            return Self::parse_part(part, project_path);
        }

        // Check for upstream error events before anything else: these carry
        // the real provider/model failure reason (e.g. 401, unknown model).
        if let Some((message, status_code)) = Self::extract_upstream_error(&json) {
            return ParsedOpenCodeItem::UpstreamError {
                message,
                status_code,
            };
        }

        // Check for permission events before session ID extraction
        if let Some(event_type) = json.get("type").and_then(|t| t.as_str()) {
            if event_type == "permission.asked"
                || event_type == "permission.v2.asked"
                || event_type == "v2.permission.asked"
            {
                let props = json
                    .get("properties")
                    .or_else(|| json.get("data"))
                    .unwrap_or(&json);

                let id = props
                    .get("id")
                    .or_else(|| json.get("id"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                let session_id = props
                    .get("sessionID")
                    .or_else(|| json.get("sessionID"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string());

                let permission = props
                    .get("permission")
                    .or_else(|| props.get("action"))
                    .or_else(|| json.get("permission"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("unknown")
                    .to_string();

                let patterns: Vec<String> = props
                    .get("patterns")
                    .or_else(|| props.get("resources"))
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|x| x.as_str().map(|s| s.to_string()))
                            .collect()
                    })
                    .unwrap_or_default();

                let metadata = props
                    .get("metadata")
                    .cloned()
                    .unwrap_or_else(|| serde_json::json!({}));

                let always: Vec<String> = props
                    .get("always")
                    .or_else(|| props.get("save"))
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|x| x.as_str().map(|s| s.to_string()))
                            .collect()
                    })
                    .unwrap_or_default();

                if !id.is_empty() {
                    return ParsedOpenCodeItem::PermissionRequested {
                        id,
                        session_id,
                        permission,
                        patterns,
                        metadata,
                        always,
                    };
                }
            } else if event_type == "permission.replied"
                || event_type == "permission.v2.replied"
                || event_type == "v2.permission.replied"
            {
                let props = json
                    .get("properties")
                    .or_else(|| json.get("data"))
                    .unwrap_or(&json);

                let id = props
                    .get("requestID")
                    .or_else(|| props.get("id"))
                    .or_else(|| json.get("requestID"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                let session_id = props
                    .get("sessionID")
                    .or_else(|| json.get("sessionID"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string());

                let reply = props
                    .get("reply")
                    .or_else(|| json.get("reply"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("once")
                    .to_string();

                if !id.is_empty() {
                    return ParsedOpenCodeItem::PermissionReplied {
                        id,
                        session_id,
                        reply,
                    };
                }
            }
        }

        // Extract session ID if present on lines without a part
        if let Some(session_id) = Self::extract_session_id(&json) {
            return ParsedOpenCodeItem::SessionIdDiscovered(session_id);
        }

        // Check top-level event type
        if let Some(event_type) = json.get("type").and_then(|t| t.as_str()) {
            match event_type {
                "step-start" | "step_start" => {
                    return ParsedOpenCodeItem::Activity(ParsedActivityInfo::new(
                        AiActivityType::Thinking,
                        AiActivityStatus::Running,
                        "Executing task step...",
                    ));
                }
                "step-finish" | "step_finish" => {
                    return ParsedOpenCodeItem::Activity(ParsedActivityInfo::new(
                        AiActivityType::Completed,
                        AiActivityStatus::Completed,
                        "Task step completed",
                    ));
                }
                "tool_use" => {
                    if let Some(part) = json.get("part") {
                        return Self::parse_part(part, project_path);
                    }
                }
                _ => {}
            }
        }

        ParsedOpenCodeItem::Ignored
    }

    /// Extract a safe upstream failure from an OpenCode JSON line.
    ///
    /// Recognized shape (from `opencode run --format json`):
    /// `{"type":"error","error":{"name":"APIError","data":{"message":"...","statusCode":401}}}`
    ///
    /// Only `message` and `statusCode` are returned; headers, request ids and
    /// any other fields are deliberately ignored so credentials can never
    /// leak through this path. The message is additionally passed through
    /// [`redact_secrets`] as defense in depth.
    pub fn extract_upstream_error(json: &Value) -> Option<(String, Option<i64>)> {
        let event_type = json.get("type").and_then(|t| t.as_str())?;
        if event_type != "error" {
            return None;
        }
        let err = json.get("error")?;
        // Primary: error.data.message / error.data.statusCode
        let data = err.get("data");
        let message = data
            .and_then(|d| d.get("message"))
            .or_else(|| err.get("message"))
            .and_then(|m| m.as_str())
            .map(str::trim)
            .filter(|m| !m.is_empty())?;
        let status_code = data
            .and_then(|d| d.get("statusCode"))
            .or_else(|| data.and_then(|d| d.get("status_code")))
            .or_else(|| err.get("statusCode"))
            .and_then(|c| c.as_i64());
        let mut safe = redact_secrets(message);
        // Bound the size so a verbose provider payload can't bloat storage.
        const MAX_LEN: usize = 1200;
        if safe.len() > MAX_LEN {
            safe.truncate(MAX_LEN);
            safe.push('…');
        }
        Some((safe, status_code))
    }

    pub fn extract_session_id(json: &Value) -> Option<String> {
        // Direct root fields
        if let Some(s) = json.get("sessionID").and_then(|v| v.as_str()) {
            if s.starts_with("ses_") {
                return Some(s.to_string());
            }
        }
        if let Some(s) = json.get("id").and_then(|v| v.as_str()) {
            if s.starts_with("ses_") {
                return Some(s.to_string());
            }
        }

        // Nested in info / data
        let sub_objs = [
            json.get("info"),
            json.get("data"),
            json.get("properties"),
            json.get("data").and_then(|d| d.get("info")),
        ];

        for sub in sub_objs.into_iter().flatten() {
            if let Some(s) = sub.get("sessionID").and_then(|v| v.as_str()) {
                if s.starts_with("ses_") {
                    return Some(s.to_string());
                }
            }
            if let Some(s) = sub.get("id").and_then(|v| v.as_str()) {
                if s.starts_with("ses_") {
                    return Some(s.to_string());
                }
            }
        }

        None
    }

    fn extract_part(json: &Value) -> Option<&Value> {
        if let Some(part) = json.get("part") {
            return Some(part);
        }
        if let Some(part) = json.get("data").and_then(|d| d.get("part")) {
            return Some(part);
        }
        if let Some(part) = json.get("properties").and_then(|p| p.get("part")) {
            return Some(part);
        }
        None
    }

    fn make_relative_path(path: &str, project_path: Option<&Path>) -> String {
        let p = Path::new(path);
        if let Some(proj) = project_path {
            if let Ok(rel) = p.strip_prefix(proj) {
                let rel_str = rel.to_string_lossy().to_string();
                if !rel_str.is_empty() {
                    return rel_str;
                }
            }
        }
        path.to_string()
    }

    fn parse_part(part: &Value, project_path: Option<&Path>) -> ParsedOpenCodeItem {
        let part_type = part.get("type").and_then(|t| t.as_str()).unwrap_or("");

        match part_type {
            "tool" => {
                let tool = part
                    .get("tool")
                    .and_then(|t| t.as_str())
                    .unwrap_or("unknown")
                    .to_string();

                let state = part.get("state");
                let status = state
                    .and_then(|s| s.get("status"))
                    .and_then(|st| st.as_str())
                    .unwrap_or("running")
                    .to_string();

                let input = state.and_then(|s| s.get("input"));

                let command = input
                    .and_then(|i| i.get("command"))
                    .and_then(|c| c.as_str())
                    .map(|s| s.to_string());

                let file_path = input
                    .and_then(|i| {
                        i.get("path")
                            .or_else(|| i.get("file"))
                            .or_else(|| i.get("filePath"))
                            .or_else(|| i.get("filepath"))
                    })
                    .and_then(|p| p.as_str())
                    .map(|p| Self::make_relative_path(p, project_path));

                let title = state
                    .and_then(|s| s.get("title"))
                    .and_then(|t| t.as_str())
                    .map(|s| s.to_string())
                    .or_else(|| command.clone())
                    .or_else(|| file_path.clone());

                let duration_ms = state.and_then(|s| s.get("time")).and_then(|t| {
                    let start = t.get("start").and_then(|v| v.as_u64());
                    let end = t.get("end").and_then(|v| v.as_u64());
                    match (start, end) {
                        (Some(s), Some(e)) if e >= s => Some(e - s),
                        _ => None,
                    }
                });

                if status == "completed" || status == "error" {
                    let exit_code = state
                        .and_then(|s| s.get("metadata"))
                        .and_then(|m| m.get("exit"))
                        .and_then(|e| e.as_i64())
                        .map(|c| c as i32);

                    ParsedOpenCodeItem::ToolFinished {
                        tool,
                        status,
                        exit_code,
                        duration_ms,
                        command,
                        file_path,
                    }
                } else {
                    ParsedOpenCodeItem::ToolStarted {
                        tool,
                        status,
                        title,
                        command,
                        file_path,
                    }
                }
            }
            "reasoning" => {
                // DO NOT expose private internal chain-of-thought text.
                // Map to safe, high-level developer activity representation.
                ParsedOpenCodeItem::Activity(ParsedActivityInfo::new(
                    AiActivityType::Thinking,
                    AiActivityStatus::Running,
                    "Analyzing project & architecture...",
                ))
            }
            "text" => {
                if let Some(text) = part.get("text").and_then(|t| t.as_str()) {
                    ParsedOpenCodeItem::ResponseChunk(text.to_string())
                } else {
                    ParsedOpenCodeItem::Ignored
                }
            }
            "step-start" | "step_start" => {
                ParsedOpenCodeItem::Activity(ParsedActivityInfo::new(
                    AiActivityType::Thinking,
                    AiActivityStatus::Running,
                    "Executing task step...",
                ))
            }
            "step-finish" | "step_finish" => {
                ParsedOpenCodeItem::Activity(ParsedActivityInfo::new(
                    AiActivityType::Completed,
                    AiActivityStatus::Completed,
                    "Task step completed",
                ))
            }
            _ => ParsedOpenCodeItem::Ignored,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_upstream_error_apierror_shape() {
        let line = r#"{"type":"error","timestamp":1788626855113,"sessionID":"ses_abc","error":{"name":"APIError","data":{"message":"User not found.","statusCode":401}}}"#;
        let json: Value = serde_json::from_str(line).unwrap();
        let (msg, code) = OpenCodeEventParser::extract_upstream_error(&json).expect("should extract");
        assert_eq!(msg, "User not found.");
        assert_eq!(code, Some(401));
    }

    #[test]
    fn test_extract_upstream_error_unknown_shape() {
        let line = r#"{"type":"error","error":{"name":"UnknownError","data":{"message":"Unexpected server error.","ref":"err_1"}}}"#;
        let json: Value = serde_json::from_str(line).unwrap();
        let (msg, code) = OpenCodeEventParser::extract_upstream_error(&json).expect("should extract");
        assert_eq!(msg, "Unexpected server error.");
        assert_eq!(code, None);
    }

    #[test]
    fn test_extract_upstream_error_ignores_non_error() {
        let line = r#"{"type":"text","part":{"type":"text","text":"hello"}}"#;
        let json: Value = serde_json::from_str(line).unwrap();
        assert!(OpenCodeEventParser::extract_upstream_error(&json).is_none());
    }

    #[test]
    fn test_parse_line_routes_error_event() {
        let line = r#"{"type":"error","error":{"name":"APIError","data":{"message":"Rate limited.","statusCode":429}}}"#;
        match OpenCodeEventParser::parse_line(line) {
            ParsedOpenCodeItem::UpstreamError { message, status_code } => {
                assert_eq!(message, "Rate limited.");
                assert_eq!(status_code, Some(429));
            }
            other => panic!("expected UpstreamError, got {:?}", other),
        }
    }

    #[test]
    fn test_redact_secrets_masks_tokens() {
        let red = redact_secrets("key=sk-or-v1-abcdef1234567890 and Bearer secret-token-xyz ok");
        assert!(!red.contains("abcdef1234567890"), "sk token leaked: {}", red);
        assert!(!red.contains("secret-token-xyz"), "bearer token leaked: {}", red);
        assert!(red.contains("sk-••••"), "sk mask missing: {}", red);
        assert!(red.contains("••••"), "bearer mask missing: {}", red);
    }

    #[test]
    fn test_redact_secrets_keeps_safe_text() {
        let msg = "User not found. (HTTP 401)";
        assert_eq!(redact_secrets(msg), msg);
    }
}
