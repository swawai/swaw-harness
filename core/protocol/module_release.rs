use std::ffi::OsStr;
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};

use serde::Deserialize;
use sha2::{Digest, Sha256};

use crate::{ModuleId, Version, VersionSelector};

pub const MODULE_MANIFEST_NAME: &str = "swaw-harness.module.json";

const MODULE_SCHEMA: &str = "swaw.harness.module/v1";
const MAXIMUM_MANIFEST_BYTES: u64 = 16 * 1024;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct InstalledModules {
    root: PathBuf,
}

impl InstalledModules {
    pub fn open(data_home: impl AsRef<Path>) -> Result<Self, String> {
        let data_home = data_home.as_ref();
        assert_regular_directory(data_home, "DataHome")?;
        let admin_root = data_home.join("admin");
        assert_regular_directory(&admin_root, "Admin EntryRoot")?;
        let modules_root = admin_root.join("modules");
        assert_regular_directory(&modules_root, "installed modules root")?;
        let root = fs::canonicalize(&modules_root).map_err(|error| {
            format!(
                "cannot resolve installed modules root '{}': {error}",
                modules_root.display()
            )
        })?;
        Ok(Self { root })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn select(
        &self,
        module: &ModuleId,
        version_selector: VersionSelector,
        platform_target_id: &str,
        executable_name: &str,
    ) -> Result<ResolvedModuleRelease, String> {
        assert_safe_segment(platform_target_id, "PlatformTargetId")?;
        assert_safe_segment(executable_name, "executable name")?;

        let mut platform_root = self.root.clone();
        for segment in module.segments() {
            platform_root.push(segment);
            assert_regular_directory(&platform_root, "module identity directory")?;
        }
        platform_root.push(platform_target_id);
        assert_regular_directory(&platform_root, "module platform directory")?;

        let (version, release_root) = select_version(&platform_root, version_selector)?;
        validate_release(
            module,
            version,
            platform_target_id,
            executable_name,
            release_root,
        )
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedModuleRelease {
    module: ModuleId,
    version: Version,
    platform_target_id: String,
    root: PathBuf,
    manifest_path: PathBuf,
    executable_path: PathBuf,
    executable_length: u64,
    executable_sha256: String,
}

impl ResolvedModuleRelease {
    pub fn module(&self) -> &ModuleId {
        &self.module
    }

    pub fn version(&self) -> Version {
        self.version
    }

    pub fn platform_target_id(&self) -> &str {
        &self.platform_target_id
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn manifest_path(&self) -> &Path {
        &self.manifest_path
    }

    pub fn executable_path(&self) -> &Path {
        &self.executable_path
    }

    pub fn executable_length(&self) -> u64 {
        self.executable_length
    }

    pub fn executable_sha256(&self) -> &str {
        &self.executable_sha256
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ModuleManifest {
    schema: String,
    module: String,
    version: String,
    platform_target_id: String,
    executable: ExecutableRecord,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ExecutableRecord {
    name: String,
    length: u64,
    sha256: String,
}

fn select_version(
    platform_root: &Path,
    selector: VersionSelector,
) -> Result<(Version, PathBuf), String> {
    let mut candidates = Vec::new();
    for entry in fs::read_dir(platform_root).map_err(|error| {
        format!(
            "cannot enumerate module platform directory '{}': {error}",
            platform_root.display()
        )
    })? {
        let entry = entry.map_err(|error| format!("cannot enumerate module versions: {error}"))?;
        let path = entry.path();
        let metadata = fs::symlink_metadata(&path).map_err(|error| {
            format!(
                "cannot inspect Module Release '{}': {error}",
                path.display()
            )
        })?;
        if metadata_is_reparse(&metadata) || !metadata.is_dir() {
            return Err(format!(
                "module platform directory contains a non-regular release directory: {}",
                path.display()
            ));
        }
        let name = entry
            .file_name()
            .to_str()
            .ok_or_else(|| "Module Release version directory name is not Unicode".to_owned())?
            .to_owned();
        let version = Version::parse(&name).map_err(|error| {
            format!(
                "invalid Module Release version directory '{}': {error}",
                path.display()
            )
        })?;
        if selector.matches(version) {
            candidates.push((version, path));
        }
    }

    candidates
        .into_iter()
        .max_by_key(|(version, _)| *version)
        .ok_or_else(|| {
            format!(
                "no installed Module Release matches version '{selector}' in '{}'",
                platform_root.display()
            )
        })
}

fn validate_release(
    expected_module: &ModuleId,
    expected_version: Version,
    expected_platform_target_id: &str,
    expected_executable_name: &str,
    release_root: PathBuf,
) -> Result<ResolvedModuleRelease, String> {
    assert_regular_directory(&release_root, "Module Release root")?;
    let manifest_path = release_root.join(MODULE_MANIFEST_NAME);
    let manifest: ModuleManifest = parse_manifest(&manifest_path)?;

    if manifest.schema != MODULE_SCHEMA {
        return Err(format!(
            "unsupported Module Release schema '{}' in '{}'; expected '{MODULE_SCHEMA}'",
            manifest.schema,
            manifest_path.display()
        ));
    }
    let manifest_module = ModuleId::parse(manifest.module)?;
    if &manifest_module != expected_module {
        return Err(format!(
            "Module Release manifest module '{}' does not match selected module '{}' in '{}'",
            manifest_module,
            expected_module,
            manifest_path.display()
        ));
    }
    let manifest_version = Version::parse(&manifest.version)?;
    if manifest_version != expected_version {
        return Err(format!(
            "Module Release manifest version '{}' does not match selected version '{}' in '{}'",
            manifest_version,
            expected_version,
            manifest_path.display()
        ));
    }
    assert_safe_segment(&manifest.platform_target_id, "manifest PlatformTargetId")?;
    if manifest.platform_target_id != expected_platform_target_id {
        return Err(format!(
            "Module Release manifest PlatformTargetId '{}' does not match selected target '{}' in '{}'",
            manifest.platform_target_id,
            expected_platform_target_id,
            manifest_path.display()
        ));
    }
    assert_safe_segment(&manifest.executable.name, "manifest executable name")?;
    if manifest.executable.name != expected_executable_name {
        return Err(format!(
            "Module Release manifest executable '{}' does not match selected executable '{}' in '{}'",
            manifest.executable.name,
            expected_executable_name,
            manifest_path.display()
        ));
    }
    validate_release_members(&release_root, &manifest.executable.name)?;
    if !is_lowercase_sha256(&manifest.executable.sha256) {
        return Err(format!(
            "Module Release manifest contains an invalid executable SHA-256: {}",
            manifest_path.display()
        ));
    }

    let executable_path = release_root.join(&manifest.executable.name);
    let executable_metadata = assert_regular_file(&executable_path, "Module Release executable")?;
    if executable_metadata.len() != manifest.executable.length {
        return Err(format!(
            "Module Release executable length does not match its manifest: {}",
            executable_path.display()
        ));
    }
    let executable_sha256 = sha256_file(&executable_path)?;
    if executable_sha256 != manifest.executable.sha256 {
        return Err(format!(
            "Module Release executable SHA-256 does not match its manifest: {}",
            executable_path.display()
        ));
    }

    Ok(ResolvedModuleRelease {
        module: manifest_module,
        version: manifest_version,
        platform_target_id: manifest.platform_target_id,
        root: release_root,
        manifest_path,
        executable_path,
        executable_length: executable_metadata.len(),
        executable_sha256,
    })
}

fn validate_release_members(release_root: &Path, executable_name: &str) -> Result<(), String> {
    let mut member_count = 0_usize;
    let mut has_manifest = false;
    let mut has_executable = false;
    for entry in fs::read_dir(release_root).map_err(|error| {
        format!(
            "cannot enumerate Module Release '{}': {error}",
            release_root.display()
        )
    })? {
        let entry = entry.map_err(|error| format!("cannot enumerate Module Release: {error}"))?;
        member_count += 1;
        let name = entry.file_name();
        has_manifest |= name == OsStr::new(MODULE_MANIFEST_NAME);
        has_executable |= name == OsStr::new(executable_name);
    }
    if member_count != 2 || !has_manifest || !has_executable {
        return Err(format!(
            "Module Release membership is invalid: {}",
            release_root.display()
        ));
    }
    Ok(())
}

fn parse_manifest(path: &Path) -> Result<ModuleManifest, String> {
    let metadata = assert_regular_file(path, "Module Release manifest")?;
    if metadata.len() == 0 || metadata.len() > MAXIMUM_MANIFEST_BYTES {
        return Err(format!(
            "Module Release manifest has an invalid size: {}",
            path.display()
        ));
    }
    let encoded = fs::read(path).map_err(|error| {
        format!(
            "cannot read Module Release manifest '{}': {error}",
            path.display()
        )
    })?;
    serde_json::from_slice(&encoded).map_err(|error| {
        format!(
            "cannot parse Module Release manifest '{}': {error}",
            path.display()
        )
    })
}

fn sha256_file(path: &Path) -> Result<String, String> {
    let mut file = File::open(path).map_err(|error| {
        format!(
            "cannot open Module Release executable '{}': {error}",
            path.display()
        )
    })?;
    let mut digest = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let count = file.read(&mut buffer).map_err(|error| {
            format!(
                "cannot hash Module Release executable '{}': {error}",
                path.display()
            )
        })?;
        if count == 0 {
            break;
        }
        digest.update(&buffer[..count]);
    }
    Ok(format!("{:x}", digest.finalize()))
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

fn assert_regular_file(path: &Path, description: &str) -> Result<fs::Metadata, String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect {description} '{}': {error}", path.display()))?;
    if metadata_is_reparse(&metadata) || !metadata.is_file() {
        Err(format!(
            "{description} is not a regular non-reparse file: {}",
            path.display()
        ))
    } else {
        Ok(metadata)
    }
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

fn is_lowercase_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
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

#[cfg(test)]
mod tests;
