class_name PieceView
extends Node3D

## One checker on the board: mesh, contact shadow, and motion cues (hover
## lift, selection float, landing settle, crowning, pending-capture ghost).

const SELECT_LIFT := 0.08
const HOVER_LIFT := 0.03

static var _blob_mesh: PlaneMesh

var square: int = -1
var piece_type: int = 0
var piece_color: int = 0
var _visual: Node3D
var _blob: MeshInstance3D
var _motion: Tween
var _loop: Tween
var _selected := false
var _hovered := false
var _dragging := false


func setup(type: int, color: int, sq: int) -> void:
	piece_type = type
	piece_color = color
	square = sq
	_visual = PieceMeshBuilder.build(type, color)
	_visual.rotation.y = randf() * TAU
	add_child(_visual)
	_tag_body()
	if _blob_mesh == null:
		_blob_mesh = PlaneMesh.new()
		_blob_mesh.size = Vector2(1.0, 1.0)
	_blob = MeshInstance3D.new()
	_blob.mesh = _blob_mesh
	_blob.material_override = MaterialLibrary.contact_shadow
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r := PieceMeshBuilder.radius_of(type) * 2.5
	_blob.scale = Vector3(r, 1.0, r)
	_blob.position.y = 0.004
	add_child(_blob)


func set_square(sq: int) -> void:
	square = sq
	_tag_body()


func set_selected(on: bool) -> void:
	_selected = on
	_restart_motion()


func set_hovered(on: bool) -> void:
	if _hovered == on:
		return
	_hovered = on
	if not _selected and not _dragging:
		_restart_motion()


func set_dragging(on: bool) -> void:
	_dragging = on
	_kill()
	if not is_instance_valid(_visual):
		return
	_visual.position.y = 0.0
	_blob.visible = not on
	if not on:
		_restart_motion()


func kill_motion() -> void:
	_kill()
	if is_instance_valid(_visual):
		_visual.position.y = 0.0
		_visual.scale = Vector3.ONE


## Captured mid-sequence under Turkish-strike rules: stays on the board, dimmed.
func set_ghost(on: bool) -> void:
	var mi := _mesh_instance()
	if mi:
		mi.transparency = 0.55 if on else 0.0
	if is_instance_valid(_visual):
		var tw := create_tween()
		tw.tween_property(_visual, "position:y", -0.03 if on else 0.0, 0.15)


func play_land(strength: float = 1.0) -> void:
	if SettingsStore.reduce_motion or not is_instance_valid(_visual):
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var s := 0.05 * strength
	tw.tween_property(_visual, "scale", Vector3(1.0 + s, 1.0 - s * 1.6, 1.0 + s), 0.05)
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK)


## Crowning: a second disc drops onto the man, then the piece becomes a king.
func become_king(animate: bool = true) -> void:
	if piece_type == CheckersTypes.KING:
		return
	kill_motion()
	var old := _visual
	piece_type = CheckersTypes.KING
	var king := PieceMeshBuilder.build(CheckersTypes.KING, piece_color)
	king.rotation.y = old.rotation.y if is_instance_valid(old) else 0.0
	if not animate or SettingsStore.reduce_motion:
		if is_instance_valid(old):
			old.queue_free()
		_visual = king
		add_child(_visual)
		_tag_body()
		return
	var disc := PieceMeshBuilder.build(CheckersTypes.MAN, piece_color)
	disc.position.y = 1.1
	disc.rotation.y = randf() * TAU
	add_child(disc)
	var h := PieceMeshBuilder.height_of(CheckersTypes.MAN)
	var tw := create_tween()
	tw.tween_property(disc, "position:y", h, 0.34).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		if is_instance_valid(old):
			old.queue_free()
		disc.queue_free()
		_visual = king
		add_child(_visual)
		_tag_body()
		play_land(0.8)
	)


func fade_capture(delay: float = 0.0) -> void:
	_kill()
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.28)
	tw.parallel().tween_property(self, "position:y", position.y - 0.12, 0.28)
	tw.tween_callback(queue_free)


func _mesh_instance() -> MeshInstance3D:
	if not is_instance_valid(_visual):
		return null
	return _visual.get_node_or_null("Mesh") as MeshInstance3D


func _tag_body() -> void:
	if not is_instance_valid(_visual):
		return
	for c in _visual.get_children():
		if c is StaticBody3D:
			(c as StaticBody3D).set_meta("square", square)


func _kill() -> void:
	if _motion:
		_motion.kill()
		_motion = null
	if _loop:
		_loop.kill()
		_loop = null


func _restart_motion() -> void:
	_kill()
	if not is_instance_valid(_visual):
		return
	var lift := SELECT_LIFT if _selected else (HOVER_LIFT if _hovered else 0.0)
	_motion = create_tween()
	_motion.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_motion.tween_property(_visual, "position:y", lift, 0.14)
	if _selected and not SettingsStore.reduce_motion:
		_loop = create_tween().set_loops()
		_loop.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_loop.tween_interval(0.14)
		_loop.tween_property(_visual, "position:y", lift + 0.022, 0.7)
		_loop.tween_property(_visual, "position:y", lift - 0.008, 0.7)
