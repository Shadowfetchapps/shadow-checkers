class_name PieceMeshBuilder
extends RefCounted


static func ivory() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.96, 0.91, 0.80)
	m.metallic = 0.18
	m.roughness = 0.28
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.rim_enabled = true
	m.rim = 0.28
	m.rim_tint = 0.55
	m.clearcoat_enabled = true
	m.clearcoat = 0.34
	m.clearcoat_roughness = 0.22
	return m


static func ebony() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.08, 0.11)
	m.metallic = 0.38
	m.roughness = 0.34
	m.rim_enabled = true
	m.rim = 0.32
	m.rim_tint = 0.12
	m.clearcoat_enabled = true
	m.clearcoat = 0.22
	m.emission_enabled = true
	m.emission = Color(0.08, 0.14, 0.20)
	m.emission_energy_multiplier = 0.08
	return m


static func crown_metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.78, 0.38)
	m.metallic = 0.88
	m.roughness = 0.18
	m.emission_enabled = true
	m.emission = Color(0.85, 0.62, 0.18)
	m.emission_energy_multiplier = 0.28
	return m


static func band_metal(color: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if color == CheckersTypes.WHITE:
		m.albedo_color = Color(0.62, 0.82, 0.88)
	else:
		m.albedo_color = Color(0.38, 0.72, 0.82)
	m.metallic = 0.72
	m.roughness = 0.24
	m.emission_enabled = true
	m.emission = Color(0.28, 0.62, 0.74)
	m.emission_energy_multiplier = 0.16
	return m


static func material_for(color: int) -> StandardMaterial3D:
	return ivory() if color == CheckersTypes.WHITE else ebony()


static func build(type: int, color: int) -> Node3D:
	var root := Node3D.new()
	var mat := material_for(color)
	if type == CheckersTypes.KING:
		_king(root, mat, color)
	else:
		_man(root, mat, color)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("square", -1)
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.36
	cyl.height = 0.48 if type == CheckersTypes.KING else 0.26
	col.shape = cyl
	col.position.y = cyl.height * 0.5
	body.add_child(col)
	root.add_child(body)
	return root


static func _add_cyl(parent: Node3D, mat: Material, r_top: float, r_bot: float, h: float, y: float, radial := 32) -> MeshInstance3D:
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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static func _add_torus(parent: Node3D, mat: Material, inner: float, outer: float, y: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 24
	mesh.ring_segments = 16
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


static func _add_sphere(parent: Node3D, mat: Material, r: float, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


static func _disc(parent: Node3D, mat: Material, y: float, scale := 1.0, band: Material = null) -> void:
	_add_cyl(parent, mat, 0.345 * scale, 0.365 * scale, 0.05, y)
	_add_cyl(parent, mat, 0.312 * scale, 0.334 * scale, 0.062, y + 0.052)
	_add_torus(parent, band if band else mat, 0.15 * scale, 0.225 * scale, y + 0.078)


static func _man(parent: Node3D, mat: Material, color: int) -> void:
	_disc(parent, mat, 0.03, 1.0, band_metal(color))


static func _king(parent: Node3D, mat: Material, color: int) -> void:
	var band := band_metal(color)
	_disc(parent, mat, 0.03, 1.0, band)
	_disc(parent, mat, 0.168, 0.93, band)
	var metal := crown_metal()
	_add_torus(parent, metal, 0.11, 0.205, 0.318)
	for i in 6:
		var a := i * TAU / 6.0 + 0.18
		_add_box(parent, metal, Vector3(0.032, 0.095, 0.032), Vector3(cos(a) * 0.155, 0.375, sin(a) * 0.155))
	_add_sphere(parent, metal, 0.042, Vector3(0, 0.43, 0))
