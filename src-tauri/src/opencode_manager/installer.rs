use std::io::Cursor;
use std::path::{Path, PathBuf};

type ProgressFn = Box<dyn Fn(String) + Send + Sync>;

// ============================================================
// Version parsing & binary verification
// ============================================================

/// Parse version from the output of `opencode --version`.
pub fn parse_version_output(combined: &str) -> Result<String, String> {
    let trimmed = combined.trim();
    if trimmed.is_empty() {
        return Err("Version output is empty".to_string());
    }

    let first_line = trimmed.lines().next().unwrap_or("");
    for token in first_line.split_whitespace() {
        let cleaned = token.trim_matches(|c: char| !c.is_ascii_digit() && c != '.');
        if !cleaned.is_empty()
            && cleaned.chars().any(|c| c.is_ascii_digit())
            && cleaned.contains('.')
        {
            return Ok(cleaned.to_string());
        }
    }

    for token in first_line.split_whitespace() {
        let t = token.trim_start_matches('v');
        if !t.is_empty() && t.chars().next().map_or(false, |c| c.is_ascii_digit()) {
            return Ok(t.to_string());
        }
    }

    Err(format!(
        "Could not parse version from output: '{}'",
        first_line
    ))
}

/// Run `opencode --version` directly on the binary path and return the verified version string.
/// Uses a 10-second timeout.
pub async fn verify_binary(path: &Path) -> Result<String, String> {
    if !path.exists() {
        return Err(format!("Binary does not exist at {:?}", path));
    }

    let cmd_future = crate::opencode_manager::new_tokio_command(path)
        .arg("--version")
        .output();

    let output = tokio::time::timeout(std::time::Duration::from_secs(10), cmd_future)
        .await
        .map_err(|_| format!("Timed out executing {:?} --version after 10s", path))?
        .map_err(|e| format!("Failed to execute {:?}: {}", path, e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!(
            "Binary exited with non-zero status code ({:?}): {}",
            output.status.code(),
            stderr.trim()
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let combined = if !stdout.is_empty() { stdout } else { stderr };

    parse_version_output(&combined)
}

// ============================================================
// Platform URL building
// ============================================================

/// Returns the HTTPS download URL and the expected binary name inside the archive.
pub fn artifact_info(version: &str, owner: &str, repo: &str) -> Result<(String, String), String> {
    let base = format!(
        "https://github.com/{}/{}/releases/download/v{}",
        owner, repo, version
    );

    let (archive_name, binary_name_in_archive) = if cfg!(target_os = "windows") {
        #[cfg(target_arch = "x86_64")]
        let n = "opencode-windows-x64.zip";
        #[cfg(target_arch = "aarch64")]
        let n = "opencode-windows-arm64.zip";
        #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
        let n = "opencode-windows-x64.zip";
        (n, "opencode.exe")
    } else if cfg!(target_os = "macos") {
        #[cfg(target_arch = "aarch64")]
        let n = "opencode-mac-arm64.tar.gz";
        #[cfg(not(target_arch = "aarch64"))]
        let n = "opencode-mac-x86_64.tar.gz";
        (n, "opencode")
    } else {
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

pub async fn download_bytes(url: &str, progress: &ProgressFn) -> Result<Vec<u8>, String> {
    if !url.starts_with("https://") {
        return Err(format!("Insecure URL rejected: HTTPS required ('{}')", url));
    }

    progress("Connecting to download server...".to_string());
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
        return Err(format!("Download failed: HTTP {} from {}", status, url));
    }

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

    // Minimum expected archive size (must be at least 512KB for a real binary bundle)
    if bytes.len() < 512 * 1024 {
        return Err(format!(
            "Download too small ({} bytes) - invalid release archive",
            bytes.len()
        ));
    }

    Ok(bytes.to_vec())
}

// ============================================================
// Extraction
// ============================================================

pub fn extract_zip(
    bytes: &[u8],
    staging_dir: &Path,
    binary_name_in_archive: &str,
    extracted_binary_path: &Path,
) -> Result<(), String> {
    use std::io::Read;

    let cursor = Cursor::new(bytes);
    let mut archive = zip::ZipArchive::new(cursor)
        .map_err(|e| format!("Failed to parse ZIP archive (invalid format): {}", e))?;

    let binary_entry_name = (0..archive.len())
        .find_map(|i| {
            archive.by_index(i).ok().and_then(|entry| {
                let name = entry.name().to_string();
                if (name == binary_name_in_archive
                    || name.ends_with(&format!("/{}", binary_name_in_archive))
                    || name.ends_with(&format!("\\{}", binary_name_in_archive)))
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

    std::fs::create_dir_all(staging_dir)
        .map_err(|e| format!("Failed to create staging dir {:?}: {}", staging_dir, e))?;

    let mut entry = archive.by_name(&binary_entry_name).map_err(|e| {
        format!(
            "Failed to read archive entry '{}': {}",
            binary_entry_name, e
        )
    })?;

    let mut content = Vec::new();
    entry
        .read_to_end(&mut content)
        .map_err(|e| format!("Failed to read binary from archive: {}", e))?;

    if content.is_empty() {
        return Err("Extracted binary is empty (0 bytes)".to_string());
    }

    std::fs::write(extracted_binary_path, &content).map_err(|e| {
        format!(
            "Failed to write binary to {:?}: {}",
            extracted_binary_path, e
        )
    })?;

    Ok(())
}

#[cfg(unix)]
pub fn extract_tar_gz(
    bytes: &[u8],
    staging_dir: &Path,
    binary_name_in_archive: &str,
    extracted_binary_path: &Path,
) -> Result<(), String> {
    use flate2::read::GzDecoder;
    use std::io::Read;
    use tar::Archive;

    std::fs::create_dir_all(staging_dir)
        .map_err(|e| format!("Failed to create staging dir {:?}: {}", staging_dir, e))?;

    let gz = GzDecoder::new(Cursor::new(bytes));
    let mut archive = Archive::new(gz);

    for entry_result in archive
        .entries()
        .map_err(|e| format!("Failed to read tar entries: {}", e))?
    {
        let mut entry = entry_result.map_err(|e| format!("Failed to read tar entry: {}", e))?;

        let path = entry
            .path()
            .map_err(|e| format!("Failed to get entry path: {}", e))?
            .to_path_buf();

        let name = path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        if name == binary_name_in_archive {
            let mut content = Vec::new();
            entry
                .read_to_end(&mut content)
                .map_err(|e| format!("Failed to read tar entry contents: {}", e))?;

            if content.is_empty() {
                return Err("Extracted binary is empty".to_string());
            }

            std::fs::write(extracted_binary_path, &content)
                .map_err(|e| format!("Failed to write binary: {}", e))?;

            return Ok(());
        }
    }

    Err(format!(
        "Binary '{}' not found in tar.gz archive",
        binary_name_in_archive
    ))
}

#[cfg(unix)]
pub fn make_executable(path: &Path) -> Result<(), String> {
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
pub fn make_executable(_path: &Path) -> Result<(), String> {
    Ok(())
}

// ============================================================
// Main install function (Isolated Staging -> Verify -> Atomic Move)
// ============================================================

/// Download, extract into an isolated staging directory, verify with `--version`,
/// check version equality, and atomically move the verified executable into `binary_dest`.
/// If download, extraction, or verification fails, any existing working binary at `binary_dest`
/// is preserved untouched.
pub async fn install_opencode<F: Fn(String) + Send + Sync + 'static>(
    version: &str,
    owner: &str,
    repo: &str,
    target_dir: &Path,
    binary_dest: &Path,
    progress: F,
) -> Result<String, String> {
    let progress: ProgressFn = Box::new(progress);
    let (url, binary_name_in_archive) = artifact_info(version, owner, repo)?;

    // 1. Create isolated staging directory on the same filesystem (inside target_dir's parent)
    let parent_dir = target_dir
        .parent()
        .ok_or_else(|| "Invalid target directory parent".to_string())?;
    let staging_id = uuid::Uuid::new_v4().to_string();
    let staging_dir = parent_dir.join(".staging").join(&staging_id);
    std::fs::create_dir_all(&staging_dir).map_err(|e| {
        format!(
            "Failed to create staging directory {:?}: {}",
            staging_dir, e
        )
    })?;

    let staging_binary = staging_dir.join(&binary_name_in_archive);

    // RAII cleaner for staging dir
    struct StagingGuard(PathBuf);
    impl Drop for StagingGuard {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
    let _guard = StagingGuard(staging_dir.clone());

    // 2. Download bytes over HTTPS
    let bytes = download_bytes(&url, &progress).await?;

    // 3. Extract to staging directory
    progress("Extracting archive into temporary staging directory...".to_string());
    if url.ends_with(".zip") {
        extract_zip(
            &bytes,
            &staging_dir,
            &binary_name_in_archive,
            &staging_binary,
        )?;
    } else {
        #[cfg(unix)]
        extract_tar_gz(
            &bytes,
            &staging_dir,
            &binary_name_in_archive,
            &staging_binary,
        )?;
        #[cfg(windows)]
        return Err("Unexpected non-ZIP archive on Windows".to_string());
    }

    // 4. Set execution permissions (if on Unix)
    make_executable(&staging_binary)?;

    // 5. Pre-activation verification: run `staging_binary --version` directly
    progress("Verifying AI engine binary...".to_string());
    let confirmed_version = verify_binary(&staging_binary).await.map_err(|e| {
        format!(
            "Binary extracted but failed verification: {}. The binary may be corrupt.",
            e
        )
    })?;

    // Verify expected version matches
    if confirmed_version != version {
        return Err(format!(
            "Version mismatch: expected '{}', but verified binary reported '{}'",
            version, confirmed_version
        ));
    }

    // 6. Ensure destination directory exists
    std::fs::create_dir_all(target_dir)
        .map_err(|e| format!("Failed to create target dir {:?}: {}", target_dir, e))?;

    // 7. Atomically move verified executable to final managed path
    progress("Activating AI engine...".to_string());
    if let Err(e) = std::fs::rename(&staging_binary, binary_dest) {
        log::warn!(
            "[OpenCode Installer] Rename failed ({:?}), falling back to copy",
            e
        );
        std::fs::copy(&staging_binary, binary_dest).map_err(|copy_err| {
            format!(
                "Failed to place verified binary at {:?}: {}",
                binary_dest, copy_err
            )
        })?;
        let _ = std::fs::remove_file(&staging_binary);
    }

    log::info!(
        "[OpenCode Installer] Successfully provisioned OpenCode v{} to {:?}",
        confirmed_version,
        binary_dest
    );

    Ok(confirmed_version)
}
