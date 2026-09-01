use std::ffi::OsString;

pub(crate) fn run(_arguments: Vec<OsString>) -> Result<(), String> {
    Err(
        "Admin runtime Facets are not implemented; Bootstrap publishes Module Releases directly"
            .to_owned(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_direct_invocation_until_runtime_facets_exist() {
        let error = run(vec!["admin/entry".into(), "create".into()]).unwrap_err();

        assert!(error.contains("not implemented"));
        assert!(error.contains("Bootstrap publishes Module Releases directly"));
    }
}
