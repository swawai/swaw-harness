use super::*;
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn repository_skill_map_is_valid_and_skills_select_modules_directly() {
    let user_home = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data/admin");
    let skill_map = SkillMap::open_core(user_home).unwrap();
    skill_map.validate().unwrap();

    for (skill_path, module, executable, arguments) in [
        (
            "helloworld",
            "swaw/templates/helloworld",
            "helloworld.exe",
            &[][..],
        ),
        (
            "dev/bun/mode",
            "swaw/core/dev",
            "swaw-harness-dev.exe",
            &["dev/bun/mode"][..],
        ),
    ] {
        let node = skill_map.find(skill_path).unwrap();
        assert_eq!(node.path(), skill_path);
        assert_eq!(node.declaration().module().as_str(), module);
        assert_eq!(node.declaration().version().to_string(), "1.*");
        assert_eq!(node.declaration().executable(), executable);
        assert_eq!(node.declaration().arguments(), arguments);
    }
    assert!(skill_map.find("dev/setup").is_err());
}

#[test]
fn core_skill_map_requires_canonical_fixed_directory_names() {
    for (relative_root, expected_error) in [
        ("Map/core", "non-canonical Skill Map root name 'Map'"),
        ("map/Core", "non-canonical Core Skill Map name 'Core'"),
    ] {
        let user_home = temporary_map("core-root-case");
        fs::create_dir_all(user_home.join(relative_root)).unwrap();

        let error = SkillMap::open_core(&user_home).unwrap_err();
        assert!(error.contains(expected_error), "{error}");

        fs::remove_dir_all(user_home).unwrap();
    }
}

#[test]
fn semantic_version_selectors_are_small_and_deterministic() {
    let versions = [
        Version::parse("1.0.0").unwrap(),
        Version::parse("1.2.4").unwrap(),
        Version::parse("1.3.0").unwrap(),
        Version::parse("2.0.0").unwrap(),
    ];
    for (selector, expected) in [
        ("1.2.4", "1.2.4"),
        ("1.2.*", "1.2.4"),
        ("1.*", "1.3.0"),
        ("2.*", "2.0.0"),
    ] {
        let selected = VersionSelector::parse(selector)
            .unwrap()
            .select_highest(versions)
            .unwrap();
        assert_eq!(selected.to_string(), expected);
    }
    for invalid in ["", "1", "1.2", "01.2.3", "1.02.*", "0.*", "0.2.*", "^1.2"] {
        assert!(VersionSelector::parse(invalid).is_err(), "{invalid}");
    }
}

#[test]
fn unsafe_paths_and_skill_documents_are_rejected() {
    let root = temporary_map("invalid-skill");
    write_skill(
        &root.join("dev/setup"),
        "swaw/core/dev",
        "1.*",
        "swaw-harness-dev.exe",
        &["dev/setup"],
    );
    let skill_map = SkillMap::open(&root).unwrap();
    for skill_path in [
        "",
        "../dev",
        "/dev",
        "DEV",
        "dev/Setup",
        "dev\\setup",
        "dev//setup",
    ] {
        assert!(skill_map.find(skill_path).is_err(), "{skill_path}");
    }

    for (module, version, executable) in [
        ("swaw/dev", "1.*", "dev.exe"),
        ("swaw/core/dev/extra", "1.*", "dev.exe"),
        ("Swaw/core/dev", "1.*", "dev.exe"),
        ("swaw/core/dev", "0.*", "dev.exe"),
        ("swaw/core/dev", "1.02.*", "dev.exe"),
        ("swaw/core/dev", "1.*", "../dev.exe"),
    ] {
        write_skill(&root.join("dev/setup"), module, version, executable, &[]);
        let skill_map = SkillMap::open(&root).unwrap();
        assert!(skill_map.find("dev/setup").is_err(), "{module}");
    }

    fs::write(
        root.join("dev/setup").join(SKILL_DOCUMENT_NAME),
        "{\"schema\":\"swaw.harness.skill/v1\",\"module\":\"swaw/core/dev\",\"version\":\"1.*\",\"executable\":\"dev.exe\",\"arguments\":[],\"extra\":true}\n",
    )
    .unwrap();
    let skill_map = SkillMap::open(&root).unwrap();
    assert!(skill_map.find("dev/setup").is_err());
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn executable_skill_nodes_can_contain_child_skills() {
    let root = temporary_map("node-shape");
    write_skill(
        &root.join("dev/setup"),
        "swaw/core/dev",
        "1.*",
        "dev.exe",
        &["dev/setup"],
    );
    write_skill(
        &root.join("dev/setup/check"),
        "swaw/core/dev",
        "1.*",
        "dev.exe",
        &["dev/setup/check"],
    );

    let skill_map = SkillMap::open(&root).unwrap();
    skill_map.validate().unwrap();
    skill_map.find("dev/setup").unwrap();
    skill_map.find("dev/setup/check").unwrap();

    for legacy_name in [
        "swaw-harness.facet.json",
        "swaw-harness.resource.json",
        "swaw-harness.executable.json",
    ] {
        let legacy_path = root.join("dev/setup").join(legacy_name);
        fs::write(&legacy_path, "{}\n").unwrap();
        assert!(skill_map.validate().is_err(), "{legacy_name}");
        fs::remove_file(legacy_path).unwrap();
    }
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn skill_map_root_cannot_be_executable() {
    let root = temporary_map("root-skill");
    write_skill(&root, "swaw/core/dev", "1.*", "dev.exe", &[]);
    let skill_map = SkillMap::open(&root).unwrap();
    assert!(skill_map.validate().is_err());
    fs::remove_dir_all(root).unwrap();
}

#[cfg(windows)]
#[test]
fn reparse_directories_cannot_enter_resolution() {
    let root = temporary_map("map-reparse");
    let skill_target = temporary_map("skill-target");
    write_skill(
        &skill_target.join("setup"),
        "swaw/core/dev",
        "1.*",
        "dev.exe",
        &[],
    );
    create_junction(&root.join("dev"), &skill_target);
    let skill_map = SkillMap::open(&root).unwrap();
    assert!(skill_map.validate().is_err());
    assert!(skill_map.find("dev/setup").is_err());

    fs::remove_dir(root.join("dev")).unwrap();
    fs::remove_dir_all(root).unwrap();
    fs::remove_dir_all(skill_target).unwrap();

    let user_home = temporary_map("map-parent-reparse");
    let map_target = temporary_map("map-parent-target");
    fs::create_dir(map_target.join("core")).unwrap();
    create_junction(&user_home.join("map"), &map_target);
    assert!(SkillMap::open_core(&user_home).is_err());

    fs::remove_dir(user_home.join("map")).unwrap();
    fs::remove_dir_all(user_home).unwrap();
    fs::remove_dir_all(map_target).unwrap();
}

#[cfg(windows)]
#[test]
fn direct_resolution_rejects_noncanonical_disk_spelling() {
    let directory_root = temporary_map("directory-case");
    write_skill(
        &directory_root.join("Dev/setup"),
        "swaw/core/dev",
        "1.*",
        "dev.exe",
        &[],
    );
    let skill_map = SkillMap::open(&directory_root).unwrap();
    let error = skill_map.find("dev/setup").unwrap_err();
    assert!(error.contains("non-canonical Skill directory name 'Dev'"));
    fs::remove_dir_all(directory_root).unwrap();

    let document_root = temporary_map("document-case");
    let skill_directory = document_root.join("dev/setup");
    fs::create_dir_all(&skill_directory).unwrap();
    fs::write(
        skill_directory.join("Skill.json"),
        "{\"schema\":\"swaw.harness.skill/v1\",\"module\":\"swaw/core/dev\",\"version\":\"1.*\",\"executable\":\"dev.exe\",\"arguments\":[]}\n",
    )
    .unwrap();
    let skill_map = SkillMap::open(&document_root).unwrap();
    let error = skill_map.find("dev/setup").unwrap_err();
    assert!(error.contains("non-canonical Skill declaration name 'Skill.json'"));
    fs::remove_dir_all(document_root).unwrap();
}

fn temporary_map(label: &str) -> PathBuf {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "swaw-harness-skill-map-{label}-{}-{unique}",
        std::process::id()
    ));
    fs::create_dir(&root).unwrap();
    root
}

fn write_skill(
    directory: &Path,
    module: &str,
    version: &str,
    executable: &str,
    arguments: &[&str],
) {
    fs::create_dir_all(directory).unwrap();
    let arguments = arguments
        .iter()
        .map(|argument| format!("\"{argument}\""))
        .collect::<Vec<_>>()
        .join(",");
    fs::write(
        directory.join(SKILL_DOCUMENT_NAME),
        format!(
            "{{\"schema\":\"swaw.harness.skill/v1\",\"module\":\"{module}\",\"version\":\"{version}\",\"executable\":\"{executable}\",\"arguments\":[{arguments}]}}\n"
        ),
    )
    .unwrap();
}

#[cfg(windows)]
fn create_junction(junction: &Path, target: &Path) {
    let junction = junction.components().collect::<PathBuf>();
    let target = fs::canonicalize(target).unwrap();
    let output = std::process::Command::new("cmd.exe")
        .args(["/d", "/c", "mklink", "/j"])
        .arg(&junction)
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
