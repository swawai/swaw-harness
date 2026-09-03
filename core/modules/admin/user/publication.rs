#[cfg(windows)]
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};
use swaw_harness_core_protocol::{UserCliIdentity, UserRecord};

use super::layout::{find_named_entry, require_exact_path};

const MAXIMUM_USER_CLI_BYTES: u64 = 1024 * 1024;

#[derive(Clone, Debug)]
pub(super) struct UserCliArtifact {
    bytes: Vec<u8>,
    identity: UserCliIdentity,
}

impl UserCliArtifact {
    pub(super) fn read(path: &Path) -> Result<Self, String> {
        let bytes = read_regular(path, "Admin User CLI executable", MAXIMUM_USER_CLI_BYTES)?;
        let identity = UserCliIdentity::new(bytes.len() as u64, sha256(&bytes))?;
        Ok(Self { bytes, identity })
    }

    pub(super) fn identity(&self) -> &UserCliIdentity {
        &self.identity
    }

    pub(super) fn install_new(&self, target: &Path) -> Result<(), String> {
        let temporary = publication_stage(target)?;
        let result = (|| {
            write_new_synced(&temporary, &self.bytes)?;
            self.verify(&temporary)?;
            fs::rename(&temporary, target).map_err(|error| {
                format!(
                    "cannot commit User CLI executable '{}': {error}",
                    target.display()
                )
            })?;
            self.verify(target)
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temporary);
        }
        result
    }

    pub(super) fn verify(&self, path: &Path) -> Result<(), String> {
        verify_identity(path, &self.identity)
    }
}

pub(super) fn verify_identity(path: &Path, expected: &UserCliIdentity) -> Result<(), String> {
    let bytes = read_regular(path, "Harness User CLI executable", MAXIMUM_USER_CLI_BYTES)?;
    if bytes.len() as u64 != expected.length() || sha256(&bytes) != expected.sha256() {
        return Err(format!(
            "Harness User CLI executable does not match user.json: {}",
            path.display()
        ));
    }
    Ok(())
}

pub(super) fn write_record_new(path: &Path, record: &UserRecord) -> Result<(), String> {
    write_new_synced(path, &record.encode()?)
}

pub(super) fn replace_record(path: &Path, record: &UserRecord) -> Result<(), String> {
    require_regular_file(path, "Harness User record")?;
    let temporary = publication_stage(path)?;
    let result = (|| {
        write_new_synced(&temporary, &record.encode()?)?;
        replace_file(path, &temporary).map_err(|error| {
            format!(
                "cannot atomically activate Harness User record '{}': {error}",
                path.display()
            )
        })
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

pub(super) fn write_new_synced(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|error| format!("cannot create '{}': {error}", path.display()))?;
    file.write_all(bytes)
        .and_then(|()| file.sync_all())
        .map_err(|error| format!("cannot write '{}': {error}", path.display()))
}

fn read_regular(path: &Path, description: &str, maximum: u64) -> Result<Vec<u8>, String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect {description} '{}': {error}", path.display()))?;
    if !metadata.is_file()
        || metadata_is_reparse(&metadata)
        || metadata.len() == 0
        || metadata.len() > maximum
    {
        return Err(format!(
            "{description} must be a bounded regular non-reparse file: {}",
            path.display()
        ));
    }
    let length = metadata.len();
    let mut bytes = Vec::with_capacity(length as usize);
    File::open(path)
        .and_then(|file| file.take(maximum + 1).read_to_end(&mut bytes))
        .map_err(|error| format!("cannot read {description} '{}': {error}", path.display()))?;
    let final_length = fs::metadata(path)
        .map_err(|error| {
            format!(
                "cannot reinspect {description} '{}': {error}",
                path.display()
            )
        })?
        .len();
    if bytes.len() as u64 != length || final_length != length {
        return Err(format!(
            "{description} changed while it was read: {}",
            path.display()
        ));
    }
    Ok(bytes)
}

fn require_regular_file(path: &Path, description: &str) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect {description} '{}': {error}", path.display()))?;
    if !metadata.is_file() || metadata_is_reparse(&metadata) {
        return Err(format!(
            "{description} must be a regular non-reparse file: {}",
            path.display()
        ));
    }
    Ok(())
}

fn sha256(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

pub(super) fn remove_stale_publication_stage(
    target: &Path,
    description: &str,
) -> Result<(), String> {
    let expected = publication_stage(target)?;
    let directory = expected
        .parent()
        .ok_or_else(|| format!("{description} has no parent directory"))?;
    let name = expected
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| format!("{description} staged name is not Unicode"))?;
    let Some(actual) = find_named_entry(directory, name)? else {
        return Ok(());
    };
    require_exact_path(&actual, &expected, description)?;
    require_regular_file(&actual, description)?;
    fs::remove_file(&actual).map_err(|error| {
        format!(
            "cannot remove stale {description} '{}': {error}",
            actual.display()
        )
    })
}

pub(super) fn publication_stage(target: &Path) -> Result<PathBuf, String> {
    let directory = target
        .parent()
        .ok_or_else(|| "publication target has no parent directory".to_owned())?;
    let name = target
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| "publication target name is not Unicode".to_owned())?;
    Ok(directory.join(format!(".{name}.tmp")))
}

#[cfg(windows)]
fn replace_file(path: &Path, temporary: &Path) -> io::Result<()> {
    use windows_sys::Win32::Storage::FileSystem::ReplaceFileW;

    let path = canonical_sibling(path)?;
    let temporary = canonical_sibling(temporary)?;
    let path = null_terminated(path.as_os_str());
    let temporary = null_terminated(temporary.as_os_str());
    let succeeded = unsafe {
        ReplaceFileW(
            path.as_ptr(),
            temporary.as_ptr(),
            std::ptr::null(),
            0,
            std::ptr::null(),
            std::ptr::null(),
        )
    };
    if succeeded == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[cfg(not(windows))]
fn replace_file(path: &Path, temporary: &Path) -> io::Result<()> {
    fs::rename(temporary, path)
}

#[cfg(windows)]
fn canonical_sibling(path: &Path) -> io::Result<PathBuf> {
    let directory = path.parent().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "publication path has no parent",
        )
    })?;
    let name = path.file_name().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "publication path has no file name",
        )
    })?;
    Ok(fs::canonicalize(directory)?.join(name))
}

#[cfg(windows)]
fn null_terminated(value: &OsStr) -> Vec<u16> {
    use std::os::windows::ffi::OsStrExt;

    value.encode_wide().chain([0]).collect()
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
