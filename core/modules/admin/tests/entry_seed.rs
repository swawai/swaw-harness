mod support;

use std::fs;
use std::sync::{Arc, Barrier};
use std::thread;

use serde_json::json;

#[cfg(windows)]
use support::create_directory_junction;
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
    assert!(data.join(".harness").join("entry.lock").is_file());
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

#[test]
fn rejects_a_fresh_source_inside_data_home_without_creating_the_lock() {
    let root = TestRoot::new();
    let harness = root.harness("h");
    let source = fixture(&root, "h/data/source", "one");

    let rejected = run_seed(&source.executable, &harness);

    assert!(!rejected.status.success());
    assert!(output_text(&rejected.stderr).contains("inside the target DataHome"));
    assert!(!harness.join("data").join(".harness").exists());
    assert!(!entry_root(&harness).exists());

    let independent = root.harness("independent");
    let accepted = run_seed(&source.executable, &independent);
    assert!(
        accepted.status.success(),
        "{}",
        output_text(&accepted.stderr)
    );
}

#[cfg(windows)]
#[test]
fn rejects_a_reparse_ancestor_before_creating_through_it() {
    let root = TestRoot::new();
    let source = fixture(&root, "source", "one");
    let physical = root.path().join("physical");
    let alias = root.path().join("alias");
    fs::create_dir(&physical).unwrap();
    create_directory_junction(&alias, &physical);
    let harness = alias.join("h");
    assert!(harness.to_string_lossy().chars().count() <= 60);

    let rejected = run_seed(&source.executable, &harness);
    fs::remove_dir(&alias).unwrap();

    assert!(!rejected.status.success());
    assert!(output_text(&rejected.stderr).contains("regular directory"));
    assert!(!physical.join("h").exists());
}

#[cfg(windows)]
#[test]
fn rejects_a_reparse_data_home_control_root() {
    let root = TestRoot::new();
    let source = fixture(&root, "source", "one");
    let harness = root.harness("h");
    let data_home = harness.join("data");
    let control_target = root.path().join("control-target");
    fs::create_dir_all(&data_home).unwrap();
    fs::create_dir(&control_target).unwrap();
    let control_root = data_home.join(".harness");
    create_directory_junction(&control_root, &control_target);

    let rejected = run_seed(&source.executable, &harness);
    fs::remove_dir(&control_root).unwrap();

    assert!(!rejected.status.success());
    assert!(output_text(&rejected.stderr).contains("regular directory"));
    assert!(!entry_root(&harness).exists());
    assert_eq!(fs::read_dir(&control_target).unwrap().count(), 0);
}

#[cfg(windows)]
#[test]
fn rejects_a_reparse_lifecycle_lock() {
    let root = TestRoot::new();
    let source = fixture(&root, "source", "one");
    let harness = root.harness("h");
    let data_home = harness.join("data");
    let lock_target = root.path().join("lock-target");
    let control_root = data_home.join(".harness");
    fs::create_dir_all(&control_root).unwrap();
    fs::create_dir(&lock_target).unwrap();
    let lock = control_root.join("entry.lock");
    create_directory_junction(&lock, &lock_target);

    let rejected = run_seed(&source.executable, &harness);
    fs::remove_dir(&lock).unwrap();

    assert!(!rejected.status.success());
    assert!(output_text(&rejected.stderr).contains("regular non-reparse file"));
    assert!(!entry_root(&harness).exists());
    assert_eq!(fs::read_dir(&lock_target).unwrap().count(), 0);
}
