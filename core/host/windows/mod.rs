use std::ffi::OsString;
use std::os::windows::ffi::OsStringExt;

mod identity;
mod process;
mod security;
mod server;

use identity::HostIdentity;

pub(super) fn run() -> Result<(), String> {
    let identity = HostIdentity::discover()?;
    // The Host establishes this immutable per-process value before accepting
    // connections or creating worker threads. Every module child inherits it.
    unsafe {
        std::env::set_var("SWAW_HARNESS_USER_HOME", identity.user_home());
    }
    server::serve(identity)
}

fn os_string(value: &[u16], description: &str) -> Result<OsString, String> {
    if value.contains(&0) {
        return Err(format!("{description} contains NUL"));
    }
    Ok(OsString::from_wide(value))
}
