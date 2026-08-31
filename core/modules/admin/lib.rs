mod entry;
mod invocation;

pub use entry::{EntryId, EntryIdError, MAX_ENTRY_ID_BYTES};

pub fn run(arguments: Vec<std::ffi::OsString>) -> Result<(), String> {
    invocation::run(arguments)
}
