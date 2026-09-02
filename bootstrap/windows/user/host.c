#include "user.h"

static WCHAR swaw_host_version_path[SWAW_MAX_PATH_UNITS];
static WCHAR swaw_host_path[SWAW_MAX_PATH_UNITS];
static WCHAR swaw_host_directory[SWAW_MAX_PATH_UNITS];
static WCHAR swaw_host_command_line[64];
static STARTUPINFOW swaw_host_startup;
static PROCESS_INFORMATION swaw_host_process;

static DWORD swaw_length(const WCHAR *value)
{
    DWORD length = 0;
    while (value[length] != L'\0') {
        ++length;
    }
    return length;
}

static BOOL swaw_copy(WCHAR *destination, DWORD capacity, const WCHAR *source)
{
    DWORD index = 0;
    while (source[index] != L'\0') {
        if (index + 1U >= capacity) {
            return FALSE;
        }
        destination[index] = source[index];
        ++index;
    }
    destination[index] = L'\0';
    return TRUE;
}

static BOOL swaw_append(WCHAR *destination, DWORD capacity, const WCHAR *suffix)
{
    DWORD position = swaw_length(destination);
    DWORD index = 0;
    while (suffix[index] != L'\0') {
        if (position + 1U >= capacity) {
            return FALSE;
        }
        destination[position++] = suffix[index++];
    }
    destination[position] = L'\0';
    return TRUE;
}

static BOOL swaw_is_exact_version(const BYTE *encoded, DWORD length)
{
    DWORD component_start = 0U;
    DWORD dots = 0U;
    DWORD index;

    if (length < 5U) {
        return FALSE;
    }
    for (index = 0U; index <= length; ++index) {
        if (index < length && encoded[index] >= (BYTE)'0' &&
            encoded[index] <= (BYTE)'9') {
            continue;
        }
        if (index == component_start ||
            (index - component_start > 1U &&
             encoded[component_start] == (BYTE)'0')) {
            return FALSE;
        }
        if (index == length) {
            return dots == 2U;
        }
        if (encoded[index] != (BYTE)'.' || dots >= 2U) {
            return FALSE;
        }
        ++dots;
        component_start = index + 1U;
    }
    return FALSE;
}

static BOOL swaw_read_host_version(
    const SwawUserIdentity *identity,
    WCHAR version[128]
)
{
    BYTE encoded[128];
    DWORD received = 0U;
    DWORD length;
    DWORD index;
    DWORD attributes;
    BYTE extra;
    DWORD extra_count = 0U;
    HANDLE pointer;

    if (!swaw_copy(
            swaw_host_version_path,
            SWAW_MAX_PATH_UNITS,
            identity->user_home
        ) ||
        !swaw_append(
            swaw_host_version_path,
            SWAW_MAX_PATH_UNITS,
            L"\\host\\current.x86_64-pc-windows-msvc"
        )) {
        return FALSE;
    }
    attributes = GetFileAttributesW(swaw_host_version_path);
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0U) {
        return FALSE;
    }
    pointer = CreateFileW(
        swaw_host_version_path,
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        NULL
    );
    if (pointer == INVALID_HANDLE_VALUE) {
        return FALSE;
    }
    if (!ReadFile(pointer, encoded, (DWORD)sizeof(encoded), &received, NULL) ||
        !ReadFile(pointer, &extra, 1U, &extra_count, NULL) ||
        extra_count != 0U) {
        CloseHandle(pointer);
        return FALSE;
    }
    CloseHandle(pointer);
    length = received;
    if (length == 0U || encoded[length - 1U] != (BYTE)'\n') {
        SetLastError(ERROR_INVALID_DATA);
        return FALSE;
    }
    --length;
    if (length > 0U && encoded[length - 1U] == (BYTE)'\r') {
        --length;
    }
    if (!swaw_is_exact_version(encoded, length)) {
        SetLastError(ERROR_INVALID_DATA);
        return FALSE;
    }
    for (index = 0U; index < length; ++index) {
        version[index] = (WCHAR)encoded[index];
    }
    version[length] = L'\0';
    return TRUE;
}

static BOOL swaw_start_host(const SwawUserIdentity *identity)
{
    WCHAR version[128];
    DWORD attributes;

    if (!swaw_read_host_version(identity, version) ||
        !swaw_copy(
            swaw_host_directory,
            SWAW_MAX_PATH_UNITS,
            identity->data_home
        ) ||
        !swaw_append(
            swaw_host_directory,
            SWAW_MAX_PATH_UNITS,
            L"\\admin\\modules\\swaw\\core\\host\\"
            L"x86_64-pc-windows-msvc\\"
        ) ||
        !swaw_append(swaw_host_directory, SWAW_MAX_PATH_UNITS, version) ||
        !swaw_copy(swaw_host_path, SWAW_MAX_PATH_UNITS, swaw_host_directory) ||
        !swaw_append(
            swaw_host_path,
            SWAW_MAX_PATH_UNITS,
            L"\\swaw-harness-core.exe"
        ) ||
        !swaw_copy(
            swaw_host_command_line,
            (DWORD)(sizeof(swaw_host_command_line) / sizeof(WCHAR)),
            L"swaw-harness-core.exe "
        ) ||
        !swaw_append(
            swaw_host_command_line,
            (DWORD)(sizeof(swaw_host_command_line) / sizeof(WCHAR)),
            identity->user_id
        )) {
        SetLastError(ERROR_BUFFER_OVERFLOW);
        return FALSE;
    }
    attributes = GetFileAttributesW(swaw_host_directory);
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0U ||
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0U) {
        return FALSE;
    }
    attributes = GetFileAttributesW(swaw_host_path);
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0U) {
        return FALSE;
    }
    swaw_host_startup.cb = (DWORD)sizeof(swaw_host_startup);
    if (!CreateProcessW(
            swaw_host_path,
            swaw_host_command_line,
            NULL,
            NULL,
            FALSE,
            CREATE_NO_WINDOW,
            NULL,
            swaw_host_directory,
            &swaw_host_startup,
            &swaw_host_process
        )) {
        return FALSE;
    }
    CloseHandle(swaw_host_process.hThread);
    CloseHandle(swaw_host_process.hProcess);
    return TRUE;
}

HANDLE swaw_connect(const SwawUserIdentity *identity)
{
    ULONGLONG deadline;
    DWORD error;
    HANDLE pipe = CreateFileW(
        identity->pipe_name,
        GENERIC_READ | GENERIC_WRITE,
        0U,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        NULL
    );
    if (pipe != INVALID_HANDLE_VALUE) {
        return pipe;
    }
    error = GetLastError();
    if (error == ERROR_FILE_NOT_FOUND) {
        if (!swaw_start_host(identity)) {
            return INVALID_HANDLE_VALUE;
        }
    } else if (error != ERROR_PIPE_BUSY) {
        return INVALID_HANDLE_VALUE;
    }
    deadline = GetTickCount64() + 15000ULL;
    for (;;) {
        pipe = CreateFileW(
            identity->pipe_name,
            GENERIC_READ | GENERIC_WRITE,
            0U,
            NULL,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL,
            NULL
        );
        if (pipe != INVALID_HANDLE_VALUE) {
            return pipe;
        }
        if (GetLastError() == ERROR_PIPE_BUSY) {
            (void)WaitNamedPipeW(identity->pipe_name, 100U);
        } else if (GetLastError() == ERROR_FILE_NOT_FOUND) {
            Sleep(25U);
        } else {
            return INVALID_HANDLE_VALUE;
        }
        if (GetTickCount64() >= deadline) {
            SetLastError(ERROR_TIMEOUT);
            return INVALID_HANDLE_VALUE;
        }
    }
}
