use std::fs::{self, File, OpenOptions};
use std::io;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

use super::layout::{find_named_entry, require_exact_path};

const LOCK_FILE_NAME: &str = "user.lock";
const LOCK_ATTEMPTS: usize = 600;
const LOCK_RETRY_DELAY: Duration = Duration::from_millis(50);

pub(super) struct UserLock {
    _file: File,
}

impl UserLock {
    pub(super) fn acquire(admin_home: &Path) -> Result<Self, String> {
        Self::acquire_with(admin_home, LOCK_ATTEMPTS, LOCK_RETRY_DELAY)
    }

    fn acquire_with(
        admin_home: &Path,
        attempts: usize,
        retry_delay: Duration,
    ) -> Result<Self, String> {
        require_regular_directory(admin_home, "Admin UserHome")?;
        let path = resolve_lock_path(admin_home)?;
        let attempts = attempts.max(1);
        for attempt in 0..attempts {
            match open_exclusive(&path) {
                Ok(file) => {
                    let actual =
                        find_named_entry(admin_home, LOCK_FILE_NAME)?.ok_or_else(|| {
                            format!(
                                "opened Harness User lifecycle lock disappeared: {}",
                                path.display()
                            )
                        })?;
                    require_exact_path(&actual, &path, "Harness User lifecycle lock")?;
                    let metadata = file.metadata().map_err(|error| {
                        format!(
                            "cannot inspect opened Harness User lifecycle lock '{}': {error}",
                            path.display()
                        )
                    })?;
                    if !metadata.is_file() || metadata_is_reparse(&metadata) {
                        return Err(format!(
                            "Harness User lifecycle lock must be a regular non-reparse file: {}",
                            path.display()
                        ));
                    }
                    return Ok(Self { _file: file });
                }
                Err(error) if is_contended(&error) && attempt + 1 < attempts => {
                    thread::sleep(retry_delay)
                }
                Err(error) => {
                    let activity = if is_contended(&error) {
                        "timed out waiting for"
                    } else {
                        "cannot acquire"
                    };
                    return Err(format!(
                        "{activity} Harness User lifecycle lock '{}': {error}",
                        path.display()
                    ));
                }
            }
        }
        unreachable!("at least one lock attempt is required")
    }

    #[cfg(test)]
    pub(super) fn acquire_for_test(
        admin_home: &Path,
        attempts: usize,
        retry_delay: Duration,
    ) -> Result<Self, String> {
        Self::acquire_with(admin_home, attempts, retry_delay)
    }
}

fn resolve_lock_path(admin_home: &Path) -> Result<PathBuf, String> {
    let expected = admin_home.join(LOCK_FILE_NAME);
    let Some(actual) = find_named_entry(admin_home, LOCK_FILE_NAME)? else {
        return Ok(expected);
    };
    require_exact_path(&actual, &expected, "Harness User lifecycle lock")?;
    Ok(actual)
}

#[cfg(windows)]
fn open_exclusive(path: &Path) -> io::Result<File> {
    use std::os::windows::fs::OpenOptionsExt;

    use windows_sys::Win32::Storage::FileSystem::FILE_FLAG_OPEN_REPARSE_POINT;

    OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .share_mode(0)
        .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
        .open(path)
}

#[cfg(not(windows))]
fn open_exclusive(path: &Path) -> io::Result<File> {
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .open(path)?;
    file.try_lock()?;
    Ok(file)
}

fn is_contended(error: &io::Error) -> bool {
    #[cfg(windows)]
    {
        matches!(error.raw_os_error(), Some(32 | 33))
    }
    #[cfg(not(windows))]
    {
        error.kind() == io::ErrorKind::WouldBlock
    }
}

fn require_regular_directory(path: &Path, description: &str) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect {description} '{}': {error}", path.display()))?;
    if !metadata.is_dir() || metadata_is_reparse(&metadata) {
        Err(format!(
            "{description} must be a regular non-reparse directory: {}",
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
        metadata.file_attributes() & 0x400 != 0
    }
    #[cfg(not(windows))]
    {
        false
    }
}
