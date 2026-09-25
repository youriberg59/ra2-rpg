# RA2 Action RPG Prototype

A small browser-based multiplayer action-RPG vertical slice inspired by Red Alert 2.

This prototype deliberately uses placeholder vector graphics instead of copyrighted Red Alert 2 assets. It is designed so an asset-import layer can be added later for users who own the original game.

## Included

- Browser client
- WebSocket multiplayer
- PostgreSQL persistence
- Character save/load
- WASD / arrow movement
- Multiplayer presence
- NPC interaction
- Quest acceptance and completion
- Enemy combat
- Enemy respawn
- XP and leveling
- Credits
- Loot
- Inventory + medkits
- Simple enemy AI
- Docker Compose
- Development bind mounts + Node watch mode
- Content-driven quests, NPCs, and enemies

## First start

Requirements:

- Docker Desktop / Docker Engine
- Docker Compose

Clone the repository:

```bash
git clone https://github.com/youriberg59/ra2-rpg.git
cd ra2-rpg
```

Then build once:

```bash
docker compose up --build -d
```

Open:

```text
http://localhost:8080
```

To test multiplayer, open a second browser/private window and use a different Player ID.

## Updating from GitHub

For normal updates:

```bash
git pull
```

The project uses bind mounts:

- `./server` -> live server source
- `./client` -> live browser files
- `./content` -> live content files

Server JavaScript changes are watched by Node and automatically restart the game process.

Client HTML/JavaScript/CSS changes are visible after refreshing the browser.

Content JSON is mounted directly too, but the current prototype loads it when the server starts. After quest/NPC/enemy content changes:

```bash
docker compose restart game
```

You only need to rebuild after changes to:

- `Dockerfile`
- `server/package.json`

Then use:

```bash
docker compose up -d --build
```

## Controls

- `WASD` / arrow keys: move
- Click an enemy: attack
- Click Boris: talk
- Mouse wheel: zoom
- Use medkits from the inventory panel

## First quest

1. Spawn in town.
2. Click Boris.
3. Accept **The Old Radar Station**.
4. Move east to the radar station.
5. Kill 5 bandits.
6. Return to Boris.
7. Receive credits, XP, and a medkit.
8. Reload later with the same Player ID — progress is saved.

## Content editing

Edit:

- `content/quests.json`
- `content/npcs.json`
- `content/enemies.json`

## Reset all saved characters

```bash
docker compose down -v
docker compose up --build -d
```

The `-v` option deletes the PostgreSQL volume, so do not use it during normal updates.

## Architecture

```text
Browser
  |
  | WebSocket
  v
Node.js authoritative game server
  |
  +-- world state
  +-- enemy AI
  +-- quest logic
  +-- combat
  |
  v
PostgreSQL
  |
  +-- character position
  +-- level / XP
  +-- inventory
  +-- quest progress
```

## Important prototype limitations

This is intentionally the first vertical slice, not the final engine.

Not yet included:

- Red Alert 2 asset importer
- SHP/VXL/HVA renderer
- RA2 map parser
- proper collision/pathfinding
- click-to-move
- ranged projectiles
- equipment slots
- party system
- instanced dungeons
- account/password authentication
- admin content editor
- world editor
