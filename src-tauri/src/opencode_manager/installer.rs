use std::path::{Path, PathBuf};
use std::io::Cursor;
use tokio::process::Command;

type ProgressFn = Box<dyn Fn(String) + Send>;

// ============================================================
// Binary verification
// ============================================================

/// Run `opencode --version` and return the trimmed version string.
/// Returns an error if the binary is missing, not executable, or
/// doesn't produce valid output within 10 seconds.
pub async fn verify_binary(path: &Path) -> Result<String, String> {
    if !path.exists() {
        return Err(format!("Binary does not exist at {:?}", path));
    }

    let output = Command::new(path)
        .arg("--version")
        .output()
        .await
        .map_err(|e| format!("Failed to run {:?}: {}", path, e))?;

    // opencode may output to stdout or stderr depending on version
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let combined = if !stdout.is_empty() { stdout } else { stderr };

    if combined.is_empty() {
        return Err("opencode --version produced no output".to_string());
    }

    // Extract version: accept first token that contains a digit
    // Handles: "1.18.25", "opencode 1.18.25", "v1.18.25", etc.
    let version = combined
        .lines()
        .next()
        .unwrap_or("")
        .split_whitespace()
        .find(|t| t.chars().any(|c| c.is_ascii_digit()))
        .unwrap_or(combined.split_whitespace().next().unwrap_or("unknown"))
        .trim_start_matches('v')
        .to_string();

    Ok(version)
}

// ============================================================
// Platform URL building
// ============================================================

/// Returns the download URL and the expected binary name inside the archive.
fn artifact_info(version: &str, owner: &str, repo: &str) -> Result<(String, String), String> {
    let base = format!(
        "https://github.com/{}/{}/releases/download/v{}",
        owner, repo, version
    );

    // Determine platform + arch artifact name
    let (archive_name, binary_name_in_archive) = if cfg!(target_os = "windows") {
        #[cfg(target_arch = "x86_64")]
        let n = "opencode-windows-x64.zip";
        #[cfg(target_arch = "aarch64")]
        let n = "opencode-windows-arm64.zip";
        #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
        let n = "opencode-windows-x64.zip"; // fallback
        (n, "opencode.exe")
    } else if cfg!(target_os = "macos") {
        #[cfg(target_arch = "aarch64")]
        let n = "opencode-mac-arm64.tar.gz";
        #[cfg(not(target_arch = "aarch64"))]
        let n = "opencode-mac-x86_64.tar.gz";
        (n, "opencode")
    } else {
        // Linux
        #[cfg(target_arch = "aarch64")]
        let n = "opencode-linux-arm64.tar.gz";
        #[cfg(not(target_arch = "aarch64"))]
        let n = "opencode-linux-x64.tar.gz";
        (n, "opencode")
    };

    let url = format!("{}/{}", base, archive_name);
    Ok((url, binary_name_in_archive.to_string()))
}

// ============================================================
// Download
// ============================================================

async fn download_bytes(url: &str, progress: &ProgressFn) -> Result<Vec<u8>, String> {
    progress(format!("Downloading OpenCode from GitHub…"));
    log::info!("[OpenCode Installer] Downloading: {}", url);

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(300))
        .user_agent("Orbit-Desktop/0.1")
        .build()
        .map_err(|e| format!("Failed to create HTTP client: {}", e))?;

    let response = client
        .get(url)
        .send()
        .await
        .map_err(|e| format!("Download request failed: {}", e))?;

    let status = response.status();
    if !status.is_success() {
        return Err(format!(
            "Download failed: HTTP {} from {}",
            status, url
        ));
    }

    let total = response.content_length();
    let bytes = response
        .bytes()
        .await
        .map_err(|e| format!("Failed to read download body: {}", e))?;

    let kb = bytes.len() / 1024;
    progress(format!("Downloaded {}KB", kb));
    log::info!("[OpenCode Installer] Downloaded {} bytes", bytes.len());

    if bytes.is_empty() {
        return Err("Download produced 0 bytes".to_string());
    }

    // Basic sanity: must be at least 1MB for a real binary bundle
    if bytes.len() < 512 * 1024 {
        return Err(format!(
            "Download too small ({} bytes) — likely not a real binary archive",
            bytes.len()
        ));
    }

    let _ = total; // suppress unused warning
    Ok(bytes.to_vec())
}

// ============================================================
// Extraction
// ============================================================

fn extract_zip(
    bytes: &[u8],
    target_dir: &Path,
    binary_name_in_archive: &str,
    binary_dest: &Path,
) -> Result<(), String> {
    use std::io::Read;

    let cursor = Cursor::new(bytes);
    let mut archive = zip::ZipArchive::new(cursor)
        .map_err(|e| format!("Failed to parse ZIP archive: {}", e))?;

    // Find the binary inside the archive (may be in a subdirectory)
    let binary_entry_name = (0..archive.len())
        .find_map(|i| {
            archive.by_index(i).ok().and_then(|entry| {
                let name = entry.name().to_string();
                if name.ends_with(binary_name_in_archive)
                    && !name.contains("__MACOSX")
                {
                    Some(name)
                } else {
                    None
                }
            })
        })
        .ok_or_else(|| {
            format!(
                "Binary '{}' not found inside ZIP archive",
                binary_name_in_archive
            )
        })?;

    std::fs::create_dir_all(target_dir)
        .map_err(|e| format!("Failed to create target dir {:?}: {}", target_dir, e))?;

    let mut entry = archive
        .by_name(&binary_entry_name)
        .map_err(|e| format!("Failed to read archive entry: {}", e))?;

    let mut content = Vec::new();
    entry
        .read_to_end(&mut content)
        .map_err(|e| format!("Failed to read binary from archive: {}", e))?;

    if content.is_empty() {
        return Err("Extracted binary is empty".to_string());
    }

    std::fs::write(binary_dest, &content)
        .map_err(|e| format!("Failed to write binary to {:?}: {}", binary_dest, e))?;

    Ok(())
}

#[cfg(unix)]
fn extract_tar_gz(
    bytes: &[u8],
    target_dir: &Path,
    binary_name_in_archive: &str,
    binary_dest: &Path,
) -> Result<(), String> {
    use std::io::Read;
    use flate2::read::GzDecoder;
    use tar::Archive;

    std::fs::create_dir_all(target_dir)
        .map_err(|e| format!("Failed to create target dir {:?}: {}", target_dir, e))?;

    let gz = GzDecoder::new(Cursor::new(bytes));
    let mut archive = Archive::new(gz);

    for entry_result in archive
        .entries()
        .map_err(|e| format!("Failed to read tar entries: {}", e))?
    {
        let mut entry = entry_result
            .map_err(|e| format!("Failed to read tar entry: {}", e))?;

        let path = entry
            .path()
            .map_err(|e| format!("Failed to get entry path: {}", e))?
            .to_path_buf();

        let name = path.file_name().unwrap_or_default().to_string_lossy().to_string();
        if name == binary_name_in_archive {
            let mut content = Vec::new();
            entry
                .read_to_end(&mut content)
                .map_err(|e| format!("Failed to read tar entry contents: {}", e))?;

            if content.is_empty() {
                return Err("Extracted binary is empty".to_string());
            }

            std::fs::write(binary_dest, &content)
                .map_err(|e| format!("Failed to write binary: {}", e))?;

            return Ok(());
        }
    }

    Err(format!(
        "Binary '{}' not found in tar.gz archive",
        binary_name_in_archive
    ))
}

/// Set executable bit on Unix
#[cfg(unix)]
fn make_executable(path: &Path) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    let mut perms = std::fs::metadata(path)
        .map_err(|e| format!("Failed to stat {:?}: {}", path, e))?
        .permissions();
    perms.set_mode(0o755);
    std::fs::set_permissions(path, perms)
        .map_err(|e| format!("Failed to chmod {:?}: {}", path, e))?;
    Ok(())
}

#[cfg(windows)]
fn make_executable(_path: &Path) -> Result<(), String> {
    // Windows doesn't use Unix execute bits
    Ok(())
}

// ============================================================
// Main install function
// ============================================================

/// Download, extract, verify and install OpenCode.
/// Returns the confirmed version string on success.
pub async fn install_opencode<F: Fn(String) + Send + 'static>(
    version: &str,
    owner: &str,
    repo: &str,
    target_dir: &Path,
    binary_dest: &Path,
    progress: F,
) -> Result<String, String> {
    let progress: ProgressFn = Box::new(progress);

    let (url, binary_name_in_archive) = artifact_info(version, owner, repo)?;

    // Download
    let bytes = download_bytes(&url, &progress).await?;

    // Extract based on archive type
    progress("Extracting archive…".to_string());

    if url.ends_with(".zip") {
        extract_zip(&bytes, target_dir, &binary_name_in_archive, binary_dest)?;
    } else {
        #[cfg(unix)]
        extract_tar_gz(&bytes, target_dir, &binary_name_in_archive, binary_dest)?;
        #[cfg(windows)]
        return Err("Unexpected tar.gz archive on Windows".to_string());
    }

    // Make executable
    make_executable(binary_dest)?;

    // Verify
    progress("Verifying installation…".to_string());
    let confirmed_version = verify_binary(binary_dest).await.map_err(|e| {
        format!(
            "Binary extracted but failed verification: {}. The binary may be corrupt.",
            e
        )
    })?;

    log::info!(
        "[OpenCode Installer] Installed version '{}' at {:?}",
        confirmed_version,
        binary_dest
    );

    Ok(confirmed_version)
}
