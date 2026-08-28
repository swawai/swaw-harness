mod identity;
mod layout;
mod lifecycle;
mod record;

pub use identity::{EntryId, EntryIdError, MAX_ENTRY_ID_BYTES};
pub use layout::EntryLayout;
pub use lifecycle::EntryLifecycleState;
pub use record::{ENTRY_RECORD_SCHEMA, EntryRecord, EntryRecordError};

pub const CONTROL_PANEL_PENDING: &str = "Swaw Harness Entry Manager control panel is not implemented yet; \
     this artifact currently validates its independent build and release.";
