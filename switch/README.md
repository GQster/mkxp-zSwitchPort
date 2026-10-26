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


### 2 – Build

`switch/buildScripts/docker_build.sh` runs each step in the `switch-dev`
container **as your user** (so nothing in the repo ends up owned by root) and
builds the image from `switch/buildScripts/dockerfile` if it is missing.

```bash
switch/buildScripts/docker_build.sh all     # deps, Ruby, then mkxp-z.nro
switch/buildScripts/docker_build.sh mkxpz   # just mkxp-z.nro (the default)
switch/buildScripts/docker_build.sh shell   # interactive shell in /workspace
```

| Step | Script | Output |
|------|--------|--------|
| `deps` | `configure_mkxpz.sh` | `libs/physfs-switch`, `libs/SDL_sound-switch` |
| `ruby` | `build_ruby_switch.sh` | `libs/ruby-switch` (Ruby 3.2.2, static) |
| `mkxpz` | `build_mkxpz_switch.sh` | `build-switch/mkxp-z.nro` |

The Ruby build is incremental: it reuses the configured `ruby-3.2.2/` tree.
Run `RUBY_CLEAN=1 switch/buildScripts/docker_build.sh ruby` after changing
`build_ruby_switch.sh` (its configure options and source patches only apply
to a fresh tree).

### 3 – Verify Results
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
└─ switch/
  └─ buildScripts/
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