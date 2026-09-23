#!/usr/bin/env bash
# Headless rules/AI test suites. Exit status is non-zero if any suite fails.
#   ./tools/run_tests.sh                 # everything
#   ./tools/run_tests.sh --suite=ai      # one synchronous suite (english, variants, notation, ai, puzzles)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
status=0
"$GODOT" --headless --path "$ROOT" --script res://tests/test_runner.gd -- "$@" || status=1
if [[ $# -eq 0 ]]; then
	"$GODOT" --headless --path "$ROOT" --script res://tests/test_ai_worker.gd || status=1
	"$GODOT" --headless --path "$ROOT" res://tests/scene_runner.tscn || status=1
fi
if [[ $status -eq 0 ]]; then
	echo "ALL TEST SUITES PASSED"
else
	echo "TEST FAILURES (see above)"
fi
exit $status
