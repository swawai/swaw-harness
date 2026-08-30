use std::path::{Path, PathBuf};

use crate::BaseResourceSpace;

pub const ENTRY_ROOT_ENVIRONMENT_VARIABLE: &str = "SWAW_HARNESS_ENTRY_ROOT";

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct InvocationContext {
    entry_root: PathBuf,
}

impl InvocationContext {
    pub fn from_environment() -> Result<Self, String> {
        let entry_root = std::env::var_os(ENTRY_ROOT_ENVIRONMENT_VARIABLE).ok_or_else(|| {
            format!("required environment variable {ENTRY_ROOT_ENVIRONMENT_VARIABLE} is not set")
        })?;
        Self::from_entry_root(entry_root)
    }

    pub fn from_entry_root(entry_root: impl Into<PathBuf>) -> Result<Self, String> {
        let entry_root = entry_root.into();
        if !entry_root.is_absolute() {
            return Err(format!(
                "{ENTRY_ROOT_ENVIRONMENT_VARIABLE} must contain an absolute EntryRoot: {}",
                entry_root.display()
            ));
        }
        Ok(Self { entry_root })
    }

    pub fn entry_root(&self) -> &Path {
        &self.entry_root
    }

    pub fn export_root(&self) -> PathBuf {
        self.entry_root.join(BaseResourceSpace::Export.name())
    }
}

#[cfg(test)]
mod tests {
    use super::{ENTRY_ROOT_ENVIRONMENT_VARIABLE, InvocationContext};

    #[test]
    fn relative_entry_root_is_rejected() {
        let error = InvocationContext::from_entry_root("relative-entry").unwrap_err();

        assert!(error.contains(ENTRY_ROOT_ENVIRONMENT_VARIABLE));
        assert!(error.contains("absolute EntryRoot"));
    }

    #[test]
    fn export_root_is_below_the_entry_root() {
        let entry_root = std::env::temp_dir().join("swaw-harness-protocol-entry");
        let context = InvocationContext::from_entry_root(&entry_root).unwrap();

        assert_eq!(context.entry_root(), entry_root);
        assert_eq!(context.export_root(), entry_root.join("export"));
    }
}
