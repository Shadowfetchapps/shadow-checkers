extends SceneTree

## Headless test runner: godot --headless --path . --script res://tests/test_runner.gd
## Optional user arg "-- --suite=<name>" runs one suite (english, variants,
## notation, ai, puzzles).

const SUITES := [
	["english", "res://tests/test_checkers_engine.gd"],
	["variants", "res://tests/test_variants.gd"],
	["notation", "res://tests/test_notation.gd"],
	["ai", "res://tests/test_ai.gd"],
	["puzzles", "res://tests/test_puzzles.gd"],
]


func _initialize() -> void:
	print("Running Shadow Checkers rules/AI tests...")
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--suite="):
			only = a.substr(8)
	var passed := 0
	var failed := 0
	var errors := PackedStringArray()
	var t0 := Time.get_ticks_msec()
	for s in SUITES:
		if not only.is_empty() and s[0] != only:
			continue
		var ts := Time.get_ticks_msec()
		var suite = load(s[1]).new()
		suite.run_all()
		passed += suite.passed
		failed += suite.failed
		errors.append_array(suite.errors)
		print("  -- %s: %d passed, %d failed (%d ms)" % [s[0], suite.passed, suite.failed, Time.get_ticks_msec() - ts])
	print("\n==============================")
	print("Shadow Checkers  —  %d passed, %d failed  (%d ms)" % [passed, failed, Time.get_ticks_msec() - t0])
	for e in errors:
		print("  FAIL  ", e)
	print("==============================\n")
	quit(0 if failed == 0 else 1)
