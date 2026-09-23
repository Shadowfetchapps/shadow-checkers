class_name PieceMeshBuilder
extends RefCounted

## Builds checker visuals. Authored meshes come from res://assets/models
## (man.obj, king.obj — tools/assetgen/build_models.py, Blender). Each has a
## `body` surface and a `trim` surface (brass ring / crown emblem) whose
## materials come from MaterialLibrary. Missing models fall back to lathed
## primitives so the game still runs.

const MODEL_DIR := "res://assets/models/"

static var _meshes: Dictionary = {}
static var _fallback: Dictionary = {}


static func mesh_for(type: int) -> Mesh:
	if _meshes.has(type):
		return _meshes[type]
	var path := MODEL_DIR + ("king.obj" if type == CheckersTypes.KING else "man.obj")
	var mesh: Mesh = load(path) as Mesh if ResourceLoader.exists(path) else null
	if mesh == null:
		mesh = _fallback_mesh(type)
	_meshes[type] = mesh
	return mesh


static func has_model(type: int) -> bool:
	return ResourceLoader.exists(MODEL_DIR + ("king.obj" if type == CheckersTypes.KING else "man.obj"))


static func height_of(type: int) -> float:
	return mesh_for(type).get_aabb().end.y


static func radius_of(type: int) -> float:
	var aabb := mesh_for(type).get_aabb()
	return maxf(aabb.size.x, aabb.size.z) * 0.5


## Surface index -> "body" / "trim" using surface names, material names, or order.
static func surface_role(mesh: Mesh, idx: int) -> String:
	var name := ""
	if mesh is ArrayMesh:
		name = (mesh as ArrayMesh).surface_get_name(idx).to_lower()
	if name.is_empty():
		var mat := mesh.surface_get_material(idx)
		if mat:
			name = mat.resource_name.to_lower()
	if "trim" in name or "gold" in name or "crown" in name:
		return "trim"
	if "body" in name:
		return "body"
	return "body" if idx == 0 else "trim"


static func build(type: int, color: int) -> Node3D:
	MaterialLibrary.ensure()
	var visual := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh_for(type)
	apply_materials(mi, color)
	visual.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius_of(type) * 0.92
	cyl.height = maxf(height_of(type), 0.12)
	col.shape = cyl
	col.position.y = cyl.height * 0.5
	body.add_child(col)
	visual.add_child(body)
	return visual


static func apply_materials(mi: MeshInstance3D, color: int) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var role := surface_role(mesh, i)
		mi.set_surface_override_material(i, MaterialLibrary.piece_trim(color) if role == "trim" else MaterialLibrary.piece_body(color))


## Lathed disc with a reeded look approximated by a bevelled rim, and a trim ring.
static func _fallback_mesh(type: int) -> ArrayMesh:
	var layers := 2 if type == CheckersTypes.KING else 1
	var am := ArrayMesh.new()
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in layers:
		var y0 := layer * 0.15
		var s := 1.0 if layer == 0 else 0.97
		var profile := [
			Vector2(0.0, y0), Vector2(0.35 * s, y0), Vector2(0.378 * s, y0 + 0.02), Vector2(0.38 * s, y0 + 0.12),
			Vector2(0.36 * s, y0 + 0.148), Vector2(0.30 * s, y0 + 0.15), Vector2(0.0, y0 + 0.142),
		]
		_lathe(body, profile, 48)
		_lathe(trim, [Vector2(0.24 * s, y0 + 0.151), Vector2(0.21 * s, y0 + 0.151)], 48)
	body.generate_normals()
	trim.generate_normals()
	body.commit(am)
	am.surface_set_name(0, "body")
	trim.commit(am)
	am.surface_set_name(1, "trim")
	return am


static func _lathe(st: SurfaceTool, profile: Array, segments: int) -> void:
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		for j in profile.size() - 1:
			var p0: Vector2 = profile[j]
			var p1: Vector2 = profile[j + 1]
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			for v in [v00, v10, v11, v00, v11, v01]:
				st.add_vertex(v)
