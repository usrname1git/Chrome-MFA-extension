#include <windows.h>
#include <filesystem>
#include <fstream>
#include <string>

int wmain(int argc, wchar_t** argv) {
    if (argc == 2 && std::wstring(argv[1]) == L"--child") {
        Sleep(15000);
        return 0;
    }
    std::filesystem::path output;
    for (int i = 1; i + 1 < argc; ++i) {
        if (std::wstring(argv[i]) == L"--path") output = argv[i + 1];
    }
    if (output.empty()) return 2;
    wchar_t executable[32768]{};
    if (!GetModuleFileNameW(nullptr, executable, 32768)) return 2;
    std::wstring command = L"\"" + std::wstring(executable) + L"\" --child";
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION child{};
    if (!CreateProcessW(executable, command.data(), nullptr, nullptr, FALSE,
                        CREATE_NO_WINDOW, nullptr, nullptr, &startup, &child)) return 2;
    std::ofstream pid(output / "child.pid");
    pid << child.dwProcessId;
    pid.close();
    const bool written = !pid.fail();
    if (!written) TerminateProcess(child.hProcess, 2);
    CloseHandle(child.hThread);
    CloseHandle(child.hProcess);
    return written ? 7 : 2;
}
