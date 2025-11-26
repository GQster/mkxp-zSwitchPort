My attempt at porting over mkxp-z for the switch, cause all a guy wants is to play Pokemon Fire Ash on the switch.


Idea: look at [EasyRPG](https://easyrpg.org/)([GIT](https://github.com/EasyRPG/)) and [JoiPlay](https://joiplay.net/) to get ideas on how to proceed...

[mkxp-z base](https://github.com/mkxp-z/mkxp-z/)








# 🎮 mkxp‑z Switch Port – Build Guide (Progress Checkpoint)

## Overview

This project aims to **port mkxp‑z** (RPG Maker XP/VX/VX Ace engine) to the **Nintendo Switch** using the
[devkitPro](https://devkitpro.org) homebrew toolchain.  
The long‑term goal is to allow fan projects such as *Pokémon Essentials* to run natively on Switch.

This document covers **everything up to the current milestone**:  
All dependencies cross‑compiled, static libraries created, and the system ready for mkxp‑z Meson integration.

---

## 🧱 Requirements

You’ll need:
- Docker (≥ 20.x)
- Git
- Internet connectivity to pull source archives
- A host system capable of running x86‑64 Docker containers

All compilation happens **inside a Docker container** with the devkitPro SDK pre‑installed.  
No native host setup required.

---

## 🚀 Quick Start

### 1 – Clone the Repository

```bash
git clone https://github.com/yourname/mkxp-z-switch.git
cd mkxp-z-switch
```


### 2 – Launch the Docker Build Environment
```bash
cd ~/projects/mkxp-zSwitchPort/
# Allow Docker/X11 to show windows
xhost +local: 
# Run the dev image, mounting your repo directly
docker run -it --rm \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$(pwd)":/workspace \
  switch-dev
```
or one line: 

```
docker build -t switch-dev switch_port/. && xhost +local: && docker run -it --rm   -e DISPLAY=$DISPLAY   -v /tmp/.X11-unix:/tmp/.X11-unix   -v "$(pwd)":/workspace   switch-dev
```

You’re now inside the build environment at /workspace.

## 🧩 Build Steps So Far
### Step 1 – Build Ruby for Switch
```bash
./build_ruby_switch.sh
```
This creates a fully static Ruby 3.2.2 library compatible with libnx.

libs/ruby-switch/lib/libruby-static.a


### Step 2 – Build PhysicsFS and SDL_sound
Run the combined dependency builder:

```bash
./configure_mkxpz.sh
```
This script:

- Patches sdl2.pc to remove invalid libraries (-lEGL -lglapi -ldrm_nouveau).
- Cross‑compiles PhysicsFS 3.2.0 → libs/physfs-switch/lib/libphysfs.a
- Cross‑compiles SDL_sound 2.0.1 → libs/SDL_sound-switch/lib/libSDL2_sound.a
- Removes all demo executables for clean static builds.
- Both libraries are built statically for aarch64‑none‑elf and link successfully.

### Step 3 – Verify Results
After the above completes, confirm all libraries exist:

```bash
ls libs/*/lib/*.a
```
You should see: 
```text
libs/ruby-switch/lib/libruby-static.a
libs/physfs-switch/lib/libphysfs.a
libs/SDL_sound-switch/lib/libSDL2_sound.a
```


### 🗂 Directory Layout After This Milestone
```
mkxp-z-switch/
└─ switch_port/
    ├─ build_ruby_switch.sh
    ├─ configure_mkxpz.sh
    ├─ dockerfile
    ├─ switch.ini
└─ libs/
   ├─ ruby-switch/
   │   └─ lib/libruby-static.a
   ├─ physfs-switch/
   │   └─ lib/libphysfs.a
   └─ SDL_sound-switch/
       └─ lib/libSDL2_sound.a
└─ physfs-build/
└─ ruby-3.2.2/
└─ SDL_sound-build/
└─ <everything else from the repo>/