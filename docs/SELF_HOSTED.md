# Self-hosted RA2 Web

## Why this architecture

Chrono Divide's official client is not open source. For a self-hosted and deeply modifiable browser game, this project now uses the GPL-3.0 DD-Channel/ra2-web reconstruction as its upstream engine.

## Docker behavior

The Docker image:

1. clones the upstream repository,
2. checks out a pinned commit,
3. installs npm dependencies,
4. starts Vite on port 3000.

Docker Compose maps it to:

```text
http://localhost:8080
```

and binds only to 127.0.0.1.

## Original game files

The host directory:

```text
./original-game
```

is mounted read-only into:

```text
/app/public/original-game
```

This means the local Vite server can serve the files to the browser without placing them in Git or baking them into the image.

## Verify files inside Docker

Run:

```powershell
docker compose exec ra2-web sh -lc "ls -lah /app/public/original-game | head -50"
```

## Verify the web client

Run:

```powershell
curl http://localhost:8080
```

or open it in a browser.

## Current limitation

Mounting the RA2 files makes them available to the self-hosted web app, but the upstream client may still require its normal import/virtual-filesystem workflow until we patch automatic loading.

That automatic-loader patch is the next development step after confirming the baseline build works.
