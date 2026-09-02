#[cfg(windows)]
use std::ffi::OsStr;
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use swaw_harness_core_protocol::BaseResourceSpace;

use super::{Mode, RESOURCE_PATH};

const DOCUMENT_SCHEMA: &str = "swaw.harness.dev-bun-mode/v1";
const DOCUMENT_NAME: &str = "mode.json";
const MAX_DOCUMENT_BYTES: u64 = 4096;

static NEXT_PUBLICATION: AtomicU64 = AtomicU64::new(0);

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct ModeDocument {
    schema: String,
    mode: Mode,
}

impl ModeDocument {
    fn new(mode: Mode) -> Self {
        Self {
            schema: DOCUMENT_SCHEMA.to_owned(),
            mode,
        }
    }

    fn validate(self) -> Result<Mode, String> {
        if self.schema != DOCUMENT_SCHEMA {
            return Err(format!(
                "unsupported Bun mode schema '{}'; expected '{DOCUMENT_SCHEMA}'",
                self.schema
            ));
        }
        Ok(self.mode)
    }
}

pub(crate) struct ModeStore {
    user_home: PathBuf,
}

impl ModeStore {
    pub(crate) fn new(user_home: impl Into<PathBuf>) -> Self {
        Self {
            user_home: user_home.into(),
        }
    }

    pub(crate) fn read(&self) -> Result<Mode, String> {
        let Some(directory) = self.resource_directory(false)? else {
            return Ok(Mode::default());
        };
        let path = directory.join(DOCUMENT_NAME);
        let metadata = match fs::symlink_metadata(&path) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Mode::default()),
            Err(error) => {
                return Err(format!(
                    "cannot inspect Bun mode document '{}': {error}",
                    path.display()
                ));
            }
        };
        require_regular_file(&path, &metadata)?;
        if metadata.len() > MAX_DOCUMENT_BYTES {
            return Err(format!(
                "Bun mode document exceeds {MAX_DOCUMENT_BYTES} bytes: {}",
                path.display()
            ));
        }
        let mut content = Vec::with_capacity((metadata.len() + 1) as usize);
        fs::File::open(&path)
            .and_then(|file| file.take(MAX_DOCUMENT_BYTES + 1).read_to_end(&mut content))
            .map_err(|error| {
                format!(
                    "cannot read Bun mode document '{}': {error}",
                    path.display()
                )
            })?;
        if content.len() as u64 > MAX_DOCUMENT_BYTES {
            return Err(format!(
                "Bun mode document exceeds {MAX_DOCUMENT_BYTES} bytes: {}",
                path.display()
            ));
        }
        let document: ModeDocument = serde_json::from_slice(&content).map_err(|error| {
            format!(
                "cannot parse Bun mode document '{}': {error}",
                path.display()
            )
        })?;
        document.validate()
    }

    pub(crate) fn write(&self, mode: Mode) -> Result<(), String> {
        let directory = self
            .resource_directory(true)?
            .expect("creating a Resource directory must return its path");
        let path = directory.join(DOCUMENT_NAME);
        match fs::symlink_metadata(&path) {
            Ok(metadata) => require_regular_file(&path, &metadata)?,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(format!(
                    "cannot inspect Bun mode document '{}': {error}",
                    path.display()
                ));
            }
        }
        let mut content = serde_json::to_vec_pretty(&ModeDocument::new(mode))
            .map_err(|error| format!("cannot serialize Bun mode document: {error}"))?;
        content.push(b'\n');
        publish(&path, &content).map_err(|error| {
            format!(
                "cannot publish Bun mode document '{}': {error}",
                path.display()
            )
        })
    }

    fn resource_directory(&self, create: bool) -> Result<Option<PathBuf>, String> {
        if !self.user_home.is_absolute() {
            return Err(format!(
                "UserHome must be absolute: {}",
                self.user_home.display()
            ));
        }
        require_regular_directory(&self.user_home, "UserHome")?;
        let mut path = self.user_home.clone();
        let components =
            std::iter::once(BaseResourceSpace::Export.name()).chain(RESOURCE_PATH.split('/'));
        for component in components {
            path.push(component);
            match fs::symlink_metadata(&path) {
                Ok(metadata) => require_directory_metadata(&path, &metadata, "Bun mode path")?,
                Err(error) if error.kind() == io::ErrorKind::NotFound && !create => {
                    return Ok(None);
                }
                Err(error) if error.kind() == io::ErrorKind::NotFound => {
                    match fs::create_dir(&path) {
                        Ok(()) => {}
                        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
                        Err(error) => {
                            return Err(format!(
                                "cannot create Bun mode directory '{}': {error}",
                                path.display()
                            ));
                        }
                    }
                    let metadata = fs::symlink_metadata(&path).map_err(|error| {
                        format!(
                            "cannot inspect created Bun mode directory '{}': {error}",
                            path.display()
                        )
                    })?;
                    require_directory_metadata(&path, &metadata, "Bun mode path")?;
                }
                Err(error) => {
                    return Err(format!(
                        "cannot inspect Bun mode directory '{}': {error}",
                        path.display()
                    ));
                }
            }
        }
        Ok(Some(path))
    }
}

fn require_regular_directory(path: &Path, subject: &str) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect {subject} '{}': {error}", path.display()))?;
    require_directory_metadata(path, &metadata, subject)
}

fn require_directory_metadata(
    path: &Path,
    metadata: &fs::Metadata,
    subject: &str,
) -> Result<(), String> {
    if !metadata.is_dir() || is_reparse_point(metadata) {
        return Err(format!(
            "{subject} must be a regular directory: {}",
            path.display()
        ));
    }
    Ok(())
}

fn require_regular_file(path: &Path, metadata: &fs::Metadata) -> Result<(), String> {
    if !metadata.is_file() || is_reparse_point(metadata) {
        return Err(format!(
            "Bun mode document must be a regular file: {}",
            path.display()
        ));
    }
    Ok(())
}

#[cfg(windows)]
fn is_reparse_point(metadata: &fs::Metadata) -> bool {
    use std::os::windows::fs::MetadataExt;

    use windows_sys::Win32::Storage::FileSystem::FILE_ATTRIBUTE_REPARSE_POINT;

    metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0
}

#[cfg(not(windows))]
fn is_reparse_point(metadata: &fs::Metadata) -> bool {
    metadata.file_type().is_symlink()
}

fn publish(path: &Path, content: &[u8]) -> io::Result<()> {
    let directory = path.parent().ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "Bun mode path has no parent")
    })?;
    let temporary = unique_sibling(directory);
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary)?;
    let prepared = file.write_all(content).and_then(|()| file.sync_all());
    drop(file);
    if let Err(error) = prepared {
        let _ = fs::remove_file(&temporary);
        return Err(error);
    }
    let committed = if path.exists() {
        replace_file(path, &temporary)
    } else {
        fs::rename(&temporary, path)
    };
    committed.map_err(|error| {
        io::Error::new(
            error.kind(),
            format!(
                "cannot commit prepared Bun mode document: {error}; recovery temporary: '{}'",
                temporary.display()
            ),
        )
    })
}

fn unique_sibling(directory: &Path) -> PathBuf {
    let sequence = NEXT_PUBLICATION.fetch_add(1, Ordering::Relaxed);
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    directory.join(format!(
        ".swaw-harness.{}.{timestamp}.{sequence}.tmp",
        std::process::id()
    ))
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
        return Err(io::Error::last_os_error());
    }
    Ok(())
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

    value.encode_wide().chain(std::iter::once(0)).collect()
}
