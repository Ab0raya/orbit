# Orbit Remote File Explorer Architecture & Specifications

> Technical documentation for Orbit's secure remote file explorer and text editing capabilities.

---

## 1. Overview & Architecture

The **Orbit Remote File Explorer** enables mobile developers to browse directories on their connected development workstations, inspect file metadata, create folders, rename/delete files, and open, view, and safely edit text files remotely over the authenticated Orbit WebSocket protocol.

```
┌─────────────────────────────────────────────────────────────┐
│ 📱 Orbit Mobile (Flutter + Riverpod)                        │
│                                                             │
│ ┌───────────────────────┐        ┌────────────────────────┐ │
│ │ File Explorer View    │        │ Text File Editor View  │ │
│ │ - Directory listing   │───────►│ - Monospace editor     │ │
│ │ - Path breadcrumb     │        │ - Remote save          │ │
│ │ - Rename & delete     │        │ - Unsaved alert        │ │
│ └───────────────────────┘        └────────────────────────┘ │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               │ WebSocket (ws://<PC_IP>:4371)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 💻 Orbit Desktop Agent (Rust)                               │
│                                                             │
│ ┌───────────────────────┐        ┌────────────────────────┐ │
│ │ Path Normalizer       │───────►│ Operations Engine      │ │
│ │ - Scope boundary      │        │ - Directory reading    │ │
│ │ - Traversal rejection │        │ - Atomic file writes   │ │
│ │ - Cross-platform roots│        │ - Size caps (5 MB)     │ │
│ └───────────────────────┘        └────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Security & Path-Scope Model

1. **Authorization Barrier**: Only authenticated, paired mobile devices can call `files.*` actions. Unpaired requests are immediately rejected with `UNAUTHORIZED`.
2. **Path Normalization**: All paths are cleaned and normalized via component analysis (resolving `.`, `..`, and `~`) without evaluating shell commands or running subprocesses.
3. **Scope Enforcement**: Paths must reside within the workstation's authorized browse roots (by default, the user's home directory and project workspace). Any traversal attempt outside allowed scopes is rejected with `PERMISSION_DENIED`.
4. **Atomic Writes**: Writes do not overwrite files in place. Content is written to a sibling temporary file (`.orbit_tmp_<pid>_<filename>`), flushed to disk, and atomically renamed over the target path.
5. **Memory & Binary Safety**:
   - File reads are strictly capped at 5 MB (`DEFAULT_MAX_READ_BYTES`) to avoid out-of-memory errors on both host and mobile devices. Files exceeding this threshold return `FILE_TOO_LARGE`.
   - Only valid UTF-8 text files can be read or written. Binary files are rejected with `UNSUPPORTED_FILE_TYPE`.
6. **Deletion Confirmation**: Deletions cannot occur silently; the mobile UI requires explicit user confirmation before issuing `files.delete`.

---

## 3. Protocol Operations

### 3.1 `files.roots`
Returns user-accessible starting directories.
* **Request Payload**: `{}`
* **Response Payload**:
  ```json
  {
    "roots": [
      { "name": "Home", "path": "/home/username" },
      { "name": "Workspace", "path": "/home/username/projects/orbit" }
    ]
  }
  ```

### 3.2 `files.list`
Lists entries inside a directory. Directories are returned first, then files alphabetically.
* **Request Payload**: `{ "path": "/home/username/project" }`
* **Response Payload**:
  ```json
  {
    "path": "/home/username/project",
    "entries": [
      {
        "name": "src",
        "path": "/home/username/project/src",
        "kind": "directory",
        "size": 0,
        "modifiedAt": 1788470000,
        "hidden": false
      },
      {
        "name": "README.md",
        "path": "/home/username/project/README.md",
        "kind": "file",
        "size": 2048,
        "modifiedAt": 1788470000,
        "hidden": false
      }
    ]
  }
  ```

### 3.3 `files.read`
Reads a UTF-8 text file up to 5 MB.
* **Request Payload**: `{ "path": "/path/to/file.txt" }`
* **Response Payload**:
  ```json
  {
    "path": "/path/to/file.txt",
    "content": "File contents here...",
    "encoding": "utf8",
    "size": 1234
  }
  ```

### 3.4 `files.write`
Safely writes text content atomically to a file.
* **Request Payload**:
  ```json
  {
    "path": "/path/to/file.txt",
    "content": "New content to save"
  }
  ```
* **Response Payload**:
  ```json
  {
    "path": "/path/to/file.txt",
    "size": 19,
    "success": true
  }
  ```

### 3.5 `files.mkdir`
Creates a directory.
* **Request Payload**: `{ "path": "/path/to/new-folder" }`
* **Response Payload**: `{ "path": "/path/to/new-folder", "success": true }`

### 3.6 `files.rename`
Renames a file or directory.
* **Request Payload**: `{ "from": "/path/old.txt", "to": "/path/new.txt" }`
* **Response Payload**: `{ "from": "/path/old.txt", "to": "/path/new.txt", "success": true }`

### 3.7 `files.delete`
Deletes a file or directory.
* **Request Payload**: `{ "path": "/path/to/remove" }`
* **Response Payload**: `{ "path": "/path/to/remove", "success": true }`

---

## 4. Mobile UI & Experience

* **File Explorer**:
  - Breadcrumb path bar displaying current workstation directory.
  - Parent directory navigation button (`..`).
  - Distinct directory and file icons with case-insensitive alphabetical sorting (folders first).
  - Context menu for renaming and deletion.
  - "+ New Folder" modal dialog with real-time validation.
* **Text File Editor**:
  - Minimalist monospace developer editor.
  - Remote read and save with animated status indicators.
  - Unsaved change indicator dot in header.
  - Warning alert dialog preventing accidental back navigation if changes remain unsaved.
