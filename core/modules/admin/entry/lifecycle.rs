use std::fmt;
use std::str::FromStr;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum EntryLifecycleState {
    Provisioning,
    Active,
    Deleting,
}

impl EntryLifecycleState {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Provisioning => "provisioning",
            Self::Active => "active",
            Self::Deleting => "deleting",
        }
    }
}

impl fmt::Display for EntryLifecycleState {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

impl FromStr for EntryLifecycleState {
    type Err = &'static str;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "provisioning" => Ok(Self::Provisioning),
            "active" => Ok(Self::Active),
            "deleting" => Ok(Self::Deleting),
            _ => Err("unsupported Entry lifecycle state"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lifecycle_names_are_closed_and_canonical() {
        for state in [
            EntryLifecycleState::Provisioning,
            EntryLifecycleState::Active,
            EntryLifecycleState::Deleting,
        ] {
            assert_eq!(state.as_str().parse(), Ok(state));
        }
        assert!("ready".parse::<EntryLifecycleState>().is_err());
    }
}
