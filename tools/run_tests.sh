#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
"$GODOT" --headless --path "$ROOT" --script res://tests/test_runner.gd
"$GODOT" --headless --path "$ROOT" --script res://tests/test_ai_worker.gd
