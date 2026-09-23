class_name WorldLook
extends RefCounted

## Environment, lighting rig, and quality tiers for the club room. An HDR
## panorama (tools/assetgen/gen_textures.py) feeds ambient light and
## reflections; a green-shaded pendant lamp is the key light over the table.

const ENV_HDR := "res://assets/textures/env/club.hdr"

static var _sky: Sky


static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.010, 0.012, 0.010)
	var sky := _salon_sky()
	if sky:
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 1.0
		env.ambient_light_energy = 0.6
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.36, 0.34, 0.26)
		env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_radius = 0.7
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.7
	env.ssr_max_steps = 56
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.2
	env.ssr_depth_tolerance = 0.25
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.025, 0.028, 0.022)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(1.0, 0.92, 0.82)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 40.0
	env.volumetric_fog_ambient_inject = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.04
	apply_quality(env)
	return env


static func apply_quality(env: Environment) -> void:
	if env == null:
		return
	env.glow_enabled = SettingsStore.bloom_enabled()
	env.ssao_enabled = SettingsStore.ssao_enabled()
	env.ssil_enabled = SettingsStore.ssil_enabled()
	env.ssr_enabled = SettingsStore.ssr_enabled()
	env.volumetric_fog_enabled = SettingsStore.volumetric_fog_enabled()
	env.fog_enabled = SettingsStore.graphics_quality != "low"


static func make_camera_attributes() -> CameraAttributesPractical:
	var attrs := CameraAttributesPractical.new()
	apply_camera_quality(attrs, 14.0)
	return attrs


static func apply_camera_quality(attrs: CameraAttributesPractical, focus: float) -> void:
	if attrs == null:
		return
	attrs.dof_blur_far_enabled = SettingsStore.dof_enabled()
	attrs.dof_blur_far_distance = focus + 7.0
	attrs.dof_blur_far_transition = 12.0
	attrs.dof_blur_amount = 0.07
	attrs.dof_blur_near_enabled = false


static func _salon_sky() -> Sky:
	if _sky:
		return _sky
	if not ResourceLoader.exists(ENV_HDR):
		return null
	var tex: Texture2D = load(ENV_HDR)
	if tex == null:
		return null
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = tex
	mat.energy_multiplier = 1.0
	_sky = Sky.new()
	_sky.sky_material = mat
	_sky.radiance_size = Sky.RADIANCE_SIZE_256
	return _sky


static func add_lights(parent: Node3D) -> Dictionary:
	var nodes := {}
	# Key: the pendant lamp's bulb, straight above the board.
	var key := SpotLight3D.new()
	key.name = "PendantKey"
	key.position = Vector3(0.0, 15.0, 1.2)
	key.light_color = Color(1.0, 0.90, 0.74)
	key.light_energy = 26.0
	key.spot_range = 34.0
	key.spot_angle = 30.0
	key.spot_angle_attenuation = 1.4
	key.spot_attenuation = 0.8
	key.light_size = 0.4
	key.shadow_enabled = SettingsStore.shadows_enabled()
	key.shadow_bias = 0.03
	key.shadow_normal_bias = 1.0
	key.shadow_blur = 1.6
	key.light_volumetric_fog_energy = 1.4
	parent.add_child(key)
	key.look_at_from_position(key.position, Vector3(0, 0.2, 0.4))
	nodes["key"] = key

	var fire := OmniLight3D.new()
	fire.name = "FireGlow"
	fire.position = Vector3(-17.0, -1.2, -6.0)
	fire.light_color = Color(1.0, 0.48, 0.18)
	fire.light_energy = 5.0
	fire.omni_range = 22.0
	fire.omni_attenuation = 1.3
	fire.shadow_enabled = false
	parent.add_child(fire)
	nodes["fire"] = fire

	var rim := SpotLight3D.new()
	rim.name = "RimSpot"
	rim.position = Vector3(5.0, 9.0, -12.0)
	rim.light_color = Color(0.92, 0.86, 0.70)
	rim.light_energy = 12.0
	rim.spot_range = 28.0
	rim.spot_angle = 26.0
	rim.shadow_enabled = false
	parent.add_child(rim)
	rim.look_at_from_position(rim.position, Vector3(0, 0.4, 0))
	nodes["rim"] = rim

	var fill := DirectionalLight3D.new()
	fill.name = "WindowFill"
	fill.light_color = Color(0.60, 0.72, 0.92)
	fill.light_energy = 0.16
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-30, -120, 0)
	parent.add_child(fill)
	nodes["fill"] = fill

	var bounce := OmniLight3D.new()
	bounce.name = "TableBounce"
	bounce.position = Vector3(0, 2.4, 2.0)
	bounce.light_color = Color(0.92, 1.0, 0.86)
	bounce.light_energy = 0.45
	bounce.omni_range = 9.0
	bounce.shadow_enabled = false
	parent.add_child(bounce)
	nodes["bounce"] = bounce

	if SettingsStore.graphics_quality in ["high", "ultra"]:
		var probe := ReflectionProbe.new()
		probe.name = "ClubProbe"
		probe.size = Vector3(40, 16, 40)
		probe.position = Vector3(0, 2.0, 0)
		probe.box_projection = true
		probe.interior = true
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.intensity = 0.9
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		parent.add_child(probe)
		nodes["probe"] = probe
	return nodes


static func apply_light_quality(nodes: Dictionary) -> void:
	var key: SpotLight3D = nodes.get("key")
	if key:
		key.shadow_enabled = SettingsStore.shadows_enabled()
