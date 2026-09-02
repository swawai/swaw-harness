mod user;
mod invocation;

pub use user::{UserId, UserIdError, MAX_USER_ID_BYTES};

pub fn run(arguments: Vec<std::ffi::OsString>) -> Result<(), String> {
    invocation::run(arguments)
}
