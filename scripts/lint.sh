#!/usr/bin/env bash
# scripts/lint.sh — Run luacheck on the codebase.
#
# Usage:
#   ./scripts/lint.sh          # lint everything
#   ./scripts/lint.sh --quiet  # less verbose
#
# Install: luarocks install luacheck

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v luacheck &>/dev/null; then
    echo "Error: luacheck not found."
    echo "Install with: luarocks install luacheck"
    exit 1
fi

echo "Running luacheck..."
luacheck lua/ tests/ plugin/ "$@"
echo "✓ luacheck passed"
