use serde::{Deserialize, Serialize};
use super::events::OrbitEvent;
use super::request::OrbitRequest;
use super::response::OrbitResponse;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
pub enum OrbitMessage {
    Request(OrbitRequest),
    Response(OrbitResponse),
    Event(OrbitEvent),
}

impl OrbitMessage {
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }

    pub fn from_json(raw: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(raw)
    }
}
