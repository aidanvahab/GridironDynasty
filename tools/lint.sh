#!/usr/bin/env bash
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://tools/lint.gd 2>&1 | grep -E "LINT FAIL|Parse Error|Compile Error|lint:" | grep -v "Failed to compile depended" | head -60
