#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT_DIR="$ROOT_DIR/build/web"
mkdir -p "$OUT_DIR"
TARGET_HTML="$OUT_DIR/tribal_village.html"

nim c \
  --app:gui \
  --cpu:wasm32 \
  --os:standalone \
  --threads:off \
  -d:release \
  -d:nimNoDevRandom \
  -d:nimNoGetRandom \
  -d:nimNoSysrand \
  -d:emscripten \
  --passL:"-sUSE_GLFW=3" \
  --passL:"-sUSE_WEBGL2=1" \
  --passL:"-sASYNCIFY" \
  --passL:"-sALLOW_MEMORY_GROWTH" \
  --passL:"-sINITIAL_MEMORY=512MB" \
  --passL:"--shell-file=$ROOT_DIR/../scripts/minshell.html" \
  -o:"$TARGET_HTML" \
  "$ROOT_DIR/tribal_village.nim"

echo "WASM build written to $TARGET_HTML"
