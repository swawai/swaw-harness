use std::path::{Path, PathBuf};

use crate::EntryId;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EntryLayout {
    storage_root: PathBuf,
    executable: PathBuf,
    entry_root: PathBuf,
    record: PathBuf,
}

impl EntryLayout {
    pub fn new(repository_root: impl AsRef<Path>, entry_id: &EntryId) -> Self {
        let storage_root = repository_root.as_ref().join("data.entry");
        let executable = storage_root.join(format!("{entry_id}.exe"));
        let entry_root = storage_root.join(entry_id.as_str());
        let record = entry_root.join("entry.json");
        Self {
            storage_root,
            executable,
            entry_root,
            record,
        }
    }

    pub fn storage_root(&self) -> &Path {
        &self.storage_root
    }

    pub fn executable(&self) -> &Path {
        &self.executable
    }

    pub fn entry_root(&self) -> &Path {
        &self.entry_root
    }

    pub fn record(&self) -> &Path {
        &self.record
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_a_validated_id_to_the_managed_layout() {
        let entry_id = EntryId::parse("demo-one").unwrap();
        let layout = EntryLayout::new("repository", &entry_id);

        assert_eq!(layout.storage_root(), Path::new("repository/data.entry"));
        assert_eq!(
            layout.executable(),
            Path::new("repository/data.entry/demo-one.exe")
        );
        assert_eq!(
            layout.entry_root(),
            Path::new("repository/data.entry/demo-one")
        );
        assert_eq!(
            layout.record(),
            Path::new("repository/data.entry/demo-one/entry.json")
        );
    }
}
