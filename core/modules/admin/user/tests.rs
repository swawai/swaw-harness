use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use sha2::{Digest, Sha256};
use swaw_harness_core_protocol::{SkillMap, UserLifecycle, UserRecord};

use super::create::create;
use super::layout::user_home_stage;
use super::lock::UserLock;
use super::publication::{publication_stage, replace_record};
use super::UserId;

const PLATFORM_TARGET_ID: &str = "x86_64-pc-windows-msvc";
const HOST_VERSION: &str = "1.0.5";

static NEXT_FIXTURE: AtomicU64 = AtomicU64::new(0);

#[test]
fn creates_an_independent_active_user_and_is_idempotent() {
    let fixture = Fixture::new("create");
    let user_id = UserId::parse("alice").unwrap();

    create(&fixture.admin_home, &user_id).unwrap();
    let user_home = fixture.data_home.join("alice");
    let user_cli = fixture.data_home.join("alice.exe");
    assert_eq!(fs::read(&user_cli).unwrap(), b"user-cli-v1");
    assert_eq!(
        fs::read_to_string(user_home.join("host").join(pointer_name())).unwrap(),
        format!("{HOST_VERSION}\n")
    );
    assert_eq!(
        UserRecord::read(&user_home, "alice").unwrap().lifecycle(),
        UserLifecycle::Active
    );
    SkillMap::open_core(&user_home).unwrap().validate().unwrap();

    let record_before = fs::read(user_home.join("user.json")).unwrap();
    write_skill(&fixture.admin_home.join("map/core/later"));
    create(&fixture.admin_home, &user_id).unwrap();
    assert_eq!(
        fs::read(user_home.join("user.json")).unwrap(),
        record_before
    );
    assert!(!user_home.join("map/core/later").exists());
}

#[test]
fn resumes_after_user_home_commit_and_uses_the_current_user_cli() {
    let fixture = Fixture::new("resume");
    let user_id = UserId::parse("alice").unwrap();
    create(&fixture.admin_home, &user_id).unwrap();

    let user_home = fixture.data_home.join("alice");
    let record = UserRecord::read(&user_home, "alice").unwrap();
    replace_record(
        &user_home.join("user.json"),
        &record.with_lifecycle(UserLifecycle::Creating),
    )
    .unwrap();
    fs::remove_file(fixture.data_home.join("alice.exe")).unwrap();
    fs::write(fixture.data_home.join("admin.exe"), b"user-cli-v2").unwrap();

    create(&fixture.admin_home, &user_id).unwrap();
    assert_eq!(
        UserRecord::read(&user_home, "alice").unwrap().lifecycle(),
        UserLifecycle::Active
    );
    assert_eq!(
        fs::read(fixture.data_home.join("alice.exe")).unwrap(),
        b"user-cli-v2"
    );

    let active = UserRecord::read(&user_home, "alice").unwrap();
    replace_record(
        &user_home.join("user.json"),
        &active.with_lifecycle(UserLifecycle::Creating),
    )
    .unwrap();
    create(&fixture.admin_home, &user_id).unwrap();
    assert_eq!(
        UserRecord::read(&user_home, "alice").unwrap().lifecycle(),
        UserLifecycle::Active
    );
}

#[test]
fn rejects_one_sided_and_noncanonical_entities() {
    let fixture = Fixture::new("conflicts");
    let user_id = UserId::parse("alice").unwrap();
    fs::write(fixture.data_home.join("alice.exe"), b"orphan").unwrap();
    assert!(create(&fixture.admin_home, &user_id).is_err());
    fs::remove_file(fixture.data_home.join("alice.exe")).unwrap();

    fs::create_dir(fixture.data_home.join("Alice")).unwrap();
    let error = create(&fixture.admin_home, &user_id).unwrap_err();
    assert!(error.contains("non-canonical name 'Alice'"), "{error}");
}

#[test]
fn rejects_a_source_host_pointer_that_does_not_select_an_installed_release() {
    let fixture = Fixture::new("bad-pointer");
    fs::write(
        fixture.admin_home.join("host").join(pointer_name()),
        b"9.9.9\n",
    )
    .unwrap();

    let error = create(&fixture.admin_home, &UserId::parse("alice").unwrap()).unwrap_err();
    assert!(error.contains("no installed Module Release"), "{error}");
    assert!(!fixture.data_home.join("alice").exists());
    assert!(!fixture.data_home.join("alice.exe").exists());
}

#[test]
fn rejects_a_host_release_without_the_managed_user_gate() {
    let fixture = Fixture::new("old-host");
    write_host_release(&fixture.data_home, "1.0.2");
    fs::write(
        fixture.admin_home.join("host").join(pointer_name()),
        b"1.0.2\n",
    )
    .unwrap();

    let error = create(&fixture.admin_home, &UserId::parse("alice").unwrap()).unwrap_err();
    assert!(
        error.contains("not approved for swaw.harness.user/v1"),
        "{error}"
    );
    assert!(!fixture.data_home.join("alice").exists());
    assert!(!fixture.data_home.join("alice.exe").exists());
}

#[test]
fn removes_fixed_stages_before_new_and_resumed_creation() {
    let fixture = Fixture::new("stale-stages");
    let user_id = UserId::parse("alice").unwrap();
    let user_home = fixture.data_home.join("alice");
    let user_cli = fixture.data_home.join("alice.exe");
    let user_home_stage = user_home_stage(&fixture.data_home, &user_id);
    let user_cli_stage = publication_stage(&user_cli).unwrap();

    fs::create_dir(&user_home_stage).unwrap();
    fs::write(user_home_stage.join("partial"), b"partial").unwrap();
    fs::write(&user_cli_stage, b"partial").unwrap();
    create(&fixture.admin_home, &user_id).unwrap();
    assert!(!user_home_stage.exists());
    assert!(!user_cli_stage.exists());

    let active = UserRecord::read(&user_home, "alice").unwrap();
    replace_record(
        &user_home.join("user.json"),
        &active.with_lifecycle(UserLifecycle::Creating),
    )
    .unwrap();
    fs::remove_file(&user_cli).unwrap();
    fs::create_dir(&user_home_stage).unwrap();
    fs::write(user_home_stage.join("partial"), b"partial").unwrap();
    fs::write(&user_cli_stage, b"partial").unwrap();
    let user_record_stage = publication_stage(&user_home.join("user.json")).unwrap();
    fs::write(&user_record_stage, b"partial").unwrap();

    create(&fixture.admin_home, &user_id).unwrap();
    assert_eq!(
        UserRecord::read(&user_home, "alice").unwrap().lifecycle(),
        UserLifecycle::Active
    );
    assert!(!user_home_stage.exists());
    assert!(!user_cli_stage.exists());
    assert!(!user_record_stage.exists());
}

#[test]
fn active_user_rejects_reserved_stages_without_removing_them() {
    let fixture = Fixture::new("active-stages");
    let user_id = UserId::parse("alice").unwrap();
    create(&fixture.admin_home, &user_id).unwrap();
    let user_home = fixture.data_home.join("alice");
    let stages = [
        (user_home_stage(&fixture.data_home, &user_id), true),
        (
            publication_stage(&fixture.data_home.join("alice.exe")).unwrap(),
            false,
        ),
        (
            publication_stage(&user_home.join("user.json")).unwrap(),
            false,
        ),
    ];

    for (stage, is_directory) in stages {
        if is_directory {
            fs::create_dir(&stage).unwrap();
        } else {
            fs::write(&stage, b"stale").unwrap();
        }
        let error = create(&fixture.admin_home, &user_id).unwrap_err();
        assert!(
            error.contains("active Harness User has a reserved"),
            "{error}"
        );
        assert!(
            stage.exists(),
            "reserved stage was modified: {}",
            stage.display()
        );
        if is_directory {
            fs::remove_dir(&stage).unwrap();
        } else {
            fs::remove_file(&stage).unwrap();
        }
    }
}

#[test]
fn rejects_a_reserved_stage_with_the_wrong_entity_type() {
    let fixture = Fixture::new("invalid-stage");
    let user_id = UserId::parse("alice").unwrap();
    let user_cli_stage = publication_stage(&fixture.data_home.join("alice.exe")).unwrap();
    fs::create_dir(&user_cli_stage).unwrap();

    let error = create(&fixture.admin_home, &user_id).unwrap_err();
    assert!(
        error.contains("must be a regular non-reparse file"),
        "{error}"
    );
    assert!(user_cli_stage.is_dir());
}

#[cfg(windows)]
#[test]
fn rejects_a_noncanonical_lifecycle_lock_name() {
    let fixture = Fixture::new("lock-case");
    fs::write(fixture.admin_home.join("User.lock"), b"").unwrap();

    let error = UserLock::acquire_for_test(&fixture.admin_home, 1, Duration::ZERO)
        .err()
        .expect("noncanonical lifecycle lock must be rejected");
    assert!(error.contains("non-canonical name 'User.lock'"), "{error}");
}

#[cfg(windows)]
#[test]
fn active_user_rejects_a_stage_case_alias_without_removing_it() {
    let fixture = Fixture::new("active-stage-case");
    let user_id = UserId::parse("alice").unwrap();
    create(&fixture.admin_home, &user_id).unwrap();
    let alias = fixture.data_home.join(".Alice.exe.tmp");
    fs::write(&alias, b"stale").unwrap();

    let error = create(&fixture.admin_home, &user_id).unwrap_err();
    assert!(
        error.contains("non-canonical name '.Alice.exe.tmp'"),
        "{error}"
    );
    assert!(alias.exists());
}

#[cfg(windows)]
#[test]
fn lifecycle_lock_is_exclusive() {
    let fixture = Fixture::new("lock");
    let _first = UserLock::acquire_for_test(&fixture.admin_home, 1, Duration::ZERO).unwrap();
    assert!(UserLock::acquire_for_test(&fixture.admin_home, 1, Duration::ZERO).is_err());
}

#[cfg(windows)]
#[test]
fn rejects_a_reparse_user_home() {
    let fixture = Fixture::new("reparse-home");
    let target = fixture.root.join("outside");
    fs::create_dir(&target).unwrap();
    create_junction(&fixture.data_home.join("alice"), &target);

    let error = create(&fixture.admin_home, &UserId::parse("alice").unwrap()).unwrap_err();
    assert!(error.contains("regular non-reparse directory"), "{error}");

    fs::remove_dir(fixture.data_home.join("alice")).unwrap();
}

struct Fixture {
    root: PathBuf,
    data_home: PathBuf,
    admin_home: PathBuf,
}

impl Fixture {
    fn new(label: &str) -> Self {
        let sequence = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
        let root = std::env::temp_dir().join(format!(
            "swaw-harness-admin-{label}-{}-{sequence}",
            std::process::id()
        ));
        let data_home = root.join("data");
        let admin_home = data_home.join("admin");
        fs::create_dir_all(admin_home.join("map/core/hello")).unwrap();
        fs::create_dir(admin_home.join("host")).unwrap();
        fs::write(data_home.join("admin.exe"), b"user-cli-v1").unwrap();
        write_skill(&admin_home.join("map/core/hello"));
        fs::write(
            admin_home.join("host").join(pointer_name()),
            format!("{HOST_VERSION}\n"),
        )
        .unwrap();
        write_host_release(&data_home, HOST_VERSION);
        Self {
            root,
            data_home,
            admin_home,
        }
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn write_skill(directory: &Path) {
    fs::create_dir_all(directory).unwrap();
    fs::write(
        directory.join("skill.json"),
        b"{\"schema\":\"swaw.harness.skill/v1\",\"module\":\"swaw/templates/helloworld\",\"version\":\"1.*\",\"executable\":\"helloworld.exe\",\"arguments\":[]}\n",
    )
    .unwrap();
}

fn write_host_release(data_home: &Path, version: &str) {
    let release = data_home
        .join("admin/modules/swaw/core/host")
        .join(PLATFORM_TARGET_ID)
        .join(version);
    fs::create_dir_all(&release).unwrap();
    let executable = b"host";
    fs::write(release.join("swaw-harness-core.exe"), executable).unwrap();
    let sha256 = format!("{:x}", Sha256::digest(executable));
    fs::write(
        release.join("swaw-harness.module.json"),
        format!(
            "{{\"schema\":\"swaw.harness.module/v1\",\"module\":\"swaw/core/host\",\"version\":\"{version}\",\"platformTargetId\":\"{PLATFORM_TARGET_ID}\",\"executable\":{{\"name\":\"swaw-harness-core.exe\",\"length\":{},\"sha256\":\"{sha256}\"}}}}\n",
            executable.len()
        ),
    )
    .unwrap();
}

fn pointer_name() -> String {
    format!("current.{PLATFORM_TARGET_ID}")
}

#[cfg(windows)]
fn create_junction(junction: &Path, target: &Path) {
    let output = std::process::Command::new("cmd.exe")
        .args(["/d", "/c", "mklink", "/j"])
        .arg(junction)
        .arg(fs::canonicalize(target).unwrap())
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "failed to create junction '{}': {}",
        junction.display(),
        String::from_utf8_lossy(&output.stderr)
    );
}
