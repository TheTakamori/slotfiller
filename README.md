# Slot Filler

Slot Filler saves and restores action bar slot assignments (spells, macros,
mounts, items, and similar actions) as named profiles. Blizzard Edit Mode
still controls bar layout; this addon only manages what is assigned to each
slot.

Profiles are account-wide. Any profile saved on one character is available on
every other character on the account.

Current version: `1.3.0`.

Target: WoW Retail `12.0.7 (Midnight)`.

## Features

- Save all action bar slots as a named profile (main bars, class bonus bars,
  Skyriding bar, and extra bars — slots 1–180).
- Saves and restores Transmog Outfit buttons, the pet action bar (pet
  abilities; pet command tokens like Attack/Follow/Stay are left untouched),
  and Click Bindings (click-cast spells, items, and macros).
- Normalizes talent-overridden spells to their base spell ID when saving, so
  a profile keeps working after a talent or spec change.
- Load a profile directly with `/sfill <name>`.
- Manage profiles from a minimap button or `/sfill`: save, load, update,
  rename, duplicate, and delete.
- Assign auto-load rules per profile using character, class, and spec
  multi-select dropdowns.
- Enable or disable auto-loading per profile with the **Allow Profile Auto
  Load** checkbox.
- Automatically loads the best-matching profile on login, reload, or spec
  change.
- Stores data account-wide in `SlotFillerDB`.

## Slash Commands

- `/sfill` — Open the profile manager.
- `/sfill <name>` — Load a profile by name (shorthand, usable in macros).
- `/sfill save <name>` — Save current bar assignments as a new profile.
- `/sfill load <name>` — Load a saved profile.
- `/sfill list` — List all saved profiles.
- `/sfill delete <name>` — Delete a profile.
- `/sfill rename <old> <new>` — Rename a profile.
- `/sfill duplicate <source> <new>` — Copy a profile.
- `/sfill minimap` — Show or hide the minimap button.
- `/sfill help` — Show command help.

## Installing

1. Close World of Warcraft.
2. Copy the `SlotFiller` folder into `_retail_/Interface/AddOns/`.
3. Start the game and enable `Slot Filler` from the addon list if needed.

## Building a Release

Run the build script from the repository root:

```
python tools/build_release.py
```

This produces `SlotFiller-<version>.zip` in the parent directory. The script
excludes `tests/`, `tools/`, `CURSEFORGE_SUBMISSION.md`, and the dev-only
files (`UI/CopyFrame.lua`, `UI/DevCommands.lua`) from the zip. It also strips
those entries from the packaged `.toc` and removes source-only icon sizes,
keeping only `slotfiller-64.png` (the size used by the game engine).

## Development

Run the test suite with:

```
lua tests/run.lua
```

Dev-only features (bar scan, restore error viewer, SBA diagnostics) live in
`UI/DevCommands.lua` and `UI/CopyFrame.lua`. These files are loaded in
development via the `.toc` but are stripped from release builds by
`tools/build_release.py`.

## Notes

- Save and load are blocked while in combat.
- Slots whose spells are unavailable for the current spec are silently skipped
  on load.
- The Rotation Assistant (SBA) button can be moved between slots but cannot
  be created from scratch (a Blizzard limitation). Keep an SBA button on every
  profile if you mix SBA and non-SBA layouts.
- Pet command tokens (Attack, Follow, Stay, and similar) are never relocated
  on load — only pet abilities are restored. Reordering tokens risks losing
  one permanently with no way to recover it, so the addon leaves them exactly
  where they currently are, the same trade-off it makes for the SBA button.
- Click Bindings are restored additively: a profile saved with none never
  clears bindings already set on the character loading it.
- Click the minimap button to open the profile manager.

## License

This project is released as `All Rights Reserved`.
