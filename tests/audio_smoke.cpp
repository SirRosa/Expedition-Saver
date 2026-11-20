// Windows Actions integration smoke-test for the in-process audio module.
// No Lua runtime needed: luaopen_RespawnSound deliberately ignores Lua state.
// This EXE exists only in CI and is NEVER shipped with the mod.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>

using AudioFn = int(__cdecl*)(void*);

int main() {
    HMODULE dll=LoadLibraryW(L".\\respawn_audio.dll");
    if (!dll) {
        std::fprintf(stderr,"DLL LoadLibraryW failed: %lu\n",GetLastError());
        return 10;
    }
    auto proc=GetProcAddress(dll,"luaopen_RespawnSound");
    if (!proc) {
        std::fprintf(stderr,"DLL entry luaopen_RespawnSound missing\n");
        FreeLibrary(dll);
        return 11;
    }
    auto fn=reinterpret_cast<AudioFn>(proc);
    if (fn(nullptr)!=0 || fn(nullptr)!=0) {
        std::fprintf(stderr,"luaopen entry returned unexpected values\n");
        FreeLibrary(dll);
        return 12;
    }
    FreeLibrary(dll);
    std::puts("PASS: Win64 audio DLL loads and exported function returns immediately");
    return 0;
}
