use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};

mod document;

pub use document::{
    EXECUTABLE_DOCUMENT_NAME, ExecutableBinding, FACET_DOCUMENT_NAME, RESOURCE_DOCUMENT_NAME,
};
use document::{FACET_SCHEMA, RESOURCE_SCHEMA, parse_executable, parse_marker};

const MAXIMUM_TREE_DEPTH: usize = 64;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedFacet {
    resource: String,
    facet: String,
    binding: ExecutableBinding,
}

impl ResolvedFacet {
    pub fn resource(&self) -> &str {
        &self.resource
    }

    pub fn facet(&self) -> &str {
        &self.facet
    }

    pub fn binding(&self) -> &ExecutableBinding {
        &self.binding
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RuntimeCoreTree {
    root: PathBuf,
}

impl RuntimeCoreTree {
    pub fn open(root: impl AsRef<Path>) -> Result<Self, String> {
        let root = root.as_ref();
        assert_regular_directory(root, "Runtime Core Tree root")?;
        let root = fs::canonicalize(root).map_err(|error| {
            format!(
                "cannot resolve Runtime Core Tree root '{}': {error}",
                root.display()
            )
        })?;
        Ok(Self { root })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn validate(&self) -> Result<(), String> {
        let mut facets = Vec::new();
        validate_directory(&self.root, &self.root, 0, &mut facets)?;
        for (resource, facet) in facets {
            self.resolve(&resource, &facet)?;
        }
        Ok(())
    }

    pub fn resolve(&self, resource: &str, facet: &str) -> Result<ResolvedFacet, String> {
        let resource_segments = parse_relative_path(resource, "Resource path")?;
        assert_safe_segment(facet, "Facet name")?;

        let resource_directory =
            join_regular_directories(&self.root, &resource_segments, "Resource directory")?;
        parse_marker(
            &resource_directory.join(RESOURCE_DOCUMENT_NAME),
            RESOURCE_SCHEMA,
            "Resource declaration",
        )?;
        let facet_directory = resource_directory.join(facet);
        assert_regular_directory(&facet_directory, "Facet directory")?;
        parse_marker(
            &facet_directory.join(FACET_DOCUMENT_NAME),
            FACET_SCHEMA,
            "Facet declaration",
        )?;

        let mut owner = resource_directory.as_path();
        let binding = loop {
            let candidate = owner.join(EXECUTABLE_DOCUMENT_NAME);
            if regular_file_exists(&candidate)? {
                parse_marker(
                    &owner.join(RESOURCE_DOCUMENT_NAME),
                    RESOURCE_SCHEMA,
                    "executable binding owner Resource declaration",
                )?;
                break parse_executable(&candidate)?;
            }
            if owner == self.root {
                return Err(format!(
                    "Resource '{resource}' Facet '{facet}' has no executable binding"
                ));
            }
            owner = owner.parent().ok_or_else(|| {
                format!(
                    "executable binding search escaped Runtime Core Tree '{}'",
                    self.root.display()
                )
            })?;
            if !owner.starts_with(&self.root) {
                return Err(format!(
                    "executable binding search escaped Runtime Core Tree '{}'",
                    self.root.display()
                ));
            }
        };

        Ok(ResolvedFacet {
            resource: resource.to_owned(),
            facet: facet.to_owned(),
            binding,
        })
    }
}

fn validate_directory(
    root: &Path,
    directory: &Path,
    depth: usize,
    facets: &mut Vec<(String, String)>,
) -> Result<(), String> {
    if depth > MAXIMUM_TREE_DEPTH {
        return Err(format!(
            "Runtime Core Tree exceeds {MAXIMUM_TREE_DEPTH} directory levels: {}",
            directory.display()
        ));
    }
    assert_regular_directory(directory, "Runtime Core Tree directory")?;

    let resource = directory.join(RESOURCE_DOCUMENT_NAME);
    let facet = directory.join(FACET_DOCUMENT_NAME);
    let executable = directory.join(EXECUTABLE_DOCUMENT_NAME);
    let has_resource = regular_file_exists(&resource)?;
    let has_facet = regular_file_exists(&facet)?;
    let has_executable = regular_file_exists(&executable)?;
    if has_resource && has_facet {
        return Err(format!(
            "a Runtime Core Tree directory cannot declare both Resource and Facet: {}",
            directory.display()
        ));
    }
    if has_resource {
        parse_marker(&resource, RESOURCE_SCHEMA, "Resource declaration")?;
    }
    if has_executable {
        if !has_resource {
            return Err(format!(
                "executable binding must be beside a Resource declaration: {}",
                executable.display()
            ));
        }
        parse_executable(&executable)?;
    }
    if has_facet {
        parse_marker(&facet, FACET_SCHEMA, "Facet declaration")?;
        let resource_directory = directory.parent().ok_or_else(|| {
            format!(
                "Facet directory has no containing Resource: {}",
                directory.display()
            )
        })?;
        if !regular_file_exists(&resource_directory.join(RESOURCE_DOCUMENT_NAME))? {
            return Err(format!(
                "Facet must be an immediate child of a Resource: {}",
                directory.display()
            ));
        }
        let relative = resource_directory
            .strip_prefix(root)
            .map_err(|_| format!("Facet escaped Runtime Core Tree: {}", directory.display()))?;
        facets.push((
            path_to_route(relative)?,
            directory_name(directory, "Facet")?,
        ));
    }

    for entry in fs::read_dir(directory).map_err(|error| {
        format!(
            "cannot enumerate Runtime Core Tree directory '{}': {error}",
            directory.display()
        )
    })? {
        let entry =
            entry.map_err(|error| format!("cannot enumerate Runtime Core Tree: {error}"))?;
        let entry_path = entry.path();
        let metadata = fs::symlink_metadata(&entry_path)
            .map_err(|error| format!("cannot inspect '{}': {error}", entry_path.display()))?;
        if metadata_is_reparse(&metadata) {
            return Err(format!(
                "Runtime Core Tree cannot contain a symbolic link or reparse point: {}",
                entry_path.display()
            ));
        }
        if metadata.is_dir() {
            assert_safe_segment(
                entry
                    .file_name()
                    .to_str()
                    .ok_or_else(|| "Runtime Core Tree directory name is not Unicode".to_owned())?,
                "Runtime Core Tree directory name",
            )?;
            validate_directory(root, &entry_path, depth + 1, facets)?;
        }
    }
    Ok(())
}

fn regular_file_exists(path: &Path) -> Result<bool, String> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata_is_reparse(&metadata) || !metadata.is_file() => Err(format!(
            "expected a regular non-reparse file when declaration exists: {}",
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

fn assert_regular_file(path: &Path, description: &str) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect {description} '{}': {error}", path.display()))?;
    if metadata_is_reparse(&metadata) || !metadata.is_file() {
        Err(format!(
            "{description} is not a regular non-reparse file: {}",
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

fn assert_release_id(value: &str) -> Result<(), String> {
    if value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        Ok(())
    } else {
        Err(format!("invalid ReleaseId '{value}'"))
    }
}

fn join_segments(root: &Path, segments: &[&str]) -> PathBuf {
    segments
        .iter()
        .fold(root.to_path_buf(), |path, segment| path.join(segment))
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

fn path_to_route(path: &Path) -> Result<String, String> {
    path.iter()
        .map(|segment| {
            segment
                .to_str()
                .map(str::to_owned)
                .ok_or_else(|| "Runtime Core Tree path is not Unicode".to_owned())
        })
        .collect::<Result<Vec<_>, _>>()
        .map(|segments| segments.join("/"))
}

fn directory_name(path: &Path, description: &str) -> Result<String, String> {
    path.file_name()
        .and_then(|value| value.to_str())
        .map(str::to_owned)
        .ok_or_else(|| {
            format!(
                "{description} directory name is not Unicode: {}",
                path.display()
            )
        })
}

#[cfg(test)]
mod tests;
