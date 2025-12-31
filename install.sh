#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-.venv}"

echo "==> Setting up Python virtual environment (${VENV_DIR})"
if [ ! -d "$VENV_DIR" ]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

echo "==> Installing Python package (editable)"
python -m ensurepip --upgrade >/dev/null 2>&1 || true
python -m pip install --upgrade pip
python -m pip install -e .

echo "==> Ensuring Nim toolchain + deps + native library"
python - <<'PY'
from tribal_village_env.build import ensure_nim_library_current

lib = ensure_nim_library_current()
print(f"Nim library ready: {lib}")
PY

echo "==> Done. Activate with: source ${VENV_DIR}/bin/activate"
