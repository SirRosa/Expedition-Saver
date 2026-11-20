# Respawn sound — v0.7.6 host + client

- The **exact WAV supplied by the user** (`re-zero-return-by-death (1).wav`, 1.886 seconds, 44.1 kHz, 16-bit stereo) replaces the old 2.7-second sound in the downloadable installer. The user's audio asset is not committed to the public GitHub repo; install the complete ZIP.
- `respawn_audio.cpp` is the complete source for the small Windows WinMM `PlaySoundW` helper. The GitHub Actions Windows job builds `respawn_audio.exe` for x64. Both that EXE and `respawn.wav` are included in the finished installation ZIP.
- **Install the same ExpeditionSaver mod folder, including the Audio subfolder, on BOTH the host PC and each client PC.** The host retains authoritative respawn/rewards; on clients the audio listener is read-only and does not perform any gameplay mutation.
- **Host:** plays exactly once on confirmed successful native respawn or existing-pawn revive fallback. Only for the host's local controller.
- **Client:** watches **only the local controller** for a real living→dead→living transition, including `LastPlayerChar` when `GetPawn()` is nil, same-character revival, and `OnNewPawn` arriving before replicated `LastPlayerChar`. It does not need a server RPC or a server-side audio broadcast.
- Sound is **not** played on initial spawn, while dead, on simple respawn requests, or on remote players' respawns. There is no duplicate playback on the host; the client listener runs only without a live authoritative GameMode.
- The sound runs via UE4SS `ExecuteAsync` in a separate source-auditable Windows process (WinMM), not the Unreal game thread. It plays through the **local default Windows output device**, independent of the game's internal volume controls.
- Config: `EnableRespawnSound = true` in `Scripts/main.lua`. Set `false` to disable. Missing helper/audio/API simply skips playback.
- GitHub Actions uses mocked UE4SS client and server events (including nil `GetPawn()`) and compiles the Win64 helper. **Actual in-game client and host audio still requires verification on two PCs.**

**Installation:** extract the complete ZIP to `Grain Rot/Helden/Binaries/Win64/` on EACH PC, preserving `ue4ss/Mods/ExpeditionSaver/Audio/`.

**Important:** GitHub's code-only Actions artifact does not include the uploaded sound. The complete downloadable installation ZIP supplied in chat includes the correct new WAV and the compiled helper.
