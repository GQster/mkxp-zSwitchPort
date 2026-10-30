# Switch build & deploy log

**Status: EMULATOR-VERIFIED (pixman TLS audit clean, clean teardown + Fire Ash New Game); hardware launch pending (SD copy complete, Switch in USB mode) — 2026-10-28 build `88ceb6de…89f1`**

Latest update at the top; earlier entries below.

---

## 2026-10-28 (round 6) — latent pixman TLS miscompile found and fixed

### Discovery: a second copy of the same devkitA64 bug

After the FluidSynth fix, the linked ELF was audited for the broken TLS pattern
(`bl __aarch64_read_tp` followed by `lsl xN, x0, #1` instead of an `add` with the
TLS offset). The audit found **11 sites in
`_pixman_implementation_lookup_composite`**, all coming from devkitPro's prebuilt
`libpixman-1.a` 0.42.2. It is the same `-fPIC` + `-mtp=soft` miscompile as the
FluidSynth shutdown crash.

mkxp-z currently calls only pixman's region functions (`pixman_region_*` in
`src/display/bitmap.cpp`), so the broken composite path had not run yet, but the
bad code was linked into the NRO and would abort if that path were reached.

The checker is `switch/buildScripts/find_bad_tls.py` (takes an `objdump -d`
listing); run it on every new static library and on the final ELF.

### Fix

- pixman 0.42.2 rebuilt from the official tarball
  (`sha256 ea1480efada2fd948bc75366f7c349e1c96d3297d09a3fe62626e38e234a625e`)
  with `-fPIE`: a meson cross file from
  `/opt/devkitpro/meson-toolchain.sh switch` with `-fPIC` replaced by `-fPIE`;
  options `-Dtests=disabled -Dgtk=disabled -Dopenmp=disabled
  -Dlibpng=disabled`.
- `libs/pixman-switch/lib/libpixman-1.a` — 982,532 bytes, SHA-256
  `ffe4764bfca49423405930a6d550fcc731a905eeb36e25751e079b2ed0275b3f`.
- `src/meson.build` links the local archive instead of `-lpixman-1`;
  `configure_mkxpz.sh` builds it and `build_mkxpz_switch.sh` checks it exists.
- Rebuilt ELF audit: **4,292** `__aarch64_read_tp` calls,
  **0** functions with a bad `lsl` after the thread-pointer read.

### Emulator verification (Ryujinx Canary 1.3.351, portable)

- Pokémon Essentials splash → title screen rendered.
- Title menu → `Quit Game` → full teardown: boot log ends
  `main: after switch_return_to_picker`; game log runs through
  `SharedMidiState::dtor: end` and ends `mkxp-z: leaving main()`. No abort.
- New Game → splash/intro → controls help → name entry → starting bedroom;
  player movement works.

Evidence is in `switch/notes/round6-pixman/`:
`build.log`, `configure.log`, `pixman-splash.png`,
`pixman-title-press-enter.png`, `pixman-title-menu.png`,
`pixman-quit-selected.png`, `pixman-titlequit-boot.log`,
`pixman-titlequit-mkxpz.log`, `pixman-name-entry.png`, `pixman-bedroom.png`,
`pixman-moved.png`, `tls-audit.txt`.

### Artifact

| Artifact | Size | SHA-256 |
|---|---|---|
| `build-switch/mkxp-z.nro` | 22,263,476 bytes | `88ceb6de2ac7ea2554c37224b545fda5398f3e010749a464a9f709b3c45189f1` |

Deploy target: `switch/mkxp-z.nro` only; Fire Ash lives at
`switch/mkxp-z/Games/FireAsh/`. The stub under `Games/` is untouched.

---

## 2026-10-28 (round 7) — SD copy complete; hardware launch deferred (USB mode)

- `build-switch/mkxp-z.nro` (hash `88ceb6de…89f1`) deployed to
  `switch/mkxp-z.nro` on the SD and verified by pull-back hash.
- `Games/FireAsh/` copied in full (16,259 files, ~1.393 GiB) after an earlier
  interrupted transfer left `Data/PkmnAnimations.rxdata` (and possibly others)
  missing — that was the cause of the "Loading Fire Ash" hang observed before
  the full copy (boot log stopped at `main: RGSS thread started`, game log at
  `scriptBinding->execute()`). Game files were **not** modified by tooling.
- The Switch is currently in **USB mode** (SD inside the console, no USB/SD
  mount), so the final launch/teardown test could not be run from this session.
  The pending hardware step remains: launch from hbmenu → splash → title →
  New Game → movement → pause-menu Quit, then confirm
  `main: after switch_return_to_picker` with no fatal screen.

---

## 2026-10-28 (round 5)

### Root cause of `2168-0002 (0x4a8)`

The abort was **not** in mkxp-z itself. devkitA64 miscompiles `thread_local`
access when a translation unit is built with **`-fPIC` + `-mtp=soft`**: it emits
`lsl tp, #1` instead of `tp + offset`. FluidSynth's `fluid_sys_cpp11.cpp` keeps
a `static thread_local std::map` (`private_data`); `delete_fluid_synth()` calls
`fluid_private_free()`, which does a TLS-relative `ldrb` through that bad
pointer and data-aborts.

Proof chain:

- Boot log stopped at `SharedMidiState::dtor: begin (inited=1)`.
- Fresh creport `01744241645_010000000000100d.log`:
  PC `mkxp-z+0x65e0f4` = `fluid_private_free`;
  LR `+0x63fb98` = `delete_fluid_synth`;
  caller `~SharedStatePrivate` ← `SharedState::finiInstance` ← `rgssThreadFun`.
- Raw disassembly: `bl __aarch64_read_tp; lsl x2, x0, #1; ldrb w0, [x2,#48]`.
  The same TU rebuilt with `-fPIE` emits `bl __aarch64_read_tp; add x2, x0, #0`.

### Fix

- `switch/buildScripts/configure_mkxpz.sh` now passes `-fPIE` in
  `FLUID_CFLAGS` / `FLUID_CXXFLAGS` for FluidSynth.
- The shipped `libs/fluidsynth-switch/lib/libfluidsynth.a` was rebuilt with the
  corrected `fluid_sys_cpp11.cpp.obj`; relocations now use
  `R_AARCH64_TLSLE_ADD_TPREL_*`. The linked NRO's `fluid_private_free` also
  uses the correct `add x2, x0, #0, lsl #12; add x2, x2, #0x4e0`.
- Picker fix from `TODO.md` #1 is in the same build: subfolders are scanned
  first, and the root-`Game.ini` shortcut is used only when no game subfolders
  exist.

### Emulator verification (Ryujinx Canary 1.3.351, portable)

Ryujinx runs homebrew NROs without `prod.keys` or firmware. Test setup:
`C:\Users\grant\AppData\Local\Temp\opencode\ryujinx` (portable), emulated SD at
`portable\sdcard`, NRO at `switch/mkxp-z.nro`, `debug.txt` present.

1. **Teardown regression** (`Games/TeardownTest`, customScript
   `Graphics.update; sleep 1; exit`):
   boot log reaches `main: after switch_return_to_picker`; `mkxpz_log.txt` reaches
   `SharedMidiState::dtor: end` and `mkxp-z: leaving main()`. No data abort, so
   the `fluid_private_free` crash is gone.
2. **Fire Ash 3.6 Part 1.2** copied to `Games/FireAsh`
   (16,259 files, 1,495,639,668 bytes; source at
   `C:\Users\grant\Downloads\FireAsh\...\Game`):
   - picker auto-selected the only subfolder and launched it;
   - path cache built, Ruby VM started, scripts ran;
   - Pokémon Essentials splash rendered;
   - **title screen reached**: `Load Game / New Game / Options / Quit Game`;
   - `SharedMidiState::ctor: soundFont='soundfont.sf2'` (Fire Ash ships its own
     SoundFont, so the earlier no-soundfont warning is gone).
3. **New Game to actual gameplay**: with the emulator D-pad temporarily
   remapped to unused letter keys (Ryujinx swallows the arrow keys; real Switch
   controls are unaffected), the title screen led through the splash/intro,
   controls-help screen, name entry (`Ryujinx`), and intro dialogue into the
   starting bedroom. Player movement with the D-pad works.
4. **Clean exit from the real game**: pause menu → `Quit Game` → confirmation.
   The boot log ends with `main: after switch_return_to_picker`; the game log
   runs through `SharedMidiState::dtor: end` and ends with
   `mkxp-z: leaving main()`. No fatal screen and no data abort.
5. **Ruby timing sanity**: `sleep 3` returned in 3.16 s; a background thread's
   `sleep` wrote its marker; `Thread.main.raise(SystemExit)` exited the game.
   (The `<main>: warning: pipe creation failed for timer ... scheduling broken`
   message still appears, but these paths work. Keep an eye on hardware.)

Evidence is saved in `switch/notes/round5-emulator/`:
`teardown-boot.log`, `teardown-mkxpz.log`, `fireash-boot.log`,
`fireash-mkxpz.log`, `fireash-splash.png`, `fireash-title.png`,
`fireash-newgame-menu.png`, `fireash-intro.png`, `fireash-controls-menu.png`,
`fireash-name-entry.png`, `fireash-ready.png`, `fireash-bedroom.png`,
`fireash-moved.png`, `fireash-quit-menu.png`, `fireash-quit-confirm.png`,
`fireash-newgame-boot.log`, `fireash-newgame-mkxpz.log`.

Note: Ryujinx headless keeps its own process alive after the guest NRO exits;
the guest boot/log files prove mkxp-z itself completed teardown. This is an
emulator-side quirk, not an mkxp-z hang.

### Artifact

| Artifact | Size | SHA-256 |
|---|---|---|
| `build-switch/mkxp-z.nro` | 22,546,100 bytes | `4996ae6763d77db714f5af37a692748980b7d0e3c6ef96e73be76e17c1b33312` |

Deploy target remains `switch/mkxp-z.nro` **only**. Do not overwrite
`switch/mkxp-z/mkxp-z.nro.disabled` (the old duplicate) or the stub in
`switch/mkxp-z/Games/`.

### Remaining hardware step

When the Switch and its MTP homebrew are connected:

1. Deploy `build-switch/mkxp-z.nro` to `switch/mkxp-z.nro`; verify the hash.
2. Copy Fire Ash to `switch/mkxp-z/Games/FireAsh/` (keep the existing stub
   `Games/*` files untouched). Check free space first (needs ~1.43 GiB).
3. Launch from hbmenu; confirm the Pokémon Essentials splash → title screen,
   then start New Game and verify movement in the bedroom.
4. Quit from the pause menu; the boot log should end with
   `main: after switch_return_to_picker` and `mkxpz_log.txt` with
   `mkxp-z: leaving main()`, with no fatal screen.

---

## 2026-10-27 (round 4) — shutdown-path instrumentation (crash is in teardown)

### Confirmed crash window

User confirms the fatal screen is **`2168-0002 (0x4a8)`** and the app does
**not** return to hbmenu — so this is a real abort, not a clean exit.

Log tail of the round-3 build:

```
`RubyGems' were not loaded.
...
EventThread termination requested
RGSS thread ack'd request after 0 ms
```

`mriBindingExecute()` runs the RMXP scripts and then `ruby_cleanup(0)` on the
RGSS thread (`binding/binding-mri.cpp:1344`), so Ruby teardown already
completed before `rqTermAck` was set. `EventThread termination requested`
proves `scriptBinding->execute()` returned. The main thread then blocks in
`SDL_WaitThread(rgssThread)` (`src/main.cpp:625`), waiting for the RGSS
thread's `SharedState::finiInstance()` + `alcDestroyContext()`. Nothing after
that point is logged → **abort is inside the RGSS-thread teardown**, while
the main thread waits.

### What this build instruments (uncommitted)

- `src/main.cpp`
  - `BOOT_MARK()` after `rqTerm.set`, at the ack decision, and after
    `SDL_WaitThread`.
  - Marks around `SDL_GL_DeleteContext`, `eventThread.cleanup()`,
    `alcCloseDevice`, `SDL_DestroyWindow`, `Sound_Quit`, `TTF_Quit`,
    `IMG_Quit`, `SDL_Quit`, `switch_return_to_picker`.
  - RGSS thread: marks after `execute()` returns, before/after
    `SharedState::finiInstance()`, before/after `alcDestroyContext()`, on
    thread return.
  - `BOOT_MARK` macro moved above `rgssThreadFun()` so the RGSS thread can use
    it.
- `src/sharedstate.cpp` — `SWITCH_TRACE` around each of the three deletes in
  `finiInstance()` (`defaultFont`, `SharedState::instance`, `_globalIBO`).
- `binding/binding-mri.cpp` — `SWITCH_TRACE` around `ruby_cleanup(0)`.

### Debug tracing

`SWITCH_TRACE` output (hundreds of detailed lines through SDL/Ruby/GL init)
is enabled by creating `sdmc:/switch/mkxp-z/debug.txt`. This build is meant
to run **with** that file present, otherwise only the `BOOT_MARK`s appear.

### Build (final, includes member-destructor traces)

| Artifact | Size | SHA-256 |
|---|---|---|
| `build-switch/mkxp-z.nro` | 22,546,100 bytes | `842f0e8a0cc3960f3681e0fbd89a0fe3e25e01758b196eb8d1e64f792a931186` |

Built in `switch-dev` (52 s). Not yet deployed — the Switch dropped off MTP
after the fatal screen. Deploy target remains `switch/mkxp-z.nro` only.

Additional traces beyond the first pass (same build, second compile):
`~SharedStatePrivate` (three GL deletes), `~GraphicsPrivate` end,
`~AudioPrivate` (incl. the nested `SDL_WaitThread` for the MIDI watch
thread), `~SharedFontState`, `~TexPool`, `~FileSystem`, `~SharedMidiState`.
These give the exact member destructor reached before the abort.

`2168-0002` is confirmed by Atmosphère's author as a **userland data abort**
(invalid memory access), not a clean exit. libnx in the build image is
**4.12.0**, so the firmware-21 TLS/ABI issue does not apply.

### Why the game exits instantly (evidence, not a guess)

The SD `Data/Scripts.rxdata` was pulled and decoded with a correct Ruby
Marshal reader (the first parser failed on Marshal's compressed-integer
encoding): it is a **valid stock RPG Maker XP Project1 script set** — 91
scripts, 552,182 bytes of code, ending in the stock `Main` script. `Main`
rescues `Errno::ENOENT`, calls `print("Unable to find file ...")`, then
returns. The folder has **no `Graphics/`**, so `Scene_Title` must fail on the
title graphic. Ruby's stdout is block-buffered when redirected to the log, so
that message is lost when the process aborts — the instant exit is explained,
and it is a data problem (incomplete stub project), not an engine fault.

### Next step

1. Reopen the MTP homebrew so the Switch is visible again.
2. Deploy this NRO + `switch/mkxp-z/debug.txt`.
3. Launch, pick the game, wait for the fatal screen.
4. Pull `mkxpz_boot.log` / `mkxpz_log.txt`; the last mark names the aborting
   teardown call (boot log covers `finiInstance`/`alcDestroyContext`, game log
   covers the finer `SWITCH_TRACE` lines).
5. Also pull `atmosphere/crash_reports/*` if a fresh report exists; addr2line
   its PC against `build-switch/mkxp-z`.

---

## 2026-10-27 (round 3) — no crash: there is no Pokémon game on the card

### What the instrumented launch showed

Full boot log — every mark passed:

```
userAppInit: start ... main: after alcOpenDevice
main: before initGL ... main: after initGL
main: before RGSS thread ... main: RGSS thread started
main: eventThread.process returned
```

`mkxpz_log.txt` (live this time): GLES context created (Mesa nouveau,
Tegra X1 / NV120), path cache built, audio up, Ruby VM up, then:

```
EventThread termination requested
RGSS thread ack'd request after 0 ms
```

`scriptBinding->execute()` returned and the RGSS thread requested termination
(`main.cpp:184-185`), **then the process died with a fatal error screen**
(confirmed by the user; not a clean return to hbmenu). The log stops before
`Debug() << "Shutting down."`, so the abort is in the teardown path
(`SDL_WaitThread`/RGSS-thread finalisation or `SDL_GL_DeleteContext`).
Awaiting the fresh creport (`atmosphere/crash_reports`) to addr2line the
exact frame — see `TODO.md` bug #2.

### Why: the only game on the SD is a stub test project

`switch/mkxp-z/Games/` contains a single project directly in the root:

```
Game.exe  69,632 bytes
Game.ini  104 bytes   -> Title=Project1, Scripts=Data/Scripts.rxdata
Data/     ~40 maps + Scripts.rxdata (111 KB)
Audio/
```

- `Title=Project1` — the default RPG Maker XP project name.
- **No `Graphics/` folder at all** — a complete RMXP game cannot run without
  it, so this is not a real game install.
- Because `Game.ini` sits directly in `Games/`, the picker takes the
  "single game" shortcut and never shows its UI.
- An incomplete/stub project like this can reach the end of
  `scriptBinding->execute()` immediately, which is exactly what the logs
  show.

### Fire Ash is not on this PC or SD

- SD root `games/` — empty.
- `switch/mkxp-z/Games/` — only the Project1 stub above.
- Searched `C:\Users\grant` (Downloads/Desktop/Documents/OneDrive) and WSL
  home for `Game.exe`, `*.rxproj`, `Fire Ash`/`Pokemon` folders: only
  `Downloads\pokemonEdits` (mGBA emulator states/ROMs, no RPG Maker game).
- No game data was ever transferred by this session — only
  `switch/mkxp-z.nro` was written.

### Next step

The picker bypass and "instant exit looks like a crash" issues are tracked in
`TODO.md` (open bugs #1–#4, reported from this session).

Get the Fire Ash game folder onto this PC, then copy it to the SD card
(`switch/mkxp-z/Games/<FireAsh>/`). Note the picker rule: while a
`Game.ini` remains directly in `Games/`, the picker auto-launches it and
never shows the game list — the Project1 stub should be moved into its own
subfolder (e.g. `Games/Project1/`) when Fire Ash is added, if the picker UI
is wanted.

---

## 2026-10-27 (round 2) — crash is AFTER the picker; instrumented build

### What the boot log proved

The socket fix worked. `sdmc:/mkxpz_boot.log` from the first fixed launch:

```
userAppInit: start
userAppInit: romfsInit ok
userAppInit: done (networking disabled)
main: before switch_pick_game
main: after switch_pick_game
main: logging enabled
```

So the app boots, the picker runs, the user picked a game, and the crash
happens in `main()` **after the picker** — inside SDL/config/Ruby/engine
startup. Not a socket problem anymore.

### Why there were no main() logs originally

`mkxpz_log.txt` on the card comes from the Switch itself — I first mistook
`GL Vendor: nouveau / NV120 / Mesa 20.1.0-rc3` for Ryujinx output, but that
is devkitPro's Mesa-nouveau GL stack on the Tegra X1 (NV120). On the first
instrumented launch `open("sdmc:/mkxpz_log.txt", O_WRONLY|O_CREAT|O_TRUNC)`
failed silently — `setup_file_logging()` only does `dup2` when the open
succeeds, and the "logging enabled" boot mark was unconditional. The new
fallback chain fixed that: the instrumented build reports
`logging: stdout -> sdmc:/mkxpz_log.txt ok` and the log is live.

### What this build changes (uncommitted)

- `switch/switch_main.cpp`
  - `setup_file_logging()` now tries, in order:
    `sdmc:/mkxpz_log.txt` → `sdmc:/switch/mkxpz_log.txt` → append to
    `sdmc:/mkxpz_boot.log`, and writes the result incl. `errno` to the
    boot log.
- `src/main.cpp`
  - 17 `BOOT_MARK()` breadcrumbs through the whole of `main()`: before/after
    `SDL_Init`, `allocUserEvents`, `Config::read`, RGSS-version print,
    `IMG_Init`, `TTF_Init`, `Sound_Init`, `SDL_CreateWindow`,
    `alcOpenDevice`, `initGL`, RGSS thread start, and after
    `eventThread.process` returns.

### Deployed

| SD-card path | Size | SHA-256 |
|---|---|---|
| `switch/mkxp-z.nro` | 22,546,100 bytes | `10aca67bc1e62849fb0cf102cc325b2afe6b215de14e4d9686a3a4a2a916380f` |

- Read-back verified, exact match.
- Previous fixed build (boot-log round) saved as
  `backup/mkxp-z.nro.socketfix` (`e5ad4a38…794bb`).
- `switch/mkxp-z/mkxp-z.nro.disabled` and `Games/` untouched.

### MTP script bug found and fixed

The "root files can't be read over MTP" theory was **wrong** — it was a
PowerShell bug in our own scripts: for single-segment paths,
`$path.Split('/') | Where-Object …` unwraps to a scalar string, so
`$parts[-1]` returned the last *character* (file named `g`, `t` instead of
`mkxpz_boot.log`). `readback_mtp.ps1`/`pull_mtp.ps1`/`move_mtp.ps1` now wrap
with `@()`. Root files are readable/writable over MTP; `mkxpz_boot.log`
was pulled successfully. Delete still unsupported; rename works.

### Next step

Launch mkxp-z, pick the game, then pull `sdmc:/mkxpz_boot.log` and
`sdmc:/mkxpz_log.txt` (fallback path may be `switch/mkxpz_log.txt`).
The last boot mark before the crash names the failing stage.

---

## 2026-10-27 — socket crash fix, rebuild, single-entry deploy

### Problem (diagnosis)

Both hbmenu entries crashed on real hardware before any log file was created:
`error code 2168-0002 (0x4A8)` = userland data abort (ARM data abort /
abnormal process exit per switchbrew). `switch/notes/notes.md` already
documented the same signature from an earlier round:

```
0x1173d0 -> libnx time.c:63
0x117268 -> libnx time.c:192
0x00ac   -> libnx runtime/devices/socket.c:948
```

The regression came back with commit `d35b00d` ("Add real networking"),
which re-enabled `socketInitializeDefault()` in `userAppInit()` at
`switch/switch_main.cpp`. Starting the BSD socket service there aborts on
the Switch before `main()` ever runs — which is why neither
`sdmc:/mkxpz_log.txt` nor the RomFS-backed logging showed anything.

### Code changes (uncommitted)

- `switch/switch_main.cpp`
  - `socketInitializeDefault()` disabled again; Ruby's socket extension
    stays linked but calls simply fail with errors instead of aborting.
  - Added raw `open`/`write`/`close` boot logging to
    `sdmc:/mkxpz_boot.log`: `userAppInit` start, `romfsInit` result, done.
    Safe before libc constructors run.
- `src/main.cpp`
  - Boot marks around the game picker (`main: before/after
    switch_pick_game`, `main: logging enabled`) via new
    `switch_boot_mark()`.

So a crash on next launch will always leave `sdmc:/mkxpz_boot.log`
showing how far boot got (before picker / in picker / after picker).

### Build

- Rebuilt with the Windows Docker CLI
  (`C:\Users\grant\AppData\Local\Programs\DockerDesktop\resources\bin\docker.exe`,
  context `desktop-linux`) against image `switch-dev`, volume `mkxp-work`,
  44 s incremental build.
- Note: Docker Desktop's WSL socket
  `/mnt/wsl/docker-desktop/shared-sockets/host-services/docker.proxy.sock`
  stopped accepting connections ("permission denied" as root too); the
  Windows `docker.exe` works. WSL `docker-desktop` distro shows Stopped.
- `switch/mkxp-z.nro.disabled` on the SD card is the exact previously
  deployed (crashing) build, preserved as a non-`.nro` backup so hbmenu
  won't list it: 22,550,196 bytes, SHA-256
  `ef5b6385df389b3191e3dac077e37b48b2b8cf17e95dc4df14886665e1d89e2b`
  (also saved locally as `backup/mkxp-z.nro.socketinit`).

### Deployed files

| SD-card path | Size | SHA-256 | State |
|---|---|---|---|
| `switch/mkxp-z.nro` | 22,546,100 bytes | `e5ad4a3814bebd1d1df8c2f165a46366bb83732b5c5dfe39bcdccb3f167974bb` | ✅ deployed, read-back verified |
| `switch/mkxp-z/mkxp-z.nro.disabled` | 22,550,196 bytes | `ef5b6385…89e2b` | old build, renamed so hbmenu shows only ONE entry |

- `switch/mkxp-z/Games/` untouched.
- hbmenu should now show exactly one "mkxp-z" entry (the verified new build).
- Read-back verified by SHA-256, exact match with the local build.

### Timeline (2026-10-27, local)

- **21:52–22:02** - Docker Desktop debugging: WSL proxy socket dead,
  found the working Windows CLI + `desktop-linux` context.
- **22:04** - Confirmed libnx 4.12 `socketInitialize`/time internals via
  container + switchbrew sources; diagnosis locked in.
- **~22:07** - New NRO built (44 s), 22,546,100 bytes, hash
  `e5ad4a38…794bb`; old deployed build backed up locally.
- **~22:10** - Switch reconnected over MTP.
- **~22:10** - Attempted to pull old `SD/mkxpz_log.txt` first; MTP server
  refused (`UNABLE_TO_MASK_PATH` on `GetFileAsync`). **Heads-up:** the new
  build truncates this file on next launch, so it's now overwritten.
- **~22:11** - Deployed `switch/mkxp-z.nro` (single destination), size
  verified during copy, `COPY_OK`.
- **~22:11** - Renamed `switch/mkxp-z/mkxp-z.nro` →
  `mkxp-z.nro.disabled` (rename works even though delete doesn't).
- **~22:12** - Read the deployed NRO back; SHA-256 matches the local
  build exactly.
- **~22:12** - Updated this log.

### What to expect on next launch

1. hbmenu: single mkxp-z entry.
2. Game picker appears; boot log at `sdmc:/mkxpz_boot.log` should show
   `userAppInit: start` → `userAppInit: romfsInit ok` →
   `userAppInit: done (networking disabled)` → `main: before
   switch_pick_game` → …
3. If it still crashes, pull `sdmc:/mkxpz_boot.log`,
   `sdmc:/mkxpz_log.txt` (or via Hekate UMS) and note where the log
   stops — that tells us whether it dies before `userAppInit`, inside
   the picker, or after `main` starts.

---

## 2026-10-26 — first deploy (both copies, later found crashing)

---

## Deployed files

Both copies on the SD card are the new build:

| SD-card path | Size | SHA-256 |
|---|---|---|
| `switch/mkxp-z.nro` | 22,550,196 bytes | `ef5b6385df389b3191e3dac077e37b48b2b8cf17e95dc4df14886665e1d89e2b` |
| `switch/mkxp-z/mkxp-z.nro` | 22,550,196 bytes | same |

The local build artifact is:

- `/home/grant/mkxp-zSwitchPort/build-switch/mkxp-z.nro`
- hash saved next to it in `build-switch/mkxp-z.nro.sha256`
- NRO header verified: `HOMEBREW` + `NRO0`

The existing `switch/mkxp-z/Games/` directory was **not touched**.

---

## What was done

1. Checked the environment:
   - WSL Ubuntu was fresh: no devkitPro, no Docker CLI, no `libs/`, no `build-switch/`.
   - Docker Desktop was running on Windows; used its shared socket from WSL as root:
     `/mnt/wsl/docker-desktop/shared-sockets/host-services/docker.proxy.sock`
   - Downloaded a static Docker CLI into WSL at `/home/grant/.local/bin/docker`.
2. Built the `switch-dev` Docker image from `switch/buildScripts/dockerfile`.
3. Seeded a persistent Docker volume `mkxp-work` with the repo.
4. Built dependencies: PhysicsFS, SDL_sound, FluidSynth.
5. Built Ruby 3.2.2 static (`libs/ruby-switch`).
6. Built mkxp-z with Meson/Ninja and packaged `mkxp-z.nro` + NACP + RomFS.
7. Backed up the old SD-card NRO to
   `/home/grant/mkxp-zSwitchPort/backup/mkxp-z.nro.old`
   (old size 18,236,084 bytes, verified while copying).
8. Copied the new NRO to both SD-card paths using the Switch's MTP interface.
9. Read both copies back from the SD card and compared SHA-256 with the local build.
   Both matched exactly.

---

## Timeline

All times local (America/Chicago, UTC-5), 2026-10-26.

- **18:55** - Started environment investigation.
- **19:02:23** - Full build started in the background.
- **19:02:24** - `switch-dev` Docker image build started.
- **19:05** - Confirmed the Switch was in MTP/file-transfer mode over USB
  (`USB\VID_057E&PID_201D`, "Nintendo Switch"). SD card browsable via
  `This PC > Nintendo Switch > SD Card`.
- **19:05** - Backed up the old `switch/mkxp-z.nro` to the WSL repo.
- **19:06** - Tested MTP writes/overwrites with tiny files. Writes and
  replace-existing work; MTP delete is not supported by this homebrew.
- **19:13:50** - Docker image build finished.
- **19:13:59** - Dependency build started.
- **19:14:46** - Dependencies finished successfully.
- **19:14:46** - Ruby 3.2.2 build started.
- **19:17:35** - Ruby finished; mkxp-z build started.
- **19:18:13** - mkxp-z link + NRO packaging succeeded.
- **19:18:21** - NRO extracted back into the WSL repo. Build total: ~16 minutes.
- **~19:19** - New NRO copied to `switch/mkxp-z.nro` and
  `switch/mkxp-z/mkxp-z.nro`; both reported the expected 22,550,196 bytes.
- **~19:20** - Read both copies back and verified SHA-256:
  `ef5b6385df389b3191e3dac077e37b48b2b8cf17e95dc4df14886665e1d89e2b`.
- **~19:22** - Cleaned up temporary WSL/Windows test files and saved the build
  hash next to the NRO.

---

## How to launch

1. Exit the MTP file-transfer homebrew (or reboot the Switch) back to hbmenu.
2. Launch `mkxp-z.nro` from the SD card.
   - The top-level `switch/mkxp-z.nro` is the one hbmenu shows directly.
   - The copy at `switch/mkxp-z/mkxp-z.nro` is the path documented in
     `switch/README.md`; either copy is the same verified build.
3. Games remain in `switch/mkxp-z/Games/<Game Name>/`.

If you need to roll back, the old NRO is at:

`/home/grant/mkxp-zSwitchPort/backup/mkxp-z.nro.old`

Copy it back to `switch/mkxp-z.nro` over MTP if the new build misbehaves.

---

## Leftovers / cleanup notes

- One tiny MTP test file remains on the SD card because this MTP homebrew does
  not consistently support delete:
  - `switch/mkxp-z/mtp-test.txt` (30 bytes)
  The other test file was successfully removed. The remaining one is harmless;
  delete it from Windows Explorer when convenient.
  *(Update 2026-10-27: it is no longer listed in `switch/mkxp-z/`; treat as gone.)*
- The Docker image `switch-dev` and volume `mkxp-work` were intentionally left in
  Docker Desktop for fast future rebuilds.
- `libs/` and `build-switch/` were copied back into the WSL repo for future
  incremental builds. They are build outputs and remain untracked by git.
- No Windows system settings, drivers, or software were changed. Temporary files
  used for the MTP experiments were deleted from the approved temp directory.
- The only Windows-side action was using PowerShell/Windows shell APIs to talk to
  the Switch's MTP device, as requested.

---

## Key files

| File | Purpose |
|---|---|
| `build-switch/mkxp-z.nro` | new verified NRO |
| `build-switch/mkxp-z.nro.sha256` | SHA-256 of the new NRO |
| `backup/mkxp-z.nro.old` | previous SD-card NRO backup |
| `/home/grant/build-progress.log` | full build log |
| `/home/grant/run_full_build.sh` | repeatable full build script |
| `/home/grant/deploy_mtp.ps1` | MTP deploy script |
| `/home/grant/readback_mtp.ps1` | MTP read-back/verification script |
| `DEPLOY_LOG.md` | this file |

---

## Useful next time

- The Docker CLI installed in WSL: `/home/grant/.local/bin/docker`
- Docker host:
  `DOCKER_HOST=unix:///mnt/wsl/docker-desktop/shared-sockets/host-services/docker.proxy.sock`
- Full rebuild:
  `wsl -d Ubuntu -u root -- /bin/bash /home/grant/run_full_build.sh`
  (~16 minutes with the cached Docker image; longer if the image has to rebuild)
- Deploy (single destination — the 2026-10-27 fix; the script's default
  destinations list the second copy at `switch/mkxp-z/mkxp-z.nro`, which must
  NOT be written while the old build is parked there as `mkxp-z.nro.disabled`):
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File '\\wsl.localhost\Ubuntu\home\grant\deploy_mtp.ps1' -Source 'C:\Users\grant\AppData\Local\Temp\opencode\mkxp-out\mkxp-z.nro' -Destinations 'switch/mkxp-z.nro'`
- Rename (remove a hbmenu entry without losing the file):
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File '\\wsl.localhost\Ubuntu\home\grant\rename_mtp.ps1' -RemotePath 'switch/mkxp-z/mkxp-z.nro' -NewName 'mkxp-z.nro.disabled'`
- Pull a file (note: `GetFileAsync`/`TryGetItemAsync` on SD-card ROOT files can
  fail with `UNABLE_TO_MASK_PATH`; reading from `switch/...` works):
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File '\\wsl.localhost\Ubuntu\home\grant\pull_mtp.ps1' -RemotePath 'switch/mkxpz_log.txt' -LocalDirectory 'C:\Users\grant\AppData\Local\Temp\opencode\mkxp-sdlog'`
- Verify:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File '\\wsl.localhost\Ubuntu\home\grant\readback_mtp.ps1' -RemotePath 'switch/mkxp-z.nro' -LocalDirectory '\\wsl.localhost\Ubuntu\home\grant' -LocalName 'verify.nro'`
