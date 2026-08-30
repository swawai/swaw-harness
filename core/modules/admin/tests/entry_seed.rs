mod support;

use std::fs;
use std::sync::{Arc, Barrier};
use std::thread;

use serde_json::json;

use support::{PLATFORM_TARGET_ID, TestRoot, assert_same_files, fixture, output_text, run_seed};

fn entry_root(harness: &std::path::Path) -> std::path::PathBuf {
    harness.join("data").join("swaw-harness")
}

fn prepare_provisioning(harness: &std::path::Path, release_id: &str) {
    let root = entry_root(harness);
    fs::create_dir_all(harness.join("data")).unwrap();
    fs::create_dir(&root).unwrap();
    fs::write(
        root.join("entry.json"),
        serde_json::to_vec_pretty(&json!({
            "schema": "swaw.harness.entry/v1",
            "entryId": "swaw-harness",
            "lifecycle": "provisioning"
        }))
        .unwrap(),
    )
    .unwrap();
    fs::write(
        root.join("provisioning.json"),
        serde_json::to_vec_pretty(&json!({
            "schema": "swaw.harness.entry-provisioning/v1",
            "releaseId": release_id,
            "platformTargetId": PLATFORM_TARGET_ID
        }))
        .unwrap(),
    )
    .unwrap();
}

fn assert_no_staging_remains(harness: &std::path::Path) {
    let data = harness.join("data");
    assert!(data.join(".entry.lock").is_file());
    assert!(!data.join(".admin").exists());
    assert!(!fs::read_dir(&data).unwrap().any(|entry| {
        entry
            .unwrap()
            .file_name()
            .to_string_lossy()
            .starts_with(".swaw-harness.seed-")
    }));
    let runtime = entry_root(harness).join("runtime");
    assert!(!fs::read_dir(runtime).unwrap().any(|entry| {
        entry
            .unwrap()
            .file_name()
            .to_string_lossy()
            .starts_with(".release-")
    }));
}

#[test]
fn seeds_one_self_contained_active_admin_entry() {
    let root = TestRoot::new();
    let source = fixture(&root, "source", "one");
    let harness = root.harness("h");

    let output = run_seed(&source.executable, &harness);
    assert!(output.status.success(), "{}", output_text(&output.stderr));
    assert!(output_text(&output.stdout).contains("seeded canonical Admin Entry"));

    let entry = entry_root(&harness);
    let record: serde_json::Value =
        serde_json::from_slice(&fs::read(entry.join("entry.json")).unwrap()).unwrap();
    assert_eq!(
        record,
        json!({
            "schema": "swaw.harness.entry/v1",
            "entryId": "swaw-harness",
            "lifecycle": "active"
        })
    );
    let runtime = entry.join("runtime").join(&source.release_id);
    assert_eq!(
        fs::read_to_string(
            entry
                .join("runtime")
                .join(format!("current.{PLATFORM_TARGET_ID}"))
        )
        .unwrap(),
        format!("{}\n", source.release_id)
    );
    assert_same_files(&source.root, &runtime);
    assert_eq!(
        fs::read(harness.join("data").join("swaw-harness.exe")).unwrap(),
        fs::read(runtime.join("entry.exe")).unwrap()
    );
    assert_no_staging_remains(&harness);

    fs::remove_dir_all(&source.root).unwrap();
    assert!(runtime.join("manifest.json").is_file());
}

#[test]
fn same_generation_is_idempotent_and_another_generation_does_not_upgrade() {
    let root = TestRoot::new();
    let first = fixture(&root, "source-one", "one");
    let second = fixture(&root, "source-two", "two");
    let harness = root.harness("h");

    assert!(run_seed(&first.executable, &harness).status.success());
    let repeated = run_seed(&first.executable, &harness);
    assert!(repeated.status.success());
    assert!(output_text(&repeated.stdout).contains("already active"));
    let different = run_seed(&second.executable, &harness);
    assert!(
        different.status.success(),
        "{}",
        output_text(&different.stderr)
    );
    assert!(output_text(&different.stdout).contains("another Release"));
    let runtime = entry_root(&harness).join("runtime");
    assert_eq!(
        fs::read_to_string(runtime.join(format!("current.{PLATFORM_TARGET_ID}"))).unwrap(),
        format!("{}\n", first.release_id)
    );
    assert!(!runtime.join(&second.release_id).exists());
}

#[test]
fn recovers_a_pinned_provisioning_entry() {
    let root = TestRoot::new();
    let source = fixture(&root, "source", "one");
    let harness = root.harness("h");
    prepare_provisioning(&harness, &source.release_id);

    let output = run_seed(&source.executable, &harness);
    assert!(output.status.success(), "{}", output_text(&output.stderr));
    assert!(output_text(&output.stdout).contains("recovered"));
    let entry = entry_root(&harness);
    let record: serde_json::Value =
        serde_json::from_slice(&fs::read(entry.join("entry.json")).unwrap()).unwrap();
    assert_eq!(record["lifecycle"], "active");
    assert!(!entry.join("provisioning.json").exists());
    assert_no_staging_remains(&harness);
}

#[test]
fn rebuilds_a_corrupt_same_identity_release_during_recovery() {
    let root = TestRoot::new();
    let source = fixture(&root, "source", "one");
    let harness = root.harness("h");
    prepare_provisioning(&harness, &source.release_id);
    let corrupt = entry_root(&harness)
        .join("runtime")
        .join(&source.release_id);
    fs::create_dir_all(&corrupt).unwrap();
    fs::write(corrupt.join("manifest.json"), b"corrupt").unwrap();

    let output = run_seed(&source.executable, &harness);
    assert!(output.status.success(), "{}", output_text(&output.stderr));
    assert_same_files(&source.root, &corrupt);
    assert_no_staging_remains(&harness);
}

#[test]
fn repairs_a_corrupt_active_same_identity_release_and_launcher() {
    let root = TestRoot::new();
    let source = fixture(&root, "source", "one");
    let harness = root.harness("h");
    assert!(run_seed(&source.executable, &harness).status.success());
    let runtime = entry_root(&harness)
        .join("runtime")
        .join(&source.release_id);
    let launcher = harness.join("data").join("swaw-harness.exe");
    fs::write(runtime.join("entry.exe"), b"corrupt Runtime artifact").unwrap();
    fs::write(&launcher, b"corrupt Entry launcher").unwrap();

    let repaired = run_seed(&source.executable, &harness);

    assert!(
        repaired.status.success(),
        "{}",
        output_text(&repaired.stderr)
    );
    assert!(output_text(&repaired.stdout).contains("already active from this Release"));
    assert_same_files(&source.root, &runtime);
    assert_eq!(
        fs::read(&launcher).unwrap(),
        fs::read(runtime.join("entry.exe")).unwrap()
    );
    assert_no_staging_remains(&harness);
}

#[test]
fn rejects_case_insensitive_namespace_conflicts() {
    let root = TestRoot::new();
    let source = fixture(&root, "source", "one");
    let harness = root.harness("h");
    fs::create_dir_all(harness.join("data").join("Swaw-Harness")).unwrap();

    let output = run_seed(&source.executable, &harness);
    assert!(!output.status.success());
    assert!(output_text(&output.stderr).contains("case-insensitive namespace conflict"));
}

#[test]
fn concurrent_seed_serializes_to_one_active_entry() {
    let root = TestRoot::new();
    let source = fixture(&root, "source", "one");
    let harness = root.harness("h");
    let barrier = Arc::new(Barrier::new(3));
    let mut handles = Vec::new();
    for _ in 0..2 {
        let executable = source.executable.clone();
        let harness = harness.clone();
        let barrier = Arc::clone(&barrier);
        handles.push(thread::spawn(move || {
            barrier.wait();
            run_seed(&executable, &harness)
        }));
    }
    barrier.wait();
    let outputs: Vec<_> = handles
        .into_iter()
        .map(|handle| handle.join().unwrap())
        .collect();
    assert!(outputs.iter().all(|output| output.status.success()));
    let stdout: Vec<_> = outputs
        .iter()
        .map(|output| output_text(&output.stdout))
        .collect();
    assert!(stdout.iter().any(|text| text.contains("seeded canonical")));
    assert!(stdout.iter().any(|text| text.contains("already active")));
}

#[test]
fn rejects_relative_harness_root_and_corrupt_source_release() {
    let root = TestRoot::new();
    let source = fixture(&root, "source", "one");
    let relative = run_seed(&source.executable, std::path::Path::new("relative"));
    assert!(!relative.status.success());
    assert!(output_text(&relative.stderr).contains("absolute"));

    fs::write(source.root.join("entry.exe"), b"tampered!").unwrap();
    let harness = root.harness("h");
    let corrupt = run_seed(&source.executable, &harness);
    assert!(!corrupt.status.success());
    assert!(output_text(&corrupt.stderr).contains("checksum"));
    assert!(!harness.join("data").exists());
}

#[test]
fn rejects_a_noncanonical_absolute_harness_root_without_creating_it() {
    let root = TestRoot::new();
    let source = fixture(&root, "source", "one");
    let noncanonical = root.path().join(".").join("h");
    let canonical = root.path().join("h");

    let output = run_seed(&source.executable, &noncanonical);

    assert!(!output.status.success());
    assert!(output_text(&output.stderr).contains("lexically normalized"));
    assert!(!canonical.exists());
}

#[test]
fn rejects_unrecognized_orphan_entry_objects() {
    let root = TestRoot::new();
    let source = fixture(&root, "source", "one");
    let harness = root.harness("h");
    fs::create_dir_all(harness.join("data")).unwrap();
    fs::write(harness.join("data").join("swaw-harness.exe"), b"orphan").unwrap();

    let output = run_seed(&source.executable, &harness);
    assert!(!output.status.success());
    assert!(output_text(&output.stderr).contains("orphan Entry executable"));
    assert!(!entry_root(&harness).exists());
}
