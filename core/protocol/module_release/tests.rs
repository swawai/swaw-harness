use super::*;
use crate::SkillMap;
use std::time::{SystemTime, UNIX_EPOCH};

const PLATFORM_TARGET_ID: &str = "x86_64-pc-windows-msvc";
const TEST_DATA_HOME_VARIABLE: &str = "SWAW_HARNESS_TEST_DATA_HOME";
const TEST_MODULE_VERSION_VARIABLE: &str = "SWAW_HARNESS_TEST_MODULE_VERSION";
const TEST_PLATFORM_TARGET_VARIABLE: &str = "SWAW_HARNESS_TEST_PLATFORM_TARGET_ID";

#[test]
fn repository_skill_selects_highest_verified_module_release() {
    let data_home = temporary_data_home("highest");
    write_release(
        &data_home,
        "swaw/core/dev",
        "1.0.0",
        "swaw-harness-dev.exe",
        b"one",
    );
    let expected_root = fs::canonicalize(write_release(
        &data_home,
        "swaw/core/dev",
        "1.4.2",
        "swaw-harness-dev.exe",
        b"highest-one",
    ))
    .unwrap();
    write_release(
        &data_home,
        "swaw/core/dev",
        "2.0.0",
        "swaw-harness-dev.exe",
        b"two",
    );

    let map_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data/admin/map/core");
    let skill = SkillMap::open(map_root)
        .unwrap()
        .find("dev/bun/mode")
        .unwrap();
    let declaration = skill.declaration();
    let installed = InstalledModules::open(&data_home).unwrap();
    let selected = installed
        .select(
            declaration.module(),
            declaration.version(),
            PLATFORM_TARGET_ID,
            declaration.executable(),
        )
        .unwrap();

    assert_eq!(selected.module(), declaration.module());
    assert_eq!(selected.version().to_string(), "1.4.2");
    assert_eq!(selected.platform_target_id(), PLATFORM_TARGET_ID);
    assert_eq!(selected.root(), expected_root);
    assert_eq!(
        selected.manifest_path(),
        expected_root.join(MODULE_MANIFEST_NAME)
    );
    assert_eq!(
        selected.executable_path(),
        expected_root.join("swaw-harness-dev.exe")
    );
    assert_eq!(selected.executable_length(), 11);
    assert_eq!(
        selected.executable_sha256(),
        sha256_file(selected.executable_path()).unwrap()
    );

    fs::remove_dir_all(data_home).unwrap();
}

#[test]
fn exact_and_minor_selectors_choose_only_matching_versions() {
    let data_home = temporary_data_home("selectors");
    for version in ["1.2.0", "1.2.7", "1.3.0"] {
        write_release(
            &data_home,
            "swaw/core/dev",
            version,
            "dev.exe",
            version.as_bytes(),
        );
    }
    let installed = InstalledModules::open(&data_home).unwrap();
    let module = ModuleId::parse("swaw/core/dev").unwrap();

    let minor = installed
        .select(
            &module,
            VersionSelector::parse("1.2.*").unwrap(),
            PLATFORM_TARGET_ID,
            "dev.exe",
        )
        .unwrap();
    assert_eq!(minor.version().to_string(), "1.2.7");

    let exact = installed
        .select(
            &module,
            VersionSelector::parse("1.2.0").unwrap(),
            PLATFORM_TARGET_ID,
            "dev.exe",
        )
        .unwrap();
    assert_eq!(exact.version().to_string(), "1.2.0");
    assert!(
        installed
            .select(
                &module,
                VersionSelector::parse("2.0.0").unwrap(),
                PLATFORM_TARGET_ID,
                "dev.exe",
            )
            .is_err()
    );

    fs::remove_dir_all(data_home).unwrap();
}

#[test]
fn corrupt_highest_release_fails_instead_of_falling_back() {
    let data_home = temporary_data_home("corrupt-highest");
    write_release(
        &data_home,
        "swaw/core/dev",
        "1.0.0",
        "dev.exe",
        b"valid-old",
    );
    let corrupt_root = write_release(
        &data_home,
        "swaw/core/dev",
        "1.1.0",
        "dev.exe",
        b"valid-new",
    );
    fs::write(corrupt_root.join("dev.exe"), b"evil!-new").unwrap();

    let installed = InstalledModules::open(&data_home).unwrap();
    let module = ModuleId::parse("swaw/core/dev").unwrap();
    let error = installed
        .select(
            &module,
            VersionSelector::parse("1.*").unwrap(),
            PLATFORM_TARGET_ID,
            "dev.exe",
        )
        .unwrap_err();
    assert!(error.contains("SHA-256"), "{error}");
    assert!(error.contains("1.1.0"), "{error}");

    fs::remove_dir_all(data_home).unwrap();
}

#[test]
fn manifest_identity_and_executable_selection_must_match() {
    let data_home = temporary_data_home("identity");
    let release_root = write_release(&data_home, "swaw/core/dev", "1.0.0", "dev.exe", b"dev");
    let manifest_path = release_root.join(MODULE_MANIFEST_NAME);
    let original = fs::read_to_string(&manifest_path).unwrap();
    fs::write(
        &manifest_path,
        original.replace("swaw/core/dev", "swaw/core/admin"),
    )
    .unwrap();

    let installed = InstalledModules::open(&data_home).unwrap();
    let module = ModuleId::parse("swaw/core/dev").unwrap();
    let error = installed
        .select(
            &module,
            VersionSelector::parse("1.0.0").unwrap(),
            PLATFORM_TARGET_ID,
            "dev.exe",
        )
        .unwrap_err();
    assert!(error.contains("does not match selected module"), "{error}");

    fs::write(&manifest_path, original).unwrap();
    let error = installed
        .select(
            &module,
            VersionSelector::parse("1.0.0").unwrap(),
            PLATFORM_TARGET_ID,
            "other.exe",
        )
        .unwrap_err();
    assert!(
        error.contains("does not match selected executable"),
        "{error}"
    );

    fs::remove_dir_all(data_home).unwrap();
}

#[test]
fn invalid_release_directory_members_are_rejected() {
    let data_home = temporary_data_home("invalid-member");
    write_release(&data_home, "swaw/core/dev", "1.0.0", "dev.exe", b"dev");
    let platform_root = module_platform_root(&data_home, "swaw/core/dev");
    fs::create_dir(platform_root.join("latest")).unwrap();

    let installed = InstalledModules::open(&data_home).unwrap();
    let error = installed
        .select(
            &ModuleId::parse("swaw/core/dev").unwrap(),
            VersionSelector::parse("1.*").unwrap(),
            PLATFORM_TARGET_ID,
            "dev.exe",
        )
        .unwrap_err();
    assert!(
        error.contains("invalid Module Release version directory"),
        "{error}"
    );

    fs::remove_dir_all(data_home).unwrap();
}

#[cfg(windows)]
#[test]
fn reparse_release_directories_cannot_enter_selection() {
    let data_home = temporary_data_home("reparse");
    let target_home = temporary_data_home("reparse-target");
    let target_release = write_release(
        &target_home,
        "swaw/core/dev",
        "1.0.0",
        "dev.exe",
        b"outside",
    );
    let platform_root = module_platform_root(&data_home, "swaw/core/dev");
    fs::create_dir_all(&platform_root).unwrap();
    create_junction(&platform_root.join("1.0.0"), &target_release);

    let installed = InstalledModules::open(&data_home).unwrap();
    let error = installed
        .select(
            &ModuleId::parse("swaw/core/dev").unwrap(),
            VersionSelector::parse("1.*").unwrap(),
            PLATFORM_TARGET_ID,
            "dev.exe",
        )
        .unwrap_err();
    assert!(error.contains("non-regular release directory"), "{error}");

    fs::remove_dir(platform_root.join("1.0.0")).unwrap();
    fs::remove_dir_all(data_home).unwrap();
    fs::remove_dir_all(target_home).unwrap();
}

#[cfg(windows)]
#[test]
#[ignore = "requires Windows Bootstrap to materialize repository Module Releases"]
fn repository_installed_skill_runs_and_writes_export() {
    let data_home = PathBuf::from(
        std::env::var_os(TEST_DATA_HOME_VARIABLE)
            .unwrap_or_else(|| panic!("{TEST_DATA_HOME_VARIABLE} is required")),
    );
    let platform_target_id = std::env::var(TEST_PLATFORM_TARGET_VARIABLE)
        .unwrap_or_else(|_| panic!("{TEST_PLATFORM_TARGET_VARIABLE} is required"));
    let expected_version = std::env::var(TEST_MODULE_VERSION_VARIABLE)
        .unwrap_or_else(|_| panic!("{TEST_MODULE_VERSION_VARIABLE} is required"));
    let skill = SkillMap::open(data_home.join("admin").join("map").join("core"))
        .unwrap()
        .find("dev/bun/mode")
        .unwrap();
    let declaration = skill.declaration();
    let selected = InstalledModules::open(&data_home)
        .unwrap()
        .select(
            declaration.module(),
            declaration.version(),
            &platform_target_id,
            declaration.executable(),
        )
        .unwrap();
    assert_eq!(selected.version().to_string(), expected_version);

    let entry_root = temporary_entry_root("installed-skill");
    let output = std::process::Command::new(selected.executable_path())
        .args(declaration.arguments())
        .arg("managed")
        .env(crate::ENTRY_ROOT_ENVIRONMENT_VARIABLE, &entry_root)
        .current_dir(selected.root())
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(String::from_utf8(output.stdout).unwrap(), "managed\n");
    assert_eq!(
        fs::read_to_string(entry_root.join("export/dev/bun/mode/mode.json")).unwrap(),
        concat!(
            "{\n",
            "  \"schema\": \"swaw.harness.dev-bun-mode/v1\",\n",
            "  \"mode\": \"managed\"\n",
            "}\n"
        )
    );

    fs::remove_dir_all(entry_root).unwrap();
}

fn temporary_data_home(label: &str) -> PathBuf {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let data_home = std::env::temp_dir().join(format!(
        "swaw-harness-installed-modules-{label}-{}-{unique}",
        std::process::id()
    ));
    fs::create_dir_all(data_home.join("admin").join("modules")).unwrap();
    data_home
}

fn temporary_entry_root(label: &str) -> PathBuf {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let entry_root = std::env::temp_dir().join(format!(
        "swaw-harness-entry-{label}-{}-{unique}",
        std::process::id()
    ));
    fs::create_dir(&entry_root).unwrap();
    entry_root
}

fn write_release(
    data_home: &Path,
    module: &str,
    version: &str,
    executable_name: &str,
    executable: &[u8],
) -> PathBuf {
    let release_root = module_platform_root(data_home, module).join(version);
    fs::create_dir_all(&release_root).unwrap();
    let executable_path = release_root.join(executable_name);
    fs::write(&executable_path, executable).unwrap();
    let sha256 = sha256_file(&executable_path).unwrap();
    fs::write(
        release_root.join(MODULE_MANIFEST_NAME),
        format!(
            concat!(
                "{{\n",
                "  \"schema\": \"swaw.harness.module/v1\",\n",
                "  \"module\": \"{}\",\n",
                "  \"version\": \"{}\",\n",
                "  \"platformTargetId\": \"{}\",\n",
                "  \"executable\": {{\n",
                "    \"name\": \"{}\",\n",
                "    \"length\": {},\n",
                "    \"sha256\": \"{}\"\n",
                "  }}\n",
                "}}\n"
            ),
            module,
            version,
            PLATFORM_TARGET_ID,
            executable_name,
            executable.len(),
            sha256
        ),
    )
    .unwrap();
    release_root
}

fn module_platform_root(data_home: &Path, module: &str) -> PathBuf {
    let mut root = data_home.join("admin").join("modules");
    for segment in module.split('/') {
        root.push(segment);
    }
    root.join(PLATFORM_TARGET_ID)
}

#[cfg(windows)]
fn create_junction(junction: &Path, target: &Path) {
    let target = fs::canonicalize(target).unwrap();
    let output = std::process::Command::new("cmd.exe")
        .args(["/d", "/c", "mklink", "/j"])
        .arg(junction)
        .arg(&target)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "failed to create junction '{}' -> '{}': stdout='{}', stderr='{}'",
        junction.display(),
        target.display(),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}
