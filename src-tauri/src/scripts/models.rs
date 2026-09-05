use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Script {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub content: String,
    pub working_directory: Option<String>,
    pub project_path: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScriptInput {
    pub id: Option<String>,
    pub name: String,
    pub description: Option<String>,
    pub content: String,
    pub working_directory: Option<String>,
    pub project_path: Option<String>,
}
