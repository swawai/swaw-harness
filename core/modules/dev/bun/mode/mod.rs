use std::ffi::OsString;
use std::fmt;
use std::str::FromStr;

use serde::{Deserialize, Serialize};

pub(crate) mod execute;
mod store;

pub(crate) use store::ModeStore;

pub(crate) const RESOURCE_PATH: &str = "dev/bun/mode";

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum Mode {
    Managed,
    #[default]
    Disabled,
}

impl fmt::Display for Mode {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Managed => "managed",
            Self::Disabled => "disabled",
        })
    }
}

impl FromStr for Mode {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "managed" => Ok(Self::Managed),
            "disabled" => Ok(Self::Disabled),
            _ => Err("Bun mode must be 'managed' or 'disabled'".to_owned()),
        }
    }
}

pub(crate) fn parse_mode(value: &OsString) -> Result<Mode, String> {
    value
        .to_str()
        .ok_or_else(|| "Bun mode must be valid Unicode".to_owned())?
        .parse()
}
