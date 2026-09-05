use std::env;
use std::path::{Component, Path, PathBuf};

/// Returns default user-accessible browse roots.
pub fn default_browse_roots() -> Vec<(String, PathBuf)> {
    let mut roots = Vec::new();

    // 1. Home directory
    if let Ok(home) = env::var("HOME").or_else(|_| env::var("USERPROFILE")) {
        let home_path = PathBuf::from(&home);
        if home_path.exists() {
            roots.push(("Home".to_string(), home_path));
        }
    }

    // 2. Current working directory (workstation project root)
    if let Ok(cwd) = env::current_dir() {
        let ws = if cwd.file_name().map(|s| s == "src-tauri").unwrap_or(false) {
            cwd.parent().map(|p| p.to_path_buf()).unwrap_or(cwd.clone())
        } else {
            cwd.clone()
        };
        if !roots.iter().any(|(_, p)| p == &ws) {
            roots.push(("Workspace".to_string(), ws));
        }
    }

    // 3. Fallback: Unix root or Windows drives if roots is empty
    if roots.is_empty() {
        #[cfg(windows)]
        {
            roots.push(("C:\\".to_string(), PathBuf::from("C:\\")));
        }
        #[cfg(not(windows))]
        {
            roots.push(("Root".to_string(), PathBuf::from("/")));
        }
    }

    roots
}

/// Normalizes a path by resolving '.', '..', and '~' without executing shell commands.
pub fn normalize_path(path_str: &str) -> PathBuf {
    let path_str = path_str.trim();

    let expanded = if let Some(rest) = path_str.strip_prefix('~') {
        if let Ok(home) = env::var("HOME").or_else(|_| env::var("USERPROFILE")) {
            if rest.is_empty() {
                home
            } else if rest.starts_with('/') || rest.starts_with('\\') {
                format!("{}{}", home, rest)
            } else {
                path_str.to_string()
            }
        } else {
            path_str.to_string()
        }
    } else {
        path_str.to_string()
    };

    let path = Path::new(&expanded);
    let mut components = Vec::new();

    for component in path.components() {
        match component {
            Component::Prefix(prefix) => components.push(Component::Prefix(prefix)),
            Component::RootDir => components.push(Component::RootDir),
            Component::CurDir => {}
            Component::ParentDir => {
                // If there's a normal component before, pop it
                match components.last() {
                    Some(Component::Normal(_)) => {
                        components.pop();
                    }
                    Some(Component::RootDir) => {
                        // At root, .. stays at root
                    }
                    _ => {
                        components.push(Component::ParentDir);
                    }
                }
            }
            Component::Normal(name) => components.push(Component::Normal(name)),
        }
    }

    let mut result = PathBuf::new();
    for c in components {
        result.push(c.as_os_str());
    }

    result
}

/// Checks if a normalized path is inside any of the allowed scope directories.
/// If scopes is empty, all valid paths are permitted.
pub fn is_within_scopes(path: &Path, scopes: &[PathBuf]) -> bool {
    if scopes.is_empty() {
        return true;
    }

    // Try canonical path if it exists, otherwise use normalized path
    let target = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());

    scopes.iter().any(|scope| {
        let canonical_scope = scope.canonicalize().unwrap_or_else(|_| scope.clone());
        target.starts_with(&canonical_scope)
    })
}

/// Checks if a file/dir is hidden (starts with '.' on Unix or Windows).
pub fn is_hidden(path: &Path) -> bool {
    path.file_name()
        .and_then(|n| n.to_str())
        .map(|s| s.starts_with('.') && s != "." && s != "..")
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_path_basic() {
        let p = normalize_path("/a/b/../c/./d");
        assert_eq!(p, PathBuf::from("/a/c/d"));
    }

    #[test]
    fn test_normalize_path_root_traversal() {
        let p = normalize_path("/../../../etc");
        assert_eq!(p, PathBuf::from("/etc"));
    }

    #[test]
    fn test_is_hidden() {
        assert!(is_hidden(Path::new("/home/user/.git")));
        assert!(is_hidden(Path::new(".env")));
        assert!(!is_hidden(Path::new("/home/user/main.rs")));
    }

    #[test]
    fn test_default_roots() {
        let roots = default_browse_roots();
        assert!(!roots.is_empty());
    }
}
