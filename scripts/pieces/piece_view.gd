class_name PieceView
extends Node3D

var square: int = -1
var piece_type: int = 0
var piece_color: int = 0
var _visual: Node3D
var _bob: Tween
var _selected := false
var _hovered := false


func setup(type: int, color: int, sq: int) -> void:
	piece_type = type
	piece_color = color
	set_square(sq)
	_visual = PieceMeshBuilder.build(type, color)
	add_child(_visual)
	_tag_body()


func set_square(sq: int) -> void:
	square = sq
	_tag_body()


func kill_motion() -> void:
	if _bob:
		_bob.kill()
		_bob = null
	if is_instance_valid(_visual):
		_visual.position.y = 0.0


func set_selected(on: bool) -> void:
	_selected = on
	_restart_bob()


func set_hovered(on: bool) -> void:
	if _hovered == on:
		return
	_hovered = on
	if _selected:
		return
	_restart_bob()


func become_king() -> void:
	if piece_type == CheckersTypes.KING:
		return
	kill_motion()
	piece_type = CheckersTypes.KING
	if is_instance_valid(_visual):
		_visual.queue_free()
	_visual = PieceMeshBuilder.build(CheckersTypes.KING, piece_color)
	add_child(_visual)
	_tag_body()
	if _selected:
		_restart_bob()


func _tag_body() -> void:
	if not is_instance_valid(_visual):
		return
	for child in _visual.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).set_meta("square", square)


func _restart_bob() -> void:
	kill_motion()
	if not is_instance_valid(_visual):
		return
	var lift := 0.0
	if _selected:
		lift = 0.08
	elif _hovered:
		lift = 0.035
	if lift <= 0.0:
		return
	_bob = create_tween().set_loops()
	_bob.set_trans(Tween.TRANS_SINE)
	_bob.tween_property(_visual, "position:y", lift, 0.42)
	_bob.tween_property(_visual, "position:y", lift * 0.25, 0.42)
