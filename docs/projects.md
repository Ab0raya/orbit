# Orbit Projects + Git Architecture & Specifications

> Technical documentation for Orbit's remote project workspace discovery, Git lifecycle management, and mobile integration.

---

## 1. Product Model & Overview

Orbit turns mobile devices into remote workstation managers by placing **Projects** at the center of the development lifecycle. A project connects **Files**, **Git**, and **Terminal** under a unified hub:

```
Workstation
    │
    └── Projects
          │
          ├── Project A (e.g. Flutter / Git)
          │      ├── Files    ──► Remote File Explorer (scoped to Project A root)
          │      ├── Terminal ──► Remote PTY Shell (cwd = Project A root)
          │      └── Git      ──► Status, Branches, Stage/Unstage, Commit, History
          │
          ├── Project B (e.g. Rust / Git)
          │      ├── Files
          │      ├── Terminal
          │      └── Git
          │
          └── Project C (Directory / Non-Git)
                 ├── Files
                 └── Terminal
```

Non-Git projects are fully supported; developers can navigate files and launch terminal sessions directly within them without requiring a Git repository.

---

## 2. Project Discovery & Technology Detection

Project discovery inspects direct children of allowed workstation project roots (such as `~/Projects`, `~/Development`, `~/workspace`, or the active repository root).

> [!IMPORTANT]
> **No Recursive Disk Crawling**: To preserve host I/O and performance, the agent scans only the direct child directories of configured roots.

### Lightweight Technology Detection
Workstation project types are detected via marker files:
* `pubspec.yaml` ──► **Flutter**
* `Cargo.toml` ──► **Rust**
* `package.json` ──► **Node.js**
* `pyproject.toml` or `requirements.txt` ──► **Python**
* `build.gradle` or `android/` ──► **Android**
* Other directories ──► **Generic**

---

## 3. Git Security & Execution Model

1. **Argument Array Execution (No Shells)**:
   Git commands are **never** executed using shell strings (e.g., `sh -c "<args>"`). Commands strictly invoke `std::process::Command::new("git")` with explicit argument vectors. User-provided commit messages and branch names are passed as isolated process parameters.
2. **Path Scope Containment**:
   All paths passed to `git.stage` and `git.unstage` must be relative to the project root and cannot contain parent-directory traversals (`..`). Paths attempting to escape the repository are rejected with `INVALID_FILE_PATH`.
3. **No Network Operations**:
   No operations invoke `git push`, `git pull`, `git fetch`, or `git clone`. Orbit strictly manages local repository state.
4. **Non-Destructive Checkout**:
   If switching branches would overwrite uncommitted changes, Git's conflict response is detected and returned as a structured `CHECKOUT_CONFLICT` error. Local edits are never discarded automatically.
5. **No Arbitrary Commands**:
   Only the 8 explicit Git actions defined in the protocol can be invoked. Arbitrary Git commands cannot be run through WebSocket.

---

## 4. Protocol Operations

### 4.1 `projects.roots`
Returns allowed project root paths.
* **Request**: `{}`
* **Response**:
  ```json
  {
    "roots": [
      { "name": "Workspace", "path": "/home/user/projects/orbit" },
      { "name": "Projects", "path": "/home/user/Projects" }
    ]
  }
  ```

### 4.2 `projects.list`
Lists discovered projects in a specific root (or across all roots if omitted).
* **Request**: `{ "path": "/home/user/Projects" }`
* **Response**:
  ```json
  {
    "projects": [
      {
        "name": "orbit",
        "path": "/home/user/Projects/orbit",
        "kind": "git",
        "projectType": "rust",
        "git": {
          "branch": "main",
          "isDirty": false
        }
      }
    ]
  }
  ```

### 4.3 `projects.info`
Returns detailed metadata for a single project, including full Git status if applicable.
* **Request**: `{ "path": "/home/user/Projects/orbit" }`
* **Response**:
  ```json
  {
    "name": "orbit",
    "path": "/home/user/Projects/orbit",
    "kind": "git",
    "projectType": "rust",
    "git": {
      "branch": "main",
      "clean": true,
      "staged": [],
      "unstaged": [],
      "untracked": []
    }
  }
  ```

### 4.4 `git.status`
Returns structured status of working tree and index.
* **Request**: `{ "path": "/home/user/Projects/orbit" }`
* **Response**:
  ```json
  {
    "branch": "main",
    "clean": false,
    "staged": [
      { "path": "src/main.rs", "status": "modified" }
    ],
    "unstaged": [],
    "untracked": [
      { "path": "test.txt", "status": "untracked" }
    ]
  }
  ```

### 4.5 `git.branches`
Returns active branch and lists of local and remote branches.
* **Request**: `{ "path": "/home/user/Projects/orbit" }`
* **Response**:
  ```json
  {
    "current": "main",
    "local": ["main", "feature/login"],
    "remote": ["origin/main"]
  }
  ```

### 4.6 `git.checkout`
Switches to an existing branch. Returns updated `GitStatus`.
* **Request**: `{ "path": "/home/user/Projects/orbit", "branch": "feature/login" }`

### 4.7 `git.create_branch`
Creates a new branch and switches to it.
* **Request**: `{ "path": "/home/user/Projects/orbit", "name": "feature/ui" }`

### 4.8 `git.stage`
Stages specified relative file paths.
* **Request**: `{ "path": "/home/user/Projects/orbit", "paths": ["src/main.rs"] }`

### 4.9 `git.unstage`
Unstages specified relative file paths.
* **Request**: `{ "path": "/home/user/Projects/orbit", "paths": ["src/main.rs"] }`

### 4.10 `git.commit`
Commits staged changes with a required commit message.
* **Request**: `{ "path": "/home/user/Projects/orbit", "message": "Add login feature" }`
* **Response**:
  ```json
  {
    "hash": "6b753d105b38d7adbe3f1e944d1838cf",
    "branch": "main",
    "message": "Add login feature"
  }
  ```

### 4.11 `git.log`
Returns recent commits (default 20, max 100).
* **Request**: `{ "path": "/home/user/Projects/orbit", "limit": 20 }`
* **Response**:
  ```json
  {
    "commits": [
      {
        "hash": "6b753d105b38d7adbe3f1e944d1838cf",
        "shortHash": "6b753d1",
        "message": "Add login feature",
        "author": "Developer",
        "timestamp": 1725401200
      }
    ]
  }
  ```

---

## 5. Mobile User Experience

* **Projects List Screen**: Quick search filtering, root filter chips, technology badges, and branch indicators.
* **Project Detail Hub**:
  - Direct links to **Files** (opens file explorer at project root) and **Terminal** (spawns PTY session with project root as `cwd`).
  - **Git Section**: Branch selector sheet, staged/unstaged/untracked files with multi-select checkboxes, commit action modal.
  - **Git History Screen**: Commit log with relative timestamps and short hashes.
