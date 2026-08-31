use std::fs;
use std::path::{Path, PathBuf};

use serde::Deserialize;

use super::{
    assert_regular_directory, assert_regular_file, assert_release_id, assert_safe_segment,
    join_segments, metadata_is_reparse, parse_relative_path,
};

pub const RESOURCE_DOCUMENT_NAME: &str = "swaw-harness.resource.json";
pub const FACET_DOCUMENT_NAME: &str = "swaw-harness.facet.json";
pub const EXECUTABLE_DOCUMENT_NAME: &str = "swaw-harness.executable.json";

pub(super) const RESOURCE_SCHEMA: &str = "swaw.harness.resource/v1";
pub(super) const FACET_SCHEMA: &str = "swaw.harness.facet/v1";
pub(super) const EXECUTABLE_SCHEMA: &str = "swaw.harness.executable/v1";
const MAXIMUM_DOCUMENT_BYTES: u64 = 16 * 1024;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ExecutableBinding {
    release_root: PathBuf,
    release_id: String,
    executable: String,
}

impl ExecutableBinding {
    pub fn release_root(&self) -> &Path {
        &self.release_root
    }

    pub fn release_id(&self) -> &str {
        &self.release_id
    }

    pub fn executable(&self) -> &str {
        &self.executable
    }

    pub fn executable_path(&self, entry_root: &Path) -> Result<PathBuf, String> {
        if !entry_root.is_absolute() {
            return Err(format!(
                "EntryRoot must be absolute when resolving an executable: {}",
                entry_root.display()
            ));
        }
        assert_regular_directory(entry_root, "EntryRoot")?;
        let mut path = entry_root.to_path_buf();
        for segment in self.release_root.iter() {
            path.push(segment);
            assert_regular_directory(&path, "Core module product directory")?;
        }
        path.push(&self.release_id);
        assert_regular_directory(&path, "Core module Release directory")?;
        path.push(&self.executable);
        assert_regular_file(&path, "Core module executable")?;
        Ok(path)
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct MarkerDocument {
    schema: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ExecutableDocument {
    schema: String,
    release_root: String,
    release_id: String,
    executable: String,
}

pub(super) fn parse_marker(
    path: &Path,
    expected_schema: &str,
    description: &str,
) -> Result<(), String> {
    let document: MarkerDocument = parse_document(path, description)?;
    if document.schema != expected_schema {
        return Err(format!(
            "unsupported {description} schema '{}' in '{}'",
            document.schema,
            path.display()
        ));
    }
    Ok(())
}

pub(super) fn parse_executable(path: &Path) -> Result<ExecutableBinding, String> {
    let document: ExecutableDocument = parse_document(path, "executable binding")?;
    if document.schema != EXECUTABLE_SCHEMA {
        return Err(format!(
            "unsupported executable binding schema '{}' in '{}'",
            document.schema,
            path.display()
        ));
    }
    let release_segments = parse_relative_path(&document.release_root, "releaseRoot")?;
    if release_segments.len() < 3
        || release_segments[0] != "runtime"
        || release_segments[1] != "core"
    {
        return Err(format!(
            "releaseRoot must identify a product root below 'runtime/core': {}",
            document.release_root
        ));
    }
    assert_release_id(&document.release_id)?;
    assert_safe_segment(&document.executable, "executable name")?;
    Ok(ExecutableBinding {
        release_root: join_segments(Path::new(""), &release_segments),
        release_id: document.release_id,
        executable: document.executable,
    })
}

fn parse_document<T: for<'de> Deserialize<'de>>(
    path: &Path,
    description: &str,
) -> Result<T, String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect {description} '{}': {error}", path.display()))?;
    if metadata_is_reparse(&metadata) || !metadata.is_file() {
        return Err(format!(
            "{description} is not a regular non-reparse file: {}",
            path.display()
        ));
    }
    if metadata.len() == 0 || metadata.len() > MAXIMUM_DOCUMENT_BYTES {
        return Err(format!(
            "{description} has an invalid size: {}",
            path.display()
        ));
    }
    let encoded = fs::read(path)
        .map_err(|error| format!("cannot read {description} '{}': {error}", path.display()))?;
    serde_json::from_slice(&encoded)
        .map_err(|error| format!("cannot parse {description} '{}': {error}", path.display()))
}
