class_name GameController
extends Node3D

signal state_changed
signal game_ended(text: String)

var engine := CheckersEngine.new()
var board: BoardView
var camera_rig: OrbitCamera
var pieces_root: Node3D
var piece_nodes: Dictionary = {}
var selected: int = -1
var legal: Array[CheckersMove] = []
var animating := false
var paused := false
var white_clock: float = 600.0
var black_clock: float = 600.0
var clock_enabled := true
var last_from: int = -1
var last_to: int = -1
var _ai_busy := false
var flipped := false
var hover_sq: int = -1
var _ai_token: int = 0
var _anim_token: int = 0
var _ai_job: CheckersAI.SearchJob
var _ended_emitted := false


func _ready() -> void:
	_build_world()
	_start_from_session()
	rebuild_pieces()
	_hint_forced()
	_refresh_marks()
	state_changed.emit()
	call_deferred("_maybe_ai")


func _process(delta: float) -> void:
	if paused or animating or engine.game_over() or not clock_enabled:
		return
	if engine.side_to_move == CheckersTypes.WHITE:
		white_clock = maxf(white_clock - delta, 0.0)
		if white_clock <= 0.0:
			engine.flag_timeout(CheckersTypes.WHITE)
			_end()
	else:
		black_clock = maxf(black_clock - delta, 0.0)
		if black_clock <= 0.0:
			engine.flag_timeout(CheckersTypes.BLACK)
			_end()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("flip_board"):
		flip_board()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("undo_move"):
		undo()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_hover_at((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_click_at(mb.position)


func is_ai_thinking() -> bool:
	return _ai_busy


func turn_status() -> String:
	if engine.game_over():
		return engine.result_text()
	if _ai_busy:
		return "Shadow is thinking…"
	if engine.must_continue_sq >= 0:
		var who := CheckersTypes.side_name(engine.side_to_move)
		if _is_human_turn():
			return "Keep jumping — %s" % who
		return "%s continues jumping" % who
	if GameSession.mode == GameSession.Mode.AI:
		if _is_human_turn():
			return "Your turn — %s" % CheckersTypes.side_name(engine.side_to_move)
		return "Shadow to move — %s" % CheckersTypes.side_name(engine.side_to_move)
	return "%s to move" % CheckersTypes.side_name(engine.side_to_move)


func _build_world() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.028, 0.032, 0.042)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.40, 0.50)
	env.ambient_light_energy = 0.48
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.08
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_bloom = 0.06
	env.ssao_enabled = SettingsStore.graphics_quality != "low"
	env.ssil_enabled = SettingsStore.graphics_quality == "high"
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env_node.environment = env
	add_child(env_node)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.93, 0.84)
	key.light_energy = 1.45
	key.shadow_enabled = SettingsStore.graphics_quality != "low"
	key.directional_shadow_max_distance = 28.0
	key.rotation_degrees = Vector3(-50, -32, 0)
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.42, 0.68, 0.88)
	fill.light_energy = 0.38
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-18, 148, 0)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.50, 0.88, 0.98)
	rim.light_energy = 1.85
	rim.omni_range = 15.0
	rim.position = Vector3(-6.2, 5.2, -5.2)
	add_child(rim)
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.72, 0.42)
	warm.light_energy = 0.85
	warm.omni_range = 12.0
	warm.position = Vector3(5.4, 3.6, 4.8)
	add_child(warm)
	board = BoardView.new()
	add_child(board)
	pieces_root = Node3D.new()
	pieces_root.name = "Pieces"
	add_child(pieces_root)
	camera_rig = OrbitCamera.new()
	add_child(camera_rig)


func _start_from_session() -> void:
	clock_enabled = GameSession.clock_seconds > 0
	white_clock = float(GameSession.clock_seconds)
	black_clock = float(GameSession.clock_seconds)
	if GameSession.load_path != "":
		var data := SaveManager.load_game(GameSession.load_path)
		SaveManager.apply_to_engine(engine, data)
		var clock: Dictionary = data.get("clock", {})
		if clock.has("white"):
			white_clock = float(clock["white"])
		if clock.has("black"):
			black_clock = float(clock["black"])
		clock_enabled = bool(clock.get("enabled", clock_enabled))
		if str(data.get("mode", "local")) == "ai":
			GameSession.mode = GameSession.Mode.AI
			GameSession.ai_side = int(data.get("ai_side", CheckersTypes.WHITE))
	elif GameSession.pending_fen != "":
		engine.from_fen(GameSession.pending_fen)
	else:
		engine.reset()
	_apply_orientation()


func rebuild_pieces() -> void:
	for c in pieces_root.get_children():
		if c is PieceView:
			(c as PieceView).kill_motion()
		c.queue_free()
	piece_nodes.clear()
	for sq in 64:
		var p := engine.piece_at(sq)
		if p == 0:
			continue
		_spawn(sq, CheckersTypes.ptype(p), CheckersTypes.pcolor(p))


func _spawn(sq: int, type: int, color: int) -> PieceView:
	var pv := PieceView.new()
	pv.setup(type, color, sq)
	pv.position = board.square_to_world(sq)
	pieces_root.add_child(pv)
	piece_nodes[sq] = pv
	return pv


func _hover_at(screen: Vector2) -> void:
	if paused or animating or engine.game_over() or _ai_busy or not _is_human_turn():
		if hover_sq >= 0:
			hover_sq = -1
			_refresh_marks()
		_set_piece_hover(-1)
		return
	var hit := _pick(screen)
	if hit == hover_sq:
		return
	hover_sq = hit
	_set_piece_hover(hit)
	_refresh_marks()


func _set_piece_hover(sq: int) -> void:
	for key in piece_nodes.keys():
		var pv: PieceView = piece_nodes[key]
		if is_instance_valid(pv):
			pv.set_hovered(int(key) == sq and sq != selected)


func _click_at(screen: Vector2) -> void:
	if paused or animating or engine.game_over() or _ai_busy:
		return
	if not _is_human_turn():
		return
	var hit := _pick(screen)
	if hit < 0:
		if engine.must_continue_sq < 0:
			_deselect()
		return
	var p := engine.piece_at(hit)
	if selected >= 0:
		if hit == selected:
			if engine.must_continue_sq < 0:
				_deselect()
			return
		if _try_play(selected, hit):
			return
		if engine.must_continue_sq >= 0:
			return
		if p != 0 and CheckersTypes.pcolor(p) == engine.side_to_move:
			_select(hit)
			return
		_deselect()
		return
	if p != 0 and CheckersTypes.pcolor(p) == engine.side_to_move:
		if engine.must_continue_sq >= 0 and hit != engine.must_continue_sq:
			return
		_select(hit)
		return
	var dest := engine.unique_move_to(hit)
	if dest:
		_apply_and_animate(dest)


func _try_play(from_sq: int, to_sq: int) -> bool:
	var m := engine.find_move(from_sq, to_sq)
	if m == null:
		return false
	_apply_and_animate(m)
	return true


func _apply_and_animate(m: CheckersMove) -> void:
	var applied := engine.apply_move(m)
	if applied == null:
		return
	last_from = m.from_sq
	last_to = m.to_sq
	if piece_nodes.has(m.from_sq):
		piece_nodes[m.from_sq].kill_motion()
	animating = true
	_anim_token += 1
	var token := _anim_token
	var finished := false
	var finish := func():
		if finished or token != _anim_token or not is_instance_valid(self):
			return
		finished = true
		animating = false
		if engine.must_continue_sq >= 0:
			_select(engine.must_continue_sq)
		else:
			_deselect()
			_hint_forced()
		_refresh_marks()
		state_changed.emit()
		if engine.game_over():
			_end()
		else:
			_maybe_ai()
	_animate_move(applied, finish)
	var dur := 0.30 / maxf(SettingsStore.animation_speed, 0.25)
	get_tree().create_timer(maxf(dur * 4.0, 1.4)).timeout.connect(func():
		if not finished and token == _anim_token:
			finish.call()
	)


func _animate_move(m: CheckersMove, done: Callable) -> void:
	var dur := 0.30 / maxf(SettingsStore.animation_speed, 0.25)
	var mover: PieceView = piece_nodes.get(m.from_sq, null)
	if mover == null or not is_instance_valid(mover):
		rebuild_pieces()
		done.call()
		return
	piece_nodes.erase(m.from_sq)
	if m.is_capture() and piece_nodes.has(m.captured_sq):
		_fade_out(piece_nodes[m.captured_sq], dur * 0.75)
		piece_nodes.erase(m.captured_sq)
	var dest := board.square_to_world(m.to_sq)
	var mid := (mover.position + dest) * 0.5 + Vector3.UP * (0.78 if m.is_capture() else 0.46)
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(mover, "position", mid, dur * 0.45)
	tw.tween_property(mover, "position", dest, dur * 0.55)
	mover.set_square(m.to_sq)
	piece_nodes[m.to_sq] = mover
	if m.is_promotion():
		tw.tween_callback(func():
			if is_instance_valid(mover):
				mover.become_king()
			AudioManager.play("king")
		)
	tw.tween_callback(done)
	if m.is_capture():
		AudioManager.play("capture" if m.ended_turn else "multi")
	else:
		AudioManager.play("move")


func _fade_out(node: Node3D, dur: float) -> void:
	if node is PieceView:
		(node as PieceView).kill_motion()
	var tw := create_tween()
	tw.tween_property(node, "position:y", node.position.y - 0.18, dur)
	tw.parallel().tween_property(node, "scale", Vector3(0.18, 0.18, 0.18), dur)
	tw.tween_callback(node.queue_free)


func _select(sq: int) -> void:
	if selected >= 0 and piece_nodes.has(selected) and is_instance_valid(piece_nodes[selected]):
		piece_nodes[selected].set_selected(false)
	selected = sq
	legal = engine.generate_legal_from(sq)
	if piece_nodes.has(sq) and is_instance_valid(piece_nodes[sq]):
		piece_nodes[sq].set_selected(true)
	_refresh_marks()
	state_changed.emit()


func _deselect() -> void:
	if selected >= 0 and piece_nodes.has(selected) and is_instance_valid(piece_nodes[selected]):
		piece_nodes[selected].set_selected(false)
	selected = -1
	legal.clear()
	_refresh_marks()
	state_changed.emit()


func _refresh_marks() -> void:
	if board == null:
		return
	board.clear_highlights()
	if last_from >= 0:
		board.show_highlight(last_from, "last")
	if last_to >= 0:
		board.show_highlight(last_to, "last")
	if selected < 0 and not engine.game_over() and _is_human_turn() and not _ai_busy:
		for sq in engine.movable_squares():
			board.show_highlight(sq, "movable")
	if engine.must_continue_sq >= 0:
		board.show_highlight(engine.must_continue_sq, "continue")
	if selected >= 0:
		board.show_highlight(selected, "select")
		if SettingsStore.show_legal_moves:
			for m in legal:
				board.show_highlight(m.to_sq, "capture" if m.is_capture() else "legal")
	if hover_sq >= 0:
		board.show_hover(hover_sq)


func _pick(screen: Vector2) -> int:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen)
	var to := from + cam.project_ray_normal(screen) * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 | 2
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return -1
	var collider: Object = hit.get("collider")
	if collider is StaticBody3D:
		var body := collider as StaticBody3D
		if body.has_meta("square"):
			return int(body.get_meta("square"))
		var parent := body.get_parent()
		if parent and parent.get_parent() is PieceView:
			return (parent.get_parent() as PieceView).square
		if parent is PieceView:
			return (parent as PieceView).square
	return -1


func _is_ai_turn() -> bool:
	return GameSession.mode == GameSession.Mode.AI and engine.side_to_move == GameSession.ai_side


func _is_human_turn() -> bool:
	return not _is_ai_turn()


func _hint_forced() -> void:
	if not _is_human_turn() or engine.game_over():
		return
	var squares := engine.movable_squares()
	if squares.size() == 1:
		_select(squares[0])


func _cancel_ai() -> void:
	_ai_token += 1
	_ai_busy = false
	_ai_job = null


func _maybe_ai() -> void:
	if not _is_ai_turn() or engine.game_over() or paused:
		return
	_ai_token += 1
	var token := _ai_token
	_ai_busy = true
	_ended_emitted = false
	state_changed.emit()
	await get_tree().process_frame
	if not is_instance_valid(self) or token != _ai_token:
		return
	await get_tree().create_timer(0.16).timeout
	if not is_instance_valid(self) or token != _ai_token:
		return
	if paused or engine.game_over() or not _is_ai_turn():
		if token == _ai_token:
			_ai_busy = false
			state_changed.emit()
		return
	var job := CheckersAI.SearchJob.new()
	job.fen = engine.to_fen()
	job.difficulty = SettingsStore.ai_difficulty
	_ai_job = job
	var task_id := WorkerThreadPool.add_task(Callable(job, "run"), true, "shadow-checkers-ai")
	while not WorkerThreadPool.is_task_completed(task_id):
		await get_tree().process_frame
		if not is_instance_valid(self) or token != _ai_token:
			return
	WorkerThreadPool.wait_for_task_completion(task_id)
	if not is_instance_valid(self) or token != _ai_token:
		return
	_ai_busy = false
	_ai_job = null
	var move := engine.find_uci(job.move_uci)
	if move == null:
		var legal_now := engine.generate_legal_moves()
		if not legal_now.is_empty():
			move = legal_now[0]
	if move:
		_apply_and_animate(move)
		_maybe_quit_verify()
	else:
		state_changed.emit()
		if engine.game_over():
			_end()


func _maybe_quit_verify() -> void:
	if not OS.get_cmdline_user_args().has("--verify-ai"):
		return
	print("VERIFY  AI move applied, status=", turn_status(), " history=", engine.history.size())
	get_tree().create_timer(0.35).timeout.connect(func():
		if is_instance_valid(self) and get_tree():
			print("VERIFY  ok")
			get_tree().quit(0)
	)


func undo() -> void:
	if animating or _ai_busy:
		return
	if not engine.can_undo():
		return
	_ended_emitted = false
	engine.undo_turn()
	if GameSession.mode == GameSession.Mode.AI and engine.can_undo() and engine.side_to_move != GameSession.ai_side:
		engine.undo_turn()
	if engine.history.is_empty():
		last_from = -1
		last_to = -1
	else:
		var last: CheckersMove = engine.history[engine.history.size() - 1]
		last_from = last.from_sq
		last_to = last.to_sq
	rebuild_pieces()
	if engine.must_continue_sq >= 0:
		_select(engine.must_continue_sq)
	else:
		_deselect()
	state_changed.emit()


func redo() -> void:
	if animating or _ai_busy:
		return
	if not engine.can_redo():
		return
	engine.redo_turn()
	if not engine.history.is_empty():
		var last: CheckersMove = engine.history[engine.history.size() - 1]
		last_from = last.from_sq
		last_to = last.to_sq
	rebuild_pieces()
	_refresh_marks()
	state_changed.emit()
	_maybe_ai()


func restart() -> void:
	_cancel_ai()
	_anim_token += 1
	animating = false
	_ended_emitted = false
	engine.reset()
	last_from = -1
	last_to = -1
	hover_sq = -1
	white_clock = float(GameSession.clock_seconds)
	black_clock = float(GameSession.clock_seconds)
	rebuild_pieces()
	_deselect()
	state_changed.emit()
	_maybe_ai()


func resign() -> void:
	if engine.game_over():
		return
	_cancel_ai()
	var side := engine.side_to_move
	if GameSession.mode == GameSession.Mode.AI:
		side = CheckersTypes.opp(GameSession.ai_side)
	engine.resign(side)
	_end()


func flip_board() -> void:
	flipped = not flipped
	camera_rig.face_side(not flipped)


func _apply_orientation() -> void:
	var orient := SettingsStore.board_orientation
	var white_side := true
	if orient == "black":
		white_side = false
	elif orient == "auto" and GameSession.mode == GameSession.Mode.AI:
		white_side = GameSession.ai_side == CheckersTypes.BLACK
	flipped = not white_side
	camera_rig.reset_view(white_side)


func save_now() -> String:
	return SaveManager.save_game(engine, {
		"mode": "ai" if GameSession.mode == GameSession.Mode.AI else "local",
		"ai_side": GameSession.ai_side,
		"ai_difficulty": SettingsStore.ai_difficulty,
		"white_name": GameSession.white_name,
		"black_name": GameSession.black_name,
		"clock": {
			"white": white_clock,
			"black": black_clock,
			"enabled": clock_enabled,
		},
	})


func export_fen() -> String:
	return engine.to_fen()


func _end() -> void:
	_ai_busy = false
	state_changed.emit()
	if _ended_emitted:
		return
	_ended_emitted = true
	game_ended.emit(engine.result_text())
	if engine.result == CheckersEngine.Result.NO_MOVES or engine.result == CheckersEngine.Result.NO_PIECES:
		AudioManager.play("win")
	elif engine.result == CheckersEngine.Result.DRAW_40_MOVE or engine.result == CheckersEngine.Result.DRAW_REPETITION or engine.result == CheckersEngine.Result.DRAW_AGREED:
		AudioManager.play("ui")
