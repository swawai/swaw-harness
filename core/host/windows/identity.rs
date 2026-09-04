use std::fs::{self, File};
use std::io::Read;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::fs::MetadataExt;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};
use swaw_harness_core_protocol::{
    InstalledModules, ModuleId, UserLifecycle, UserRecord, Version, VersionSelector,
};

const REPARSE_POINT: u32 = 0x400;
const HOST_MODULE_ID: &str = "swaw/core/host";
const HOST_EXECUTABLE: &str = "swaw-harness-core.exe";
const PLATFORM_TARGET_ID: &str = "x86_64-pc-windows-msvc";

#[derive(Clone, Debug)]
pub(super) struct HostIdentity {
    user_id: String,
    user_home: PathBuf,
    data_home: PathBuf,
    pipe_name: Vec<u16>,
    mutex_name: Vec<u16>,
}

impl HostIdentity {
    pub(super) fn discover() -> Result<Self, String> {
        let user_id = discover_user_id()?;
        let executable = std::env::current_exe()
            .map_err(|error| format!("cannot locate Core Host executable: {error}"))?;
        if executable.file_name().and_then(|name| name.to_str()) != Some(HOST_EXECUTABLE) {
            return Err(format!(
                "Core Host executable has an unexpected name: {}",
                executable.display()
            ));
        }
        assert_regular_file(&executable, "Core Host executable")?;
        let release_root = parent(&executable, "Core Host Module Release")?;
        assert_regular_directory(release_root, "Core Host Module Release")?;
        let version_text = release_root
            .file_name()
            .and_then(|name| name.to_str())
            .ok_or_else(|| "Core Host Module Release Version is not Unicode".to_owned())?;
        let version = Version::parse(version_text)?;

        let platform_root = named_parent(release_root, PLATFORM_TARGET_ID, "platform directory")?;
        let module_root = named_parent(platform_root, "host", "Core Host module directory")?;
        let group_root = named_parent(module_root, "core", "Core Host group directory")?;
        let publisher_root = named_parent(group_root, "swaw", "Core Host publisher directory")?;
        let modules_root = named_parent(publisher_root, "modules", "shared modules root")?;
        let admin_root = named_parent(modules_root, "admin", "Admin UserHome")?;
        let data_home = named_parent(admin_root, "data", "DataHome")?.to_owned();
        let harness_root = parent(&data_home, "HarnessRoot")?.to_owned();
        assert_regular_directory(&harness_root, "HarnessRoot")?;

        let modules = InstalledModules::open(&data_home)?;
        let module = ModuleId::parse(HOST_MODULE_ID)?;
        let selected = modules.select(
            &module,
            VersionSelector::Exact(version),
            PLATFORM_TARGET_ID,
            HOST_EXECUTABLE,
        )?;
        if normalized_path_units(selected.executable_path()) != normalized_path_units(&executable) {
            return Err(format!(
                "Core Host executable is not the selected Module Release executable: {}",
                executable.display()
            ));
        }

        let user_home = find_exact_data_entry(&data_home, &user_id, "UserHome")?;
        assert_regular_directory(&user_home, "UserHome")?;
        validate_user_lifecycle(&data_home, &user_home, &user_id)?;
        let suffix = endpoint_suffix(&harness_root, &user_id);

        Ok(Self {
            user_id,
            user_home,
            data_home,
            pipe_name: wide_null(&format!(r"\\.\pipe\swaw-harness-v2-{suffix}")),
            mutex_name: wide_null(&format!(r"Local\swaw-harness-core-v2-{suffix}")),
        })
    }

    pub(super) fn user_id(&self) -> &str {
        &self.user_id
    }

    pub(super) fn user_home(&self) -> &Path {
        &self.user_home
    }

    pub(super) fn data_home(&self) -> &Path {
        &self.data_home
    }

    pub(super) fn pipe_name(&self) -> &[u16] {
        &self.pipe_name
    }

    pub(super) fn mutex_name(&self) -> &[u16] {
        &self.mutex_name
    }

    pub(super) fn accepts_user_home(&self, value: &Path) -> bool {
        normalized_path_units(value) == normalized_path_units(&self.user_home)
    }
}

fn validate_user_lifecycle(
    data_home: &Path,
    user_home: &Path,
    user_id: &str,
) -> Result<(), String> {
    if user_id == "admin" {
        return Ok(());
    }
    let record = UserRecord::read(user_home, user_id)?;
    if record.lifecycle() != UserLifecycle::Active {
        return Err(format!(
            "Harness User is not active: {}",
            user_home.display()
        ));
    }
    let cli_name = format!("{user_id}.exe");
    let user_cli = find_exact_data_entry(data_home, &cli_name, "User CLI executable")?;
    let metadata = assert_regular_file(&user_cli, "User CLI executable")?;
    if metadata.len() != record.user_cli().length()
        || sha256_file(&user_cli)? != record.user_cli().sha256()
    {
        return Err(format!(
            "Harness User CLI executable does not match user.json: {}",
            user_cli.display()
        ));
    }
    Ok(())
}

fn discover_user_id() -> Result<String, String> {
    let mut arguments = std::env::args_os();
    let _ = arguments.next();
    let user_id = arguments
        .next()
        .ok_or_else(|| "Core Host requires exactly one UserId argument".to_owned())?
        .into_string()
        .map_err(|_| "Core Host UserId is not Unicode".to_owned())?;
    if arguments.next().is_some() {
        return Err("Core Host requires exactly one UserId argument".to_owned());
    }
    validate_user_id(&user_id)?;
    Ok(user_id)
}

fn named_parent<'a>(path: &'a Path, expected: &str, description: &str) -> Result<&'a Path, String> {
    let result = parent(path, description)?;
    assert_regular_directory(result, description)?;
    if result.file_name().and_then(|name| name.to_str()) != Some(expected) {
        return Err(format!(
            "{description} must be named '{expected}': {}",
            result.display()
        ));
    }
    Ok(result)
}

fn find_exact_data_entry(
    data_home: &Path,
    expected_name: &str,
    description: &str,
) -> Result<PathBuf, String> {
    let mut matching = Vec::new();
    for entry in fs::read_dir(data_home).map_err(|error| {
        format!(
            "cannot enumerate DataHome '{}': {error}",
            data_home.display()
        )
    })? {
        let entry = entry.map_err(|error| format!("cannot enumerate UserHome: {error}"))?;
        let name = entry
            .file_name()
            .into_string()
            .map_err(|_| "DataHome contains a non-Unicode name".to_owned())?;
        if name.eq_ignore_ascii_case(expected_name) {
            matching.push((name, entry.path()));
        }
    }
    match matching.as_slice() {
        [(name, path)] if name == expected_name => Ok(path.clone()),
        [(name, path)] => Err(format!(
            "{description} has non-canonical name '{name}'; expected '{expected_name}': {}",
            path.display()
        )),
        [] => Err(format!("{description} does not exist: {expected_name}")),
        _ => Err(format!(
            "DataHome contains ambiguous {description} names for: {expected_name}"
        )),
    }
}

fn sha256_file(path: &Path) -> Result<String, String> {
    let mut file = File::open(path).map_err(|error| {
        format!(
            "cannot open User CLI executable '{}': {error}",
            path.display()
        )
    })?;
    let mut digest = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let count = file.read(&mut buffer).map_err(|error| {
            format!(
                "cannot hash User CLI executable '{}': {error}",
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

fn parent<'a>(path: &'a Path, description: &str) -> Result<&'a Path, String> {
    path.parent()
        .ok_or_else(|| format!("cannot derive {description} from '{}'", path.display()))
}

fn assert_regular_directory(path: &Path, description: &str) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect {description} '{}': {error}", path.display()))?;
    if !metadata.is_dir() || metadata.file_attributes() & REPARSE_POINT != 0 {
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
    if !metadata.is_file() || metadata.file_attributes() & REPARSE_POINT != 0 {
        Err(format!(
            "{description} is not a regular non-reparse file: {}",
            path.display()
        ))
    } else {
        Ok(metadata)
    }
}

fn validate_user_id(value: &str) -> Result<(), String> {
    let bytes = value.as_bytes();
    let valid = bytes.first().is_some_and(u8::is_ascii_lowercase)
        && bytes
            .iter()
            .skip(1)
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || *byte == b'-')
        && bytes
            .last()
            .is_some_and(|byte| byte.is_ascii_alphanumeric())
        && !value.contains("--")
        && value.len() <= 16;
    let reserved = matches!(value, "con" | "prn" | "aux" | "nul")
        || matches!(bytes, [b'c', b'o', b'm', b'1'..=b'9'])
        || matches!(bytes, [b'l', b'p', b't', b'1'..=b'9']);
    if !valid || reserved {
        Err(format!("Core Host UserId is invalid: {value}"))
    } else {
        Ok(())
    }
}

fn endpoint_suffix(harness_root: &Path, user_id: &str) -> String {
    let mut hash = 0xcbf29ce484222325_u64;
    for unit in normalized_path_units(harness_root)
        .into_iter()
        .chain([0])
        .chain(user_id.encode_utf16())
    {
        hash ^= u64::from(unit);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}-{user_id}")
}

fn normalized_path_units(path: &Path) -> Vec<u16> {
    let mut units: Vec<_> = path.as_os_str().encode_wide().collect();
    if units.starts_with(&[b'\\' as u16, b'\\' as u16, b'?' as u16, b'\\' as u16]) {
        units.drain(..4);
        if units.starts_with(&[b'U' as u16, b'N' as u16, b'C' as u16, b'\\' as u16]) {
            units.splice(..4, [b'\\' as u16, b'\\' as u16]);
        }
    }
    while units.last().is_some_and(|unit| matches!(*unit, 47 | 92)) {
        units.pop();
    }
    for unit in &mut units {
        if *unit == b'/' as u16 {
            *unit = b'\\' as u16;
        } else if (*unit as u8).is_ascii_uppercase() && *unit <= u16::from(u8::MAX) {
            *unit += u16::from(b'a' - b'A');
        }
    }
    units
}

fn wide_null(value: &str) -> Vec<u16> {
    value.encode_utf16().chain([0]).collect()
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::Path;
    use std::sync::atomic::{AtomicU64, Ordering};

    use swaw_harness_core_protocol::{UserCliIdentity, UserLifecycle, UserRecord};

    use super::{
        endpoint_suffix, normalized_path_units, validate_user_id, validate_user_lifecycle,
    };

    static NEXT_FIXTURE: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn endpoint_is_stable_across_ascii_path_case_and_separators() {
        assert_eq!(
            endpoint_suffix(Path::new(r"D:\Harness"), "admin"),
            endpoint_suffix(Path::new("d:/harness/"), "admin")
        );
    }

    #[test]
    fn verbatim_prefix_does_not_change_path_identity() {
        assert_eq!(
            normalized_path_units(Path::new(r"\\?\D:\Harness")),
            normalized_path_units(Path::new(r"D:\Harness"))
        );
    }

    #[test]
    fn user_id_is_small_canonical_ascii() {
        assert!(validate_user_id("admin").is_ok());
        assert!(validate_user_id("Admin").is_err());
        assert!(validate_user_id("1user").is_err());
        assert!(validate_user_id("user_name").is_err());
        assert!(validate_user_id("com1").is_err());
        assert!(validate_user_id("a2345678901234567").is_err());
    }

    #[test]
    fn admin_does_not_require_a_managed_user_record() {
        let missing = std::env::temp_dir().join("swaw-harness-missing-admin-home");
        assert!(validate_user_lifecycle(&missing, &missing, "admin").is_ok());
    }

    #[test]
    fn ordinary_user_requires_an_active_strict_record() {
        let user_home = temporary_user_home("lifecycle");
        let data_home = user_home.parent().unwrap();
        let user_cli = data_home.join("alice.exe");
        fs::write(&user_cli, b"cli").unwrap();
        let creating = UserRecord::new(
            "alice",
            UserLifecycle::Creating,
            UserCliIdentity::new(3, super::sha256_file(&user_cli).unwrap()).unwrap(),
        )
        .unwrap();
        fs::write(user_home.join("user.json"), creating.encode().unwrap()).unwrap();
        assert!(validate_user_lifecycle(data_home, &user_home, "alice").is_err());

        fs::write(
            user_home.join("user.json"),
            creating
                .with_lifecycle(UserLifecycle::Active)
                .encode()
                .unwrap(),
        )
        .unwrap();
        assert!(validate_user_lifecycle(data_home, &user_home, "alice").is_ok());
        fs::write(&user_cli, b"bad").unwrap();
        assert!(validate_user_lifecycle(data_home, &user_home, "alice").is_err());
        assert!(validate_user_lifecycle(data_home, &user_home, "bob").is_err());

        fs::remove_dir_all(data_home).unwrap();
    }

    fn temporary_user_home(label: &str) -> std::path::PathBuf {
        let sequence = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
        let root = std::env::temp_dir().join(format!(
            "swaw-harness-host-{label}-{}-{sequence}",
            std::process::id()
        ));
        let path = root.join("alice");
        fs::create_dir(&root).unwrap();
        fs::create_dir(&path).unwrap();
        path
    }
}
