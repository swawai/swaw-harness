use std::ffi::OsString;
use std::path::Path;

use crate::entry::swaw_harness::seed;

const RESOURCE_PATH: &str = "admin/entry/swaw-harness";
const SEED_FACET: &str = "seed";

pub(crate) fn run(executable: &Path, arguments: Vec<OsString>) -> Result<(), String> {
    let [resource, facet, harness_root] = arguments.as_slice() else {
        return Err(usage());
    };
    if resource.to_str() != Some(RESOURCE_PATH) || facet.to_str() != Some(SEED_FACET) {
        return Err(usage());
    }

    let outcome = seed::run(executable, Path::new(harness_root))?;
    println!("{}", outcome.message());
    Ok(())
}

fn usage() -> String {
    format!("expected: swaw-harness-admin {RESOURCE_PATH} {SEED_FACET} <absolute HarnessRoot>")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_an_incomplete_or_wrong_route() {
        for arguments in [
            vec![],
            vec![RESOURCE_PATH.into(), SEED_FACET.into()],
            vec!["admin/entry".into(), SEED_FACET.into(), "C:\\h".into()],
            vec![RESOURCE_PATH.into(), "create".into(), "C:\\h".into()],
        ] {
            assert!(
                run(Path::new("admin.exe"), arguments)
                    .unwrap_err()
                    .contains("expected:")
            );
        }
    }
}
