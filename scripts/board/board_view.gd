class_name BoardView
extends Node3D

signal square_clicked(sq: int)

var highlights: Array[MeshInstance3D] = []
var dots: Array[MeshInstance3D] = []
var _hover: MeshInstance3D
var _light_base: Color = Color(0.84, 0.72, 0.54)
var _dark_base: Color = Color(0.20, 0.13, 0.09)
var _select_mat: StandardMaterial3D
var _legal_mat: StandardMaterial3D
var _capture_mat: StandardMaterial3D
var _last_mat: StandardMaterial3D
var _continue_mat: StandardMaterial3D
var _movable_mat: StandardMaterial3D
var _hover_mat: StandardMaterial3D
var _dot_legal: StandardMaterial3D
var _dot_capture: StandardMaterial3D


func _ready() -> void:
	_build_materials()
	_build_table()
	_build_frame()
	_build_squares()
	_build_coords()
	_build_highlights()
	_build_dots()
	_build_hover()


func square_to_world(sq: int) -> Vector3:
	var f := CheckersTypes.file_of(sq)
	var r := CheckersTypes.rank_of(sq)
	return Vector3(f - 3.5, 0.198, 3.5 - r)


func world_to_square(pos: Vector3) -> int:
	var f := int(floor(pos.x + 4.0))
	var r := int(floor(4.0 - pos.z))
	if CheckersTypes.in_board(f, r):
		return CheckersTypes.sq(f, r)
	return -1


func clear_highlights() -> void:
	for h in highlights:
		h.visible = false
	for d in dots:
		d.visible = false
	if _hover:
		_hover.visible = false


func show_highlight(sq: int, kind: String) -> void:
	if sq < 0 or sq > 63:
		return
	match kind:
		"legal":
			_show_dot(sq, _dot_legal, 0.11)
		"capture":
			_show_dot(sq, _dot_capture, 0.14)
		"select":
			_show_plane(sq, _select_mat)
		"continue":
			_show_plane(sq, _continue_mat)
		"movable":
			_show_plane(sq, _movable_mat)
		_:
			_show_plane(sq, _last_mat)


func show_hover(sq: int) -> void:
	if sq < 0 or sq > 63 or _hover == null:
		return
	var f := CheckersTypes.file_of(sq)
	var r := CheckersTypes.rank_of(sq)
	_hover.position = Vector3(f - 3.5, 0.208, 3.5 - r)
	_hover.visible = true


func _show_plane(sq: int, mat: Material) -> void:
	var h := highlights[sq]
	h.visible = true
	h.material_override = mat


func _show_dot(sq: int, mat: Material, radius: float) -> void:
	var d := dots[sq]
	d.visible = true
	d.material_override = mat
	if d.mesh is CylinderMesh:
		var mesh := d.mesh as CylinderMesh
		mesh.top_radius = radius
		mesh.bottom_radius = radius


func _build_materials() -> void:
	_select_mat = _emit(Color(0.38, 0.90, 1.0, 0.58), 1.05)
	_legal_mat = _emit(Color(0.32, 0.72, 0.86, 0.28), 0.55)
	_capture_mat = _emit(Color(0.94, 0.34, 0.28, 0.48), 0.85)
	_continue_mat = _emit(Color(0.98, 0.76, 0.28, 0.55), 0.95)
	_last_mat = _emit(Color(0.96, 0.78, 0.32, 0.30), 0.45)
	_movable_mat = _emit(Color(0.40, 0.82, 0.78, 0.22), 0.35)
	_hover_mat = _emit(Color(0.95, 0.97, 1.0, 0.22), 0.4)
	_dot_legal = _emit(Color(0.42, 0.88, 0.82, 0.92), 0.9)
	_dot_capture = _emit(Color(0.95, 0.32, 0.28, 0.95), 1.1)


func _emit(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_receive_shadows = true
	return m


func _wood(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.04
	return m


func _build_table() -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(20, 0.14, 20)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.045, 0.05, 0.062)
	mat.roughness = 0.92
	mi.material_override = mat
	mi.position.y = -0.16
	add_child(mi)
	var cloth := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(13.2, 0.04, 13.2)
	cloth.mesh = cm
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.07, 0.12, 0.14)
	felt.roughness = 0.88
	cloth.material_override = felt
	cloth.position.y = -0.07
	add_child(cloth)


func _build_frame() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.10, 0.07)
	mat.metallic = 0.18
	mat.roughness = 0.42
	var frame := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8.95, 0.26, 8.95)
	frame.mesh = box
	frame.material_override = mat
	frame.position.y = 0.04
	add_child(frame)
	var inlay := MeshInstance3D.new()
	var ib := BoxMesh.new()
	ib.size = Vector3(8.55, 0.06, 8.55)
	inlay.mesh = ib
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.55, 0.72, 0.78)
	metal.metallic = 0.72
	metal.roughness = 0.28
	inlay.material_override = metal
	inlay.position.y = 0.155
	add_child(inlay)
	var inner := MeshInstance3D.new()
	var felt_box := BoxMesh.new()
	felt_box.size = Vector3(8.08, 0.05, 8.08)
	inner.mesh = felt_box
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.08, 0.11, 0.13)
	inner.material_override = felt
	inner.position.y = 0.13
	add_child(inner)


func _build_squares() -> void:
	for r in 8:
		for f in 8:
			var sq := CheckersTypes.sq(f, r)
			var dark := CheckersTypes.is_dark_fr(f, r)
			var shade := 1.0 + 0.045 * sin(float(f) * 1.7 + float(r) * 2.1)
			var base := _dark_base if dark else _light_base
			var mat := _wood(Color(base.r * shade, base.g * shade, base.b * (shade * 0.98)), 0.58 if dark else 0.46)
			var mi := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.98, 0.075 if dark else 0.068, 0.98)
			mi.mesh = mesh
			mi.material_override = mat
			mi.position = Vector3(f - 3.5, 0.162 if dark else 0.168, 3.5 - r)
			add_child(mi)
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.set_meta("square", sq)
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.0, 0.16, 1.0)
			col.shape = shape
			body.add_child(col)
			body.position = Vector3(f - 3.5, 0.16, 3.5 - r)
			add_child(body)


func _build_coords() -> void:
	var font := ThemeDB.fallback_font
	var display: FontFile = load("res://assets/fonts/InterDisplay-Medium.ttf")
	if display:
		font = display
	for f in 8:
		_label(CheckersTypes.FILE_NAMES[f], Vector3(f - 3.5, 0.24, 4.38), font)
		_label(CheckersTypes.FILE_NAMES[f], Vector3(f - 3.5, 0.24, -4.38), font)
	for r in 8:
		_label(str(r + 1), Vector3(-4.38, 0.24, 3.5 - r), font)
		_label(str(r + 1), Vector3(4.38, 0.24, 3.5 - r), font)


func _label(text: String, pos: Vector3, font: Font) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 30
	l.modulate = Color(0.78, 0.86, 0.90, 0.78)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.position = pos
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.pixel_size = 0.011
	add_child(l)


func _build_highlights() -> void:
	highlights.resize(64)
	for r in 8:
		for f in 8:
			var sq := CheckersTypes.sq(f, r)
			var mi := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.96, 0.018, 0.96)
			mi.mesh = mesh
			mi.material_override = _last_mat
			mi.position = Vector3(f - 3.5, 0.208, 3.5 - r)
			mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			highlights[sq] = mi


func _build_dots() -> void:
	dots.resize(64)
	for r in 8:
		for f in 8:
			var sq := CheckersTypes.sq(f, r)
			var mi := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.11
			mesh.bottom_radius = 0.11
			mesh.height = 0.03
			mesh.radial_segments = 20
			mi.mesh = mesh
			mi.material_override = _dot_legal
			mi.position = Vector3(f - 3.5, 0.222, 3.5 - r)
			mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			dots[sq] = mi


func _build_hover() -> void:
	_hover = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.98, 0.012, 0.98)
	_hover.mesh = mesh
	_hover.material_override = _hover_mat
	_hover.visible = false
	_hover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hover)
