class_name PieceMeshBuilder
extends RefCounted


static func ivory() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.89, 0.80)
	m.metallic = 0.22
	m.roughness = 0.32
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.rim_enabled = true
	m.rim = 0.20
	m.rim_tint = 0.4
	m.clearcoat_enabled = true
	m.clearcoat = 0.22
	m.clearcoat_roughness = 0.28
	return m


static func ebony() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.11, 0.135)
	m.metallic = 0.32
	m.roughness = 0.38
	m.rim_enabled = true
	m.rim = 0.24
	m.rim_tint = 0.18
	m.clearcoat_enabled = true
	m.clearcoat = 0.16
	return m


static func crown_metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.86, 0.92)
	m.metallic = 0.82
	m.roughness = 0.22
	m.emission_enabled = true
	m.emission = Color(0.35, 0.72, 0.82)
	m.emission_energy_multiplier = 0.18
	return m


static func material_for(color: int) -> StandardMaterial3D:
	return ivory() if color == CheckersTypes.WHITE else ebony()


static func build(type: int, color: int) -> Node3D:
	var root := Node3D.new()
	var mat := material_for(color)
	if type == CheckersTypes.KING:
		_king(root, mat)
	else:
		_man(root, mat)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.34
	cyl.height = 0.42 if type == CheckersTypes.KING else 0.22
	col.shape = cyl
	col.position.y = cyl.height * 0.5
	body.add_child(col)
	root.add_child(body)
	return root


static func _add_cyl(parent: Node3D, mat: Material, r_top: float, r_bot: float, h: float, y: float, radial := 28) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bot
	mesh.height = h
	mesh.radial_segments = radial
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = y
	parent.add_child(mi)


static func _add_torus(parent: Node3D, mat: Material, inner: float, outer: float, y: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 20
	mesh.ring_segments = 12
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = y
	parent.add_child(mi)


static func _add_box(parent: Node3D, mat: Material, size: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


static func _disc(parent: Node3D, mat: Material, y: float, scale := 1.0) -> void:
	_add_cyl(parent, mat, 0.33 * scale, 0.35 * scale, 0.045, y)
	_add_cyl(parent, mat, 0.30 * scale, 0.32 * scale, 0.055, y + 0.048)
	_add_torus(parent, mat, 0.16 * scale, 0.22 * scale, y + 0.072)


static func _man(parent: Node3D, mat: Material) -> void:
	_disc(parent, mat, 0.028, 1.0)


static func _king(parent: Node3D, mat: Material) -> void:
	_disc(parent, mat, 0.028, 1.0)
	_disc(parent, mat, 0.155, 0.94)
	var metal := crown_metal()
	_add_torus(parent, metal, 0.12, 0.20, 0.30)
	for i in 5:
		var a := i * TAU / 5.0 + 0.2
		_add_box(parent, metal, Vector3(0.035, 0.08, 0.035), Vector3(cos(a) * 0.16, 0.35, sin(a) * 0.16))
	_add_cyl(parent, metal, 0.03, 0.03, 0.05, 0.38, 10)
