use std::process::Command;

fn command() -> Command {
    Command::new(env!("CARGO_BIN_EXE_swaw-harness-helloworld"))
}
#[test]
fn runs_with_the_default_recipient() {
    let output = command().output().unwrap();

    assert!(output.status.success());
    assert_eq!(String::from_utf8(output.stdout).unwrap(), "Hello, World!\n");
    assert!(output.stderr.is_empty());
}

#[test]
fn forwards_one_argument_to_the_library() {
    let output = command().arg("Swaw").output().unwrap();

    assert!(output.status.success());
    assert_eq!(String::from_utf8(output.stdout).unwrap(), "Hello, Swaw!\n");
    assert!(output.stderr.is_empty());
}

#[test]
fn reports_invalid_usage() {
    let output = command().args(["Swaw", "Harness"]).output().unwrap();

    assert_eq!(output.status.code(), Some(2));
    assert!(output.stdout.is_empty());
    assert_eq!(
        String::from_utf8(output.stderr).unwrap(),
        "usage: helloworld [recipient]\n"
    );
}
