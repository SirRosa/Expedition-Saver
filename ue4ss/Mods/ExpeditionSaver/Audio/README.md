# Respawn sound (v0.7.5 test build)

- **respawn.wav** is converted from the audio file supplied by the user. For distribution, use the complete user-specific install ZIP; the original audio and its WAV conversion are intentionally not committed to the public repository.
- **respawn_audio.cpp** is the complete source for the tiny Windows helper. The GitHub Actions Windows job builds **respawn_audio.exe** from source. The final installer places the EXE and WAV beside each other in this folder.
- Playback is initiated **only once after a verified native respawn or successful existing-character revive fallback**.
- It uses UE4SS `ExecuteAsync` to launch a local, windowless Win64 helper. The child process plays the WAV using `PlaySoundW`, so the 2.7-second playback cannot block the Unreal game thread. It has no network access, registry modifications, or persistence.
- Default: `EnableRespawnSound = true` in `Scripts/main.lua`. Set to `false` to disable.
- Sound plays through **Windows' default output device**, independently of Unreal's in-game sound mixer/volume. It is **local**: on a hosted co-op game it plays only for a locally controlled player on the host. It is not replicated to clients.
- If `ExecuteAsync`, `os.execute`, the EXE or WAV is unavailable, the sound is skipped and respawn logic is unchanged.
- CI tests simulate the UE4SS API and Windows commands, and Windows Actions compiles the helper; actual audible in-game playback is not verified by CI.

**Install path**: `Grain Rot/Helden/Binaries/Win64/ue4ss/Mods/ExpeditionSaver/Audio/`.

**Important**: GitHub's source-only Lua artifact cannot contain the user-supplied WAV. The final downloadable combined ZIP includes both the compiled EXE and the WAV. Do not install the Lua-only Actions artifact expecting audio to work without both files.
