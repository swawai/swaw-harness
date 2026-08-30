use std::fs::{File, OpenOptions};
use std::path::Path;
use std::thread;
use std::time::{Duration, Instant};

pub(crate) struct FileLock {
    _file: File,
}

impl FileLock {
    pub(crate) fn acquire(path: &Path, timeout: Duration) -> Result<Self, String> {
        let deadline = Instant::now() + timeout;
        loop {
            let file = OpenOptions::new()
                .read(true)
                .write(true)
                .create(true)
                .truncate(false)
                .open(path)
                .map_err(|error| {
                    format!("cannot open lifecycle lock '{}': {error}", path.display())
                })?;
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
