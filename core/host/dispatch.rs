use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};

use swaw_harness_core_protocol::{InstalledModules, SkillMap};

pub(crate) const PLATFORM_TARGET_ID: &str = "x86_64-pc-windows-msvc";

#[derive(Debug)]
pub(crate) struct PreparedCall {
    executable: PathBuf,
    arguments: Vec<OsString>,
    working_directory: PathBuf,
}

impl PreparedCall {
    #[cfg(test)]
    pub(crate) fn for_test(
        executable: PathBuf,
        arguments: Vec<OsString>,
        working_directory: PathBuf,
    ) -> Self {
        Self {
            executable,
            arguments,
            working_directory,
        }
    }

    pub(crate) fn executable(&self) -> &Path {
        &self.executable
    }

    pub(crate) fn arguments(&self) -> impl Iterator<Item = &OsStr> {
        self.arguments.iter().map(OsString::as_os_str)
    }

    pub(crate) fn working_directory(&self) -> &Path {
        &self.working_directory
    }
}

pub(crate) fn prepare_call(
    data_home: &Path,
    user_home: &Path,
    skill_path: &str,
    dynamic_arguments: impl IntoIterator<Item = OsString>,
) -> Result<PreparedCall, String> {
    let skill_map = SkillMap::open(user_home.join("map").join("core"))?;
    let node = skill_map.find(skill_path)?;
    let declaration = node.declaration();
    let modules = InstalledModules::open(data_home)?;
    let release = modules.select(
        declaration.module(),
        declaration.version(),
        PLATFORM_TARGET_ID,
        declaration.executable(),
    )?;

    let mut arguments: Vec<OsString> = declaration.arguments().iter().map(OsString::from).collect();
    arguments.extend(dynamic_arguments);
    Ok(PreparedCall {
        executable: release.executable_path().to_owned(),
        arguments,
        working_directory: release.root().to_owned(),
    })
}
