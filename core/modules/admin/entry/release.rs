use std::collections::HashSet;
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::entry::{assert_regular_directory, assert_regular_file, read_bounded};

pub(crate) const ADMIN_ARTIFACT_NAME: &str = "swaw-harness-admin.exe";
pub(crate) const ENTRY_ARTIFACT_NAME: &str = "entry.exe";
const RELEASE_SCHEMA: &str = "swaw.harness.bootstrap-release/v1";
const MAXIMUM_MANIFEST_BYTES: u64 = 1_048_576;
const MAXIMUM_ARTIFACT_BYTES: u64 = 64 * 1024 * 1024;
const MAXIMUM_ARTIFACTS: usize = 32;

#[derive(Debug, Clone)]
pub(crate) struct ValidatedRelease {
    root: PathBuf,
    manifest: ReleaseManifest,
}

impl ValidatedRelease {
    pub(crate) fn from_executable(executable: &Path) -> Result<Self, String> {
        if executable.file_name().and_then(|name| name.to_str()) != Some(ADMIN_ARTIFACT_NAME) {
            return Err(format!(
                "Admin executable must be named '{ADMIN_ARTIFACT_NAME}': {}",
                executable.display()
            ));
        }
        assert_regular_file(executable, "Admin executable")?;
        let root = executable.parent().ok_or_else(|| {
            format!(
                "Admin executable has no containing Release: {}",
                executable.display()
            )
        })?;
        let release = Self::open(root)?;
        let expected = release.artifact_path(ADMIN_ARTIFACT_NAME)?;
        if !same_path_text(executable, &expected) {
            return Err(format!(
                "Admin executable is not the manifest member '{}': {}",
                ADMIN_ARTIFACT_NAME,
                executable.display()
            ));
        }
        Ok(release)
    }

    pub(crate) fn open(root: &Path) -> Result<Self, String> {
        assert_regular_directory(root, "Release root")?;
        let directory_id = root
            .file_name()
            .and_then(|value| value.to_str())
            .ok_or_else(|| format!("Release root has an invalid identity: {}", root.display()))?;
        assert_release_id(directory_id)?;

        let manifest_path = root.join("manifest.json");
        let encoded = read_bounded(&manifest_path, MAXIMUM_MANIFEST_BYTES, "Release manifest")?;
        let manifest: ReleaseManifest = serde_json::from_slice(&encoded).map_err(|error| {
            format!(
                "cannot parse Release manifest '{}': {error}",
                manifest_path.display()
            )
        })?;
        manifest.validate(directory_id)?;
        validate_members(root, &manifest)?;

        Ok(Self {
            root: root.to_path_buf(),
            manifest,
        })
    }

    pub(crate) fn root(&self) -> &Path {
        &self.root
    }

    pub(crate) fn release_id(&self) -> &str {
        &self.manifest.release_id
    }

    pub(crate) fn platform_target_id(&self) -> &str {
        &self.manifest.platform_target_id
    }

    pub(crate) fn artifact_path(&self, name: &str) -> Result<PathBuf, String> {
        if !self
            .manifest
            .artifacts
            .iter()
            .any(|artifact| artifact.name == name)
        {
            return Err(format!(
                "Release does not contain required artifact '{name}'"
            ));
        }
        Ok(self.root.join(name))
    }

    pub(crate) fn copy_to(&self, destination: &Path) -> Result<Self, String> {
        if destination.exists() {
            return Err(format!(
                "Runtime Release destination already exists: {}",
                destination.display()
            ));
        }
        fs::create_dir(destination).map_err(|error| {
            format!(
                "cannot create staged Runtime Release '{}': {error}",
                destination.display()
            )
        })?;
        copy_release_file(
            &self.root.join("manifest.json"),
            &destination.join("manifest.json"),
        )?;
        for artifact in &self.manifest.artifacts {
            copy_release_file(
                &self.root.join(&artifact.name),
                &destination.join(&artifact.name),
            )?;
        }
        Self::open(destination)
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ReleaseManifest {
    schema: String,
    release_id: String,
    platform_target_id: String,
    artifacts: Vec<ArtifactRecord>,
}

impl ReleaseManifest {
    fn validate(&self, directory_id: &str) -> Result<(), String> {
        if self.schema != RELEASE_SCHEMA {
            return Err(format!(
                "unsupported Release manifest schema '{}'",
                self.schema
            ));
        }
        assert_release_id(&self.release_id)?;
        if self.release_id != directory_id {
            return Err(format!(
                "Release manifest identity '{}' does not match directory '{directory_id}'",
                self.release_id
            ));
        }
        assert_safe_segment(&self.platform_target_id, "PlatformTargetId")?;
        if self.artifacts.is_empty() || self.artifacts.len() > MAXIMUM_ARTIFACTS {
            return Err(format!(
                "Release must contain 1 to {MAXIMUM_ARTIFACTS} artifacts"
            ));
        }

        let mut names = HashSet::new();
        let mut case_insensitive_names = HashSet::new();
        for artifact in &self.artifacts {
            assert_safe_segment(&artifact.name, "artifact name")?;
            if artifact.length == 0 || artifact.length > MAXIMUM_ARTIFACT_BYTES {
                return Err(format!(
                    "Release artifact '{}' has an invalid length",
                    artifact.name
                ));
            }
            assert_sha256(&artifact.sha256, "artifact checksum")?;
            if !names.insert(artifact.name.clone()) {
                return Err(format!("duplicate Release artifact '{}'", artifact.name));
            }
            if !case_insensitive_names.insert(artifact.name.to_ascii_lowercase()) {
                return Err(format!(
                    "case-insensitive duplicate Release artifact '{}'",
                    artifact.name
                ));
            }
        }
        for required in [ADMIN_ARTIFACT_NAME, ENTRY_ARTIFACT_NAME] {
            if !names.contains(required) {
                return Err(format!("Release is missing required artifact '{required}'"));
            }
        }

        let computed = compute_release_id(&self.platform_target_id, &self.artifacts);
        if computed != self.release_id {
            return Err(format!(
                "Release identity '{}' does not match its manifest content",
                self.release_id
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct ArtifactRecord {
    name: String,
    length: u64,
    sha256: String,
}

fn validate_members(root: &Path, manifest: &ReleaseManifest) -> Result<(), String> {
    let expected: HashSet<&str> = std::iter::once("manifest.json")
        .chain(
            manifest
                .artifacts
                .iter()
                .map(|artifact| artifact.name.as_str()),
        )
        .collect();
    let entries = fs::read_dir(root)
        .map_err(|error| format!("cannot enumerate Release '{}': {error}", root.display()))?;
    let mut actual = HashSet::new();
    for entry in entries {
        let entry = entry.map_err(|error| format!("cannot enumerate Release member: {error}"))?;
        let name = entry
            .file_name()
            .to_str()
            .ok_or_else(|| "Release contains a non-Unicode member name".to_owned())?
            .to_owned();
        assert_regular_file(&entry.path(), "Release member")?;
        actual.insert(name);
    }
    if actual.len() != expected.len() || actual.iter().any(|name| !expected.contains(name.as_str()))
    {
        return Err(format!("Release membership is invalid: {}", root.display()));
    }

    for artifact in &manifest.artifacts {
        let path = root.join(&artifact.name);
        let metadata = assert_regular_file(&path, "Release artifact")?;
        if metadata.len() != artifact.length {
            return Err(format!(
                "Release artifact length is invalid: {}",
                path.display()
            ));
        }
        if sha256_file(&path)? != artifact.sha256 {
            return Err(format!(
                "Release artifact checksum is invalid: {}",
                path.display()
            ));
        }
    }
    Ok(())
}

fn copy_release_file(source: &Path, destination: &Path) -> Result<(), String> {
    assert_regular_file(source, "Runtime Release copy source")?;
    fs::copy(source, destination).map_err(|error| {
        format!(
            "cannot copy Release member '{}' to '{}': {error}",
            source.display(),
            destination.display()
        )
    })?;
    fs::OpenOptions::new()
        .write(true)
        .open(destination)
        .and_then(|file| file.sync_all())
        .map_err(|error| {
            format!(
                "cannot flush copied Release member '{}': {error}",
                destination.display()
            )
        })
}

fn sha256_file(path: &Path) -> Result<String, String> {
    let mut file = File::open(path)
        .map_err(|error| format!("cannot open Release artifact '{}': {error}", path.display()))?;
    let mut algorithm = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let count = file.read(&mut buffer).map_err(|error| {
            format!("cannot hash Release artifact '{}': {error}", path.display())
        })?;
        if count == 0 {
            break;
        }
        algorithm.update(&buffer[..count]);
    }
    Ok(hex_lower(&algorithm.finalize()))
}

fn compute_release_id(platform_target_id: &str, artifacts: &[ArtifactRecord]) -> String {
    let mut lines = vec![
        RELEASE_SCHEMA.to_owned(),
        format!("target={platform_target_id}"),
    ];
    for artifact in artifacts {
        lines.push(format!("artifact={}", artifact.name));
        lines.push(format!("length={}", artifact.length));
        lines.push(format!("sha256={}", artifact.sha256));
    }
    let mut algorithm = Sha256::new();
    algorithm.update(lines.join("\n").as_bytes());
    hex_lower(&algorithm.finalize())
}

fn hex_lower(bytes: &[u8]) -> String {
    let mut result = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use std::fmt::Write;
        write!(&mut result, "{byte:02x}").expect("writing to a String cannot fail");
    }
    result
}

fn assert_release_id(value: &str) -> Result<(), String> {
    if value.len() == 64
        && value
            .as_bytes()
            .iter()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(byte))
    {
        Ok(())
    } else {
        Err(format!("invalid ReleaseId '{value}'"))
    }
}

fn assert_sha256(value: &str, description: &str) -> Result<(), String> {
    if value.len() == 64
        && value
            .as_bytes()
            .iter()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(byte))
    {
        Ok(())
    } else {
        Err(format!("invalid {description} '{value}'"))
    }
}

fn assert_safe_segment(value: &str, description: &str) -> Result<(), String> {
    let bytes = value.as_bytes();
    let valid = bytes
        .first()
        .is_some_and(|byte| byte.is_ascii_alphanumeric())
        && bytes
            .iter()
            .skip(1)
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'+' | b'-'));
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

fn same_path_text(left: &Path, right: &Path) -> bool {
    left.to_string_lossy()
        .replace('/', "\\")
        .eq_ignore_ascii_case(&right.to_string_lossy().replace('/', "\\"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn computes_the_bootstrap_release_identity_contract() {
        let artifacts = vec![ArtifactRecord {
            name: "entry.exe".to_owned(),
            length: 5,
            sha256: "a".repeat(64),
        }];
        let id = compute_release_id("x86_64-pc-windows-msvc", &artifacts);
        assert_eq!(id.len(), 64);
        assert!(
            id.bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
        );
    }

    #[test]
    fn rejects_unsafe_windows_release_member_names() {
        for name in ["con.exe", "LPT1", "member.", "../member"] {
            assert!(
                assert_safe_segment(name, "artifact name").is_err(),
                "{name}"
            );
        }
        assert!(assert_safe_segment("swaw-harness-admin.exe", "artifact name").is_ok());
    }
}
