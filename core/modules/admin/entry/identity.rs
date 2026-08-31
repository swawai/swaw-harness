use std::fmt;
use std::str::FromStr;

use serde::{Deserialize, Deserializer, Serialize, Serializer};

pub const MAX_ENTRY_ID_BYTES: usize = 16;

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct EntryId(String);

impl EntryId {
    pub fn parse(value: impl Into<String>) -> Result<Self, EntryIdError> {
        let value = value.into();
        validate(&value)?;
        Ok(Self(value))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl AsRef<str> for EntryId {
    fn as_ref(&self) -> &str {
        self.as_str()
    }
}

impl fmt::Display for EntryId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

impl FromStr for EntryId {
    type Err = EntryIdError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        Self::parse(value)
    }
}

impl Serialize for EntryId {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(self.as_str())
    }
}

impl<'de> Deserialize<'de> for EntryId {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Self::parse(value).map_err(serde::de::Error::custom)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EntryIdError {
    message: &'static str,
}

impl EntryIdError {
    const fn new(message: &'static str) -> Self {
        Self { message }
    }
}

impl fmt::Display for EntryIdError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.message)
    }
}

impl std::error::Error for EntryIdError {}

fn validate(value: &str) -> Result<(), EntryIdError> {
    if value.is_empty() || value.len() > MAX_ENTRY_ID_BYTES {
        return Err(EntryIdError::new(
            "EntryId must contain 1 to 16 ASCII bytes",
        ));
    }
    if !value.is_ascii() {
        return Err(EntryIdError::new("EntryId must contain only ASCII bytes"));
    }

    let bytes = value.as_bytes();
    if !bytes[0].is_ascii_lowercase() {
        return Err(EntryIdError::new(
            "EntryId must start with a lowercase ASCII letter",
        ));
    }
    if !bytes[bytes.len() - 1].is_ascii_lowercase() && !bytes[bytes.len() - 1].is_ascii_digit() {
        return Err(EntryIdError::new(
            "EntryId must end with a lowercase ASCII letter or digit",
        ));
    }
    if !bytes
        .iter()
        .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || *byte == b'-')
    {
        return Err(EntryIdError::new(
            "EntryId may contain only lowercase ASCII letters, digits, or hyphens",
        ));
    }
    if bytes.windows(2).any(|pair| pair == b"--") {
        return Err(EntryIdError::new(
            "EntryId cannot contain consecutive hyphens",
        ));
    }
    if is_windows_reserved_name(value) {
        return Err(EntryIdError::new(
            "EntryId cannot be a Windows reserved device name",
        ));
    }
    if value == "modules" {
        return Err(EntryIdError::new(
            "EntryId cannot use the reserved DataHome modules name",
        ));
    }
    Ok(())
}

fn is_windows_reserved_name(value: &str) -> bool {
    matches!(value, "con" | "prn" | "aux" | "nul")
        || matches!(value.as_bytes(), [b'c', b'o', b'm', b'1'..=b'9'])
        || matches!(value.as_bytes(), [b'l', b'p', b't', b'1'..=b'9'])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_canonical_lowercase_ascii_ids() {
        for value in ["a", "entry1", "project-one", "a1-b2", "con-safe"] {
            let entry_id = EntryId::parse(value).unwrap();
            assert_eq!(entry_id.as_str(), value);
        }
        assert!(EntryId::parse("a".repeat(MAX_ENTRY_ID_BYTES)).is_ok());
    }

    #[test]
    fn rejects_noncanonical_or_out_of_range_ids() {
        for value in [
            "",
            "1entry",
            "Entry",
            "entry_name",
            "-entry",
            "entry-",
            "entry--one",
            "entry one",
            "entrée",
            "modules",
        ] {
            assert!(EntryId::parse(value).is_err(), "{value}");
        }
        assert!(EntryId::parse("a".repeat(MAX_ENTRY_ID_BYTES + 1)).is_err());
    }

    #[test]
    fn rejects_all_supported_windows_reserved_device_names() {
        for value in ["con", "prn", "aux", "nul"] {
            assert!(EntryId::parse(value).is_err(), "{value}");
        }
        for number in 1..=9 {
            for prefix in ["com", "lpt"] {
                let value = format!("{prefix}{number}");
                assert!(EntryId::parse(&value).is_err(), "{value}");
            }
        }
    }
}
