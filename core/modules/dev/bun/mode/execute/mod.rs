use std::ffi::OsString;
use std::path::Path;

use super::{ModeStore, RESOURCE_PATH, parse_mode};

pub(crate) fn run(entry_root: &Path, arguments: &[OsString]) -> Result<(), String> {
    let store = ModeStore::new(entry_root);
    let mode = match arguments {
        [] => store.read()?,
        [value] => {
            let mode = parse_mode(value)?;
            store.write(mode)?;
            mode
        }
        _ => return Err(format!("usage: {RESOURCE_PATH} [managed|disabled]")),
    };
    println!("{mode}");
    Ok(())
}
