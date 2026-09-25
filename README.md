# RA2 RPG — self-hosted RA2 Web workspace

This repository now runs a **self-hosted browser RA2 engine in Docker** using the GPL-3.0 project [DD-Channel/ra2-web](https://github.com/DD-Channel/ra2-web) as the upstream codebase.

The long-term goal is to modify that engine into an isometric action-RPG experience while reusing Red Alert 2 file formats, rendering and game logic.

## Important status

The upstream RA2 Web project is still under development. It already contains parsers/rendering support for MIX, SHP, VXL, TMP, INI and other Red Alert 2 formats, but not every original-game feature is complete.

This repository currently provides the **self-hosted Docker foundation**. RPG engine changes will be added as patches/overrides on top of the pinned upstream source.

## Original Red Alert 2 files

Put your legally owned original game files in:

```text
C:\ra2-rpg\original-game\
```

For example:

```text
original-game/
  ra2.mix
  language.mix
  multi.mix
  cache.mix
  local.mix
  conquer.mix
  neutral.mix
  generic.mix
  ...
```

The directory is excluded from Git.

At runtime Docker mounts it read-only at:

```text
/app/public/original-game
```

so the files are available only through the local web application.

The Docker port is deliberately bound to:

```text
127.0.0.1:8080
```

rather than all network interfaces, to avoid exposing your original game archives to the LAN.

## Start the self-hosted client

From PowerShell:

```powershell
cd C:\ra2-rpg
git pull
docker compose down
docker compose up --build -d
```

Then open:

```text
http://localhost:8080
```

To follow logs:

```powershell
docker compose logs -f ra2-web
```

To stop it:

```powershell
docker compose down
```

## Architecture

```text
Browser
   |
   v
localhost:8080
   |
   v
Docker / Vite
   |
   +-- DD-Channel/ra2-web source
   |
   +-- /original-game  <-- your local RA2 files, read-only
   |
   +-- future RPG patches
```

## Upstream version

The Docker image currently pins RA2 Web commit:

```text
786800b50fe19f7dbe1fa6243e364fd761c64198
```

Pinning the commit makes our modifications reproducible instead of silently changing every time the upstream repository changes.

## RPG modification strategy

Our changes will live under:

```text
patches/
```

and later be applied during the Docker build/start process.

Planned engine changes:

- click-to-move single-character controls
- hero-centric gameplay instead of RTS unit selection
- visible projectiles and weapon effects
- NPC interaction/dialogues
- inventory and loot
- quests
- persistent character state
- large isometric RPG maps
- custom characters/buildings/items
- multiplayer RPG synchronization

## Licensing

The upstream RA2 Web project states that it is GPL-3.0. Any distributed derivative code based on it must therefore remain compatible with GPL-3.0 and provide source code.

Red Alert 2 itself and its original data files remain EA's intellectual property and are **not included in this repository**.

## Previous Chrono Divide Mod SDK files

The old `mod/` directory is retained for reference while the project transitions to the self-hosted engine. The active Docker service is now `ra2-web`, not the previous `mod-builder`.
