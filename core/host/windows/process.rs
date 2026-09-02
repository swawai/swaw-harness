use std::ffi::{OsStr, c_void};
use std::fs::File;
use std::io::Read;
use std::mem::size_of;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
use std::ptr::{null, null_mut};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::Duration;

use windows_sys::Win32::Foundation::{
    GENERIC_READ, HANDLE, HANDLE_FLAG_INHERIT, INVALID_HANDLE_VALUE, WAIT_OBJECT_0, WAIT_TIMEOUT,
};
use windows_sys::Win32::Security::SECURITY_ATTRIBUTES;
use windows_sys::Win32::Storage::FileSystem::{
    CreateFileW, FILE_ATTRIBUTE_NORMAL, FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING,
};
use windows_sys::Win32::System::JobObjects::{
    AssignProcessToJobObject, CreateJobObjectW, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation,
    SetInformationJobObject,
};
use windows_sys::Win32::System::Pipes::{CreatePipe, PeekNamedPipe};
use windows_sys::Win32::System::Threading::{
    CREATE_NO_WINDOW, CREATE_SUSPENDED, CreateProcessW, DeleteProcThreadAttributeList,
    EXTENDED_STARTUPINFO_PRESENT, GetExitCodeProcess, InitializeProcThreadAttributeList,
    PROC_THREAD_ATTRIBUTE_HANDLE_LIST, PROCESS_INFORMATION, ResumeThread, STARTF_USESTDHANDLES,
    STARTUPINFOEXW, TerminateProcess, UpdateProcThreadAttribute, WaitForSingleObject,
};

use crate::dispatch::PreparedCall;
use crate::wire::{self, KIND_STDERR, KIND_STDOUT};

const STREAM_BUFFER_BYTES: usize = 16 * 1024;
const STREAM_QUEUE_CAPACITY: usize = 8;
const CLIENT_POLL_INTERVAL: Duration = Duration::from_millis(25);

pub(super) fn execute(call: &PreparedCall, client: &mut File) -> Result<u32, String> {
    let mut child = ChildProcess::spawn(call)?;
    let (sender, receiver) = stream_channel();
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "Core Host child stdout pipe is absent".to_owned())?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| "Core Host child stderr pipe is absent".to_owned())?;
    let stdout_thread = spawn_reader(stdout, KIND_STDOUT, sender.clone());
    let stderr_thread = spawn_reader(stderr, KIND_STDERR, sender);

    let mut open_streams = 2_usize;
    let exit_code = loop {
        match receiver.recv_timeout(CLIENT_POLL_INTERVAL) {
            Ok(StreamEvent::Data(kind, data)) => {
                if let Err(error) = wire::write_frame(client, kind, &data) {
                    child.cancel();
                    return Err(format!("Core Host client disconnected: {error}"));
                }
            }
            Ok(StreamEvent::Closed) => open_streams -= 1,
            Ok(StreamEvent::Failed(error)) => {
                child.cancel();
                return Err(error);
            }
            Err(RecvTimeoutError::Disconnected) if open_streams != 0 => {
                child.cancel();
                return Err("Core Host output readers stopped unexpectedly".to_owned());
            }
            Err(RecvTimeoutError::Disconnected | RecvTimeoutError::Timeout) => {}
        }

        if !client_is_connected(client) {
            child.cancel();
            return Err("Core Host client disconnected".to_owned());
        }
        if let Some(code) = child.exit_code()? {
            child.finish();
            if open_streams == 0 {
                break code;
            }
        }
    };

    stdout_thread
        .join()
        .map_err(|_| "Core Host stdout reader panicked".to_owned())?;
    stderr_thread
        .join()
        .map_err(|_| "Core Host stderr reader panicked".to_owned())?;
    Ok(exit_code)
}

enum StreamEvent {
    Data(u16, Vec<u8>),
    Closed,
    Failed(String),
}

fn stream_channel() -> (mpsc::SyncSender<StreamEvent>, mpsc::Receiver<StreamEvent>) {
    mpsc::sync_channel(STREAM_QUEUE_CAPACITY)
}

fn spawn_reader(
    mut stream: File,
    kind: u16,
    sender: mpsc::SyncSender<StreamEvent>,
) -> thread::JoinHandle<()> {
    thread::spawn(move || {
        let mut buffer = [0_u8; STREAM_BUFFER_BYTES];
        loop {
            match stream.read(&mut buffer) {
                Ok(0) => {
                    let _ = sender.send(StreamEvent::Closed);
                    break;
                }
                Ok(count) => {
                    if sender
                        .send(StreamEvent::Data(kind, buffer[..count].to_vec()))
                        .is_err()
                    {
                        break;
                    }
                }
                Err(error) => {
                    let _ = sender.send(StreamEvent::Failed(format!(
                        "cannot read module output: {error}"
                    )));
                    break;
                }
            }
        }
    })
}

fn client_is_connected(client: &File) -> bool {
    unsafe {
        PeekNamedPipe(
            client.as_raw_handle(),
            null_mut(),
            0,
            null_mut(),
            null_mut(),
            null_mut(),
        ) != 0
    }
}

struct ChildProcess {
    process: OwnedHandle,
    job: Option<OwnedHandle>,
    stdout: Option<File>,
    stderr: Option<File>,
}

impl ChildProcess {
    fn spawn(call: &PreparedCall) -> Result<Self, String> {
        let (stdout_read, stdout_write) = child_pipe()?;
        let (stderr_read, stderr_write) = child_pipe()?;
        let null_input = inherited_null_input()?;
        let job = create_kill_on_close_job()?;
        let inherited_handles = [
            null_input.as_raw_handle(),
            stdout_write.as_raw_handle(),
            stderr_write.as_raw_handle(),
        ];
        let attributes = ProcThreadAttributes::for_handles(&inherited_handles)?;
        let mut startup = STARTUPINFOEXW::default();
        startup.StartupInfo.cb = size_of::<STARTUPINFOEXW>() as u32;
        startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
        startup.StartupInfo.hStdInput = inherited_handles[0];
        startup.StartupInfo.hStdOutput = inherited_handles[1];
        startup.StartupInfo.hStdError = inherited_handles[2];
        startup.lpAttributeList = attributes.as_ptr();
        let application = wide_null(call.executable().as_os_str())?;
        let mut command_line = command_line(call)?;
        let current_directory = wide_null(call.working_directory().as_os_str())?;
        let mut information = PROCESS_INFORMATION::default();
        if unsafe {
            CreateProcessW(
                application.as_ptr(),
                command_line.as_mut_ptr(),
                null(),
                null(),
                1,
                CREATE_SUSPENDED | CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT,
                null(),
                current_directory.as_ptr(),
                &startup.StartupInfo,
                &mut information,
            )
        } == 0
        {
            return Err(last_error("cannot create module process"));
        }
        let process = unsafe { OwnedHandle::from_raw_handle(information.hProcess) };
        let thread = unsafe { OwnedHandle::from_raw_handle(information.hThread) };
        if unsafe { AssignProcessToJobObject(job.as_raw_handle(), process.as_raw_handle()) } == 0 {
            unsafe {
                TerminateProcess(process.as_raw_handle(), 1);
            }
            return Err(last_error("cannot assign module process to its Job Object"));
        }
        if unsafe { ResumeThread(thread.as_raw_handle()) } == u32::MAX {
            unsafe {
                TerminateProcess(process.as_raw_handle(), 1);
            }
            return Err(last_error("cannot resume module process"));
        }
        drop(thread);
        drop(stdout_write);
        drop(stderr_write);
        drop(null_input);

        Ok(Self {
            process,
            job: Some(job),
            stdout: Some(File::from(stdout_read)),
            stderr: Some(File::from(stderr_read)),
        })
    }

    fn exit_code(&self) -> Result<Option<u32>, String> {
        match unsafe { WaitForSingleObject(self.process.as_raw_handle(), 0) } {
            WAIT_TIMEOUT => Ok(None),
            WAIT_OBJECT_0 => {
                let mut exit_code = 0_u32;
                if unsafe { GetExitCodeProcess(self.process.as_raw_handle(), &mut exit_code) } == 0
                {
                    Err(last_error("cannot read module exit code"))
                } else {
                    Ok(Some(exit_code))
                }
            }
            _ => Err(last_error("cannot wait for module process")),
        }
    }

    fn cancel(&mut self) {
        self.job.take();
    }

    fn finish(&mut self) {
        // Closing the completed call's Job Object also terminates descendants
        // that outlived the module's main process.
        self.job.take();
    }
}

struct ProcThreadAttributes {
    storage: Vec<usize>,
    initialized: bool,
}

impl ProcThreadAttributes {
    fn for_handles(handles: &[HANDLE]) -> Result<Self, String> {
        let mut required = 0_usize;
        unsafe {
            InitializeProcThreadAttributeList(null_mut(), 1, 0, &mut required);
        }
        if required == 0 {
            return Err(last_error("cannot size the module process attribute list"));
        }
        let words = required.div_ceil(size_of::<usize>());
        let mut result = Self {
            storage: vec![0_usize; words],
            initialized: false,
        };
        if unsafe { InitializeProcThreadAttributeList(result.as_ptr(), 1, 0, &mut required) } == 0 {
            return Err(last_error(
                "cannot initialize the module process attribute list",
            ));
        }
        result.initialized = true;
        if unsafe {
            UpdateProcThreadAttribute(
                result.as_ptr(),
                0,
                PROC_THREAD_ATTRIBUTE_HANDLE_LIST as usize,
                handles.as_ptr().cast::<c_void>(),
                std::mem::size_of_val(handles),
                null_mut(),
                null(),
            )
        } == 0
        {
            return Err(last_error(
                "cannot restrict the module process inherited handles",
            ));
        }
        Ok(result)
    }

    fn as_ptr(&self) -> *mut c_void {
        self.storage.as_ptr().cast_mut().cast::<c_void>()
    }
}

impl Drop for ProcThreadAttributes {
    fn drop(&mut self) {
        if self.initialized {
            unsafe {
                DeleteProcThreadAttributeList(self.as_ptr());
            }
        }
    }
}

fn child_pipe() -> Result<(OwnedHandle, OwnedHandle), String> {
    let attributes = SECURITY_ATTRIBUTES {
        nLength: size_of::<SECURITY_ATTRIBUTES>() as u32,
        lpSecurityDescriptor: null_mut(),
        bInheritHandle: 1,
    };
    let mut read: HANDLE = null_mut();
    let mut write: HANDLE = null_mut();
    if unsafe { CreatePipe(&mut read, &mut write, &attributes, 0) } == 0 {
        return Err(last_error("cannot create module output pipe"));
    }
    let read = unsafe { OwnedHandle::from_raw_handle(read) };
    let write = unsafe { OwnedHandle::from_raw_handle(write) };
    if unsafe {
        windows_sys::Win32::Foundation::SetHandleInformation(
            read.as_raw_handle(),
            HANDLE_FLAG_INHERIT,
            0,
        )
    } == 0
    {
        return Err(last_error("cannot make module output reader private"));
    }
    Ok((read, write))
}

fn inherited_null_input() -> Result<OwnedHandle, String> {
    let name: Vec<u16> = "NUL".encode_utf16().chain([0]).collect();
    let attributes = SECURITY_ATTRIBUTES {
        nLength: size_of::<SECURITY_ATTRIBUTES>() as u32,
        lpSecurityDescriptor: null_mut(),
        bInheritHandle: 1,
    };
    let handle = unsafe {
        CreateFileW(
            name.as_ptr(),
            GENERIC_READ,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            &attributes,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL,
            null_mut(),
        )
    };
    if handle == INVALID_HANDLE_VALUE {
        Err(last_error("cannot open the module null stdin"))
    } else {
        Ok(unsafe { OwnedHandle::from_raw_handle(handle) })
    }
}

fn create_kill_on_close_job() -> Result<OwnedHandle, String> {
    let handle = unsafe { CreateJobObjectW(null(), null()) };
    if handle.is_null() {
        return Err(last_error("cannot create module Job Object"));
    }
    let job = unsafe { OwnedHandle::from_raw_handle(handle) };
    let mut limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if unsafe {
        SetInformationJobObject(
            job.as_raw_handle(),
            JobObjectExtendedLimitInformation,
            (&limits as *const JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast::<c_void>(),
            size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
        )
    } == 0
    {
        return Err(last_error("cannot configure module Job Object"));
    }
    Ok(job)
}

fn command_line(call: &PreparedCall) -> Result<Vec<u16>, String> {
    let mut result = quote_argument(call.executable().as_os_str())?;
    for argument in call.arguments() {
        result.push(b' ' as u16);
        result.extend(quote_argument(argument)?);
    }
    result.push(0);
    Ok(result)
}

fn quote_argument(value: &OsStr) -> Result<Vec<u16>, String> {
    let units: Vec<_> = value.encode_wide().collect();
    if units.contains(&0) {
        return Err("module argument contains NUL".to_owned());
    }
    if !units.is_empty()
        && units
            .iter()
            .all(|unit| !matches!(*unit, 9 | 10 | 11 | 12 | 13 | 32 | 34))
    {
        return Ok(units);
    }

    let mut quoted = vec![b'"' as u16];
    let mut slashes = 0_usize;
    for unit in units {
        if unit == b'\\' as u16 {
            slashes += 1;
        } else if unit == b'"' as u16 {
            quoted.extend(std::iter::repeat_n(b'\\' as u16, slashes * 2 + 1));
            quoted.push(unit);
            slashes = 0;
        } else {
            quoted.extend(std::iter::repeat_n(b'\\' as u16, slashes));
            quoted.push(unit);
            slashes = 0;
        }
    }
    quoted.extend(std::iter::repeat_n(b'\\' as u16, slashes * 2));
    quoted.push(b'"' as u16);
    Ok(quoted)
}

fn wide_null(value: &OsStr) -> Result<Vec<u16>, String> {
    let mut result: Vec<_> = value.encode_wide().collect();
    if result.contains(&0) {
        return Err("module path contains NUL".to_owned());
    }
    result.push(0);
    Ok(result)
}

fn last_error(activity: &str) -> String {
    format!("{activity}: {}", std::io::Error::last_os_error())
}

#[cfg(test)]
#[path = "process_tests.rs"]
mod tests;
