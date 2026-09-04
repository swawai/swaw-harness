use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};

use swaw_harness_core_protocol::{InstalledModules, SkillMap};

pub(crate) const PLATFORM_TARGET_ID: &str = "x86_64-pc-windows-msvc";

#[derive(Debug)]
pub(crate) struct PreparedCall {
    executable: PathBuf,
    arguments: Vec<OsString>,
    working_directory: PathBuf,
    module: String,
    version: String,
    platform_target_id: String,
    executable_name: String,
    executable_length: u64,
    executable_sha256: String,
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
            module: "swaw/test/probe".to_owned(),
            version: "1.0.0".to_owned(),
            platform_target_id: PLATFORM_TARGET_ID.to_owned(),
            executable_name: "probe.exe".to_owned(),
            executable_length: 0,
            executable_sha256: "0".repeat(64),
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

    pub(crate) fn set_working_directory(&mut self, value: PathBuf) {
        self.working_directory = value;
    }

    pub(crate) fn module(&self) -> &str {
        &self.module
    }

    pub(crate) fn version(&self) -> &str {
        &self.version
    }

    pub(crate) fn platform_target_id(&self) -> &str {
        &self.platform_target_id
    }

    pub(crate) fn executable_name(&self) -> &str {
        &self.executable_name
    }

    pub(crate) fn executable_length(&self) -> u64 {
        self.executable_length
    }

    pub(crate) fn executable_sha256(&self) -> &str {
        &self.executable_sha256
    }
}

pub(crate) fn prepare_call(
    data_home: &Path,
    user_home: &Path,
    skill_path: &str,
    dynamic_arguments: impl IntoIterator<Item = OsString>,
) -> Result<PreparedCall, String> {
    let skill_map = SkillMap::open_core(user_home)?;
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
    let executable_name = declaration.executable().to_owned();
    Ok(PreparedCall {
        executable: release.executable_path().to_owned(),
        arguments,
        working_directory: release.root().to_owned(),
        module: release.module().to_string(),
        version: release.version().to_string(),
        platform_target_id: release.platform_target_id().to_owned(),
        executable_name,
        executable_length: release.executable_length(),
        executable_sha256: release.executable_sha256().to_owned(),
    })
}
