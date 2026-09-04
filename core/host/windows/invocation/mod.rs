mod help;
mod node;

use std::fs::File;

use swaw_harness_core_protocol::{SkillInvocationTarget, SkillNodeMethod};

use super::identity::HostIdentity;

pub(super) fn invoke(
    pipe: &mut File,
    identity: &HostIdentity,
    target: &SkillInvocationTarget,
    arguments: impl IntoIterator<Item = Vec<u16>>,
) -> Result<(), String> {
    match target.method() {
        SkillNodeMethod::Node => node::invoke(pipe, identity, target, arguments),
        SkillNodeMethod::Help => help::invoke(pipe, identity, target, arguments),
        method => Err(format!(
            "Core Host node method '/.{}' is not implemented",
            method.name()
        )),
    }
}
