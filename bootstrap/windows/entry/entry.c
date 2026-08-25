#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static const char swaw_entry_message[] =
    "[ERROR] Swaw Harness Entry executable runtime is not implemented yet; "
    "this artifact is for build and publication validation only.\r\n";

__declspec(noreturn) void swaw_entry_main(void)
{
    DWORD written = 0;
    HANDLE error_handle = GetStdHandle(STD_ERROR_HANDLE);

    if (error_handle != NULL && error_handle != INVALID_HANDLE_VALUE) {
        WriteFile(
            error_handle,
            swaw_entry_message,
            (DWORD)(sizeof(swaw_entry_message) - 1),
            &written,
            NULL
        );
    }
    ExitProcess(1);
}
