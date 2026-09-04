use std::fs::File;

use swaw_harness_core_protocol::SkillInvocationTarget;

use super::super::{identity::HostIdentity, os_string, process};
use crate::dispatch::prepare_call;
use crate::run::RunWorkspace;
use crate::wire::{self, KIND_RESULT};

pub(super) fn invoke(
    pipe: &mut File,
    identity: &HostIdentity,
    target: &SkillInvocationTarget,
    arguments: impl IntoIterator<Item = Vec<u16>>,
) -> Result<(), String> {
    let skill_path = target
        .skill_path()
        .ok_or_else(|| "node invocation requires a non-empty SkillPath".to_owned())?;
    let dynamic_arguments = arguments
        .into_iter()
        .map(|value| os_string(&value, "dynamic argument"))
        .collect::<Result<Vec<_>, _>>()?;
    let mut call = prepare_call(
        identity.data_home(),
        identity.user_home(),
        skill_path,
        dynamic_arguments,
    )?;
    let run = RunWorkspace::start(identity.user_home(), target, &mut call)?;
    if let Err(error) = wire::write_run_id(pipe, run.run_id()) {
        return match run.fail(&error) {
            Ok(()) => Err(error),
            Err(record_error) => Err(format!(
                "{error}; additionally cannot finish Run record: {record_error}"
            )),
        };
    }
    let exit_code = match process::execute(&call, pipe) {
        Ok(exit_code) => {
            run.complete(exit_code)?;
            exit_code
        }
        Err(error) => {
            if let Err(record_error) = run.fail(&error) {
                return Err(format!(
                    "{error}; additionally cannot finish Run record: {record_error}"
                ));
            }
            return Err(error);
        }
    };
    wire::write_frame(pipe, KIND_RESULT, &exit_code.to_le_bytes())
}
