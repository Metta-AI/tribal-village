#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-.venv}"

if [ -n "${VIRTUAL_ENV:-}" ]; then
  VENV_DIR="$VIRTUAL_ENV"
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "==> uv not found; attempting install..."
  if command -v curl >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  else
    echo "uv is required but curl is missing; please install uv manually." >&2
    exit 1
  fi
fi

echo "==> Setting up Python virtual environment (${VENV_DIR})"
if [ ! -d "$VENV_DIR" ]; then
  uv venv "$VENV_DIR"
fi

# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

echo "==> Installing Python package (editable)"
uv pip install -e . --python "$VENV_DIR/bin/python"

echo "==> Ensuring Nim toolchain + deps + native library"
"$VENV_DIR/bin/python" - <<'PY'
from tribal_village_env.build import ensure_nim_library_current

lib = ensure_nim_library_current()
print(f"Nim library ready: {lib}")
PY

echo "==> Done. Activate with: source ${VENV_DIR}/bin/activate"
