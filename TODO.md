# mkxp-z Switch port — TODO

Tracked bugs and improvements, newest first. Add findings here instead of
burying them in chat.

---

## Open bugs

### 1. Game picker is silently bypassed by a `Game.ini` in the `Games/` root
**Reported:** 2026-10-27 — `Project1` stub auto-launched and exited instantly; user
saw what looked like a crash.
**Where:** `switch/switch_gamepicker.cpp:185-200`
**Status:** **fixed 2026-10-27 (round 5)** — `switch_pick_game()` now scans the
subfolders first and only takes the root-`Game.ini` shortcut when there are
**no** subfolder games. With one game subfolder it launches that game; with
several it shows the UI. The stub stays untouched in `Games/` and is no longer
reachable while `Games/FireAsh/` exists.
**Remaining:** `recordPlayed()` is still only called on the UI/console pick
paths, so auto-launched games never enter `play_history.txt`.
**Also:** the picker bypassed the UI entirely (no way to choose) whenever
`Games/Game.ini` existed — that was the "instant exit looks like a crash"
experience.

### 2. Fatal crash in the shutdown path, right after the RGSS thread finishes
**Reported:** 2026-10-27 — Switch fatal error screen `2168-0002 (0x4A8)` on every
launch that reaches teardown.
**Status:** **root cause found and fixed 2026-10-27 (round 5)**.
**Root cause:** devkitA64 miscompiles `thread_local` when a translation unit is
built with **`-fPIC` + `-mtp=soft`**: it emits `lsl tp, #1` instead of
`tp + offset` for TLS accesses. FluidSynth's `fluid_sys_cpp11.cpp` keeps a
`static thread_local std::map` (`private_data`), and `delete_fluid_synth()` calls
`fluid_private_free()` → `private_data.erase()` → `ldrb [2*tp + 48]` → data
abort at `0x8ca6a00010`.
**Proof:** boot log stopped at `SharedMidiState::dtor: begin (inited=1)`;
creport PC `mkxp-z+0x65e0f4` = `fluid_private_free`, LR `+0x63fb98` =
`delete_fluid_synth`, caller chain `SharedStatePrivate::~SharedStatePrivate` ←
`SharedState::finiInstance` ← `rgssThreadFun`. Raw disassembly:
`bl __aarch64_read_tp; lsl x2, x0, #1; ldrb w0, [x2, #48]`. Recompiling the same
TU with `-fPIE` emits `bl __aarch64_read_tp; add x2, x0, #0` — correct.
**Fix:** `switch/buildScripts/configure_mkxpz.sh` now builds FluidSynth with
`-fPIE` (`FLUID_CFLAGS`/`FLUID_CXXFLAGS`), and the shipped
`libs/fluidsynth-switch/lib/libfluidsynth.a` was rebuilt with the corrected
object. mkxp-z itself already uses `-fPIE`.
**UX (still open):** detect ~0 frames / <2 s runtime and show a visible
explanation instead of dropping the user on a fatal screen.
**Note:** the instant exit itself is a data problem (incomplete stub project,
see #3/#4), not an engine fault.
**Verified 2026-10-28:** Ryujinx Canary 1.3.351 (portable, no keys/firmware).
Both a `TeardownTest` custom script and Fire Ash complete
`SharedState::finiInstance`, `SharedMidiState::dtor: end` and
`mkxp-z: leaving main()` without a data abort. Fire Ash was taken past the
title screen through New Game into the bedroom (movement works) and then quit
with the in-game pause-menu `Quit Game` → confirmation, which produced the same
clean teardown. Hardware re-test still pending.
Round 6 re-ran the teardown and New Game paths on the fixed-pixman build with
the same clean result.
See `DEPLOY_LOG.md` rounds 5–6 and `switch/notes/round5-emulator/`,
`switch/notes/round6-pixman/`.

### 3. No validation of game folder completeness
**Where:** `switch/switch_gamepicker.cpp` (scan) / `src/main.cpp` (pre-launch)
**Behaviour:** an incomplete project (e.g. missing `Graphics/`, `Data/`,
or the `Scripts=` file named in `Game.ini`) launches anyway and fails
unclearly.
**Fix:** before launch, check `Game.ini`, the `Scripts=` path, `Data/`, and
`Graphics/`; show a picker/console warning listing what is missing. Do not
refuse to launch — warn and let the user proceed.

### 4. Diagnostic gaps around game startup
- `Scripts.rxdata` script count and load/execute duration are not logged.
- `play_history.txt` is not written for auto-launched games (see #1).
- Boot log currently stops at "RGSS thread started"; add an RGSS-side mark
  when `SharedState::initInstance` completes and when `execute()` returns.
- **Ruby stdout is block-buffered when redirected to `mkxpz_log.txt`.** The
  stock RMXP `Main` script catches `Errno::ENOENT` and does
  `print("Unable to find file ...")`; that message is lost when the process
  aborts before Ruby flushes stdout. This is why the Project1 stub appears to
  exit with no explanation. Verified: the SD `Scripts.rxdata` is a valid
  stock RGSS1 project (91 scripts, 552,182 bytes of code, includes `Main`),
  and the folder has no `Graphics/` — so `Scene_Title` must hit
  `Errno::ENOENT` on the title graphic.
  **Fix:** add `$stdout.sync = true; $stderr.sync = true` to a preload script
  (e.g. `switch/romfs-root/preload/loading_screen.rb`) and/or log the exit
  path in `runRMXPScripts()`.

### 5. MIDI BGM is silent — no SoundFont is bundled
**Where:** `mkxp.json` (`midiSoundFont` empty) / `config.cpp` `midi.soundFont`.
**Evidence:** Fire Ash's `Audio/BGM` contains **27 `.mid` files** (the other
913 files are `.ogg`, 1.29 GB). The round-4/5 boot logs print
`Warning: No soundfont specified, sound might be mute` twice from
`SharedMidiState::addSynth()`.
**Fix:** ship a compact General MIDI SoundFont in RomFS (e.g. `TimGM6mb.sf2`,
~6 MB) and point `midiSoundFont` at it via the default config, or add it to the
game picker's per-game config. Also verify FluidSynth tuning-iterator TLS is
fine after the `-fPIE` rebuild (bug #2).
**Update 2026-10-28:** Fire Ash already ships `soundfont.sf2` and sets
`"midiSoundFont": "soundfont.sf2"` in its own `mkxp.json`; the emulator log now
shows `SharedMidiState::ctor: soundFont='soundfont.sf2'` and no "No soundfont"
warning. This is covered for Fire Ash. Keep the item open only as a
default-config improvement for games that do not ship a SoundFont.

### 6. Ruby timer warning on Switch (investigate)
**Observed:** every launch prints
`<main>: warning: pipe creation failed for timer: Function not implemented,
scheduling broken` because libnx has no `pipe()`.
**2026-10-28 emulator check:** main-thread `sleep 3` took 3.16 s; a background
thread's `sleep` wrote its marker; `Thread.main.raise(SystemExit)` exited the
game cleanly. So it is not blocking the basics, but thread scheduling for
timers is not fully healthy.
**If hardware shows stuck timers/animations:** add a `pipe()` fallback (or a
timer-thread patch) to the Ruby 3.2 Switch build and retest.

### 7. pixman had the same soft-TLS miscompile (latent), fixed in round 6
**Found:** 2026-10-28 — after the FluidSynth fix, a static audit of the linked
ELF found 11 `bl __aarch64_read_tp; lsl xN, x0, #1` sites inside
`_pixman_implementation_lookup_composite`, from devkitPro's prebuilt
`libpixman-1.a` 0.42.2.
**Impact:** mkxp-z only calls pixman region functions today, so this path had
not executed, but the broken code was linked into every NRO and would
data-abort if composite/fill paths were used.
**Status:** **fixed 2026-10-28 (round 6)** — pixman 0.42.2 rebuilt from source
with `-fPIE`, archive at `libs/pixman-switch/lib/libpixman-1.a`
(SHA-256 `ffe4764b…275b3f`), linked by `src/meson.build`; the configure script
rebuilds it and the build script checks for it. New ELF audit: 4,292
thread-pointer calls, 0 bad `lsl` sites.
**Guard:** `switch/buildScripts/find_bad_tls.py <objdump -d output>` checks for
this pattern. Run it on any new static library and on the final ELF before
deploying.
See `DEPLOY_LOG.md` round 6 and `switch/notes/round6-pixman/`.

---

## Nice-to-have

- Picker "No games found" message is console-only (text mode); render it in
  the home-screen style UI instead so it is visible for more than a flash.
- Add an on-screen "Loading <title>…" fallback when `loading_screen.rb` hits
  `StandardError` (currently only `System.puts`).
- Picker: allow launching a game placed directly in `Games/` while other
  games exist in subfolders (see #1).

---

## Fixed already (for reference)

- ✅ Socket init crash (`2168-0002 0x4A8`) — `socketInitializeDefault()` disabled;
  diagnostics via `sdmc:/mkxpz_boot.log` (2026-10-27).
- ✅ pixman soft-TLS miscompile — rebuilt 0.42.2 with `-fPIE`; linked ELF now has
  zero bad thread-pointer accesses (2026-10-28, round 6).
- ✅ Partial FireAsh copy caused the "Loading Fire Ash" hang (missing
  `Data/*.rxdata`); full replacement complete (2026-10-28, round 7).

## Remaining
- **Hardware launch + teardown test**: Switch is in USB mode; SD FireAsh is
  complete and the NRO (`88ceb6de…89f1`) is on the card. Final on-device
  check is still needed: launch from hbmenu → splash → title → New Game →
  movement → pause-menu Quit, then confirm
  `main: after switch_return_to_picker` with no `2168-0002` fatal screen.
- ✅ Silent logging failure — `setup_file_logging()` now falls back
  `sdmc:/mkxpz_log.txt` → `sdmc:/switch/mkxpz_log.txt` → boot log, and reports
  `errno` (2026-10-27).
- ✅ Duplicate hbmenu entry — stale `switch/mkxp-z/mkxp-z.nro` renamed to
  `mkxp-z.nro.disabled` (2026-10-27).
