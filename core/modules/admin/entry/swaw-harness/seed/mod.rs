use std::fs;
use std::path::Path;
use std::time::Duration;

use crate::entry::layout::ADMIN_ENTRY_ID;
use crate::entry::release::ENTRY_ARTIFACT_NAME;
use crate::entry::{
    EntryId, EntryLayout, EntryLifecycleState, EntryRecord, FileLock, ProvisioningRecord,
    ValidatedRelease, assert_case_spelling, assert_regular_directory, assert_regular_file,
    clean_stage_directories, copy_file_atomic, create_stage_directory, ensure_child_directory,
    ensure_root_directory, move_directory, path_exists, paths_overlap, read_bounded,
    remove_regular_file_if_present, remove_tree, same_file_contents, validate_harness_root,
    write_atomic,
};

const LOCK_TIMEOUT: Duration = Duration::from_secs(120);
const SEED_STAGE_PREFIX: &str = "swaw-harness.seed";
const RUNTIME_STAGE_PREFIX: &str = "release";
const MAXIMUM_RECORD_BYTES: u64 = 1_048_576;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SeedOutcome {
    Created,
    Recovered,
    AlreadyActiveSameRelease,
    AlreadyActiveOtherRelease,
}

impl SeedOutcome {
    pub(crate) const fn message(self) -> &'static str {
        match self {
            Self::Created => "seeded canonical Admin Entry",
            Self::Recovered => "recovered canonical Admin Entry provisioning",
            Self::AlreadyActiveSameRelease => {
                "canonical Admin Entry already active from this Release"
            }
            Self::AlreadyActiveOtherRelease => {
                "canonical Admin Entry already active from another Release; seed left it unchanged"
            }
        }
    }
}

pub(crate) fn run(executable: &Path, harness_root: &Path) -> Result<SeedOutcome, String> {
    let source = ValidatedRelease::from_executable(executable)?;
    let harness_root = validate_harness_root(harness_root)?;
    let entry_id = EntryId::parse(ADMIN_ENTRY_ID).map_err(|error| error.to_string())?;
    let layout = EntryLayout::new(&harness_root, &entry_id);

    if paths_overlap(source.root(), layout.data_home()) && !path_exists(layout.entry_root()) {
        return Err(
            "source Release cannot be inside the target DataHome for a fresh seed".to_owned(),
        );
    }
    prepare_management_directories(&layout)?;
    let _lock = FileLock::acquire(layout.lock(), LOCK_TIMEOUT)?;
    clean_stage_directories(layout.data_home(), SEED_STAGE_PREFIX)?;
    assert_entry_namespace(&layout, &entry_id)?;

    if !path_exists(layout.entry_root()) {
        if path_exists(layout.executable()) {
            return Err(format!(
                "unrecognized orphan Entry executable blocks seed: {}",
                layout.executable().display()
            ));
        }
        if paths_overlap(source.root(), layout.data_home()) {
            return Err(
                "source Release cannot be inside the target DataHome for a fresh seed".to_owned(),
            );
        }
        return provision_fresh(&source, &layout, &entry_id);
    }

    assert_regular_directory(layout.entry_root(), "canonical Admin EntryRoot")?;
    let record = read_entry_record(&layout, &entry_id)?;
    match record.lifecycle() {
        EntryLifecycleState::Provisioning => {
            if paths_overlap(source.root(), layout.data_home()) {
                return Err(
                    "source Release cannot be inside the target DataHome during provisioning"
                        .to_owned(),
                );
            }
            recover_provisioning(&source, &layout, &entry_id)
        }
        EntryLifecycleState::Active => validate_active(&source, &layout),
        EntryLifecycleState::Deleting => {
            Err("canonical Admin Entry is deleting and cannot be seeded".to_owned())
        }
    }
}

fn prepare_management_directories(layout: &EntryLayout) -> Result<(), String> {
    ensure_root_directory(layout.harness_root())?;
    let data_home = ensure_child_directory(layout.harness_root(), "data")?;
    if data_home != layout.data_home() {
        return Err("managed directory construction did not match the canonical layout".to_owned());
    }
    let control_root = ensure_child_directory(layout.data_home(), ".harness")?;
    if control_root != layout.control_root() {
        return Err("managed control directory did not match the canonical layout".to_owned());
    }
    Ok(())
}

fn assert_entry_namespace(layout: &EntryLayout, entry_id: &EntryId) -> Result<(), String> {
    assert_case_spelling(layout.data_home(), entry_id.as_str())?;
    assert_case_spelling(layout.data_home(), &format!("{entry_id}.exe"))?;
    if path_exists(layout.entry_root()) {
        assert_regular_directory(layout.entry_root(), "canonical Admin EntryRoot")?;
    }
    if path_exists(layout.executable()) {
        assert_regular_file(layout.executable(), "canonical Admin Entry executable")?;
    }
    Ok(())
}

fn provision_fresh(
    source: &ValidatedRelease,
    layout: &EntryLayout,
    entry_id: &EntryId,
) -> Result<SeedOutcome, String> {
    let stage_parent = create_stage_directory(layout.data_home(), SEED_STAGE_PREFIX)?;
    let result = (|| {
        let staged_entry = stage_parent.join(entry_id.as_str());
        fs::create_dir(&staged_entry).map_err(|error| {
            format!(
                "cannot create staged canonical Admin EntryRoot '{}': {error}",
                staged_entry.display()
            )
        })?;
        let runtime_root = staged_entry.join("runtime");
        fs::create_dir(&runtime_root).map_err(|error| {
            format!(
                "cannot create staged Runtime root '{}': {error}",
                runtime_root.display()
            )
        })?;
        let runtime_release = runtime_root.join(source.release_id());
        source.copy_to(&runtime_release)?;
        write_selector(
            &runtime_root.join(format!("current.{}", source.platform_target_id())),
            source.release_id(),
        )?;
        write_atomic(
            &staged_entry.join("provisioning.json"),
            &ProvisioningRecord::new(
                source.release_id().to_owned(),
                source.platform_target_id().to_owned(),
            )
            .encode_json()
            .map_err(|error| error.to_string())?,
        )?;
        write_atomic(
            &staged_entry.join("entry.json"),
            &EntryRecord::new(entry_id.clone(), EntryLifecycleState::Provisioning)
                .encode_json()
                .map_err(|error| error.to_string())?,
        )?;
        move_directory(&staged_entry, layout.entry_root())?;
        fs::remove_dir(&stage_parent).map_err(|error| {
            format!(
                "cannot remove completed seed stage '{}': {error}",
                stage_parent.display()
            )
        })?;
        activate_provisioning(source, layout, entry_id)?;
        Ok(SeedOutcome::Created)
    })();
    if path_exists(&stage_parent) {
        let _ = remove_tree(&stage_parent, layout.data_home());
    }
    result
}

fn recover_provisioning(
    source: &ValidatedRelease,
    layout: &EntryLayout,
    entry_id: &EntryId,
) -> Result<SeedOutcome, String> {
    let transaction = read_provisioning_record(layout)?;
    assert_transaction_matches(&transaction, source)?;
    activate_provisioning(source, layout, entry_id)?;
    Ok(SeedOutcome::Recovered)
}

fn activate_provisioning(
    source: &ValidatedRelease,
    layout: &EntryLayout,
    entry_id: &EntryId,
) -> Result<(), String> {
    let record = read_entry_record(layout, entry_id)?;
    if record.lifecycle() != EntryLifecycleState::Provisioning {
        return Err("activation requires a provisioning Entry record".to_owned());
    }
    let transaction = read_provisioning_record(layout)?;
    assert_transaction_matches(&transaction, source)?;

    ensure_runtime_release(source, layout)?;
    write_selector(
        &layout.runtime_selector(source.platform_target_id()),
        source.release_id(),
    )?;
    let installed = ValidatedRelease::open(&layout.runtime_release(source.release_id()))?;
    let launcher = installed.artifact_path(ENTRY_ARTIFACT_NAME)?;
    copy_file_atomic(&launcher, layout.executable())?;
    if !same_file_contents(&launcher, layout.executable())? {
        return Err(
            "installed Entry executable does not match the selected Runtime Release".to_owned(),
        );
    }
    write_atomic(
        layout.record(),
        &EntryRecord::new(entry_id.clone(), EntryLifecycleState::Active)
            .encode_json()
            .map_err(|error| error.to_string())?,
    )?;
    remove_regular_file_if_present(layout.provisioning())?;
    Ok(())
}

fn ensure_runtime_release(source: &ValidatedRelease, layout: &EntryLayout) -> Result<(), String> {
    if !path_exists(layout.runtime_root()) {
        fs::create_dir(layout.runtime_root()).map_err(|error| {
            format!(
                "cannot create Runtime Release root '{}': {error}",
                layout.runtime_root().display()
            )
        })?;
    }
    assert_regular_directory(layout.runtime_root(), "Runtime Release root")?;
    clean_stage_directories(layout.runtime_root(), RUNTIME_STAGE_PREFIX)?;
    let target = layout.runtime_release(source.release_id());
    if path_exists(&target) {
        if ValidatedRelease::open(&target).is_ok() {
            return Ok(());
        }
        remove_tree(&target, layout.runtime_root())?;
    }

    let stage_parent = create_stage_directory(layout.runtime_root(), RUNTIME_STAGE_PREFIX)?;
    let staged_release = stage_parent.join(source.release_id());
    let result = (|| {
        source.copy_to(&staged_release)?;
        move_directory(&staged_release, &target)?;
        fs::remove_dir(&stage_parent).map_err(|error| {
            format!(
                "cannot remove completed Runtime stage '{}': {error}",
                stage_parent.display()
            )
        })?;
        Ok(())
    })();
    if path_exists(&stage_parent) {
        let _ = remove_tree(&stage_parent, layout.runtime_root());
    }
    result
}

fn validate_active(source: &ValidatedRelease, layout: &EntryLayout) -> Result<SeedOutcome, String> {
    let selected_id = read_selector(&layout.runtime_selector(source.platform_target_id()))?;
    let same_release = selected_id == source.release_id();
    if same_release {
        ensure_runtime_release(source, layout)?;
    }
    let installed = ValidatedRelease::open(&layout.runtime_release(&selected_id))?;
    if installed.platform_target_id() != source.platform_target_id() {
        return Err(format!(
            "active Runtime Release target '{}' does not match source target '{}'",
            installed.platform_target_id(),
            source.platform_target_id()
        ));
    }
    let launcher = installed.artifact_path(ENTRY_ARTIFACT_NAME)?;
    let launcher_matches = if path_exists(layout.executable()) {
        same_file_contents(&launcher, layout.executable())?
    } else {
        false
    };
    if !launcher_matches {
        if !same_release {
            return Err(
                "active Entry executable does not match its selected Runtime Release".to_owned(),
            );
        }
        copy_file_atomic(&launcher, layout.executable())?;
        if !same_file_contents(&launcher, layout.executable())? {
            return Err(
                "repaired Entry executable does not match its selected Runtime Release".to_owned(),
            );
        }
    }
    if path_exists(layout.provisioning()) {
        let transaction = read_provisioning_record(layout)?;
        assert_transaction_matches_identity(
            &transaction,
            &selected_id,
            source.platform_target_id(),
        )?;
        remove_regular_file_if_present(layout.provisioning())?;
    }
    if same_release {
        Ok(SeedOutcome::AlreadyActiveSameRelease)
    } else {
        Ok(SeedOutcome::AlreadyActiveOtherRelease)
    }
}

fn read_entry_record(layout: &EntryLayout, entry_id: &EntryId) -> Result<EntryRecord, String> {
    let encoded = read_bounded(layout.record(), MAXIMUM_RECORD_BYTES, "Entry record")?;
    EntryRecord::decode_json(&encoded, entry_id).map_err(|error| error.to_string())
}

fn read_provisioning_record(layout: &EntryLayout) -> Result<ProvisioningRecord, String> {
    let encoded = read_bounded(
        layout.provisioning(),
        MAXIMUM_RECORD_BYTES,
        "Entry provisioning record",
    )?;
    ProvisioningRecord::decode_json(&encoded).map_err(|error| error.to_string())
}

fn assert_transaction_matches(
    transaction: &ProvisioningRecord,
    source: &ValidatedRelease,
) -> Result<(), String> {
    assert_transaction_matches_identity(
        transaction,
        source.release_id(),
        source.platform_target_id(),
    )
}

fn assert_transaction_matches_identity(
    transaction: &ProvisioningRecord,
    release_id: &str,
    platform_target_id: &str,
) -> Result<(), String> {
    if transaction.release_id() != release_id
        || transaction.platform_target_id() != platform_target_id
    {
        return Err(format!(
            "unfinished provisioning is pinned to Release '{}', not '{}'",
            transaction.release_id(),
            release_id
        ));
    }
    Ok(())
}

fn write_selector(path: &Path, release_id: &str) -> Result<(), String> {
    write_atomic(path, format!("{release_id}\n").as_bytes())
}

fn read_selector(path: &Path) -> Result<String, String> {
    let bytes = read_bounded(path, 65, "Runtime Release selector")?;
    if bytes.len() != 65 || bytes[64] != b'\n' {
        return Err(format!(
            "Runtime Release selector has invalid framing: {}",
            path.display()
        ));
    }
    let release_id = std::str::from_utf8(&bytes[..64])
        .map_err(|error| format!("Runtime Release selector is not ASCII: {error}"))?;
    if !release_id
        .bytes()
        .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(format!(
            "Runtime Release selector has invalid identity: {release_id}"
        ));
    }
    Ok(release_id.to_owned())
}
