Project Goal: Port mkxp-z (RPG Maker XP/VX/VX Ace engine) to Nintendo Switch to play Pokémon Essentials (specifically Fire Ash).

here are my notes:


1. What the two reference projects teach us
──────────────────────────────
A. EasyRPG-Player
• Target RPG Maker 2000/2003.
• Has an official Switch port that lives in the same mono-repo:
src/ports/switch/, cmake/toolchains/armv8-switch.cmake.
• Uses devkitPro / libnx + SDL2 + GLES2.
• Handles:
– Joy-Con → RPG Maker input mapping (key emulation).
– Automatic game discovery on SD (/switch/easyrpg-player/games).
– Packaging into a single .nro with a small romfs.
• SDL2 and tinyxml2, liblcf, libpng, libvorbis are pulled from portlibs packages.
• Build system: CMake; they provide “Switch.cmake” toolchain that appends -specs=$(DEVKITPRO)/libnx/switch.specs.
Take-aways for mkxp-z:
1. 95 % of the platform glue you need is already solved in that Switch port: SDL window, audio, input, FS.
2. We can copy their CMake toolchain + small libnx helper files almost verbatim (licence: GPL-2 — compatible with mkxp-z’s GPL-2).

B. JoiPlay
• Android / Linux front-end that embeds a modified mkxp-z core.
• Interesting branches:
jp/mkxp-z@joiplay-android – all platform-specific changes are guarded with #ifdef JOIPLAY.
• Major differences vs upstream mkxp-z:
– Bundles Ruby 2.4 as static library (because Android can’t dlopen).
– Adds an asset loader abstraction so the game content can live inside Android APK’s “assets”.
– Gamepad mapping layer (XInput-like → RPG Maker keys).
• There is no Switch port here, but the patches show how to untangle mkxp-z’s desktop-only assumptions: file dialogs, IME, etc.

C. Strategy Shift: Upstream mkxp-z now uses Meson (not CMake). We adapted the plan to use a Meson cross-file (switch.ini) instead of a CMake toolchain.

Take-aways for mkxp-z:
1. We will need to follow the same “embed Ruby” approach; dynamic loading is not available on libnx homebrew.
2. JoiPlay already fixed a lot of “desktop only” code paths; we can cherry-pick those commits into our branch.

──────────────────────────────
2. Technical checkpoints for a Switch mkxp-z port
──────────────────────────────
(0) Build mkxp-z on desktop first (prove your fork compiles).

(1) Dependencies that already exist in devkitPro/portlibs:
• SDL2, SDL2_image, SDL2_mixer, zlib, libpng, libjpeg-turbo, freetype, libvorbis/ogg, OpenAL-Soft.
Install with dkp-pacman -S switch-… inside your Docker container.

(2) The “missing” dependency: Ruby. Choices:
a. Static Ruby 2.7
– Easiest: copy JoiPlay’s CMakeLists.txt for building Ruby, change Android defines to libnx defines, append -D__SWITCH__.
– Strip out ext/openssl, ext/readline, which require unix TTY.
b. mruby (lightweight).
– Less compatible: Pokémon Essentials games use RGSS 1.0 APIs that rely on full Ruby standard libs, so stick with full Ruby.

(3) Platform layer code to write:
• src/platform/switch/ directory with:
– switch_main.cpp (call socketInitializeDefault, romfsInit, hidInitialize, etc.).
– SwitchFilesystem.cpp implementing overrides for mkxp::File to transparently search:
1. sdmc:/switch/mkxp-z/games/<GameFolder>
2. romfs:/ (if user packages game inside NRO).
– SwitchInput.cpp converting libnx HID data → mkxp key states (A=B, B=Y, etc.).
– Optional: SwitchHomeButton.cpp to handle HOME suspend/resume.

(4) Audio: easiest path is OpenAL-Soft (already ported by devkitPro). Point CMake to link -lopenal. Alternately use SDL2_Audio to avoid additional lib.

(5) GPU:
• Upstream SDL2 on Switch defaults to GLES2 + Nvidia Tegra EGL.
• mkxp-z’s rendering back-end:
– GL 2.x (desktop)
– GLES2 path already exists for Android/iOS builds (look at RenderContext_gles2.cpp).
• So you only need to turn on -DMKXP_BACKEND_GLES2 in CMake.

(6) Packaging & deployment:
• Use EasyRPG’s scripts/create_nro.sh as a template.
• nacp metadata example:
title: “mkxp-z Switch Player”
author: “YourName”
version: “0.1.0”
• Ship one .nro; user drops game folders under /switch/mkxp-z/games.

──────────────────────────────
3. Concrete work plan (in Git branches)
──────────────────────────────
Step 0 – confirm desktop build
git checkout -b switch-port-bootstrap
cmake -Bbuild -H. -DMKXP_USE_OPENAL=ON
make -C build
Run a sample RGSS game on Linux to be sure nothing is broken.

Step 1 – import EasyRPG’s Switch toolchain
• Copy cmake/toolchains/armv8-switch.cmake into cmake/toolchains/.
• Add toolchains/SwitchHelpers.cmake with find_package(SDL2 REQUIRED) etc.

Step 2 – add platform directory
mkdir -p src/platform/switch
Borrow src/ports/switch/switch_main.cpp from EasyRPG as a skeleton, replace EasyRPG hooks with mkxp::Engine::run(argc, argv).

Step 3 – embed Ruby
• Create external/ruby/ and commit JoiPlay’s CMake build scripts.
• In top-level CMakeLists.txt add add_subdirectory(external/ruby) and link ruby-static.
• Patch mkxp-z’s ruby_main.cpp to call ruby_sysinit(&argc, &argv) etc. unconditionally.
• Define RUBY_MKXP_STATIC to silence dlopen logic.

Step 4 – input mapping layer
• New file SwitchInput.cpp. Example map:
Joy-Con A → RPG key “C” (confirm)
Joy-Con B → “B” (cancel)
Plus → F12 (reset)
Touchscreen → already handled by SDL2’s mouse events.

Step 5 – iterate, run on hardware
Inside container:
cmake -Bbuild-switch -H. \
-DMKXP_BACKEND_GLES2=ON \
-DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/armv8-switch.cmake
make -C build-switch
nacptool … && elf2nro build-switch/mkxpz.elf mkxpz.nro …
Copy to SD:/switch/mkxp-z/ and run via hbmenu.

Use nxlink -s to stream stdout/stderr for live debugging.

Step 6 – upstream hygiene
• Re-run clang-format for added files.
• Push to your fork.
• Once booting, open a WIP PR marked [WIP] Switch port so others can review.

──────────────────────────────
4. What could go wrong and how to mitigate
──────────────────────────────

Ruby compile fails with missing pthreads → add -D__SWITCH__ -DHRUBY_HAVE_PTHREAD_NATIVE=0 and patch thread_pthread.c.
GLES2 shaders won’t compile (precision qualifiers) → borrow the Android GLES2 shader path already in mkxp-z.
Out-of-memory for large PNGs on 4 GB Switch RAM → enable SDL2 texture streaming and purge caches every map-change.
Audio pops → set OpenAL buffer size to 1024 and use audren backend (OpenAL’s switch port supports it).
──────────────────────────────
5. Milestone checklist
──────────────────────────────
✓ Docker dev environment (done)
□ mkxp-z desktop build green
□ CMake cross-build generates .elf
□ SDL window opens on Switch
□ Ruby “Hello World” runs (proof interpreter works)
□ Load title screen of a small RGSS game
□ Full Pokémon Essentials fan project loads maps + plays BGM
□ Package v0.1 release .nro on GitHub

──────────────────────────────
6. Optional future polish
──────────────────────────────
• FPS limiter tied to Switch vsync to save battery.
• NSP forwarder channel for Atmosphere users.
• Amiibo event callback (why not?).
• Integrate gyro for minigames (add to Input layer).

──────────────────────────────
Bottom line
──────────────────────────────
• EasyRPG gives you a proven recipe for the libnx + SDL2 plumbing.
• JoiPlay shows how to tame mkxp-z for a non-desktop OS (static Ruby, asset abstraction).
• Combine the two: transplant EasyRPG’s porting scaffold + cherry-pick JoiPlay’s upstream fixes.
















# 🧩 Work Done So Far

## 1. Reference Projects & Strategy

- **Strategy:** Use **mkxp‑z** (Meson build system) + **devkitPro toolchain** to target Nintendo Switch homebrew.
- **Approach:** Cross‑compile all dependencies, **link statically**, and package the output as a `.nro` executable.
- **Reference Implementations:**
  - **EasyRPG‑Player** – provides a working SDL2 + libnx + CMake baseline for Switch.
  - **JoiPlay** – demonstrates static Ruby embedding and non‑desktop abstractions.
- **Build Methodology:** Automate everything with reproducible shell scripts inside Docker to rebuild a full toolchain.

---

## 2. Accomplished Milestones

| Area | Status | Notes |
|------|---------|-------|
| **Docker Environment** | ✅ **Complete** | • devkitA64 toolchain installed<br>• libnx SDK + portlibs configured<br>• Meson, ninja, pkg-config available |
| **Desktop Build Validation** | ✅ **Complete** | • mkxp-z builds on x86_64 Linux<br>• Confirmed Meson build system works |
| **Cross-Compilation Setup** | ✅ **Complete** | • `switch.ini` Meson cross-file created<br>• Toolchain: `aarch64-none-elf-gcc` (GCC 15.1.0)<br>• Flags: `-march=armv8-a -mtune=cortex-a57 -D__SWITCH__` |
| **PhysFS Build** | ✅ **Complete** | • Version: 3.2.0<br>• Patched for Switch POSIX mode<br>• Output: `libs/physfs-switch/lib/libphysfs.a`<br>• Automated via `configure_mkxpz.sh` |
| **SDL_sound Build** | ✅ **Complete** | • Version: 2.0.1<br>• Examples removed, static-only<br>• Patched `sdl2.pc` (removed invalid EGL libs)<br>• Output: `libs/SDL_sound-switch/lib/libSDL2_sound.a` |
| **Ruby 3.2 Cross-Compilation** | 🔄 **Complete** | switch/buildScripts/build_ruby_switch.sh| 
| **mkxp‑z Switch Build** | ✅ **Complete** | • `switch/buildScripts/build_mkxpz_switch.sh` fully automates:<br>  – All patch operations for filesystem, asserts, and net stubs<br>  – Meson + Ninja cross‑build producing `build-switch/mkxp-z`<br>  – `.nacp` metadata and `.nro` packaging<br>• Output: `build-switch/mkxp-z.nro` runs in Flatpak Ryujinx ✔ |
| **Emulator Verification** | ✅ **Complete** | • HelloWorld NRO and mkxp‑z NRO load in Ryujinx (firmware 21.0.0)<br>• Proper NACP inclusion prevents LibHac crash<br>• Logs stream to `sdmc:/hello_log.txt` and `sdmc:/mkxpz_log.txt` |
| **On‑Device Testing Prep** | ⚙️ **In Progress** | • mkxp‑z NRO packaged for `/switch/mkxp-z/`<br>• Ready to deploy to real Switch via hbmenu for first run tests |

### Now, on Switch (and in Ryujinx, where sdmc:/ is the Flatpak sdcard folder), mkxp‑z will always look for Game.ini in:
   ```
   ~/.var/app/io.github.ryubing.Ryujinx/config/Ryujinx/sdcard/switch/
   sdmc:/switch/mkxp-z/Game.ini
   ```
set in 
   ```src/main.cpp```
line 
   ```strncpy(dataDir, "sdmc:/switch/mkxp-z", sizeof(dataDir));```

---

## 3. Immediate Next Steps (Current Challenge)
✅ **Current State:**  
The complete mkxp‑z Switch build now produces a valid `.nro` with embedded NACP metadata.  
having issues with the nro running on the switch. attempting to debug in the emulator first
- **Filesystem Layer**
  - Replace placeholder:
    ```cpp
    // TODO: real Switch filesystem implementation.
    // For now, use mkxp‑z’s existing filesystem logic.
    ```
  - Implement proper search order:
    ```
    1. sdmc:/switch/mkxp-z/games/<GameFolder>/
    2. romfs:/
    ```
  - Confirm PhysFS mounts and relative paths work under both emu + hardware.

- **Input Layer**
  - Replace stubbed comment:
    ```cpp
    // TODO: real Switch input mapping if needed.
    // For now, rely on SDL2’s input handling.
    ```
  - Implement Joy‑Con‑to‑RGSS key mapping (`A→C`, `B→B`, `Plus→F12`, etc.) consistent with EasyRPG mapping.

   - stubbed: switch/switch_time_stub.c   




### 🧩 Resolved Issues

- **libnx socket/time crash (2168‑0002 0x4a8)**
  - Crash traced via `addr2line` to `libnx time.c` during early `socketInitializeDefault()`.
  - Cause: sockets/time services unavailable in homebrew context.
  - **Fix:** removed `socketInitializeDefault()` and `nxlinkStdio()`. Launch now stable.

- **Ryujinx “Loading as homebrew” hang**
  - Cause: missing NACP section in generated `.nro`.
  - **Fix:** added explicit `nacptool` → `elf2nro --nacp=...` step in build.
  - Result: `.nro` loads instantly with metadata recognized (`Hello World (mkxp‑z test)`).

- **Repeated patching of `httplib.h`**
  - Issue: non‑idempotent build patch duplicated `#ifndef __SWITCH__` blocks.
  - **Fix:** introduced sentinel `// SWITCH_HTTPLIB_PATCH` and guarded patch block—stable for multiple runs.

# cmds:

   clear && docker build -t switch-dev switch/buildScripts/. && xhost +local: && docker run -it --rm   -e DISPLAY=$DISPLAY   -v /tmp/.X11-unix:/tmp/.X11-unix   -v "$(pwd)":/workspace   switch-dev


# Clean start:

   cd /workspace

   ### 1) Ruby: make sure we’re using the new -fPIC build
   clear && rm -rf ruby-3.2.2 libs/ruby-switch && switch/buildScripts/build_ruby_switch.sh

   ### 2) PhysFS + SDL_sound with -fPIC
   //dont run this i think      rm -rf physfs-src physfs-build libs/physfs-switch
   //dont run this i think      rm -rf SDL_sound-src SDL_sound-build libs/SDL_sound-switch
   
   clear
   switch/buildScripts/configure_mkxpz.sh

   ### 3) mkxp-z itself
   clear && rm -rf build-switch && switch/buildScripts/build_mkxpz_switch.sh


# Finding the log like issue: 
EX: 
```
 log
      FP:                      000000534fd41fe0
      LR:                      0000005978142c38 (mkxp-z + 0x114c38)
      SP:                      000000534fd41fe0
      PC:                      0000005978142da0 (mkxp-z + 0x114da0)
    Stack Trace:
      ReturnAddress[00]:       000000597802e0ac (mkxp-z + 0xac)
      ReturnAddress[01]:       0000001c4c96b05c
      ReturnAddress[02]:       0000001751011c90

  CMD:
   aarch64-none-elf-addr2line -f -C -e build-switch/mkxp-z 0x114da0 0x114c38 0xac
```


## one cmd to clear, copy mkxpz, and run in emulator:
```
clear && cp ~/projects/mkxp-zSwitchPort/build-switch/mkxp-z.nro /home/grant/.var/app/io.github.ryubing.Ryujinx/config/Ryujinx/sdcard/switch/ && flatpak run io.github.ryubing.Ryujinx /home/grant/.var/app/io.github.ryubing.Ryujinx/config/Ryujinx/sdcard/switch/mkxp-z.nro
```


files to give to the ai:
build_ruby_switch.sh
build_mkxpz_switch.sh
configure_mkxpz.sh
switch.ini
src/main.cpp
src.meson.build
binding/meson.build
switch/assert_wrapper.h















# Note a couple of things to clean up later (not blocking yet)
These are worth correcting, but I’d treat them as secondary until we see the exact crash location:

Redundant / dubious GL libs on Switch
You patched sdl2.pc to remove -lEGL -lglapi -ldrm_nouveau, then you re‑added -lglapi -ldrm_nouveau manually in:

meson
sdl2 = declare_dependency(
    include_directories: switch_inc,
    link_args: switch_link_args + ['-lSDL2', '-lnx', '-lglapi', '-ldrm_nouveau', '-lm']
)
On real hardware those Mesa/DRM libs don’t exist and aren’t needed; SDL2 for Switch uses libnx+EGL internally. Once we have the core crash identified, I’d strip that down to:

meson
sdl2 = declare_dependency(
    include_directories: switch_inc,
    link_args: switch_link_args + ['-lSDL2', '-lnx', '-lm']
)
Ruby arch include path mismatch
switch.ini uses:
ini
-I/workspace/libs/ruby-switch/include/ruby-3.2.0/aarch64-linux
src/meson.build uses:
meson
'../libs/ruby-switch/include/ruby-3.2.0/aarch64-elf'
Your build_ruby_switch.sh copies .ext/include/aarch64-elf into ruby-3.2.0/aarch64-elf, so that’s the correct arch dir. The aarch64-linux include in the cross-file likely doesn’t exist and is just redundant; it probably doesn’t hurt, but we should clean it once we know everything else works.