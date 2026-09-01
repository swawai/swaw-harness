use std::fmt;
use std::fs;
use std::path::Path;

use serde::Deserialize;

use super::{assert_safe_segment, metadata_is_reparse};

pub const SKILL_DOCUMENT_NAME: &str = "skill.json";

const SKILL_SCHEMA: &str = "swaw.harness.skill/v1";
const MAXIMUM_ARGUMENTS: usize = 64;
const MAXIMUM_ARGUMENT_BYTES: usize = 4096;
const MAXIMUM_DOCUMENT_BYTES: u64 = 16 * 1024;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SkillDeclaration {
    module: ModuleId,
    version: VersionSelector,
    executable: String,
    arguments: Vec<String>,
}

impl SkillDeclaration {
    pub fn module(&self) -> &ModuleId {
        &self.module
    }

    pub fn version(&self) -> VersionSelector {
        self.version
    }

    pub fn executable(&self) -> &str {
        &self.executable
    }

    pub fn arguments(&self) -> &[String] {
        &self.arguments
    }
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct ModuleId(String);

impl ModuleId {
    pub fn parse(value: impl Into<String>) -> Result<Self, String> {
        let value = value.into();
        let segments: Vec<_> = value.split('/').collect();
        if segments.len() != 3 {
            return Err(format!(
                "module must contain exactly Publisher/Group/Module: {value}"
            ));
        }
        for segment in segments {
            assert_safe_segment(segment, "module identity segment")?;
        }
        Ok(Self(value))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub fn segments(&self) -> impl Iterator<Item = &str> {
        self.0.split('/')
    }
}

impl fmt::Display for ModuleId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub struct Version {
    major: u64,
    minor: u64,
    patch: u64,
}

impl Version {
    pub fn parse(value: &str) -> Result<Self, String> {
        let components: Vec<_> = value.split('.').collect();
        let [major, minor, patch] = components.as_slice() else {
            return Err(format!(
                "version must contain exact MAJOR.MINOR.PATCH: {value}"
            ));
        };
        Ok(Self {
            major: parse_version_component(major, value)?,
            minor: parse_version_component(minor, value)?,
            patch: parse_version_component(patch, value)?,
        })
    }

    pub fn major(self) -> u64 {
        self.major
    }

    pub fn minor(self) -> u64 {
        self.minor
    }

    pub fn patch(self) -> u64 {
        self.patch
    }
}

impl fmt::Display for Version {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum VersionSelector {
    Exact(Version),
    Major(u64),
    Minor { major: u64, minor: u64 },
}

impl VersionSelector {
    pub fn parse(value: &str) -> Result<Self, String> {
        let Some(prefix) = value.strip_suffix(".*") else {
            return Version::parse(value).map(Self::Exact);
        };
        let components: Vec<_> = prefix.split('.').collect();
        let selector = match components.as_slice() {
            [major] => Self::Major(parse_version_component(major, value)?),
            [major, minor] => Self::Minor {
                major: parse_version_component(major, value)?,
                minor: parse_version_component(minor, value)?,
            },
            _ => {
                return Err(format!(
                    "version selector must be exact, MAJOR.*, or MAJOR.MINOR.*: {value}"
                ));
            }
        };
        if matches!(selector, Self::Major(0) | Self::Minor { major: 0, .. }) {
            return Err("major 0 requires an exact module version".to_owned());
        }
        Ok(selector)
    }

    pub fn matches(self, version: Version) -> bool {
        match self {
            Self::Exact(expected) => expected == version,
            Self::Major(major) => version.major == major,
            Self::Minor { major, minor } => version.major == major && version.minor == minor,
        }
    }

    pub fn select_highest(self, versions: impl IntoIterator<Item = Version>) -> Option<Version> {
        versions
            .into_iter()
            .filter(|version| self.matches(*version))
            .max()
    }
}

impl fmt::Display for VersionSelector {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Exact(version) => version.fmt(formatter),
            Self::Major(major) => write!(formatter, "{major}.*"),
            Self::Minor { major, minor } => write!(formatter, "{major}.{minor}.*"),
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SkillDocument {
    schema: String,
    module: String,
    version: String,
    executable: String,
    arguments: Vec<String>,
}

pub(super) fn parse_skill_declaration(path: &Path) -> Result<SkillDeclaration, String> {
    let document: SkillDocument = parse_document(path, "Skill declaration")?;
    if document.schema != SKILL_SCHEMA {
        return Err(format!(
            "unsupported Skill schema '{}' in '{}'; expected '{SKILL_SCHEMA}'",
            document.schema,
            path.display()
        ));
    }
    let module = ModuleId::parse(document.module)?;
    let version = VersionSelector::parse(&document.version)?;
    assert_safe_segment(&document.executable, "executable name")?;
    if document.arguments.len() > MAXIMUM_ARGUMENTS {
        return Err(format!(
            "Skill arguments exceed {MAXIMUM_ARGUMENTS} items: {}",
            path.display()
        ));
    }
    for argument in &document.arguments {
        if argument.as_bytes().len() > MAXIMUM_ARGUMENT_BYTES || argument.contains('\0') {
            return Err(format!(
                "Skill argument is too large or contains NUL: {}",
                path.display()
            ));
        }
    }
    Ok(SkillDeclaration {
        module,
        version,
        executable: document.executable,
        arguments: document.arguments,
    })
}

fn parse_version_component(component: &str, source: &str) -> Result<u64, String> {
    if component.is_empty()
        || !component.bytes().all(|byte| byte.is_ascii_digit())
        || (component.len() > 1 && component.starts_with('0'))
    {
        return Err(format!("invalid numeric version component in '{source}'"));
    }
    component
        .parse()
        .map_err(|_| format!("numeric version component is too large in '{source}'"))
}

fn parse_document<T: for<'de> Deserialize<'de>>(
    path: &Path,
    description: &str,
) -> Result<T, String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect {description} '{}': {error}", path.display()))?;
    if metadata_is_reparse(&metadata) || !metadata.is_file() {
        return Err(format!(
            "{description} is not a regular non-reparse file: {}",
            path.display()
        ));
    }
    if metadata.len() == 0 || metadata.len() > MAXIMUM_DOCUMENT_BYTES {
        return Err(format!(
            "{description} has an invalid size: {}",
            path.display()
        ));
    }
    let encoded = fs::read(path)
        .map_err(|error| format!("cannot read {description} '{}': {error}", path.display()))?;
    serde_json::from_slice(&encoded)
        .map_err(|error| format!("cannot parse {description} '{}': {error}", path.display()))
}
