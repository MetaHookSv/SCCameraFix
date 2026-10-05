# AGENTS.md - SCCameraFix Project Guide

## Project Overview

**SCCameraFix** is a Sven Co-op only plugin for MetaHookSV that fixes the third-person / spectator chase camera. Sven Co-op's camera clips through players and ignores the chase distance; the plugin re-implements the observer view by re-implementing `V_CalcSpectatorRefdef` and hooking the client's `V_CalcNormalRefdef`, and it routes the observer's `EV_PlayerTrace` through a proxy so the trace ignores the spectated player instead of the world. All client addresses come from the MetaHook gamedata symbol catalog.

The plugin is small and self-contained: four plugin translation units, one gamedata module, no UI, no test suite. Read the sources directly instead of hunting for more documents.

- **Project type**: Native C++ plugin (Windows DLL), MSVC x86 only
- **Engine**: Sven Co-op 5.x client (`svengine` class builds only — see Engine Compatibility)
- **Framework**: MetaHookSV Plugin API (`IPluginsV4`, API 109 or newer)
- **Main dependencies**: MetaHook SDK only (public API + `include/HLSDK/common/interface.cpp`). **No Capstone, no SourceSDK, no third-party library is linked**

## Project Structure

```
SCCameraFix/
├── src/
│   ├── plugins.cpp            # IPluginsV4 lifecycle: Init / LoadEngine / LoadClient / ExitGame
│   ├── plugins.h              # Shared globals, API guard, GamedataResolvePtr, legacy search macros
│   ├── privatehook.cpp        # Client symbol resolution, V_CalcNormalRefdef hook, unused helpers
│   ├── privatehook.h          # private_funcs_t, resolved client globals, hook declarations
│   ├── exportfuncs.cpp        # Camera re-implementation, Event API proxies, HUD_Init/Shutdown
│   ├── exportfuncs.h          # HUD/CAM_Think declarations, OBS_SVEN_* observer-mode macros
│   ├── mathlib2.cpp/.h        # Trimmed copy of the HL/Source math library (vectors, angles, matrices)
│   └── (no enginedef.h)       # <metahook.h> and the SDK headers are included directly
├── cmake/
│   ├── Sources.cmake          # Explicit compile list
│   ├── Dependencies.cmake     # Source-path resolution and FetchContent fallback
│   ├── LaunchGame.cmake       # Optional F5 deploy support
│   └── VCLTL.cmake            # VC-LTL 5.3.1
├── scripts/
│   ├── build-SCCameraFix-x86-{Debug,Release}.bat
│   ├── manifests/sccamerafix.json      # Gamedata manifest (6 client symbols, 2 game builds)
│   ├── sync-gamedata.py                # Prunes the upstream catalog into the build tree
│   └── validate-gamedata.py            # Validates it before the plugin target builds
├── .github/workflows/livebuild.yml, release.yml   # CI, via .github/actions/build-windows-x86
├── thirdparty/cache/          # Ignored VC-LTL binary cache
├── build/x86/<configuration>/    # Ignored build output
├── install/x86/<configuration>/  # Ignored install output
├── README.md                  # Install, `cl_chasedist`, build (English only, no docs/ directory)
└── CMakeLists.txt             # Windows MSVC x86 build and install rules
```

## Core Modules

### 1. Plugin lifecycle (`src/plugins.cpp`)

`IPluginsV4` exported through `EXPOSE_SINGLE_INTERFACE(IPluginsV4, IPluginsV4, METAHOOK_PLUGIN_API_VERSION_V4)`:

- `Init`: stores the host API / interface / engine save
- `LoadEngine`: collects the file system, engine type/buildnum, then fills four `mh_dll_info_t` records — engine, mirror engine, client, mirror client — including their `.text` / `.data` / `.rdata` sections, and copies `cl_enginefunc_t`. **It installs no hooks**
- `LoadClient`: copies the export table, fills the client / mirror-client records, **takes over three slots** — `CAM_Think`, `HUD_Init`, `HUD_Shutdown` — and then runs `Client_FillAddress(...)` followed by `Client_InstallHooks()`
- `ExitGame`: empty; the client hooks are removed in `HUD_Shutdown` instead
- `GetVersion`: returns the build timestamp baked in by CMake

### 2. Client symbol resolution (`src/privatehook.cpp`)

`GamedataResolvePtr` (an inline helper in `src/plugins.h`) wraps `g_pMetaHookAPI->ResolveGameSymbol`. A miss is fatal: it reports the symbol, its owning module, the host's status string and the engine buildnum through `Sys_Error`. Unlike the other plugin repositories this diagnostic carries **no CRC64**.

`Client_FillAddress(DllInfo, RealDllInfo)` resolves everything against the **real** client DLL (`RealDllInfo` = `g_ClientDLLInfo`, the non-mirror image), module `client`:

- `pfnClientFactory("SCClientDLL001", 0)` must succeed, otherwise `Sys_Error("This plugin is for Sven Co-op!")`. This is the only Sven Co-op gate
- `gEngfuncs` (the *client's own* global, module `client`) — only its address is kept, to reach the `pEventAPI` slot
- `v_origin`, `g_vVecViewangles` (globals), `V_CalcNormalRefdef` (function)
- `Client_FillAddress_CL_IsThirdPerson` resolves `g_iUser1` and `g_iUser2`

`Client_InstallHooks` installs a single inline hook on `V_CalcNormalRefdef`; `Client_UninstallHooks` removes it.

Two helpers in this file are **dead code** and must not be mistaken for an active path: `ConvertDllInfoSpace` (declared in `privatehook.h`, never called) and `GetVFunctionFromVFTable` (defined only, never called or declared). Note that several of their locals are consumed by `RVA_from_VA` / `VA_from_RVA` through token pasting (`name` + `_VA` / `_RVA`), so the code reads as if it referenced undeclared variables.

### 3. Spectator camera (`src/exportfuncs.cpp`)

`V_CalcNormalRefdef` (the hook) dispatches to the plugin's own implementation whenever the engine is in an observer view — `pparams->spectator || (*g_iUser1)` — and otherwise forwards to the original `gPrivateFuncs.V_CalcNormalRefdef`.

`V_CalcSpectatorRefdef` switches on `*g_iUser1`:

| Value | Mode | Behaviour |
| --- | --- | --- |
| `OBS_SVEN_NONE` (0) | not observing | not handled here — the hook only enters on a non-zero mode |
| `OBS_SVEN_CHASE_FREE` (1) | free chase | `V_GetChasePos(*g_iUser2, &v_cl_angles, ...)` — mouse angles drive the view |
| `OBS_SVEN_ROAMING` (2) | roaming | copies `cl_viewangles` and `simorg` straight through |
| `OBS_SVEN_CHASE_LOCKED` (3) | locked chase | `V_GetChasePos(*g_iUser2, nullptr, ...)` — the target's own angles, pitch negated |

It writes `cl_viewangles`, `viewangles` and `vieworg` back into `ref_params_t` and mirrors `viewangles` into `*g_vVecViewangles` for the sound engine.

The chase math:

- `V_GetChasePos`: target 0 falls back to the local player's angles/origin; the origin is the target's origin plus `VEC_VIEW` (`0, 0, 28`); the distance comes from `cl_chasedist`, defaulting to 128 when the cvar is unavailable
- `V_GetChaseOrigin`: traces backwards along the view angles in up to 8 iterations, skipping each entity it hits, stopping on the world, on non-player `SOLID_BSP` geometry, or when within 1 unit of the end; the returned point is the end position pushed 4 units along the trace plane normal

### 4. Event API proxy (`src/exportfuncs.cpp`)

`HUD_Init` copies `gEngfuncs.pEventAPI` into a static `s_ProxyEventAPI`, replaces three entries, and installs it into the **client DLL's own** `gEngfuncs.pEventAPI` slot:

```
s_ProxyEventAPI.EV_PlayerTrace           = EV_PlayerTrace_Proxy
s_ProxyEventAPI.EV_SetUpPlayerPrediction = EV_SetUpPlayerPrediction_Proxy
s_ProxyEventAPI.EV_SetSolidPlayers       = EV_SetSolidPlayers_Proxy
(*g_pClientDLLEventAPI) = &s_ProxyEventAPI      // &client_gEngfuncs->pEventAPI
```

The plugin's own `gEngfuncs.pEventAPI` still points at the original table, which is what the proxies call through — so the plugin never recurses into itself.

`CAM_Think` brackets the original call with `g_bIsCallingCAM_Think`, and the re-entrant `EV_PlayerTrace_Proxy` only rewrites the trace when **both** conditions hold: it is running inside `CAM_Think`, and `traceFlags == (PM_STUDIO_BOX | PM_STUDIO_IGNORE)`. In that case it:

1. runs `EV_SetUpPlayerPrediction(1, 1)` and `EV_PushPMStates()` on the original API
2. picks the spectated player — the local player, or `GetEntityByIndex(*g_iUser2)` while `g_iUser1 && g_iUser2 && *g_iUser1` — and calls `EV_SetSolidPlayers` with its index (or `-1` when it is not a player)
3. scans the physent list for the entry whose `info` equals that player's index and passes it as `ignore_pe`, so the trace ignores the spectated player
4. re-traces with hull 2, the same flags and that `ignore_pe`, then `EV_PopPMStates()`, and finally raises `g_bIsCallingCAM_Think_Post`

The scan bound is `EngineGetMaxPhysEnts()`: `MAX_PHYSENTS_10152` (1024) on SvEngine with buildnum ≥ 10152, otherwise `MAX_PHYSENTS` (600) — both from the SDK's `pm_defs.h`.

`EV_SetUpPlayerPrediction_Proxy` and `EV_SetSolidPlayers_Proxy` suppress the engine's own follow-up `EV_SetUpPlayerPrediction(1, 1)` / `EV_SetSolidPlayers(-1)` calls once the post flag is set, so the engine cannot undo the setup the proxy just applied.

`HUD_Init` also binds `cl_chasedist`: it first asks `pfnGetCvarPointer("cl_chasedist")` and only registers the cvar with default `128` and `FCVAR_CLIENTDLL | FCVAR_ARCHIVE` when the engine does not already own it.

`HUD_Shutdown` calls `Client_UninstallHooks()` before the original `gExportfuncs.HUD_Shutdown()`.

### 5. Math helpers (`src/mathlib2.cpp`)

A trimmed copy of the GoldSrc / Source math library (vectors, angles, matrices, plane side tests). The camera path uses `AngleVectors`, `VectorDistance`, `VectorCopy` / `VectorAdd` and the `VEC_VIEW` offset. It is compiled as part of the plugin, not linked from the SDK.

## Key Code Flow

```
Engine client frame
    ↓
CAM_Think (taken over) → g_bIsCallingCAM_Think = true → original CAM_Think
    ↓
Engine chase code → client gEngfuncs.pEventAPI → EV_PlayerTrace_Proxy
    ↓
Inside CAM_Think and flags == PM_STUDIO_BOX|PM_STUDIO_IGNORE?
    ├── no  → original EV_PlayerTrace
    └── yes → push PM states, pick spectated player, find its physent, hull 2,
              trace with that ignore_pe, pop PM states, raise the post flag
    ↓
V_CalcNormalRefdef (inline hook)
    ↓
pparams->spectator || *g_iUser1 ?
    ├── no  → original V_CalcNormalRefdef
    └── yes → V_CalcSpectatorRefdef → V_GetChasePos → V_GetChaseOrigin
              → write viewangles / vieworg back, mirror into *g_vVecViewangles
```

## Build Instructions

Requirements: Windows, Visual Studio 2022, CMake 3.21 or newer, Python 3.8 or newer, MSVC x86 (`-A Win32`), static CRT (`MultiThreaded`), `_MBCS` and VC-LTL 5.3.1. No `CMAKE_CXX_STANDARD` is set, so the MSVC default language level applies.

```bat
scripts\build-SCCameraFix-x86-Release.bat
scripts\build-SCCameraFix-x86-Debug.bat
```

The scripts configure, build and install. Debug compiles at `/W0`; Release compiles at `/W3`; both suppress `/wd4311 /wd4312 /wd4819 /wd4996` and pass `/permissive`. Release also enables interprocedural optimization and `/OPT:REF /OPT:ICF`; the DLL links with `/SUBSYSTEM:WINDOWS`. Output stays in `build/x86/<configuration>/`; the DLL, its PDB and the gamedata catalog are installed to `install/x86/<configuration>/svencoop/metahook/`. Nothing is deployed to the game automatically.

### Dependencies

- **MetaHook SDK**: fetched automatically from the latest `main`; pass `-DMETAHOOK_SOURCE_PATH=D:\MetaHook` or export the same environment variable to build against a local tree. The path is the repository root providing `include/metahook.h`, `include/HLSDK` and `include/Interface`
- **VC-LTL 5.3.1**: downloaded once into `thirdparty/cache`
- **Nothing else.** No Capstone headers, no SourceSDK units, and no third-party library is linked — the MetaHook SDK tree is the only dependency besides VC-LTL

Keep `cmake/Sources.cmake` as the explicit compile list (4 plugin units); `include/HLSDK/common/interface.cpp` is compiled in because `EXPOSE_SINGLE_INTERFACE` (which exports `CreateInterface`) lives there.

### gamedata

`scripts/manifests/sccamerafix.json` declares six records in the `client` module — `V_CalcNormalRefdef` as a `function`, and `gEngfuncs`, `g_iUser1`, `g_iUser2`, `g_vVecViewangles`, `v_origin` as `global`s — for the supported Sven Co-op builds. There are no `numberedPatchSets`.

`scripts/manifests/sccamerafix.json` → `scripts/sync-gamedata.py` → pruned catalog under `build/x86/<Configuration>/assets/svencoop/metahook/gamedata/sccamerafix`, validated by `scripts/validate-gamedata.py` before the plugin target builds (`SCCameraFixGameData` → `SCCameraFixGameDataValidate` → `SCCameraFix`). Disable with `-DSCCAMERAFIX_SYNC_GAMEDATA=OFF`. When gamedata usage changes, update the manifest in the same change.

### Optional F5 debugging

```powershell
cmake -S . -B build/launch -G "Visual Studio 17 2022" -A Win32 -DMETAHOOKSV_ENABLE_LAUNCH_GAME=ON
```

Select **LaunchGame** and press F5; **DeployGame** builds, stages and copies the plugin DLL/PDB/resources into an existing MetaHook installation before the debugger attaches. The feature defaults OFF. See `README.md` for `METAHOOKSV_GAME_*` options.

## Engine Compatibility

Sven Co-op only. The gamedata catalog covers two client builds, and `Client_FillAddress` additionally requires the `SCClientDLL001` client factory:

| Game build | Support |
| --- | --- |
| `svencoop-8948` | ✅ |
| `svencoop-10257` | ✅ |
| Any other engine (including other GoldSrc mods) | ❌ fatal, never a silent no-op |

Catalog coverage is not a correctness statement: a listed build only means the records exist, not that this standalone build was verified in-game.

## Important Constants, Macros and Types

```cpp
static_assert(METAHOOK_API_VERSION >= 109, ...);  // ResolveGameSymbol requires MetaHook API 109
#define MHPluginName "SCCameraFix"
#define Sys_Error(msg, ...) g_pMetaHookAPI->SysError("[" MHPluginName "] " msg, __VA_ARGS__);

// src/exportfuncs.h — observer modes written by the engine into *g_iUser1
OBS_SVEN_NONE        0
OBS_SVEN_CHASE_FREE  1
OBS_SVEN_ROAMING     2
OBS_SVEN_CHASE_LOCKED 3

// src/exportfuncs.cpp
const vec3_t VEC_VIEW = { 0, 0, 28 };   // eye offset above the target origin
static bool g_bIsCallingCAM_Think;      // set only around the original CAM_Think
static bool g_bIsCallingCAM_Think_Post; // raised after the proxied trace

// Client cvar
cl_chasedist   default 128, FCVAR_CLIENTDLL | FCVAR_ARCHIVE (only registered when absent)

// SDK pm_defs.h — physent scan bound
MAX_PHYSENTS = 600, MAX_PHYSENTS_10152 = 1024 (Sven Co-op 5.16)
```

Runtime configuration: `SCCameraFix.dll` must be listed in the host's `metahook/configs/plugins.lst`, and `metahook/gamedata/sccamerafix` must stay next to it.

## Debugging Tips

1. **Console output**: the only diagnostics are `Sys_Error` — a missing gamedata symbol (symbol, module, status, buildnum) or the "This plugin is for Sven Co-op!" client-factory gate
2. **Breakpoint locations**: `Client_FillAddress()` (symbol resolution), `HUD_Init()` (proxy installation), `CAM_Think()` (the proxy's active window), `EV_PlayerTrace_Proxy()` (the ignore-physent scan), `V_CalcSpectatorRefdef()` / `V_GetChaseOrigin()` (the camera math)
3. **The proxy only acts inside `CAM_Think` with `PM_STUDIO_BOX | PM_STUDIO_IGNORE`.** A breakpoint in `EV_PlayerTrace_Proxy` will hit for every trace in the game; check `g_bIsCallingCAM_Think` before concluding anything
4. **`EV_PlayerTrace_Proxy` scans the physent list** — a breakpoint in its loop is the quickest way to see which index is chosen as `ignore_pe`

## Repository Rules

- Preserve the MetaHook API, plugin exports, calling conventions and camera behavior. Match the naming, indentation and comment style of the files you touch
- Client symbols come only from gamedata and the host gamedata contract. **Do not** reintroduce signature search or the old disassembly locators described in the source comments (the `CL_IsThirdPerson` operand scan and the `mov eax,[gEngfuncs]; mov eax,[eax+EventAPI]` sequence); the catalog publishes those globals directly. The `Search_Pattern*` macros left in `src/plugins.h` are legacy helpers, not a supported path
- Keep the `static_assert(METAHOOK_API_VERSION >= 109)` guard in sync with the APIs actually used
- Keep the Sven Co-op client-factory gate; the plugin is not portable to other GoldSrc mods
- Do not modify external or third-party sources; the MetaHook SDK is a read-only build input
- MSVC x86 only. Keep the static CRT / VC-LTL and warning-level settings in `CMakeLists.txt` in sync with the other standalone plugin repositories
- When gamedata usage changes, update `scripts/manifests/sccamerafix.json` in the same change. `README.md` is English-only; there is no Chinese README and no `docs/` directory

## Related Links

- **MetaHookSV**: https://github.com/hzqst/MetaHookSv
- **Gamedata symbol catalog**: https://hlnd2t.github.io/GoldSrc_VibeSignatures/
- **Sven Co-op**: https://www.svencoop.com/
