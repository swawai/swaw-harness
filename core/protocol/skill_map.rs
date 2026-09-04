use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};

mod document;
mod help;

use crate::filesystem::find_exact_child;
use document::parse_skill_declaration;
pub use document::{ModuleId, SKILL_DOCUMENT_NAME, SkillDeclaration, Version, VersionSelector};
pub use help::{HelpLanguage, SkillHelpNode};

const AGENT_DOCUMENT_NAME: &str = "AGENTS.md";
pub(crate) const MAXIMUM_TREE_DEPTH: usize = 64;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SkillNode {
    path: String,
    declaration: SkillDeclaration,
}

impl SkillNode {
    pub fn path(&self) -> &str {
        &self.path
    }

    pub fn declaration(&self) -> &SkillDeclaration {
        &self.declaration
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SkillMap {
    root: PathBuf,
}

impl SkillMap {
    pub fn open_core(user_home: impl AsRef<Path>) -> Result<Self, String> {
        let user_home = user_home.as_ref();
        assert_regular_directory(user_home, "UserHome")?;
        let map_root = find_exact_child(user_home, "map", "Skill Map root")?;
        assert_regular_directory(&map_root, "Skill Map root")?;
        let core_root = find_exact_child(&map_root, "core", "Core Skill Map")?;
        assert_regular_directory(&core_root, "Core Skill Map")?;
        Self::open(core_root)
    }

    pub fn open(root: impl AsRef<Path>) -> Result<Self, String> {
        let root = root.as_ref();
        assert_regular_directory(root, "Skill Map root")?;
        let root = fs::canonicalize(root).map_err(|error| {
            format!(
                "cannot resolve Skill Map root '{}': {error}",
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

    pub fn find(&self, skill_path: &str) -> Result<SkillNode, String> {
        let skill_segments = parse_relative_path(skill_path, "Skill path")?;
        let skill_directory =
            join_exact_regular_directories(&self.root, &skill_segments, "Skill directory")?;
        let declaration_path =
            find_exact_regular_file(&skill_directory, SKILL_DOCUMENT_NAME, "Skill declaration")?;
        let declaration = parse_skill_declaration(&declaration_path)?;
        validate_directory_entries(&self.root, &skill_directory, true, |_| Ok(()))?;

        Ok(SkillNode {
            path: skill_path.to_owned(),
            declaration,
        })
    }
}

fn validate_directory(root: &Path, directory: &Path, depth: usize) -> Result<(), String> {
    if depth > MAXIMUM_TREE_DEPTH {
        return Err(format!(
            "Skill Map exceeds {MAXIMUM_TREE_DEPTH} directory levels: {}",
            directory.display()
        ));
    }
    assert_regular_directory(directory, "Skill Map directory")?;

    let skill_document = directory.join(SKILL_DOCUMENT_NAME);
    let has_skill = regular_file_exists(&skill_document, "Skill declaration")?;
    if has_skill {
        if directory == root {
            return Err("Skill Map root cannot declare a Skill".to_owned());
        }
        parse_skill_declaration(&skill_document)?;
    }
    help::validate_help_documents(directory)?;

    for child_directory in validate_directory_entries(root, directory, true, |_| Ok(()))? {
        validate_directory(root, &child_directory, depth + 1)?;
    }
    Ok(())
}

fn validate_directory_entries(
    root: &Path,
    directory: &Path,
    include_child_directories: bool,
    mut inspect_child_directory: impl FnMut(&Path) -> Result<(), String>,
) -> Result<Vec<PathBuf>, String> {
    let mut child_directories = Vec::new();
    for entry in fs::read_dir(directory).map_err(|error| {
        format!(
            "cannot enumerate Skill Map directory '{}': {error}",
            directory.display()
        )
    })? {
        let entry = entry.map_err(|error| format!("cannot enumerate Skill Map: {error}"))?;
        let entry_path = entry.path();
        let metadata = fs::symlink_metadata(&entry_path)
            .map_err(|error| format!("cannot inspect '{}': {error}", entry_path.display()))?;
        let is_directory = metadata_is_directory_entry(&metadata);
        if is_directory {
            inspect_child_directory(&entry_path)?;
        }
        if metadata_is_reparse(&metadata) {
            if !include_child_directories && is_directory {
                continue;
            }
            return Err(format!(
                "Skill Map cannot contain a symbolic link or reparse point: {}",
                entry_path.display()
            ));
        }
        if is_directory {
            if include_child_directories {
                assert_safe_segment(
                    entry
                        .file_name()
                        .to_str()
                        .ok_or_else(|| "Skill Map directory name is not Unicode".to_owned())?,
                    "Skill Map directory name",
                )?;
                child_directories.push(entry_path);
            }
        } else if metadata.is_file() {
            let name = entry.file_name();
            let name = name
                .to_str()
                .ok_or_else(|| "Skill Map file name is not Unicode".to_owned())?;
            let allowed = name == SKILL_DOCUMENT_NAME
                || help::is_help_document_name(name)
                || (directory == root && name == AGENT_DOCUMENT_NAME);
            if !allowed {
                return Err(format!(
                    "unexpected Skill Map file: {}",
                    entry_path.display()
                ));
            }
        } else {
            return Err(format!(
                "Skill Map entry is not a regular file or directory: {}",
                entry_path.display()
            ));
        }
    }
    Ok(child_directories)
}

fn regular_file_exists(path: &Path, description: &str) -> Result<bool, String> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata_is_reparse(&metadata) || !metadata.is_file() => Err(format!(
            "expected a regular non-reparse file when {description} exists: {}",
            path.display()
        )),
        Ok(_) => {
            let canonical = fs::canonicalize(path).map_err(|error| {
                format!("cannot resolve {description} '{}': {error}", path.display())
            })?;
            if canonical.file_name() != path.file_name() {
                return Err(format!(
                    "non-canonical {description} name '{}'; expected '{}': {}",
                    canonical
                        .file_name()
                        .and_then(|name| name.to_str())
                        .unwrap_or("<non-Unicode>"),
                    path.file_name()
                        .and_then(|name| name.to_str())
                        .unwrap_or("<non-Unicode>"),
                    canonical.display()
                ));
            }
            Ok(true)
        }
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

fn metadata_is_directory_entry(metadata: &fs::Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x10;
        metadata.file_attributes() & FILE_ATTRIBUTE_DIRECTORY != 0
    }
    #[cfg(not(windows))]
    {
        metadata.is_dir()
    }
}

pub(crate) fn parse_relative_path<'a>(
    value: &'a str,
    description: &str,
) -> Result<Vec<&'a str>, String> {
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

pub(crate) fn assert_safe_segment(value: &str, description: &str) -> Result<(), String> {
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

fn join_exact_regular_directories(
    root: &Path,
    segments: &[&str],
    description: &str,
) -> Result<PathBuf, String> {
    join_exact_regular_directories_inspecting(root, segments, description, |_| Ok(()))
}

fn join_exact_regular_directories_inspecting(
    root: &Path,
    segments: &[&str],
    description: &str,
    mut inspect_directory: impl FnMut(&Path) -> Result<(), String>,
) -> Result<PathBuf, String> {
    let mut path = root.to_path_buf();
    for segment in segments {
        inspect_directory(&path.join(segment))?;
        path = find_exact_child(&path, segment, description)?;
        assert_regular_directory(&path, description)?;
    }
    Ok(path)
}

fn find_exact_regular_file(
    directory: &Path,
    name: &str,
    description: &str,
) -> Result<PathBuf, String> {
    let path = find_exact_child(directory, name, description)?;
    let metadata = fs::symlink_metadata(&path)
        .map_err(|error| format!("cannot inspect {description} '{}': {error}", path.display()))?;
    if metadata_is_reparse(&metadata) || !metadata.is_file() {
        return Err(format!(
            "{description} is not a regular non-reparse file: {}",
            path.display()
        ));
    }
    Ok(path)
}

#[cfg(test)]
mod tests;
