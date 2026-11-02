# mkxp-z for Nintendo Switch

A homebrew (`.nro`) build of mkxp-z for the Nintendo Switch, using devkitPro's
devkitA64 toolchain and libnx. It runs RPG Maker XP/VX/VX Ace games, such as
Pokémon Essentials fan games, from the SD card.

## Building

Everything builds inside a Docker image based on `devkitpro/devkita64`:

```bash
switch/buildScripts/docker_build.sh         # build-switch/mkxp-z.nro
switch/buildScripts/docker_build.sh shell   # a shell in the container
```

The script builds the image from `switch/buildScripts/dockerfile` if it is
missing and runs the build as your user, so nothing in the repo ends up owned
by root.

`build_mkxpz_switch.sh` is a normal Meson cross build with
`switch/switch.ini`:

- Dependencies come from devkitPro's portlibs (SDL2, SDL2_ttf, SDL2_image,
  OpenAL, Ogg/Vorbis, Theora, FreeType, zlib).
- Everything else is built from mkxp-z's own subprojects, as on other
  platforms: Ruby 3.1, PhysFS, SDL_sound, FluidSynth, pixman, uchardet and
  libiconv. Ruby and PhysFS get small Switch patches
  (`subprojects/packagefiles/ruby-3.1-switch.patch`, `physfs-switch.patch`),
  each behind `__SWITCH__`.
- The RomFS gets `switch/romfs-root/` plus `scripts/preload/win32_wrap.rb`.

`switch/buildScripts/find_bad_tls.py` checks a disassembly of the ELF for
devkitA64's soft-TLS miscompile. The cross file avoids it with
`-ftls-model=local-exec`:

```bash
aarch64-none-elf-objdump -d build-switch/mkxp-z.cortex-a57 > dis.txt
python3 switch/buildScripts/find_bad_tls.py dis.txt
```

## Installing and playing

1. Copy `build-switch/mkxp-z.nro` to the SD card as `/switch/mkxp-z.nro`.
2. Put each game in its own folder under `/switch/mkxp-z/Games/`, with its
   `Game.ini`. A `mkxp.json` in the game folder is read as usual.
3. Start the Homebrew Menu by holding R while launching a game, not from the
   Album: the Album gives homebrew too little memory for large games.
4. Pick a game. Closing it returns to the picker; B in the picker exits.

The picker's Settings tile edits controller profiles. The system keyboard is
used for text entry.

## Debugging

Every launch writes `sdmc:/mkxpz_log.txt`. See [DEBUGGING.md](DEBUGGING.md)
for the other logs, the detailed tracing switch and crash reports.
