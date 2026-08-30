use std::path::Path;

#[test]
fn bun_mode_resource_keeps_its_declaration_facet_and_handler_together() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    for relative in [
        "bun/mode/swaw-harness.resource.json",
        "bun/mode/mod.rs",
        "bun/mode/execute/swaw-harness.facet.json",
        "bun/mode/execute/mod.rs",
    ] {
        assert!(root.join(relative).is_file(), "missing {relative}");
    }
}
