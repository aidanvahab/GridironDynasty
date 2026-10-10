#!/usr/bin/env bash
# Refreshes the global class cache, then runs the headless unit tests.
# Usage: tools/test.sh [filter]
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://tests/run_tests.gd -- "$@"
