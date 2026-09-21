#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
# quit-after only fires if the main loop keeps pumping. A UI-thread AI freeze
# would stall this past the wall timeout.
timeout 12s "$GODOT" --headless --path "$ROOT" \
	res://scenes/main/game.tscn -- --verify-ai --ai-difficulty=hard
echo "live headless boot exited cleanly"
