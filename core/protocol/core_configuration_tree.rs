use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};

mod document;

use document::parse_facet;
pub use document::{FACET_DOCUMENT_NAME, FacetDefinition, ModuleId, Version, VersionSelector};

const AGENT_DOCUMENT_NAME: &str = "AGENTS.md";
const MAXIMUM_TREE_DEPTH: usize = 64;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedFacet {
    resource: String,
    facet: String,
    definition: FacetDefinition,
}

impl ResolvedFacet {
    pub fn resource(&self) -> &str {
        &self.resource
    }

    pub fn facet(&self) -> &str {
        &self.facet
    }

    pub fn definition(&self) -> &FacetDefinition {
        &self.definition
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CoreConfigurationTree {
    root: PathBuf,
}

impl CoreConfigurationTree {
    pub fn open(root: impl AsRef<Path>) -> Result<Self, String> {
        let root = root.as_ref();
        assert_regular_directory(root, "Core Configuration Tree root")?;
        let root = fs::canonicalize(root).map_err(|error| {
            format!(
                "cannot resolve Core Configuration Tree root '{}': {error}",
                root.display()
            )
        })?;
        Ok(Self { root })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn validate(&self) -> Result<(), String> {
        validate_directory(&self.root, &self.root, 0)
    }

    pub fn resolve(&self, resource: &str, facet: &str) -> Result<ResolvedFacet, String> {
        let resource_segments = parse_relative_path(resource, "Resource path")?;
        assert_safe_segment(facet, "Facet name")?;

        let resource_directory =
            join_regular_directories(&self.root, &resource_segments, "Resource directory")?;
        let facet_directory = resource_directory.join(facet);
        assert_regular_directory(&facet_directory, "Facet directory")?;
        let definition = parse_facet(&facet_directory.join(FACET_DOCUMENT_NAME))?;

        Ok(ResolvedFacet {
            resource: resource.to_owned(),
            facet: facet.to_owned(),
            definition,
        })
    }
}

fn validate_directory(root: &Path, directory: &Path, depth: usize) -> Result<(), String> {
    if depth > MAXIMUM_TREE_DEPTH {
        return Err(format!(
            "Core Configuration Tree exceeds {MAXIMUM_TREE_DEPTH} directory levels: {}",
            directory.display()
        ));
    }
    assert_regular_directory(directory, "Core Configuration Tree directory")?;

    let facet_document = directory.join(FACET_DOCUMENT_NAME);
    let has_facet = regular_file_exists(&facet_document)?;
    if has_facet {
        if directory == root {
            return Err("Core Configuration Tree root cannot be a Facet".to_owned());
        }
        let resource_directory = directory
            .parent()
            .ok_or_else(|| format!("Facet has no Resource parent: {}", directory.display()))?;
        if resource_directory == root {
            return Err(format!(
                "Facet must have a non-empty Resource path: {}",
                directory.display()
            ));
        }
        parse_facet(&facet_document)?;
    }

    for entry in fs::read_dir(directory).map_err(|error| {
        format!(
            "cannot enumerate Core Configuration Tree directory '{}': {error}",
            directory.display()
        )
    })? {
        let entry =
            entry.map_err(|error| format!("cannot enumerate Core Configuration Tree: {error}"))?;
        let entry_path = entry.path();
        let metadata = fs::symlink_metadata(&entry_path)
            .map_err(|error| format!("cannot inspect '{}': {error}", entry_path.display()))?;
        if metadata_is_reparse(&metadata) {
            return Err(format!(
                "Core Configuration Tree cannot contain a symbolic link or reparse point: {}",
                entry_path.display()
            ));
        }
        if metadata.is_dir() {
            if has_facet {
                return Err(format!(
                    "Facet directory must be a leaf: {}",
                    directory.display()
                ));
            }
            assert_safe_segment(
                entry.file_name().to_str().ok_or_else(|| {
                    "Core Configuration Tree directory name is not Unicode".to_owned()
                })?,
                "Core Configuration Tree directory name",
            )?;
            validate_directory(root, &entry_path, depth + 1)?;
        } else if metadata.is_file() {
            let name = entry.file_name();
            let name = name
                .to_str()
                .ok_or_else(|| "Core Configuration Tree file name is not Unicode".to_owned())?;
            let allowed =
                name == FACET_DOCUMENT_NAME || (directory == root && name == AGENT_DOCUMENT_NAME);
            if !allowed {
                return Err(format!(
                    "unexpected Core Configuration Tree file: {}",
                    entry_path.display()
                ));
            }
        } else {
            return Err(format!(
                "Core Configuration Tree entry is not a regular file or directory: {}",
                entry_path.display()
            ));
        }
    }
    Ok(())
}

fn regular_file_exists(path: &Path) -> Result<bool, String> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata_is_reparse(&metadata) || !metadata.is_file() => Err(format!(
            "expected a regular non-reparse file when Facet declaration exists: {}",
            path.display()
        )),
        Ok(_) => Ok(true),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(false),
        Err(error) => Err(format!("cannot inspect '{}': {error}", path.display())),
    }
}

fn assert_regular_directory(path: &Path, description: &str) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect {description} '{}': {error}", path.display()))?;
    if metadata_is_reparse(&metadata) || !metadata.is_dir() {
        Err(format!(
            "{description} is not a regular non-reparse directory: {}",
            path.display()
        ))
    } else {
        Ok(())
    }
}

fn metadata_is_reparse(metadata: &fs::Metadata) -> bool {
    if metadata.file_type().is_symlink() {
        return true;
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
        metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0
    }
    #[cfg(not(windows))]
    {
        false
    }
}

fn parse_relative_path<'a>(value: &'a str, description: &str) -> Result<Vec<&'a str>, String> {
    if value.is_empty() || value.contains('\\') {
        return Err(format!(
            "{description} must be a canonical relative path: {value}"
        ));
    }
    let segments: Vec<_> = value.split('/').collect();
    for segment in &segments {
        assert_safe_segment(segment, description)?;
    }
    Ok(segments)
}

fn assert_safe_segment(value: &str, description: &str) -> Result<(), String> {
    let bytes = value.as_bytes();
    let valid = bytes
        .first()
        .is_some_and(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit())
        && bytes.iter().skip(1).all(|byte| {
            byte.is_ascii_lowercase()
                || byte.is_ascii_digit()
                || matches!(byte, b'.' | b'_' | b'+' | b'-')
        });
    let base = value
        .split('.')
        .next()
        .unwrap_or(value)
        .to_ascii_lowercase();
    let reserved = matches!(base.as_str(), "con" | "prn" | "aux" | "nul")
        || matches!(base.as_bytes(), [b'c', b'o', b'm', b'1'..=b'9'])
        || matches!(base.as_bytes(), [b'l', b'p', b't', b'1'..=b'9']);
    if valid && !value.ends_with('.') && !reserved {
        Ok(())
    } else {
        Err(format!("invalid {description} '{value}'"))
    }
}

fn join_regular_directories(
    root: &Path,
    segments: &[&str],
    description: &str,
) -> Result<PathBuf, String> {
    let mut path = root.to_path_buf();
    for segment in segments {
        path.push(segment);
        assert_regular_directory(&path, description)?;
    }
    Ok(path)
}

#[cfg(test)]
mod tests;
