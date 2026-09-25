# RA2 RPG — Chrono Divide Mod

This project now targets **Chrono Divide + the official Chrono Divide Mod SDK** instead of maintaining a custom browser renderer.

Chrono Divide is a browser reimplementation of Red Alert 2. Its public Mod SDK supports RA2-style mod files such as INI files, MIX archives, maps and a standalone `modcd.ini` manifest. The original Red Alert 2 MIX archives are supplied separately by the player and are not included in this repository.

## Project direction

The goal is to explore an Action-RPG-like Red Alert 2 experience while keeping Chrono Divide as the rendering/gameplay engine.

The repository is organized as a Chrono Divide mod workspace:

```text
ra2-rpg/
  mod/
    modcd.ini
    rules.ini
    art.ini
    README.txt

  tools/
    package-mod.sh

  dist/
    generated mod archives

  docs/
    CHRONO-DIVIDE.md
```

## Important engine constraint

Chrono Divide's public Mod SDK exposes RA2-compatible modding through INI/MIX/map content. It does not expose the entire game client source as a general-purpose RPG engine.

That means we can directly modify things such as:

- units
- infantry
- weapons
- buildings
- art definitions
- maps
- game rules
- supported map triggers/actions
- custom MIX content

But systems such as a persistent MMO inventory, arbitrary JavaScript NPC dialogue trees, accounts or a totally new control layer are not automatically available through the Mod SDK. Those features will need to be approximated with supported RA2/Chrono Divide mechanics or implemented as a separate companion layer where possible.

## Prerequisites

You need:

- an original Red Alert 2 installation / original MIX archives
- access to Chrono Divide in your browser
- Docker Desktop only if you want to use the packaging helper in this repository

No copyrighted Red Alert 2 assets are stored in this repository.

## Development workflow

1. Open Chrono Divide.
2. Go to **Options → Storage**.
3. Open the `mods` directory.
4. Create a folder named:

```text
ra2-rpg
```

5. Copy the files from this repository's `mod/` directory into that folder.
6. Reload Chrono Divide.
7. Open **Mods**.
8. Load **RA2 RPG**.
9. After every mod-file change, refresh/reload the Chrono Divide client.

## Package the mod with Docker

Build the helper image once:

```powershell
docker compose build
```

Create a distributable ZIP:

```powershell
docker compose run --rm mod-builder
```

The generated archive will appear in:

```text
dist/ra2-rpg.zip
```

The archive is intentionally flat, as expected by Chrono Divide's mod import workflow.

## Updating the project

```powershell
cd C:\ra2-rpg
git pull
```

You normally do **not** need to rebuild a game server anymore because Chrono Divide itself is the game client.

## Main mod files

### mod/modcd.ini

Chrono Divide mod manifest. It defines the mod ID, name, description, version and author.

### mod/rules.ini

Gameplay definitions and overrides.

### mod/art.ini

Visual definitions and overrides.

Additional files can later include:

```text
*.map
*.mpr
*.pkt
expand##.mix
ecache##.mix
elocal##.mix
ra2.csf
```

## Next milestones

The sensible order for this project is now:

1. Create a dedicated RPG-style infantry hero.
2. Restrict gameplay toward controlling a small number of units / one hero where possible.
3. Create RPG-like weapons and progression proxies using supported rules.
4. Build a dedicated large isometric map.
5. Add civilians/NPC-like actors and supported map triggers.
6. Add custom SHP/VXL/building/loot-style graphics in MIX archives.
7. Evaluate which requested RPG systems require an external companion service rather than Chrono Divide modding alone.

## Official references

- Chrono Divide Mod SDK: https://github.com/chronodivide/mod-sdk
- Chrono Divide: https://chronodivide.com
