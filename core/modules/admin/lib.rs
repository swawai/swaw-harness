use std::ffi::OsString;

mod entry;
mod invocation;

pub fn run(arguments: Vec<OsString>) -> Result<(), String> {
    let executable = std::env::current_exe()
        .map_err(|error| format!("cannot resolve the Admin executable path: {error}"))?;
    invocation::run(&executable, arguments)
}
