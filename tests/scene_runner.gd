extends Node

## Scene-based test entry point. Unlike `--script` runs, autoloads exist here,
## so the presentation suite and an end-to-end controller check can run.
## godot --headless --path . res://tests/scene_runner.tscn

const _Presentation := preload("res://tests/test_presentation.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("Running Shadow Checkers presentation tests...")
	var look = _Presentation.new()
	var ok: bool = look.run_all()
	ok = await _controller_flow() and ok
	get_tree().quit(0 if ok else 1)


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  ok    ", name)
	else:
		_failed += 1
		print("  FAIL  ", name)


## Finds a position with a multi-jump by random play, then enters that jump
## hop by hop through the real controller, as a player clicking would.
func _controller_flow() -> bool:
	print("controller")
	SettingsStore.auto_complete = false
	SettingsStore.reduce_motion = true
	var probe := CheckersEngine.new("english")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var target: CheckersMove = null
	var fen := ""
	for attempt in 400:
		probe.set_variant("english")
		for ply in 60:
			var moves := probe.generate_legal_moves()
			if moves.is_empty():
				break
			for m in moves:
				if m.capture_count() >= 2:
					target = m
					break
			if target:
				fen = probe.to_fen()
				break
			probe.apply_move(moves[rng.randi() % moves.size()])
		if target:
			break
	_check("found a multi-jump position", target != null)
	if target == null:
		return false
	GameSession.configure_local(false, "", "english")
	GameSession.pending_fen = fen
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	var c := game.get_node("World") as GameController
	c._select(target.path[0])
	_check("origin selected", c.selected == target.path[0])
	c._extend(target.path[1], false)
	for i in 30:
		await get_tree().process_frame
	_check("first hop is pending, not played", c.engine.history.is_empty() and c.prefix.size() == 2)
	for k in range(2, target.path.size()):
		c._extend(target.path[k], false)
		for i in 30:
			await get_tree().process_frame
	_check("sequence committed as one turn", c.engine.history.size() == 1 and c.engine.history[0].path == target.path)
	_check("captured discs left the board", c.engine.history[0].capture_count() == target.capture_count())
	var typed := c.engine.generate_legal_moves()
	if not typed.is_empty():
		var text := c.engine.notation_for(typed[0])
		for i in 20:
			await get_tree().process_frame
		_check("typed move plays (%s)" % text, c.play_text(text))
		for i in 30:
			await get_tree().process_frame
		_check("typed move recorded", c.engine.history.size() == 2)
	game.queue_free()
	await get_tree().process_frame
	print("Shadow Checkers controller  —  %d passed, %d failed" % [_passed, _failed])
	return _failed == 0
