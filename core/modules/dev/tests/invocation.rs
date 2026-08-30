use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicU64, Ordering};

use swaw_harness_core_protocol::ENTRY_ROOT_ENVIRONMENT_VARIABLE;

static NEXT_FIXTURE: AtomicU64 = AtomicU64::new(0);

fn command(entry_root: Option<&Path>, arguments: &[&str]) -> Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_swaw-harness-dev"));
    command
        .env_remove(ENTRY_ROOT_ENVIRONMENT_VARIABLE)
        .arg("dev/bun/mode")
        .args(arguments);
    if let Some(entry_root) = entry_root {
        command.env(ENTRY_ROOT_ENVIRONMENT_VARIABLE, entry_root);
    }
    command.output().unwrap()
}

fn stdout(output: &Output) -> String {
    String::from_utf8(output.stdout.clone()).unwrap()
}

fn stderr(output: &Output) -> String {
    String::from_utf8(output.stderr.clone()).unwrap()
}

#[test]
fn missing_mode_reads_as_disabled_without_creating_state() {
    let fixture = Fixture::new();

    let output = command(Some(&fixture.root), &[]);

    assert!(output.status.success(), "{}", stderr(&output));
    assert_eq!(stdout(&output), "disabled\n");
    assert!(!fixture.document().exists());
    assert!(!fixture.root.join("export").exists());
}

#[test]
fn mode_is_persisted_at_the_resource_relative_export_path() {
    let fixture = Fixture::new();

    let set = command(Some(&fixture.root), &["managed"]);

    assert!(set.status.success(), "{}", stderr(&set));
    assert_eq!(stdout(&set), "managed\n");
    assert_eq!(
        fs::read_to_string(fixture.document()).unwrap(),
        concat!(
            "{\n",
            "  \"schema\": \"swaw.harness.dev-bun-mode/v1\",\n",
            "  \"mode\": \"managed\"\n",
            "}\n"
        )
    );

    let read = command(Some(&fixture.root), &[]);
    assert!(read.status.success(), "{}", stderr(&read));
    assert_eq!(stdout(&read), "managed\n");

    let replace = command(Some(&fixture.root), &["disabled"]);
    assert!(replace.status.success(), "{}", stderr(&replace));
    assert_eq!(stdout(&replace), "disabled\n");
    assert!(
        fs::read_to_string(fixture.document())
            .unwrap()
            .contains("\"mode\": \"disabled\"")
    );
}

#[test]
fn invalid_mode_does_not_replace_the_valid_document() {
    let fixture = Fixture::new();
    let initial = command(Some(&fixture.root), &["managed"]);
    assert!(initial.status.success(), "{}", stderr(&initial));
    let before = fs::read(fixture.document()).unwrap();

    let invalid = command(Some(&fixture.root), &["system"]);

    assert!(!invalid.status.success());
    assert!(stderr(&invalid).contains("Bun mode must be 'managed' or 'disabled'"));
    assert_eq!(fs::read(fixture.document()).unwrap(), before);
}

#[test]
fn missing_entry_root_environment_is_rejected() {
    let output = command(None, &["managed"]);

    assert!(!output.status.success());
    assert!(stderr(&output).contains(ENTRY_ROOT_ENVIRONMENT_VARIABLE));
}

#[test]
fn relative_entry_root_environment_is_rejected() {
    let output = command(Some(Path::new("relative-entry")), &["managed"]);

    assert!(!output.status.success());
    assert!(stderr(&output).contains("absolute EntryRoot"));
}

struct Fixture {
    root: PathBuf,
}

impl Fixture {
    fn new() -> Self {
        let root = std::env::temp_dir().join(format!(
            "swaw-harness-dev-bun-mode-{}-{}",
            std::process::id(),
            NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&root).unwrap();
        Self { root }
    }

    fn document(&self) -> PathBuf {
        self.root.join("export/dev/bun/mode/mode.json")
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}
