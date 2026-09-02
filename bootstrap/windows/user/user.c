#include "user.h"
#include <shellapi.h>

static SwawUserIdentity swaw_identity;

__declspec(noreturn) void swaw_user_cli_main(void)
{
    int argument_count = 0;
    WCHAR **arguments;
    HANDLE pipe;

    if (!swaw_initialize_identity(&swaw_identity)) {
        SWAW_FAIL("[ERROR] User CLI executable is not installed in DataHome.\r\n");
    }
    arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
    if (arguments == NULL || argument_count < 2 ||
        argument_count - 1 > (int)SWAW_MAX_ARGUMENTS) {
        if (arguments != NULL) {
            LocalFree(arguments);
        }
        SWAW_FAIL("[ERROR] A SkillPath is required.\r\n");
    }
    pipe = swaw_connect(&swaw_identity);
    if (pipe == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        LocalFree(arguments);
        SWAW_FAIL_LAST_ERROR(
            "[ERROR] Cannot connect to the Harness User Core Host.",
            error
        );
    }
    if (!swaw_send_request(
            pipe,
            &swaw_identity,
            argument_count - 1,
            arguments + 1
        )) {
        LocalFree(arguments);
        CloseHandle(pipe);
        SWAW_FAIL("[ERROR] Cannot send the Core Host request.\r\n");
    }
    LocalFree(arguments);
    swaw_receive(pipe);
}
