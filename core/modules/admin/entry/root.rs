use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};

use super::platform::{is_reparse_point, path_character_count};

const MAX_HARNESS_ROOT_CHARACTERS: usize = 60;

pub(crate) fn validate_harness_root(path: &Path) -> Result<PathBuf, String> {
    if !path.is_absolute() {
        return Err(format!(
            "HarnessRoot must be an absolute path: {}",
            path.display()
        ));
    }
    if path
        .components()
        .any(|component| matches!(component, Component::ParentDir))
    {
        return Err(format!(
            "HarnessRoot must be lexically normalized: {}",
            path.display()
        ));
    }
    let normalized: PathBuf = path.components().collect();
    if normalized.as_os_str() != path.as_os_str() {
        return Err(format!(
            "HarnessRoot must be lexically normalized: {}",
            path.display()
        ));
    }
    if path_character_count(&normalized) > MAX_HARNESS_ROOT_CHARACTERS {
        return Err(format!(
            "HarnessRoot exceeds the 60-character Windows path budget: {}",
            path.display()
        ));
    }
    Ok(normalized)
}

pub(crate) fn ensure_root_directory(path: &Path) -> Result<(), String> {
    inspect_existing_ancestors(path)?;

    let mut missing = Vec::new();
    for ancestor in path.ancestors() {
        match fs::symlink_metadata(ancestor) {
            Ok(_) => break,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                missing.push(ancestor.to_path_buf());
            }
            Err(error) => return Err(inspect_error(ancestor, error)),
        }
    }

    for directory in missing.iter().rev() {
        let parent = directory.parent().ok_or_else(|| {
            format!(
                "HarnessRoot directory has no parent: {}",
                directory.display()
            )
        })?;
        inspect_existing_ancestors(parent)?;
        match fs::create_dir(directory) {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
            Err(error) => {
                return Err(format!(
                    "cannot create HarnessRoot directory '{}': {error}",
                    directory.display()
                ));
            }
        }
        assert_regular_root_component(directory)?;
    }

    inspect_existing_ancestors(path)
}

fn inspect_existing_ancestors(path: &Path) -> Result<(), String> {
    for ancestor in path.ancestors() {
        match fs::symlink_metadata(ancestor) {
            Ok(metadata) => {
                if !metadata.is_dir() || is_reparse_point(&metadata) {
                    return Err(format!(
                        "HarnessRoot ancestor must be a regular directory: {}",
                        ancestor.display()
                    ));
                }
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(inspect_error(ancestor, error)),
        }
    }
    Ok(())
}

fn assert_regular_root_component(path: &Path) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path).map_err(|error| inspect_error(path, error))?;
    if !metadata.is_dir() || is_reparse_point(&metadata) {
        return Err(format!(
            "HarnessRoot ancestor must be a regular directory: {}",
            path.display()
        ));
    }
    Ok(())
}

fn inspect_error(path: &Path, error: io::Error) -> String {
    format!(
        "cannot inspect HarnessRoot ancestor '{}': {error}",
        path.display()
    )
}
