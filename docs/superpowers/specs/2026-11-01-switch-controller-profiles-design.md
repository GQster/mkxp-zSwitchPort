# Controller profiles for the Switch build: design

Date: 2026-11-01
Status: reviewed, awaiting approval

## Intent

The Switch controller layout is hard-coded today (`src/input/keybindings.cpp`,
`#ifdef __SWITCH__` block). Changing a button means rebuilding the NRO. The user
wants to rebind the Switch controller from the console itself, through a
Settings screen in the game picker, and keep several layouts as named
profiles.

mkxp-z is a PC engine, and its games are written for a keyboard. So a profile
maps Switch buttons to **keyboard keys**. A Switch button acts exactly as if
those keys were pressed on a PC keyboard. That works with every mkxp-z game,
including games that read keys directly rather than RPG Maker's virtual
buttons. It also keeps the feature game-neutral: nothing in it knows about any
particular game.

## Goals

- A **Settings** tile in the game picker opens a controls screen.
- Several **named profiles**. One is **active**, and every game launched
  afterwards uses it.
- A profile maps each Switch input to **one or more keyboard keys** from the
  full keyboard.
- Editing works the way the user described it: choose **Map a button**, press
  the Switch button to change (captured), then scroll through keyboard keys and
  pick one.
- A built-in **Default** profile reproduces today's layout exactly, so nothing
  changes for a player who never opens Settings.
- Profiles are stored on the SD card, survive NRO updates, and can be edited
  or backed up on a PC.

## Non-goals (for now)

- Per-game profiles. The user named this as a possible later option. Keep it
  possible by storing profiles by name, so a game-to-profile assignment can
  be added later, but don't build it.
- Changing profiles or bindings while a game is running.
- Mapping to RPG Maker's virtual buttons (Confirm, Cancel, …) directly.
  They're reachable through the keys games already understand.
- Touchscreen, motion controls, rumble.
- Any game-specific behaviour.

## Anti-goals (failure even if it "works")

- **Default stops behaving like today's layout.** Everything tuned this session
  must keep working with the Default profile:
  - A confirms, B cancels;
  - Y/+ open the pause menu and close menus (Start);
  - X/− switch in menus and use the registered item on the map (Select);
  - R is the registered item, ZR the game speed, ZL the soft-reset prompt in
    Pokémon Essentials games;
  - holding B runs in Essentials games;
  - L quick-saves in Fire Ash.
- **Double input.** A Switch button must not trigger both its profile keys and
  the old hard-coded controller bindings.
- **No way back to a working layout.** A broken custom profile must never lock
  the player out of the picker or of a sane layout.
- **Game-specific code** in this feature.

## User-facing design (decided with the user)

### The Settings tile

- It sits in the picker's tile row like another game, **always the last tile,
  on the right**. The most recently played game still starts selected.
- It has a gear icon and the label "Settings".
- A on it opens Settings instead of launching anything.
- **The picker is always shown when there is at least one game** (user
  decision), so Settings is always reachable. This ends today's
  auto-launch:
  - A single game folder now shows one game tile plus Settings, and A starts
    the game.
  - The old layout (a lone `Games/Game.ini`) appears as a single game tile in
    the same way.
  - The "No games found" screen stays as it is, since there is nothing to
    launch.
- The picker reads the controller directly with libnx HID, not through
  profiles. That makes it the guaranteed way back from a broken profile.

### Controls screen: profile list

- Lists every profile, with the active one marked.
- A edits the selected profile. Y makes it active. X opens rename/delete for
  it. B goes back to the picker.
- "+ New profile" creates a copy of the selected profile and asks for a name
  with the Switch's on-screen keyboard. The engine already wraps it in
  `switch/switch_swkbd.cpp`.
- **Default** is built in. It can be copied, but not edited, renamed or
  deleted. Copying it is how a custom profile starts.
- When Default is selected in the editor, its bindings are shown as the key
  table below, read-only.

### Profile editor

- The top entry is **Map a button**. Below it is a list of every Switch input
  and the keys it currently sends (e.g. `Y   Esc + F6`), or "nothing".
- **Map a button** shows "Press a button…" and captures the next Switch input:
  any button or stick direction. That's the input being edited.
- Then a **key list** shows the full keyboard. The player scrolls, picks a key
  and presses A to bind it.
- A button can send **several keys at once**. The editor must let the player
  either replace a button's keys with the chosen one or add the chosen key to
  the ones it already has, and remove keys from a button. How that's presented
  (an add/replace choice, a per-button sub-list, etc.) is left to the builder.
- The key list needs grouping or jumping (letters, digits, arrows, function
  keys, other), so finding a key among ~100 doesn't take long scrolling.
- Changes are saved when leaving the editor.

### What can be mapped

All of these can be mapped, including the stick directions, which are treated
as buttons:
- A, B, X, Y, L, R, ZL, ZR, +, −, L3, R3;
- D-pad up/down/left/right;
- left stick up/down/left/right;
- right stick up/down/left/right.

### Default profile

**Default keeps today's input path** (user decision). While Default is
active, the existing hard-coded Switch controller → RGSS bindings in
`src/input/keybindings.cpp` stay exactly as they are, and no keys are
injected. Default behaves exactly as the game plays now.

The key table below is what the editor shows for Default, and what a copy of
Default starts with. The keys are chosen from mkxp-z's standard keyboard
bindings (`defaultKbBindings` in `src/input/keybindings.cpp`), so each key
reaches the same RPG Maker button the old controller binding did:

| Switch input | Keys | Reaches (RGSS) |
|---|---|---|
| A | Enter | C |
| B | X | B |
| X | Left Shift + D | A + Z |
| Y | Esc + F6 | B + F6 |
| − | Left Shift + D | A + Z |
| + | Esc + F6 | B + F6 |
| L | Q | L |
| R | D | Z |
| ZL | F5 | F5 |
| ZR | W | R |
| D-pad, left stick | Arrow keys | Up/Down/Left/Right |
| Right stick up / down | A / S | X / Y |
| Right stick left/right, L3, R3 | nothing | |

F5 and F6 reach `Input::F5`/`Input::F6` through mkxp-z's built-in function-key
bindings. `romfs:/preload/switch_controls.rb` uses those two for soft reset
and Start, so the Essentials extras keep working in copies too.

A copy of Default runs through key injection, so it behaves slightly
differently from Default itself, and that difference is accepted:
- **Left Shift also reaches `Input::SHIFT`:** mkxp-z binds it statically in
  `staticKbBindings` in `src/input/input.cpp`.
- **Raw-key readers see the keys:** games that read the keyboard directly
  (`Input.pressex?`, `Input.raw_key_states`, the Win32API key wrappers in
  `scripts/preload/win32_wrap.rb`) see the pressed keys, exactly as they would
  from a PC keyboard.

## Constraints

- **Universal:** no game-specific code (standing user requirement).
- **The picker runs before SDL video and mkxp-z start.** It draws with
  SDL_ttf/SDL_image onto a surface copied to a libnx framebuffer, and reads
  input with libnx HID (`switch/switch_pickerui.cpp`). The Settings screens
  should reuse its drawing helpers and visual style.
- **In-game input comes through SDL's game controller API.** Its Switch
  mapping is positional: SDL's "A" is the Switch's B button, and so on. See
  the comment in `src/input/keybindings.cpp`. The physical-button names in a
  profile must be Switch labels, translated correctly.
- **Keys must look real to the game.** They have to reach mkxp-z's keyboard
  state (`EventThread::keyStates`) so that both of these see them:
  - RGSS virtual buttons through mkxp-z's keyboard bindings, including the
    static F5–F9 bindings;
  - games that read raw keys (`Input.pressex?` and similar, and the Win32API
    key stubs).

  When two Switch inputs send the same key, releasing one must not release
  the key while the other is still held.
- **Exactly one input path at a time:**
  - Default active: the old controller bindings fire, and no keys are
    injected.
  - A custom profile active: keys are injected, and the old controller
    bindings must not also fire.
- **Engine shortcuts:** some keys are handled by mkxp-z itself when pressed on
  a keyboard: F1 (settings window), F2 (FPS display), F12 (engine reset),
  Alt+Enter (fullscreen). They stay in the key list.

  F12's engine reset re-runs the game's scripts. That is known to break
  Pokémon Essentials games: their alias chains loop, see the crash
  investigation in `switch/DEBUGGING.md`. The builder decides whether these
  keys behave as on PC or get a warning in the list. They are not removed.
- **Storage:** one JSON file, `sdmc:/switch/mkxp-z/controls.json`, holding the
  custom profiles (not Default) and the name of the active profile.
  - A missing or unreadable file means "Default is active, no custom
    profiles". It must never block the picker or a game launch.
  - Deleting the file on a PC resets everything to Default. This is the last
    way back, for the case where the picker UI itself can't start (its
    text-console fallback has no Settings).
  - mkxp-z already includes a JSON library (`src/util/json5pp.hpp`).
  - The exact schema is the builder's choice, but it should use readable key
    names (e.g. SDL scancode names) so it can be edited by hand.
- **Logging:** when debug tracing is on (`debug.txt`), log which profile was
  applied at launch. That fits `switch/DEBUGGING.md`, which should get a short
  section about `controls.json`.

## Decisions made by me, not the user

These are my calls; flag any you disagree with:
- The profile list's button assignments (A edit, Y make active, X
  rename/delete, B back).
- Default is read-only, and new profiles start as copies.
- One `controls.json` file rather than one file per profile.
- Stick directions are mappable like buttons.
- The key list contains only keyboard keys, no RPG Maker virtual buttons.
  (The user agreed to keys; the "only" part is my call.)
- Changes save when leaving the editor.
- The old layout (a lone `Games/Game.ini`) appears as a single game tile.
- The "No games found" screen and the text-console fallback don't get
  Settings. Deleting `controls.json` is the last-resort reset.

## Left to the builder

- Exact screen layouts and drawing, within the picker's existing style.
- How a captured press is cancelled.
- How add/replace/remove keys is presented.
- How the key list is grouped and navigated.
- The `controls.json` schema.
- How profile keys are injected into the engine, as long as the constraints
  above hold.
- Whether engine-shortcut keys get a warning.
- Code structure and tests.
