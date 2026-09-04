use std::fs::File;
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
use std::path::PathBuf;
use std::ptr::null_mut;
use std::thread;

use windows_sys::Win32::Foundation::{
    ERROR_ALREADY_EXISTS, ERROR_PIPE_CONNECTED, GetLastError, INVALID_HANDLE_VALUE,
};
use windows_sys::Win32::Storage::FileSystem::{FlushFileBuffers, PIPE_ACCESS_DUPLEX};
use windows_sys::Win32::System::Pipes::{
    ConnectNamedPipe, CreateNamedPipeW, DisconnectNamedPipe, PIPE_READMODE_BYTE,
    PIPE_REJECT_REMOTE_CLIENTS, PIPE_TYPE_BYTE, PIPE_UNLIMITED_INSTANCES, PIPE_WAIT,
};
use windows_sys::Win32::System::Threading::CreateMutexW;

use super::identity::HostIdentity;
use super::invocation;
use super::os_string;
use super::security::LocalSecurity;
use crate::wire::{self, KIND_ERROR, KIND_RESULT};
use swaw_harness_core_protocol::SkillInvocationTarget;

const PIPE_BUFFER_BYTES: u32 = 64 * 1024;

pub(super) fn serve(identity: HostIdentity) -> Result<(), String> {
    let security = LocalSecurity::for_logon_session()?;
    let mutex = unsafe { CreateMutexW(security.attributes(), 0, identity.mutex_name().as_ptr()) };
    if mutex.is_null() {
        return Err(last_error("cannot create the Core Host instance mutex"));
    }
    let _mutex = unsafe { OwnedHandle::from_raw_handle(mutex) };
    if unsafe { GetLastError() } == ERROR_ALREADY_EXISTS {
        return Ok(());
    }

    loop {
        let pipe = create_pipe(&identity, &security)?;
        let connected = unsafe { ConnectNamedPipe(pipe.as_raw_handle(), null_mut()) } != 0;
        if !connected && unsafe { GetLastError() } != ERROR_PIPE_CONNECTED {
            return Err(last_error("cannot accept a Core Host named-pipe client"));
        }
        let connection_identity = identity.clone();
        thread::spawn(move || handle_connection(pipe, &connection_identity));
    }
}

fn create_pipe(identity: &HostIdentity, security: &LocalSecurity) -> Result<OwnedHandle, String> {
    let handle = unsafe {
        CreateNamedPipeW(
            identity.pipe_name().as_ptr(),
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
            PIPE_UNLIMITED_INSTANCES,
            PIPE_BUFFER_BYTES,
            PIPE_BUFFER_BYTES,
            0,
            security.attributes(),
        )
    };
    if handle == INVALID_HANDLE_VALUE {
        Err(last_error("cannot create the Core Host named pipe"))
    } else {
        Ok(unsafe { OwnedHandle::from_raw_handle(handle) })
    }
}

fn handle_connection(pipe: OwnedHandle, identity: &HostIdentity) {
    let mut pipe = File::from(pipe);
    if let Err(error) = invoke(&mut pipe, identity) {
        let message = format!("[ERROR] {error}\r\n");
        let _ = wire::write_frame(&mut pipe, KIND_ERROR, message.as_bytes());
        let _ = wire::write_frame(&mut pipe, KIND_RESULT, &1_u32.to_le_bytes());
    }
    unsafe {
        FlushFileBuffers(pipe.as_raw_handle());
        DisconnectNamedPipe(pipe.as_raw_handle());
    }
}

fn invoke(pipe: &mut File, identity: &HostIdentity) -> Result<(), String> {
    let request = wire::read_request(pipe)?;
    let user_id = String::from_utf16(&request.user_id)
        .map_err(|_| "Core Host request UserId is not valid UTF-16".to_owned())?;
    if user_id != identity.user_id() {
        return Err("Core Host request UserId does not match this Host".to_owned());
    }
    let requested_user_home = PathBuf::from(os_string(&request.user_home, "UserHome")?);
    if !identity.accepts_user_home(&requested_user_home) {
        return Err("Core Host request UserHome does not match this Host".to_owned());
    }

    let mut arguments = request.arguments.into_iter();
    let target_units = arguments
        .next()
        .ok_or_else(|| "Core Host request has no Skill invocation target".to_owned())?;
    let target_text = String::from_utf16(&target_units)
        .map_err(|_| "Core Host Skill invocation target is not valid UTF-16".to_owned())?;
    let target = SkillInvocationTarget::parse(&target_text)?;
    if target.skill_map_id() != "core" {
        return Err(format!(
            "Core Host currently supports only SkillMapId 'core': {}",
            target.skill_map_id()
        ));
    }
    invocation::invoke(pipe, identity, &target, arguments)
}

fn last_error(activity: &str) -> String {
    format!("{activity}: {}", std::io::Error::last_os_error())
}
