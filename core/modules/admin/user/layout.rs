use std::fs;
use std::path::{Path, PathBuf};

use swaw_harness_core_protocol::{InstalledModules, ModuleId, SkillMap, Version, VersionSelector};

use super::UserId;

const ADMIN_USER_ID: &str = "admin";
const HOST_MODULE_ID: &str = "swaw/core/host";
const HOST_EXECUTABLE: &str = "swaw-harness-core.exe";
const MINIMUM_MANAGED_USER_HOST_VERSION: &str = "1.0.8";
const PLATFORM_TARGET_ID: &str = "x86_64-pc-windows-msvc";
const MAXIMUM_TREE_DEPTH: usize = 64;

pub(super) struct Layout {
    pub(super) data_home: PathBuf,
    pub(super) admin_home: PathBuf,
    pub(super) admin_cli: PathBuf,
    pub(super) user_home: PathBuf,
    pub(super) user_cli: PathBuf,
}

impl Layout {
    pub(super) fn discover(invocation_user_home: &Path, user_id: &UserId) -> Result<Self, String> {
        if !invocation_user_home.is_absolute() {
            return Err(format!(
                "invoking UserHome must be absolute: {}",
                invocation_user_home.display()
            ));
        }
        require_regular_directory(invocation_user_home, "invoking UserHome")?;
        let data_home = invocation_user_home
            .parent()
            .ok_or_else(|| "cannot derive DataHome from invoking UserHome".to_owned())?
            .to_owned();
        require_named_directory(&data_home, "data", "DataHome")?;
        let admin_home = find_named_entry(&data_home, ADMIN_USER_ID)?
            .ok_or_else(|| "DataHome does not contain the Admin UserHome".to_owned())?;
        require_named_directory(&admin_home, ADMIN_USER_ID, "Admin UserHome")?;
        let admin_cli = find_named_entry(&data_home, "admin.exe")?
            .ok_or_else(|| "DataHome does not contain the Admin User CLI executable".to_owned())?;
        require_exact_path(
            &admin_cli,
            &data_home.join("admin.exe"),
            "Admin User CLI executable",
        )?;
        Ok(Self {
            user_home: data_home.join(user_id.as_str()),
            user_cli: data_home.join(format!("{user_id}.exe")),
            data_home,
            admin_home,
            admin_cli,
        })
    }
}

pub(super) fn validate_core_map(user_home: &Path) -> Result<PathBuf, String> {
    let map = SkillMap::open_core(user_home)?;
    map.validate()?;
    Ok(map.root().to_owned())
}

pub(super) fn validate_host_pointer(user_home: &Path, data_home: &Path) -> Result<Version, String> {
    let host_root = find_named_entry(user_home, "host")?.ok_or_else(|| {
        format!(
            "UserHome is missing Core Host selection root: {}",
            user_home.display()
        )
    })?;
    require_named_directory(&host_root, "host", "Core Host selection root")?;
    let pointer_name = host_pointer_name();
    let pointer = find_named_entry(&host_root, &pointer_name)?.ok_or_else(|| {
        format!(
            "Core Host version pointer does not exist: {}",
            host_root.join(&pointer_name).display()
        )
    })?;
    require_exact_path(
        &pointer,
        &host_root.join(&pointer_name),
        "Core Host version pointer",
    )?;
    let metadata = fs::symlink_metadata(&pointer).map_err(|error| {
        format!(
            "cannot inspect Core Host version pointer '{}': {error}",
            pointer.display()
        )
    })?;
    if !metadata.is_file() || metadata_is_reparse(&metadata) || metadata.len() > 128 {
        return Err(format!(
            "Core Host version pointer must be a bounded regular non-reparse file: {}",
            pointer.display()
        ));
    }
    let bytes = fs::read(&pointer).map_err(|error| {
        format!(
            "cannot read Core Host version pointer '{}': {error}",
            pointer.display()
        )
    })?;
    let text = bytes.strip_suffix(b"\n").ok_or_else(|| {
        format!(
            "Core Host version pointer must end with one newline: {}",
            pointer.display()
        )
    })?;
    let text = text.strip_suffix(b"\r").unwrap_or(text);
    if text.is_empty() || !text.is_ascii() || text.contains(&b'\n') || text.contains(&b'\r') {
        return Err(format!(
            "Core Host version pointer has invalid framing: {}",
            pointer.display()
        ));
    }
    let version = Version::parse(std::str::from_utf8(text).expect("ASCII is UTF-8"))?;
    let release = InstalledModules::open(data_home)?.select(
        &ModuleId::parse(HOST_MODULE_ID)?,
        VersionSelector::Exact(version),
        PLATFORM_TARGET_ID,
        HOST_EXECUTABLE,
    )?;
    require_managed_user_host_version(release.version())?;
    Ok(release.version())
}

fn require_managed_user_host_version(version: Version) -> Result<(), String> {
    let minimum = Version::parse(MINIMUM_MANAGED_USER_HOST_VERSION)
        .expect("managed-user Core Host minimum must be a valid version");
    if version.major() != minimum.major() || version < minimum {
        return Err(format!(
            "Core Host Module Release version '{version}' is not approved for swaw.harness.user/v1; expected a 1.x version at or above {minimum}"
        ));
    }
    Ok(())
}

pub(super) fn copy_tree(source: &Path, target: &Path, depth: usize) -> Result<(), String> {
    if depth > MAXIMUM_TREE_DEPTH {
        return Err(format!(
            "Core Skill Map exceeds {MAXIMUM_TREE_DEPTH} levels: {}",
            source.display()
        ));
    }
    require_regular_directory(source, "source Core Skill Map directory")?;
    fs::create_dir(target).map_err(|error| {
        format!(
            "cannot create staged Skill Map directory '{}': {error}",
            target.display()
        )
    })?;
    for entry in fs::read_dir(source).map_err(|error| {
        format!(
            "cannot enumerate Core Skill Map '{}': {error}",
            source.display()
        )
    })? {
        let entry = entry.map_err(|error| format!("cannot enumerate Core Skill Map: {error}"))?;
        let source_path = entry.path();
        let target_path = target.join(entry.file_name());
        let metadata = fs::symlink_metadata(&source_path).map_err(|error| {
            format!(
                "cannot inspect Core Skill Map entry '{}': {error}",
                source_path.display()
            )
        })?;
        if metadata_is_reparse(&metadata) {
            return Err(format!(
                "Core Skill Map cannot contain a reparse point: {}",
                source_path.display()
            ));
        }
        if metadata.is_dir() {
            copy_tree(&source_path, &target_path, depth + 1)?;
        } else if metadata.is_file() {
            fs::copy(&source_path, &target_path).map_err(|error| {
                format!(
                    "cannot copy Core Skill Map file '{}': {error}",
                    source_path.display()
                )
            })?;
        } else {
            return Err(format!(
                "Core Skill Map entry is not a regular file or directory: {}",
                source_path.display()
            ));
        }
    }
    Ok(())
}

pub(super) fn find_named_entry(parent: &Path, expected: &str) -> Result<Option<PathBuf>, String> {
    let mut result = None;
    for entry in fs::read_dir(parent)
        .map_err(|error| format!("cannot enumerate '{}': {error}", parent.display()))?
    {
        let entry =
            entry.map_err(|error| format!("cannot enumerate '{}': {error}", parent.display()))?;
        let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        if name.eq_ignore_ascii_case(expected) {
            if name != expected {
                return Err(format!(
                    "non-canonical name '{name}'; expected '{expected}': {}",
                    entry.path().display()
                ));
            }
            if result.replace(entry.path()).is_some() {
                return Err(format!(
                    "ambiguous entries named '{expected}' in '{}'",
                    parent.display()
                ));
            }
        }
    }
    Ok(result)
}

pub(super) fn require_regular_directory(path: &Path, description: &str) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect {description} '{}': {error}", path.display()))?;
    if metadata.is_dir() && !metadata_is_reparse(&metadata) {
        Ok(())
    } else {
        Err(format!(
            "{description} must be a regular non-reparse directory: {}",
            path.display()
        ))
    }
}

pub(super) fn remove_stage(path: &Path) -> Result<(), String> {
    require_regular_directory(path, "staged UserHome")?;
    fs::remove_dir_all(path).map_err(|error| {
        format!(
            "cannot remove staged UserHome '{}': {error}",
            path.display()
        )
    })
}

pub(super) fn require_exact_path(
    actual: &Path,
    expected: &Path,
    description: &str,
) -> Result<(), String> {
    if actual == expected {
        Ok(())
    } else {
        Err(format!(
            "{description} has an unexpected path: {}; expected {}",
            actual.display(),
            expected.display()
        ))
    }
}

pub(super) fn host_pointer_name() -> String {
    format!("current.{PLATFORM_TARGET_ID}")
}

pub(super) fn user_home_stage(data_home: &Path, user_id: &UserId) -> PathBuf {
    data_home.join(format!(".user-{user_id}.tmp"))
}

pub(super) fn remove_stale_user_home_stage(
    data_home: &Path,
    user_id: &UserId,
) -> Result<(), String> {
    let expected = user_home_stage(data_home, user_id);
    let name = expected
        .file_name()
        .and_then(|value| value.to_str())
        .expect("UserId produces a Unicode staged UserHome name");
    let Some(actual) = find_named_entry(data_home, name)? else {
        return Ok(());
    };
    require_exact_path(&actual, &expected, "staged UserHome")?;
    remove_stage(&actual)
}

fn require_named_directory(path: &Path, name: &str, description: &str) -> Result<(), String> {
    if path.file_name().and_then(|value| value.to_str()) != Some(name) {
        return Err(format!(
            "{description} must be named '{name}': {}",
            path.display()
        ));
    }
    require_regular_directory(path, description)
}

fn metadata_is_reparse(metadata: &fs::Metadata) -> bool {
    if metadata.file_type().is_symlink() {
        return true;
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        metadata.file_attributes() & 0x400 != 0
    }
    #[cfg(not(windows))]
    {
        false
    }
}
