#!/usr/bin/env bash
# scripts/test.sh — Run the waymark.nvim test suite.
#
# Usage:
#   ./scripts/test.sh              # run all tests
#   ./scripts/test.sh test_config  # run only tests/test_config.lua
#
# Requires: nvim (headless), plenary.nvim (auto-bootstrapped)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Determine which test files to run
if [ $# -gt 0 ]; then
    # Run specific test file(s)
    TEST_FILES=()
    for arg in "$@"; do
        # Allow both "test_config" and "tests/test_config.lua"
        if [[ "$arg" == tests/* ]]; then
            TEST_FILES+=("$arg")
        elif [[ "$arg" == *.lua ]]; then
            TEST_FILES+=("tests/$arg")
        else
            TEST_FILES+=("tests/${arg}.lua")
        fi
    done
else
    # Run all test files
    TEST_FILES=(tests/test_*.lua)
fi

PASSED=0
FAILED=0
ERRORS=()

for test_file in "${TEST_FILES[@]}"; do
    if [ ! -f "$test_file" ]; then
        echo "⚠  File not found: $test_file"
        FAILED=$((FAILED + 1))
        ERRORS+=("$test_file (not found)")
        continue
    fi

    echo "━━━ Running: $test_file ━━━"

    if nvim --headless --noplugin -u tests/minimal_init.lua \
        -c "PlenaryBustedFile $test_file" 2>&1; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        ERRORS+=("$test_file")
    fi
    echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASSED passed, $FAILED failed (${#TEST_FILES[@]} files)"

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "Failed:"
    for err in "${ERRORS[@]}"; do
        echo "  ✗ $err"
    done
    exit 1
fi
