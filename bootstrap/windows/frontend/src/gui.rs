#![windows_subsystem = "windows"]

use std::ptr;

#[link(name = "user32")]
unsafe extern "system" {
    #[link_name = "MessageBoxW"]
    fn message_box_w(
        window: *mut core::ffi::c_void,
        text: *const u16,
        caption: *const u16,
        kind: u32,
    ) -> i32;
}

fn wide_null(value: &str) -> Vec<u16> {
    value.encode_utf16().chain([0]).collect()
}

fn main() {
    let caption = wide_null("Swaw Harness");
    let message = wide_null(swaw_har_frontend::GUI_PENDING);
    unsafe {
        // SAFETY: Both UTF-16 buffers are null-terminated and remain alive
        // for the duration of this synchronous call; no owner window is used.
        message_box_w(
            ptr::null_mut(),
            message.as_ptr(),
            caption.as_ptr(),
            0x0000_0040,
        );
    }
}
