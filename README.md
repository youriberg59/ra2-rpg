# RA2 RPG — self-hosted RA2 Web workspace

This project runs a self-hosted browser RA2 engine using the GPL-3.0 project [DD-Channel/ra2-web](https://github.com/DD-Channel/ra2-web) as the upstream codebase.

The goal is to progressively turn it into an isometric action-RPG while reusing Red Alert 2 formats, rendering and game logic.

## No rebuild workflow

The Docker setup is now intentionally designed so normal updates do **not** require rebuilding an image.

RA2 Web itself is stored in a persistent Docker volume. Our startup script, RPG patches and original game files are bind-mounted from your working copy.

Normal update:

```powershell
cd C:\ra2-rpg
git pull
docker compose restart ra2-web
```

If the container is stopped:

```powershell
docker compose up -d
```

You should not normally need:

```text
docker compose build
docker compose up --build
```

## First start after this migration

Because the Compose architecture changed from a custom-built image to a persistent source volume, run once:

```powershell
cd C:\ra2-rpg
git pull
docker compose down
docker compose up -d
```

Then open:

```text
http://127.0.0.1:8080
```

The first launch may take longer because it clones the upstream RA2 Web repository and runs `npm ci`. Subsequent restarts reuse both the source checkout and `node_modules`.

## Original Red Alert 2 files

Put your legally owned files in:

```text
C:\ra2-rpg\original-game\
```

That folder remains excluded from Git.

Docker mounts it read-only into:

```text
/app/public/original-game
```

The service is bound only to:

```text
127.0.0.1:8080
```

so it is not intentionally exposed on your LAN.

## Patch workflow

RPG changes live under:

```text
patches/
```

Shell patch scripts named `*.sh` are applied automatically at every container start, in alphabetical order.

This means future changes can usually be deployed with only:

```powershell
git pull
docker compose restart ra2-web
```

The startup process resets the upstream source to the pinned commit first, then reapplies our patches. This keeps the environment reproducible.

## Upstream version

Pinned upstream commit:

```text
786800b50fe19f7dbe1fa6243e364fd761c64198
```

## Logs

```powershell
docker compose logs -f ra2-web
```

## Verify your original files inside the container

```powershell
docker compose exec ra2-web bash -lc "ls -lah /app/public/original-game | head -50"
```

## Planned RPG work

- automatic loading of local RA2 resources
- single-character / hero-centric controls
- click-to-move
- visible weapons/projectiles
- NPC interaction and dialogue
- inventory and loot
- quests
- persistent character state
- large isometric RPG maps
- custom characters, buildings and items

## Licensing

The upstream project states that it is GPL-3.0. Derivative distributed code must remain compatible with that license and make source code available.

Original Red Alert 2 data files remain EA's intellectual property and are not included in this repository.


## Centralized resources and LAN access

The app is now exposed on TCP port 8080 on all host interfaces.

Local access:

```text
http://127.0.0.1:8080
```

LAN access:

```text
http://YOUR-PC-LAN-IP:8080
```

The startup script creates `/original-game-pack.tar` from the host `original-game/` directory. New browsers automatically import that server-hosted archive into their own browser storage; users do not need to manually select a Red Alert 2 folder.

The UI default language is patched to `en-US`.

Each new browser/device still downloads and stores the required resources once, because browser storage is isolated per device/profile. Existing browsers reuse their local copy on subsequent visits.

Because the RA2 resource archive is available to clients that can reach port 8080, only expose this service on a trusted private network. Do not port-forward 8080 to the public Internet.
