# Orbit Desktop

> Orbit is a desktop + mobile system that allows developers to monitor, control, and inspect their development PC remotely from a mobile application.

Orbit Desktop is designed not simply as an administrative GUI, but as a local control/status interface for the background **Orbit Agent** running within the native Rust system layer.

---

## Architecture Overview

```
                      +--------------------------------+
                      |       Orbit Mobile App         |
                      +--------------------------------+
                                      │
                                      │ WebSocket (ws://<PC_IP>:4371)
                                      ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Orbit Desktop                                                          │
│                                                                        │
│  ┌───────────────────────┐             ┌────────────────────────────┐  │
│  │     Tauri UI          │             │        Orbit Agent         │  │
│  │ (React 18 + TS + Vite)│◄─── IPC ───►│        (Rust Layer)        │  │
│  └───────────────────────┘             └─────────────┬──────────────┘  │
│                                                      │                 │
│         ┌─────────────────────────┬──────────────────┴──────────┐      │
│         ▼                         ▼                             ▼      │
│  ┌──────────────┐     ┌──────────────────────┐          ┌────────────┐ │
│  │ WS Server    │◄───►│    Message Router    │◄────────►│ Session /  │ │
│  │ (Port 4371)  │     │ (Validate & Dispatch)│          │ Device Mgr │ │
│  └──────────────┘     └──────────┬───────────┘          └────────────┘ │
│                                  ▼                                     │
│                       ┌──────────────────────┐                         │
│                       │   Action Handlers    │                         │
│                       │ • ping               │                         │
│                       │ • pairing.verify     │                         │
│                       │ • system.info        │                         │
│                       │ • agent.status       │                         │
│                       │ • server.info        │                         │
│                       └──────────────────────┘                         │
└────────────────────────────────────────────────────────────────────────┘
```

### Component Structure

```
orbit/
├── docs/
│   └── protocol.md               # Complete Orbit WebSocket Protocol v1.0 specification
├── scripts/
│   └── test_client.mjs           # Automated end-to-end integration test client
├── src/                          # Tauri Frontend UI
│   ├── components/
│   │   ├── Header.tsx            # Orbit branding, agent status, reload action
│   │   ├── StatusBadge.tsx       # Status pills with pulse animations
│   │   ├── InfoCard.tsx          # Card container with developer-tool styling
│   │   ├── PairingCard.tsx       # 6-digit numeric pairing code display & actions
│   │   ├── NetworkCard.tsx       # Local network IPs and adapter inspect
│   │   └── ServerCard.tsx        # WebSocket server port, status, connected devices
│   ├── pages/
│   │   └── OverviewPage.tsx      # Main developer overview and telemetry
│   ├── services/
│   │   └── agentService.ts       # Typed Tauri invoke wrappers & formatters
│   ├── types/
│   │   ├── agent.ts              # TypeScript interfaces mirroring Rust structs
│   │   └── protocol.ts           # Discriminated union protocol definitions
│   ├── App.tsx                   # Root UI component
│   ├── main.tsx                  # React entry point
│   └── index.css                 # Dark-first developer design system
│
└── src-tauri/                    # Rust Agent & System Layer
    ├── src/
    │   ├── agent/
    │   │   ├── mod.rs            # OrbitAgent lifecycle orchestrator & uptime tracker
    │   │   ├── server.rs         # Tokio-tungstenite WebSocket server (port 4371)
    │   │   ├── router.rs         # Message parser, authorization, & dispatcher
    │   │   ├── handlers.rs       # Action handlers (ping, pair, system, status)
    │   │   ├── session.rs        # Session state & paired device registry
    │   │   ├── pairing.rs        # Numeric pairing code generation & expiration TTL
    │   │   └── system.rs         # Real device hostname, OS, arch, & network IPs
    │   ├── protocol/
    │   │   ├── mod.rs            # Protocol module root
    │   │   ├── message.rs        # Root OrbitMessage enum
    │   │   ├── request.rs        # Request envelope struct
    │   │   ├── response.rs       # Response envelope struct & constructors
    │   │   ├── events.rs         # Event envelope struct & constructors
    │   │   └── errors.rs         # Structured ProtocolError types
    │   ├── commands.rs           # Typed Tauri IPC command handlers
    │   ├── lib.rs                # Tauri 2 app builder, setup, & runtime manager
    │   └── main.rs               # Binary entry point
    ├── Cargo.toml                # Rust dependencies
    └── tauri.conf.json           # Tauri 2 configuration
```

---

## Orbit WebSocket Protocol (v1.0)

See [docs/protocol.md](docs/protocol.md) for complete specifications and JSON payloads.

### Message Envelope

All communication uses JSON envelopes with correlated request IDs:

* **Request**:
  ```json
  { "id": "req_001", "type": "request", "action": "system.info", "payload": {} }
  ```
* **Response (Success)**:
  ```json
  { "id": "req_001", "type": "response", "action": "system.info", "success": true, "payload": { ... } }
  ```
* **Response (Error)**:
  ```json
  { "id": "req_001", "type": "response", "action": "system.info", "success": false, "error": { "code": "UNAUTHORIZED", "message": "..." } }
  ```
* **Event**:
  ```json
  { "type": "event", "event": "device.paired", "payload": { ... } }
  ```

### Supported Actions & Access Levels

| Action | Access Level | Description |
| :--- | :--- | :--- |
| `ping` | **Public** | Heartbeat & RTT measurement. Returns `{ timestamp: u64 }`. |
| `pairing.verify` | **Public** | Validates the 6-digit code, marks session paired, assigns device ID, and emits `device.paired`. |
| `system.info` | **Paired Only** | Hostname, OS, architecture, network adapters, and local IPs. |
| `agent.status` | **Paired Only** | Agent health (`online`), uptime in seconds, software version, connected paired devices. |
| `server.info` | **Paired Only** | Port (`4371`), listening status, bind address, active connected clients. |
| `terminal.create` | **Paired Only** | Spawns a persistent PTY session running platform shell (`bash`/`zsh`/`pwsh`). |
| `terminal.input` | **Owner Only** | Streams keystrokes directly into PTY stdin. |
| `terminal.resize` | **Owner Only** | Resizes native PTY window rows & cols. |
| `terminal.list` | **Paired Only** | Lists active sessions owned by authenticated device. |
| `terminal.history` | **Owner Only** | Fetches recent 100 KB rolling buffer upon client reconnection. |
| `terminal.kill` | **Owner Only** | Gracefully kills PTY process and emits `terminal.exited`. |

---

## Remote Terminal Architecture

See [docs/terminal.md](docs/terminal.md) for full architecture specifications.

* **PTY Engine**: Cross-platform pseudo-terminal powered by `portable-pty` (Linux, macOS, Windows).
* **Process Independence**: Terminal sessions are bound to persistent `deviceId`s, not transient WebSocket connections. Sessions survive mobile app backgrounding and reconnections.
* **Deadlock-Free Lifecycle**: Uses isolated `ChildKiller` process signallers so termination never deadlocks with blocked waiter threads.
* **Rolling Replay Buffer**: Retains the last 100 KB of output per session for instant replay upon reconnection.

---

## Remote File Explorer Architecture

See [docs/files.md](docs/files.md) for full architecture specifications.

* **Scope Enforcement**: Enforces a secure browse boundary starting at the user's home/workspace directories and rejects directory traversal attacks.
* **Atomic Writes**: Writes are flushed to temporary files and renamed atomically over destination targets to prevent corruption.
* **Memory Protection**: Maximum text file read size capped at 5 MB; rejects non-UTF-8 binary files.
* **Mobile File Manager & Text Editor**: Directory tree browsing, parent navigation (`..`), folder creation, renaming, deletion with confirmation modal, and a clean monospace text file editor.

---

## Projects & Git Architecture

See [docs/projects.md](docs/projects.md) for full architecture specifications.

* **Workstation Project Hub**: Discovers development repositories (Flutter, Rust, Node, Python, Android, Generic) across allowed project roots.
* **Project Centrality**: Connects Files (scoped file explorer) and Terminal (spawns with project `cwd`) directly from the project detail hub.
* **Safe Git Engine**: Executes Git commands with explicit argument vectors (never `sh -c`), enforces repository containment, and prevents destructive overwrites (`CHECKOUT_CONFLICT`).
* **Local Git Workflows**: Full mobile UI for branch switching, branch creation, selective file staging/unstaging, commits, and commit log viewing.

---

## Security Model

1. **Unpaired Authorization Boundary**: Unpaired clients can only call `ping` and `pairing.verify`. All other actions return `UNAUTHORIZED`.
2. **Terminal Ownership Boundary**: A mobile client can only access, write to, resize, or kill terminal sessions that it owns (`ownerDeviceId`).
3. **CWD Directory Validation**: Working directories are strictly validated (`Path::exists()` & `Path::is_dir()`).
4. **Zero Code or Stream Logging**: Pairing codes, terminal input, and terminal output are **never** logged to stdout, logs, or disk.
5. **Brute-Force Protection**: 5 consecutive invalid pairing attempts triggers `RATE_LIMITED`.
6. **Dimension & Message Size Caps**: Message size capped at 64 KB; terminal dimensions bounded (cols: 20-500, rows: 5-200).

---

## Development & Verification

### Running Locally

```bash
# 1. Install frontend dependencies
npm install

# 2. Compile and verify TypeScript frontend
npm run build

# 3. Run Rust unit tests
cargo test --manifest-path src-tauri/Cargo.toml

# 4. Run Rust Clippy verification
cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings

# 5. Build native binary
cargo build --manifest-path src-tauri/Cargo.toml

# 6. Run automated end-to-end integration tests
ORBIT_TEST_PAIRING_CODE=842917 ./src-tauri/target/debug/orbit-desktop &
node scripts/test_client.mjs
node scripts/test_terminal.mjs
```

---

## Orbit Mobile (Flutter)

See [docs/mobile.md](docs/mobile.md) for full mobile architectural documentation, and [docs/ai.md](docs/ai.md) for OpenCode AI integration details.

### Prerequisites

* Flutter SDK `^3.13.0`
* Dart `^3.13.0`
* OpenCode CLI (tested with `v1.18.27`) on workstation

### Running Orbit Mobile

```bash
# 1. Change to mobile directory
cd mobile

# 2. Fetch dependencies
flutter pub get

# 3. Analyze code
flutter analyze

# 4. Run unit tests
flutter test

# 5. Run live integration test against local Orbit Desktop
ORBIT_TEST_PAIRING_CODE=842917 flutter test test/integration_test.dart

# 6. Run on connected mobile device or emulator
flutter run
```

---

## Live AI Command Center (OpenCode Integration)

Orbit turns your mobile device into an AI command center for your development workstation:
* **Live Activity Streaming**: Real-time structured activity events (`ai.task.activity`) showing step progress, command execution, tool invocations, and file operations.
* **Tool Lifecycle Tracking**: Complete tool lifecycle visibility (`started` -> `running` -> `finished` with exit codes and durations).
* **Zero Hidden Reasoning Leakage**: Strips private model deliberation (`reasoning_details`, internal chain-of-thought) into high-level, human-readable indicators.
* **Intelligent Auto-Scroll & Viewer**: Real-time following with "Jump to latest" floating button and a dedicated monospace output viewer.
* **Tap-to-Inspect Tool Details**: Bottom sheet providing exact command inspection, exit codes, durations, and file paths.
* **Reconnect Resilience**: Tasks run in background processes and survive WebSocket disconnects; full history and state are restored seamlessly via `ai.task.get`.
* **Bounded Resource Guarantees**: Enforces 500 activities and 256 KB output memory bounds per task with asynchronous stderr drain preventing deadlocks.
* See [docs/ai.md](docs/ai.md) for complete details.

---

## Milestone 08.5: Product UX Correction

Orbit's information architecture firmly establishes Orbit as a remote AI command center for your development PC, where Projects, Files, Terminal, and Git are supporting capabilities:

* **Top-Level AI Command Center**: AI is a first-class navigation destination accessible immediately without preselecting a project.
* **AI Working Context (`AiContext`)**: Operates against an explicit context:
  - `No context`: General queries executed safely in an isolated sandbox.
  - `Existing Project`: Context preselected via "Ask Orbit AI" from project detail or selected from the project list.
  - `Arbitrary Directory`: Safe directory validation against allowed workspace roots.
* **AI Independent of Git & Project Discovery**: OpenCode tasks run seamlessly on arbitrary directories and non-Git repositories without requiring Git tracking or metadata.
* **Developer Code Editor**: Full syntax highlighting across Dart, TypeScript, Rust, Python, Go, and more, line numbers gutter, horizontal scrolling, in-file search with match count navigation, explicit edit mode, and atomic `files.write` saving.
* **Image & Binary File Previews**: Native image rendering for PNG, JPEG, animated GIF, WebP, BMP, and SVG (vector rendering via `flutter_svg`) with pinch-to-zoom and dimension metadata (`512 × 512`), along with graceful hex dump previews for binary files without UTF-8 decode errors.
* **Capabilities-Centric Projects UX**: Non-Git projects display available capabilities (Files, Terminal, Orbit AI) without broken status warnings; Git is clearly presented as an optional capability.

---

## Milestone 08.6: AI Conversation + Connection & Context UX

* **Conversational AI Experience**: Multi-turn dialogue (`User -> AiTask -> AI Response`) layered over traceable `AiTask` execution units.
* **First-Class Assistant Responses**: Clean, user-visible assistant responses extracted from OpenCode NDJSON and completely separated from internal deliberation and activity logs.
* **Streaming AI Responses**: Real-time token streaming over `ai.task.response` events without full-tree widget rebuilds.
* **Rich Markdown & Code Block Actions**: Assistant responses render Markdown formatting with styled code blocks, syntax-appropriate font, horizontal scrolling, and 1-tap copy actions.
* **Meaningful Current Activity & Informative Timeline**: Current activity answers "What is Orbit doing right now?" (`Reading README.md`, `Running flutter analyze`), while the technical timeline records completed actions.
* **Visual Directory Picker**: Visual filesystem browser (`DirectoryPickerSheet`) replacing manual path entry with safe root validation.
* **In-Place Context Switching**: Modal overlay context selection preserves current draft prompt and conversation history without navigation jumps.
* **QR Code Pairing**: Instant pairing via `orbit://pair/v1` QR codes respecting 10-minute TTLs with zero credential leakage.
* **Stable Device Identity**: Resolves duplicate device bug via persistent installation `deviceId`, seamless socket replacement, and `session.resume`.
* **File-to-AI Context Flow**: Direct "Ask Orbit AI" action from code editor and file preview screens with automatic context preselection.


