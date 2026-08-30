use std::ffi::OsString;

mod bun;
mod invocation;
mod setup;

pub fn run(arguments: Vec<OsString>) -> Result<(), String> {
    invocation::run(arguments)
}
