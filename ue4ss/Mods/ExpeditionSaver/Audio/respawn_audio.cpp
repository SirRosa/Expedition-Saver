// Standalone Windows WAV player for Expedition Saver's respawn effect.
// WinMM PlaySoundW is synchronous *inside this child process*. The game
// invokes it via UE4SS ExecuteAsync, never on Unreal's game thread.
// No network access, registry writes, file modifications or persistence.
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <shellapi.h>
#include <mmsystem.h>
#pragma comment(lib, "winmm.lib")
#pragma comment(lib, "shell32.lib")

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    int argc = 0;
    LPWSTR* args = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!args || argc != 2) {
        if (args) LocalFree(args);
        return 2;
    }
    const wchar_t* wavPath = args[1];
    const DWORD attrs = GetFileAttributesW(wavPath);
    if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
        LocalFree(args);
        return 3;
    }
    const BOOL played = PlaySoundW(
        wavPath, nullptr, SND_FILENAME | SND_NODEFAULT | SND_SYNC);
    LocalFree(args);
    return played ? 0 : 4;
}
