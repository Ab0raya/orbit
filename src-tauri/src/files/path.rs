use std::collections::HashSet;
use std::env;
use std::path::{Component, Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiscoveredRoot {
    pub name: String,
    pub path: PathBuf,
    pub label: Option<String>,
    pub kind: String, // "drive" | "volume" | "mount" | "home" | "workspace"
    pub is_removable: bool,
}

#[cfg(unix)]
fn is_mount_point(path: &Path) -> bool {
    use std::os::unix::fs::MetadataExt;
    if let (Ok(meta), Some(parent)) = (std::fs::metadata(path), path.parent()) {
        if let Ok(parent_meta) = std::fs::metadata(parent) {
            return meta.dev() != parent_meta.dev();
        }
    }
    false
}

#[cfg(not(unix))]
fn is_mount_point(_path: &Path) -> bool {
    false
}

/// Discovers accessible filesystem drive roots, mounted volumes, and user roots across platforms.
pub fn discover_system_roots() -> Vec<DiscoveredRoot> {
    let mut roots = Vec::new();

    #[cfg(windows)]
    {
        let mut seen_paths = HashSet::new();

        // 1. Query sysinfo::Disks for drives with volume names and metadata
        let disks = sysinfo::Disks::new_with_refreshed_list();
        for disk in disks.list() {
            let mount = disk.mount_point();
            let path_buf = mount.to_path_buf();
            let name_os = disk.name().to_string_lossy();
            let label = if !name_os.trim().is_empty() {
                name_os.trim().to_string()
            } else if mount == Path::new("C:\\") {
                "System Drive".to_string()
            } else if disk.is_removable() {
                "External Drive".to_string()
            } else {
                "Local Disk".to_string()
            };

            let name = mount.to_string_lossy().to_string();
            seen_paths.insert(path_buf.to_string_lossy().to_uppercase());
            roots.push(DiscoveredRoot {
                name,
                path: path_buf,
                label: Some(label),
                kind: if disk.is_removable() {
                    "removable".to_string()
                } else {
                    "drive".to_string()
                },
                is_removable: disk.is_removable(),
            });
        }

        // 2. Iterate logical drive letters A..=Z in case any accessible drives were not in sysinfo
        for letter in b'A'..=b'Z' {
            let drive_str = format!("{}:\\", letter as char);
            let drive_path = PathBuf::from(&drive_str);
            let key = drive_str.to_uppercase();
            if !seen_paths.contains(&key) && drive_path.exists() {
                let label = if letter == b'C' {
                    "System Drive".to_string()
                } else {
                    "Local Disk".to_string()
                };
                seen_paths.insert(key);
                roots.push(DiscoveredRoot {
                    name: drive_str,
                    path: drive_path,
                    label: Some(label),
                    kind: "drive".to_string(),
                    is_removable: false,
                });
            }
        }
    }

    #[cfg(target_os = "linux")]
    {
        // 1. System Root
        roots.push(DiscoveredRoot {
            name: "System Root".to_string(),
            path: PathBuf::from("/"),
            label: Some("System Drive".to_string()),
            kind: "drive".to_string(),
            is_removable: false,
        });

        let mut seen_paths = HashSet::new();
        seen_paths.insert(PathBuf::from("/"));

        // 2. Discover external / secondary storage drives via sysinfo
        let disks = sysinfo::Disks::new_with_refreshed_list();

        // Identify the underlying block device / pool for the system root
        let root_disk = disks.list().iter().find(|d| d.mount_point() == Path::new("/"));
        let root_device = root_disk.map(|d| d.name().to_os_string());

        for disk in disks.list() {
            let mount = disk.mount_point();
            if mount == Path::new("/") || seen_paths.contains(mount) {
                continue;
            }

            // Exclude subvolume mounts belonging to the same underlying system filesystem as root
            // (e.g. Btrfs subvolumes for /home, /var/log, /var/cache/pacman/pkg, ZFS root datasets)
            if let Some(ref root_dev) = root_device {
                if !root_dev.is_empty() && disk.name() == root_dev {
                    continue;
                }
            }

            // Exclude virtual / pseudo filesystems
            let fs = disk.file_system().to_string_lossy().to_lowercase();
            let is_virtual_fs = matches!(
                fs.as_str(),
                "tmpfs"
                    | "devtmpfs"
                    | "sysfs"
                    | "proc"
                    | "cgroup"
                    | "cgroup2"
                    | "pstore"
                    | "bpf"
                    | "tracefs"
                    | "debugfs"
                    | "configfs"
                    | "fusectl"
                    | "efivarfs"
                    | "autofs"
                    | "hugetlbfs"
                    | "mqueue"
                    | "ramfs"
                    | "squashfs"
                    | "overlay"
                    | "fuse.portal"
                    | "fuse.gvfsd-fuse"
            );
            if is_virtual_fs {
                continue;
            }

            let mount_str = mount.to_string_lossy();
            if mount_str.starts_with("/boot")
                || mount_str.starts_with("/efi")
                || mount_str.starts_with("/dev")
                || mount_str.starts_with("/proc")
                || mount_str.starts_with("/sys")
                || mount_str.starts_with("/etc")
                || mount_str.starts_with("/var/lib/docker")
                || mount_str.starts_with("/var/lib/containers")
                || mount_str.starts_with("/snap")
                || (mount_str.starts_with("/run") && !mount_str.starts_with("/run/media"))
            {
                continue;
            }

            let name = mount
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| mount_str.to_string());

            let label = if disk.is_removable() {
                "External Drive".to_string()
            } else if mount_str.starts_with("/run/media") || mount_str.starts_with("/media") {
                "Mounted Drive".to_string()
            } else {
                "Mounted Volume".to_string()
            };

            seen_paths.insert(mount.to_path_buf());
            roots.push(DiscoveredRoot {
                name,
                path: mount.to_path_buf(),
                label: Some(label),
                kind: if disk.is_removable() {
                    "removable".to_string()
                } else {
                    "volume".to_string()
                },
                is_removable: disk.is_removable(),
            });
        }

        // 3. Fallback discovery for standard mount parents: /mnt, /media, /run/media
        // Only accept actual filesystem mount points (where st_dev != parent.st_dev)
        let mount_parents = vec![
            PathBuf::from("/mnt"),
            PathBuf::from("/media"),
            PathBuf::from("/run/media"),
        ];
        for parent in mount_parents {
            if parent.exists() && parent.is_dir() {
                if let Ok(entries) = std::fs::read_dir(&parent) {
                    for entry in entries.flatten() {
                        let path = entry.path();
                        if !path.is_dir() {
                            continue;
                        }

                        if is_mount_point(&path) && !seen_paths.contains(&path) {
                            let name = entry.file_name().to_string_lossy().to_string();
                            seen_paths.insert(path.clone());
                            roots.push(DiscoveredRoot {
                                name,
                                path,
                                label: Some("Mounted Volume".to_string()),
                                kind: "mount".to_string(),
                                is_removable: false,
                            });
                        } else if parent == Path::new("/media") || parent == Path::new("/run/media") {
                            // Handle /run/media/$USER or /media/$USER sub-mounts
                            if let Ok(sub_entries) = std::fs::read_dir(&path) {
                                for sub in sub_entries.flatten() {
                                    let sub_path = sub.path();
                                    if sub_path.is_dir()
                                        && is_mount_point(&sub_path)
                                        && !seen_paths.contains(&sub_path)
                                    {
                                        let name = sub.file_name().to_string_lossy().to_string();
                                        seen_paths.insert(sub_path.clone());
                                        roots.push(DiscoveredRoot {
                                            name,
                                            path: sub_path,
                                            label: Some("Mounted Drive".to_string()),
                                            kind: "mount".to_string(),
                                            is_removable: true,
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    #[cfg(target_os = "macos")]
    {
        // 1. Macintosh HD Root
        roots.push(DiscoveredRoot {
            name: "Macintosh HD".to_string(),
            path: PathBuf::from("/"),
            label: Some("System Drive".to_string()),
            kind: "drive".to_string(),
            is_removable: false,
        });

        let mut seen_paths = HashSet::new();
        seen_paths.insert(PathBuf::from("/"));

        // 2. /Volumes directory
        let volumes = Path::new("/Volumes");
        if volumes.exists() && volumes.is_dir() {
            if let Ok(entries) = std::fs::read_dir(volumes) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    let file_name = entry.file_name().to_string_lossy().to_string();
                    if !file_name.starts_with('.') && path.is_dir() && !seen_paths.contains(&path) {
                        if let Ok(target) = std::fs::read_link(&path) {
                            if target == Path::new("/") {
                                continue;
                            }
                        }
                        seen_paths.insert(path.clone());
                        roots.push(DiscoveredRoot {
                            name: file_name.clone(),
                            path,
                            label: Some("Mounted Volume".to_string()),
                            kind: "volume".to_string(),
                            is_removable: false,
                        });
                    }
                }
            }
        }

        // 3. Sysinfo disks
        let disks = sysinfo::Disks::new_with_refreshed_list();
        for disk in disks.list() {
            let mount = disk.mount_point();
            if !seen_paths.contains(mount) {
                let name = disk.name().to_string_lossy().to_string();
                seen_paths.insert(mount.to_path_buf());
                roots.push(DiscoveredRoot {
                    name: if name.is_empty() {
                        mount.to_string_lossy().to_string()
                    } else {
                        name
                    },
                    path: mount.to_path_buf(),
                    label: Some(if disk.is_removable() {
                        "External Drive".to_string()
                    } else {
                        "Mounted Volume".to_string()
                    }),
                    kind: if disk.is_removable() {
                        "removable".to_string()
                    } else {
                        "volume".to_string()
                    },
                    is_removable: disk.is_removable(),
                });
            }
        }
    }

    // Quick Access Roots
    // Home directory
    if let Ok(home) = env::var("HOME").or_else(|_| env::var("USERPROFILE")) {
        let home_path = PathBuf::from(&home);
        if home_path.exists() {
            roots.push(DiscoveredRoot {
                name: "Home".to_string(),
                path: home_path,
                label: Some("User Home".to_string()),
                kind: "home".to_string(),
                is_removable: false,
            });
        }
    }

    // Current working directory (Workspace)
    if let Ok(cwd) = env::current_dir() {
        let ws = if cwd.file_name().map(|s| s == "src-tauri").unwrap_or(false) {
            cwd.parent().map(|p| p.to_path_buf()).unwrap_or(cwd.clone())
        } else {
            cwd.clone()
        };
        if !roots.iter().any(|r| r.path == ws) {
            roots.push(DiscoveredRoot {
                name: "Workspace".to_string(),
                path: ws,
                label: Some("Project Root".to_string()),
                kind: "workspace".to_string(),
                is_removable: false,
            });
        }
    }

    // Fallback if roots is empty
    if roots.is_empty() {
        #[cfg(windows)]
        {
            roots.push(DiscoveredRoot {
                name: "C:\\".to_string(),
                path: PathBuf::from("C:\\"),
                label: Some("System Drive".to_string()),
                kind: "drive".to_string(),
                is_removable: false,
            });
        }
        #[cfg(not(windows))]
        {
            roots.push(DiscoveredRoot {
                name: "System Root".to_string(),
                path: PathBuf::from("/"),
                label: Some("System Drive".to_string()),
                kind: "drive".to_string(),
                is_removable: false,
            });
        }
    }

    roots
}

/// Returns default user-accessible browse roots.
pub fn default_browse_roots() -> Vec<(String, PathBuf)> {
    discover_system_roots()
        .into_iter()
        .map(|r| (r.name, r.path))
        .collect()
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

/// Strips Windows verbatim prefix (`\\?\` or `\\?\UNC\`) if present.
pub fn strip_verbatim_prefix(path: &Path) -> PathBuf {
    let s = path.to_string_lossy();
    if let Some(stripped) = s.strip_prefix(r"\\?\UNC\") {
        PathBuf::from(format!(r"\\{}", stripped))
    } else if let Some(stripped) = s.strip_prefix(r"\\?\") {
        PathBuf::from(stripped)
    } else {
        path.to_path_buf()
    }
}

/// Checks if a target path matches or is within an allowed scope path.
pub fn check_scope_match(target: &Path, scope: &Path) -> bool {
    #[cfg(windows)]
    {
        let target_comps: Vec<_> = target.components().collect();
        let scope_comps: Vec<_> = scope.components().collect();
        if scope_comps.len() > target_comps.len() {
            return false;
        }
        for (t, s) in target_comps.iter().zip(scope_comps.iter()) {
            let t_str = t.as_os_str().to_string_lossy().to_lowercase();
            let s_str = s.as_os_str().to_string_lossy().to_lowercase();
            if t_str != s_str {
                return false;
            }
        }
        true
    }

    #[cfg(not(windows))]
    {
        target.starts_with(scope)
    }
}

/// Checks if a normalized path is inside any of the allowed scope directories.
/// If scopes is empty, all valid paths are permitted.
pub fn is_within_scopes(path: &Path, scopes: &[PathBuf]) -> bool {
    if scopes.is_empty() {
        return true;
    }

    let target_canonical = path.canonicalize().ok().map(|p| strip_verbatim_prefix(&p));
    let target_raw = strip_verbatim_prefix(path);

    scopes.iter().any(|scope| {
        let scope_canonical = scope.canonicalize().ok().map(|p| strip_verbatim_prefix(&p));
        let scope_raw = strip_verbatim_prefix(scope);

        if let (Some(t_can), Some(s_can)) = (&target_canonical, &scope_canonical) {
            if check_scope_match(t_can, s_can) {
                return true;
            }
        }

        if check_scope_match(&target_raw, &scope_raw) {
            return true;
        }

        if let Some(t_can) = &target_canonical {
            if check_scope_match(t_can, &scope_raw) {
                return true;
            }
        }

        if let Some(s_can) = &scope_canonical {
            if check_scope_match(&target_raw, s_can) {
                return true;
            }
        }

        false
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

    #[test]
    fn test_discover_system_roots() {
        let roots = discover_system_roots();
        assert!(!roots.is_empty());
        // Verify every root has non-empty name and path
        for r in &roots {
            assert!(!r.name.is_empty());
            assert!(!r.path.to_string_lossy().is_empty());
            assert!(!r.kind.is_empty());
        }

        #[cfg(target_os = "linux")]
        {
            // Verify System Root exists
            assert!(roots.iter().any(|r| r.path == PathBuf::from("/")));
            // Verify /home is not present as a separate drive root when it shares root device
            let has_subvol_home = roots
                .iter()
                .any(|r| r.path == PathBuf::from("/home") && r.kind == "volume");
            assert!(!has_subvol_home);
        }
    }

    #[test]
    fn test_strip_verbatim_prefix() {
        let p1 = Path::new(r"\\?\C:\Projects\Orbit");
        assert_eq!(
            strip_verbatim_prefix(p1),
            PathBuf::from(r"C:\Projects\Orbit")
        );

        let p2 = Path::new(r"\\?\UNC\server\share\file.txt");
        assert_eq!(
            strip_verbatim_prefix(p2),
            PathBuf::from(r"\\server\share\file.txt")
        );

        let p3 = Path::new("/usr/bin/bash");
        assert_eq!(strip_verbatim_prefix(p3), PathBuf::from("/usr/bin/bash"));
    }

    #[test]
    fn test_is_within_scopes_basic() {
        let scopes = vec![PathBuf::from("/home/user/project")];
        assert!(is_within_scopes(
            Path::new("/home/user/project/src"),
            &scopes
        ));
        assert!(!is_within_scopes(Path::new("/etc/passwd"), &scopes));
    }

    #[test]
    fn test_is_within_scopes_empty_allows_all() {
        let scopes: Vec<PathBuf> = Vec::new();
        assert!(is_within_scopes(Path::new("/any/path"), &scopes));
    }
}
