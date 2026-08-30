use std::fmt;

use serde::{Deserialize, Serialize};

use crate::entry::{EntryId, EntryLifecycleState};

pub(crate) const ENTRY_RECORD_SCHEMA: &str = "swaw.harness.entry/v1";
const PROVISIONING_RECORD_SCHEMA: &str = "swaw.harness.entry-provisioning/v1";

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct EntryRecord {
    entry_id: EntryId,
    lifecycle: EntryLifecycleState,
}

impl EntryRecord {
    pub(crate) fn new(entry_id: EntryId, lifecycle: EntryLifecycleState) -> Self {
        Self {
            entry_id,
            lifecycle,
        }
    }

    pub(crate) fn lifecycle(&self) -> EntryLifecycleState {
        self.lifecycle
    }

    pub(crate) fn encode_json(&self) -> Result<Vec<u8>, RecordError> {
        encode_pretty(&EntryRecordDocumentRef {
            schema: ENTRY_RECORD_SCHEMA,
            entry_id: &self.entry_id,
            lifecycle: self.lifecycle,
        })
    }

    pub(crate) fn decode_json(
        encoded: &[u8],
        expected_entry_id: &EntryId,
    ) -> Result<Self, RecordError> {
        let document: EntryRecordDocument = serde_json::from_slice(encoded)?;
        if document.schema != ENTRY_RECORD_SCHEMA {
            return Err(RecordError::UnsupportedSchema(document.schema));
        }
        if document.entry_id != *expected_entry_id {
            return Err(RecordError::IdentityMismatch {
                expected: expected_entry_id.clone(),
                actual: document.entry_id,
            });
        }
        Ok(Self::new(document.entry_id, document.lifecycle))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ProvisioningRecord {
    release_id: String,
    platform_target_id: String,
}

impl ProvisioningRecord {
    pub(crate) fn new(release_id: String, platform_target_id: String) -> Self {
        Self {
            release_id,
            platform_target_id,
        }
    }

    pub(crate) fn release_id(&self) -> &str {
        &self.release_id
    }

    pub(crate) fn platform_target_id(&self) -> &str {
        &self.platform_target_id
    }

    pub(crate) fn encode_json(&self) -> Result<Vec<u8>, RecordError> {
        encode_pretty(&ProvisioningRecordDocumentRef {
            schema: PROVISIONING_RECORD_SCHEMA,
            release_id: &self.release_id,
            platform_target_id: &self.platform_target_id,
        })
    }

    pub(crate) fn decode_json(encoded: &[u8]) -> Result<Self, RecordError> {
        let document: ProvisioningRecordDocument = serde_json::from_slice(encoded)?;
        if document.schema != PROVISIONING_RECORD_SCHEMA {
            return Err(RecordError::UnsupportedSchema(document.schema));
        }
        Ok(Self::new(document.release_id, document.platform_target_id))
    }
}

fn encode_pretty<T: Serialize>(document: &T) -> Result<Vec<u8>, RecordError> {
    let mut encoded = serde_json::to_vec_pretty(document)?;
    encoded.push(b'\n');
    Ok(encoded)
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

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ProvisioningRecordDocument {
    schema: String,
    release_id: String,
    platform_target_id: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ProvisioningRecordDocumentRef<'a> {
    schema: &'static str,
    release_id: &'a str,
    platform_target_id: &'a str,
}

#[derive(Debug)]
pub(crate) enum RecordError {
    InvalidJson(serde_json::Error),
    UnsupportedSchema(String),
    IdentityMismatch { expected: EntryId, actual: EntryId },
}

impl fmt::Display for RecordError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidJson(error) => write!(formatter, "invalid managed record JSON: {error}"),
            Self::UnsupportedSchema(schema) => {
                write!(formatter, "unsupported record schema '{schema}'")
            }
            Self::IdentityMismatch { expected, actual } => write!(
                formatter,
                "Entry record identity '{actual}' does not match expected EntryId '{expected}'"
            ),
        }
    }
}

impl std::error::Error for RecordError {}

impl From<serde_json::Error> for RecordError {
    fn from(error: serde_json::Error) -> Self {
        Self::InvalidJson(error)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_a_canonical_versioned_entry_record() {
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
    fn rejects_unknown_fields_and_mismatched_identity() {
        let expected = EntryId::parse("demo").unwrap();
        let extra = br#"{"schema":"swaw.harness.entry/v1","entryId":"demo","lifecycle":"active","extra":true}"#;
        assert!(matches!(
            EntryRecord::decode_json(extra, &expected),
            Err(RecordError::InvalidJson(_))
        ));
        let mismatch =
            br#"{"schema":"swaw.harness.entry/v1","entryId":"other","lifecycle":"active"}"#;
        assert!(matches!(
            EntryRecord::decode_json(mismatch, &expected),
            Err(RecordError::IdentityMismatch { .. })
        ));
    }

    #[test]
    fn provisioning_record_round_trips_exact_source_identity() {
        let expected = ProvisioningRecord::new("a".repeat(64), "x86_64-pc-windows-msvc".to_owned());
        let actual = ProvisioningRecord::decode_json(&expected.encode_json().unwrap()).unwrap();
        assert_eq!(actual, expected);
    }
}
