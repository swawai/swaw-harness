use std::ffi::OsString;

use swaw_harness_core_protocol::InvocationContext;

pub(crate) fn run(arguments: Vec<OsString>) -> Result<(), String> {
    let [resource, dynamic @ ..] = arguments.as_slice() else {
        return Err(usage());
    };
    let resource = resource
        .to_str()
        .ok_or_else(|| "Resource path must be valid Unicode".to_owned())?;
    if resource == crate::bun::mode::RESOURCE_PATH {
        let context = InvocationContext::from_environment()?;
        crate::bun::mode::execute::run(context.entry_root(), dynamic)
    } else {
        Err(format!("unsupported Dev Resource path '{resource}'"))
    }
}

fn usage() -> String {
    format!(
        "expected: swaw-harness-dev {} [managed|disabled]",
        crate::bun::mode::RESOURCE_PATH
    )
}
