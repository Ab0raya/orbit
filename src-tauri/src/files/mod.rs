pub mod manager;
pub mod operations;
pub mod path;

pub use manager::{FileListResult, FileManager, FileReadResult, FileRoot, FileWriteResult};
pub use operations::{
    detect_file_category, detect_mime_type, extract_image_dimensions, read_binary_file,
    search_files, BinaryReadResult, FileCategory, FileEntry, FileError, FileSearchResult,
    SearchFileResult,
};

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::{Path, PathBuf};

    fn setup_test_sandbox() -> (PathBuf, FileManager) {
        let temp_dir = std::env::temp_dir().join(format!("orbit_test_fs_{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&temp_dir).unwrap();

        let mgr = FileManager::with_scopes(vec![temp_dir.clone()]);
        (temp_dir, mgr)
    }

    fn cleanup_test_sandbox(path: PathBuf) {
        let _ = fs::remove_dir_all(path);
    }

    #[test]
    fn test_directory_listing_and_metadata() {
        let (sandbox, mgr) = setup_test_sandbox();
        let sub_dir = sandbox.join("subdir");
        let test_file = sandbox.join("hello.txt");

        fs::create_dir(&sub_dir).unwrap();
        fs::write(&test_file, "Hello World").unwrap();

        let list_res = mgr.list(&sandbox.to_string_lossy()).unwrap();
        assert_eq!(list_res.entries.len(), 2);

        // Directories sorted before files
        assert_eq!(list_res.entries[0].name, "subdir");
        assert_eq!(list_res.entries[0].kind, "directory");
        assert_eq!(list_res.entries[0].size, 0);

        assert_eq!(list_res.entries[1].name, "hello.txt");
        assert_eq!(list_res.entries[1].kind, "file");
        assert_eq!(list_res.entries[1].size, 11);
        assert!(list_res.entries[1].modified_at.is_some());

        cleanup_test_sandbox(sandbox);
    }

    #[test]
    fn test_read_and_write_text_file_atomic() {
        let (sandbox, mgr) = setup_test_sandbox();
        let file_path = sandbox.join("notes.md");
        let path_str = file_path.to_string_lossy().to_string();

        // 1. Write file atomically
        let write_res = mgr
            .write(&path_str, "# Orbit Notes\nRemote file test")
            .unwrap();
        assert_eq!(write_res.size, 30);
        assert!(write_res.success);

        // 2. Read back
        let read_res = mgr.read(&path_str).unwrap();
        assert_eq!(read_res.content, "# Orbit Notes\nRemote file test");
        assert_eq!(read_res.encoding, "utf8");
        assert_eq!(read_res.size, 30);

        // 3. Overwrite
        mgr.write(&path_str, "Updated content").unwrap();
        let read_res2 = mgr.read(&path_str).unwrap();
        assert_eq!(read_res2.content, "Updated content");

        cleanup_test_sandbox(sandbox);
    }

    #[test]
    fn test_mkdir_rename_delete() {
        let (sandbox, mgr) = setup_test_sandbox();
        let dir_to_create = sandbox.join("new_folder");
        let dir_str = dir_to_create.to_string_lossy().to_string();

        // 1. Mkdir
        mgr.mkdir(&dir_str).unwrap();
        assert!(dir_to_create.exists() && dir_to_create.is_dir());

        // 2. Create file inside
        let file_path = dir_to_create.join("file.txt");
        let file_str = file_path.to_string_lossy().to_string();
        mgr.write(&file_str, "content").unwrap();

        // 3. Rename file
        let renamed_path = dir_to_create.join("renamed.txt");
        let renamed_str = renamed_path.to_string_lossy().to_string();
        mgr.rename(&file_str, &renamed_str).unwrap();
        assert!(!file_path.exists());
        assert!(renamed_path.exists());

        // 4. Delete file
        mgr.delete(&renamed_str).unwrap();
        assert!(!renamed_path.exists());

        // 5. Delete directory
        mgr.delete(&dir_str).unwrap();
        assert!(!dir_to_create.exists());

        cleanup_test_sandbox(sandbox);
    }

    #[test]
    fn test_invalid_path_and_traversal_rejection() {
        let (sandbox, mgr) = setup_test_sandbox();

        // Path outside sandbox scope
        let traversal_path = sandbox.join("../../etc/passwd");
        let traversal_str = traversal_path.to_string_lossy().to_string();

        let res = mgr.read(&traversal_str);
        assert!(res.is_err());
        match res.unwrap_err() {
            FileError::PermissionDenied(_) => {}
            other => panic!(
                "Expected PermissionDenied for traversal attempt, got {:?}",
                other
            ),
        }

        cleanup_test_sandbox(sandbox);
    }

    #[test]
    fn test_nonexistent_file_and_directory() {
        let (sandbox, mgr) = setup_test_sandbox();

        let non_file = sandbox.join("does_not_exist.txt");
        let non_dir = sandbox.join("does_not_exist_dir");

        let read_err = mgr.read(&non_file.to_string_lossy()).unwrap_err();
        match read_err {
            FileError::NotFound(_) => {}
            other => panic!("Expected NotFound, got {:?}", other),
        }

        let list_err = mgr.list(&non_dir.to_string_lossy()).unwrap_err();
        match list_err {
            FileError::NotFound(_) => {}
            other => panic!("Expected NotFound, got {:?}", other),
        }

        cleanup_test_sandbox(sandbox);
    }

    // 1. image file detection
    #[test]
    fn test_image_file_detection() {
        assert_eq!(
            detect_file_category(Path::new("photo.png")),
            FileCategory::Image
        );
        assert_eq!(
            detect_file_category(Path::new("pic.jpg")),
            FileCategory::Image
        );
        assert_eq!(
            detect_file_category(Path::new("pic.jpeg")),
            FileCategory::Image
        );
        assert_eq!(
            detect_file_category(Path::new("anim.gif")),
            FileCategory::Image
        );
        assert_eq!(
            detect_file_category(Path::new("graphic.webp")),
            FileCategory::Image
        );
        assert_eq!(
            detect_file_category(Path::new("bitmap.bmp")),
            FileCategory::Image
        );
        assert_eq!(
            detect_file_category(Path::new("vector.svg")),
            FileCategory::Image
        );
    }

    // 2. text file detection
    #[test]
    fn test_text_file_detection() {
        assert_eq!(
            detect_file_category(Path::new("readme.txt")),
            FileCategory::Text
        );
        assert_eq!(
            detect_file_category(Path::new("doc.md")),
            FileCategory::Text
        );
        assert_eq!(
            detect_file_category(Path::new("app.log")),
            FileCategory::Text
        );
        assert_eq!(
            detect_file_category(Path::new("data.json")),
            FileCategory::Text
        );
        assert_eq!(
            detect_file_category(Path::new("config.yaml")),
            FileCategory::Text
        );
        assert_eq!(
            detect_file_category(Path::new("config.yml")),
            FileCategory::Text
        );
        assert_eq!(
            detect_file_category(Path::new("feed.xml")),
            FileCategory::Text
        );
        assert_eq!(
            detect_file_category(Path::new("table.csv")),
            FileCategory::Text
        );
        assert_eq!(detect_file_category(Path::new(".env")), FileCategory::Text);
    }

    // 3. code file detection
    #[test]
    fn test_code_file_detection() {
        assert_eq!(
            detect_file_category(Path::new("main.dart")),
            FileCategory::Code
        );
        assert_eq!(
            detect_file_category(Path::new("lib.rs")),
            FileCategory::Code
        );
        assert_eq!(
            detect_file_category(Path::new("app.ts")),
            FileCategory::Code
        );
        assert_eq!(
            detect_file_category(Path::new("view.tsx")),
            FileCategory::Code
        );
        assert_eq!(
            detect_file_category(Path::new("script.js")),
            FileCategory::Code
        );
        assert_eq!(
            detect_file_category(Path::new("comp.jsx")),
            FileCategory::Code
        );
        assert_eq!(
            detect_file_category(Path::new("server.py")),
            FileCategory::Code
        );
        assert_eq!(
            detect_file_category(Path::new("Main.java")),
            FileCategory::Code
        );
        assert_eq!(
            detect_file_category(Path::new("App.kt")),
            FileCategory::Code
        );
        assert_eq!(
            detect_file_category(Path::new("main.go")),
            FileCategory::Code
        );
        assert_eq!(
            detect_file_category(Path::new("index.html")),
            FileCategory::Code
        );
        assert_eq!(
            detect_file_category(Path::new("style.css")),
            FileCategory::Code
        );
        assert_eq!(
            detect_file_category(Path::new("run.sh")),
            FileCategory::Code
        );
    }

    // 4. unknown binary detection
    #[test]
    fn test_unknown_binary_detection() {
        assert_eq!(
            detect_file_category(Path::new("blob.bin")),
            FileCategory::Binary
        );
        assert_eq!(
            detect_file_category(Path::new("firmware.dat")),
            FileCategory::Binary
        );
        assert_eq!(
            detect_file_category(Path::new("archive.tar.gz")),
            FileCategory::Binary
        );
        assert_eq!(
            detect_file_category(Path::new("program.exe")),
            FileCategory::Binary
        );
    }

    // 5. oversized file rejection
    #[test]
    fn test_oversized_binary_file_handling() {
        let (sandbox, mgr) = setup_test_sandbox();
        let big_file = sandbox.join("large.bin");
        // Write 100 bytes
        fs::write(&big_file, vec![0x42; 100]).unwrap();

        // Reading with max_bytes = 50 should return metadata with is_too_large: true and content: None
        let res = mgr
            .read_binary(&big_file.to_string_lossy(), Some(50))
            .unwrap();
        assert!(res.is_too_large);
        assert!(res.content.is_none());
        assert_eq!(res.size, 100);
        assert_eq!(res.file_category, FileCategory::Binary);

        cleanup_test_sandbox(sandbox);
    }

    // 6. binary path validation
    #[test]
    fn test_binary_path_validation() {
        let (sandbox, mgr) = setup_test_sandbox();
        let traversal = sandbox.join("../../secret.bin");

        let res = mgr.read_binary(&traversal.to_string_lossy(), None);
        assert!(res.is_err(), "Traversal on read_binary must be rejected");
        match res.unwrap_err() {
            FileError::PermissionDenied(_) => {}
            other => panic!("Expected PermissionDenied, got {:?}", other),
        }

        cleanup_test_sandbox(sandbox);
    }

    // 7. MIME/type metadata and image dimensions
    #[test]
    fn test_mime_type_metadata_and_dimensions() {
        let (sandbox, mgr) = setup_test_sandbox();

        // 1x1 transparent PNG bytes
        let png_bytes = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
            0x00, 0x00, 0x00, 0x0D, // IHDR length
            0x49, 0x48, 0x44, 0x52, // IHDR
            0x00, 0x00, 0x00, 0x0A, // width = 10
            0x00, 0x00, 0x00, 0x14, // height = 20
            0x08, 0x06, 0x00, 0x00, 0x00, // bit depth, color type, etc.
            0x00, 0x00, 0x00, 0x00, // crc
        ];

        let png_file = sandbox.join("test_dims.png");
        fs::write(&png_file, png_bytes).unwrap();

        let res = mgr.read_binary(&png_file.to_string_lossy(), None).unwrap();
        assert_eq!(res.mime_type, "image/png");
        assert_eq!(res.file_category, FileCategory::Image);
        assert_eq!(res.width, Some(10));
        assert_eq!(res.height, Some(20));
        assert!(res.content.is_some());
        assert!(!res.is_too_large);

        cleanup_test_sandbox(sandbox);
    }

    // 8. existing text file behavior remains intact
    #[test]
    fn test_existing_text_file_behavior_intact() {
        let (sandbox, mgr) = setup_test_sandbox();
        let file_path = sandbox.join("plain.txt");
        let path_str = file_path.to_string_lossy().to_string();

        mgr.write(&path_str, "Hello from orbit").unwrap();
        let text_res = mgr.read(&path_str).unwrap();
        assert_eq!(text_res.content, "Hello from orbit");
        assert_eq!(text_res.encoding, "utf8");

        cleanup_test_sandbox(sandbox);
    }

    // 9. File search by name
    #[test]
    fn test_search_files_by_name() {
        let (sandbox, mgr) = setup_test_sandbox();
        let file_a = sandbox.join("README.md");
        let file_b = sandbox.join("src").join("main.rs");
        let file_c = sandbox.join("docs").join("architecture.md");

        fs::create_dir_all(sandbox.join("src")).unwrap();
        fs::create_dir_all(sandbox.join("docs")).unwrap();
        fs::write(&file_a, "# Project README\nWelcome to Orbit").unwrap();
        fs::write(&file_b, "fn main() { println!(\"orbit\"); }").unwrap();
        fs::write(&file_c, "# Architecture Doc").unwrap();

        // Search for "readme" (case-insensitive)
        let res = mgr
            .search(&sandbox.to_string_lossy(), "readme", "name", None)
            .unwrap();
        assert_eq!(res.results.len(), 1);
        assert_eq!(res.results[0].name, "README.md");
        assert!(!res.results[0].is_directory);

        // Search for ".md"
        let res_md = mgr
            .search(&sandbox.to_string_lossy(), ".md", "name", None)
            .unwrap();
        assert_eq!(res_md.results.len(), 2);

        cleanup_test_sandbox(sandbox);
    }

    // 10. File search by content
    #[test]
    fn test_search_files_by_content() {
        let (sandbox, mgr) = setup_test_sandbox();
        let file_a = sandbox.join("README.md");
        let file_b = sandbox.join("code.rs");

        fs::write(&file_a, "line 1\nline 2: UNIQUE_KEYWORD_ORBIT\nline 3").unwrap();
        fs::write(&file_b, "// no match here\nlet x = 42;").unwrap();

        let res = mgr
            .search(
                &sandbox.to_string_lossy(),
                "UNIQUE_KEYWORD",
                "content",
                None,
            )
            .unwrap();
        assert_eq!(res.results.len(), 1);
        assert_eq!(res.results[0].name, "README.md");
        assert_eq!(res.results[0].line_number, Some(2));
        assert!(res.results[0]
            .line_content
            .as_ref()
            .unwrap()
            .contains("UNIQUE_KEYWORD_ORBIT"));

        cleanup_test_sandbox(sandbox);
    }

    // 11. Search skips ignored directories (.git, node_modules, build)
    #[test]
    fn test_search_skips_ignored_directories() {
        let (sandbox, mgr) = setup_test_sandbox();
        let git_dir = sandbox.join(".git");
        let node_dir = sandbox.join("node_modules");
        let build_dir = sandbox.join("build");
        let valid_dir = sandbox.join("src");

        fs::create_dir_all(&git_dir).unwrap();
        fs::create_dir_all(&node_dir).unwrap();
        fs::create_dir_all(&build_dir).unwrap();
        fs::create_dir_all(&valid_dir).unwrap();

        fs::write(git_dir.join("config"), "secret_in_git").unwrap();
        fs::write(node_dir.join("package.json"), "secret_in_node").unwrap();
        fs::write(build_dir.join("output.txt"), "secret_in_build").unwrap();
        fs::write(valid_dir.join("lib.rs"), "pub fn secret_in_src() {}").unwrap();

        let res = mgr
            .search(&sandbox.to_string_lossy(), "secret_in", "content", None)
            .unwrap();
        assert_eq!(res.results.len(), 1);
        assert_eq!(res.results[0].name, "lib.rs");

        cleanup_test_sandbox(sandbox);
    }

    // 12. Search skips binary files
    #[test]
    fn test_search_skips_binary_files() {
        let (sandbox, mgr) = setup_test_sandbox();
        let bin_file = sandbox.join("app.bin");
        let text_file = sandbox.join("app.txt");

        // Binary file with null bytes
        let mut bin_content = b"findme_in_binary".to_vec();
        bin_content.insert(4, 0); // null byte
        fs::write(&bin_file, bin_content).unwrap();

        fs::write(&text_file, "findme_in_text").unwrap();

        let res = mgr
            .search(&sandbox.to_string_lossy(), "findme", "content", None)
            .unwrap();
        assert_eq!(res.results.len(), 1);
        assert_eq!(res.results[0].name, "app.txt");

        cleanup_test_sandbox(sandbox);
    }

    // 13. Search respects result limits and truncated flag
    #[test]
    fn test_search_limits() {
        let (sandbox, mgr) = setup_test_sandbox();
        for i in 0..10 {
            let p = sandbox.join(format!("file_{}.txt", i));
            fs::write(p, "orbit search match").unwrap();
        }

        let res = mgr
            .search(&sandbox.to_string_lossy(), "orbit", "content", Some(3))
            .unwrap();
        assert_eq!(res.results.len(), 3);
        assert!(res.truncated);

        cleanup_test_sandbox(sandbox);
    }

    // 14. Files operations on paths with spaces
    #[test]
    fn test_files_operations_with_spaces() {
        let (sandbox, mgr) = setup_test_sandbox();

        // 1. Create nested directory structure with spaces
        let nested_dir = sandbox.join("New Volume").join("The Cave").join("projects");
        fs::create_dir_all(&nested_dir).unwrap();

        // 2. List directory with spaces
        let list_res = mgr.list(&nested_dir.to_string_lossy()).unwrap();
        assert_eq!(list_res.entries.len(), 0);

        // 3. Write file with spaces
        let file_path = nested_dir.join("orbit test document.txt");
        let write_res = mgr
            .write(&file_path.to_string_lossy(), "hello orbit from space path")
            .unwrap();
        assert!(write_res.success);

        // 4. Read file with spaces
        let read_res = mgr.read(&file_path.to_string_lossy()).unwrap();
        assert_eq!(read_res.content, "hello orbit from space path");

        // 5. Mkdir directory with spaces
        let sub_dir = nested_dir.join("subfolder with spaces");
        let mkdir_res = mgr.mkdir(&sub_dir.to_string_lossy()).unwrap();
        assert!(Path::new(&mkdir_res).exists());

        // 6. Rename file with spaces
        let renamed_file = nested_dir.join("orbit renamed document.txt");
        mgr.rename(&file_path.to_string_lossy(), &renamed_file.to_string_lossy())
            .unwrap();
        assert!(!file_path.exists());
        assert!(renamed_file.exists());

        // 7. Search in directory with spaces
        let search_res = mgr
            .search(
                &nested_dir.to_string_lossy(),
                "orbit from space",
                "content",
                None,
            )
            .unwrap();
        assert_eq!(search_res.results.len(), 1);
        assert_eq!(search_res.results[0].name, "orbit renamed document.txt");

        // 8. Delete file with spaces
        mgr.delete(&renamed_file.to_string_lossy()).unwrap();
        assert!(!renamed_file.exists());

        cleanup_test_sandbox(sandbox);
    }
}
