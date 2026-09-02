use std::ffi::c_void;
use std::mem::size_of;
use std::os::windows::io::{FromRawHandle, OwnedHandle};
use std::ptr::null_mut;

use windows_sys::Win32::Foundation::{GetLastError, LocalFree};
use windows_sys::Win32::Security::Authorization::{
    ConvertSidToStringSidW, ConvertStringSecurityDescriptorToSecurityDescriptorW,
};
use windows_sys::Win32::Security::{
    GetTokenInformation, PSECURITY_DESCRIPTOR, SECURITY_ATTRIBUTES, TOKEN_GROUPS, TOKEN_QUERY,
    TokenLogonSid,
};
use windows_sys::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

const SECURITY_DESCRIPTOR_REVISION: u32 = 1;
const ERROR_INSUFFICIENT_BUFFER: u32 = 122;

pub(super) struct LocalSecurity {
    descriptor: PSECURITY_DESCRIPTOR,
    attributes: SECURITY_ATTRIBUTES,
}

impl LocalSecurity {
    pub(super) fn for_logon_session() -> Result<Self, String> {
        let sid = current_logon_sid_string()?;
        let sddl: Vec<u16> = format!("D:P(A;;GA;;;{sid})")
            .encode_utf16()
            .chain([0])
            .collect();
        let mut descriptor = null_mut();
        if unsafe {
            ConvertStringSecurityDescriptorToSecurityDescriptorW(
                sddl.as_ptr(),
                SECURITY_DESCRIPTOR_REVISION,
                &mut descriptor,
                null_mut(),
            )
        } == 0
        {
            return Err(last_error("cannot create Core Host security descriptor"));
        }
        Ok(Self {
            descriptor,
            attributes: SECURITY_ATTRIBUTES {
                nLength: size_of::<SECURITY_ATTRIBUTES>() as u32,
                lpSecurityDescriptor: descriptor,
                bInheritHandle: 0,
            },
        })
    }

    pub(super) fn attributes(&self) -> &SECURITY_ATTRIBUTES {
        &self.attributes
    }
}

impl Drop for LocalSecurity {
    fn drop(&mut self) {
        if !self.descriptor.is_null() {
            unsafe {
                LocalFree(self.descriptor);
            }
        }
    }
}

fn current_logon_sid_string() -> Result<String, String> {
    let mut raw_token = null_mut();
    if unsafe { OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut raw_token) } == 0 {
        return Err(last_error("cannot open the Core Host process token"));
    }
    let token = unsafe { OwnedHandle::from_raw_handle(raw_token) };
    let mut required = 0_u32;
    unsafe {
        GetTokenInformation(
            token.as_raw_handle(),
            TokenLogonSid,
            null_mut(),
            0,
            &mut required,
        );
    }
    if required < size_of::<TOKEN_GROUPS>() as u32
        || unsafe { GetLastError() } != ERROR_INSUFFICIENT_BUFFER
    {
        return Err(last_error("cannot size the Core Host logon SID"));
    }
    let mut buffer = vec![0_u8; required as usize];
    if unsafe {
        GetTokenInformation(
            token.as_raw_handle(),
            TokenLogonSid,
            buffer.as_mut_ptr().cast::<c_void>(),
            required,
            &mut required,
        )
    } == 0
    {
        return Err(last_error("cannot read the Core Host logon SID"));
    }
    let groups = unsafe { &*buffer.as_ptr().cast::<TOKEN_GROUPS>() };
    if groups.GroupCount != 1 || groups.Groups[0].Sid.is_null() {
        return Err("Core Host process token has no unique logon SID".to_owned());
    }
    let mut raw_string = null_mut();
    if unsafe { ConvertSidToStringSidW(groups.Groups[0].Sid, &mut raw_string) } == 0 {
        return Err(last_error("cannot format the Core Host logon SID"));
    }
    let length = unsafe {
        (0..)
            .find(|index| *raw_string.add(*index) == 0)
            .ok_or_else(|| "Core Host logon SID is not terminated".to_owned())?
    };
    let result = String::from_utf16(unsafe { std::slice::from_raw_parts(raw_string, length) })
        .map_err(|_| "Core Host logon SID is not valid UTF-16".to_owned());
    unsafe {
        LocalFree(raw_string.cast());
    }
    result
}

trait OwnedHandleRaw {
    fn as_raw_handle(&self) -> *mut c_void;
}

impl OwnedHandleRaw for OwnedHandle {
    fn as_raw_handle(&self) -> *mut c_void {
        use std::os::windows::io::AsRawHandle;
        AsRawHandle::as_raw_handle(self)
    }
}

fn last_error(activity: &str) -> String {
    format!("{activity}: {}", std::io::Error::last_os_error())
}
