use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct OrbitRequest {
    pub id: String,
    #[serde(rename = "type")]
    pub msg_type: String,
    pub action: String,
    #[serde(default)]
    pub payload: serde_json::Value,
}

impl OrbitRequest {
    pub fn new(id: impl Into<String>, action: impl Into<String>, payload: serde_json::Value) -> Self {
        Self {
            id: id.into(),
            msg_type: "request".to_string(),
            action: action.into(),
            payload,
        }
    }
}
