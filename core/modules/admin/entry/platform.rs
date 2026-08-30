use std::fs;
use std::io;
use std::path::Path;

#[cfg(windows)]
use std::os::windows::ffi::OsStrExt;
#[cfg(windows)]
use std::os::windows::fs::MetadataExt;
#[cfg(windows)]
use windows_sys::Win32::Storage::FileSystem::{
    MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH, MoveFileExW,
};

const WINDOWS_REPARSE_POINT_ATTRIBUTE: u32 = 0x0000_0400;

#[cfg(windows)]
pub(super) fn path_character_count(path: &Path) -> usize {
    path.as_os_str().encode_wide().count()
}

#[cfg(not(windows))]
pub(super) fn path_character_count(path: &Path) -> usize {
    path.to_string_lossy().chars().count()
}

pub(super) fn is_reparse_point(metadata: &fs::Metadata) -> bool {
    if metadata.file_type().is_symlink() {
        return true;
    }
    #[cfg(windows)]
    {
        return metadata.file_attributes() & WINDOWS_REPARSE_POINT_ATTRIBUTE != 0;
    }
    #[cfg(not(windows))]
    {
        false
    }
}

#[cfg(windows)]
pub(super) fn move_file_replace(source: &Path, destination: &Path) -> io::Result<()> {
    let source: Vec<u16> = source.as_os_str().encode_wide().chain([0]).collect();
    let destination: Vec<u16> = destination.as_os_str().encode_wide().chain([0]).collect();
    let result = unsafe {
        // SAFETY: Both buffers are null-terminated UTF-16 paths and remain
        // alive for this synchronous MoveFileExW call.
        MoveFileExW(
            source.as_ptr(),
            destination.as_ptr(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        )
    };
    if result == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[cfg(not(windows))]
pub(super) fn move_file_replace(source: &Path, destination: &Path) -> io::Result<()> {
    fs::rename(source, destination)
}
