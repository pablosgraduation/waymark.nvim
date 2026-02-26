#!/usr/bin/env bash
# scripts/format.sh — Format Lua files with StyLua.
#
# Usage:
#   ./scripts/format.sh          # format in-place
#   ./scripts/format.sh --check  # check only (CI mode, exits non-zero if unformatted)
#
# Install: cargo install stylua
#   or:    brew install stylua

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v stylua &>/dev/null; then
    echo "Error: stylua not found."
    echo "Install with: cargo install stylua"
    echo "         or:  brew install stylua"
    exit 1
fi

echo "Running stylua..."
stylua lua/ tests/ plugin/ "$@"
echo "✓ stylua done"
