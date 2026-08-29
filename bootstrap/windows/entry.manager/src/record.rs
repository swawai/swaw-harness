use std::fmt;

use serde::{Deserialize, Serialize};

use crate::{EntryId, EntryLifecycleState};

pub const ENTRY_RECORD_SCHEMA: &str = "swaw.harness.entry/v1";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EntryRecord {
    entry_id: EntryId,
    lifecycle: EntryLifecycleState,
}

impl EntryRecord {
    pub fn new(entry_id: EntryId, lifecycle: EntryLifecycleState) -> Self {
        Self {
            entry_id,
            lifecycle,
        }
    }

    pub fn entry_id(&self) -> &EntryId {
        &self.entry_id
    }

    pub fn lifecycle(&self) -> EntryLifecycleState {
        self.lifecycle
    }

    pub fn encode_json(&self) -> Result<Vec<u8>, EntryRecordError> {
        let document = EntryRecordDocumentRef {
            schema: ENTRY_RECORD_SCHEMA,
            entry_id: &self.entry_id,
            lifecycle: self.lifecycle,
        };
        let mut encoded = serde_json::to_vec_pretty(&document)?;
        encoded.push(b'\n');
        Ok(encoded)
    }

    pub fn decode_json(
        encoded: &[u8],
        expected_entry_id: &EntryId,
    ) -> Result<Self, EntryRecordError> {
        let document: EntryRecordDocument = serde_json::from_slice(encoded)?;
        if document.schema != ENTRY_RECORD_SCHEMA {
            return Err(EntryRecordError::UnsupportedSchema(document.schema));
        }
        if document.entry_id != *expected_entry_id {
            return Err(EntryRecordError::IdentityMismatch {
                expected: expected_entry_id.clone(),
                actual: document.entry_id,
            });
        }
        Ok(Self::new(document.entry_id, document.lifecycle))
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct EntryRecordDocument {
    schema: String,
    entry_id: EntryId,
    lifecycle: EntryLifecycleState,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct EntryRecordDocumentRef<'a> {
    schema: &'static str,
    entry_id: &'a EntryId,
    lifecycle: EntryLifecycleState,
}

#[derive(Debug)]
pub enum EntryRecordError {
    InvalidJson(serde_json::Error),
    UnsupportedSchema(String),
    IdentityMismatch { expected: EntryId, actual: EntryId },
}

impl fmt::Display for EntryRecordError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidJson(error) => write!(formatter, "invalid Entry record JSON: {error}"),
            Self::UnsupportedSchema(schema) => {
                write!(formatter, "unsupported Entry record schema '{schema}'")
            }
            Self::IdentityMismatch { expected, actual } => write!(
                formatter,
                "Entry record identity '{actual}' does not match expected EntryId '{expected}'"
            ),
        }
    }
}

impl std::error::Error for EntryRecordError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::InvalidJson(error) => Some(error),
            Self::UnsupportedSchema(_) | Self::IdentityMismatch { .. } => None,
        }
    }
}

impl From<serde_json::Error> for EntryRecordError {
    fn from(error: serde_json::Error) -> Self {
        Self::InvalidJson(error)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_a_canonical_versioned_record() {
        let record = EntryRecord::new(
            EntryId::parse("demo").unwrap(),
            EntryLifecycleState::Provisioning,
        );

        assert_eq!(
            record.encode_json().unwrap(),
            concat!(
                "{\n",
                "  \"schema\": \"swaw.harness.entry/v1\",\n",
                "  \"entryId\": \"demo\",\n",
                "  \"lifecycle\": \"provisioning\"\n",
                "}\n"
            )
            .as_bytes()
        );
    }

    #[test]
    fn round_trips_every_lifecycle_state() {
        let entry_id = EntryId::parse("demo").unwrap();
        for lifecycle in [
            EntryLifecycleState::Provisioning,
            EntryLifecycleState::Active,
            EntryLifecycleState::Deleting,
        ] {
            let expected = EntryRecord::new(entry_id.clone(), lifecycle);
            let actual =
                EntryRecord::decode_json(&expected.encode_json().unwrap(), &entry_id).unwrap();
            assert_eq!(actual, expected);
        }
    }

    #[test]
    fn rejects_unsupported_schema_and_mismatched_identity() {
        let expected = EntryId::parse("expected").unwrap();
        let unsupported = br#"{
            "schema":"swaw.harness.entry/v2",
            "entryId":"expected",
            "lifecycle":"active"
        }"#;
        assert!(matches!(
            EntryRecord::decode_json(unsupported, &expected),
            Err(EntryRecordError::UnsupportedSchema(_))
        ));

        let mismatch = br#"{
            "schema":"swaw.harness.entry/v1",
            "entryId":"actual",
            "lifecycle":"active"
        }"#;
        assert!(matches!(
            EntryRecord::decode_json(mismatch, &expected),
            Err(EntryRecordError::IdentityMismatch { .. })
        ));
    }

    #[test]
    fn rejects_unknown_missing_or_invalid_fields() {
        let expected = EntryId::parse("demo").unwrap();
        for encoded in [
            br#"{"#.as_slice(),
            br#"{"schema":"swaw.harness.entry/v1","entryId":"demo","lifecycle":"active","extra":true}"#.as_slice(),
            br#"{"schema":"swaw.harness.entry/v1","entryId":"demo"}"#.as_slice(),
            br#"{"schema":"swaw.harness.entry/v1","entryId":"demo","lifecycle":"ready"}"#.as_slice(),
            br#"{"schema":"swaw.harness.entry/v1","entryId":"Demo","lifecycle":"active"}"#.as_slice(),
            r#"{"schema":"swaw.harness.entry/v1","entryId":"démo","lifecycle":"active"}"#.as_bytes(),
        ] {
            assert!(matches!(
                EntryRecord::decode_json(encoded, &expected),
                Err(EntryRecordError::InvalidJson(_))
            ));
        }
    }
}
