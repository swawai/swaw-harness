mod core_configuration_tree;
mod invocation;
mod resource_space;

pub use core_configuration_tree::{
    CoreConfigurationTree, FACET_DOCUMENT_NAME, FacetDefinition, ModuleId, ResolvedFacet, Version,
    VersionSelector,
};
pub use invocation::{ENTRY_ROOT_ENVIRONMENT_VARIABLE, InvocationContext};
pub use resource_space::BaseResourceSpace;
