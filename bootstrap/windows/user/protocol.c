#include "user.h"

#include <limits.h>

static DWORD swaw_length(const WCHAR *value)
{
    DWORD length = 0;
    while (value[length] != L'\0') {
        ++length;
    }
    return length;
}

static BOOL swaw_write_all(HANDLE handle, const BYTE *buffer, DWORD length)
{
    DWORD position = 0;
    while (position < length) {
        DWORD written = 0;
        if (!WriteFile(
                handle,
                buffer + position,
                length - position,
                &written,
                NULL
            ) || written == 0U) {
            return FALSE;
        }
        position += written;
    }
    return TRUE;
}

static BOOL swaw_write_utf8_text(
    HANDLE handle,
    const BYTE *buffer,
    DWORD length
)
{
    DWORD console_mode;
    int required_units;
    int converted_units;
    int additional_units = 0;
    WCHAR *text;
    DWORD position = 0U;

    if (!GetConsoleMode(handle, &console_mode)) {
        return swaw_write_all(handle, buffer, length);
    }
    if (length == 0U) {
        return TRUE;
    }
    required_units = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        (const char *)buffer,
        (int)length,
        NULL,
        0
    );
    if (required_units <= 0) {
        return FALSE;
    }
    text = (WCHAR *)HeapAlloc(
        GetProcessHeap(),
        0U,
        (SIZE_T)required_units * sizeof(WCHAR)
    );
    if (text == NULL) {
        return FALSE;
    }
    converted_units = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        (const char *)buffer,
        (int)length,
        text,
        required_units
    );
    if (converted_units != required_units) {
        HeapFree(GetProcessHeap(), 0U, text);
        return FALSE;
    }
    for (converted_units = 0; converted_units < required_units; ++converted_units) {
        if (text[converted_units] == L'\n' &&
            (converted_units == 0 || text[converted_units - 1] != L'\r')) {
            ++additional_units;
        }
    }
    if (additional_units > 0) {
        int source = required_units;
        int destination;
        WCHAR *expanded;
        if (additional_units > INT_MAX - required_units) {
            HeapFree(GetProcessHeap(), 0U, text);
            return FALSE;
        }
        converted_units = required_units + additional_units;
        expanded = (WCHAR *)HeapReAlloc(
            GetProcessHeap(),
            0U,
            text,
            (SIZE_T)converted_units * sizeof(WCHAR)
        );
        if (expanded == NULL) {
            HeapFree(GetProcessHeap(), 0U, text);
            return FALSE;
        }
        text = expanded;
        destination = converted_units;
        while (source > 0) {
            WCHAR unit = text[--source];
            text[--destination] = unit;
            if (unit == L'\n' && (source == 0 || text[source - 1] != L'\r')) {
                text[--destination] = L'\r';
            }
        }
    } else {
        converted_units = required_units;
    }
    while (position < (DWORD)converted_units) {
        DWORD written = 0U;
        if (!WriteConsoleW(
                handle,
                text + position,
                (DWORD)converted_units - position,
                &written,
                NULL
            ) || written == 0U) {
            HeapFree(GetProcessHeap(), 0U, text);
            return FALSE;
        }
        position += written;
    }
    HeapFree(GetProcessHeap(), 0U, text);
    return TRUE;
}

static BOOL swaw_read_all(HANDLE handle, BYTE *buffer, DWORD length)
{
    DWORD position = 0;
    while (position < length) {
        DWORD received = 0;
        if (!ReadFile(
                handle,
                buffer + position,
                length - position,
                &received,
                NULL
            ) || received == 0U) {
            return FALSE;
        }
        position += received;
    }
    return TRUE;
}

__declspec(noreturn) void swaw_fail(const char *message, DWORD length)
{
    HANDLE error_handle = GetStdHandle(STD_ERROR_HANDLE);
    if (error_handle != NULL && error_handle != INVALID_HANDLE_VALUE) {
        (void)swaw_write_all(error_handle, (const BYTE *)message, length);
    }
    ExitProcess(1U);
}

__declspec(noreturn) void swaw_fail_last_error(
    const char *message,
    DWORD length,
    DWORD error
)
{
    static const char digits[] = "0123456789abcdef";
    char suffix[] = " [Win32 0x00000000]\r\n";
    DWORD index;
    HANDLE error_handle = GetStdHandle(STD_ERROR_HANDLE);
    for (index = 0U; index < 8U; ++index) {
        suffix[10U + index] = digits[(error >> ((7U - index) * 4U)) & 0x0fU];
    }
    if (error_handle != NULL && error_handle != INVALID_HANDLE_VALUE) {
        (void)swaw_write_all(error_handle, (const BYTE *)message, length);
        (void)swaw_write_all(
            error_handle,
            (const BYTE *)suffix,
            (DWORD)(sizeof(suffix) - 1U)
        );
    }
    ExitProcess(1U);
}

static void swaw_put_u32(BYTE **position, DWORD value)
{
    (*position)[0] = (BYTE)(value & 0xffU);
    (*position)[1] = (BYTE)((value >> 8U) & 0xffU);
    (*position)[2] = (BYTE)((value >> 16U) & 0xffU);
    (*position)[3] = (BYTE)((value >> 24U) & 0xffU);
    *position += 4;
}

static void swaw_put_utf16(BYTE **position, const WCHAR *value, DWORD units)
{
    DWORD index;
    swaw_put_u32(position, units);
    for (index = 0U; index < units; ++index) {
        WCHAR unit = value[index];
        (*position)[0] = (BYTE)(unit & 0xffU);
        (*position)[1] = (BYTE)((unit >> 8U) & 0xffU);
        *position += 2;
    }
}

BOOL swaw_send_request(
    HANDLE pipe,
    const SwawUserIdentity *identity,
    int argument_count,
    WCHAR **arguments
)
{
    DWORD user_id_units = swaw_length(identity->user_id);
    DWORD user_home_units = swaw_length(identity->user_home);
    SIZE_T payload_size = 12U +
        (SIZE_T)user_id_units * 2U +
        (SIZE_T)user_home_units * 2U;
    BYTE header[SWAW_HEADER_BYTES] = {
        (BYTE)'S', (BYTE)'W', (BYTE)'A', (BYTE)'H',
        (BYTE)SWAW_PROTOCOL_VERSION, 0U,
        (BYTE)SWAW_KIND_REQUEST, 0U,
        0U, 0U, 0U, 0U
    };
    BYTE *payload;
    BYTE *position;
    int index;

    if (argument_count < 1 || argument_count > (int)SWAW_MAX_ARGUMENTS) {
        return FALSE;
    }
    for (index = 0; index < argument_count; ++index) {
        DWORD units = swaw_length(arguments[index]);
        if ((index == 0 && units == 0U) || units > 32768U) {
            return FALSE;
        }
        payload_size += 4U + (SIZE_T)units * 2U;
        if (payload_size > SWAW_MAX_PAYLOAD_BYTES) {
            return FALSE;
        }
    }
    payload = (BYTE *)HeapAlloc(GetProcessHeap(), 0U, payload_size);
    if (payload == NULL) {
        return FALSE;
    }
    position = payload;
    swaw_put_utf16(&position, identity->user_id, user_id_units);
    swaw_put_utf16(&position, identity->user_home, user_home_units);
    swaw_put_u32(&position, (DWORD)argument_count);
    for (index = 0; index < argument_count; ++index) {
        swaw_put_utf16(
            &position,
            arguments[index],
            swaw_length(arguments[index])
        );
    }
    header[8] = (BYTE)((DWORD)payload_size & 0xffU);
    header[9] = (BYTE)(((DWORD)payload_size >> 8U) & 0xffU);
    header[10] = (BYTE)(((DWORD)payload_size >> 16U) & 0xffU);
    header[11] = (BYTE)(((DWORD)payload_size >> 24U) & 0xffU);
    if (!swaw_write_all(pipe, header, SWAW_HEADER_BYTES) ||
        !swaw_write_all(pipe, payload, (DWORD)payload_size)) {
        HeapFree(GetProcessHeap(), 0U, payload);
        return FALSE;
    }
    HeapFree(GetProcessHeap(), 0U, payload);
    return TRUE;
}

static DWORD swaw_u32(const BYTE *value)
{
    return (DWORD)value[0] |
        ((DWORD)value[1] << 8U) |
        ((DWORD)value[2] << 16U) |
        ((DWORD)value[3] << 24U);
}

static BOOL swaw_is_run_id(const BYTE *value, DWORD length)
{
    DWORD index;
    if (length != 32U || value[12] != (BYTE)'7' ||
        (value[16] != (BYTE)'8' && value[16] != (BYTE)'9' &&
         value[16] != (BYTE)'a' && value[16] != (BYTE)'b')) {
        return FALSE;
    }
    for (index = 0U; index < length; ++index) {
        if (!((value[index] >= (BYTE)'0' && value[index] <= (BYTE)'9') ||
              (value[index] >= (BYTE)'a' && value[index] <= (BYTE)'f'))) {
            return FALSE;
        }
    }
    return TRUE;
}

__declspec(noreturn) void swaw_receive(HANDLE pipe)
{
    BYTE header[SWAW_HEADER_BYTES];
    HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
    HANDLE error = GetStdHandle(STD_ERROR_HANDLE);

    for (;;) {
        DWORD kind;
        DWORD length;
        BYTE *payload;
        if (!swaw_read_all(pipe, header, SWAW_HEADER_BYTES) ||
            header[0] != (BYTE)'S' || header[1] != (BYTE)'W' ||
            header[2] != (BYTE)'A' || header[3] != (BYTE)'H' ||
            header[4] != (BYTE)SWAW_PROTOCOL_VERSION || header[5] != 0U) {
            CloseHandle(pipe);
            SWAW_FAIL("[ERROR] Core Host returned an invalid response.\r\n");
        }
        kind = (DWORD)header[6] | ((DWORD)header[7] << 8U);
        length = swaw_u32(header + 8U);
        if (length > SWAW_MAX_PAYLOAD_BYTES ||
            (kind == SWAW_KIND_RESULT && length != 4U) ||
            (kind == SWAW_KIND_RUN_ID && length != 32U)) {
            CloseHandle(pipe);
            SWAW_FAIL("[ERROR] Core Host returned an invalid frame.\r\n");
        }
        payload = (BYTE *)HeapAlloc(
            GetProcessHeap(),
            0U,
            length == 0U ? 1U : length
        );
        if (payload == NULL || !swaw_read_all(pipe, payload, length)) {
            if (payload != NULL) {
                HeapFree(GetProcessHeap(), 0U, payload);
            }
            CloseHandle(pipe);
            SWAW_FAIL("[ERROR] Cannot read the Core Host response.\r\n");
        }
        if (kind == SWAW_KIND_STDOUT) {
            if (output != NULL && output != INVALID_HANDLE_VALUE) {
                if (!swaw_write_all(output, payload, length)) {
                    HeapFree(GetProcessHeap(), 0U, payload);
                    CloseHandle(pipe);
                    ExitProcess(1U);
                }
            }
        } else if (kind == SWAW_KIND_UTF8_STDOUT) {
            if (output != NULL && output != INVALID_HANDLE_VALUE) {
                if (!swaw_write_utf8_text(output, payload, length)) {
                    HeapFree(GetProcessHeap(), 0U, payload);
                    CloseHandle(pipe);
                    ExitProcess(1U);
                }
            }
        } else if (kind == SWAW_KIND_STDERR || kind == SWAW_KIND_ERROR) {
            if (error != NULL && error != INVALID_HANDLE_VALUE) {
                if (!swaw_write_all(error, payload, length)) {
                    HeapFree(GetProcessHeap(), 0U, payload);
                    CloseHandle(pipe);
                    ExitProcess(1U);
                }
            }
        } else if (kind == SWAW_KIND_RUN_ID) {
            static const BYTE prefix[] = "[RUN] ";
            static const BYTE suffix[] = "\r\n";
            if (!swaw_is_run_id(payload, length)) {
                HeapFree(GetProcessHeap(), 0U, payload);
                CloseHandle(pipe);
                SWAW_FAIL("[ERROR] Core Host returned an invalid RunId.\r\n");
            }
            if (error != NULL && error != INVALID_HANDLE_VALUE &&
                (!swaw_write_all(
                    error,
                    prefix,
                    (DWORD)(sizeof(prefix) - 1U)
                ) ||
                 !swaw_write_all(error, payload, length) ||
                 !swaw_write_all(
                    error,
                    suffix,
                    (DWORD)(sizeof(suffix) - 1U)
                ))) {
                HeapFree(GetProcessHeap(), 0U, payload);
                CloseHandle(pipe);
                ExitProcess(1U);
            }
        } else if (kind == SWAW_KIND_RESULT) {
            DWORD exit_code = swaw_u32(payload);
            HeapFree(GetProcessHeap(), 0U, payload);
            CloseHandle(pipe);
            ExitProcess(exit_code);
        } else {
            HeapFree(GetProcessHeap(), 0U, payload);
            CloseHandle(pipe);
            SWAW_FAIL("[ERROR] Core Host returned an unknown frame.\r\n");
        }
        HeapFree(GetProcessHeap(), 0U, payload);
    }
}
