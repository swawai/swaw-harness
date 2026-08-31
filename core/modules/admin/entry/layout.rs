use std::path::{Path, PathBuf};

use crate::entry::EntryId;

pub(crate) const ADMIN_ENTRY_ID: &str = "swaw-harness";

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct EntryLayout {
    harness_root: PathBuf,
    data_home: PathBuf,
    control_root: PathBuf,
    lock: PathBuf,
    executable: PathBuf,
    entry_root: PathBuf,
    record: PathBuf,
    provisioning: PathBuf,
    runtime_root: PathBuf,
}

impl EntryLayout {
    pub(crate) fn new(harness_root: impl AsRef<Path>, entry_id: &EntryId) -> Self {
        let harness_root = harness_root.as_ref().to_path_buf();
        let data_home = harness_root.join("data");
        let control_root = data_home.join(".harness");
        let entry_root = data_home.join(entry_id.as_str());
        Self {
            harness_root,
            lock: control_root.join("entry.lock"),
            executable: data_home.join(format!("{entry_id}.exe")),
            record: entry_root.join("entry.json"),
            provisioning: entry_root.join("provisioning.json"),
            runtime_root: entry_root.join("runtime"),
            data_home,
            control_root,
            entry_root,
        }
    }

    pub(crate) fn harness_root(&self) -> &Path {
        &self.harness_root
    }

    pub(crate) fn data_home(&self) -> &Path {
        &self.data_home
    }

    pub(crate) fn control_root(&self) -> &Path {
        &self.control_root
    }

    pub(crate) fn lock(&self) -> &Path {
        &self.lock
    }

    pub(crate) fn executable(&self) -> &Path {
        &self.executable
    }

    pub(crate) fn entry_root(&self) -> &Path {
        &self.entry_root
    }

    pub(crate) fn record(&self) -> &Path {
        &self.record
    }

    pub(crate) fn provisioning(&self) -> &Path {
        &self.provisioning
    }

    pub(crate) fn runtime_root(&self) -> &Path {
        &self.runtime_root
    }

    pub(crate) fn runtime_release(&self, release_id: &str) -> PathBuf {
        self.runtime_root.join(release_id)
    }

    pub(crate) fn runtime_selector(&self, platform_target_id: &str) -> PathBuf {
        self.runtime_root
            .join(format!("current.{platform_target_id}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_an_entry_to_the_canonical_managed_layout() {
        let entry_id = EntryId::parse("demo-one").unwrap();
        let layout = EntryLayout::new("harness", &entry_id);

        assert_eq!(layout.data_home(), Path::new("harness/data"));
        assert_eq!(layout.control_root(), Path::new("harness/data/.harness"));
        assert_eq!(layout.lock(), Path::new("harness/data/.harness/entry.lock"));
        assert_eq!(layout.executable(), Path::new("harness/data/demo-one.exe"));
        assert_eq!(layout.entry_root(), Path::new("harness/data/demo-one"));
        assert_eq!(
            layout.record(),
            Path::new("harness/data/demo-one/entry.json")
        );
        assert_eq!(
            layout.runtime_release(&"a".repeat(64)),
            Path::new("harness/data/demo-one/runtime").join("a".repeat(64))
        );
        assert_eq!(
            layout.runtime_selector("x86_64-pc-windows-msvc"),
            Path::new("harness/data/demo-one/runtime/current.x86_64-pc-windows-msvc")
        );
    }
}
