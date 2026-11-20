// Grain Rot / Expedition Saver v0.7.7 - zero-console, in-process respawn WAV
//
// Why a DLL? Lua os.execute launches cmd.exe, produces a visible window and
// delays playback while starting a process. UE4SS Lua supports native C
// libraries via package.loadlib. This tiny module deliberately does NOT
// depend on or access any Lua API: its lua_CFunction only triggers WinMM
// PlaySoundW(SND_ASYNC), and returns zero Lua values. Safe on x64 Lua 5.4.
//
// Audio is user-supplied and NOT committed to GitHub.
// Install this DLL next to respawn.wav in the mod's Audio/ folder.
//
// No subprocess, shell, console, additional thread, internet, files written,
// registry access, Unreal object access, or blocking WAV playback.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <cwchar>
#pragma comment(lib, "winmm.lib")

static HMODULE g_self = nullptr;
BOOL APIENTRY DllMain(HMODULE self, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = self;
        DisableThreadLibraryCalls(self);
    }
    return TRUE;
}

// package.loadlib("<path>\\respawn_audio.dll","luaopen_RespawnSound")
// Lua 5.4 calls this with lua_State*, which is unused and opaque here.
// x64 Windows has one native calling convention; no Lua DLL import needed.
extern "C" __declspec(dllexport) int __cdecl luaopen_RespawnSound(void* /*lua_state*/) {
    if (g_self == nullptr) return 0;
    wchar_t fullPath[MAX_PATH + 32]{};
    const DWORD len = GetModuleFileNameW(g_self, fullPath, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) return 0;
    wchar_t* separator = std::wcsrchr(fullPath, L'\\');
    if (separator == nullptr) return 0;

    // Fixed sibling file name; never execute user data as commands.
    constexpr wchar_t wavName[] = L"respawn.wav";
    const size_t remaining = (sizeof(fullPath) / sizeof(fullPath[0]))
        - static_cast<size_t>(separator + 1 - fullPath);
    if (remaining < sizeof(wavName) / sizeof(wavName[0])) return 0;
    std::wcscpy(separator + 1, wavName);

    // Async WinMM returns immediately; playback happens in the current
    // process without creating a console/window or freezing the game thread.
    PlaySoundW(fullPath, nullptr,
        SND_FILENAME | SND_NODEFAULT | SND_ASYNC);
    return 0;
}
