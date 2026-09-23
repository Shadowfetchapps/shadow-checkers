class_name BoardView
extends Node3D

## The draughtboard: base slab, 64 tiles, frame, coordinates, optional
## 1–32 square numbers, capture trays, and pooled highlight marks. Geometry
## comes from res://assets/models when present, otherwise primitives.
## The frame rests on the table at y = 0; tile tops are at TOP_Y.

const LIFT := 0.12
const TILE_H := 0.07
const TOP_Y := LIFT + TILE_H
const MODEL_DIR := "res://assets/models/"
const TRAY_X := 5.35

var _fill: Array[MeshInstance3D] = []
var _marker: Array[MeshInstance3D] = []
var _hover: MeshInstance3D
var _arrows: Node3D
var _coords: Array[Label3D] = []
var _numbers: Array[Label3D] = []
var _hover_sq := -1
var _white_bottom := true


func _ready() -> void:
	MaterialLibrary.ensure()
	_build_base()
	_build_tiles()
	_build_frame()
	_build_trays()
	_build_coords()
	_build_numbers()
	_build_marks()
	apply_settings()


func square_to_world(sq: int) -> Vector3:
	return Vector3(CheckersTypes.file_of(sq) - 3.5, TOP_Y, 3.5 - CheckersTypes.rank_of(sq))


## Slot for the index-th disc captured BY `capturer`, stacked flat in rows on
## the capturer's right-hand side of the board.
func tray_slot(capturer: int, index: int) -> Vector3:
	var col := index % 2
	var row := int(index / 2.0)
	var side := 1.0 if capturer == CheckersTypes.WHITE else -1.0
	var x := side * (TRAY_X - 0.3 + col * 0.6)
	var z := side * (3.35 - row * 0.64)
	return Vector3(x, 0.035, z)


func set_white_bottom(white_bottom: bool) -> void:
	_white_bottom = white_bottom
	var rot := 0.0 if white_bottom else 180.0
	for l in _coords:
		l.rotation_degrees = Vector3(-90, rot, 0)
	for l in _numbers:
		l.rotation_degrees = Vector3(-90, rot, 0)
	_place_numbers()


func apply_settings() -> void:
	var c := MaterialLibrary.coord_color()
	for l in _coords:
		l.visible = SettingsStore.show_coordinates
		l.modulate = Color(c.r, c.g, c.b, 0.9)
	for l in _numbers:
		l.visible = SettingsStore.show_square_numbers
		l.modulate = Color(c.r, c.g, c.b, 0.55)


# --- Marks ----------------------------------------------------------------------------

func clear_highlights() -> void:
	for i in 64:
		_fill[i].visible = false
		_marker[i].visible = false


func show_highlight(sq: int, kind: String) -> void:
	if sq < 0 or sq > 63:
		return
	match kind:
		"select":
			_show_fill(sq, MaterialLibrary.mark_select)
		"last":
			if SettingsStore.highlight_last_move:
				_show_fill(sq, MaterialLibrary.mark_last)
		"legal":
			_show_marker(sq, MaterialLibrary.mark_legal, 0.44)
		"capture":
			_show_marker(sq, MaterialLibrary.mark_capture, 0.98)
		"movable":
			_show_marker(sq, MaterialLibrary.mark_movable, 1.0)
		"path":
			if SettingsStore.highlight_last_move:
				_show_marker(sq, MaterialLibrary.mark_path, 0.22)
		"route":
			_show_marker(sq, MaterialLibrary.mark_path, 0.26)


func show_hover(sq: int) -> void:
	if sq == _hover_sq:
		return
	_hover_sq = sq
	if sq < 0:
		_hover.visible = false
		return
	var p := square_to_world(sq)
	_hover.position = Vector3(p.x, TOP_Y + 0.006, p.z)
	_hover.visible = true


func _show_fill(sq: int, mat: Material) -> void:
	_fill[sq].material_override = mat
	_fill[sq].visible = true


func _show_marker(sq: int, mat: Material, s: float) -> void:
	var m := _marker[sq]
	m.material_override = mat
	m.scale = Vector3(s, 1, s)
	m.visible = true


## Flat arrow through every landing square of a (multi-jump) path.
func show_path_arrow(path: PackedInt32Array, mat: Material = null) -> void:
	clear_arrows()
	if path.size() < 2:
		return
	var pts: Array[Vector3] = []
	for s in path:
		pts.append(square_to_world(s))
	var mi := MeshInstance3D.new()
	mi.mesh = _arrow_mesh(pts, 0.16, 0.46, 0.42)
	mi.material_override = mat if mat else MaterialLibrary.mark_hint
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.012
	_arrows.add_child(mi)
	if not SettingsStore.reduce_motion:
		mi.transparency = 1.0
		create_tween().tween_property(mi, "transparency", 0.0, 0.25)


func clear_arrows() -> void:
	for c in _arrows.get_children():
		c.queue_free()


func _arrow_mesh(pts: Array[Vector3], shaft_w: float, head_w: float, head_len: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var n := pts.size()
	for i in n - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var dir := (p1 - p0).normalized()
		if i == 0:
			p0 += dir * 0.3
		if i == n - 2:
			p1 -= dir * head_len
		else:
			p1 += dir * shaft_w * 0.5
		var side := dir.cross(Vector3.UP).normalized() * shaft_w * 0.5
		for v in [p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side]:
			st.add_vertex(Vector3(v.x, TOP_Y, v.z))
	var tip := pts[n - 1]
	var d := (tip - pts[n - 2]).normalized()
	var base := tip - d * head_len
	var hs := d.cross(Vector3.UP).normalized() * head_w * 0.5
	st.add_vertex(Vector3(base.x - hs.x, TOP_Y, base.z - hs.z))
	st.add_vertex(Vector3(tip.x - d.x * 0.12, TOP_Y, tip.z - d.z * 0.12))
	st.add_vertex(Vector3(base.x + hs.x, TOP_Y, base.z + hs.z))
	return st.commit()


# --- Construction ------------------------------------------------------------------------

func _model(name: String) -> Mesh:
	var p := MODEL_DIR + name + ".obj"
	return load(p) as Mesh if ResourceLoader.exists(p) else null


func _build_base() -> void:
	var mi := MeshInstance3D.new()
	var mesh := _model("board_base")
	if mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3(8.02, 0.1, 8.02)
		mesh = box
		mi.position.y = LIFT - 0.05
	else:
		mi.position.y = LIFT
	mi.mesh = mesh
	mi.material_override = MaterialLibrary.base_mat
	add_child(mi)


func _build_tiles() -> void:
	var tile := _model("square_tile")
	var authored := tile != null
	if not authored:
		var box := BoxMesh.new()
		box.size = Vector3(0.985, TILE_H, 0.985)
		tile = box
	var rng := RandomNumberGenerator.new()
	rng.seed = 32
	for r in 8:
		for f in 8:
			var sq := CheckersTypes.sq(f, r)
			var mi := MeshInstance3D.new()
			mi.mesh = tile
			var dark := CheckersTypes.is_dark_fr(f, r)
			var variant := rng.randi_range(0, MaterialLibrary.SQUARE_VARIANTS - 1)
			mi.material_override = MaterialLibrary.dark_square(variant) if dark else MaterialLibrary.light_square(variant)
			mi.position = Vector3(f - 3.5, LIFT + (0.0 if authored else TILE_H * 0.5), 3.5 - r)
			mi.rotation.y = (PI * 0.5 if dark else 0.0) + (PI if rng.randf() < 0.5 else 0.0)
			add_child(mi)
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.set_meta("square", sq)
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.0, 0.1, 1.0)
			col.shape = shape
			body.add_child(col)
			body.position = Vector3(f - 3.5, TOP_Y - 0.05, 3.5 - r)
			add_child(body)


func _build_frame() -> void:
	var mesh := _model("board_frame")
	if mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position.y = LIFT
		for i in mesh.get_surface_count():
			var role := PieceMeshBuilder.surface_role(mesh, i)
			mi.set_surface_override_material(i, MaterialLibrary.inlay_mat if role == "trim" else MaterialLibrary.frame_mat)
		add_child(mi)
		return
	var w := 0.6
	var h := 0.22
	for side in 4:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(8.0 + w * 2.0, h, w) if side < 2 else Vector3(w, h, 8.0)
		mi.mesh = box
		mi.material_override = MaterialLibrary.frame_mat
		var off := 4.0 + w * 0.5
		mi.position = [Vector3(0, h * 0.5, off), Vector3(0, h * 0.5, -off), Vector3(off, h * 0.5, 0), Vector3(-off, h * 0.5, 0)][side]
		add_child(mi)


func _build_trays() -> void:
	for side in [-1.0, 1.0]:
		var tray := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.3, 0.03, 8.1)
		tray.mesh = box
		tray.material_override = MaterialLibrary.felt_mat
		tray.position = Vector3(side * TRAY_X, 0.015, 0)
		add_child(tray)
		for edge in [-0.67, 0.67]:
			var rail := MeshInstance3D.new()
			var rb := BoxMesh.new()
			rb.size = Vector3(0.04, 0.05, 8.1)
			rail.mesh = rb
			rail.material_override = MaterialLibrary.brass_mat
			rail.position = Vector3(side * TRAY_X + edge, 0.025, 0)
			add_child(rail)


func _build_coords() -> void:
	var font := ThemeFactory.font("display_medium")
	var y := LIFT + 0.105
	for f in 8:
		for z in [4.3, -4.3]:
			_coords.append(_label(CheckersTypes.FILE_NAMES[f], Vector3(f - 3.5, y, z), font, 72, 0.0028))
	for r in 8:
		for x in [-4.3, 4.3]:
			_coords.append(_label(str(r + 1), Vector3(x, y, 3.5 - r), font, 72, 0.0028))


func _build_numbers() -> void:
	var font := ThemeFactory.font("medium")
	for sq in 64:
		var n := CheckersTypes.square_number(sq)
		if n < 0:
			continue
		var l := _label(str(n), Vector3.ZERO, font, 48, 0.0034)
		l.set_meta("square", sq)
		_numbers.append(l)
	_place_numbers()


## Numbers sit in the top-left corner of each dark square from the viewer's side.
func _place_numbers() -> void:
	var s := 1.0 if _white_bottom else -1.0
	for l in _numbers:
		var p := square_to_world(int(l.get_meta("square")))
		l.position = Vector3(p.x - 0.33 * s, TOP_Y + 0.004, p.z - 0.33 * s)


func _label(text: String, pos: Vector3, font: Font, size: int, px: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = px
	l.outline_size = 0
	l.position = pos
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	return l


func _build_marks() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	for r in 8:
		for f in 8:
			var origin := Vector3(f - 3.5, TOP_Y, 3.5 - r)
			var fill := MeshInstance3D.new()
			fill.mesh = plane
			fill.scale = Vector3(0.985, 1, 0.985)
			fill.position = origin + Vector3(0, 0.003, 0)
			fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fill.visible = false
			add_child(fill)
			_fill.append(fill)
			var marker := MeshInstance3D.new()
			marker.mesh = plane
			marker.position = origin + Vector3(0, 0.008, 0)
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			marker.visible = false
			add_child(marker)
			_marker.append(marker)
	_hover = MeshInstance3D.new()
	_hover.mesh = plane
	_hover.material_override = MaterialLibrary.mark_hover
	_hover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hover.visible = false
	add_child(_hover)
	_arrows = Node3D.new()
	_arrows.name = "Arrows"
	add_child(_arrows)
