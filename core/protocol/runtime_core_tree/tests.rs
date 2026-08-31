use super::*;
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn repository_tree_is_valid_and_facets_select_modules_directly() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data/admin/core");
    let tree = RuntimeCoreTree::open(root).unwrap();
    tree.validate().unwrap();

    for (resource, facet, module, executable, arguments) in [
        (
            "dev/setup",
            "execute",
            "swaw/core/dev",
            "swaw-harness-dev.exe",
            &["dev/setup"][..],
        ),
        (
            "dev/bun/mode",
            "execute",
            "swaw/core/dev",
            "swaw-harness-dev.exe",
            &["dev/bun/mode"][..],
        ),
    ] {
        let resolved = tree.resolve(resource, facet).unwrap();
        assert_eq!(resolved.resource(), resource);
        assert_eq!(resolved.facet(), facet);
        assert_eq!(resolved.definition().module().as_str(), module);
        assert_eq!(resolved.definition().version().to_string(), "1.*");
        assert_eq!(resolved.definition().executable(), executable);
        assert_eq!(resolved.definition().arguments(), arguments);
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
fn unsafe_routes_and_facet_documents_are_rejected() {
    let root = temporary_tree("invalid-facet");
    write_facet(
        &root.join("dev/setup/execute"),
        "swaw/core/dev",
        "1.*",
        "swaw-harness-dev.exe",
        &["dev/setup"],
    );
    let tree = RuntimeCoreTree::open(&root).unwrap();
    for resource in [
        "",
        "../dev",
        "/dev",
        "DEV",
        "dev/Setup",
        "dev\\setup",
        "dev//setup",
    ] {
        assert!(tree.resolve(resource, "execute").is_err(), "{resource}");
    }
    assert!(tree.resolve("dev/setup", "Execute").is_err());

    for (module, version, executable) in [
        ("swaw/dev", "1.*", "dev.exe"),
        ("swaw/core/dev/extra", "1.*", "dev.exe"),
        ("Swaw/core/dev", "1.*", "dev.exe"),
        ("swaw/core/dev", "0.*", "dev.exe"),
        ("swaw/core/dev", "1.02.*", "dev.exe"),
        ("swaw/core/dev", "1.*", "../dev.exe"),
    ] {
        write_facet(
            &root.join("dev/setup/execute"),
            module,
            version,
            executable,
            &[],
        );
        let tree = RuntimeCoreTree::open(&root).unwrap();
        assert!(tree.resolve("dev/setup", "execute").is_err(), "{module}");
    }

    fs::write(
        root.join("dev/setup/execute").join(FACET_DOCUMENT_NAME),
        "{\"schema\":\"swaw.harness.facet/v1\",\"module\":\"swaw/core/dev\",\"version\":\"1.*\",\"executable\":\"dev.exe\",\"arguments\":[],\"extra\":true}\n",
    )
    .unwrap();
    let tree = RuntimeCoreTree::open(&root).unwrap();
    assert!(tree.resolve("dev/setup", "execute").is_err());
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn tree_rejects_legacy_files_and_non_leaf_facets() {
    let root = temporary_tree("tree-shape");
    write_facet(
        &root.join("dev/setup/execute"),
        "swaw/core/dev",
        "1.*",
        "dev.exe",
        &[],
    );
    fs::write(root.join("dev/setup/swaw-harness.resource.json"), "{}\n").unwrap();
    let tree = RuntimeCoreTree::open(&root).unwrap();
    assert!(tree.validate().is_err());

    fs::remove_file(root.join("dev/setup/swaw-harness.resource.json")).unwrap();
    fs::create_dir(root.join("dev/setup/execute/child")).unwrap();
    let tree = RuntimeCoreTree::open(&root).unwrap();
    assert!(tree.validate().is_err());
    fs::remove_dir_all(root).unwrap();
}

#[cfg(windows)]
#[test]
fn reparse_resource_directories_cannot_enter_resolution() {
    let root = temporary_tree("tree-reparse");
    let resource_target = temporary_tree("resource-target");
    write_facet(
        &resource_target.join("execute"),
        "swaw/core/dev",
        "1.*",
        "dev.exe",
        &[],
    );
    create_junction(&root.join("dev"), &resource_target);
    let tree = RuntimeCoreTree::open(&root).unwrap();
    assert!(tree.validate().is_err());
    assert!(tree.resolve("dev", "execute").is_err());

    fs::remove_dir(root.join("dev")).unwrap();
    fs::remove_dir_all(root).unwrap();
    fs::remove_dir_all(resource_target).unwrap();
}

fn temporary_tree(label: &str) -> PathBuf {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "swaw-harness-runtime-core-tree-{label}-{}-{unique}",
        std::process::id()
    ));
    fs::create_dir(&root).unwrap();
    root
}

fn write_facet(
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
        directory.join(FACET_DOCUMENT_NAME),
        format!(
            "{{\"schema\":\"swaw.harness.facet/v1\",\"module\":\"{module}\",\"version\":\"{version}\",\"executable\":\"{executable}\",\"arguments\":[{arguments}]}}\n"
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
