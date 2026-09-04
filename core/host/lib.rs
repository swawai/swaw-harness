mod dispatch;
mod wire;

#[cfg(windows)]
mod run;

#[cfg(windows)]
mod windows;

#[cfg(windows)]
pub fn run() -> Result<(), String> {
    windows::run()
}

#[cfg(not(windows))]
pub fn run() -> Result<(), String> {
    Err("Swaw Harness Core Host v1 supports Windows only".to_owned())
}
