mod identity;
mod layout;
mod lifecycle;
mod record;

pub use identity::{EntryId, EntryIdError, MAX_ENTRY_ID_BYTES};
pub use layout::EntryLayout;
pub use lifecycle::EntryLifecycleState;
pub use record::{ENTRY_RECORD_SCHEMA, EntryRecord, EntryRecordError};

pub const ENTRY_OPERATIONS_PENDING: &str = "Swaw Harness CLI Entry operations are not implemented yet; \
     this executable currently validates its independent console interface and release.";

pub const GUI_PENDING: &str = "The Swaw Harness graphical interface is not implemented yet.\n\n\
     Entry operations will be delegated to swaw-harness-cli.exe.";
