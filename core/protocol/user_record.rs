use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::filesystem::find_exact_child;

pub const USER_DOCUMENT_NAME: &str = "user.json";

const USER_SCHEMA: &str = "swaw.harness.user/v1";
const MAXIMUM_DOCUMENT_BYTES: u64 = 16 * 1024;
const MAXIMUM_USER_CLI_BYTES: u64 = 1024 * 1024;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum UserLifecycle {
    Creating,
    Active,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UserCliIdentity {
    length: u64,
    sha256: String,
}

impl UserCliIdentity {
    pub fn new(length: u64, sha256: impl Into<String>) -> Result<Self, String> {
        let identity = Self {
            length,
            sha256: sha256.into(),
        };
        identity.validate()?;
        Ok(identity)
    }

    pub fn length(&self) -> u64 {
        self.length
    }

    pub fn sha256(&self) -> &str {
        &self.sha256
    }

    fn validate(&self) -> Result<(), String> {
        if self.length == 0 || self.length > MAXIMUM_USER_CLI_BYTES {
            return Err(format!(
                "User CLI executable length must be between 1 and {MAXIMUM_USER_CLI_BYTES} bytes"
            ));
        }
        if !is_lowercase_sha256(&self.sha256) {
            return Err("User CLI executable SHA-256 is invalid".to_owned());
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UserRecord {
    schema: String,
    user_id: String,
    lifecycle: UserLifecycle,
    user_cli: UserCliIdentity,
}

impl UserRecord {
    pub fn new(
        user_id: impl Into<String>,
        lifecycle: UserLifecycle,
        user_cli: UserCliIdentity,
    ) -> Result<Self, String> {
        let record = Self {
            schema: USER_SCHEMA.to_owned(),
            user_id: user_id.into(),
            lifecycle,
            user_cli,
        };
        record.validate(&record.user_id)?;
        Ok(record)
    }

    pub fn read(user_home: impl AsRef<Path>, expected_user_id: &str) -> Result<Self, String> {
        let user_home = user_home.as_ref();
        assert_regular_directory(user_home, "UserHome")?;
        let path = find_exact_child(user_home, USER_DOCUMENT_NAME, "Harness User record")?;
        let metadata = fs::symlink_metadata(&path).map_err(|error| {
            format!(
                "cannot inspect Harness User record '{}': {error}",
                path.display()
            )
        })?;
        if metadata_is_reparse(&metadata) || !metadata.is_file() {
            return Err(format!(
                "Harness User record is not a regular non-reparse file: {}",
                path.display()
            ));
        }
        if metadata.len() == 0 || metadata.len() > MAXIMUM_DOCUMENT_BYTES {
            return Err(format!(
                "Harness User record has an invalid size: {}",
                path.display()
            ));
        }
        let encoded = fs::read(&path).map_err(|error| {
            format!(
                "cannot read Harness User record '{}': {error}",
                path.display()
            )
        })?;
        let record: Self = serde_json::from_slice(&encoded).map_err(|error| {
            format!(
                "cannot parse Harness User record '{}': {error}",
                path.display()
            )
        })?;
        record.validate(expected_user_id)?;
        Ok(record)
    }

    pub fn encode(&self) -> Result<Vec<u8>, String> {
        self.validate(&self.user_id)?;
        let mut encoded = serde_json::to_vec_pretty(self)
            .map_err(|error| format!("cannot serialize Harness User record: {error}"))?;
        encoded.push(b'\n');
        Ok(encoded)
    }

    pub fn user_id(&self) -> &str {
        &self.user_id
    }

    pub fn lifecycle(&self) -> UserLifecycle {
        self.lifecycle
    }

    pub fn user_cli(&self) -> &UserCliIdentity {
        &self.user_cli
    }

    pub fn with_lifecycle(&self, lifecycle: UserLifecycle) -> Self {
        let mut result = self.clone();
        result.lifecycle = lifecycle;
        result
    }

    fn validate(&self, expected_user_id: &str) -> Result<(), String> {
        if self.schema != USER_SCHEMA {
            return Err(format!(
                "unsupported Harness User schema '{}'; expected '{USER_SCHEMA}'",
                self.schema
            ));
        }
        if self.user_id != expected_user_id {
            return Err(format!(
                "Harness User record UserId '{}' does not match expected UserId '{expected_user_id}'",
                self.user_id
            ));
        }
        self.user_cli.validate()
    }
}

fn assert_regular_directory(path: &Path, description: &str) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect {description} '{}': {error}", path.display()))?;
    if metadata_is_reparse(&metadata) || !metadata.is_dir() {
        Err(format!(
            "{description} is not a regular non-reparse directory: {}",
            path.display()
        ))
    } else {
        Ok(())
    }
}

fn metadata_is_reparse(metadata: &fs::Metadata) -> bool {
    if metadata.file_type().is_symlink() {
        return true;
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
        metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0
    }
    #[cfg(not(windows))]
    {
        false
    }
}

fn is_lowercase_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT_FIXTURE: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn round_trip_preserves_identity_lifecycle_and_cli() {
        let user_home = temporary_user_home("round-trip");
        let record = fixture_record(UserLifecycle::Creating);
        fs::write(user_home.join(USER_DOCUMENT_NAME), record.encode().unwrap()).unwrap();

        let stored = UserRecord::read(&user_home, "alice").unwrap();
        assert_eq!(stored.user_id(), "alice");
        assert_eq!(stored.lifecycle(), UserLifecycle::Creating);
        assert_eq!(stored.user_cli().length(), 3);
        assert_eq!(stored.user_cli().sha256(), "a".repeat(64));

        fs::remove_dir_all(user_home).unwrap();
    }

    #[test]
    fn active_is_an_explicit_lifecycle_transition() {
        let creating = fixture_record(UserLifecycle::Creating);
        let active = creating.with_lifecycle(UserLifecycle::Active);

        assert_eq!(creating.lifecycle(), UserLifecycle::Creating);
        assert_eq!(active.lifecycle(), UserLifecycle::Active);
        assert_eq!(active.user_cli(), creating.user_cli());
    }

    #[test]
    fn unknown_fields_schema_identity_and_cli_are_rejected() {
        let user_home = temporary_user_home("invalid");
        let path = user_home.join(USER_DOCUMENT_NAME);
        let valid =
            String::from_utf8(fixture_record(UserLifecycle::Active).encode().unwrap()).unwrap();

        for invalid in [
            valid.replace("\n}", ",\n  \"extra\": true\n}"),
            valid.replace("swaw.harness.user/v1", "swaw.harness.user/v2"),
            valid.replace("\"alice\"", "\"bob\""),
            valid.replace(&"a".repeat(64), "ABC"),
        ] {
            fs::write(&path, invalid).unwrap();
            assert!(UserRecord::read(&user_home, "alice").is_err());
        }

        fs::remove_dir_all(user_home).unwrap();
    }

    fn fixture_record(lifecycle: UserLifecycle) -> UserRecord {
        UserRecord::new(
            "alice",
            lifecycle,
            UserCliIdentity::new(3, "a".repeat(64)).unwrap(),
        )
        .unwrap()
    }

    fn temporary_user_home(label: &str) -> std::path::PathBuf {
        let sequence = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "swaw-harness-user-record-{label}-{}-{sequence}",
            std::process::id()
        ));
        fs::create_dir(&path).unwrap();
        path
    }
}
