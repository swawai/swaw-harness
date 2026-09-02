use std::ffi::OsString;

pub(crate) fn run(_arguments: Vec<OsString>) -> Result<(), String> {
    Err(
        "Admin management skills are not implemented; Bootstrap publishes initial Module Releases directly"
            .to_owned(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_direct_invocation_until_management_skills_are_implemented() {
        let error = run(vec!["admin/user".into(), "create".into()]).unwrap_err();

        assert!(error.contains("not implemented"));
        assert!(error.contains("Bootstrap publishes initial Module Releases directly"));
    }
}
