# SCCameraFix

## Fix the Sven Co-op spectator / chase camera (Sven Co-op only)

Sven Co-op's third-person and spectator camera clips through players and ignores the chase distance. SCCameraFix reinstates the correct observer view: it re-implements `V_CalcSpectatorRefdef` and hooks the client's `V_CalcNormalRefdef`, and routes the observer's `EV_PlayerTrace` through a proxy so the trace ignores the spectated player instead of the world. All client addresses are resolved through the MetaHook gamedata symbol catalog.

# Install

1. Download and install [MetaHookSv](https://github.com/hzqst/MetaHookSv).

2. Build or download .dll, put it into `/SteamLibrary/steamapps/common/Sven Co-op/svencoop/metahook/plugins` directory.

3. Add `SCCameraFix.dll` in `/SteamLibrary/steamapps/common/Sven Co-op/svencoop/metahook/configs/plugins.lst` as a newline.

4. Keep the `svencoop/metahook/gamedata/sccamerafix` directory shipped next to the plugin: it carries the client symbols (`V_CalcNormalRefdef`, `gEngfuncs`, `v_origin`, `g_vVecViewangles`, `g_iUser1`, `g_iUser2`) the plugin resolves at load time.

5. Enjoy.

# Client Cvar

|Cvar|Default|Comment|
|---|---|---|
|cl_chasedist|128|chase camera distance behind the target|

## F5 debugging (optional)

Install MetaHook and enable this plugin in the game's `plugins.lst` first. Configure a standalone Visual Studio Win32 solution:

```powershell
cmake -S . -B build/launch -G "Visual Studio 17 2022" -A Win32 -DMETAHOOKSV_ENABLE_LAUNCH_GAME=ON
```

Open the solution, select **LaunchGame** and press **F5**. **DeployGame** builds this plugin and its dependencies, stages Install, and copies plugin DLLs/PDBs/resources before the native debugger starts the existing game launcher. Root launchers/runtime files and plugin lists remain unchanged. Set VS to build before running and **Do not launch** on build errors; stop the game before redeploying. Ordinary builds do not deploy.

`METAHOOKSV_GAME_DIRECTORY` defaults to Steam discovery; `METAHOOKSV_GAME_APPID` defaults to `225840`. Set `METAHOOKSV_GAME_MOD` for a custom mod and `METAHOOKSV_GAME_ARGUMENTS` for extra arguments. Debug and Release are supported.

The shared module uses `METAHOOKSV_LAUNCH_GAME_MODULE_DIR`, the surrounding MetaHookSv checkout, or a pinned source archive. Without Installer sources, it downloads the self-contained CLI from GitHub `latest` (no .NET required); `METAHOOKSV_INSTALLER_RELEASE` selects a fixed tag, and `METAHOOKSV_INSTALLER_CLI_EXECUTABLE` supplies an offline EXE. Plugin mode requires v20261004c or later. Valid caches under `build/launch/launch-game/installer/<release>` are reused without update checks; select another tag or clear that private cache to upgrade. `GH_TOKEN`/`GITHUB_TOKEN` may be supplied through the environment if GitHub API rate limits prevent the first download. The feature defaults OFF and performs no extra downloads when disabled.

# Build

Requirements: Windows, Visual Studio 2022, CMake 3.21 or newer, Python 3.8 or newer. The first configure downloads VC-LTL 5.3.1 into `thirdparty/cache` and synchronizes the gamedata catalog.

1. Run `scripts\build-SCCameraFix-x86-Release.bat` (or `scripts\build-SCCameraFix-x86-Debug.bat`).

2. The plugin, its PDB and the gamedata catalog are installed to `install\x86\<Configuration>\svencoop\metahook`.

3. Copy `SCCameraFix.dll` and `gamedata\sccamerafix` into `svencoop/metahook`, as described in Install.

The MetaHook SDK is fetched automatically at a pinned commit. To build against a local MetaHook source tree instead, pass it on the command line or export the same environment variable before configuring:

```
scripts\build-SCCameraFix-x86-Release.bat -DMETAHOOK_SOURCE_PATH=D:\MetaHook
```

The path is the repository root that provides `include/metahook.h`, `include/HLSDK` and `include/Interface`.

SCCameraFix uses no Capstone and no SourceSDK headers; the MetaHook SDK tree is its only dependency besides VC-LTL. Pass `-DSCCAMERAFIX_SYNC_GAMEDATA=OFF` to build without downloading gamedata.
