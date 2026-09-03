use std::ffi::OsString;

use swaw_harness_core_protocol::InvocationContext;

use crate::user::{self, UserId};

const USAGE: &str = "usage: admin/user/create <UserId>";

pub(crate) fn run(arguments: Vec<OsString>) -> Result<(), String> {
    let [domain, operation, raw_user_id] = arguments.as_slice() else {
        return Err(USAGE.to_owned());
    };
    if domain != "user" || operation != "create" {
        return Err(USAGE.to_owned());
    }
    let raw_user_id = raw_user_id
        .to_str()
        .ok_or_else(|| "UserId must be Unicode".to_owned())?;
    let user_id = UserId::parse(raw_user_id).map_err(|error| error.to_string())?;
    let context = InvocationContext::from_environment()?;
    user::create(context.user_home(), &user_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_unknown_or_incomplete_commands() {
        for arguments in [
            vec![],
            vec!["user".into()],
            vec!["user".into(), "delete".into(), "alice".into()],
            vec!["user".into(), "create".into()],
        ] {
            assert_eq!(run(arguments).unwrap_err(), USAGE);
        }
    }

    #[test]
    fn rejects_an_invalid_user_id_before_reading_environment() {
        let error = run(vec!["user".into(), "create".into(), "Admin".into()]).unwrap_err();

        assert!(error.contains("lowercase ASCII"));
    }
}
