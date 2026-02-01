#!/usr/bin/env bash
# Install git hooks for tribal-village development
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts"

# Get the actual git directory (handles worktrees)
GIT_DIR="$(git -C "$ROOT_DIR" rev-parse --git-dir)"

# Resolve to absolute path
if [[ ! "$GIT_DIR" = /* ]]; then
    GIT_DIR="$ROOT_DIR/$GIT_DIR"
fi

HOOKS_DIR="$GIT_DIR/hooks"

echo "==> Installing git hooks to $HOOKS_DIR"

# Install pre-commit hook
if [ -f "$SCRIPT_DIR/pre-commit" ]; then
    cp "$SCRIPT_DIR/pre-commit" "$HOOKS_DIR/pre-commit"
    chmod +x "$HOOKS_DIR/pre-commit"
    echo "    Installed pre-commit hook"
fi

echo "==> Git hooks installed successfully"
