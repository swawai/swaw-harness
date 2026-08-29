use std::{env, process::ExitCode};

use swaw_harness_helloworld::greeting;

const USAGE: &str = "usage: helloworld [recipient]";

fn main() -> ExitCode {
    let arguments = env::args().skip(1).collect::<Vec<_>>();
    match arguments.as_slice() {
        [] => {
            println!("{}", greeting(None));
            ExitCode::SUCCESS
        }
        [recipient] => {
            println!("{}", greeting(Some(recipient)));
            ExitCode::SUCCESS
        }
        _ => {
            eprintln!("{USAGE}");
            ExitCode::from(2)
        }
    }
}
