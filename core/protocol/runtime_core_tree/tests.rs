use super::document::EXECUTABLE_SCHEMA;
use super::*;
use std::time::{SystemTime, UNIX_EPOCH};

const ADMIN_RELEASE_ID: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const DEV_RELEASE_ID: &str = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd";

#[test]
fn repository_tree_is_valid_and_uses_nearest_executable_binding() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../runtime.core.tree");
    let tree = RuntimeCoreTree::open(root).unwrap();
    tree.validate().unwrap();

    for (resource, facet, release_root, release_id, executable) in [
        (
            "admin/entry/swaw-harness",
            "seed",
            "runtime/core/admin",
            ADMIN_RELEASE_ID,
            "swaw-harness-admin.exe",
        ),
        (
            "dev/setup",
            "execute",
            "runtime/core/dev",
            DEV_RELEASE_ID,
            "swaw-harness-dev.exe",
        ),
        (
            "dev/bun/mode",
            "execute",
            "runtime/core/dev",
            DEV_RELEASE_ID,
            "swaw-harness-dev.exe",
        ),
    ] {
        let resolved = tree.resolve(resource, facet).unwrap();
        assert_eq!(resolved.resource(), resource);
        assert_eq!(resolved.facet(), facet);
        assert_eq!(resolved.binding().release_root(), Path::new(release_root));
        assert_eq!(resolved.binding().release_id(), release_id);
        assert_eq!(resolved.binding().executable(), executable);
    }
}

#[test]
fn child_resource_can_replace_its_inherited_binding() {
    let root = temporary_tree("nearest-binding");
    write_resource(&root.join("dev"));
    write_binding(
        &root.join("dev"),
        "runtime/core/dev",
        DEV_RELEASE_ID,
        "dev.exe",
    );
    write_resource(&root.join("dev/setup"));
    write_binding(
        &root.join("dev/setup"),
        "runtime/core/dev-setup",
        ADMIN_RELEASE_ID,
        "setup.exe",
    );
    write_facet(&root.join("dev/setup/execute"));

    let tree = RuntimeCoreTree::open(&root).unwrap();
    let resolved = tree.resolve("dev/setup", "execute").unwrap();
    assert_eq!(
        resolved.binding().release_root(),
        Path::new("runtime/core/dev-setup")
    );
    assert_eq!(resolved.binding().executable(), "setup.exe");
    let entry_root = root.join("entry");
    let executable = entry_root
        .join("runtime/core/dev-setup")
        .join(ADMIN_RELEASE_ID)
        .join("setup.exe");
    fs::create_dir_all(executable.parent().unwrap()).unwrap();
    fs::write(&executable, b"fixture").unwrap();
    assert_eq!(
        resolved.binding().executable_path(&entry_root).unwrap(),
        executable
    );
    assert!(
        resolved
            .binding()
            .executable_path(Path::new("relative-entry"))
            .is_err()
    );
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn unsafe_routes_and_binding_documents_are_rejected() {
    let root = temporary_tree("invalid-binding");
    write_resource(&root.join("dev"));
    write_facet(&root.join("dev/execute"));
    let tree = RuntimeCoreTree::open(&root).unwrap();
    assert!(tree.resolve("dev", "execute").is_err());
    for resource in [
        "",
        "../dev",
        "/dev",
        "DEV",
        "dev/Setup",
        "dev\\setup",
        "dev//setup",
    ] {
        let tree = RuntimeCoreTree::open(&root).unwrap();
        assert!(tree.resolve(resource, "execute").is_err(), "{resource}");
    }
    let tree = RuntimeCoreTree::open(&root).unwrap();
    assert!(tree.resolve("dev", "Execute").is_err());

    for (release_root, release_id, executable) in [
        ("../runtime/core/dev", DEV_RELEASE_ID, "dev.exe"),
        ("runtime/other/dev", DEV_RELEASE_ID, "dev.exe"),
        ("runtime/core/dev", "short", "dev.exe"),
        ("runtime/core/dev", DEV_RELEASE_ID, "../dev.exe"),
    ] {
        write_binding(&root.join("dev"), release_root, release_id, executable);
        let tree = RuntimeCoreTree::open(&root).unwrap();
        assert!(tree.resolve("dev", "execute").is_err(), "{release_root}");
    }

    fs::write(
        root.join("dev").join(EXECUTABLE_DOCUMENT_NAME),
        format!(
            "{{\"schema\":\"{EXECUTABLE_SCHEMA}\",\"releaseRoot\":\"runtime/core/dev\",\"releaseId\":\"{DEV_RELEASE_ID}\",\"executable\":\"dev.exe\",\"extra\":true}}\n"
        ),
    )
    .unwrap();
    let tree = RuntimeCoreTree::open(&root).unwrap();
    assert!(tree.resolve("dev", "execute").is_err());
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn binding_requires_a_resource_owner_and_all_required_fields() {
    let root = temporary_tree("binding-owner");
    write_resource(&root.join("dev"));
    write_facet(&root.join("dev/execute"));

    write_binding(&root, "runtime/core/dev", DEV_RELEASE_ID, "dev.exe");
    let tree = RuntimeCoreTree::open(&root).unwrap();
    assert!(tree.validate().is_err());
    assert!(tree.resolve("dev", "execute").is_err());

    fs::remove_file(root.join(EXECUTABLE_DOCUMENT_NAME)).unwrap();
    fs::write(
        root.join("dev").join(EXECUTABLE_DOCUMENT_NAME),
        format!(
            "{{\"schema\":\"{EXECUTABLE_SCHEMA}\",\"releaseRoot\":\"runtime/core/dev\",\"releaseId\":\"{DEV_RELEASE_ID}\"}}\n"
        ),
    )
    .unwrap();
    let tree = RuntimeCoreTree::open(&root).unwrap();
    assert!(tree.validate().is_err());

    fs::remove_dir_all(root).unwrap();
}

#[cfg(windows)]
#[test]
fn reparse_directories_cannot_enter_the_tree_or_module_release_path() {
    let root = temporary_tree("tree-reparse");
    let resource_target = temporary_tree("resource-target");
    write_resource(&resource_target);
    write_binding(
        &resource_target,
        "runtime/core/dev",
        DEV_RELEASE_ID,
        "dev.exe",
    );
    write_facet(&resource_target.join("execute"));
    create_junction(&root.join("dev"), &resource_target);
    let tree = RuntimeCoreTree::open(&root).unwrap();
    assert!(tree.validate().is_err());
    assert!(tree.resolve("dev", "execute").is_err());
    fs::remove_dir(root.join("dev")).unwrap();
    fs::remove_dir_all(root).unwrap();
    fs::remove_dir_all(resource_target).unwrap();

    let tree_root = temporary_tree("release-reparse-tree");
    write_resource(&tree_root.join("dev"));
    write_binding(
        &tree_root.join("dev"),
        "runtime/core/dev",
        DEV_RELEASE_ID,
        "dev.exe",
    );
    write_facet(&tree_root.join("dev/execute"));
    let binding = RuntimeCoreTree::open(&tree_root)
        .unwrap()
        .resolve("dev", "execute")
        .unwrap()
        .binding()
        .clone();

    let entry_root = temporary_tree("release-reparse-entry");
    fs::create_dir_all(entry_root.join("runtime/core/dev")).unwrap();
    let release_target = temporary_tree("release-target");
    fs::write(release_target.join("dev.exe"), b"fixture").unwrap();
    let release_junction = entry_root.join("runtime/core/dev").join(DEV_RELEASE_ID);
    create_junction(&release_junction, &release_target);
    assert!(binding.executable_path(&entry_root).is_err());

    fs::remove_dir(release_junction).unwrap();
    fs::remove_dir_all(entry_root).unwrap();
    fs::remove_dir_all(release_target).unwrap();
    fs::remove_dir_all(tree_root).unwrap();
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

fn write_resource(directory: &Path) {
    fs::create_dir_all(directory).unwrap();
    fs::write(
        directory.join(RESOURCE_DOCUMENT_NAME),
        format!("{{\"schema\":\"{RESOURCE_SCHEMA}\"}}\n"),
    )
    .unwrap();
}

fn write_facet(directory: &Path) {
    fs::create_dir_all(directory).unwrap();
    fs::write(
        directory.join(FACET_DOCUMENT_NAME),
        format!("{{\"schema\":\"{FACET_SCHEMA}\"}}\n"),
    )
    .unwrap();
}

fn write_binding(directory: &Path, release_root: &str, release_id: &str, executable: &str) {
    fs::write(
        directory.join(EXECUTABLE_DOCUMENT_NAME),
        format!(
            "{{\"schema\":\"{EXECUTABLE_SCHEMA}\",\"releaseRoot\":\"{release_root}\",\"releaseId\":\"{release_id}\",\"executable\":\"{executable}\"}}\n"
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
