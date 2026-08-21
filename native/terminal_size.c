#include <stdint.h>

#ifdef _WIN32
#include <windows.h>

uint64_t CJDiagnosticGetTerminalWidth(void)
{
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    BOOL isSuccess = GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi);
    if (!isSuccess)
        return 0;
    return (uint64_t)(csbi.srWindow.Right - csbi.srWindow.Left + 1);
}
#else
#include <sys/ioctl.h>
#include <unistd.h>

uint64_t CJDiagnosticGetTerminalWidth(void)
{
    struct winsize w;
    int isFailure = ioctl(STDOUT_FILENO, TIOCGWINSZ, &w);
    if (isFailure != 0)
        return 0;
    return (uint64_t)w.ws_col;
}
#endif
