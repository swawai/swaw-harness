use std::ffi::{OsStr, OsString};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
use std::process::Command;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use windows_sys::Win32::Foundation::{ERROR_BROKEN_PIPE, WAIT_OBJECT_0};
use windows_sys::Win32::System::Pipes::PeekNamedPipe;
use windows_sys::Win32::System::Threading::{
    OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION, WaitForSingleObject,
};

use super::*;

const SYNCHRONIZE_PROCESS: u32 = 0x0010_0000;
const PROBE_MARKER: &str = "SWAW-HARNESS-MODULE-PROBE ";

#[test]
fn module_output_queue_applies_bounded_backpressure() {
    let (sender, _receiver) = stream_channel();
    for _ in 0..STREAM_QUEUE_CAPACITY {
        assert!(sender.try_send(StreamEvent::Closed).is_ok());
    }
    assert!(matches!(
        sender.try_send(StreamEvent::Closed),
        Err(std::sync::mpsc::TrySendError::Full(StreamEvent::Closed))
    ));
}

#[test]
fn windows_arguments_are_quoted_without_changing_content() {
    assert_eq!(
        quote_argument(OsStr::new("plain")).unwrap(),
        "plain".encode_utf16().collect::<Vec<_>>()
    );
    assert_eq!(
        quote_argument(OsStr::new("two words")).unwrap(),
        "\"two words\"".encode_utf16().collect::<Vec<_>>()
    );
    assert_eq!(
        quote_argument(OsStr::new("ends with \\")).unwrap(),
        "\"ends with \\\\\"".encode_utf16().collect::<Vec<_>>()
    );
}

#[test]
fn module_process_is_batch_only_and_inherits_only_its_standard_handles() {
    let (unrelated_read, unrelated_write) = child_pipe().unwrap();
    let executable = std::env::current_exe().unwrap();
    let working_directory = executable.parent().unwrap().to_owned();
    let call = PreparedCall::for_test(
        executable,
        vec![
            OsString::from("--exact"),
            OsString::from("windows::process::tests::module_process_probe"),
            OsString::from("--ignored"),
            OsString::from("--nocapture"),
        ],
        working_directory.clone(),
    );
    let mut child = ChildProcess::spawn(&call).unwrap();
    drop(unrelated_write);

    let mut available = 0_u32;
    assert_eq!(
        unsafe {
            PeekNamedPipe(
                unrelated_read.as_raw_handle(),
                null_mut(),
                0,
                null_mut(),
                &mut available,
                null_mut(),
            )
        },
        0,
        "module inherited an unrelated handle"
    );
    assert_eq!(
        std::io::Error::last_os_error().raw_os_error(),
        Some(ERROR_BROKEN_PIPE as i32)
    );

    let stdout = child.stdout.take().unwrap();
    let (sender, receiver) = mpsc::channel();
    let reader = thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if let Some(value) = line.strip_prefix(PROBE_MARKER) {
                let (process_id, working_directory) = value.split_once('\t').unwrap();
                let _ = sender.send((
                    process_id.parse::<u32>().unwrap(),
                    std::path::PathBuf::from(working_directory),
                ));
                break;
            }
        }
    });
    let (descendant_id, child_working_directory) = receiver
        .recv_timeout(Duration::from_secs(10))
        .expect("module probe did not observe stdin EOF or start its descendant");
    assert_eq!(child_working_directory, working_directory);
    let descendant = unsafe {
        OpenProcess(
            PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE_PROCESS,
            0,
            descendant_id,
        )
    };
    assert!(!descendant.is_null());
    let descendant = unsafe { OwnedHandle::from_raw_handle(descendant) };

    child.cancel();
    assert_eq!(
        unsafe { WaitForSingleObject(descendant.as_raw_handle(), 5000) },
        WAIT_OBJECT_0,
        "closing the module Job Object did not terminate its descendant"
    );
    assert_eq!(
        unsafe { WaitForSingleObject(child.process.as_raw_handle(), 5000) },
        WAIT_OBJECT_0,
        "closing the module Job Object did not terminate its main process"
    );
    reader.join().unwrap();
}

#[test]
#[ignore = "runs only as the supervised module process probe"]
fn module_process_probe() {
    let mut input = Vec::new();
    std::io::stdin().read_to_end(&mut input).unwrap();
    assert!(input.is_empty(), "module stdin did not produce EOF");

    let descendant = Command::new("cmd.exe")
        .args(["/d", "/s", "/c", "ping -n 30 127.0.0.1 >nul"])
        .spawn()
        .unwrap();
    println!(
        "{PROBE_MARKER}{}\t{}",
        descendant.id(),
        std::env::current_dir().unwrap().display()
    );
    std::io::stdout().flush().unwrap();
    thread::sleep(Duration::from_secs(30));
}
