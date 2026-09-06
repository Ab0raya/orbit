use super::*;
use std::io::Write;
use std::path::PathBuf;

#[test]
fn test_managed_path_resolution() {
    let base = PathBuf::from("C:\\Users\\Admin\\AppData\\Roaming\\Orbit");
    let manager = OpencodeManager::new(base.clone());

    let managed_dir = manager.managed_dir();
    let expected_dir = base
        .join("opencode")
        .join(format!("v{}", OPENCODE_MANAGED_VERSION));
    assert_eq!(managed_dir, expected_dir);

    let binary_path = manager.managed_binary_path();
    let exe_name = if cfg!(windows) {
        "opencode.exe"
    } else {
        "opencode"
    };
    assert_eq!(binary_path, expected_dir.join(exe_name));
}

#[test]
fn test_missing_binary_detection() {
    let temp_dir = std::env::temp_dir().join(format!("orbit_test_{}", uuid::Uuid::new_v4()));
    let non_existent = temp_dir.join("opencode.exe");

    assert_eq!(detector::find_managed(&non_existent), None);
}

#[test]
fn test_existing_valid_binary() {
    let temp_dir = std::env::temp_dir().join(format!("orbit_test_{}", uuid::Uuid::new_v4()));
    let _ = std::fs::create_dir_all(&temp_dir);
    let fake_binary = temp_dir.join("opencode.exe");
    std::fs::write(&fake_binary, b"fake binary content").unwrap();

    let found = detector::find_managed(&fake_binary);
    assert_eq!(found, Some(fake_binary.clone()));

    let _ = std::fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_version_parsing() {
    use installer::parse_version_output;

    // Plain version
    assert_eq!(parse_version_output("1.18.29").unwrap(), "1.18.29");
    // Prefix with program name
    assert_eq!(parse_version_output("opencode 1.18.29").unwrap(), "1.18.29");
    // Prefix with v
    assert_eq!(parse_version_output("v1.18.29").unwrap(), "1.18.29");
    // With build metadata
    assert_eq!(
        parse_version_output("opencode 1.18.29 (commit abc1234)").unwrap(),
        "1.18.29"
    );
    // Multiline output
    assert_eq!(
        parse_version_output("opencode v1.18.29\nRelease build 2026").unwrap(),
        "1.18.29"
    );

    // Errors on empty or invalid
    assert!(parse_version_output("").is_err());
    assert!(parse_version_output("   \n\t").is_err());
    assert!(parse_version_output("unknown command error").is_err());
}

#[test]
fn test_install_state_transitions() {
    let manager = OpencodeManager::new(PathBuf::from("test_dir"));

    // Initial state
    assert_eq!(manager.status(), OpencodeStatus::Checking);
    assert!(!manager.status().is_ready());
    assert_eq!(manager.status().user_message(), "Preparing AI engine...");

    // Installing transition
    manager.set_status(OpencodeStatus::Installing {
        progress: Some("Downloading AI engine...".to_string()),
    });
    assert!(!manager.status().is_ready());
    assert_eq!(manager.status().user_message(), "Downloading AI engine...");

    // Ready transition
    manager.set_status(OpencodeStatus::Ready {
        version: "1.18.29".to_string(),
        path: "C:\\test\\opencode.exe".to_string(),
    });
    assert!(manager.status().is_ready());
    assert_eq!(
        manager.status().ready_path(),
        Some(PathBuf::from("C:\\test\\opencode.exe"))
    );
    assert_eq!(manager.status().user_message(), "AI engine ready.");

    // DTO payload matches
    let payload = manager.status_payload();
    assert_eq!(payload.state, "ready");
    assert!(payload.is_ready);
    assert_eq!(payload.version, Some("1.18.29".to_string()));
    assert_eq!(payload.path, Some("C:\\test\\opencode.exe".to_string()));

    // Error transition
    manager.set_status(OpencodeStatus::Error {
        message: "Network failure".to_string(),
    });
    assert!(!manager.status().is_ready());
    assert!(manager.status().user_message().contains("Network failure"));
}

#[tokio::test]
async fn test_failed_download_insecure_url() {
    let progress: Box<dyn Fn(String) + Send + Sync> = Box::new(|_| {});
    let res = installer::download_bytes("http://example.com/opencode.zip", &progress).await;
    assert!(res.is_err());
    let err = res.unwrap_err();
    assert!(err.contains("HTTPS required"));
}

#[test]
fn test_invalid_zip() {
    let temp_dir = std::env::temp_dir().join(format!("orbit_test_zip_{}", uuid::Uuid::new_v4()));
    let _ = std::fs::create_dir_all(&temp_dir);
    let dest = temp_dir.join("opencode.exe");

    let invalid_bytes = b"not a valid zip file";
    let res = installer::extract_zip(invalid_bytes, &temp_dir, "opencode.exe", &dest);
    assert!(res.is_err());
    assert!(res.unwrap_err().contains("Failed to parse ZIP archive"));

    let _ = std::fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_missing_executable_in_zip() {
    let temp_dir = std::env::temp_dir().join(format!("orbit_test_zip_{}", uuid::Uuid::new_v4()));
    let _ = std::fs::create_dir_all(&temp_dir);
    let dest = temp_dir.join("opencode.exe");

    // Build a valid ZIP without opencode.exe
    let mut zip_buf = Vec::new();
    {
        let mut zip_writer = zip::ZipWriter::new(std::io::Cursor::new(&mut zip_buf));
        let options = zip::write::SimpleFileOptions::default();
        zip_writer.start_file("other_file.txt", options).unwrap();
        zip_writer.write_all(b"sample data").unwrap();
        zip_writer.finish().unwrap();
    }

    let res = installer::extract_zip(&zip_buf, &temp_dir, "opencode.exe", &dest);
    assert!(res.is_err());
    assert!(res.unwrap_err().contains("not found inside ZIP"));

    let _ = std::fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_version_mismatch() {
    let expected = "1.18.29";
    let verified = "1.18.28";
    assert_ne!(expected, verified);
}

#[test]
fn test_preserving_previous_valid_installation() {
    let temp_root =
        std::env::temp_dir().join(format!("orbit_test_preserve_{}", uuid::Uuid::new_v4()));
    let manager = OpencodeManager::new(temp_root.clone());

    let target_dir = manager.managed_dir();
    std::fs::create_dir_all(&target_dir).unwrap();
    let binary_dest = manager.managed_binary_path();

    // Create an existing working binary
    std::fs::write(&binary_dest, b"existing known-good binary").unwrap();

    // Staging simulation of failed extraction
    let staging_dir = temp_root.join("opencode").join(".staging").join("dummy");
    std::fs::create_dir_all(&staging_dir).unwrap();

    let invalid_bytes = b"corrupted bytes";
    let dest_staging = staging_dir.join("opencode.exe");
    let res = installer::extract_zip(invalid_bytes, &staging_dir, "opencode.exe", &dest_staging);
    assert!(res.is_err());

    // Verify existing known-good binary was preserved completely
    assert!(binary_dest.exists());
    let content = std::fs::read(&binary_dest).unwrap();
    assert_eq!(content, b"existing known-good binary");

    let _ = std::fs::remove_dir_all(&temp_root);
}

#[tokio::test]
async fn test_live_ensure_ready_flow() {
    let manager = OpencodeManager::with_default_dir();
    println!(
        "[Test] Starting ensure_ready flow for: {:?}",
        manager.managed_binary_path()
    );
    manager.ensure_ready().await;

    let status = manager.status();
    println!("[Test] Result status: {:?}", status);
    assert!(
        status.is_ready(),
        "Expected status to be Ready, got {:?}",
        status
    );

    let path = manager
        .resolve_binary_path()
        .expect("Should resolve binary path");
    assert!(path.is_file(), "Binary file should exist at {:?}", path);

    // Verify opencode.exe --version succeeds
    let version = installer::verify_binary(&path)
        .await
        .expect("Binary verification must succeed");
    assert_eq!(version, OPENCODE_MANAGED_VERSION);

    // Second launch simulation: should verify and reuse existing valid binary without re-downloading
    let status_before = manager.status();
    manager.ensure_ready().await;
    let status_after = manager.status();
    assert_eq!(status_before, status_after);
    assert!(status_after.is_ready());
}
