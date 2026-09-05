pub mod context;
pub mod manager;
pub mod models;
pub mod parser;
pub mod permission;
pub mod process;
pub mod provider_manager;
pub mod storage;

pub use context::{validate_ai_working_directory, ValidatedAiContext};
pub use manager::AiTaskManager;
pub use models::{AiAgent, AiBroadcastEvent, AiTask, AiTaskStatus, AiTaskSummary};
pub use parser::{OpenCodeEventParser, ParsedOpenCodeItem};
pub use permission::{
    AiPermissionDecision, AiPermissionRequest, AiPermissionRisk, AiPermissionState,
    PermissionManager,
};
pub use process::find_opencode_binary;
pub use provider_manager::AiProviderManager;
pub use storage::AiConversationStore;

#[cfg(test)]
mod tests {
    use super::*;
    use super::models::{AiActivity, AiActivityStatus, AiActivityType};
    use crate::projects::ProjectManager;
    use std::path::PathBuf;
    use std::sync::Arc;

    // Test 1: Task creation & properties
    #[test]
    fn test_ai_task_creation_and_properties() {
        let task = AiTask {
            task_id: "task_test_1".to_string(),
            device_id: "dev_1".to_string(),
            project_path: PathBuf::from("/home/user/project"),
            prompt: "Refactor database".to_string(),
            agent: AiAgent::Plan,
            read_only: true,
            status: AiTaskStatus::Queued,
            open_code_session_id: None,
            child_pid: None,
            started_at: 1000,
            finished_at: None,
            output: None,
            response: None,
            error: None,
            conversation_id: None,
            model: None,
            activities: Vec::new(),
        };

        assert_eq!(task.task_id, "task_test_1");
        assert_eq!(task.agent, AiAgent::Plan);
        assert!(task.read_only);
        assert_eq!(task.status, AiTaskStatus::Queued);

        let summary = task.to_summary();
        assert_eq!(summary.task_id, "task_test_1");
        assert_eq!(summary.status, AiTaskStatus::Queued);
        assert_eq!(summary.agent, AiAgent::Plan);
        assert!(summary.read_only);
        assert_eq!(summary.activity_count, 0);
        assert!(summary.latest_activity.is_none());
    }

    // Test 2: Task state transitions
    #[test]
    fn test_task_state_transitions() {
        assert!(!AiTaskStatus::Queued.is_terminal());
        assert!(!AiTaskStatus::Running.is_terminal());
        assert!(AiTaskStatus::Completed.is_terminal());
        assert!(AiTaskStatus::Failed.is_terminal());
        assert!(AiTaskStatus::Cancelled.is_terminal());

        assert_eq!(AiTaskStatus::Queued.as_str(), "queued");
        assert_eq!(AiTaskStatus::Running.as_str(), "running");
        assert_eq!(AiTaskStatus::Completed.as_str(), "completed");
        assert_eq!(AiTaskStatus::Failed.as_str(), "failed");
        assert_eq!(AiTaskStatus::Cancelled.as_str(), "cancelled");
    }

    // Test 3: Agent modes & permissions
    #[test]
    fn test_agent_modes() {
        assert_eq!(AiAgent::Plan.as_str(), "plan");
        assert_eq!(AiAgent::Build.as_str(), "build");

        assert!(AiAgent::Plan.is_read_only());
        assert!(!AiAgent::Build.is_read_only());

        assert_eq!(AiAgent::from_str_loose("PLAN"), Some(AiAgent::Plan));
        assert_eq!(AiAgent::from_str_loose("  build  "), Some(AiAgent::Build));
        assert_eq!(AiAgent::from_str_loose("invalid"), None);
    }

    // Test 4: OpenCode event parsing: session ID extraction
    #[test]
    fn test_opencode_event_parser_session_id() {
        let line = r#"{"type":"session.created.1","sessionID":"ses_abc1234567890abcdef"}"#;
        let res = OpenCodeEventParser::parse_line(line);
        assert_eq!(
            res,
            ParsedOpenCodeItem::SessionIdDiscovered("ses_abc1234567890abcdef".to_string())
        );

        let nested_line = r#"{"type":"event","data":{"info":{"id":"ses_xyz987654321"}}}"#;
        let nested_res = OpenCodeEventParser::parse_line(nested_line);
        assert_eq!(
            nested_res,
            ParsedOpenCodeItem::SessionIdDiscovered("ses_xyz987654321".to_string())
        );
    }

    // Test 5: OpenCode event parsing: tool started & completed
    #[test]
    fn test_opencode_event_parser_tool() {
        let running_tool = r#"{
            "type":"message.part.updated.1",
            "part":{
                "type":"tool",
                "tool":"bash",
                "state":{"status":"running","title":"git status"}
            }
        }"#;
        let res = OpenCodeEventParser::parse_line(running_tool);
        assert_eq!(
            res,
            ParsedOpenCodeItem::ToolStarted {
                tool: "bash".to_string(),
                status: "running".to_string(),
                title: Some("git status".to_string()),
                command: None,
                file_path: None,
            }
        );

        let completed_tool = r#"{
            "type":"message.part.updated.1",
            "part":{
                "type":"tool",
                "tool":"bash",
                "state":{"status":"completed","metadata":{"exit":0}}
            }
        }"#;
        let res2 = OpenCodeEventParser::parse_line(completed_tool);
        assert_eq!(
            res2,
            ParsedOpenCodeItem::ToolFinished {
                tool: "bash".to_string(),
                status: "completed".to_string(),
                exit_code: Some(0),
                duration_ms: None,
                command: None,
                file_path: None,
            }
        );
    }

    // Test 6: Reasoning normalization (no raw internal reasoning tokens)
    #[test]
    fn test_opencode_event_parser_reasoning_normalized() {
        let line = r#"{
            "type":"message.part.updated.1",
            "part":{
                "type":"reasoning",
                "text":"Secret private chain of thought that must not be exposed"
            }
        }"#;
        let res = OpenCodeEventParser::parse_line(line);
        match res {
            ParsedOpenCodeItem::Activity(info) => {
                assert_eq!(info.activity_type, AiActivityType::Thinking);
                assert!(!info.title.contains("Secret private"));
                assert!(info.title.contains("Analyzing") || info.title.contains("architecture"));
            }
            _ => panic!("Expected Activity variant"),
        }
    }

    // Test 7: Output chunk extraction
    #[test]
    fn test_opencode_event_parser_output() {
        let line = r#"{
            "type":"message.part.updated.1",
            "part":{
                "type":"text",
                "text":"Here is the architecture summary of the project."
            }
        }"#;
        let res = OpenCodeEventParser::parse_line(line);
        assert_eq!(
            res,
            ParsedOpenCodeItem::ResponseChunk(
                "Here is the architecture summary of the project.".to_string()
            )
        );
    }

    // Test 8: Malformed JSON and non-JSON lines tolerance
    #[test]
    fn test_opencode_event_parser_malformed_tolerance() {
        assert_eq!(OpenCodeEventParser::parse_line(""), ParsedOpenCodeItem::Ignored);
        assert_eq!(OpenCodeEventParser::parse_line("   "), ParsedOpenCodeItem::Ignored);
        assert_eq!(
            OpenCodeEventParser::parse_line("OpenCode v1.18.27 starting..."),
            ParsedOpenCodeItem::Ignored
        );
        assert_eq!(
            OpenCodeEventParser::parse_line("{malformed: json!"),
            ParsedOpenCodeItem::Ignored
        );
        assert_eq!(
            OpenCodeEventParser::parse_line(r#"{"unknown_field": 123}"#),
            ParsedOpenCodeItem::Ignored
        );
    }

    // Test 9: Manager validation: empty prompt rejection
    #[tokio::test]
    async fn test_manager_empty_prompt_rejection() {
        let project_mgr = Arc::new(ProjectManager::new());
        let ai_mgr = AiTaskManager::new(project_mgr);

        let res = ai_mgr.start_task("dev_1", "/any/path", "   ", None, None).await;
        assert!(res.is_err());
        assert_eq!(res.unwrap_err().code, "AI_TASK_INVALID_PROMPT");
    }

    // Test 10: Manager validation: invalid agent rejection
    #[tokio::test]
    async fn test_manager_invalid_agent_rejection() {
        let project_mgr = Arc::new(ProjectManager::new());
        let ai_mgr = AiTaskManager::new(project_mgr);

        let res = ai_mgr.start_task("dev_1", "/any/path", "Valid prompt", Some("invalid_agent"), None).await;
        assert!(res.is_err());
        assert_eq!(res.unwrap_err().code, "AI_TASK_INVALID_AGENT");
    }

    // Test 11: Manager validation: project scope rejection
    #[tokio::test]
    async fn test_manager_project_scope_rejection() {
        let project_mgr = Arc::new(ProjectManager::new());
        let ai_mgr = AiTaskManager::new(project_mgr);

        // Path outside allowed project roots
        let res = ai_mgr.start_task("dev_1", "/etc/shadow", "Analyze system", None, None).await;
        assert!(res.is_err());
        let err = res.unwrap_err();
        assert!(err.code == "PROJECT_NOT_ALLOWED" || err.code == "PROJECT_NOT_FOUND");
    }

    // Test 12: Manager task ownership & list filtering
    #[tokio::test]
    async fn test_manager_ownership_and_list() {
        let project_mgr = Arc::new(ProjectManager::new());
        let ai_mgr = AiTaskManager::new(project_mgr);

        // List for empty device
        let list1 = ai_mgr.list_tasks("dev_1");
        assert!(list1.is_empty());

        // Get non-existent task
        let get_err = ai_mgr.get_task("task_nonexistent", "dev_1").await;
        assert!(get_err.is_err());
        assert_eq!(get_err.unwrap_err().code, "AI_TASK_NOT_FOUND");
    }

    // Test 13: Structured activity classification (command, file, test, duration, exit code)
    #[test]
    fn test_structured_activity_classification() {
        let project_root = PathBuf::from("/home/user/workspace/orbit");
        let line = r#"{
            "type":"message.part.updated.1",
            "part":{
                "type":"tool",
                "tool":"bash",
                "state":{
                    "status":"completed",
                    "title":"Running tests",
                    "input":{"command":"flutter test"},
                    "time":{"start":1000,"end":5200},
                    "metadata":{"exit":0}
                }
            }
        }"#;

        let res = OpenCodeEventParser::parse_line_with_project(line, Some(&project_root));
        match res {
            ParsedOpenCodeItem::ToolFinished {
                tool,
                status,
                exit_code,
                duration_ms,
                command,
                ..
            } => {
                assert_eq!(tool, "bash");
                assert_eq!(status, "completed");
                assert_eq!(exit_code, Some(0));
                assert_eq!(duration_ms, Some(4200));
                assert_eq!(command, Some("flutter test".to_string()));
            }
            _ => panic!("Expected ToolFinished variant with duration and exit code"),
        }
    }

    // Test 14: Relative path normalization against project root
    #[test]
    fn test_relative_path_normalization() {
        let project_root = PathBuf::from("/home/user/workspace/orbit");
        let line = r#"{
            "type":"message.part.updated.1",
            "part":{
                "type":"tool",
                "tool":"read",
                "state":{
                    "status":"running",
                    "input":{"path":"/home/user/workspace/orbit/mobile/lib/main.dart"}
                }
            }
        }"#;

        let res = OpenCodeEventParser::parse_line_with_project(line, Some(&project_root));
        match res {
            ParsedOpenCodeItem::ToolStarted {
                tool,
                file_path,
                ..
            } => {
                assert_eq!(tool, "read");
                assert_eq!(file_path, Some("mobile/lib/main.dart".to_string()));
            }
            _ => panic!("Expected ToolStarted variant with normalized relative path"),
        }
    }

    // Test 15: Bounded activity history (500 limit, drops oldest, keeps newest)
    #[test]
    fn test_bounded_activity_history() {
        let mut task = AiTask {
            task_id: "task_bound_test".to_string(),
            device_id: "dev_1".to_string(),
            project_path: PathBuf::from("/home/user/project"),
            prompt: "Test bounding".to_string(),
            agent: AiAgent::Plan,
            read_only: true,
            status: AiTaskStatus::Running,
            open_code_session_id: None,
            child_pid: None,
            started_at: 1000,
            finished_at: None,
            output: None,
            response: None,
            error: None,
            conversation_id: None,
            model: None,
            activities: Vec::new(),
        };

        for i in 0..550 {
            task.push_activity(AiActivity {
                activity_id: format!("act_{}", i),
                task_id: task.task_id.clone(),
                timestamp: 1000 + i as u64,
                activity_type: AiActivityType::Command,
                status: AiActivityStatus::Completed,
                title: format!("Activity {}", i),
                detail: None,
                tool: Some("bash".to_string()),
                command: None,
                file_path: None,
                duration_ms: None,
                exit_code: None,
            });
        }

        assert_eq!(task.activities.len(), models::MAX_ACTIVITIES_PER_TASK);
        assert_eq!(task.activities.first().unwrap().activity_id, "act_50");
        assert_eq!(task.activities.last().unwrap().activity_id, "act_549");
    }

    // Test 16: Bounded output truncation (256 KB limit, drops oldest, keeps newest)
    #[test]
    fn test_bounded_output_truncation() {
        let mut task = AiTask {
            task_id: "task_output_bound".to_string(),
            device_id: "dev_1".to_string(),
            project_path: PathBuf::from("/home/user/project"),
            prompt: "Test output bound".to_string(),
            agent: AiAgent::Plan,
            read_only: true,
            status: AiTaskStatus::Running,
            open_code_session_id: None,
            child_pid: None,
            started_at: 1000,
            finished_at: None,
            output: None,
            response: None,
            error: None,
            conversation_id: None,
            model: None,
            activities: Vec::new(),
        };

        // Append 300 KB in chunks
        let chunk = "A".repeat(1024); // 1 KB
        for _ in 0..300 {
            task.append_output(&chunk);
        }
        task.append_output("FINAL_MARKER");

        let out = task.output.unwrap();
        assert!(out.len() <= models::MAX_OUTPUT_BYTES_PER_TASK);
        assert!(out.ends_with("FINAL_MARKER"));
    }

    // Test 17: Cancellation state protection
    #[test]
    fn test_cancellation_terminal_state_protection() {
        let task = AiTask {
            task_id: "task_cancel_test".to_string(),
            device_id: "dev_1".to_string(),
            project_path: PathBuf::from("/home/user/project"),
            prompt: "Test cancel race".to_string(),
            agent: AiAgent::Plan,
            read_only: true,
            status: AiTaskStatus::Cancelled,
            open_code_session_id: None,
            child_pid: None,
            started_at: 1000,
            finished_at: Some(2000),
            output: None,
            response: None,
            error: None,
            conversation_id: None,
            model: None,
            activities: Vec::new(),
        };

        // Once cancelled, status is terminal
        assert!(task.status.is_terminal());
        assert_eq!(task.status, AiTaskStatus::Cancelled);
    }

    // Test 18: Task get / reconnect retrieval
    #[tokio::test]
    async fn test_manager_get_task_reconnect_retrieval() {
        let project_mgr = Arc::new(ProjectManager::new());
        let ai_mgr = AiTaskManager::new(project_mgr);

        // Directly verify get_task fails with AI_TASK_NOT_FOUND for unknown tasks
        let err = ai_mgr.get_task("nonexistent_task", "dev_1").await.unwrap_err();
        assert_eq!(err.code, "AI_TASK_NOT_FOUND");
    }

    // Test 19: AI arbitrary allowed directory validation
    #[test]
    fn test_ai_arbitrary_allowed_directory_validation() {
        let temp_dir = std::env::temp_dir().join(format!("orbit_ai_allowed_{}", std::process::id()));
        let _ = std::fs::create_dir_all(&temp_dir);
        let project_mgr = ProjectManager::with_roots(vec![std::env::temp_dir()]);

        let res = validate_ai_working_directory(&temp_dir.to_string_lossy(), &project_mgr);
        assert!(res.is_ok(), "Expected valid directory within allowed roots: {:?}", res);
        match res.unwrap() {
            ValidatedAiContext::Directory(p) => {
                assert!(p.exists());
            }
            _ => panic!("Expected ValidatedAiContext::Directory"),
        }

        let _ = std::fs::remove_dir_all(&temp_dir);
    }

    // Test 20: AI rejected system directory
    #[test]
    fn test_ai_rejected_system_directory() {
        let project_mgr = ProjectManager::new();

        // 1. Root /
        let err_root = validate_ai_working_directory("/", &project_mgr);
        assert!(err_root.is_err(), "Root / must be rejected");

        // 2. /etc
        let err_etc = validate_ai_working_directory("/etc", &project_mgr);
        assert!(err_etc.is_err(), "/etc must be rejected");

        // 3. /root
        let err_sysroot = validate_ai_working_directory("/root", &project_mgr);
        assert!(err_sysroot.is_err(), "/root must be rejected");

        // 4. ~/.ssh
        let err_ssh = validate_ai_working_directory("~/.ssh", &project_mgr);
        assert!(err_ssh.is_err(), "~/.ssh must be rejected");
    }

    // Test 21: AI non-Git directory validation
    #[test]
    fn test_ai_non_git_directory() {
        let temp_dir = std::env::temp_dir().join(format!("orbit_ai_nongit_{}", std::process::id()));
        let _ = std::fs::create_dir_all(&temp_dir);
        // Explicitly ensure NO .git exists
        assert!(!temp_dir.join(".git").exists());

        let project_mgr = ProjectManager::with_roots(vec![std::env::temp_dir()]);
        let res = validate_ai_working_directory(&temp_dir.to_string_lossy(), &project_mgr);
        assert!(res.is_ok(), "Non-git directory within allowed roots must be accepted: {:?}", res);

        let _ = std::fs::remove_dir_all(&temp_dir);
    }

    // Test 22: Existing Project-based AI still works
    #[test]
    fn test_existing_project_based_ai_works() {
        let cwd = std::env::current_dir().unwrap();
        let project_mgr = ProjectManager::new();

        let res = validate_ai_working_directory(&cwd.to_string_lossy(), &project_mgr);
        assert!(res.is_ok(), "Current workspace project must be accepted: {:?}", res);
    }

    // Test 23: No-context validation
    #[test]
    fn test_ai_no_context_validation() {
        let project_mgr = ProjectManager::new();

        let res_empty = validate_ai_working_directory("", &project_mgr).unwrap();
        assert_eq!(res_empty, ValidatedAiContext::NoContext);

        let res_none = validate_ai_working_directory("none", &project_mgr).unwrap();
        assert_eq!(res_none, ValidatedAiContext::NoContext);

        let res_spaces = validate_ai_working_directory("   ", &project_mgr).unwrap();
        assert_eq!(res_spaces, ValidatedAiContext::NoContext);
    }

    // Test 24: AI response extraction & buffering
    #[test]
    fn test_ai_response_extraction_and_buffering() {
        let mut task = AiTask {
            task_id: "task_resp_test".to_string(),
            device_id: "dev_1".to_string(),
            project_path: PathBuf::from("/home/user/project"),
            prompt: "Explain architecture".to_string(),
            agent: AiAgent::Plan,
            read_only: true,
            status: AiTaskStatus::Running,
            open_code_session_id: None,
            child_pid: None,
            started_at: 1000,
            finished_at: None,
            output: None,
            response: None,
            error: None,
            conversation_id: None,
            model: None,
            activities: Vec::new(),
        };

        assert!(task.response.is_none());

        task.append_response("Orbit is a remote ");
        task.append_response("AI command center.");

        assert_eq!(task.response.as_deref(), Some("Orbit is a remote AI command center."));

        // Bounded response buffer test
        let large_chunk = "R".repeat(1024);
        for _ in 0..300 {
            task.append_response(&large_chunk);
        }
        task.append_response("END_RESP");
        let resp = task.response.unwrap();
        assert!(resp.len() <= models::MAX_OUTPUT_BYTES_PER_TASK);
        assert!(resp.ends_with("END_RESP"));
    }

    // Test 25: Reasoning tokens filtered from user-facing response
    #[test]
    fn test_reasoning_tokens_filtered_from_response() {
        let reasoning_line = r#"{
            "type":"message.part.updated.1",
            "part":{
                "type":"reasoning",
                "text":"Let me think about how to answer this question without modifying anything..."
            }
        }"#;

        let parsed = OpenCodeEventParser::parse_line(reasoning_line);
        // Reasoning must NEVER produce ResponseChunk or OutputChunk
        match parsed {
            ParsedOpenCodeItem::Activity(info) => {
                assert_eq!(info.activity_type, AiActivityType::Thinking);
                assert!(!info.title.contains("think about how to answer"));
                assert_eq!(info.title, "Analyzing project & architecture...");
            }
            other => panic!("Reasoning must be mapped to safe thinking activity, got: {:?}", other),
        }
    }

    // Test 26: OpenCode permission requested event parsing
    #[test]
    fn test_opencode_permission_requested_parsing() {
        let line = r#"{
            "type": "permission.asked",
            "properties": {
                "id": "per_12345",
                "sessionID": "ses_abc123",
                "permission": "bash",
                "patterns": ["flutter analyze"],
                "metadata": {"command": "flutter analyze"},
                "always": ["flutter analyze"]
            }
        }"#;

        let res = OpenCodeEventParser::parse_line(line);
        match res {
            ParsedOpenCodeItem::PermissionRequested {
                id,
                session_id,
                permission,
                patterns,
                ..
            } => {
                assert_eq!(id, "per_12345");
                assert_eq!(session_id.as_deref(), Some("ses_abc123"));
                assert_eq!(permission, "bash");
                assert_eq!(patterns, vec!["flutter analyze"]);
            }
            other => panic!("Expected PermissionRequested, got {:?}", other),
        }
    }

    // Test 27: OpenCode permission replied event parsing
    #[test]
    fn test_opencode_permission_replied_parsing() {
        let line = r#"{
            "type": "permission.replied",
            "properties": {
                "requestID": "per_12345",
                "sessionID": "ses_abc123",
                "reply": "once"
            }
        }"#;

        let res = OpenCodeEventParser::parse_line(line);
        match res {
            ParsedOpenCodeItem::PermissionReplied { id, session_id, reply } => {
                assert_eq!(id, "per_12345");
                assert_eq!(session_id.as_deref(), Some("ses_abc123"));
                assert_eq!(reply, "once");
            }
            other => panic!("Expected PermissionReplied, got {:?}", other),
        }
    }

    // Test 28: PermissionManager risk classification
    #[test]
    fn test_permission_risk_classification() {
        use permission::{AiPermissionRisk, PermissionManager};

        // High risk: destructive bash command
        let risk_rm = PermissionManager::classify_risk(
            "bash",
            &["rm -rf /tmp/foo".to_string()],
            &serde_json::json!({}),
        );
        assert_eq!(risk_rm, AiPermissionRisk::High);

        let risk_git_reset = PermissionManager::classify_risk(
            "bash",
            &["git reset --hard HEAD~1".to_string()],
            &serde_json::json!({}),
        );
        assert_eq!(risk_git_reset, AiPermissionRisk::High);

        let risk_chmod = PermissionManager::classify_risk(
            "bash",
            &["chmod 777 script.sh".to_string()],
            &serde_json::json!({}),
        );
        assert_eq!(risk_chmod, AiPermissionRisk::High);

        let risk_delete = PermissionManager::classify_risk(
            "delete",
            &["file.txt".to_string()],
            &serde_json::json!({}),
        );
        assert_eq!(risk_delete, AiPermissionRisk::High);

        // Medium risk: regular commands and edits
        let risk_normal = PermissionManager::classify_risk(
            "bash",
            &["flutter analyze".to_string()],
            &serde_json::json!({}),
        );
        assert_eq!(risk_normal, AiPermissionRisk::Medium);

        let risk_edit = PermissionManager::classify_risk(
            "edit",
            &["lib/main.dart".to_string()],
            &serde_json::json!({}),
        );
        assert_eq!(risk_edit, AiPermissionRisk::Medium);

        // Low risk: read operations
        let risk_read = PermissionManager::classify_risk(
            "read",
            &["README.md".to_string()],
            &serde_json::json!({}),
        );
        assert_eq!(risk_read, AiPermissionRisk::Low);
    }

    // Test 29: PermissionManager lifecycle: create, allow, deny, ownership
    #[tokio::test]
    async fn test_permission_manager_lifecycle() {
        use permission::{AiPermissionDecision, AiPermissionState, PermissionManager};

        let pm = PermissionManager::new();

        // 1. Create request
        let (req, rx) = pm
            .create_request(
                "perm_1".to_string(),
                "task_1".to_string(),
                "device_a".to_string(),
                Some("ses_1".to_string()),
                "bash".to_string(),
                vec!["cargo test".to_string()],
                serde_json::json!({"command": "cargo test"}),
                "/home/user/project".to_string(),
            )
            .await;

        assert_eq!(req.state, AiPermissionState::Pending);

        // 2. Unmatched device cannot resolve
        let unauthorized_res = pm
            .resolve_request("device_b", "perm_1", AiPermissionDecision::Allow)
            .await;
        assert!(unauthorized_res.is_err());

        // 3. Matched device resolves Allow
        let ok_res = pm
            .resolve_request("device_a", "perm_1", AiPermissionDecision::Allow)
            .await;
        assert!(ok_res.is_ok());
        let resolved = ok_res.unwrap();
        assert_eq!(resolved.state, AiPermissionState::Approved);

        // Resolver channel receives Allow
        let decision = rx.await.unwrap();
        assert_eq!(decision, AiPermissionDecision::Allow);

        // Cannot resolve again
        let re_resolve = pm
            .resolve_request("device_a", "perm_1", AiPermissionDecision::Deny)
            .await;
        assert!(re_resolve.is_err());
    }

    // Test 30: Destructive action forbids Always Allow
    #[tokio::test]
    async fn test_destructive_action_forbids_always_allow() {
        use permission::{AiPermissionDecision, PermissionManager};

        let pm = PermissionManager::new();
        let (_req, _rx) = pm
            .create_request(
                "perm_destruct".to_string(),
                "task_2".to_string(),
                "device_a".to_string(),
                Some("ses_2".to_string()),
                "bash".to_string(),
                vec!["rm -rf /".to_string()],
                serde_json::json!({}),
                "/home/user/project".to_string(),
            )
            .await;

        // Attempt Always Allow on destructive action
        let res = pm
            .resolve_request("device_a", "perm_destruct", AiPermissionDecision::Always)
            .await;
        assert!(res.is_err(), "Always Allow must be forbidden for destructive actions");

        // Allow once must succeed
        let allow_once = pm
            .resolve_request("device_a", "perm_destruct", AiPermissionDecision::Allow)
            .await;
        assert!(allow_once.is_ok());
    }

    // Test 31: Task cancellation cascades to pending permissions
    #[tokio::test]
    async fn test_task_cancellation_cascades_permissions() {
        use permission::{AiPermissionDecision, AiPermissionState, PermissionManager};

        let pm = PermissionManager::new();
        let (_req, rx) = pm
            .create_request(
                "perm_cancel".to_string(),
                "task_3".to_string(),
                "device_a".to_string(),
                Some("ses_3".to_string()),
                "bash".to_string(),
                vec!["npm install".to_string()],
                serde_json::json!({}),
                "/home/user/project".to_string(),
            )
            .await;

        let cancelled = pm.cancel_task_requests("task_3").await;
        assert_eq!(cancelled.len(), 1);
        assert_eq!(cancelled[0].state, AiPermissionState::Cancelled);

        // Channel receives Deny on cancellation
        let decision = rx.await.unwrap();
        assert_eq!(decision, AiPermissionDecision::Deny);
    }
}
