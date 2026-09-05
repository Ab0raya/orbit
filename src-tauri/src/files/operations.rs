use serde::{Deserialize, Serialize};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::Path;
use std::time::UNIX_EPOCH;

use super::path::is_hidden;

pub const DEFAULT_MAX_READ_BYTES: u64 = 5 * 1024 * 1024; // 5 MB

#[derive(Debug, thiserror::Error)]
pub enum FileError {
    #[error("Path not found: {0}")]
    NotFound(String),
    #[error("Permission denied: {0}")]
    PermissionDenied(String),
    #[error("Invalid path: {0}")]
    InvalidPath(String),
    #[error("File exceeds maximum allowed size ({0} bytes)")]
    FileTooLarge(u64),
    #[error("Unsupported file type: only valid UTF-8 text files are supported")]
    UnsupportedFileType,
    #[error("Path already exists: {0}")]
    AlreadyExists(String),
    #[error("Directory not empty: {0}")]
    DirectoryNotEmpty(String),
    #[error("Operation failed: {0}")]
    Io(String),
}

impl From<std::io::Error> for FileError {
    fn from(err: std::io::Error) -> Self {
        match err.kind() {
            std::io::ErrorKind::NotFound => FileError::NotFound(err.to_string()),
            std::io::ErrorKind::PermissionDenied => FileError::PermissionDenied(err.to_string()),
            std::io::ErrorKind::AlreadyExists => FileError::AlreadyExists(err.to_string()),
            _ => FileError::Io(err.to_string()),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum FileCategory {
    Text,
    Code,
    Image,
    Binary,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BinaryReadResult {
    pub path: String,
    pub name: String,
    pub extension: String,
    pub size: u64,
    pub mime_type: String,
    pub file_category: FileCategory,
    pub encoding: String,
    pub content: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub modified_at: Option<u64>,
    pub is_too_large: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub kind: String, // "file" | "directory"
    pub size: u64,
    pub modified_at: Option<u64>,
    pub hidden: bool,
}

/// Lists entries in a directory. Directories are returned first, then files alphabetically.
pub fn list_directory(path: &Path) -> Result<Vec<FileEntry>, FileError> {
    if !path.exists() {
        return Err(FileError::NotFound(path.to_string_lossy().to_string()));
    }
    if !path.is_dir() {
        return Err(FileError::InvalidPath(format!(
            "Path '{}' is not a directory",
            path.display()
        )));
    }

    let read_dir = fs::read_dir(path).map_err(|e| match e.kind() {
        std::io::ErrorKind::PermissionDenied => {
            FileError::PermissionDenied(path.to_string_lossy().to_string())
        }
        _ => FileError::from(e),
    })?;

    let mut entries = Vec::new();

    for entry_res in read_dir {
        let entry = match entry_res {
            Ok(e) => e,
            Err(_) => continue, // Skip inaccessible entry
        };

        let entry_path = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        let metadata = entry.metadata().ok();

        let (kind, size) = if let Some(meta) = &metadata {
            if meta.is_dir() {
                ("directory".to_string(), 0)
            } else {
                ("file".to_string(), meta.len())
            }
        } else {
            ("file".to_string(), 0)
        };

        let modified_at = metadata.and_then(|m| {
            m.modified()
                .ok()
                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                .map(|d| d.as_secs())
        });

        let hidden = is_hidden(&entry_path);

        entries.push(FileEntry {
            name,
            path: entry_path.to_string_lossy().to_string(),
            kind,
            size,
            modified_at,
            hidden,
        });
    }

    // Sort: directories first, then files alphabetically (case-insensitive)
    entries.sort_by(|a, b| match (a.kind.as_str(), b.kind.as_str()) {
        ("directory", "file") => std::cmp::Ordering::Less,
        ("file", "directory") => std::cmp::Ordering::Greater,
        _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
    });

    Ok(entries)
}

/// Reads a text file up to max_bytes. Verifies UTF-8 encoding.
pub fn read_text_file(path: &Path, max_bytes: u64) -> Result<(String, u64), FileError> {
    if !path.exists() {
        return Err(FileError::NotFound(path.to_string_lossy().to_string()));
    }
    if path.is_dir() {
        return Err(FileError::InvalidPath(format!(
            "Path '{}' is a directory, not a file",
            path.display()
        )));
    }

    let metadata = fs::metadata(path).map_err(|e| match e.kind() {
        std::io::ErrorKind::PermissionDenied => {
            FileError::PermissionDenied(path.to_string_lossy().to_string())
        }
        _ => FileError::from(e),
    })?;

    let file_size = metadata.len();
    if file_size > max_bytes {
        return Err(FileError::FileTooLarge(file_size));
    }

    let mut file = File::open(path).map_err(|e| match e.kind() {
        std::io::ErrorKind::PermissionDenied => {
            FileError::PermissionDenied(path.to_string_lossy().to_string())
        }
        _ => FileError::from(e),
    })?;

    let mut buffer = Vec::with_capacity(file_size as usize);
    file.read_to_end(&mut buffer)?;

    // Check for UTF-8 validity
    let content = String::from_utf8(buffer).map_err(|_| FileError::UnsupportedFileType)?;

    Ok((content, file_size))
}

/// Writes content to a file atomically via a temporary file in the same directory.
pub fn write_text_file_atomic(path: &Path, content: &str) -> Result<u64, FileError> {
    let parent = path.parent().ok_or_else(|| {
        FileError::InvalidPath("Cannot write to root or invalid path".to_string())
    })?;

    if !parent.exists() {
        return Err(FileError::NotFound(parent.to_string_lossy().to_string()));
    }

    let filename = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unnamed");

    let tmp_filename = format!(".orbit_tmp_{}_{}", std::process::id(), filename);
    let tmp_path = parent.join(tmp_filename);

    // Write to temp file
    {
        let mut tmp_file = File::create(&tmp_path).map_err(|e| match e.kind() {
            std::io::ErrorKind::PermissionDenied => {
                FileError::PermissionDenied(path.to_string_lossy().to_string())
            }
            _ => FileError::from(e),
        })?;

        tmp_file.write_all(content.as_bytes())?;
        tmp_file.flush()?;
    }

    // Atomically rename over target file
    if let Err(e) = fs::rename(&tmp_path, path) {
        let _ = fs::remove_file(&tmp_path);
        return Err(match e.kind() {
            std::io::ErrorKind::PermissionDenied => {
                FileError::PermissionDenied(path.to_string_lossy().to_string())
            }
            _ => FileError::from(e),
        });
    }

    Ok(content.len() as u64)
}

/// Creates a new directory.
pub fn create_dir(path: &Path) -> Result<(), FileError> {
    if path.exists() {
        return Err(FileError::AlreadyExists(
            path.to_string_lossy().to_string(),
        ));
    }
    fs::create_dir_all(path).map_err(|e| match e.kind() {
        std::io::ErrorKind::PermissionDenied => {
            FileError::PermissionDenied(path.to_string_lossy().to_string())
        }
        _ => FileError::from(e),
    })
}

/// Renames a file or directory.
pub fn rename_path(from: &Path, to: &Path) -> Result<(), FileError> {
    if !from.exists() {
        return Err(FileError::NotFound(from.to_string_lossy().to_string()));
    }
    if to.exists() {
        return Err(FileError::AlreadyExists(to.to_string_lossy().to_string()));
    }

    fs::rename(from, to).map_err(|e| match e.kind() {
        std::io::ErrorKind::PermissionDenied => {
            FileError::PermissionDenied(from.to_string_lossy().to_string())
        }
        _ => FileError::from(e),
    })
}

/// Deletes a file or directory.
pub fn delete_path(path: &Path) -> Result<(), FileError> {
    if !path.exists() {
        return Err(FileError::NotFound(path.to_string_lossy().to_string()));
    }

    if path.is_dir() {
        fs::remove_dir_all(path).map_err(|e| match e.kind() {
            std::io::ErrorKind::PermissionDenied => {
                FileError::PermissionDenied(path.to_string_lossy().to_string())
            }
            _ => FileError::from(e),
        })
    } else {
        fs::remove_file(path).map_err(|e| match e.kind() {
            std::io::ErrorKind::PermissionDenied => {
                FileError::PermissionDenied(path.to_string_lossy().to_string())
            }
            _ => FileError::from(e),
        })
    }
}

/// Detects the high-level category of a file based on its extension or filename.
pub fn detect_file_category(path: &Path) -> FileCategory {
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
    let filename = path.file_name().and_then(|f| f.to_str()).unwrap_or("").to_lowercase();

    if filename.starts_with(".env") || filename == "dockerfile" || filename == ".gitignore" {
        return FileCategory::Text;
    }

    match ext.as_str() {
        "png" | "jpg" | "jpeg" | "gif" | "webp" | "bmp" | "svg" => FileCategory::Image,
        "dart" | "ts" | "tsx" | "js" | "jsx" | "rs" | "py" | "java" | "kotlin" | "kt"
        | "swift" | "c" | "cpp" | "h" | "hpp" | "go" | "php" | "rb" | "sh" | "bash"
        | "zsh" | "css" | "scss" | "html" | "htm" | "vue" | "svelte" | "sql" | "toml" => {
            FileCategory::Code
        }
        "txt" | "md" | "markdown" | "log" | "yaml" | "yml" | "json" | "xml" | "csv"
        | "env" | "ini" | "conf" => FileCategory::Text,
        _ => FileCategory::Binary,
    }
}

/// Detects the MIME type of a file.
pub fn detect_mime_type(path: &Path) -> String {
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
    match ext.as_str() {
        "png" => "image/png".to_string(),
        "jpg" | "jpeg" => "image/jpeg".to_string(),
        "gif" => "image/gif".to_string(),
        "webp" => "image/webp".to_string(),
        "bmp" => "image/bmp".to_string(),
        "svg" => "image/svg+xml".to_string(),
        "dart" => "text/x-dart".to_string(),
        "rs" => "text/x-rust".to_string(),
        "ts" => "application/typescript".to_string(),
        "tsx" => "application/typescript-jsx".to_string(),
        "js" => "application/javascript".to_string(),
        "jsx" => "application/javascript-jsx".to_string(),
        "py" => "text/x-python".to_string(),
        "go" => "text/x-go".to_string(),
        "java" => "text/x-java".to_string(),
        "kt" | "kotlin" => "text/x-kotlin".to_string(),
        "swift" => "text/x-swift".to_string(),
        "c" | "h" => "text/x-c".to_string(),
        "cpp" | "hpp" => "text/x-c++".to_string(),
        "php" => "text/x-php".to_string(),
        "rb" => "text/x-ruby".to_string(),
        "sh" | "bash" | "zsh" => "text/x-sh".to_string(),
        "html" | "htm" => "text/html".to_string(),
        "css" => "text/css".to_string(),
        "scss" => "text/x-scss".to_string(),
        "vue" => "text/x-vue".to_string(),
        "svelte" => "text/x-svelte".to_string(),
        "txt" | "log" | "env" => "text/plain".to_string(),
        "md" | "markdown" => "text/markdown".to_string(),
        "json" => "application/json".to_string(),
        "yaml" | "yml" => "text/yaml".to_string(),
        "xml" => "text/xml".to_string(),
        "csv" => "text/csv".to_string(),
        _ => "application/octet-stream".to_string(),
    }
}

/// Extracts image dimensions (width, height) without external heavy libraries.
/// Supports PNG, GIF, BMP, JPEG, and WebP headers.
pub fn extract_image_dimensions(path: &Path) -> Option<(u32, u32)> {
    let mut file = File::open(path).ok()?;
    let mut buffer = [0u8; 4096];
    let n = file.read(&mut buffer).ok()?;
    let data = &buffer[..n];

    // PNG: \x89PNG\r\n\x1a\n then IHDR chunk
    if data.len() >= 24 && &data[0..8] == b"\x89PNG\r\n\x1a\n" && &data[12..16] == b"IHDR" {
        let width = u32::from_be_bytes(data[16..20].try_into().ok()?);
        let height = u32::from_be_bytes(data[20..24].try_into().ok()?);
        return Some((width, height));
    }

    // GIF: GIF87a or GIF89a
    if data.len() >= 10 && (&data[0..6] == b"GIF87a" || &data[0..6] == b"GIF89a") {
        let width = u16::from_le_bytes(data[6..8].try_into().ok()?) as u32;
        let height = u16::from_le_bytes(data[8..10].try_into().ok()?) as u32;
        return Some((width, height));
    }

    // BMP: "BM"
    if data.len() >= 26 && &data[0..2] == b"BM" {
        let width = i32::from_le_bytes(data[18..22].try_into().ok()?).unsigned_abs();
        let height = i32::from_le_bytes(data[22..26].try_into().ok()?).unsigned_abs();
        return Some((width, height));
    }

    // JPEG: 0xFF, 0xD8
    if data.len() >= 4 && data[0] == 0xFF && data[1] == 0xD8 {
        let mut i = 2;
        while i + 9 < data.len() {
            if data[i] != 0xFF {
                i += 1;
                continue;
            }
            let marker = data[i + 1];
            // SOF markers: 0xC0..=0xC3, 0xC5..=0xC7, 0xC9..=0xCB, 0xCD..=0xCF
            let is_sof = (0xC0..=0xC3).contains(&marker)
                || (0xC5..=0xC7).contains(&marker)
                || (0xC9..=0xCB).contains(&marker)
                || (0xCD..=0xCF).contains(&marker);
            if is_sof {
                let h = u16::from_be_bytes([data[i + 5], data[i + 6]]) as u32;
                let w = u16::from_be_bytes([data[i + 7], data[i + 8]]) as u32;
                return Some((w, h));
            }
            // Skip marker segment
            if i + 3 < data.len() {
                let len = u16::from_be_bytes([data[i + 2], data[i + 3]]) as usize;
                if len == 0 {
                    break;
                }
                i += 2 + len;
            } else {
                break;
            }
        }
    }

    // WebP: RIFF .... WEBP
    if data.len() >= 30 && &data[0..4] == b"RIFF" && &data[8..12] == b"WEBP" {
        if &data[12..16] == b"VP8 " && data.len() >= 30 {
            let width = (u16::from_le_bytes([data[26], data[27]]) & 0x3FFF) as u32;
            let height = (u16::from_le_bytes([data[28], data[29]]) & 0x3FFF) as u32;
            return Some((width, height));
        } else if &data[12..16] == b"VP8L" && data.len() >= 25 {
            let b0 = data[21] as u32;
            let b1 = data[22] as u32;
            let b2 = data[23] as u32;
            let b3 = data[24] as u32;
            let width = 1 + (b0 | ((b1 & 0x3F) << 8));
            let height = 1 + ((b1 >> 6) | (b2 << 2) | ((b3 & 0xF) << 10));
            return Some((width, height));
        } else if &data[12..16] == b"VP8X" && data.len() >= 30 {
            let width = 1 + (data[24] as u32 | ((data[25] as u32) << 8) | ((data[26] as u32) << 16));
            let height = 1 + (data[27] as u32 | ((data[28] as u32) << 8) | ((data[29] as u32) << 16));
            return Some((width, height));
        }
    }

    None
}

/// Reads a binary or image file up to max_bytes and returns base64 encoded payload and metadata.
/// If the file exceeds max_bytes, it returns metadata with is_too_large: true and content: None.
pub fn read_binary_file(path: &Path, max_bytes: u64) -> Result<BinaryReadResult, FileError> {
    if !path.exists() {
        return Err(FileError::NotFound(path.to_string_lossy().to_string()));
    }
    if path.is_dir() {
        return Err(FileError::InvalidPath(format!(
            "Path '{}' is a directory, not a file",
            path.display()
        )));
    }

    let metadata = fs::metadata(path).map_err(|e| match e.kind() {
        std::io::ErrorKind::PermissionDenied => {
            FileError::PermissionDenied(path.to_string_lossy().to_string())
        }
        _ => FileError::from(e),
    })?;

    let file_size = metadata.len();
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("").to_string();
    let extension = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
    let file_category = detect_file_category(path);
    let mime_type = detect_mime_type(path);
    let dimensions = if file_category == FileCategory::Image {
        extract_image_dimensions(path)
    } else {
        None
    };
    let (width, height) = match dimensions {
        Some((w, h)) => (Some(w), Some(h)),
        None => (None, None),
    };

    let modified_at = metadata.modified().ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs());

    if file_size > max_bytes {
        return Ok(BinaryReadResult {
            path: path.to_string_lossy().to_string(),
            name,
            extension,
            size: file_size,
            mime_type,
            file_category,
            encoding: "base64".to_string(),
            content: None,
            width,
            height,
            modified_at,
            is_too_large: true,
        });
    }

    let mut file = File::open(path).map_err(|e| match e.kind() {
        std::io::ErrorKind::PermissionDenied => {
            FileError::PermissionDenied(path.to_string_lossy().to_string())
        }
        _ => FileError::from(e),
    })?;

    let mut buffer = Vec::with_capacity(file_size as usize);
    file.read_to_end(&mut buffer)?;

    use base64::Engine;
    let encoded = base64::prelude::BASE64_STANDARD.encode(&buffer);

    Ok(BinaryReadResult {
        path: path.to_string_lossy().to_string(),
        name,
        extension,
        size: file_size,
        mime_type,
        file_category,
        encoding: "base64".to_string(),
        content: Some(encoded),
        width,
        height,
        modified_at,
        is_too_large: false,
    })
}

pub const MAX_SEARCH_RESULTS: usize = 200;
pub const MAX_SEARCH_CONTENT_FILE_BYTES: u64 = 2 * 1024 * 1024; // 2 MB
pub const MAX_SEARCH_DEPTH: usize = 25;

pub const IGNORED_SEARCH_DIRS: &[&str] = &[
    ".git",
    "node_modules",
    "build",
    "dist",
    "target",
    ".dart_tool",
    ".gradle",
    ".cache",
    ".idea",
    ".vscode",
    ".cargo",
];

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SearchFileResult {
    pub path: String,
    pub name: String,
    pub relative_path: String,
    pub is_directory: bool,
    pub line_number: Option<usize>,
    pub line_content: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct FileSearchResult {
    pub root: String,
    pub query: String,
    pub mode: String,
    pub total_matches: usize,
    pub truncated: bool,
    pub results: Vec<SearchFileResult>,
}

pub fn search_files(
    root: &Path,
    query: &str,
    mode: &str,
    max_results: usize,
) -> Result<FileSearchResult, FileError> {
    if !root.exists() {
        return Err(FileError::NotFound(root.to_string_lossy().to_string()));
    }
    if !root.is_dir() {
        return Err(FileError::InvalidPath(format!(
            "Root '{}' is not a directory",
            root.display()
        )));
    }

    let query_trimmed = query.trim();
    if query_trimmed.is_empty() {
        return Ok(FileSearchResult {
            root: root.to_string_lossy().to_string(),
            query: query.to_string(),
            mode: mode.to_string(),
            total_matches: 0,
            truncated: false,
            results: Vec::new(),
        });
    }

    let query_lower = query_trimmed.to_lowercase();
    let is_content_mode = mode.eq_ignore_ascii_case("content");
    let limit = max_results.clamp(1, MAX_SEARCH_RESULTS);

    let mut results = Vec::new();
    let mut truncated = false;

    let mut stack = vec![(root.to_path_buf(), 0usize)];

    while let Some((dir_path, depth)) = stack.pop() {
        if depth > MAX_SEARCH_DEPTH {
            continue;
        }

        let read_dir = match fs::read_dir(&dir_path) {
            Ok(rd) => rd,
            Err(_) => continue,
        };

        let mut subdirs = Vec::new();

        for entry_res in read_dir {
            let entry = match entry_res {
                Ok(e) => e,
                Err(_) => continue,
            };

            let entry_path = entry.path();
            let file_name_os = entry.file_name();
            let file_name = file_name_os.to_string_lossy();

            if entry_path.is_dir() && IGNORED_SEARCH_DIRS.iter().any(|d| *d == file_name) {
                continue;
            }

            let rel_path = match entry_path.strip_prefix(root) {
                Ok(p) => p.to_string_lossy().to_string(),
                Err(_) => file_name.to_string(),
            };

            if entry_path.is_dir() {
                if !is_content_mode && file_name.to_lowercase().contains(&query_lower) {
                    results.push(SearchFileResult {
                        path: entry_path.to_string_lossy().to_string(),
                        name: file_name.to_string(),
                        relative_path: rel_path.clone(),
                        is_directory: true,
                        line_number: None,
                        line_content: None,
                    });
                    if results.len() >= limit {
                        truncated = true;
                        break;
                    }
                }
                subdirs.push((entry_path, depth + 1));
            } else if entry_path.is_file() {
                if !is_content_mode {
                    if file_name.to_lowercase().contains(&query_lower)
                        || rel_path.to_lowercase().contains(&query_lower)
                    {
                        results.push(SearchFileResult {
                            path: entry_path.to_string_lossy().to_string(),
                            name: file_name.to_string(),
                            relative_path: rel_path,
                            is_directory: false,
                            line_number: None,
                            line_content: None,
                        });
                        if results.len() >= limit {
                            truncated = true;
                            break;
                        }
                    }
                } else {
                    let metadata = match entry.metadata() {
                        Ok(m) => m,
                        Err(_) => continue,
                    };

                    if metadata.len() > MAX_SEARCH_CONTENT_FILE_BYTES {
                        continue;
                    }

                    let mut sample = [0u8; 1024];
                    let is_binary = match File::open(&entry_path) {
                        Ok(mut f) => {
                            let n = f.read(&mut sample).unwrap_or(0);
                            sample[..n].contains(&0)
                        }
                        Err(_) => continue,
                    };

                    if is_binary {
                        continue;
                    }

                    if let Ok(file) = File::open(&entry_path) {
                        use std::io::BufRead;
                        let reader = std::io::BufReader::new(file);
                        for (idx, line_res) in reader.lines().enumerate() {
                            if let Ok(line) = line_res {
                                if line.to_lowercase().contains(&query_lower) {
                                    let preview = line.trim().chars().take(200).collect::<String>();
                                    results.push(SearchFileResult {
                                        path: entry_path.to_string_lossy().to_string(),
                                        name: file_name.to_string(),
                                        relative_path: rel_path.clone(),
                                        is_directory: false,
                                        line_number: Some(idx + 1),
                                        line_content: Some(preview),
                                    });

                                    if results.len() >= limit {
                                        truncated = true;
                                        break;
                                    }
                                }
                            }
                        }
                    }
                    if results.len() >= limit {
                        truncated = true;
                        break;
                    }
                }
            }
        }

        if truncated {
            break;
        }

        for sub in subdirs {
            stack.push(sub);
        }
    }

    let total = results.len();
    Ok(FileSearchResult {
        root: root.to_string_lossy().to_string(),
        query: query.to_string(),
        mode: mode.to_string(),
        total_matches: total,
        truncated,
        results,
    })
}
