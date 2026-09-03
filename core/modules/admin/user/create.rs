use std::fs;
use std::path::{Path, PathBuf};

use swaw_harness_core_protocol::{UserLifecycle, UserRecord, Version};

use super::UserId;
use super::layout::{
    Layout, copy_tree, find_named_entry, host_pointer_name, remove_stage,
    remove_stale_user_home_stage, require_exact_path, require_regular_directory, user_home_stage,
    validate_core_map, validate_host_pointer,
};
use super::lock::UserLock;
use super::publication::{
    UserCliArtifact, remove_stale_publication_stage, replace_record, verify_identity,
    write_new_synced, write_record_new,
};

pub(crate) fn create(invocation_user_home: &Path, user_id: &UserId) -> Result<(), String> {
    let layout = Layout::discover(invocation_user_home, user_id)?;
    let _lock = UserLock::acquire(&layout.admin_home)?;

    let user_home = find_named_entry(&layout.data_home, user_id.as_str())?;
    let user_cli = find_named_entry(&layout.data_home, &format!("{user_id}.exe"))?;
    match (user_home, user_cli) {
        (None, None) => {
            remove_stale_creation_stages(&layout, user_id, None)?;
            create_new(&layout, user_id)
        }
        (Some(user_home), user_cli) => resume_or_verify(&layout, user_id, &user_home, user_cli),
        (None, Some(user_cli)) => {
            remove_stale_creation_stages(&layout, user_id, None)?;
            Err(format!(
                "Harness User creation is incomplete because the User CLI exists without UserHome: {}",
                user_cli.display()
            ))
        }
    }
}

fn create_new(layout: &Layout, user_id: &UserId) -> Result<(), String> {
    let source = SourceSnapshot::read(layout)?;
    let stage = user_home_stage(&layout.data_home, user_id);
    fs::create_dir(&stage).map_err(|error| {
        format!(
            "cannot create staged UserHome '{}': {error}",
            stage.display()
        )
    })?;
    let result = (|| {
        prepare_user_home(&stage, user_id, &source)?;
        validate_user_home(&stage, user_id, UserLifecycle::Creating, layout)?;
        fs::rename(&stage, &layout.user_home).map_err(|error| {
            format!(
                "cannot commit UserHome '{}': {error}",
                layout.user_home.display()
            )
        })?;
        source.user_cli.install_new(&layout.user_cli)?;
        activate(&layout.user_home, user_id, layout)
    })();
    if let Err(error) = result {
        return match fs::symlink_metadata(&stage) {
            Ok(_) => match remove_stage(&stage) {
                Ok(()) => Err(error),
                Err(cleanup) => Err(format!(
                    "{error}; staged UserHome cleanup also failed: {cleanup}"
                )),
            },
            Err(missing) if missing.kind() == std::io::ErrorKind::NotFound => Err(error),
            Err(cleanup) => Err(format!(
                "{error}; cannot inspect staged UserHome for cleanup '{}': {cleanup}",
                stage.display()
            )),
        };
    }
    Ok(())
}

fn resume_or_verify(
    layout: &Layout,
    user_id: &UserId,
    user_home: &Path,
    user_cli: Option<PathBuf>,
) -> Result<(), String> {
    require_exact_path(user_home, &layout.user_home, "UserHome")?;
    require_regular_directory(user_home, "UserHome")?;
    let record = UserRecord::read(user_home, user_id.as_str())?;

    match record.lifecycle() {
        UserLifecycle::Active => {
            let user_cli = user_cli.ok_or_else(|| {
                format!(
                    "active Harness User is missing its User CLI executable: {}",
                    layout.user_cli.display()
                )
            })?;
            require_exact_path(&user_cli, &layout.user_cli, "User CLI executable")?;
            verify_identity(&user_cli, record.user_cli())?;
            validate_user_home(user_home, user_id, UserLifecycle::Active, layout)
        }
        UserLifecycle::Creating => {
            remove_stale_creation_stages(layout, user_id, Some(user_home))?;
            validate_user_home(user_home, user_id, UserLifecycle::Creating, layout)?;
            match user_cli {
                Some(user_cli) => {
                    require_exact_path(&user_cli, &layout.user_cli, "User CLI executable")?;
                    verify_identity(&user_cli, record.user_cli())?;
                }
                None => install_missing_cli(layout, user_id, user_home, &record)?,
            }
            activate(user_home, user_id, layout)
        }
    }
}

fn remove_stale_creation_stages(
    layout: &Layout,
    user_id: &UserId,
    user_home: Option<&Path>,
) -> Result<(), String> {
    remove_stale_user_home_stage(&layout.data_home, user_id)?;
    remove_stale_publication_stage(&layout.user_cli, "staged User CLI executable")?;
    if let Some(user_home) = user_home {
        remove_stale_publication_stage(&user_home.join("user.json"), "staged Harness User record")?;
    }
    Ok(())
}

fn install_missing_cli(
    layout: &Layout,
    user_id: &UserId,
    user_home: &Path,
    record: &UserRecord,
) -> Result<(), String> {
    let current = UserCliArtifact::read(&layout.admin_cli)?;
    if current.identity() != record.user_cli() {
        replace_record(
            &user_home.join("user.json"),
            &UserRecord::new(
                user_id.as_str(),
                UserLifecycle::Creating,
                current.identity().clone(),
            )?,
        )?;
    }
    current.install_new(&layout.user_cli)
}

fn activate(user_home: &Path, user_id: &UserId, layout: &Layout) -> Result<(), String> {
    let record = UserRecord::read(user_home, user_id.as_str())?;
    verify_identity(&layout.user_cli, record.user_cli())?;
    replace_record(
        &user_home.join("user.json"),
        &record.with_lifecycle(UserLifecycle::Active),
    )?;
    validate_user_home(user_home, user_id, UserLifecycle::Active, layout)
}

fn prepare_user_home(
    stage: &Path,
    user_id: &UserId,
    source: &SourceSnapshot,
) -> Result<(), String> {
    let map_root = stage.join("map");
    fs::create_dir(&map_root).map_err(|error| {
        format!(
            "cannot create staged Skill Map root '{}': {error}",
            map_root.display()
        )
    })?;
    copy_tree(&source.core_map, &map_root.join("core"), 0)?;

    let host_root = stage.join("host");
    fs::create_dir(&host_root).map_err(|error| {
        format!(
            "cannot create staged Core Host selection root '{}': {error}",
            host_root.display()
        )
    })?;
    write_new_synced(
        &host_root.join(host_pointer_name()),
        format!("{}\n", source.host_version).as_bytes(),
    )?;
    write_record_new(
        &stage.join("user.json"),
        &UserRecord::new(
            user_id.as_str(),
            UserLifecycle::Creating,
            source.user_cli.identity().clone(),
        )?,
    )
}

fn validate_user_home(
    user_home: &Path,
    user_id: &UserId,
    expected_lifecycle: UserLifecycle,
    layout: &Layout,
) -> Result<(), String> {
    require_regular_directory(user_home, "UserHome")?;
    let record = UserRecord::read(user_home, user_id.as_str())?;
    if record.lifecycle() != expected_lifecycle {
        return Err(format!(
            "Harness User lifecycle is {:?}; expected {:?}: {}",
            record.lifecycle(),
            expected_lifecycle,
            user_home.display()
        ));
    }
    validate_core_map(user_home)?;
    validate_host_pointer(user_home, &layout.data_home)?;
    Ok(())
}

struct SourceSnapshot {
    core_map: PathBuf,
    host_version: Version,
    user_cli: UserCliArtifact,
}

impl SourceSnapshot {
    fn read(layout: &Layout) -> Result<Self, String> {
        Ok(Self {
            core_map: validate_core_map(&layout.admin_home)?,
            host_version: validate_host_pointer(&layout.admin_home, &layout.data_home)?,
            user_cli: UserCliArtifact::read(&layout.admin_cli)?,
        })
    }
}
