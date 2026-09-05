use serde::{Deserialize, Serialize};
use super::errors::ProtocolError;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct OrbitResponse {
    pub id: String,
    #[serde(rename = "type")]
    pub msg_type: String,
    pub action: String,
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub payload: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ProtocolError>,
}

impl OrbitResponse {
    pub fn success(id: impl Into<String>, action: impl Into<String>, payload: serde_json::Value) -> Self {
        Self {
            id: id.into(),
            msg_type: "response".to_string(),
            action: action.into(),
            success: true,
            payload: Some(payload),
            error: None,
        }
    }

    pub fn error(id: impl Into<String>, action: impl Into<String>, error: ProtocolError) -> Self {
        Self {
            id: id.into(),
            msg_type: "response".to_string(),
            action: action.into(),
            success: false,
            payload: None,
            error: Some(error),
        }
    }
}
