# Respawn audio v0.7.7 — instant, invisible, host + client

The exact user-provided **re-zero-return-by-death (1).wav** (1.886 s, PCM 44.1 kHz stereo) is included as `respawn.wav` **only in the chat installation ZIP**. It is not committed to this public repository.

## Why we removed the EXE

v0.7.5–v0.7.6 mistakenly used `os.execute()` to launch a Win32 EXE. Lua invokes `cmd.exe`, making a visible console window and introducing process-launch latency. This was unsuitable for a game.

v0.7.7 ships a small **in-process Windows DLL**:
- `respawn_audio.cpp` is its complete auditable source.
- `respawn_audio.dll` is compiled in GitHub Actions x64, copied into the final installation ZIP.
- `Scripts/main.lua` uses Lua's `package.loadlib(path, "luaopen_RespawnSound")` to load it **once at mod startup**.
- The exported Lua C function ignores its Lua argument, needs no Lua runtime exports, and calls native `PlaySoundW(... SND_FILENAME | SND_NODEFAULT | SND_ASYNC)`, which **returns without waiting for the WAV to finish**.
- **No shell, CMD, subprocess, EXE, PowerShell, busy-loop or sleep.** Audio is played through Windows' default sound device; game audio-volume settings do not control it.

Host: played once on successful server-side respawn or verified fallback revive. Client: the local-only observer triggers after witnessed death on `OnNewPawn`, replicated `CharacterState` revival or its periodic fallback. Not for initial join or remote players.

## Installation

Extract the user-specific ZIP to `Grain Rot/Helden/Binaries/Win64/` on **both host and each client**. The files must be adjacent in `ue4ss/Mods/ExpeditionSaver/Audio/`:

- `respawn_audio.dll`
- `respawn.wav`
- (optional/auditable) `respawn_audio.cpp`

`respawn_audio.exe` from older versions is obsolete and can be deleted. It is **not included or invoked** by v0.7.7.

Enable/disable via `EnableRespawnSound = true/false` in `Scripts/main.lua`. If `package.loadlib` or the DLL is unavailable, audio is silently skipped with one error log; respawn and currency logic continue.

CI performs Lua 5.4 mock regression tests and compiles/smoke-tests the DLL on Windows x64. **Actual in-game audible playback and host/client synchronization still require verification on two real PCs.**
