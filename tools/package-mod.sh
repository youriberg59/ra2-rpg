#!/bin/sh
set -eu

MOD_DIR="/workspace/mod"
DIST_DIR="/workspace/dist"
OUT="$DIST_DIR/ra2-rpg.zip"

mkdir -p "$DIST_DIR"
rm -f "$OUT"

cd "$MOD_DIR"
zip -r "$OUT" . -x "*.DS_Store"

echo "Created $OUT"
