use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicU64, Ordering};

use serde::Serialize;
use sha2::{Digest, Sha256};

pub(crate) const PLATFORM_TARGET_ID: &str = "x86_64-pc-windows-msvc";
const RELEASE_SCHEMA: &str = "swaw.harness.bootstrap-release/v1";
const ADMIN_ARTIFACT_NAME: &str = "swaw-harness-admin.exe";
const ENTRY_ARTIFACT_NAME: &str = "entry.exe";
static TEST_COUNTER: AtomicU64 = AtomicU64::new(0);

pub(crate) struct TestRoot(PathBuf);

impl TestRoot {
    pub(crate) fn new() -> Self {
        let counter = TEST_COUNTER.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!("swh{:x}{counter:x}", std::process::id()));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir(&path).unwrap();
        Self(path)
    }

    pub(crate) fn path(&self) -> &Path {
        &self.0
    }

    pub(crate) fn harness(&self, name: &str) -> PathBuf {
        let path = self.path().join(name);
        assert!(
            path.to_string_lossy().chars().count() <= 60,
            "{}",
            path.display()
        );
        path
    }
}

impl Drop for TestRoot {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

pub(crate) struct FixtureRelease {
    pub(crate) root: PathBuf,
    pub(crate) executable: PathBuf,
    pub(crate) release_id: String,
}

pub(crate) fn fixture(root: &TestRoot, name: &str, generation: &str) -> FixtureRelease {
    let stage = root.path().join(name).join("stage");
    fs::create_dir_all(&stage).unwrap();

    let binary = Path::new(env!("CARGO_BIN_EXE_swaw-harness-admin"));
    fs::copy(binary, stage.join(ADMIN_ARTIFACT_NAME)).unwrap();
    fs::write(
        stage.join(ENTRY_ARTIFACT_NAME),
        format!("entry-{generation}"),
    )
    .unwrap();
    fs::write(
        stage.join("swaw-harness-dev.exe"),
        format!("dev-{generation}"),
    )
    .unwrap();

    let mut artifacts = Vec::new();
    for name in [
        ADMIN_ARTIFACT_NAME,
        ENTRY_ARTIFACT_NAME,
        "swaw-harness-dev.exe",
    ] {
        let bytes = fs::read(stage.join(name)).unwrap();
        artifacts.push(ArtifactRecord {
            name: name.to_owned(),
            length: bytes.len() as u64,
            sha256: sha256(&bytes),
        });
    }
    let release_id = compute_release_id(&artifacts);
    let manifest = ReleaseManifest {
        schema: RELEASE_SCHEMA,
        release_id: &release_id,
        platform_target_id: PLATFORM_TARGET_ID,
        artifacts: &artifacts,
    };
    let mut encoded = serde_json::to_vec_pretty(&manifest).unwrap();
    encoded.push(b'\n');
    fs::write(stage.join("manifest.json"), encoded).unwrap();

    let release_root = stage.with_file_name(&release_id);
    fs::rename(&stage, &release_root).unwrap();
    FixtureRelease {
        executable: release_root.join(ADMIN_ARTIFACT_NAME),
        root: release_root,
        release_id,
    }
}

pub(crate) fn run_seed(executable: &Path, harness_root: &Path) -> Output {
    Command::new(executable)
        .arg("admin/entry/swaw-harness")
        .arg("seed")
        .arg(harness_root)
        .output()
        .unwrap()
}

pub(crate) fn output_text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

pub(crate) fn assert_same_files(left: &Path, right: &Path) {
    let left_names = file_names(left);
    let right_names = file_names(right);
    assert_eq!(left_names, right_names);
    for name in left_names {
        assert_eq!(
            fs::read(left.join(&name)).unwrap(),
            fs::read(right.join(name)).unwrap()
        );
    }
}

fn file_names(root: &Path) -> Vec<String> {
    let mut names: Vec<_> = fs::read_dir(root)
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    names
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ReleaseManifest<'a> {
    schema: &'static str,
    release_id: &'a str,
    platform_target_id: &'static str,
    artifacts: &'a [ArtifactRecord],
}

#[derive(Serialize)]
struct ArtifactRecord {
    name: String,
    length: u64,
    sha256: String,
}

fn compute_release_id(artifacts: &[ArtifactRecord]) -> String {
    let mut lines = vec![
        RELEASE_SCHEMA.to_owned(),
        format!("target={PLATFORM_TARGET_ID}"),
    ];
    for artifact in artifacts {
        lines.push(format!("artifact={}", artifact.name));
        lines.push(format!("length={}", artifact.length));
        lines.push(format!("sha256={}", artifact.sha256));
    }
    sha256(lines.join("\n").as_bytes())
}

fn sha256(bytes: &[u8]) -> String {
    let mut algorithm = Sha256::new();
    algorithm.update(bytes);
    let mut result = String::with_capacity(64);
    for byte in algorithm.finalize() {
        use std::fmt::Write;
        write!(&mut result, "{byte:02x}").unwrap();
    }
    result
}
