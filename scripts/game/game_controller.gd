class_name GameController
extends Node3D

## Owns the live game: rules engine, 3D board and discs, input (click, drag,
## and click-by-click multi-jumps), animation, clocks, Shadow's threaded
## search, evaluation, hints, history review, puzzles, and autosave.

signal state_changed
signal move_played(move: CheckersMove)
signal game_finished(info: Dictionary)
signal thinking_changed(on: bool)
signal eval_updated(white_score: int, win_white: int, depth: int, pv_text: String)
signal hint_shown(text: String)
signal view_changed(ply: int, live: bool)
signal toast(text: String, kind: String)
signal puzzle_event(kind: String, text: String)
signal clock_low(side: int)

const DRAG_THRESHOLD := 7.0
const DRAG_LIFT := 0.36

class FuncJob:
	extends RefCounted
	var fn: Callable
	var result: Variant
	func run() -> void:
		result = fn.call()

var engine := CheckersEngine.new()
var board: BoardView
var camera_rig: OrbitCamera
var clock_prop: GameClockProp
var pieces_root: Node3D
var piece_nodes: Dictionary = {}
var tray_nodes: Array[PieceView] = []

var selected := -1
var prefix := PackedInt32Array()
var animating := false
var paused := false
var view_ply := 0
var clock_enabled := false
var clock_base := 0
var clock_increment := 0
var clocks: Array[float] = [0.0, 0.0]
var last_eval := {"score": 0, "win": 0, "depth": 0, "ply": -1, "pv": ""}

var _world_env: WorldEnvironment
var _lights: Dictionary = {}
var _ai_job: CheckersAI.SearchJob
var _ai_task := -1
var _ai_started_ms := 0
var _ai_min_ms := 0
var _eval_job: CheckersAI.SearchJob
var _eval_task := -1
var _eval_ply := -1
var _eval_dirty := false
var _hint_job: CheckersAI.SearchJob
var _hint_task := -1
var _func_job: FuncJob
var _func_task := -1
var _func_done: Callable

var _press_pos := Vector2.ZERO
var _press_sq := -1
var _press_was_selected := false
var _mouse_down := false
var _dragging := false
var _drag_piece: PieceView
var _hover_sq := -1
var _ghosts: Array[PieceView] = []
var _drop_hop := false
var _ended := false
var _recorded := false
var _low_warned: Array[bool] = [false, false]
var _last_tick := -1
var _view_cache: Dictionary = {}

var _puzzle_plies_left := 0
var _puzzle_step := 0
var _puzzle_clean := true
var _puzzle_solved := false
var _puzzle_on_line := true


func _ready() -> void:
	MaterialLibrary.apply_theme(SettingsStore.board_theme, SettingsStore.piece_style)
	MaterialLibrary.set_high_contrast(SettingsStore.high_contrast)
	CheckersAI.warmup()
	_build_world()
	_start_from_session()
	view_ply = engine.history.size()
	rebuild_pieces()
	_refresh_marks()
	SettingsStore.settings_changed.connect(_on_settings_changed)
	state_changed.emit()
	AudioManager.play("game_start")
	call_deferred("_after_start")


func _after_start() -> void:
	if engine.game_over():
		_finish()
		return
	_maybe_ai()
	_request_eval()


func _exit_tree() -> void:
	_cancel_ai()
	_cancel_task("eval")
	_cancel_task("hint")
	_cancel_task("func")
	if not _ended and GameSession.mode != GameSession.Mode.PUZZLE and not engine.history.is_empty():
		SaveManager.save_game(snapshot(), SaveManager.autosave_path())


# --- World ------------------------------------------------------------------------------

func _build_world() -> void:
	_world_env = WorldEnvironment.new()
	_world_env.environment = WorldLook.make_environment()
	add_child(_world_env)
	_lights = WorldLook.add_lights(self)
	var club := ClubBuilder.build(self, true)
	clock_prop = club.get_node_or_null("Clock") as GameClockProp
	board = BoardView.new()
	board.name = "Board"
	add_child(board)
	pieces_root = Node3D.new()
	pieces_root.name = "Pieces"
	add_child(pieces_root)
	camera_rig = OrbitCamera.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.view_changed.connect(func(): board.set_white_bottom(camera_rig.is_white_bottom()); state_changed.emit())


func _start_from_session() -> void:
	clock_base = GameSession.clock_base
	clock_increment = GameSession.clock_increment
	clock_enabled = clock_base > 0 and GameSession.mode in [GameSession.Mode.LOCAL, GameSession.Mode.AI]
	clocks = [float(clock_base), float(clock_base)]
	engine.set_variant(GameSession.variant)
	if GameSession.load_path != "":
		var data := SaveManager.load_game(GameSession.load_path)
		var ok := not data.is_empty()
		if ok:
			_apply_save_meta(data)
			ok = SaveManager.apply_to_engine(engine, data)
		if not ok:
			engine.set_variant(GameSession.variant)
			call_deferred("_emit_toast", "That save could not be read. Started a new game.", "error")
	elif GameSession.pending_pdn != "":
		var res := CheckersPdn.import_game(GameSession.pending_pdn)
		if bool(res.get("ok", false)):
			engine = res["engine"]
			GameSession.variant = engine.variant
			var h: Dictionary = res.get("headers", {})
			GameSession.white_name = str(h.get("White", "White"))
			GameSession.black_name = str(h.get("Black", "Black"))
		else:
			call_deferred("_emit_toast", "PDN import failed: %s" % res.get("error", "unknown error"), "error")
	elif GameSession.pending_fen != "":
		if not engine.from_fen(GameSession.pending_fen):
			engine.set_variant(GameSession.variant)
			call_deferred("_emit_toast", "That position could not be read.", "error")
	if GameSession.mode == GameSession.Mode.PUZZLE:
		_puzzle_plies_left = int(GameSession.puzzle.get("plies", 1))
	var white_bottom := true
	if GameSession.mode in [GameSession.Mode.AI, GameSession.Mode.PUZZLE]:
		white_bottom = GameSession.ai_side == CheckersTypes.BLACK
	camera_rig.reset_view(white_bottom, true)
	board.set_white_bottom(white_bottom)


func _apply_save_meta(data: Dictionary) -> void:
	var mode := str(data.get("mode", "local"))
	GameSession.mode = {"ai": GameSession.Mode.AI, "analysis": GameSession.Mode.ANALYSIS}.get(mode, GameSession.Mode.LOCAL)
	GameSession.variant = str(data.get("variant", "english"))
	GameSession.ai_side = int(data.get("ai_side", CheckersTypes.WHITE))
	GameSession.ai_level = str(data.get("ai_level", SettingsStore.ai_level))
	GameSession.white_name = str(data.get("white_name", "White"))
	GameSession.black_name = str(data.get("black_name", "Black"))
	var c: Dictionary = data.get("clock", {})
	clock_base = int(c.get("base", 0))
	clock_increment = int(c.get("increment", 0))
	clock_enabled = bool(c.get("enabled", false)) and clock_base > 0
	clocks = [float(c.get("white", clock_base)), float(c.get("black", clock_base))]
	GameSession.clock_base = clock_base
	GameSession.clock_increment = clock_increment


func _emit_toast(text: String, kind: String) -> void:
	toast.emit(text, kind)


# --- Frame loop ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_tick_clocks(delta)
	_poll_ai()
	_poll_eval()
	_poll_hint()
	_poll_func()
	if clock_prop:
		clock_prop.set_times(clocks[0], clocks[1], engine.side_to_move if _clocks_running() else -1, clock_enabled)


func _clocks_running() -> bool:
	return clock_enabled and not paused and not engine.game_over() and engine.history.size() >= 2


func _tick_clocks(delta: float) -> void:
	if not _clocks_running() or animating:
		return
	var side := engine.side_to_move
	clocks[side] = maxf(clocks[side] - delta, 0.0)
	var human := _is_human(side)
	if clocks[side] <= 10.0 and not _low_warned[side]:
		_low_warned[side] = true
		clock_low.emit(side)
		if human:
			AudioManager.play("clock_warning")
	if human and clocks[side] <= 10.0:
		var s := int(ceil(clocks[side]))
		if s != _last_tick:
			_last_tick = s
			AudioManager.play("clock_tick")
	if clocks[side] <= 0.0:
		_cancel_ai()
		engine.flag_timeout(side)
		_finish()


# --- Input -----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_mouse_motion((event as InputEventMouseMotion).position)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_press(mb.position)
			else:
				_on_release(mb.position)
		return
	if paused:
		return
	if event.is_action_pressed("cancel_sequence") and prefix.size() > 1:
		_reset_partial(true)
	elif event.is_action_pressed("flip_board"):
		flip_board()
	elif event.is_action_pressed("redo_move"):
		redo()
	elif event.is_action_pressed("undo_move"):
		undo()
	elif event.is_action_pressed("hint"):
		request_hint()
	elif event.is_action_pressed("review_prev"):
		step_view(-1)
	elif event.is_action_pressed("review_next"):
		step_view(1)
	elif event.is_action_pressed("review_first"):
		set_view_ply(0)
	elif event.is_action_pressed("review_last"):
		set_view_ply(engine.history.size())
	else:
		return
	get_viewport().set_input_as_handled()


func can_interact() -> bool:
	if paused or animating or _ai_task >= 0 or _func_task >= 0:
		return false
	if engine.game_over() and GameSession.mode != GameSession.Mode.ANALYSIS:
		return false
	if GameSession.mode == GameSession.Mode.PUZZLE and _puzzle_solved:
		return false
	if not is_live() and GameSession.mode != GameSession.Mode.ANALYSIS:
		return false
	return _is_human(_view_engine().side_to_move)


func _on_press(screen: Vector2) -> void:
	_mouse_down = true
	_press_pos = screen
	_press_sq = -1
	if not is_live() and GameSession.mode != GameSession.Mode.ANALYSIS and not animating:
		set_view_ply(engine.history.size())
		return
	if not can_interact():
		if not paused and not animating and _ai_task < 0 and not engine.game_over():
			AudioManager.play("illegal")
		return
	var hit := _pick(screen, 1 | 2)
	if hit < 0:
		if prefix.size() <= 1:
			_deselect()
		return
	if selected >= 0 and hit in _landings():
		_extend(hit, false)
		return
	var pos := _view_engine()
	if hit in pos.movable_squares() and (prefix.size() <= 1 or hit == prefix[0]):
		if prefix.size() > 1:
			_reset_partial(false)
		_press_was_selected = hit == selected
		_press_sq = hit
		if hit != selected:
			_select(hit)
		return
	var p := pos.piece_at(hit)
	if p != 0 and CheckersTypes.pcolor(p) == pos.side_to_move and prefix.size() <= 1:
		AudioManager.play("illegal")
		if pos.must_capture():
			toast.emit("A capture is available — you must take it.", "info")
		return
	if selected >= 0:
		AudioManager.play("illegal")


func _on_release(screen: Vector2) -> void:
	_mouse_down = false
	if _dragging:
		_finish_drag(screen)
		return
	if _press_sq >= 0 and _press_sq == selected and _press_was_selected and prefix.size() <= 1 and screen.distance_to(_press_pos) < DRAG_THRESHOLD:
		_deselect()
	_press_sq = -1


func _on_mouse_motion(screen: Vector2) -> void:
	if _mouse_down and _press_sq >= 0 and not _dragging and screen.distance_to(_press_pos) >= DRAG_THRESHOLD and can_interact():
		var pv: PieceView = piece_nodes.get(_press_sq)
		if pv:
			_dragging = true
			_drag_piece = pv
			pv.set_selected(false)
			pv.set_dragging(true)
			AudioManager.play("select")
	if _dragging and is_instance_valid(_drag_piece):
		var p := _ray_plane(screen, BoardView.TOP_Y + DRAG_LIFT)
		if p != Vector3.INF:
			p.x = clampf(p.x, -5.2, 5.2)
			p.z = clampf(p.z, -5.2, 5.2)
			_drag_piece.position = _drag_piece.position.lerp(p, 0.65)
		_set_hover(_pick(screen, 1))
		return
	if not can_interact():
		_set_hover(-1)
		return
	_set_hover(_pick(screen, 1 | 2))


func _finish_drag(screen: Vector2) -> void:
	_dragging = false
	var pv := _drag_piece
	_drag_piece = null
	_press_sq = -1
	var to := _pick(screen, 1)
	if is_instance_valid(pv):
		pv.set_dragging(false)
	if to >= 0 and to in _landings():
		_extend(to, true)
		return
	if is_instance_valid(pv):
		var home := board.square_to_world(pv.square)
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(pv, "position", home, 0.18)
		if to >= 0 and to != pv.square:
			AudioManager.play("illegal")
	if selected >= 0:
		_select(selected)


func _set_hover(sq: int) -> void:
	if sq == _hover_sq:
		return
	if _hover_sq >= 0 and piece_nodes.has(_hover_sq):
		(piece_nodes[_hover_sq] as PieceView).set_hovered(false)
	_hover_sq = sq
	board.show_hover(sq)
	if sq >= 0 and piece_nodes.has(sq) and not _dragging and can_interact() and prefix.size() <= 1:
		if sq in _view_engine().movable_squares():
			(piece_nodes[sq] as PieceView).set_hovered(true)


func _landings() -> PackedInt32Array:
	if selected < 0 or prefix.is_empty():
		return PackedInt32Array()
	return _view_engine().next_landings(prefix)


## Adds a landing square to the move being entered. Completes the move when
## the path is a full legal move, or auto-completes a forced remainder.
func _extend(landing: int, dragged: bool) -> void:
	var pos := _view_engine()
	var before := prefix.size()
	prefix.append(landing)
	var cands := pos.candidates_for_prefix(prefix)
	if cands.is_empty():
		prefix.resize(before)
		AudioManager.play("illegal")
		return
	var complete := _complete_in(cands)
	if complete == null and SettingsStore.auto_complete:
		while complete == null:
			var nexts := pos.next_landings(prefix)
			if nexts.size() != 1:
				break
			prefix.append(nexts[0])
			cands = pos.candidates_for_prefix(prefix)
			complete = _complete_in(cands)
		if complete == null and cands.size() == 1:
			complete = cands[0]
	if complete:
		_submit(complete, before - 1, dragged)
		return
	# Partial multi-jump: show the hop(s) now and wait for the next landing.
	_animate_partial(cands[0], before - 1, prefix.size() - 1, dragged)


## Plays a move typed in PDN numbers ("11-15", "22x15x6") or squares ("c3d4").
func play_text(text: String) -> bool:
	var t := text.strip_edges()
	if t.is_empty():
		return false
	if not can_interact():
		toast.emit("It isn't your move.", "info")
		return false
	var m := _view_engine().find_uci(t)
	if m == null:
		AudioManager.play("illegal")
		toast.emit("“%s” isn't a legal move here." % t, "error")
		return false
	if prefix.size() > 1:
		_reset_partial(false)
	_deselect(false)
	_submit(m, 0)
	return true


func _complete_in(cands: Array[CheckersMove]) -> CheckersMove:
	for c in cands:
		if c.path.size() == prefix.size():
			return c
	return null


func _reset_partial(reselect: bool) -> void:
	var origin := prefix[0] if prefix.size() > 0 else -1
	prefix = PackedInt32Array()
	selected = -1
	_ghosts.clear()
	rebuild_pieces()
	if reselect and origin >= 0:
		_select(origin)
	else:
		_refresh_marks()


# --- Playing moves ---------------------------------------------------------------------------

## `hops_done` = number of hops of `m` already shown on the board; `dragged`
## means the disc was dropped on the next landing by hand.
func _submit(m: CheckersMove, hops_done: int, dragged: bool = false) -> void:
	_drop_hop = dragged
	if GameSession.mode == GameSession.Mode.PUZZLE:
		_puzzle_submit(m, hops_done)
		return
	if not is_live():
		_truncate_to_view()
	ProfileStore.record_moves(1)
	_play(m, hops_done)


func _truncate_to_view() -> void:
	while engine.history.size() > view_ply:
		engine.undo()
	engine.redo_stack.clear()
	_view_cache.clear()
	_ended = false


func _play(m: CheckersMove, hops_done: int = 0, after: Callable = Callable()) -> void:
	var mover_side := engine.side_to_move
	var applied := engine.apply_move(m)
	if applied == null:
		_reset_partial(false)
		return
	if clock_enabled and engine.history.size() > 2:
		clocks[mover_side] += float(clock_increment)
	if clocks[mover_side] > 10.0:
		_low_warned[mover_side] = false
	view_ply = engine.history.size()
	_view_cache.clear()
	prefix = PackedInt32Array()
	selected = -1
	board.clear_arrows()
	board.clear_highlights()
	animating = true
	_animate_move(applied, maxi(hops_done, 0), func():
		animating = false
		_refresh_marks()
		move_played.emit(applied)
		state_changed.emit()
		view_changed.emit(view_ply, true)
		if GameSession.mode != GameSession.Mode.PUZZLE:
			SaveManager.save_game(snapshot(), SaveManager.autosave_path())
		if after.is_valid():
			after.call()
			return
		if engine.game_over():
			_finish()
		else:
			_maybe_ai()
			_request_eval()
	)


func _hop_duration(from_sq: int, to_sq: int) -> float:
	var d := board.square_to_world(from_sq).distance_to(board.square_to_world(to_sq))
	return (0.14 + 0.05 * d) / maxf(SettingsStore.animation_speed, 0.25)


func _flying(variant: String) -> bool:
	return CheckersRules.flying_kings(variant)


## Animates the hops of `m` from index `start_hop`; captured discs fly to the
## tray (immediately in English, at the end under Turkish-strike rules).
func _animate_move(m: CheckersMove, start_hop: int, done: Callable) -> void:
	var dropped := _drop_hop
	_drop_hop = false
	var mover: PieceView = piece_nodes.get(m.path[start_hop])
	if mover == null:
		mover = piece_nodes.get(m.from_sq())
	if mover == null:
		rebuild_pieces()
		done.call()
		return
	for k in piece_nodes.keys():
		if piece_nodes[k] == mover:
			piece_nodes.erase(k)
			break
	mover.kill_motion()
	var reduce := SettingsStore.reduce_motion
	var deferred_removal := CheckersRules.flying_kings(engine.variant)
	var pending: Array[PieceView] = []
	for g in _ghosts:
		pending.append(g)
	_ghosts.clear()
	var tw := create_tween()
	var hop_count := m.path.size() - 1
	for i in range(start_hop, hop_count):
		var from := m.path[i]
		var to := m.path[i + 1]
		var a := mover.position if i == start_hop else board.square_to_world(from)
		var b := board.square_to_world(to)
		var capture_hop := m.is_capture()
		var dur := 0.1 if reduce else _hop_duration(from, to)
		var h := 0.0 if reduce else (0.45 if capture_hop else 0.16)
		if dropped and i == start_hop:
			dur = 0.08
			h = 0.0
		tw.tween_method(func(t: float):
			if is_instance_valid(mover):
				var e := t * t * (3.0 - 2.0 * t)
				var p := a.lerp(b, e)
				p.y = lerpf(a.y, b.y, e) + sin(t * PI) * h
				mover.position = p
		, 0.0, 1.0, dur)
		var hop := i
		tw.tween_callback(func():
			if is_instance_valid(mover):
				mover.play_land(0.8 if capture_hop else 1.0)
			if capture_hop and hop < m.captures.size():
				AudioManager.play("capture")
				var victim: PieceView = piece_nodes.get(m.captures[hop])
				if victim:
					piece_nodes.erase(m.captures[hop])
					if deferred_removal:
						victim.set_ghost(true)
						pending.append(victim)
					else:
						_send_to_tray(victim, m.color)
			elif not capture_hop:
				AudioManager.play("place")
			if m.promotes and hop + 1 == m.promote_index and hop + 1 < hop_count and is_instance_valid(mover):
				mover.become_king()
				AudioManager.play("crown")
		)
		if i < hop_count - 1:
			tw.tween_interval(0.04)
	tw.tween_callback(func():
		for v in pending:
			if is_instance_valid(v):
				v.set_ghost(false)
				_send_to_tray(v, m.color)
		if is_instance_valid(mover):
			mover.set_square(m.to_sq())
			piece_nodes[m.to_sq()] = mover
			if m.promotes and (m.promote_index < 0 or m.promote_index >= hop_count) and mover.piece_type != CheckersTypes.KING:
				mover.become_king()
				AudioManager.play("crown")
		if m.capture_count() >= 3:
			AudioManager.play("multi_capture", -4.0)
	)
	tw.tween_interval(0.12 if m.promotes else 0.04)
	tw.tween_callback(done)


## Shows hops [from_hop, to_hop) of a sequence the player is still entering.
func _animate_partial(cand: CheckersMove, from_hop: int, to_hop: int, dragged: bool) -> void:
	var mover: PieceView = piece_nodes.get(prefix[from_hop])
	if mover == null:
		return
	piece_nodes.erase(prefix[from_hop])
	mover.set_selected(false)
	animating = true
	board.clear_highlights()
	var tw := create_tween()
	for i in range(from_hop, to_hop):
		var a := board.square_to_world(prefix[i])
		var b := board.square_to_world(prefix[i + 1])
		var start := mover.position if i == from_hop else a
		var dur := 0.08 if dragged and i == from_hop else _hop_duration(prefix[i], prefix[i + 1])
		var h := 0.0 if dragged and i == from_hop else 0.45
		tw.tween_method(func(t: float):
			if is_instance_valid(mover):
				var e := t * t * (3.0 - 2.0 * t)
				var p := start.lerp(b, e)
				p.y = lerpf(start.y, b.y, e) + sin(t * PI) * h
				mover.position = p
		, 0.0, 1.0, dur)
		var hop := i
		tw.tween_callback(func():
			AudioManager.play("capture")
			if hop < cand.captures.size():
				var victim: PieceView = piece_nodes.get(cand.captures[hop])
				if victim:
					piece_nodes.erase(cand.captures[hop])
					victim.set_ghost(true)
					_ghosts.append(victim)
			if cand.promotes and hop + 1 == cand.promote_index and is_instance_valid(mover):
				mover.become_king()
				AudioManager.play("crown")
		)
	tw.tween_callback(func():
		animating = false
		if is_instance_valid(mover):
			mover.set_square(prefix[prefix.size() - 1])
			piece_nodes[prefix[prefix.size() - 1]] = mover
			mover.set_selected(true)
		selected = prefix[prefix.size() - 1]
		_refresh_marks()
		state_changed.emit()
	)


func _send_to_tray(pv: PieceView, capturer: int) -> void:
	if not is_instance_valid(pv):
		return
	var index := 0
	for t in tray_nodes:
		if is_instance_valid(t) and t.piece_color == pv.piece_color:
			index += 1
	tray_nodes.append(pv)
	pv.kill_motion()
	var slot := board.tray_slot(capturer, index)
	if SettingsStore.reduce_motion:
		pv.position = slot
		pv.scale = Vector3.ONE * 0.8
		return
	var start := pv.position
	var dur := 0.42 / maxf(SettingsStore.animation_speed, 0.25)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		if is_instance_valid(pv):
			var e := t * t * (3.0 - 2.0 * t)
			var p := start.lerp(slot, e)
			p.y += sin(t * PI) * 1.0
			pv.position = p
	, 0.0, 1.0, dur)
	tw.parallel().tween_property(pv, "scale", Vector3.ONE * 0.8, dur)


# --- Pieces ---------------------------------------------------------------------------------

func rebuild_pieces() -> void:
	for c in pieces_root.get_children():
		c.queue_free()
	piece_nodes.clear()
	tray_nodes.clear()
	_ghosts.clear()
	var pos := _view_engine()
	for sq in 64:
		var p := pos.piece_at(sq)
		if p != 0:
			var pv := PieceView.new()
			pv.setup(CheckersTypes.ptype(p), CheckersTypes.pcolor(p), sq)
			pv.position = board.square_to_world(sq)
			pieces_root.add_child(pv)
			piece_nodes[sq] = pv
	var counts := _captured_counts(pos)
	for capturer in [CheckersTypes.WHITE, CheckersTypes.BLACK]:
		var victims: Array = counts[capturer]
		for i in victims.size():
			var pv := PieceView.new()
			pv.setup(int(victims[i]), CheckersTypes.opp(capturer), -1)
			pv.position = board.tray_slot(capturer, i)
			pv.scale = Vector3.ONE * 0.8
			pieces_root.add_child(pv)
			tray_nodes.append(pv)


## Piece types captured by each side at the viewed ply.
func _captured_counts(pos: CheckersEngine) -> Dictionary:
	var out := {CheckersTypes.WHITE: [], CheckersTypes.BLACK: []}
	var hist := engine.history
	for i in mini(view_ply, hist.size()):
		var m: CheckersMove = hist[i]
		for p in m.captured_pieces:
			(out[m.color] as Array).append(CheckersTypes.ptype(p))
	return out


# --- Selection and marks ------------------------------------------------------------------------

func _select(sq: int) -> void:
	if selected >= 0 and piece_nodes.has(selected):
		(piece_nodes[selected] as PieceView).set_selected(false)
	selected = sq
	prefix = PackedInt32Array([sq])
	if piece_nodes.has(sq) and not _dragging:
		(piece_nodes[sq] as PieceView).set_selected(true)
		AudioManager.play("select")
	_refresh_marks()
	state_changed.emit()


func _deselect(emit: bool = true) -> void:
	if selected >= 0 and piece_nodes.has(selected):
		(piece_nodes[selected] as PieceView).set_selected(false)
	selected = -1
	prefix = PackedInt32Array()
	_refresh_marks()
	if emit:
		state_changed.emit()


func _refresh_marks() -> void:
	board.clear_highlights()
	var pos := _view_engine()
	if view_ply > 0 and prefix.size() <= 1:
		var last: CheckersMove = engine.history[view_ply - 1]
		board.show_highlight(last.from_sq(), "last")
		board.show_highlight(last.to_sq(), "last")
		for i in range(1, last.path.size() - 1):
			board.show_highlight(last.path[i], "path")
	var interactive := can_interact()
	if selected < 0 and interactive and SettingsStore.show_movable and not pos.game_over():
		for sq in pos.movable_squares():
			board.show_highlight(sq, "movable")
	if selected >= 0:
		board.show_highlight(selected, "select")
		for i in range(0, prefix.size() - 1):
			board.show_highlight(prefix[i], "route")
		if SettingsStore.show_legal_moves:
			var capture := pos.must_capture()
			for sq in pos.next_landings(prefix):
				board.show_highlight(sq, "capture" if capture else "legal")


# --- Picking ------------------------------------------------------------------------------------

func _pick(screen: Vector2, mask: int) -> int:
	var cam := camera_rig.camera
	if cam == null:
		return -1
	var from := cam.project_ray_origin(screen)
	var to := from + cam.project_ray_normal(screen) * 100.0
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return -1
	var node: Node = hit.get("collider")
	if node and node.has_meta("square"):
		return int(node.get_meta("square"))
	return -1


func _ray_plane(screen: Vector2, y: float) -> Vector3:
	var cam := camera_rig.camera
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return Vector3.INF
	var t := (y - o.y) / d.y
	return Vector3.INF if t < 0.0 else o + d * t


# --- Review -------------------------------------------------------------------------------------

func is_live() -> bool:
	return view_ply == engine.history.size()


func step_view(delta: int) -> void:
	set_view_ply(view_ply + delta)


func set_view_ply(ply: int) -> void:
	ply = clampi(ply, 0, engine.history.size())
	if ply == view_ply or animating or _dragging:
		return
	prefix = PackedInt32Array()
	selected = -1
	board.clear_arrows()
	var forward_one := ply == view_ply + 1
	view_ply = ply
	if forward_one:
		animating = true
		_animate_move(engine.history[ply - 1], 0, func():
			animating = false
			_refresh_marks()
			state_changed.emit()
		)
	else:
		rebuild_pieces()
		_refresh_marks()
		AudioManager.play("slide")
	view_changed.emit(view_ply, is_live())
	state_changed.emit()
	_request_eval()


func _view_engine() -> CheckersEngine:
	if is_live():
		return engine
	if _view_cache.has(view_ply):
		return _view_cache[view_ply]
	var e := CheckersEngine.new(engine.variant)
	if engine.start_fen != "":
		e.from_fen(engine.start_fen)
	for i in view_ply:
		e.play_path(engine.history[i].path)
	_view_cache.clear()
	_view_cache[view_ply] = e
	return e


func view_position() -> CheckersEngine:
	return _view_engine()


# --- Shadow ---------------------------------------------------------------------------------------

func _is_ai_turn() -> bool:
	return GameSession.mode == GameSession.Mode.AI and engine.side_to_move == GameSession.ai_side


func _is_human(side: int) -> bool:
	return side in GameSession.human_sides()


func is_thinking() -> bool:
	return _ai_task >= 0


func _new_job(level: String, upto: int) -> CheckersAI.SearchJob:
	var job := CheckersAI.SearchJob.new()
	job.variant = engine.variant
	job.start_fen = engine.start_fen
	job.moves_uci = _moves_uci(upto)
	job.level = level
	return job


func _maybe_ai() -> void:
	if not _is_ai_turn() or engine.game_over() or paused or _ai_task >= 0:
		return
	_ai_job = _new_job(GameSession.ai_level, engine.history.size())
	if clock_enabled:
		var remaining := clocks[GameSession.ai_side]
		if remaining < 180.0:
			_ai_job.time_ms = int(clampf(remaining / 40.0 + clock_increment * 0.6, 0.08, 2.5) * 1000.0)
	_ai_started_ms = Time.get_ticks_msec()
	_ai_min_ms = 420 + randi() % 420
	_ai_task = WorkerThreadPool.add_task(_ai_job.run, true, "shadow-checkers-ai")
	thinking_changed.emit(true)
	state_changed.emit()


func _poll_ai() -> void:
	if _ai_task < 0 or paused or not WorkerThreadPool.is_task_completed(_ai_task):
		return
	if Time.get_ticks_msec() - _ai_started_ms < _ai_min_ms and not _ai_job.from_book:
		return
	WorkerThreadPool.wait_for_task_completion(_ai_task)
	_ai_task = -1
	var job := _ai_job
	_ai_job = null
	thinking_changed.emit(false)
	if job == null or job.cancelled:
		state_changed.emit()
		return
	var m := engine.find_uci(job.best_uci)
	if m == null:
		var all := engine.generate_legal_moves()
		if all.is_empty():
			state_changed.emit()
			return
		m = all[0]
	if job.depth > 0 and not job.from_book:
		var white_ai := GameSession.ai_side == CheckersTypes.WHITE
		last_eval = {"score": job.score_white, "win": job.win_in if white_ai else -job.win_in, "depth": job.depth, "ply": engine.history.size() + 1, "pv": ""}
	_play(m)


func _cancel_ai() -> void:
	if _ai_task >= 0:
		if _ai_job:
			_ai_job.cancelled = true
		WorkerThreadPool.wait_for_task_completion(_ai_task)
		_ai_task = -1
		_ai_job = null
		thinking_changed.emit(false)


func eval_wanted() -> bool:
	return SettingsStore.show_eval_bar or GameSession.mode == GameSession.Mode.ANALYSIS or (_ended and GameSession.mode != GameSession.Mode.PUZZLE)


func _request_eval() -> void:
	if not eval_wanted():
		return
	if _eval_task >= 0:
		_eval_dirty = true
		if _eval_job:
			_eval_job.cancelled = true
		return
	var pos := _view_engine()
	if pos.game_over():
		var s := 0 if pos.result_side < 0 else (9999 if pos.result_side == CheckersTypes.WHITE else -9999)
		eval_updated.emit(s, 0, 0, "")
		return
	_eval_job = _new_job("analysis", view_ply)
	_eval_job.use_book = false
	_eval_job.time_ms = 1500 if GameSession.mode == GameSession.Mode.ANALYSIS else 700
	_eval_ply = view_ply
	_eval_dirty = false
	_eval_task = WorkerThreadPool.add_task(_eval_job.run, true, "shadow-checkers-eval")


func _poll_eval() -> void:
	if _eval_task < 0 or not WorkerThreadPool.is_task_completed(_eval_task):
		return
	WorkerThreadPool.wait_for_task_completion(_eval_task)
	_eval_task = -1
	var job := _eval_job
	_eval_job = null
	if _eval_dirty or job == null or job.cancelled or _eval_ply != view_ply:
		_eval_dirty = false
		_request_eval()
		return
	var pos := _view_engine()
	var white_stm := pos.side_to_move == CheckersTypes.WHITE
	var win_white := job.win_in if white_stm else -job.win_in
	var pv := _pv_text(pos, job.pv, 6)
	last_eval = {"score": job.score_white, "win": win_white, "depth": job.depth, "ply": view_ply, "pv": pv}
	eval_updated.emit(job.score_white, win_white, job.depth, pv)


func request_hint() -> void:
	if not can_interact() or _hint_task >= 0:
		return
	board.clear_arrows()
	_puzzle_clean = false
	if GameSession.mode == GameSession.Mode.PUZZLE and _puzzle_on_line:
		var sol: Array = GameSession.puzzle.get("solution", [])
		if _puzzle_step < sol.size():
			var m := engine.find_uci(str(sol[_puzzle_step]))
			if m:
				board.show_path_arrow(m.path)
				hint_shown.emit("Try %s" % engine.notation_for(m))
				AudioManager.play("hint")
				return
	_hint_job = _new_job("analysis", view_ply)
	_hint_job.time_ms = 1000
	_hint_task = WorkerThreadPool.add_task(_hint_job.run, true, "shadow-checkers-hint")
	ProfileStore.record_hint()
	toast.emit("Shadow is looking for a move…", "info")


func _poll_hint() -> void:
	if _hint_task < 0 or not WorkerThreadPool.is_task_completed(_hint_task):
		return
	WorkerThreadPool.wait_for_task_completion(_hint_task)
	_hint_task = -1
	var job := _hint_job
	_hint_job = null
	if job == null or job.cancelled:
		return
	var pos := _view_engine()
	var m := pos.find_uci(job.best_uci)
	if m == null:
		return
	board.show_path_arrow(m.path)
	hint_shown.emit("Shadow suggests %s" % pos.notation_for(m))
	AudioManager.play("hint")


func _cancel_task(kind: String) -> void:
	match kind:
		"eval":
			if _eval_task >= 0:
				if _eval_job:
					_eval_job.cancelled = true
				WorkerThreadPool.wait_for_task_completion(_eval_task)
				_eval_task = -1
		"hint":
			if _hint_task >= 0:
				if _hint_job:
					_hint_job.cancelled = true
				WorkerThreadPool.wait_for_task_completion(_hint_task)
				_hint_task = -1
		"func":
			if _func_task >= 0:
				WorkerThreadPool.wait_for_task_completion(_func_task)
				_func_task = -1


func _run_async(fn: Callable, done: Callable) -> void:
	_func_job = FuncJob.new()
	_func_job.fn = fn
	_func_done = done
	_func_task = WorkerThreadPool.add_task(_func_job.run, true, "shadow-checkers-puzzle")
	state_changed.emit()


func _poll_func() -> void:
	if _func_task < 0 or not WorkerThreadPool.is_task_completed(_func_task):
		return
	WorkerThreadPool.wait_for_task_completion(_func_task)
	_func_task = -1
	var r: Variant = _func_job.result
	_func_job = null
	var cb := _func_done
	_func_done = Callable()
	if cb.is_valid():
		cb.call(r)
	state_changed.emit()


# --- Puzzles ---------------------------------------------------------------------------------------

func _puzzle_submit(m: CheckersMove, hops_done: int) -> void:
	var uci := m.to_uci()
	var sol: Array = GameSession.puzzle.get("solution", [])
	if _puzzle_on_line and _puzzle_step < sol.size() and engine.find_uci(str(sol[_puzzle_step])) != null and engine.find_uci(str(sol[_puzzle_step])).to_uci() == uci:
		_puzzle_correct(m, hops_done)
		return
	var probe := engine.clone()
	var left := _puzzle_plies_left
	var p := GameSession.puzzle
	_run_async(func(): return CheckersPuzzles.is_solving_move(probe, uci, p, left), func(ok: Variant):
		if bool(ok):
			_puzzle_on_line = false
			_puzzle_correct(m, hops_done)
		else:
			_puzzle_wrong(m, hops_done)
	)


func _puzzle_correct(m: CheckersMove, hops_done: int) -> void:
	_play(m, hops_done, func():
		_puzzle_plies_left -= 1
		_puzzle_step += 1
		if _puzzle_goal_met() or _puzzle_plies_left <= 0:
			_puzzle_solved = true
			ProfileStore.mark_puzzle(str(GameSession.puzzle.get("id", "")), true)
			AudioManager.play("victory")
			puzzle_event.emit("solved", "Solved — well played!" if _puzzle_clean else "Solved — with a little help.")
			state_changed.emit()
			return
		puzzle_event.emit("correct", "Good move. Keep going.")
		_puzzle_reply()
	)


func _puzzle_goal_met() -> bool:
	return CheckersPuzzles.goal_met(engine, GameSession.puzzle)


func _puzzle_reply() -> void:
	if engine.game_over():
		return
	var sol: Array = GameSession.puzzle.get("solution", [])
	var listed := str(sol[_puzzle_step]) if _puzzle_on_line and _puzzle_step < sol.size() else ""
	var probe := engine.clone()
	var left := _puzzle_plies_left
	var p := GameSession.puzzle
	_run_async(func(): return CheckersPuzzles.best_defense(probe, p, left, listed), func(reply: Variant):
		var m := engine.find_uci(str(reply))
		if m == null:
			return
		if _puzzle_on_line and listed != "" and m.to_uci() != engine.find_uci(listed).to_uci():
			_puzzle_on_line = false
		get_tree().create_timer(0.35).timeout.connect(func():
			_play(m, 0, func():
				_puzzle_plies_left -= 1
				_puzzle_step += 1
				state_changed.emit()
			)
		)
	)


func _puzzle_wrong(m: CheckersMove, hops_done: int) -> void:
	_puzzle_clean = false
	ProfileStore.puzzle_attempts += 1
	AudioManager.play("illegal")
	puzzle_event.emit("wrong", "Not the winning move — try again.")
	_play(m, hops_done, func():
		get_tree().create_timer(0.75).timeout.connect(func():
			engine.undo()
			engine.redo_stack.clear()
			view_ply = engine.history.size()
			_view_cache.clear()
			rebuild_pieces()
			_refresh_marks()
			state_changed.emit()
		)
	)


func puzzle_info() -> Dictionary:
	return {
		"title": str(GameSession.puzzle.get("title", "Puzzle")),
		"goal": str(GameSession.puzzle.get("goal", "gain")),
		"gain": GameSession.puzzle.get("gain", 1),
		"plies": int(GameSession.puzzle.get("plies", 1)),
		"solved": _puzzle_solved,
		"theme": str(GameSession.puzzle.get("theme", "")),
		"difficulty": int(GameSession.puzzle.get("difficulty", 1)),
	}


func restart_puzzle() -> void:
	if GameSession.mode != GameSession.Mode.PUZZLE:
		return
	_cancel_task("func")
	engine.set_variant(str(GameSession.puzzle.get("variant", "english")))
	engine.from_fen(str(GameSession.puzzle.get("fen", "")))
	_puzzle_plies_left = int(GameSession.puzzle.get("plies", 1))
	_puzzle_step = 0
	_puzzle_solved = false
	_puzzle_on_line = true
	view_ply = 0
	_view_cache.clear()
	board.clear_arrows()
	rebuild_pieces()
	_deselect()


# --- Commands ----------------------------------------------------------------------------------------

func undo() -> void:
	if animating or GameSession.mode == GameSession.Mode.PUZZLE:
		return
	_cancel_ai()
	if prefix.size() > 1:
		_reset_partial(false)
	if not engine.can_undo():
		return
	if not is_live():
		view_ply = engine.history.size()
	engine.undo()
	if GameSession.mode == GameSession.Mode.AI and engine.side_to_move == GameSession.ai_side and engine.can_undo():
		engine.undo()
	_after_history_edit()


func redo() -> void:
	if animating or GameSession.mode == GameSession.Mode.PUZZLE or not engine.can_redo():
		return
	engine.redo()
	if GameSession.mode == GameSession.Mode.AI and engine.side_to_move == GameSession.ai_side and engine.can_redo():
		engine.redo()
	_after_history_edit()
	_maybe_ai()


func can_undo() -> bool:
	return GameSession.mode != GameSession.Mode.PUZZLE and engine.can_undo() and not animating


func can_redo() -> bool:
	return GameSession.mode != GameSession.Mode.PUZZLE and engine.can_redo() and not animating


func _after_history_edit() -> void:
	_ended = false
	view_ply = engine.history.size()
	_view_cache.clear()
	prefix = PackedInt32Array()
	selected = -1
	board.clear_arrows()
	rebuild_pieces()
	_refresh_marks()
	view_changed.emit(view_ply, true)
	state_changed.emit()
	_request_eval()


func restart(swap_colors: bool = false) -> void:
	_cancel_ai()
	_cancel_task("hint")
	if GameSession.mode == GameSession.Mode.PUZZLE:
		restart_puzzle()
		return
	if swap_colors and GameSession.mode == GameSession.Mode.AI:
		GameSession.ai_side = CheckersTypes.opp(GameSession.ai_side)
		var w := GameSession.white_name
		GameSession.white_name = GameSession.black_name
		GameSession.black_name = w
		camera_rig.reset_view(GameSession.ai_side == CheckersTypes.BLACK)
	var start := engine.start_fen
	engine.set_variant(engine.variant)
	if start != "":
		engine.from_fen(start)
	clocks = [float(clock_base), float(clock_base)]
	_low_warned = [false, false]
	_ended = false
	_recorded = false
	_after_history_edit()
	AudioManager.play("game_start")
	_maybe_ai()


func resign() -> void:
	if engine.game_over():
		return
	_cancel_ai()
	var side := engine.side_to_move
	if GameSession.mode == GameSession.Mode.AI:
		side = CheckersTypes.opp(GameSession.ai_side)
	engine.resign(side)
	_finish()


func offer_draw() -> bool:
	if engine.game_over():
		return false
	if GameSession.mode != GameSession.Mode.AI:
		engine.agree_draw()
		_finish()
		return true
	var ai_view := int(last_eval.get("score", 0))
	if GameSession.ai_side == CheckersTypes.BLACK:
		ai_view = -ai_view
	var plies := engine.history.size()
	var few := engine.piece_count(CheckersTypes.WHITE) + engine.piece_count(CheckersTypes.BLACK) <= 8
	if (plies >= 30 and ai_view <= 20) or (few and absi(ai_view) <= 40) or ai_view <= -150:
		engine.agree_draw()
		_finish()
		return true
	toast.emit("Shadow declines the draw.", "info")
	return false


func flip_board() -> void:
	camera_rig.face_side(not camera_rig.white_side)


func set_paused(on: bool) -> void:
	paused = on
	if not on:
		_maybe_ai()


func save_now() -> String:
	var path := SaveManager.save_game(snapshot())
	toast.emit("Game saved" if path != "" else "Could not save the game", "success" if path != "" else "error")
	return path


func snapshot() -> Dictionary:
	var mode_name: String = {GameSession.Mode.AI: "ai", GameSession.Mode.ANALYSIS: "analysis", GameSession.Mode.PUZZLE: "puzzle"}.get(GameSession.mode, "local")
	return {
		"variant": engine.variant,
		"mode": mode_name,
		"ai_side": GameSession.ai_side,
		"ai_level": GameSession.ai_level,
		"white_name": GameSession.white_name,
		"black_name": GameSession.black_name,
		"title": "%s vs %s" % [GameSession.white_name, GameSession.black_name],
		"start_fen": engine.start_fen,
		"moves_uci": Array(_moves_uci(engine.history.size())),
		"fen": engine.to_fen(),
		"result": engine.result_token(),
		"result_text": engine.result_text() if engine.game_over() else "",
		"finished": engine.game_over(),
		"clock": {"base": clock_base, "increment": clock_increment, "white": clocks[0], "black": clocks[1], "enabled": clock_enabled},
		"pdn": export_pdn(),
	}


func export_pdn() -> String:
	var headers := {
		"Event": "Shadow Checkers",
		"Site": "Shadowfetch Club Room",
		"White": GameSession.white_name,
		"Black": GameSession.black_name,
	}
	if clock_enabled:
		headers["TimeControl"] = "%d+%d" % [clock_base, clock_increment]
	return CheckersPdn.export_game(engine, headers)


func export_fen() -> String:
	return _view_engine().to_fen()


func load_fen(fen: String) -> bool:
	var probe := CheckersEngine.new(engine.variant)
	if not probe.from_fen(fen):
		toast.emit("That position could not be read.", "error")
		return false
	_cancel_ai()
	engine.from_fen(fen)
	clocks = [float(clock_base), float(clock_base)]
	_after_history_edit()
	_maybe_ai()
	return true


func load_pdn(text: String) -> bool:
	var res := CheckersPdn.import_game(text)
	if not bool(res.get("ok", false)):
		toast.emit("PDN: %s" % str(res.get("error", "could not read the game")), "error")
		return false
	_cancel_ai()
	engine = res["engine"]
	GameSession.variant = engine.variant
	clocks = [float(clock_base), float(clock_base)]
	_after_history_edit()
	if engine.game_over():
		_finish()
	else:
		_maybe_ai()
	return true


func _finish() -> void:
	if _ended:
		return
	_ended = true
	_cancel_task("hint")
	var info := {
		"text": label_text(engine.result_text()),
		"reason": engine.result_reason(),
		"token": engine.result_token(),
		"winner": engine.result_side,
		"player_score": -1.0,
		"rating_delta": 0.0,
		"moves": engine.history.size(),
	}
	var outcome := ""
	if GameSession.mode == GameSession.Mode.AI:
		var human := CheckersTypes.opp(GameSession.ai_side)
		var score := 0.5
		if engine.result_side == human:
			score = 1.0
		elif engine.result_side == GameSession.ai_side:
			score = 0.0
		info["player_score"] = score
		if not _recorded and engine.history.size() >= 2:
			_recorded = true
			info["rating_delta"] = ProfileStore.record_ai_result("%s:%s" % [engine.variant, GameSession.ai_level], score)
		outcome = "victory" if score >= 1.0 else ("defeat" if score <= 0.0 else "draw")
	elif GameSession.mode in [GameSession.Mode.LOCAL, GameSession.Mode.ANALYSIS]:
		if GameSession.mode == GameSession.Mode.LOCAL and not _recorded and engine.history.size() >= 2:
			_recorded = true
			ProfileStore.record_local_game()
		outcome = "draw" if engine.result_side < 0 else "victory"
	if outcome != "":
		get_tree().create_timer(0.4).timeout.connect(func(): AudioManager.play(outcome))
	if GameSession.mode != GameSession.Mode.PUZZLE:
		SaveManager.save_game(snapshot(), SaveManager.autosave_path())
	_refresh_marks()
	state_changed.emit()
	game_finished.emit(info)
	_request_eval()


func _on_settings_changed() -> void:
	MaterialLibrary.apply_theme(SettingsStore.board_theme, SettingsStore.piece_style)
	MaterialLibrary.set_high_contrast(SettingsStore.high_contrast)
	board.apply_settings()
	WorldLook.apply_quality(_world_env.environment)
	WorldLook.apply_light_quality(_lights)
	WorldLook.apply_camera_quality(camera_rig.attributes, camera_rig.distance)
	_refresh_marks()
	_request_eval()
	state_changed.emit()


# --- Queries for the HUD ------------------------------------------------------------------------------

## Replaces engine side names with the current piece style's names
## ("Red" for the classic red-and-black set).
func label_text(text: String) -> String:
	var w := MaterialLibrary.side_label(CheckersTypes.WHITE)
	var b := MaterialLibrary.side_label(CheckersTypes.BLACK)
	if w != "White":
		text = text.replace("White", w)
	if b != "Black":
		text = text.replace("Black", b)
	return text


func side_label(side: int) -> String:
	return MaterialLibrary.side_label(side)


func side_name(side: int) -> String:
	var n := GameSession.white_name if side == CheckersTypes.WHITE else GameSession.black_name
	return label_text(n) if n in ["White", "Black"] else n


func is_ai_side(side: int) -> bool:
	return GameSession.mode == GameSession.Mode.AI and side == GameSession.ai_side


func bottom_side() -> int:
	return CheckersTypes.WHITE if camera_rig.is_white_bottom() else CheckersTypes.BLACK


func status_text() -> String:
	var pos := _view_engine()
	if not is_live():
		return "Reviewing turn %d of %d" % [view_ply, engine.history.size()]
	if engine.game_over():
		return label_text(engine.result_text())
	if _ai_task >= 0:
		return "Shadow is thinking"
	if _func_task >= 0:
		return "Checking your move"
	var who := side_label(pos.side_to_move)
	if prefix.size() > 1:
		return "Keep jumping"
	if GameSession.mode == GameSession.Mode.PUZZLE:
		if _puzzle_solved:
			return "Puzzle solved"
		return "%s to play and %s" % [who, "win" if str(GameSession.puzzle.get("goal", "gain")) == "win" else "gain material"]
	var forced := pos.must_capture()
	if GameSession.mode == GameSession.Mode.AI:
		if _is_human(pos.side_to_move):
			return "Your move — you must capture" if forced else "Your move"
		return "Shadow's move"
	return "%s to move%s" % [who, " — capture required" if forced else ""]


func must_capture_now() -> bool:
	return is_live() and not engine.game_over() and engine.must_capture()


func is_puzzle_busy() -> bool:
	return _func_task >= 0


func captured_by(side: int) -> Array:
	return _captured_counts(_view_engine())[side]


# --- Helpers ---------------------------------------------------------------------------------------------

func _moves_uci(count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in mini(count, engine.history.size()):
		out.append(engine.history[i].to_uci())
	return out


func _pv_text(pos: CheckersEngine, pv: PackedStringArray, limit: int) -> String:
	if pv.is_empty():
		return ""
	var c := pos.clone()
	var parts := PackedStringArray()
	for i in mini(pv.size(), limit):
		var m := c.find_uci(pv[i])
		if m == null:
			break
		var applied := c.apply_move(m)
		if applied == null:
			break
		parts.append(applied.notation)
	return "  ".join(parts)
