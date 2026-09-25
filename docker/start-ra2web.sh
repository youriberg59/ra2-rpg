#!/bin/sh
set -eu

cd /app

if [ ! -d /app/public/original-game ]; then
  echo "WARNING: /app/public/original-game is not mounted."
else
  echo "Original RA2 files mounted from host:"
  find /app/public/original-game -maxdepth 1 -type f -printf '  %f\n' | sort | head -100 || true
fi

if [ -d /workspace/patches ]; then
  echo "Patch directory mounted at /workspace/patches"
fi

exec npm run dev -- --host 0.0.0.0 --port 3000
