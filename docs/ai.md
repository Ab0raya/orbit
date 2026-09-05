# Orbit — OpenCode AI Integration & Live AI Activity

> Architectural reference, security specification, protocol interactions, event normalization, and live command center integration for local OpenCode execution within the Orbit ecosystem.

---

## 1. Overview & Architecture

Orbit transforms local OpenCode CLI execution on the developer workstation into a real-time **developer command center** on mobile. The mobile developer does not just "start a task and wait" — they watch the AI work on their PC in real time.

### Architecture Diagram

```
Flutter Mobile Application
         │
         │ Authenticated Orbit Protocol (WebSocket)
         ▼
Orbit Desktop Agent (Tauri 2 / Rust)
         │
         ├── ProjectManager (Path & Scope Validation)
         │
         └── AiTaskManager
                 │
                 ├── Safe Process Discovery (PATH / mise shims)
                 ├── In-Memory Bounded History (500 activities, 256 KB output)
                 ├── Stderr Drainer (Prevents pipe deadlock)
                 ▼
          tokio::process::Command
                 │ (argv slice, strictly NO shell interpolation)
                 ▼
          opencode run "<prompt>" --dir "<path>" --agent <agent> --format json
                 │
                 ▼ NDJSON Stream (stdout)
          OpenCodeEventParser
                 │
                 ├── Strips hidden/raw reasoning tokens (`reasoning_details`)
                 ├── Extracts OpenCode session ID (`ses_...`)
                 ├── Normalizes relative file paths against project root
                 ├── Extracts tool commands, exit codes, and durations
                 └── Emits typed `AiActivity` structures
                 │
                 ▼ Broadcast Channel
          OrbitWsServer Forwarder
                 │
                 ▼ WebSocket (`ai.task.activity`, `ai.task.*`)
         Flutter Live Command Center UI
                 ├── Prominent Current Activity Card
                 ├── Technical Chronological Timeline
                 ├── Tap-to-Inspect Tool Details Modal Sheet
                 ├── Auto-scroll with "Jump to latest"
                 └── Monospace Selectable Output Viewer
```

---

## 2. OpenCode Dependency & Configuration

* **Local Installation**: OpenCode CLI must be installed on the host workstation. Orbit does not install, download, or auto-update OpenCode.
* **Supported Version**: Verified with OpenCode `1.18.27`.
* **Discovery Mechanism**:
  1. Inspects explicit `OPENCODE_BIN` environment variable override if defined.
  2. Resolves `opencode` binary from the system `PATH`.
  3. Checks standard mise user shim location (`~/.local/share/mise/shims/opencode`).
  4. If unresolved, returns structured error `OPENCODE_NOT_FOUND`.
* **Zero Cloud Intermediary**: All AI prompts, tool interactions, and responses stream directly peer-to-peer over the local authenticated WebSocket. Workstation provider credentials (`~/.local/share/opencode/auth.json` or environment variables) stay strictly on the local machine and are never transmitted over the network.

---

## 3. Strict Security Rules

Never expose:
- Chain-of-thought tokens or hidden reasoning
- Internal model deliberation (`reasoning_details`)
- System prompts
- Workstation credentials, auth tokens, or API keys
- Environment variables or raw process environments
- Workstation-absolute paths outside the active project

### High-Level Activity vs. Private Reasoning

Orbit exposes clean developer-facing activity indicators, never internal reasoning:
* **Allowed**: "Analyzing project & architecture...", "Reading file `lib/main.dart`", "Running command `flutter test`", "Tool exited (0)"
* **Forbidden**: Raw model thinking tokens, hidden prompts, or full process environment dumps.

---

## 4. Structured Activity Model

The Orbit protocol normalizes low-level OpenCode events into a clean, platform-independent activity model:

```rust
pub struct AiActivity {
    pub activity_id: String,
    pub task_id: String,
    pub timestamp: u64,
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
```

### Activity Types
* `thinking`: Task step execution or architectural analysis
* `reading`: Inspecting file contents (normalized to project-relative paths)
* `writing`: Modifying or creating file contents
* `command`: General shell execution (e.g. `flutter build`, `npm test`)
* `testing`: Running unit or integration test suites
* `tool`: Generic tool invocation
* `waiting`: Queued or awaiting process startup
* `completed`: Task step or overall task completion
* `error`: Tool failure or process error

### Tool Lifecycle
Tools transition deterministically:
`tool_started` (running) ──► `tool_finished` (completed / failed with duration & exit code)

---

## 5. Process Safety & Resource Bounding

1. **Deadlock Prevention**:
   - OpenCode process `stdout` is processed line-by-line via `BufReader`.
   - `stderr` is drained asynchronously in a dedicated tokio background task. If OpenCode emits substantial stderr diagnostics, the OS pipe buffer will never saturate and deadlock the child process.
2. **Reaping & Orphan Prevention**:
   - Cancellation issues `SIGINT` (or `start_kill` on Unix) and actively waits (`child.wait()`) to reap the exit status, preventing zombie processes.
3. **Bounded Activity History**:
   - In-memory activity history is capped at **500 activities** per task (`MAX_ACTIVITIES_PER_TASK`). Oldest entries are discarded when the buffer is exceeded.
4. **Bounded Output Stream**:
   - Raw output is capped at **256 KB** per task (`MAX_OUTPUT_BYTES_PER_TASK`). When exceeded, older bytes are sliced away at UTF-8 character boundaries to preserve newest output without memory leaks.

---

## 6. Deterministic Task State Machine

```
         QUEUED
           │
           ▼
        RUNNING
      ┌────┴────┐
      ▼         ▼
  COMPLETED   FAILED
      ▲
      │
  CANCELLED (Terminal, cannot be overwritten)
```

* State transitions are monotonic. Once a task enters `cancelled`, late process-exit events cannot overwrite it with `completed` or `failed`.
* Terminal states (`completed`, `failed`, `cancelled`) are permanent.

---

## 7. Reconnect Resilience

1. **Survives Disconnection**: AI tasks run in background Tokio tasks decoupled from WebSocket connection lifecycles. If the phone loses connection, OpenCode continues working on the workstation.
2. **Device Ownership Preservation**:
   - On reconnect, mobile passes its stored `deviceId` in `pairing.verify`.
   - The desktop agent re-associates the new connection with the existing device identity.
3. **State & Activity Recovery (`ai.task.get`)**:
   - Calling `ai.task.get` with `taskId` returns the complete task state, including the bounded activity timeline, output buffer, duration, and status.
   - The mobile UI immediately rehydrates the full command center view upon reconnect.

---

## 8. Protocol Reference

### 8.1 `ai.task.start`
* **Access Level**: Paired Only
* **Request**:
  ```json
  {
    "action": "ai.task.start",
    "payload": {
      "projectPath": "/home/user/workspace/orbit",
      "prompt": "Inspect codebase architecture",
      "agent": "plan",
      "readOnly": true
    }
  }
  ```
* **Response**:
  ```json
  {
    "taskId": "task_12345",
    "status": "queued"
  }
  ```

### 8.2 `ai.task.get` (New in Milestone 08)
* **Access Level**: Paired Only
* **Request**:
  ```json
  {
    "action": "ai.task.get",
    "payload": {
      "taskId": "task_12345"
    }
  }
  ```
* **Response**: Full `AiTask` object with `activities` list and bounded `output`.

### 8.3 `ai.task.cancel`
* **Access Level**: Paired Only
* **Request**:
  ```json
  {
    "action": "ai.task.cancel",
    "payload": {
      "taskId": "task_12345"
    }
  }
  ```

### 8.4 `ai.task.activity` (New in Milestone 08 Broadcast Event)
* **Payload**:
  ```json
  {
    "taskId": "task_12345",
    "activity": {
      "activityId": "act_67890",
      "taskId": "task_12345",
      "timestamp": 1725410000000,
      "activityType": "command",
      "status": "completed",
      "title": "Running tests",
      "tool": "bash",
      "command": "flutter test",
      "durationMs": 4200,
      "exitCode": 0
    }
  }
  ```

---

## 9. Global AI Command Center & AI Working Context (Milestone 08.5)

### 9.1 Conceptual Hierarchy: AI as Primary Destination

Orbit is an AI command center for your development PC; Projects, Files, Terminal, and Git are workstation capabilities. AI is accessible directly as a top-level tab in mobile navigation without requiring a prior Project or Git repository selection.

```
                    ORBIT
                      │
          ┌───────────┼───────────┐
          │           │           │
         AI         Files      Terminal
          │
          ▼
    AI Command Center
          │
    ┌─────┴─────┐
    │           │
 Context      No Context
    │
 ┌──┴───────────────┐
 │                  │
Project          Directory
 │
 └── optional Git
```

### 9.2 AI Working Context (`AiContext`)

AI operates against an explicit `AiContext`:
1. **No context** (`AiContextSource.none`): For general conversational/knowledge tasks that do not require workstation filesystem access. Commands execute within an isolated temporary sandbox (`/tmp/orbit_ai_sandbox`).
2. **Existing Project** (`AiContextSource.project`): Automatically associated when opened from Project Detail via "Ask Orbit AI" or chosen in the context picker modal.
3. **Arbitrary allowed directory** (`AiContextSource.directory`): Any user-specified path validated against allowed workspace roots without requiring Git or Project discovery.

### 9.3 Security Boundary & Path Validation

Arbitrary working directories are strictly validated before passing to OpenCode:
* **Allowed Roots**: Must reside within allowed workspace roots (e.g. `~/Projects`, `~/Development`).
* **Denied Locations**: Automatically rejected with structured error:
  - Root filesystem (`/`)
  - User home directory root (`~`)
  - System directories (`/etc`, `/root`, `/usr`, `/var`)
  - Sensitive credential locations (`~/.ssh`, `~/.aws`, `~/.gnupg`)
* **No Git Requirement**: Neither `.git` nor Git tracking is required. Non-Git repositories and standalone folders run OpenCode tasks identically.
* **No `--auto` Flag**: OpenCode is never passed `--auto`. Plan mode is strictly read-only; Build mode requires explicit confirmation.

---

## 10. AI Conversation Model & First-Class Responses (Milestone 08.6)

### 10.1 Conversational Layer Over AiTask

Orbit retains `AiTask` as the foundational execution unit while layering a natural, multi-turn conversational interface on top:

```
Conversation
    │
    ├── User Message ("Explain README.md")
    │
    ├── AI Task (`AiTask`)
    │      ├── Current Activity ("Reading README.md")
    │      ├── Technical Timeline ("Read 12 KB", "Analyzed architecture")
    │      └── Tool Execution (`bash`, `read_file`, etc.)
    │
    └── Assistant Response ("README.md describes Orbit as...")
```

* **Traceability**: Every assistant response is tied to an underlying `AiTask` ID and execution record.
* **Non-Disruptive Navigation**: Context selection occurs via an in-place bottom modal sheet, preserving active draft prompts, conversation history, and task states.

### 10.2 Response Extraction vs. Raw NDJSON / Internal Deliberation

The Desktop Agent extracts user-facing assistant content while strictly filtering out internal model internals:

* **Extracted**: `part.type == "text"` chunks are accumulated and broadcast via `ai.task.response` events with `{ taskId, delta }`.
* **Filtered Out**:
  - `part.type == "reasoning"` (Chain-of-thought tokens)
  - `reasoning_details` (Internal model deliberation)
  - Raw JSON-RPC envelopes and hidden system tokens
  - Credentials and internal environment dumps

### 10.3 Technical Timeline vs. Assistant Response

Orbit enforces a clear separation between technical execution metadata and conversational assistant output:

| Component | Purpose | Examples |
| :--- | :--- | :--- |
| **Current Activity** | Answers "What is Orbit doing right now?" | `Reading README.md`, `Running flutter analyze`, `Updating lib/main.dart` |
| **Technical Timeline** | Chronological record of tool execution | `✓ Read README.md (12 KB)`, `✓ Inspected mobile/lib/ (18 files)` |
| **Assistant Response** | Conversational answer delivered to the developer | Markdown explanations, bulleted analysis, code snippets |

Technical activities are never dumped into the chat bubble; assistant responses are never buried inside the technical timeline.

### 10.4 Streaming Assistant Responses (`ai.task.response`)

Incremental text parts from OpenCode NDJSON stream are immediately relayed over the WebSocket:
* `event: "ai.task.response"`
* `payload: { "taskId": "task_...", "delta": "README.md describes..." }`

On the mobile client, `AiTaskController` appends tokens in real time to the active `AiMessage`, providing low-latency streaming feedback without re-rendering the full conversation tree.

### 10.5 Markdown & Code Block Rendering

Assistant responses are rendered with full Markdown support using `flutter_markdown_plus`:
* Headers, bold text, lists, and inline code formatting.
* Styled monospace code blocks with horizontal scrolling.
* Dedicated **Copy Code** and **Copy Response** buttons with sanitized clipboard integration.

### 10.6 Visual Directory Selection (`DirectoryPickerSheet`)

Manual path typing is replaced with a visual filesystem browser:
* Navigates directories via `files.roots` and `files.list`.
* Displays folder icons, directory names, and breadcrumb path header.
* Files are disabled; only valid directories are selectable.
* Validates every selected directory through the desktop agent's security boundary.

### 10.7 File-to-AI Context Flow ("Ask Orbit AI" from Editor/Viewer)

Developers can seamlessly transition from file inspection to AI inquiry:
* Available from `CodeEditorScreen`, `ImagePreviewScreen`, and `BinaryFileScreen`.
* Pre-populates working directory context to the file's parent folder.
* Sets draft prompt context (e.g. `"Explain README.md"`).
* Keeps user in the primary AI Command Center.

