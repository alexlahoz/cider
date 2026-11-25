/*
 * steamwebhelper.exe wrapper for Steam for Windows running under Wine on macOS.
 *
 * Problem: Steam's embedded Chromium (CEF) browser paints its windows black under Wine on macOS.
 * Started as a single process without GPU acceleration, it renders correctly.
 *
 * What it does: Steam launches "steamwebhelper.exe" (this program). We launch the original,
 * renamed to "steamwebhelper_real.exe", with the same arguments plus a few Chromium switches,
 * wait for it to exit and return its exit code.
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -municode -mwindows -s -Wl,--no-insert-timestamp \
 *        -o steamwebhelper.exe webhelper_wrapper.c
 */
#include <windows.h>
#include <wchar.h>

/* Cider looks for this marker to recognise any version of the wrapper. */
__attribute__((used)) static const char CIDER_MARKER[] = "CIDER_STEAMWEBHELPER_WRAPPER";

/* The real web helper is several MB; anything this small is a wrapper, and launching it would loop. */
#define MIN_REAL_SIZE (1024 * 1024)

static const wchar_t *EXTRA_FLAGS =
    L" --single-process"
    L" --disable-gpu"
    L" --disable-gpu-compositing"
    L" --in-process-gpu"
    L" --no-sandbox";

/* Returns a pointer to the arguments (everything after the program name). */
static const wchar_t *skip_program_name(const wchar_t *cmd)
{
    if (*cmd == L'"') {
        cmd++;
        while (*cmd && *cmd != L'"') cmd++;
        if (*cmd == L'"') cmd++;
    } else {
        while (*cmd && *cmd != L' ' && *cmd != L'\t') cmd++;
    }
    while (*cmd == L' ' || *cmd == L'\t') cmd++;
    return cmd;
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR unused, int show)
{
    (void)inst; (void)prev; (void)unused; (void)show;

    /* Path of the real executable: same folder, steamwebhelper_real.exe */
    wchar_t real[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, real, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return 1;
    wchar_t *slash = wcsrchr(real, L'\\');
    if (!slash) return 1;
    slash[1] = L'\0';
    if (wcslen(real) + 32 >= MAX_PATH) return 1;
    wcscat(real, L"steamwebhelper_real.exe");

    WIN32_FILE_ATTRIBUTE_DATA fa;
    if (!GetFileAttributesExW(real, GetFileExInfoStandard, &fa)) return 2;
    if (fa.nFileSizeHigh == 0 && fa.nFileSizeLow < MIN_REAL_SIZE) return 3;

    const wchar_t *args = skip_program_name(GetCommandLineW());

    /* New command line: "real" <original args> <extra switches> */
    size_t len = wcslen(real) + wcslen(args) + wcslen(EXTRA_FLAGS) + 8;
    wchar_t *cmdline = HeapAlloc(GetProcessHeap(), 0, len * sizeof(wchar_t));
    if (!cmdline) return 1;
    _snwprintf(cmdline, len, L"\"%ls\" %ls%ls", real, args, EXTRA_FLAGS);
    cmdline[len - 1] = L'\0';

    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(real, cmdline, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi))
        return (int)GetLastError();

    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return (int)code;
}
