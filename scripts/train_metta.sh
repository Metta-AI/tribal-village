#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METTA_DIR="${METTA_DIR:-$ROOT_DIR/metta}"

if [ ! -d "$METTA_DIR" ]; then
  echo "Metta repo not found at $METTA_DIR. Set METTA_DIR to the metta checkout." >&2
  exit 1
fi

: "${TRIBAL_VECTOR_BACKEND:=serial}"
export TRIBAL_VECTOR_BACKEND

# Resolve symlinks so uv workspace-relative paths stay correct.
METTA_DIR="$(cd "$METTA_DIR" && pwd -P)"

exec uv run --project "$METTA_DIR" --extra tribal-village python -m tribal_village_env.cli train "$@"
