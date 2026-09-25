#!/bin/bash
set -euo pipefail

REPO="${RA2WEB_REPO:-https://github.com/DD-Channel/ra2-web.git}"
COMMIT="${RA2WEB_COMMIT:-786800b50fe19f7dbe1fa6243e364fd761c64198}"

if ! command -v git >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends git ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

if [ ! -d /app/.git ]; then
  echo "Cloning RA2 Web into persistent Docker volume..."
  rm -rf /app/*
  git clone "$REPO" /app
fi

cd /app

CURRENT_REMOTE="$(git config --get remote.origin.url || true)"
if [ "$CURRENT_REMOTE" != "$REPO" ]; then
  git remote set-url origin "$REPO"
fi

git fetch --all --tags --prune

if ! git rev-parse --verify "$COMMIT^{commit}" >/dev/null 2>&1; then
  git fetch origin "$COMMIT"
fi

git reset --hard "$COMMIT"
git clean -fd

# Linux is case-sensitive. The upstream project contains several imports whose
# filename casing matches Windows but not the actual files in src/util/.
# Normalize the known lowercase utility modules before Vite starts.
find src -type f \( -name '*.ts' -o -name '*.tsx' \) -print0 | xargs -0 sed -i \
  -e 's#/util/Logger#/util/logger#g' \
  -e 's#/util/Array#/util/array#g' \
  -e 's#/util/Mouse#/util/mouse#g' \
  -e 's#/util/String#/util/string#g' \
  -e 's#/util/Math#/util/math#g' \
  -e 's#/util/Event#/util/event#g' \
  -e 's#/util/Dom#/util/dom#g' \
  -e 's#/util/Format#/util/format#g' \
  -e 's#/util/Geometry#/util/geometry#g' \
  -e 's#/util/Number#/util/number#g' \
  -e 's#/util/Stream#/util/stream#g' \
  -e 's#/util/Time#/util/time#g' \
  -e 's#/util/UserAgent#/util/userAgent#g' \
  -e 's#/util/KeyNames#/util/keyNames#g' \
  -e 's#/util/FullScreen#/util/fullScreen#g'

# Expose the user's local RA2 files to Vite without nesting a Docker mount inside /app.
mkdir -p /app/public
rm -rf /app/public/original-game
ln -s /original-game /app/public/original-game

# Build one server-side archive that new browsers can import automatically.
# Cache it in a persistent Docker volume so normal restarts are fast.
mkdir -p /resource-cache

SOURCE_SIG="$(
  find /original-game -maxdepth 1 -type f -printf '%f:%s:%T@\n' \
    | sort \
    | sha256sum \
    | awk '{print $1}'
)"
CACHED_SIG=""
[ -f /resource-cache/original-game-pack.sig ] && CACHED_SIG="$(cat /resource-cache/original-game-pack.sig)"

if [ ! -f /resource-cache/original-game-pack.tar ] || [ "$SOURCE_SIG" != "$CACHED_SIG" ]; then
  echo "Building centralized RA2 resource archive (only required when original-game changes)..."
  TMP_ARCHIVE="/resource-cache/original-game-pack.tar.tmp"
  rm -f "$TMP_ARCHIVE"
  tar -cf "$TMP_ARCHIVE" -C /original-game .
  mv "$TMP_ARCHIVE" /resource-cache/original-game-pack.tar
  printf '%s' "$SOURCE_SIG" > /resource-cache/original-game-pack.sig
  echo "Centralized RA2 archive ready."
else
  echo "Using cached centralized RA2 resource archive."
fi

rm -f /app/public/original-game-pack.tar
ln -s /resource-cache/original-game-pack.tar /app/public/original-game-pack.tar

# Apply local patch scripts in lexical order.
if [ -d /workspace/patches ]; then
  while IFS= read -r patch_script; do
    echo "Applying patch: $patch_script"
    /bin/bash "$patch_script"
  done < <(find /workspace/patches -maxdepth 1 -type f -name '*.sh' | sort)
fi

LOCK_HASH="$(sha256sum package-lock.json | awk '{print $1}')"
OLD_HASH=""
[ -f node_modules/.ra2web-lock-hash ] && OLD_HASH="$(cat node_modules/.ra2web-lock-hash)"

if [ ! -d node_modules ] || [ "$LOCK_HASH" != "$OLD_HASH" ]; then
  echo "Installing npm dependencies..."
  npm ci
  printf '%s' "$LOCK_HASH" > node_modules/.ra2web-lock-hash
else
  echo "npm dependencies already up to date."
fi

if [ -d /original-game ]; then
  echo "Original RA2 files mounted:"
  find /original-game -maxdepth 1 -type f -printf '  %f\n' | sort | head -100 || true
else
  echo "WARNING: original-game is not mounted."
fi

exec npm run dev -- --host 0.0.0.0 --port 3000
