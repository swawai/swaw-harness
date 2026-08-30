use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use super::platform::{is_reparse_point, move_file_replace};

static UNIQUE_COUNTER: AtomicU64 = AtomicU64::new(0);

pub(crate) fn ensure_child_directory(parent: &Path, name: &str) -> Result<PathBuf, String> {
    assert_regular_directory(parent, "managed parent directory")?;
    assert_case_spelling(parent, name)?;
    let path = parent.join(name);
    match fs::create_dir(&path) {
        Ok(()) => {}
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
        Err(error) => {
            return Err(format!(
                "cannot create managed directory '{}': {error}",
                path.display()
            ));
        }
    }
    assert_regular_directory(&path, "managed directory")?;
    Ok(path)
}

pub(crate) fn assert_regular_directory(path: &Path, description: &str) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("{description} is missing '{}': {error}", path.display()))?;
    if !metadata.is_dir() || is_reparse_point(&metadata) {
        return Err(format!(
            "{description} must be a regular directory: {}",
            path.display()
        ));
    }
    Ok(())
}

pub(crate) fn assert_regular_file(path: &Path, description: &str) -> Result<fs::Metadata, String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("{description} is missing '{}': {error}", path.display()))?;
    if !metadata.is_file() || is_reparse_point(&metadata) {
        return Err(format!(
            "{description} must be a regular file: {}",
            path.display()
        ));
    }
    Ok(metadata)
}

pub(crate) fn path_exists(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok()
}

pub(crate) fn read_bounded(
    path: &Path,
    maximum_bytes: u64,
    description: &str,
) -> Result<Vec<u8>, String> {
    let metadata = assert_regular_file(path, description)?;
    if metadata.len() == 0 || metadata.len() > maximum_bytes {
        return Err(format!(
            "{description} must contain 1 to {maximum_bytes} bytes: {}",
            path.display()
        ));
    }
    let mut file = File::open(path)
        .map_err(|error| format!("cannot open {description} '{}': {error}", path.display()))?;
    let mut bytes = Vec::with_capacity(metadata.len() as usize);
    file.read_to_end(&mut bytes)
        .map_err(|error| format!("cannot read {description} '{}': {error}", path.display()))?;
    if bytes.len() as u64 != metadata.len() {
        return Err(format!(
            "{description} changed while it was read: {}",
            path.display()
        ));
    }
    Ok(bytes)
}

pub(crate) fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| format!("atomic destination has no parent: {}", path.display()))?;
    assert_regular_directory(parent, "atomic destination parent")?;
    let leaf = path
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| format!("atomic destination has an invalid name: {}", path.display()))?;
    let stage = parent.join(format!(".{leaf}.tmp"));
    remove_regular_file_if_present(&stage)?;
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&stage)
        .map_err(|error| format!("cannot create atomic stage '{}': {error}", stage.display()))?;
    let result = (|| {
        file.write_all(bytes)
            .map_err(|error| format!("cannot write atomic stage '{}': {error}", stage.display()))?;
        file.sync_all()
            .map_err(|error| format!("cannot flush atomic stage '{}': {error}", stage.display()))?;
        drop(file);
        if path_exists(path) {
            assert_regular_file(path, "atomic destination")?;
        }
        move_file_replace(&stage, path)
            .map_err(|error| format!("cannot publish atomic file '{}': {error}", path.display()))
    })();
    if result.is_err() {
        let _ = fs::remove_file(&stage);
    }
    result
}

pub(crate) fn copy_file_atomic(source: &Path, destination: &Path) -> Result<(), String> {
    assert_regular_file(source, "copy source")?;
    let parent = destination
        .parent()
        .ok_or_else(|| format!("copy destination has no parent: {}", destination.display()))?;
    assert_regular_directory(parent, "copy destination parent")?;
    let leaf = destination
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| {
            format!(
                "copy destination has an invalid name: {}",
                destination.display()
            )
        })?;
    let stage = parent.join(format!(".{leaf}.tmp"));
    remove_regular_file_if_present(&stage)?;
    fs::copy(source, &stage).map_err(|error| {
        format!(
            "cannot copy '{}' to '{}': {error}",
            source.display(),
            stage.display()
        )
    })?;
    OpenOptions::new()
        .write(true)
        .open(&stage)
        .and_then(|file| file.sync_all())
        .map_err(|error| format!("cannot flush copied file '{}': {error}", stage.display()))?;
    if path_exists(destination) {
        assert_regular_file(destination, "copy destination")?;
    }
    let result = move_file_replace(&stage, destination).map_err(|error| {
        format!(
            "cannot publish copied file '{}': {error}",
            destination.display()
        )
    });
    if result.is_err() {
        let _ = fs::remove_file(&stage);
    }
    result
}

pub(crate) fn remove_regular_file_if_present(path: &Path) -> Result<(), String> {
    if !path_exists(path) {
        return Ok(());
    }
    assert_regular_file(path, "managed temporary file")?;
    fs::remove_file(path)
        .map_err(|error| format!("cannot remove managed file '{}': {error}", path.display()))
}

pub(crate) fn create_stage_directory(stage_parent: &Path, prefix: &str) -> Result<PathBuf, String> {
    assert_regular_directory(stage_parent, "Entry staging parent")?;
    for _ in 0..64 {
        let path = stage_parent.join(format!(".{prefix}-{}.tmp", unique_token()));
        match fs::create_dir(&path) {
            Ok(()) => return Ok(path),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => {
                return Err(format!(
                    "cannot create Admin staging directory '{}': {error}",
                    path.display()
                ));
            }
        }
    }
    Err("cannot allocate a unique Admin staging directory".to_owned())
}

pub(crate) fn clean_stage_directories(stage_parent: &Path, prefix: &str) -> Result<(), String> {
    assert_regular_directory(stage_parent, "Entry staging parent")?;
    let expected_prefix = format!(".{prefix}-");
    for entry in fs::read_dir(stage_parent)
        .map_err(|error| format!("cannot enumerate Entry staging parent: {error}"))?
    {
        let entry = entry.map_err(|error| format!("cannot enumerate Admin stage: {error}"))?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with(&expected_prefix) && name.ends_with(".tmp") {
            remove_tree(&entry.path(), stage_parent)?;
        }
    }
    Ok(())
}

pub(crate) fn remove_tree(path: &Path, controlled_root: &Path) -> Result<(), String> {
    if !is_path_below(path, controlled_root) {
        return Err(format!(
            "refusing to remove a path outside the controlled root: {}",
            path.display()
        ));
    }
    if !path_exists(path) {
        return Ok(());
    }
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect managed path '{}': {error}", path.display()))?;
    if is_reparse_point(&metadata) {
        if metadata.is_dir() {
            fs::remove_dir(path)
        } else {
            fs::remove_file(path)
        }
        .map_err(|error| format!("cannot remove reparse point '{}': {error}", path.display()))?;
        return Ok(());
    }
    if metadata.is_dir() {
        for child in fs::read_dir(path).map_err(|error| {
            format!(
                "cannot enumerate managed directory '{}': {error}",
                path.display()
            )
        })? {
            let child =
                child.map_err(|error| format!("cannot enumerate managed child: {error}"))?;
            remove_tree(&child.path(), controlled_root)?;
        }
        fs::remove_dir(path)
            .map_err(|error| format!("cannot remove directory '{}': {error}", path.display()))?;
    } else {
        fs::remove_file(path)
            .map_err(|error| format!("cannot remove file '{}': {error}", path.display()))?;
    }
    Ok(())
}

pub(crate) fn move_directory(source: &Path, destination: &Path) -> Result<(), String> {
    assert_regular_directory(source, "staged directory")?;
    if path_exists(destination) {
        return Err(format!(
            "managed directory destination already exists: {}",
            destination.display()
        ));
    }
    fs::rename(source, destination).map_err(|error| {
        format!(
            "cannot publish staged directory '{}' as '{}': {error}",
            source.display(),
            destination.display()
        )
    })
}

pub(crate) fn assert_case_spelling(parent: &Path, expected: &str) -> Result<(), String> {
    if !path_exists(parent) {
        return Ok(());
    }
    assert_regular_directory(parent, "case-check parent")?;
    for entry in fs::read_dir(parent)
        .map_err(|error| format!("cannot enumerate '{}': {error}", parent.display()))?
    {
        let entry = entry.map_err(|error| format!("cannot enumerate namespace entry: {error}"))?;
        let actual = entry.file_name().to_string_lossy().into_owned();
        if actual.eq_ignore_ascii_case(expected) && actual != expected {
            return Err(format!(
                "case-insensitive namespace conflict: expected '{expected}', found '{actual}'"
            ));
        }
    }
    Ok(())
}

pub(crate) fn same_file_contents(left: &Path, right: &Path) -> Result<bool, String> {
    let left_metadata = assert_regular_file(left, "left file")?;
    let right_metadata = assert_regular_file(right, "right file")?;
    if left_metadata.len() != right_metadata.len() {
        return Ok(false);
    }
    let mut left_file =
        File::open(left).map_err(|error| format!("cannot open '{}': {error}", left.display()))?;
    let mut right_file =
        File::open(right).map_err(|error| format!("cannot open '{}': {error}", right.display()))?;
    let mut left_buffer = [0_u8; 64 * 1024];
    let mut right_buffer = [0_u8; 64 * 1024];
    loop {
        let left_count = left_file
            .read(&mut left_buffer)
            .map_err(|error| format!("cannot read '{}': {error}", left.display()))?;
        let right_count = right_file
            .read(&mut right_buffer)
            .map_err(|error| format!("cannot read '{}': {error}", right.display()))?;
        if left_count != right_count || left_buffer[..left_count] != right_buffer[..right_count] {
            return Ok(false);
        }
        if left_count == 0 {
            return Ok(true);
        }
    }
}

fn is_path_below(path: &Path, root: &Path) -> bool {
    let path = normalized_compare_text(path);
    let mut root = normalized_compare_text(root);
    if !root.ends_with('\\') {
        root.push('\\');
    }
    path.starts_with(&root)
}

pub(crate) fn paths_overlap(left: &Path, right: &Path) -> bool {
    let left_text = normalized_compare_text(left);
    let right_text = normalized_compare_text(right);
    is_equal_or_below(&left_text, &right_text) || is_equal_or_below(&right_text, &left_text)
}

fn is_equal_or_below(path: &str, root: &str) -> bool {
    path == root
        || path
            .strip_prefix(root)
            .is_some_and(|suffix| suffix.starts_with('\\'))
}

fn normalized_compare_text(path: &Path) -> String {
    let normalized: PathBuf = path.components().collect();
    normalized
        .to_string_lossy()
        .replace('/', "\\")
        .trim_end_matches('\\')
        .to_ascii_lowercase()
}

fn unique_token() -> String {
    let counter = UNIQUE_COUNTER.fetch_add(1, Ordering::Relaxed);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    format!("{:x}-{:x}-{counter:x}", std::process::id(), nanos)
}
