#ifndef SWAW_HARNESS_USER_H
#define SWAW_HARNESS_USER_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#define SWAW_MAX_PATH_UNITS 32768U
#define SWAW_MAX_ARGUMENTS 64U
#define SWAW_MAX_PAYLOAD_BYTES (256U * 1024U)
#define SWAW_HEADER_BYTES 12U
#define SWAW_PROTOCOL_VERSION 1U
#define SWAW_KIND_REQUEST 1U
#define SWAW_KIND_STDOUT 2U
#define SWAW_KIND_STDERR 3U
#define SWAW_KIND_RESULT 4U
#define SWAW_KIND_ERROR 5U

typedef struct SwawUserIdentity {
    WCHAR data_home[SWAW_MAX_PATH_UNITS];
    WCHAR user_home[SWAW_MAX_PATH_UNITS];
    WCHAR harness_root[SWAW_MAX_PATH_UNITS];
    WCHAR pipe_name[256];
    WCHAR user_id[17];
} SwawUserIdentity;

BOOL swaw_initialize_identity(SwawUserIdentity *identity);
HANDLE swaw_connect(const SwawUserIdentity *identity);
BOOL swaw_send_request(
    HANDLE pipe,
    const SwawUserIdentity *identity,
    int argument_count,
    WCHAR **arguments
);
__declspec(noreturn) void swaw_receive(HANDLE pipe);
__declspec(noreturn) void swaw_fail(const char *message, DWORD length);
__declspec(noreturn) void swaw_fail_last_error(
    const char *message,
    DWORD length,
    DWORD error
);

#define SWAW_FAIL(message) swaw_fail((message), (DWORD)(sizeof(message) - 1U))
#define SWAW_FAIL_LAST_ERROR(message, error) \
    swaw_fail_last_error((message), (DWORD)(sizeof(message) - 1U), (error))

#endif
