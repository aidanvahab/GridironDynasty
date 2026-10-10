#!/usr/bin/env bash
# Compile-checks every GDScript file. Exits non-zero if any script fails.
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
out=$("$GODOT" --headless --path . -s res://tools/lint.gd 2>&1)
status=$?
echo "$out" | grep -E "LINT FAIL|Parse Error|Compile Error|lint:" | grep -v "Failed to compile depended" | head -60
exit $status
