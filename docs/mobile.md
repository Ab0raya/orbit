# Orbit Mobile Architecture & Technical Guide

> Technical guide covering the Orbit Flutter mobile application architecture, WebSocket communication protocol, pairing verification, local persistence, reconnection strategy, and remote PTY terminal streaming.

---

## 1. Overview & Architecture

Orbit Mobile (`mobile/`) is a cross-platform Flutter application (iOS & Android) that allows developers to monitor and control their workstation remotely. It connects directly over the local network to the native Rust **Orbit Desktop Agent** via WebSockets (`ws://<PC_IP>:4371`), adhering to the **Orbit WebSocket Protocol v1.0**.

```
📱 Orbit Mobile (Flutter + Riverpod)
│
├── lib/core/
│   ├── networking/
│   │   ├── orbit_websocket_client.dart   # WS transport, request correlation, reconnection
│   │   └── connection_state.dart         # Connection state machine
│   ├── storage/
│   │   ├── local_storage.dart            # ILocalStorage abstraction
│   │   └── shared_prefs_storage.dart     # SharedPreferences implementation
│   └── errors/
│       └── orbit_exception.dart          # Typed exception hierarchy
│
├── lib/protocol/
│   ├── messages/
│   │   ├── orbit_request.dart            # JSON request envelope
│   │   ├── orbit_response.dart           # Correlated response envelope
│   │   ├── orbit_event.dart              # Asynchronous broadcast events
│   │   └── orbit_error.dart              # Structured error envelope
│   └── models/
│       ├── agent_status.dart             # Uptime, status, connected devices
│       ├── system_info.dart              # Hostname, OS, architecture, network IPs
│       ├── server_info.dart              # Port, listening state, client stats
│       ├── pairing_models.dart           # Pairing code verification
│       ├── terminal_models.dart          # PTY sessions, input, resize, history
│       └── file_models.dart              # File entries, read/write/list responses
│
├── lib/features/
│   ├── connection/                       # Host/Port input, handshake, recent devices
│   ├── pairing/                          # 6-digit PIN entry and authentication
│   ├── dashboard/                        # Host telemetry, uptime, tools navigation
│   ├── terminal/                         # Interactive PTY console & ANSI parser
│   └── files/                            # Remote File Explorer & Text File Editor
│
└── lib/shared/
    ├── theme/                            # Cyber-dark palette with neon lime/emerald
    └── widgets/                          # OrbitCard, OrbitButton, OrbitTextField, StatusPill
```

---

## 2. State Management with Riverpod

State management is built on **Riverpod**:
* `webSocketClientProvider`: Singleton `OrbitWebSocketClient` managing the transport connection.
* `localStorageProvider`: Injected `ILocalStorage` interface for device identity persistence.
* `connectionControllerProvider`: `StateNotifier` managing target host, port, socket connectivity, and welcome event validation.
* `pairingControllerProvider`: Manages 6-digit numeric pairing input, submission to `pairing.verify`, and storage of authenticated `deviceId`.
* `dashboardControllerProvider`: Polls `agent.status` and `system.info` with live latency tracking.
* `terminalControllerProvider`: Manages active remote terminal sessions, streams real-time `terminal.output` chunks, debounces terminal window resize calculations, and retrieves rolling history.

---

## 3. WebSocket Client & Request Correlation

### 3.1 Asynchronous Correlated Requests
Messages transmitted over the WebSocket use correlated request IDs:
```dart
final id = 'req_${uuid.substring(0, 12)}';
final request = OrbitRequest(id: id, action: 'system.info', payload: {});
```
`OrbitWebSocketClient` stores a `Completer<OrbitResponse>` in `_pendingRequests[id]` with a configurable timeout (default 10s). When the agent returns a response matching `id`, the matching completer is resolved.

### 3.2 Event Broadcast Stream
Incoming unidirectional frames (`type: "event"`) are pushed to `events: Stream<OrbitEvent>`:
* Handshake: `welcome`
* Session: `device.paired`, `device.connected`, `device.disconnected`
* PTY: `terminal.created`, `terminal.output`, `terminal.exited`, `terminal.error`

---

## 4. Pairing & Local Persistence

1. When pairing, the user enters the 6-digit code shown on the Orbit Desktop UI.
2. Mobile sends `pairing.verify`:
   ```json
   {
     "id": "req_...",
     "type": "request",
     "action": "pairing.verify",
     "payload": {
       "code": "842917",
       "name": "Alex's Phone",
       "platform": "android"
     }
   }
   ```
3. Upon success, the client receives `{ "paired": true, "deviceId": "dev_..." }`.
4. The mobile client stores:
   - `deviceId`
   - `pcAddress`
   - `pcPort`
   - `pcDisplayName`
   - `mobileDisplayName`
   - `pairedAt`
5. **Security**: The pairing code is **never** stored locally or transmitted outside the secure WebSocket channel.

---

## 5. Reconnection Strategy

When network connectivity is interrupted (Wi-Fi drop, mobile backgrounding):
* The client enters `OrbitConnectionStatus.reconnecting`.
* Exponential backoff is applied: 1s, 2s, 4s, 8s, up to a maximum of 30 seconds.
* Active PTY terminal sessions **remain running on the Desktop Agent**.
* Upon reconnecting, the mobile app calls `terminal.list` to retrieve active sessions and `terminal.history` to fetch the 100 KB rolling buffer.

---

## 6. Remote Terminal Integration

The mobile terminal (`lib/features/terminal/`) provides:
* **True Streaming**: Output chunks from `terminal.output` are rendered immediately into the console without buffering whole commands.
* **ANSI Sequence Parsing**: Terminal colors (16-color & bright 256-color palettes), bold, and reset codes are converted to styled `TextSpan`s.
* **Viewport Resizing**: Viewport dimensions are calculated and debounced before sending `terminal.resize` to the PTY.
* **Accessory Shortcuts**: Hardware/virtual keys for `Ctrl+C`, `Tab`, `Esc`, `↑`, `↓`, and `Clear`.
* **Rolling Buffer Recovery**: Restores terminal state via `terminal.history`.

---

## 7. Remote File Explorer & Text Editor

The file explorer (`lib/features/files/`) provides:
* **Directory Browsing**: Hierarchical navigation with path breadcrumbs, parent navigation (`..`), and refresh.
* **Workstation Metadata**: Displays file size and modification timestamps, with folders prioritized at the top.
* **File Operations**: In-place folder creation (`files.mkdir`), renaming (`files.rename`), and deletion (`files.delete` with confirmation modal).
* **Text File Editor**: Remote viewing and editing for files up to 5 MB with atomic saving (`files.write`) and unsaved changes interception via `PopScope`.

---

## 8. Projects & Git Integration

The projects feature (`lib/features/projects/`) turns Orbit into a workstation manager:
* **Project Discovery**: Lists workstation projects with search query filtering and technology detection (Flutter, Rust, Node, Python, Android, Generic).
* **Project Detail Hub**: Central screen connecting:
  - **[ Files ]**: Pre-focused file explorer at the project root.
  - **[ Terminal ]**: New PTY terminal with `cwd` set to the project root.
  - **[ Git ]**: Branch switcher, commit history, and staging view.
* **Local Git Workflow**: Interactive staging/unstaging with selective checkboxes, branch creation/checkout with conflict guard, and atomic commit dialog.
* **Git History**: Commit log viewer with short hashes, author, and relative timestamps.

---

## 9. Live AI Activity & Command Center

The AI integration (`lib/features/ai/`) provides a full developer command center for OpenCode execution:
* **Prompt Composer (`AiPromptScreen`)**:
  - Multiline prompt entry with project context header.
  - Mode toggle between **Plan** (read-only analysis) and **Build** (mutating development).
  - Explicit confirmation modal for mutating `build` tasks to guard against inadvertent project edits.
* **Live Activity Command Center (`AiTaskScreen`)**:
  - **Prominent Current Activity Banner**: Displays live tool execution (e.g. `Running tests: flutter test`, `Reading file: lib/main.dart`) with active pulse indicator and duration.
  - **Technical Chronological Timeline**: Type-specific icons (`terminal`, `science`, `description`, `edit_note`, `memory`), timestamps, and duration badges.
  - **Tap-to-Inspect Tool Details Modal**: Bottom sheet revealing tool name, status, exact command, relative file path, duration, and exit code with zero secret leakage.
  - **Intelligent Auto-Scroll**: Follows new events automatically when at the bottom; pauses when the developer scrolls up, displaying a subtle "Jump to latest" floating button.
  - **Monospace Output Viewer**: Monospace font with selectable text, copy-to-clipboard button, and bounded memory buffer.
  - **Summary Cards**:
    - Completed: Duration (`MM:SS`), total activities, tools executed, and files touched metrics.
    - Failed: OpenCode exit code and sanitized error description.
## 10. Milestone 08.5: First-Class AI Command Center & File Enhancements

### 10.1 Top-Level Navigation Shell (`MainNavigationShell`)
Orbit Mobile positions AI as a primary top-level destination:
* **Primary Navigation Tabs**:
  1. **Home** (`DashboardScreen`): Telemetry, uptime, connected status, and quick-jump hero cards.
  2. **AI** (`AiCommandCenterScreen`): Global AI workspace for workstation-wide analysis.
  3. **Files** (`FileExplorerScreen`): Filesystem browsing and file viewing.
  4. **Terminal** (`TerminalScreen`): Interactive PTY terminal shell.
  5. **Projects** (`ProjectsScreen`): Workstation project directory explorer.

### 10.2 Global AI Command Center (`AiCommandCenterScreen`)
* **AI Working Context (`AiContext`)**:
  - `No context`: General prompts executed in a temporary sandbox directory without workstation mutation risk.
  - `Existing Project`: Context auto-selected when opened from Project Detail ("Ask Orbit AI") or selected from project list.
  - `Arbitrary Directory`: Safe directory validation against allowed workspace roots.
* **Context Selector Modal**: Bottom sheet to switch between No Context, discovered Projects, and custom paths.
* **Plan vs. Build Switcher**:
  - `PLAN`: Read-only analysis and inspection.
  - `BUILD`: Explicit confirmation modal; `--auto` flag is never passed.
* **Active Tasks Banner**: Displays currently running tasks with elapsed timer and instant navigation.
* **Recent Tasks List**: Displays completed/failed tasks with execution duration, prompt title, and context badge.

### 10.3 Code Editor (`CodeEditorScreen`)
* **Syntax Highlighting**: Powered by `flutter_highlight` with `atomOneDarkTheme`.
* **Line Numbers Gutter**: Monospace line numbers aligned with code lines.
* **Horizontal Scrolling**: Wrapped in dual-axis scroll views preventing line distortion.
* **In-File Search**: Query matching, match count (`X of Y`), cyclic previous/next navigation, and auto-scrolling to match.
* **View vs. Edit Modes**: Read-only by default; explicit "Edit" mode enables text modification with unsaved changes tracking (`PopScope`) and atomic `files.write` saving.

### 10.4 Image & Binary File Previews
* **`ImagePreviewScreen`**: Supports PNG, JPEG, animated GIF, WebP, BMP, and SVG (rendered vectorially via `flutter_svg`). Pinch-to-zoom and pan via `InteractiveViewer`. Metadata footer with dimensions (`512 × 512`), MIME type, and size.
* **`BinaryFileScreen`**: Gracefully displays metadata and hex dump preview for compiled binaries, archives, and unknown formats without UTF-8 decode errors.
* **Oversized Protection**: Bounded preview limits (5 MB) display safe warning cards rather than transferring unbounded payloads.

---

## 11. AI Conversation, Connection UX & Visual Context (Milestone 08.6)

### 11.1 Conversational AI Experience

Orbit Mobile elevates the AI Command Center from an isolated task executor to an interactive development workstation conversational partner:
* **Natural Dialogue Flow**: User prompts and assistant responses are rendered as chat bubbles linked to execution units.
* **Traceable Execution**: Each message maintains a reference to its underlying `AiTask` ID.
* **Context Preservation**: Changing directories or inspecting technical details never clears current prompt drafts or kicks the user out to Home.
* **Actionable Prompt Suggestions**: Pre-built quick action chips (`Explain README.md`, `Analyze architecture`, `Check test coverage`) accelerate standard queries.

### 11.2 Response Markdown & Code Block Actions

Assistant responses are parsed and styled with developer aesthetics:
* Powered by `flutter_markdown_plus` with syntax highlighting integration.
* Code blocks feature dedicated headers indicating language, horizontal scrolling, and a 1-tap **Copy Code** action.
* Full responses include a **Copy Response** button with notification feedback.

### 11.3 Visual Directory Picker (`DirectoryPickerSheet`)

Manual path entry is superseded by a visual filesystem navigator:
* Fetches allowed workspace roots via `files.roots`.
* Navigates child folders via `files.list`, clearly distinguishing directories from files.
* Breadcrumb navigation bar supports jumping up directory levels.
* Files are disabled; only directories can be selected.
* Backend retains ultimate security authority, re-validating all paths before execution.

### 11.4 In-Place Context Selection

Context selection operates via an overlay modal bottom sheet:
* Tap current working context banner to open `DirectoryPickerSheet`.
* Choose between **No Context**, discovered **Projects**, or browse **Directories**.
* On selection, updates working context in place without resetting draft prompt or conversation history.

### 11.5 QR Code Pairing & Scanner (`QrScannerSheet`)

Fast, camera-based pairing via standard Orbit QR URI scheme:
* Desktop displays an SVG QR encoding `orbit://pair/v1?host=...&port=...&code=...&expires=...`.
* Mobile scanner (`mobile_scanner`) requests camera permissions and decodes `OrbitPairingQrPayload`.
* Validates pairing code expiration TTL before prefilling host and port settings.
* Zero secrets or credentials stored in QR payloads.
* Fallback manual IP/port entry remains readily available.

### 11.6 Stable Device Identity & Reconnection Resilience (`session.resume`)

Eliminates duplicate device records on desktop:
* Mobile installation generates and persists a UUID `installationDeviceId`.
* Initial pairing passes `deviceId` to register permanent device record.
* Socket reconnections or app restarts call `session.resume` with existing `deviceId`.
* Desktop rebinds the active WebSocket connection to the existing device record, maintaining an invariant of 1 paired device count.




