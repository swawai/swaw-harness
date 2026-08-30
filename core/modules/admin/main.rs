use std::process::ExitCode;

fn main() -> ExitCode {
    match swaw_harness_admin::run(std::env::args_os().skip(1).collect()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("swaw-harness-admin: {error}");
            ExitCode::FAILURE
        }
    }
}
