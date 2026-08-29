use std::path::{Path, PathBuf};

use crate::EntryId;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EntryLayout {
    data_home: PathBuf,
    executable: PathBuf,
    entry_root: PathBuf,
    record: PathBuf,
}

impl EntryLayout {
    pub fn new(harness_root: impl AsRef<Path>, entry_id: &EntryId) -> Self {
        let data_home = harness_root.as_ref().join("data");
        let executable = data_home.join(format!("{entry_id}.exe"));
        let entry_root = data_home.join(entry_id.as_str());
        let record = entry_root.join("entry.json");
        Self {
            data_home,
            executable,
            entry_root,
            record,
        }
    }

    pub fn data_home(&self) -> &Path {
        &self.data_home
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
        let layout = EntryLayout::new("harness", &entry_id);

        assert_eq!(layout.data_home(), Path::new("harness/data"));
        assert_eq!(layout.executable(), Path::new("harness/data/demo-one.exe"));
        assert_eq!(layout.entry_root(), Path::new("harness/data/demo-one"));
        assert_eq!(
            layout.record(),
            Path::new("harness/data/demo-one/entry.json")
        );
    }
}
