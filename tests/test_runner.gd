extends SceneTree

const TestCheckersEngineScript := preload("res://tests/test_checkers_engine.gd")


func _initialize() -> void:
	print("Running Shadow Checkers engine tests...")
	var tests = TestCheckersEngineScript.new()
	var ok: bool = tests.run_all()
	quit(0 if ok else 1)
