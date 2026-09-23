class_name ClubBuilder
extends RefCounted

## The club room around the board: a mahogany table with a green leather
## top, plank floor, panelled walls with bookshelves, a fireplace, wall
## sconces, a green-shaded pendant lamp, and the tournament clock.
## Table top is y = 0 (the board frame rests on it).

const TABLE_HALF := 7.0
const FLOOR_Y := -3.2


static func build(parent: Node3D, with_clock: bool = true) -> Node3D:
	MaterialLibrary.ensure()
	var root := Node3D.new()
	root.name = "Club"
	parent.add_child(root)
	_table(root)
	_room(root)
	_bookshelves(root)
	_fireplace(root)
	_pendant(root)
	_sconces(root)
	if with_clock:
		var clock := GameClockProp.new()
		clock.name = "Clock"
		clock.position = Vector3(-6.25, 0.0, -1.6)
		clock.rotation_degrees = Vector3(0, 62, 0)
		root.add_child(clock)
	return root


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, segs := 32) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bot
	mesh.height = h
	mesh.radial_segments = segs
	mesh.rings = 1
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _table(parent: Node3D) -> void:
	var t := TABLE_HALF * 2.0
	_box(parent, Vector3(t, 0.34, t), Vector3(0, -0.17, 0), MaterialLibrary.table_wood)
	_box(parent, Vector3(t - 1.2, 0.012, t - 1.2), Vector3(0, 0.001, 0), MaterialLibrary.leather_mat)
	for s in [-1.0, 1.0]:
		_box(parent, Vector3(t - 1.16, 0.018, 0.03), Vector3(0, 0.006, s * (TABLE_HALF - 0.6)), MaterialLibrary.brass_mat)
		_box(parent, Vector3(0.03, 0.018, t - 1.16), Vector3(s * (TABLE_HALF - 0.6), 0.006, 0), MaterialLibrary.brass_mat)
	_box(parent, Vector3(t - 0.8, 0.5, t - 0.8), Vector3(0, -0.58, 0), MaterialLibrary.table_wood)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_cyl(parent, 0.28, 0.2, 2.9, Vector3(x * 5.9, FLOOR_Y + 1.45, z * 5.9), MaterialLibrary.table_wood, 24)
			_cyl(parent, 0.24, 0.24, 0.08, Vector3(x * 5.9, FLOOR_Y + 0.04, z * 5.9), MaterialLibrary.brass_mat, 24)


static func _room(parent: Node3D) -> void:
	var floor := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(70, 70)
	floor.mesh = fp
	floor.material_override = MaterialLibrary.floor_mat
	floor.position.y = FLOOR_Y
	parent.add_child(floor)
	var rug := MeshInstance3D.new()
	var rp := PlaneMesh.new()
	rp.size = Vector2(20, 16)
	rug.mesh = rp
	rug.material_override = MaterialLibrary.rug_mat
	rug.position.y = FLOOR_Y + 0.01
	parent.add_child(rug)
	var h := 34.0
	var cy := FLOOR_Y + h * 0.5
	for w in [[Vector3(44, h, 0.3), Vector3(0, cy, -19.0)], [Vector3(44, h, 0.3), Vector3(0, cy, 22.0)],
			[Vector3(0.3, h, 44), Vector3(-21.0, cy, 0)], [Vector3(0.3, h, 44), Vector3(21.0, cy, 0)]]:
		_box(parent, w[0], w[1], MaterialLibrary.wall_mat)
		var size: Vector3 = w[0]
		var pos: Vector3 = w[1]
		var inward := -Vector3(pos.x, 0, pos.z).normalized() * 0.2
		var rail := Vector3(size.x if size.x > 1 else 0.16, 0.08, size.z if size.z > 1 else 0.16)
		_box(parent, rail, Vector3(pos.x, FLOOR_Y + 2.8, pos.z) + inward * 1.2, MaterialLibrary.brass_mat)
		var base := Vector3(size.x if size.x > 1 else 0.2, 0.4, size.z if size.z > 1 else 0.2)
		_box(parent, base, Vector3(pos.x, FLOOR_Y + 0.2, pos.z) + inward, MaterialLibrary.table_wood)


## Two tall bookcases on the back wall, filled with a MultiMesh of spines.
static func _bookshelves(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1837
	var spines := PackedColorArray([
		Color(0.28, 0.06, 0.05), Color(0.10, 0.18, 0.12), Color(0.12, 0.10, 0.20), Color(0.36, 0.24, 0.12),
		Color(0.18, 0.12, 0.08), Color(0.42, 0.34, 0.20), Color(0.06, 0.06, 0.07), Color(0.22, 0.14, 0.10),
	])
	for cx: float in [-12.5, 12.5]:
		var z := -18.5
		var width := 6.0
		var shelves := 6
		_box(parent, Vector3(width + 0.4, 10.0, 0.9), Vector3(cx, FLOOR_Y + 5.0, z - 0.1), MaterialLibrary.table_wood)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var book := BoxMesh.new()
		book.size = Vector3(1, 1, 1)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.75
		book.material = mat
		mm.mesh = book
		var xforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		for s in shelves:
			var y0 := FLOOR_Y + 0.8 + s * 1.55
			_box(parent, Vector3(width, 0.08, 0.8), Vector3(cx, y0 - 0.04, z + 0.25), MaterialLibrary.table_wood)
			var x := cx - width * 0.5 + 0.1
			while x < cx + width * 0.5 - 0.2:
				var w := rng.randf_range(0.08, 0.18)
				var hgt := rng.randf_range(0.9, 1.3)
				var lean := rng.randf_range(-0.05, 0.05) if rng.randf() < 0.15 else 0.0
				var b := Basis.from_euler(Vector3(0, 0, lean)).scaled(Vector3(w, hgt, rng.randf_range(0.55, 0.7)))
				xforms.append(Transform3D(b, Vector3(x + w * 0.5, y0 + hgt * 0.5, z + 0.3)))
				colors.append(spines[rng.randi() % spines.size()].lightened(rng.randf_range(-0.1, 0.12)))
				x += w + rng.randf_range(0.0, 0.02)
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_color(i, colors[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)


static func _fireplace(parent: Node3D) -> void:
	var x := -20.6
	var z := -6.0
	_box(parent, Vector3(0.8, 4.2, 5.6), Vector3(x, FLOOR_Y + 2.1, z), MaterialLibrary.column_mat)
	_box(parent, Vector3(1.2, 0.3, 6.2), Vector3(x + 0.2, FLOOR_Y + 4.3, z), MaterialLibrary.table_wood)
	var hearth := _box(parent, Vector3(0.3, 1.6, 2.8), Vector3(x + 0.35, FLOOR_Y + 1.1, z), MaterialLibrary.fire_glow)
	hearth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(parent, Vector3(0.1, 0.06, 3.0), Vector3(x + 0.55, FLOOR_Y + 1.95, z), MaterialLibrary.brass_mat)


static func _pendant(parent: Node3D) -> void:
	var y := 17.5
	_cyl(parent, 0.02, 0.02, 12.0, Vector3(0, y + 6.3, 1.2), MaterialLibrary.brass_mat, 8)
	var shade := _cyl(parent, 0.35, 2.2, 1.1, Vector3(0, y, 1.2), MaterialLibrary.lamp_green, 48)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cyl(parent, 2.24, 2.24, 0.05, Vector3(0, y - 0.55, 1.2), MaterialLibrary.brass_mat, 48)
	_cyl(parent, 0.4, 0.4, 0.2, Vector3(0, y + 0.62, 1.2), MaterialLibrary.brass_mat, 24)


static func _sconces(parent: Node3D) -> void:
	for p in [Vector3(-20.6, 1.4, 6.0), Vector3(20.6, 1.4, -6.0), Vector3(20.6, 1.4, 6.0), Vector3(-6.0, 1.4, -18.6), Vector3(6.0, 1.4, -18.6)]:
		var back := _box(parent, Vector3(0.4, 0.6, 0.4), p, MaterialLibrary.brass_mat)
		back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var glass := _cyl(parent, 0.22, 0.3, 0.5, p + Vector3(0, 0.5, 0) - Vector3(p.x, 0, p.z).normalized() * 0.3, MaterialLibrary.lamp_glass, 24)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var light := OmniLight3D.new()
		light.position = p + Vector3(0, 0.6, 0) - Vector3(p.x, 0, p.z).normalized() * 0.6
		light.light_color = Color(1.0, 0.74, 0.46)
		light.light_energy = 1.6
		light.omni_range = 8.0
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		parent.add_child(light)
