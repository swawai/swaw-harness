#include "user.h"

static WCHAR swaw_module_path[SWAW_MAX_PATH_UNITS];

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

static BOOL swaw_equal_segment(
    const WCHAR *path,
    DWORD start,
    const WCHAR *expected
)
{
    DWORD index = 0;
    while (expected[index] != L'\0') {
        if (path[start + index] != expected[index]) {
            return FALSE;
        }
        ++index;
    }
    return path[start + index] == L'\0';
}

static ULONGLONG swaw_hash_unit(ULONGLONG hash, WCHAR value)
{
    hash ^= (ULONGLONG)value;
    return hash * 0x100000001b3ULL;
}

static ULONGLONG swaw_endpoint_hash(const SwawUserIdentity *identity)
{
    const WCHAR *path = identity->harness_root;
    DWORD length = swaw_length(path);
    DWORD index = 0U;
    ULONGLONG hash = 0xcbf29ce484222325ULL;

    if (length >= 4U && path[0] == L'\\' && path[1] == L'\\' &&
        path[2] == L'?' && path[3] == L'\\') {
        index = 4U;
        if (length >= 8U && path[4] == L'U' && path[5] == L'N' &&
            path[6] == L'C' && path[7] == L'\\') {
            hash = swaw_hash_unit(hash, L'\\');
            hash = swaw_hash_unit(hash, L'\\');
            index = 8U;
        }
    }
    while (length > index &&
           (path[length - 1U] == L'\\' || path[length - 1U] == L'/')) {
        --length;
    }
    while (index < length) {
        WCHAR value = path[index++];
        if (value == L'/') {
            value = L'\\';
        } else if (value >= L'A' && value <= L'Z') {
            value = (WCHAR)(value + (L'a' - L'A'));
        }
        hash = swaw_hash_unit(hash, value);
    }
    hash = swaw_hash_unit(hash, L'\0');
    index = 0U;
    while (identity->user_id[index] != L'\0') {
        hash = swaw_hash_unit(hash, identity->user_id[index++]);
    }
    return hash;
}

static void swaw_initialize_pipe_name(SwawUserIdentity *identity)
{
    static const WCHAR prefix[] = L"\\\\.\\pipe\\swaw-harness-v1-";
    static const WCHAR digits[] = L"0123456789abcdef";
    ULONGLONG hash = swaw_endpoint_hash(identity);
    DWORD position = 0U;
    DWORD index = 0U;

    while (prefix[index] != L'\0') {
        identity->pipe_name[position++] = prefix[index++];
    }
    for (index = 0U; index < 16U; ++index) {
        DWORD shift = (15U - index) * 4U;
        identity->pipe_name[position++] = digits[(hash >> shift) & 0x0fU];
    }
    identity->pipe_name[position++] = L'-';
    index = 0U;
    while (identity->user_id[index] != L'\0') {
        identity->pipe_name[position++] = identity->user_id[index++];
    }
    identity->pipe_name[position] = L'\0';
}

BOOL swaw_initialize_identity(SwawUserIdentity *identity)
{
    DWORD length = GetModuleFileNameW(
        NULL,
        swaw_module_path,
        SWAW_MAX_PATH_UNITS
    );
    DWORD separator;
    DWORD name_start;
    DWORD name_length;
    DWORD index;
    DWORD data_separator;
    WCHAR previous = L'\0';

    if (length == 0U || length + 1U >= SWAW_MAX_PATH_UNITS) {
        return FALSE;
    }
    separator = length;
    while (separator > 0U &&
           swaw_module_path[separator - 1U] != L'\\' &&
           swaw_module_path[separator - 1U] != L'/') {
        --separator;
    }
    if (separator == 0U || length - separator <= 4U) {
        return FALSE;
    }
    name_start = separator;
    name_length = length - separator - 4U;
    if (name_length == 0U || name_length > 16U ||
        swaw_module_path[length - 4U] != L'.' ||
        swaw_module_path[length - 3U] != L'e' ||
        swaw_module_path[length - 2U] != L'x' ||
        swaw_module_path[length - 1U] != L'e') {
        return FALSE;
    }
    for (index = 0U; index < name_length; ++index) {
        WCHAR value = swaw_module_path[name_start + index];
        if ((index == 0U && !(value >= L'a' && value <= L'z')) ||
            (index > 0U && !((value >= L'a' && value <= L'z') ||
              (value >= L'0' && value <= L'9') || value == L'-')) ||
            (value == L'-' && previous == L'-')) {
            return FALSE;
        }
        identity->user_id[index] = value;
        previous = value;
    }
    if (previous == L'-' ||
        (name_length == 3U &&
         ((identity->user_id[0] == L'c' && identity->user_id[1] == L'o' &&
           identity->user_id[2] == L'n') ||
          (identity->user_id[0] == L'p' && identity->user_id[1] == L'r' &&
           identity->user_id[2] == L'n') ||
          (identity->user_id[0] == L'a' && identity->user_id[1] == L'u' &&
           identity->user_id[2] == L'x') ||
          (identity->user_id[0] == L'n' && identity->user_id[1] == L'u' &&
           identity->user_id[2] == L'l'))) ||
        (name_length == 4U && identity->user_id[3] >= L'1' &&
         identity->user_id[3] <= L'9' &&
         ((identity->user_id[0] == L'c' && identity->user_id[1] == L'o' &&
           identity->user_id[2] == L'm') ||
          (identity->user_id[0] == L'l' && identity->user_id[1] == L'p' &&
           identity->user_id[2] == L't')))) {
        return FALSE;
    }
    identity->user_id[name_length] = L'\0';
    swaw_module_path[separator - 1U] = L'\0';
    if (!swaw_copy(identity->data_home, SWAW_MAX_PATH_UNITS, swaw_module_path)) {
        return FALSE;
    }
    data_separator = swaw_length(identity->data_home);
    while (data_separator > 0U &&
           identity->data_home[data_separator - 1U] != L'\\' &&
           identity->data_home[data_separator - 1U] != L'/') {
        --data_separator;
    }
    if (data_separator == 0U ||
        !swaw_equal_segment(identity->data_home, data_separator, L"data")) {
        return FALSE;
    }
    if (!swaw_copy(
            identity->harness_root,
            SWAW_MAX_PATH_UNITS,
            identity->data_home
        )) {
        return FALSE;
    }
    identity->harness_root[data_separator - 1U] = L'\0';
    if (!swaw_copy(
            identity->user_home,
            SWAW_MAX_PATH_UNITS,
            identity->data_home
        ) ||
        !swaw_append(identity->user_home, SWAW_MAX_PATH_UNITS, L"\\") ||
        !swaw_append(
            identity->user_home,
            SWAW_MAX_PATH_UNITS,
            identity->user_id
        )) {
        return FALSE;
    }
    swaw_initialize_pipe_name(identity);
    return TRUE;
}
