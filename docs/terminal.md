# Orbit Remote Terminal Architecture & Specifications

> Detailed technical guide covering PTY allocation, session ownership, live streaming, rolling output buffers, and platform-specific behavior.

---

## 1. Overview & Architecture

Orbit provides real-time, interactive remote terminal access to the host PC from authenticated mobile and desktop clients. Unlike basic command-executing endpoints (`Command::new(...)`), Orbit spawns a genuine persistent pseudo-terminal (PTY) backed by native system shells (`/bin/bash`, `zsh`, PowerShell, `cmd.exe`).

```
Flutter Mobile App / Desktop UI
              │
              │ WebSocket (ws://<IP>:4371)
              ▼
┌─────────────────────────────────────────────────────────────┐
│ Orbit Desktop Agent                                         │
│                                                             │
│ ┌──────────────────────┐        ┌─────────────────────────┐ │
│ │  WebSocket Server    │◄──────►│     Message Router      │ │
│ │  (Real-time frames)  │        │ (Auth & Action Dispatch)│ │
│ └──────────┬───────────┘        └────────────┬────────────┘ │
│            │                                 │              │
│            ▼                                 ▼              │
│ ┌──────────────────────┐        ┌─────────────────────────┐ │
│ │ Session Manager      │        │    Terminal Manager     │ │
│ │ (Mobile Device IDs)  │        │ (PTY Session Registry)  │ │
│ └──────────────────────┘        └────────────┬────────────┘ │
│                                              │              │
│                                              ▼              │
│                                 ┌─────────────────────────┐ │
│                                 │     PTY Session         │ │
│                                 │ ┌─────────────────────┐ │ │
│                                 │ │ Master (Reader/Wrtr)│ │ │
│                                 │ ├─────────────────────┤ │ │
│                                 │ │ 100 KB Rolling Buf  │ │ │
│                                 │ ├─────────────────────┤ │ │
│                                 │ │ Child Killer Signal │ │ │
│                                 │ └─────────────────────┘ │ │
│                                 └────────────┬────────────┘ │
│                                              │              │
│                                              ▼              │
│                                 ┌─────────────────────────┐ │
│                                 │   Native Shell Process  │ │
│                                 │ (bash / zsh / pwsh)     │ │
│                                 └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Platform Shell Detection

Platform detection is encapsulated in `src-tauri/src/terminal/platform.rs`:

* **Linux**: Evaluates `$SHELL`. If not set or invalid, defaults to `/bin/bash` with fallback to `/bin/sh`.
* **macOS**: Evaluates `$SHELL`. If not set or invalid, defaults to `/bin/zsh` with fallback to `/bin/bash`.
* **Windows**: Evaluates `%COMSPEC%` or checks for `powershell.exe`, with fallback to `cmd.exe`.

Terminal sessions automatically export:
- `TERM=xterm-256color`
- `COLORTERM=truecolor`

This preserves full ANSI color palettes, text formatting, cursor addressing, and progress bars.

---

## 3. Session Lifecycle & Ownership Model

### 3.1 Device Identity vs. Connection ID
* **Device Ownership**: Every terminal session is tagged with `ownerDeviceId` (the persistent ID of the paired mobile client, e.g. `dev_5bf07bc0...`).
* **Connection Independence**: Mobile WebSocket connections are transient. When a mobile device disconnects (network blip, app backgrounded, Wi-Fi handover), **the PTY session continues running on the host**.
* **Reconnection**: When the mobile client reconnects and authenticates, it can invoke `terminal.list` to retrieve its active sessions and `terminal.history` to fetch recent output.
* **Ownership Enforcement**: `terminal.input`, `terminal.resize`, `terminal.kill`, and `terminal.history` strictly check that `request.deviceId == session.ownerDeviceId`. Unmatched attempts are rejected with `UNAUTHORIZED`.

### 3.2 Deadlock-Free Process Lifecycle
To prevent deadlocks between background waiting threads and asynchronous cancellation:
* Process termination uses `portable_pty::ChildKiller` via `child.clone_killer()`.
* The actual `Child` is owned solely by the waiter thread waiting on `child.wait()`.
* The `TerminalSession` retains a `ChildKiller` instance, allowing immediate asynchronous termination without lock contention.
* If a session is dropped or unreferenced, `TerminalSession::drop` automatically kills the child process to guarantee zero zombie processes.

---

## 4. Rolling Output Buffer (100 KB)

Each active terminal session maintains an in-memory `RollingBuffer` (`src-tauri/src/terminal/buffer.rs`):
* **Max Capacity**: 102,400 bytes (100 KB).
* **Eviction**: When new PTY output exceeds 100 KB, the oldest bytes are drained from the beginning of the buffer.
* **Replay Support**: Calling `terminal.history` returns the buffered output as UTF-8 (lossy), allowing a reconnecting client to immediately restore terminal context.

---

## 5. Security & Isolation

1. **Mandatory Pairing**: All `terminal.*` actions require an authenticated session (`UNAUTHORIZED` returned if unpaired).
2. **Path Traversal & CWD Validation**:
   - `cwd` values are validated with `Path::exists()` and `Path::is_dir()`.
   - Invalid paths return structured `INVALID_CWD` errors.
   - If omitted, defaults to the user's home directory (`$HOME`).
3. **Dimension Bounds**:
   - `cols` bounded between 20 and 500 (default 120).
   - `rows` bounded between 5 and 200 (default 30).
   - Out-of-bounds requests return `INVALID_DIMENSIONS`.
4. **Privacy Protection**: Terminal input, output, and environment variables are **never** logged to disk or console.
