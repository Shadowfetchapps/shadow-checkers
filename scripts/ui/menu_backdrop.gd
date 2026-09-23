class_name MenuBackdrop
extends Node3D

## Living title-screen scene: the club room with Shadow playing itself at a
## relaxed level on the menu board, under a slowly orbiting camera.

const MOVE_EVERY := 2.6

var camera_rig: OrbitCamera
var board: BoardView
var _engine := CheckersEngine.new("english")
var _pieces: Node3D
var _nodes: Dictionary = {}
var _timer := 0.0
var _job: CheckersAI.SearchJob
var _task := -1
var _world_env: WorldEnvironment


func _ready() -> void:
	MaterialLibrary.apply_theme(SettingsStore.board_theme, SettingsStore.piece_style)
	CheckersAI.warmup()
	_world_env = WorldEnvironment.new()
	_world_env.environment = WorldLook.make_environment()
	add_child(_world_env)
	WorldLook.add_lights(self)
	ClubBuilder.build(self, true)
	board = BoardView.new()
	add_child(board)
	_pieces = Node3D.new()
	add_child(_pieces)
	camera_rig = OrbitCamera.new()
	camera_rig.interactive = false
	camera_rig.auto_orbit_speed = 2.0 if not SettingsStore.reduce_motion else 0.0
	add_child(camera_rig)
	camera_rig.pitch = 36.0
	camera_rig.yaw = 24.0
	camera_rig.distance = camera_rig.frame_distance() * 0.92
	camera_rig.call_deferred("_snap")
	_restart()
	SettingsStore.settings_changed.connect(func():
		MaterialLibrary.apply_theme(SettingsStore.board_theme, SettingsStore.piece_style)
		WorldLook.apply_quality(_world_env.environment)
		board.apply_settings()
	)


func _exit_tree() -> void:
	if _task >= 0:
		_job.cancelled = true
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func set_insets(left: float, right: float) -> void:
	camera_rig.set_insets(left, right, 0.0, 0.0)
	camera_rig.distance = camera_rig.frame_distance() * 0.92


func _process(delta: float) -> void:
	if _task >= 0:
		if WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			var m := _engine.find_uci(_job.best_uci)
			if m:
				var applied := _engine.apply_move(m)
				if applied:
					_animate(applied)
		return
	if SettingsStore.reduce_motion:
		return
	_timer += delta
	if _timer < MOVE_EVERY:
		return
	_timer = 0.0
	if _engine.game_over() or _engine.history.size() > 90:
		_restart()
		return
	_job = CheckersAI.SearchJob.new()
	_job.variant = _engine.variant
	_job.start_fen = _engine.start_fen
	var ucis := PackedStringArray()
	for h in _engine.history:
		ucis.append(h.to_uci())
	_job.moves_uci = ucis
	_job.level = "casual"
	_task = WorkerThreadPool.add_task(_job.run, true, "shadow-checkers-menu")


func _restart() -> void:
	_engine.set_variant("english")
	for c in _pieces.get_children():
		c.queue_free()
	_nodes.clear()
	for sq in 64:
		var p := _engine.piece_at(sq)
		if p != 0:
			var pv := PieceView.new()
			pv.setup(CheckersTypes.ptype(p), CheckersTypes.pcolor(p), sq)
			pv.position = board.square_to_world(sq)
			_pieces.add_child(pv)
			_nodes[sq] = pv


func _animate(m: CheckersMove) -> void:
	var mover: PieceView = _nodes.get(m.from_sq())
	if mover == null:
		return
	_nodes.erase(m.from_sq())
	_nodes[m.to_sq()] = mover
	var tw := create_tween()
	for i in m.path.size() - 1:
		var a := board.square_to_world(m.path[i])
		var b := board.square_to_world(m.path[i + 1])
		var h := 0.45 if m.is_capture() else 0.16
		tw.tween_method(func(t: float):
			if is_instance_valid(mover):
				var e := t * t * (3.0 - 2.0 * t)
				var p := a.lerp(b, e)
				p.y += sin(t * PI) * h
				mover.position = p
		, 0.0, 1.0, 0.42)
		var hop := i
		tw.tween_callback(func():
			if hop < m.captures.size() and _nodes.has(m.captures[hop]):
				var victim: PieceView = _nodes[m.captures[hop]]
				_nodes.erase(m.captures[hop])
				victim.fade_capture()
		)
	tw.tween_callback(func():
		if is_instance_valid(mover):
			mover.set_square(m.to_sq())
			mover.play_land()
			if m.promotes:
				mover.become_king()
	)
