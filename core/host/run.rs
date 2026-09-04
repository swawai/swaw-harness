use std::fs::{self, OpenOptions};
use std::io::{ErrorKind, Write};
use std::os::windows::ffi::OsStrExt;
use std::os::windows::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Serialize;
use swaw_harness_core_protocol::{BaseResourceSpace, SkillInvocationTarget};
use uuid::Uuid;
use windows_sys::Win32::Storage::FileSystem::{
    MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH, MoveFileExW,
};

use crate::dispatch::PreparedCall;

const RUN_SCHEMA: &str = "swaw.harness.run/v1";
const RUN_DOCUMENT_NAME: &str = "run.json";
const RUN_DOCUMENT_TEMPORARY_NAME: &str = ".run.json.tmp";
const REPARSE_POINT: u32 = 0x400;
const RUN_ID_ATTEMPTS: usize = 8;

pub(crate) struct RunWorkspace {
    root: PathBuf,
    document_path: PathBuf,
    document: RunDocument,
}

impl RunWorkspace {
    pub(crate) fn start(
        user_home: &Path,
        target: &SkillInvocationTarget,
        call: &mut PreparedCall,
    ) -> Result<Self, String> {
        let runs_root = user_home.join(BaseResourceSpace::Runs.name());
        ensure_runs_root(&runs_root)?;
        let (run_id, root) = create_run_root(&runs_root)?;
        let node_directory = match create_node_directory(&root, target) {
            Ok(directory) => directory,
            Err(error) => {
                let _ = fs::remove_dir_all(&root);
                return Err(error);
            }
        };
        call.set_working_directory(node_directory);

        let document_path = root.join(RUN_DOCUMENT_NAME);
        let document = match RunDocument::started(&run_id, target, call) {
            Ok(document) => document,
            Err(error) => {
                let _ = fs::remove_dir_all(&root);
                return Err(error);
            }
        };
        if let Err(error) = write_new_document(&document_path, &document) {
            let _ = fs::remove_dir_all(&root);
            return Err(error);
        }
        Ok(Self {
            root,
            document_path,
            document,
        })
    }

    pub(crate) fn run_id(&self) -> &str {
        &self.document.run_id
    }

    pub(crate) fn complete(mut self, exit_code: u32) -> Result<(), String> {
        self.document.result = RunResult::completed(exit_code)?;
        self.replace_document()
    }

    pub(crate) fn fail(mut self, error: &str) -> Result<(), String> {
        self.document.result = RunResult::failed(error.to_owned())?;
        self.replace_document()
    }

    fn replace_document(&self) -> Result<(), String> {
        let temporary_path = self.root.join(RUN_DOCUMENT_TEMPORARY_NAME);
        write_new_document(&temporary_path, &self.document)?;
        let source = wide_null(temporary_path.as_os_str())?;
        let destination = wide_null(self.document_path.as_os_str())?;
        if unsafe {
            MoveFileExW(
                source.as_ptr(),
                destination.as_ptr(),
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
            )
        } == 0
        {
            let error = std::io::Error::last_os_error();
            let _ = fs::remove_file(&temporary_path);
            return Err(format!(
                "cannot atomically replace Run record '{}': {error}",
                self.document_path.display()
            ));
        }
        Ok(())
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RunDocument {
    schema: &'static str,
    run_id: String,
    started_at_unix_ms: u64,
    target: RunTarget,
    module_release: RunModuleRelease,
    arguments_utf16: Vec<Vec<u16>>,
    result: RunResult,
}

impl RunDocument {
    fn started(
        run_id: &str,
        target: &SkillInvocationTarget,
        call: &PreparedCall,
    ) -> Result<Self, String> {
        Ok(Self {
            schema: RUN_SCHEMA,
            run_id: run_id.to_owned(),
            started_at_unix_ms: unix_milliseconds()?,
            target: RunTarget {
                skill_map_id: target.skill_map_id().to_owned(),
                skill_path: target.skill_path().to_owned(),
                method: target.method().name(),
            },
            module_release: RunModuleRelease {
                module: call.module().to_owned(),
                version: call.version().to_owned(),
                platform_target_id: call.platform_target_id().to_owned(),
                executable: call.executable_name().to_owned(),
                executable_length: call.executable_length(),
                executable_sha256: call.executable_sha256().to_owned(),
            },
            arguments_utf16: call
                .arguments()
                .map(|argument| argument.encode_wide().collect())
                .collect(),
            result: RunResult::running(),
        })
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RunTarget {
    skill_map_id: String,
    skill_path: String,
    method: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RunModuleRelease {
    module: String,
    version: String,
    platform_target_id: String,
    executable: String,
    executable_length: u64,
    executable_sha256: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RunResult {
    state: &'static str,
    completed_at_unix_ms: Option<u64>,
    exit_code: Option<u32>,
    error: Option<String>,
}

impl RunResult {
    const fn running() -> Self {
        Self {
            state: "running",
            completed_at_unix_ms: None,
            exit_code: None,
            error: None,
        }
    }

    fn completed(exit_code: u32) -> Result<Self, String> {
        Ok(Self {
            state: "completed",
            completed_at_unix_ms: Some(unix_milliseconds()?),
            exit_code: Some(exit_code),
            error: None,
        })
    }

    fn failed(error: String) -> Result<Self, String> {
        Ok(Self {
            state: "failed",
            completed_at_unix_ms: Some(unix_milliseconds()?),
            exit_code: None,
            error: Some(error),
        })
    }
}

fn ensure_runs_root(path: &Path) -> Result<(), String> {
    match fs::create_dir(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == ErrorKind::AlreadyExists => {
            assert_exact_existing_directory(path, "Runs resource-space root")
        }
        Err(error) => Err(format!(
            "cannot create Runs resource-space root '{}': {error}",
            path.display()
        )),
    }
}

fn assert_exact_existing_directory(path: &Path, description: &str) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| format!("cannot derive parent for {description}: {}", path.display()))?;
    let expected = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| format!("{description} name is not Unicode: {}", path.display()))?;
    let mut matches = Vec::new();
    for entry in fs::read_dir(parent).map_err(|error| {
        format!(
            "cannot enumerate parent directory '{}' for {description}: {error}",
            parent.display()
        )
    })? {
        let entry = entry.map_err(|error| format!("cannot enumerate {description}: {error}"))?;
        let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        if name.eq_ignore_ascii_case(expected) {
            matches.push((name, entry.path()));
        }
    }
    match matches.as_slice() {
        [(name, actual)] if name == expected => assert_regular_directory(actual, description),
        [(name, actual)] => Err(format!(
            "non-canonical {description} name '{name}'; expected '{expected}': {}",
            actual.display()
        )),
        [] => Err(format!("cannot find {description}: {}", path.display())),
        _ => Err(format!(
            "ambiguous case-insensitive {description} names for '{expected}' in '{}'",
            parent.display()
        )),
    }
}

fn create_run_root(runs_root: &Path) -> Result<(String, PathBuf), String> {
    for _ in 0..RUN_ID_ATTEMPTS {
        let run_id = Uuid::now_v7().simple().to_string();
        let root = runs_root.join(&run_id);
        match fs::create_dir(&root) {
            Ok(()) => return Ok((run_id, root)),
            Err(error) if error.kind() == ErrorKind::AlreadyExists => continue,
            Err(error) => {
                return Err(format!(
                    "cannot create Run root '{}': {error}",
                    root.display()
                ));
            }
        }
    }
    Err(format!(
        "cannot allocate a unique RunId below '{}'",
        runs_root.display()
    ))
}

fn create_node_directory(
    run_root: &Path,
    target: &SkillInvocationTarget,
) -> Result<PathBuf, String> {
    let mut directory = run_root.to_owned();
    for segment in std::iter::once(target.skill_map_id()).chain(target.skill_path().split('/')) {
        directory.push(segment);
        fs::create_dir(&directory).map_err(|error| {
            format!(
                "cannot create Run node directory '{}': {error}",
                directory.display()
            )
        })?;
    }
    Ok(directory)
}

fn write_new_document(path: &Path, document: &RunDocument) -> Result<(), String> {
    let mut encoded = serde_json::to_vec_pretty(document)
        .map_err(|error| format!("cannot encode Run record: {error}"))?;
    encoded.push(b'\n');
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|error| format!("cannot create Run record '{}': {error}", path.display()))?;
    file.write_all(&encoded)
        .and_then(|()| file.sync_all())
        .map_err(|error| format!("cannot write Run record '{}': {error}", path.display()))
}

fn assert_regular_directory(path: &Path, description: &str) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("cannot inspect {description} '{}': {error}", path.display()))?;
    if !metadata.is_dir() || metadata.file_attributes() & REPARSE_POINT != 0 {
        Err(format!(
            "{description} is not a regular non-reparse directory: {}",
            path.display()
        ))
    } else {
        Ok(())
    }
}

fn unix_milliseconds() -> Result<u64, String> {
    let value = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| format!("system time precedes Unix epoch: {error}"))?
        .as_millis();
    u64::try_from(value).map_err(|_| "system time does not fit Run timestamp".to_owned())
}

fn wide_null(value: &std::ffi::OsStr) -> Result<Vec<u16>, String> {
    let mut result: Vec<_> = value.encode_wide().collect();
    if result.contains(&0) {
        return Err("Run record path contains NUL".to_owned());
    }
    result.push(0);
    Ok(result)
}

#[cfg(test)]
mod tests {
    use std::ffi::OsString;
    use std::fs;
    use std::os::windows::ffi::OsStringExt;

    use serde_json::Value;

    use super::*;

    #[test]
    fn run_workspace_uses_one_uuid_v7_root_and_exact_node_path() {
        let user_home = temporary_user_home("workspace");
        let executable = std::env::current_exe().unwrap();
        let mut call = PreparedCall::for_test(
            executable.clone(),
            vec![OsString::from("Swaw"), OsString::from_wide(&[0xd800])],
            executable.parent().unwrap().to_owned(),
        );
        let target = SkillInvocationTarget::parse("core/release/publish").unwrap();

        let run = RunWorkspace::start(&user_home, &target, &mut call).unwrap();
        let run_root = run.root.clone();
        let run_id = run_root.file_name().unwrap().to_str().unwrap().to_owned();
        assert_eq!(run_id.len(), 32);
        assert!(run_id.bytes().all(|byte| byte.is_ascii_hexdigit()));
        let parsed = Uuid::parse_str(&run_id).unwrap();
        assert_eq!(parsed.get_version_num(), 7);
        assert_eq!(
            call.working_directory(),
            run_root.join("core/release/publish")
        );
        let started: Value =
            serde_json::from_slice(&fs::read(run_root.join(RUN_DOCUMENT_NAME)).unwrap()).unwrap();
        assert_eq!(started["result"]["state"], "running");
        assert!(started["result"]["exitCode"].is_null());

        run.complete(7).unwrap();
        let document: Value =
            serde_json::from_slice(&fs::read(run_root.join(RUN_DOCUMENT_NAME)).unwrap()).unwrap();
        assert_eq!(document["schema"], RUN_SCHEMA);
        assert_eq!(document["runId"], run_id);
        assert_eq!(document["target"]["skillMapId"], "core");
        assert_eq!(document["target"]["skillPath"], "release/publish");
        assert_eq!(document["target"]["method"], "node");
        assert_eq!(
            document["argumentsUtf16"][0],
            serde_json::json!([83, 119, 97, 119])
        );
        assert_eq!(document["argumentsUtf16"][1], serde_json::json!([0xd800]));
        assert_eq!(document["result"]["state"], "completed");
        assert_eq!(document["result"]["exitCode"], 7);
        assert!(!run_root.join(RUN_DOCUMENT_TEMPORARY_NAME).exists());
        assert!(!run_id.contains('-'));

        fs::remove_dir_all(user_home).unwrap();
    }

    #[test]
    fn noncanonical_runs_root_name_is_rejected() {
        let user_home = temporary_user_home("case");
        fs::create_dir(user_home.join("Runs")).unwrap();

        let error = ensure_runs_root(&user_home.join("runs")).unwrap_err();
        assert!(error.contains("non-canonical"), "{error}");

        fs::remove_dir_all(user_home).unwrap();
    }

    fn temporary_user_home(label: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!(
            "swaw-harness-run-{label}-{}-{}",
            std::process::id(),
            Uuid::now_v7().simple()
        ));
        fs::create_dir(&root).unwrap();
        root
    }
}
