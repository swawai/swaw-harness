use std::fs::{self, File, OpenOptions};
use std::io;
use std::path::Path;
use std::thread;
use std::time::{Duration, Instant};

#[cfg(windows)]
use std::os::windows::fs::OpenOptionsExt;
#[cfg(windows)]
use windows_sys::Win32::Storage::FileSystem::{
    FILE_FLAG_OPEN_REPARSE_POINT, FILE_SHARE_READ, FILE_SHARE_WRITE,
};

use super::platform::is_reparse_point;

pub(crate) struct FileLock {
    _file: File,
}

impl FileLock {
    pub(crate) fn acquire(path: &Path, timeout: Duration) -> Result<Self, String> {
        let deadline = Instant::now() + timeout;
        loop {
            let file = open_lock_file(path)?;
            match file.try_lock() {
                Ok(()) => return Ok(Self { _file: file }),
                Err(_) if Instant::now() < deadline => {
                    drop(file);
                    thread::sleep(Duration::from_millis(100));
                }
                Err(error) => {
                    return Err(format!(
                        "timed out waiting for lifecycle lock '{}': {error}",
                        path.display()
                    ));
                }
            }
        }
    }
}

fn open_lock_file(path: &Path) -> Result<File, String> {
    assert_lock_path_if_present(path)?;

    let mut options = OpenOptions::new();
    options.read(true).write(true).create(true).truncate(false);
    #[cfg(windows)]
    options
        .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
        .share_mode(FILE_SHARE_READ | FILE_SHARE_WRITE);

    let file = options
        .open(path)
        .map_err(|error| format!("cannot open lifecycle lock '{}': {error}", path.display()))?;
    assert_regular_lock_metadata(
        &file.metadata().map_err(|error| {
            format!(
                "cannot inspect opened lifecycle lock '{}': {error}",
                path.display()
            )
        })?,
        path,
    )?;
    assert_lock_path_if_present(path)?;
    Ok(file)
}

fn assert_lock_path_if_present(path: &Path) -> Result<(), String> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => assert_regular_lock_metadata(&metadata, path),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(format!(
            "cannot inspect lifecycle lock '{}': {error}",
            path.display()
        )),
    }
}

fn assert_regular_lock_metadata(metadata: &fs::Metadata, path: &Path) -> Result<(), String> {
    if !metadata.is_file() || is_reparse_point(metadata) {
        return Err(format!(
            "lifecycle lock must be a regular non-reparse file: {}",
            path.display()
        ));
    }
    Ok(())
}
