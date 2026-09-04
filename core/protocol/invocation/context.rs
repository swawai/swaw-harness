use std::path::{Path, PathBuf};

use crate::BaseResourceSpace;

pub const USER_HOME_ENVIRONMENT_VARIABLE: &str = "SWAW_HARNESS_USER_HOME";

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct InvocationContext {
    user_home: PathBuf,
}

impl InvocationContext {
    pub fn from_environment() -> Result<Self, String> {
        let user_home = std::env::var_os(USER_HOME_ENVIRONMENT_VARIABLE).ok_or_else(|| {
            format!("required environment variable {USER_HOME_ENVIRONMENT_VARIABLE} is not set")
        })?;
        Self::from_user_home(user_home)
    }

    pub fn from_user_home(user_home: impl Into<PathBuf>) -> Result<Self, String> {
        let user_home = user_home.into();
        if !user_home.is_absolute() {
            return Err(format!(
                "{USER_HOME_ENVIRONMENT_VARIABLE} must contain an absolute UserHome: {}",
                user_home.display()
            ));
        }
        Ok(Self { user_home })
    }

    pub fn user_home(&self) -> &Path {
        &self.user_home
    }

    pub fn export_root(&self) -> PathBuf {
        self.user_home.join(BaseResourceSpace::Export.name())
    }
}

#[cfg(test)]
mod tests {
    use super::{InvocationContext, USER_HOME_ENVIRONMENT_VARIABLE};

    #[test]
    fn relative_user_home_is_rejected() {
        let error = InvocationContext::from_user_home("relative-user-home").unwrap_err();

        assert!(error.contains(USER_HOME_ENVIRONMENT_VARIABLE));
        assert!(error.contains("absolute UserHome"));
    }

    #[test]
    fn export_root_is_below_the_user_home() {
        let user_home = std::env::temp_dir().join("swaw-harness-protocol-user-home");
        let context = InvocationContext::from_user_home(&user_home).unwrap();

        assert_eq!(context.user_home(), user_home);
        assert_eq!(context.export_root(), user_home.join("export"));
    }
}
