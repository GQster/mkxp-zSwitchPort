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
| **Docker Environment** | ✅ Validated | devkitPro’s `libnx`, `portlibs`, and SDK toolchains installed. |
| **Desktop Build** | ✅ Validated | mkxp‑z compiles and runs correctly on x86_64 Linux. |
| **Cross‑Build System** | ✅ Created | `switch.ini` Meson cross file configured for `aarch64‑none‑elf` toolchain. |
| **Ruby 3.2 Cross‑Compilation** | ✅ Completed | `build_ruby_switch.sh` builds static Ruby 3.2.2 (**`libruby‑static.a`**). |
|  |  | • Injected **C shim** to emulate `mmap()` / `mprotect()` using `calloc`.<br>• Disabled **signal‑based GC** (`USE_SIGALTSTACK 0`).<br>• Produces fully static lib at `libs/ruby‑switch/lib/libruby‑static.a`. |
| **PhysicsFS Build** | ✅ Completed | Cross‑compiled v3.2.0, patched for Switch POSIX mode (`PHYSFS_PLATFORM_UNIX`).<br>Output: `libs/physfs‑switch/lib/libphysfs.a`. |
| **SDL_sound Build** | ✅ Completed | Cross‑compiled v2.0.1 with all examples removed.<br>Patched `sdl2.pc` to drop invalid `‑lEGL ‑lglapi ‑ldrm_nouveau`.<br>Output: `libs/SDL_sound‑switch/lib/libSDL2_sound.a`. |
| **Automation** | ✅ Stable | `configure_mkxpz.sh` cleanly and reproducibly builds PhysFS + SDL_sound.<br>All intermediate issues (math libs, pkg‑config, dangling example targets) resolved. |

---

## 3. Immediate Next Steps (Current Challenge)

1. **Meson Integration – mkxp‑z**
   - Configure Meson using `switch.ini` to consume the newly built static libraries:  
     - `libruby‑static.a`  
     - `libphysfs.a`  
     - `libSDL2_sound.a`
   - Override or wrap Meson dependency lookups to point at these libs and their include paths.

2. **Compile Engine**
   - Run `meson compile -C build‑switch` (or `ninja ‑C build‑switch`) to generate the main `mkxp‑z.elf`.

3. **Link & Package**
   - Convert `.elf → .nro` using `elf2nro` with Switch metadata (`nacptool`).  
   - Deploy to `/switch/mkxp‑z/` on SD card for testing.

---

✅ **Current State:**  
_All dependency builds (Ruby, PhysFS, SDL_sound) are complete and verified._  
The project is ready to move into the **mkxp‑z Meson cross‑compile stage** and integrate the engine‑specific Switch platform layer.d.<br>Patched `sdl2.pc` to drop invalid `‑lEGL ‑lglapi ‑ldrm_nouveau`.<br>Output: `libs/SDL_sound‑switch/lib/libSDL2_sound.a`. |
| **Automation** | ✅ Stable | `configure_mkxpz.sh` cleanly and reproducibly builds PhysFS + SDL_sound.<br>All intermediate issues (math libs, pkg‑config, dangling example targets) resolved. |

---

## 3. Immediate Next Steps (Current Challenge)

1. **Meson Integration – mkxp‑z**
   - Configure Meson using `switch.ini` to consume the newly built static libraries:  
     - `libruby‑static.a`  
     - `libphysfs.a`  
     - `libSDL2_sound.a`
   - Override or wrap Meson dependency lookups to point at these libs and their include paths.

2. **Compile Engine**
   - Run `meson compile -C build‑switch` (or `ninja ‑C build‑switch`) to generate the main `mkxp‑z.elf`.

3. **Link & Package**
   - Convert `.elf → .nro` using `elf2nro` with Switch metadata (`nacptool`).  
   - Deploy to `/switch/mkxp‑z/` on SD card for testing.

---

✅ **Current State:**  
_All dependency builds (Ruby, PhysFS, SDL_sound) are complete and verified._  
The project is ready to move into the **mkxp‑z Meson cross‑compile stage** and integrate the engine‑specific Switch platform layer.
















clear && docker build -t switch-dev switch_port/. && xhost +local: && docker run -it --rm   -e DISPLAY=$DISPLAY   -v /tmp/.X11-unix:/tmp/.X11-unix   -v "$(pwd)":/workspace   switch-dev

cd switch_port
clear && rm -rf ../build-switch
./build_mkxpz_switch.sh