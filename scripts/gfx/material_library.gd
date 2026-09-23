class_name MaterialLibrary
extends RefCounted

## Shared materials for the board, pieces, club room, and highlight marks.
## Materials are created once and mutated in place by `apply_theme`, so a
## theme change restyles every live instance without rebuilding the scene.
## Textures come from res://assets/textures (tools/assetgen/gen_textures.py);
## if a set is missing, a small procedural stand-in is generated instead.

const TEX_DIR := "res://assets/textures/"
const SQUARE_VARIANTS := 4

const BOARD_THEMES := {
	"club": {
		"name": "Club Room", "blurb": "Maple and mahogany with a brass inlay.",
		"light": "sq_maple", "dark": "sq_mahogany", "frame": "frame_mahogany",
		"light_color": Color(0.84, 0.70, 0.48), "dark_color": Color(0.30, 0.10, 0.06), "frame_color": Color(0.26, 0.09, 0.05),
		"light_rough": 0.9, "dark_rough": 0.85, "frame_rough": 0.8, "coat": 0.4,
		"inlay": "brass", "coord": Color(0.94, 0.84, 0.62),
	},
	"classic": {
		"name": "Red & Black", "blurb": "The traditional lacquered draughtboard.",
		"light": "sq_lacquer_red", "dark": "sq_lacquer_black", "frame": "frame_lacquer_black",
		"light_color": Color(0.55, 0.07, 0.05), "dark_color": Color(0.03, 0.03, 0.03), "frame_color": Color(0.03, 0.03, 0.03),
		"light_rough": 0.7, "dark_rough": 0.7, "frame_rough": 0.7, "coat": 0.7,
		"inlay": "gold", "coord": Color(0.95, 0.82, 0.52),
	},
	"slate": {
		"name": "Slate & Stone", "blurb": "Cream limestone and cleft slate, smoked oak.",
		"light": "sq_stone_cream", "dark": "sq_slate", "frame": "frame_oak_smoked",
		"light_color": Color(0.82, 0.78, 0.68), "dark_color": Color(0.16, 0.18, 0.20), "frame_color": Color(0.14, 0.11, 0.08),
		"light_rough": 1.0, "dark_rough": 1.0, "frame_rough": 0.9, "coat": 0.1,
		"inlay": "silver", "coord": Color(0.90, 0.90, 0.86),
	},
	"marble": {
		"name": "Marble Hall", "blurb": "Carrara and Nero Marquina, verde frame.",
		"light": "sq_marble_white", "dark": "sq_marble_black", "frame": "frame_marble_green",
		"light_color": Color(0.88, 0.87, 0.85), "dark_color": Color(0.06, 0.06, 0.065), "frame_color": Color(0.08, 0.14, 0.11),
		"light_rough": 0.6, "dark_rough": 0.55, "frame_rough": 0.6, "coat": 0.6,
		"inlay": "gold", "coord": Color(0.92, 0.88, 0.76),
	},
}

const PIECE_STYLES := {
	"club": {
		"name": "Cream & Mahogany", "white_tex": "piece_cream", "black_tex": "piece_mahogany_red",
		"white": Color(0.92, 0.86, 0.72), "black": Color(0.34, 0.08, 0.05),
		"white_rough": 0.35, "black_rough": 0.3, "coat": 0.5, "trim": "brass", "tex_strength": 1.0,
		"names": ["White", "Black"],
	},
	"classic": {
		"name": "Red & Black", "white_tex": "", "black_tex": "",
		"white": Color(0.62, 0.06, 0.05), "black": Color(0.03, 0.03, 0.035),
		"white_rough": 0.22, "black_rough": 0.2, "coat": 0.8, "trim": "gold", "tex_strength": 0.0,
		"names": ["Red", "Black"],
	},
	"ivory": {
		"name": "Ivory & Ebony", "white_tex": "piece_ivory", "black_tex": "piece_ebony",
		"white": Color(0.95, 0.91, 0.82), "black": Color(0.055, 0.05, 0.055),
		"white_rough": 0.32, "black_rough": 0.2, "coat": 0.55, "trim": "gold", "tex_strength": 1.0,
		"names": ["White", "Black"],
	},
	"stone": {
		"name": "Marble", "white_tex": "sq_marble_white", "black_tex": "sq_marble_black",
		"white": Color(0.92, 0.92, 0.91), "black": Color(0.07, 0.07, 0.08),
		"white_rough": 0.25, "black_rough": 0.22, "coat": 0.7, "trim": "silver", "tex_strength": 1.0,
		"names": ["White", "Black"],
	},
}

const METALS := {
	"gold": {"color": Color(1.0, 0.78, 0.36), "rough": 0.26},
	"brass": {"color": Color(0.86, 0.64, 0.32), "rough": 0.34},
	"silver": {"color": Color(0.93, 0.93, 0.95), "rough": 0.2},
}

static var _ready := false
static var _tex_cache: Dictionary = {}
static var current_board := "club"
static var current_pieces := "club"

static var light_sq: Array[StandardMaterial3D] = []
static var dark_sq: Array[StandardMaterial3D] = []
static var frame_mat: StandardMaterial3D
static var inlay_mat: StandardMaterial3D
static var base_mat: StandardMaterial3D
static var piece_white: StandardMaterial3D
static var piece_black: StandardMaterial3D
static var trim_white: StandardMaterial3D
static var trim_black: StandardMaterial3D
static var felt_mat: StandardMaterial3D

static var gold_mat: StandardMaterial3D
static var brass_mat: StandardMaterial3D
static var floor_mat: StandardMaterial3D
static var wall_mat: StandardMaterial3D
static var rug_mat: StandardMaterial3D
static var leather_mat: StandardMaterial3D
static var table_wood: StandardMaterial3D
static var drape_mat: StandardMaterial3D
static var column_mat: StandardMaterial3D
static var lamp_glass: StandardMaterial3D
static var gold_emit: StandardMaterial3D
static var clock_face: StandardMaterial3D

static var mark_legal: StandardMaterial3D
static var mark_capture: StandardMaterial3D
static var mark_select: StandardMaterial3D
static var mark_last: StandardMaterial3D
static var mark_check: StandardMaterial3D
static var mark_hover: StandardMaterial3D
static var mark_hint: StandardMaterial3D
static var mark_premove: StandardMaterial3D
static var mark_movable: StandardMaterial3D
static var mark_path: StandardMaterial3D
static var lamp_green: StandardMaterial3D
static var fire_glow: StandardMaterial3D
static var contact_shadow: StandardMaterial3D

# Legacy aliases used by older code paths and tests.
static var ivory_mat: StandardMaterial3D
static var ebony_mat: StandardMaterial3D
static var gold_trim_mat: StandardMaterial3D
static var legal_mat: StandardMaterial3D


static func ensure() -> void:
	if _ready:
		return
	_ready = true
	for i in SQUARE_VARIANTS:
		light_sq.append(_pbr(Color.WHITE, 0.8, 0.0))
		dark_sq.append(_pbr(Color.WHITE, 0.8, 0.0))
	frame_mat = _pbr(Color.WHITE, 0.8, 0.0)
	inlay_mat = _pbr(Color.WHITE, 0.3, 1.0)
	base_mat = _pbr(Color(0.03, 0.025, 0.02), 0.9, 0.0)
	piece_white = _pbr(Color.WHITE, 0.3, 0.0)
	piece_black = _pbr(Color.WHITE, 0.2, 0.0)
	trim_white = _pbr(Color.WHITE, 0.3, 1.0)
	trim_black = _pbr(Color.WHITE, 0.3, 1.0)
	felt_mat = _textured("felt_green", Color(0.04, 0.12, 0.08), 0.95, 0.0, Vector3(4, 4, 4))

	gold_mat = _metal("gold")
	brass_mat = _metal("brass")
	var brushed := _tex("brass_brushed", "rough")
	if brushed:
		brass_mat.roughness_texture = brushed
		brass_mat.roughness = 0.9
	floor_mat = _textured("floor_plank_oak", Color(0.22, 0.14, 0.08), 0.7, 0.0, Vector3(0.1, 0.1, 0.1), true)
	wall_mat = _textured("wall_panel_wood", Color(0.12, 0.07, 0.04), 0.7, 0.0, Vector3(0.18, 0.18, 0.18), true)
	rug_mat = _textured("felt_green", Color(0.04, 0.12, 0.08), 0.95, 0.0, Vector3(3, 3, 3))
	leather_mat = _textured("table_leather_green", Color(0.04, 0.12, 0.08), 0.55, 0.0, Vector3(0.45, 0.45, 0.45), true)
	leather_mat.clearcoat_enabled = true
	leather_mat.clearcoat = 0.3
	table_wood = _textured("frame_mahogany", Color(0.24, 0.08, 0.05), 0.6, 0.0, Vector3(0.35, 0.35, 0.35), true)
	table_wood.clearcoat_enabled = true
	table_wood.clearcoat = 0.4
	table_wood.clearcoat_roughness = 0.2
	drape_mat = _pbr(Color(0.20, 0.045, 0.05), 0.85, 0.0)
	drape_mat.rim_enabled = true
	drape_mat.rim = 0.3
	column_mat = _textured("frame_oak_smoked", Color(0.14, 0.1, 0.07), 0.5, 0.0, Vector3(0.5, 0.5, 0.5), true)
	lamp_green = _pbr(Color(0.10, 0.36, 0.20, 1.0), 0.12, 0.0)
	lamp_green.clearcoat_enabled = true
	lamp_green.clearcoat = 1.0
	lamp_green.emission_enabled = true
	lamp_green.emission = Color(0.20, 0.55, 0.30)
	lamp_green.emission_energy_multiplier = 0.6
	fire_glow = _unshaded(Color(1.0, 0.45, 0.15), 3.0)
	lamp_glass = _pbr(Color(1.0, 0.86, 0.58, 0.55), 0.2, 0.0)
	lamp_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lamp_glass.emission_enabled = true
	lamp_glass.emission = Color(1.0, 0.72, 0.38)
	lamp_glass.emission_energy_multiplier = 2.4
	gold_emit = _unshaded(Color(0.95, 0.78, 0.42), 1.2)
	clock_face = _unshaded(Color(0.02, 0.02, 0.018), 0.0)

	_build_marks()
	apply_theme(current_board, current_pieces)

	ivory_mat = piece_white
	ebony_mat = piece_black
	gold_trim_mat = trim_white
	legal_mat = mark_legal


static func piece_body(color: int) -> StandardMaterial3D:
	ensure()
	return piece_white if color == CheckersTypes.WHITE else piece_black


static func piece_trim(color: int) -> StandardMaterial3D:
	ensure()
	return trim_white if color == CheckersTypes.WHITE else trim_black


static func light_square(variant: int) -> StandardMaterial3D:
	ensure()
	return light_sq[posmod(variant, SQUARE_VARIANTS)]


static func dark_square(variant: int) -> StandardMaterial3D:
	ensure()
	return dark_sq[posmod(variant, SQUARE_VARIANTS)]


static func coord_color() -> Color:
	return BOARD_THEMES.get(current_board, BOARD_THEMES["club"])["coord"]


## Display name for a side under the current piece style ("Red" for the
## classic red-and-black set).
static func side_label(side: int) -> String:
	var names: Array = PIECE_STYLES.get(current_pieces, PIECE_STYLES["club"])["names"]
	return str(names[0 if side == CheckersTypes.WHITE else 1])


static func apply_theme(board_theme: String, piece_style: String) -> void:
	if not _ready:
		current_board = board_theme
		current_pieces = piece_style
		ensure()
		return
	current_board = board_theme if BOARD_THEMES.has(board_theme) else "club"
	current_pieces = piece_style if PIECE_STYLES.has(piece_style) else "club"
	var bt: Dictionary = BOARD_THEMES[current_board]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	for i in SQUARE_VARIANTS:
		var off := Vector3(float(i % 2) * 0.5, float(int(i / 2.0)) * 0.5, 0.0)
		_style_surface(light_sq[i], bt["light"], bt["light_color"], bt["light_rough"], bt["coat"], Vector3(0.5, 0.5, 1.0), off)
		_style_surface(dark_sq[i], bt["dark"], bt["dark_color"], bt["dark_rough"], bt["coat"], Vector3(0.5, 0.5, 1.0), off)
	_style_surface(frame_mat, bt["frame"], bt["frame_color"], bt["frame_rough"], bt["coat"], Vector3(0.45, 0.45, 0.45), Vector3.ZERO, true)
	var inlay: String = bt["inlay"]
	if inlay == "none":
		_copy_look(inlay_mat, frame_mat)
		inlay_mat.albedo_color = frame_mat.albedo_color.darkened(0.3)
	else:
		_style_metal(inlay_mat, inlay)

	var ps: Dictionary = PIECE_STYLES[current_pieces]
	_style_piece(piece_white, ps["white_tex"], ps["white"], ps["white_rough"], ps["coat"], ps["tex_strength"])
	_style_piece(piece_black, ps["black_tex"], ps["black"], ps["black_rough"], ps["coat"], ps["tex_strength"])
	var trim: String = ps["trim"]
	if trim == "body":
		_copy_look(trim_white, piece_white)
		_copy_look(trim_black, piece_black)
		trim_white.albedo_color = piece_white.albedo_color.darkened(0.08)
		trim_black.albedo_color = piece_black.albedo_color.lightened(0.06)
	else:
		_style_metal(trim_white, trim)
		_style_metal(trim_black, trim)
	_style_marks()


static func set_high_contrast(on: bool) -> void:
	ensure()
	mark_legal.albedo_color.a = 1.0 if on else 0.95
	mark_capture.albedo_color.a = 1.0 if on else 0.95
	mark_last.albedo_color.a = 0.55 if on else 0.32
	mark_select.albedo_color.a = 0.75 if on else 0.5


# --- Styling helpers ----------------------------------------------------------

static func _style_surface(m: StandardMaterial3D, tex_name: String, fallback: Color, rough: float, coat: float, uv_scale: Vector3, uv_off: Vector3, triplanar: bool = false) -> void:
	var albedo := _tex(tex_name, "albedo")
	m.albedo_texture = albedo
	m.albedo_color = Color.WHITE if albedo else fallback
	if albedo == null:
		m.albedo_texture = _fallback_tex(tex_name, fallback)
		m.albedo_color = Color.WHITE
	var normal := _tex(tex_name, "normal")
	m.normal_enabled = normal != null
	m.normal_texture = normal
	m.normal_scale = 0.8
	var r := _tex(tex_name, "rough")
	m.roughness_texture = r
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = rough if r else clampf(rough * 0.6, 0.05, 1.0)
	m.metallic = 0.0
	m.clearcoat_enabled = coat > 0.0
	m.clearcoat = coat
	m.clearcoat_roughness = 0.28
	m.uv1_triplanar = triplanar
	m.uv1_world_triplanar = false
	m.uv1_scale = uv_scale
	m.uv1_offset = uv_off
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


static func _style_piece(m: StandardMaterial3D, tex_name: String, color: Color, rough: float, coat: float, strength: float) -> void:
	var albedo := _tex(tex_name, "albedo") if strength > 0.0 and tex_name != "" else null
	m.albedo_texture = albedo
	m.albedo_color = Color.WHITE if albedo else color
	var normal := _tex(tex_name, "normal") if albedo else null
	m.normal_enabled = normal != null
	m.normal_texture = normal
	m.normal_scale = 0.35
	m.roughness_texture = null
	m.roughness = rough
	m.metallic = 0.0
	m.metallic_specular = 0.55
	m.clearcoat_enabled = coat > 0.0
	m.clearcoat = coat
	m.clearcoat_roughness = 0.1
	m.rim_enabled = true
	m.rim = 0.12
	m.rim_tint = 0.4
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3(2.2, 2.2, 2.2)
	m.uv1_triplanar_sharpness = 2.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


static func _style_metal(m: StandardMaterial3D, kind: String) -> void:
	var spec: Dictionary = METALS.get(kind, METALS["gold"])
	m.albedo_texture = null
	m.albedo_color = spec["color"]
	m.metallic = 1.0
	m.roughness = spec["rough"]
	m.roughness_texture = null
	m.normal_enabled = false
	m.normal_texture = null
	m.clearcoat_enabled = false
	m.rim_enabled = false
	m.uv1_triplanar = false
	m.emission_enabled = false


static func _copy_look(dst: StandardMaterial3D, src: StandardMaterial3D) -> void:
	dst.albedo_texture = src.albedo_texture
	dst.albedo_color = src.albedo_color
	dst.metallic = src.metallic
	dst.roughness = src.roughness
	dst.roughness_texture = src.roughness_texture
	dst.normal_enabled = src.normal_enabled
	dst.normal_texture = src.normal_texture
	dst.clearcoat_enabled = src.clearcoat_enabled
	dst.clearcoat = src.clearcoat
	dst.uv1_triplanar = src.uv1_triplanar
	dst.uv1_scale = src.uv1_scale


static func _pbr(albedo: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return m


static func _metal(kind: String) -> StandardMaterial3D:
	var m := _pbr(Color.WHITE, 0.3, 1.0)
	_style_metal(m, kind)
	return m


static func _textured(name: String, fallback: Color, rough: float, metal: float, uv_scale: Vector3, triplanar: bool = false) -> StandardMaterial3D:
	var m := _pbr(fallback, rough, metal)
	var albedo := _tex(name, "albedo")
	if albedo:
		m.albedo_texture = albedo
		m.albedo_color = Color.WHITE
	var normal := _tex(name, "normal")
	if normal:
		m.normal_enabled = true
		m.normal_texture = normal
	var r := _tex(name, "rough")
	if r:
		m.roughness_texture = r
		m.roughness = 1.0
	m.uv1_scale = uv_scale
	m.uv1_triplanar = triplanar
	m.uv1_world_triplanar = triplanar
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _unshaded(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	return m


static func _tex(name: String, kind: String) -> Texture2D:
	if name.is_empty():
		return null
	var key := name + "_" + kind
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = null
	for ext in [".jpg", ".png", ".webp"]:
		var p: String = TEX_DIR + key + ext
		if ResourceLoader.exists(p):
			tex = load(p)
			break
	_tex_cache[key] = tex
	return tex


# --- Highlight marks ------------------------------------------------------------

static func _build_marks() -> void:
	# Two-tone marks: a bright core inside a dark outline reads on pale and
	# dark squares alike.
	mark_legal = _mark(_radial_tex([[0.0, Color(0.56, 0.96, 0.74, 1)], [0.50, Color(0.56, 0.96, 0.74, 1)], [0.58, Color(0.03, 0.12, 0.08, 0.85)], [0.76, Color(0.03, 0.12, 0.08, 0.85)], [0.9, Color(0, 0, 0, 0)]]), Color(1, 1, 1, 0.95), 0.0, false)
	mark_capture = _mark(_radial_tex([[0.0, Color(0, 0, 0, 0)], [0.66, Color(0, 0, 0, 0)], [0.70, Color(0.03, 0.12, 0.08, 0.85)], [0.76, Color(1.0, 0.52, 0.30, 1)], [0.86, Color(1.0, 0.52, 0.30, 1)], [0.9, Color(0.03, 0.12, 0.08, 0.85)], [0.98, Color(0, 0, 0, 0)]]), Color(1, 1, 1, 0.95), 0.0, false)
	mark_select = _mark(_square_tex(0.10, 0.45), Color(0.98, 0.82, 0.42, 0.5), 0.9, false)
	mark_last = _mark(_square_tex(0.02, 0.0), Color(0.95, 0.76, 0.34, 0.32), 0.5, false)
	mark_check = _mark(_radial_tex([[0.0, Color(1, 1, 1, 0.95)], [0.45, Color(1, 1, 1, 0.55)], [1.0, Color(1, 1, 1, 0)]]), Color(1.0, 0.18, 0.14, 0.95), 2.2, true)
	mark_hover = _mark(_outline_tex(0.06), Color(1.0, 0.90, 0.62, 0.75), 0.9, false)
	mark_hint = _mark(null, Color(0.55, 0.85, 1.0, 0.85), 1.6, false)
	mark_hint.cull_mode = BaseMaterial3D.CULL_DISABLED
	mark_premove = _mark(_square_tex(0.02, 0.0), Color(0.45, 0.70, 1.0, 0.35), 0.6, false)
	mark_movable = _mark(_radial_tex([[0.0, Color(1, 1, 1, 0)], [0.62, Color(1, 1, 1, 0.0)], [0.78, Color(1, 1, 1, 0.9)], [0.86, Color(1, 1, 1, 0.9)], [1.0, Color(1, 1, 1, 0)]]), Color(0.42, 0.86, 0.64, 0.75), 1.1, false)
	mark_path = _mark(_radial_tex([[0.0, Color(1, 1, 1, 1)], [0.5, Color(1, 1, 1, 0.9)], [1.0, Color(1, 1, 1, 0)]]), Color(0.98, 0.84, 0.46, 0.8), 1.2, false)
	contact_shadow = StandardMaterial3D.new()
	contact_shadow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	contact_shadow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	contact_shadow.albedo_color = Color(0, 0, 0, 0.55)
	contact_shadow.albedo_texture = _radial_tex([[0.0, Color(1, 1, 1, 1)], [0.55, Color(1, 1, 1, 0.55)], [1.0, Color(1, 1, 1, 0)]])
	contact_shadow.disable_receive_shadows = true
	contact_shadow.render_priority = -1


static func _style_marks() -> void:
	mark_legal.albedo_color = Color(1, 1, 1, mark_legal.albedo_color.a)


static func _mark(tex: Texture2D, c: Color, energy: float, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.albedo_texture = tex
	m.emission_enabled = energy > 0.0
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = energy
	m.disable_receive_shadows = true
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_BACK
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


static func _radial_tex(stops: Array) -> GradientTexture2D:
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(float(s[0]))
		colors.append(s[1])
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


## Filled rounded square with a brighter rim; `rim` in UV units.
static func _square_tex(rim: float, rim_boost: float) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n)
			var v := (float(y) + 0.5) / float(n)
			var edge := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
			var a := smoothstep(0.0, 0.03, edge)
			if rim > 0.0:
				a *= 0.75 + rim_boost * (1.0 - smoothstep(0.0, rim, edge))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func _outline_tex(width: float) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n)
			var v := (float(y) + 0.5) / float(n)
			var edge := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
			var a := 1.0 - smoothstep(width * 0.6, width, edge)
			a *= smoothstep(0.0, 0.012, edge)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


# --- Procedural stand-ins when an authored texture is missing ------------------

static func _fallback_tex(name: String, base: Color) -> Texture2D:
	var key := "fallback_" + name
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var dark := base.darkened(0.25)
	for y in 128:
		for x in 128:
			var n := _fbm(float(x) * 0.05, float(y) * 0.012, name.hash() % 97)
			img.set_pixel(x, y, base.lerp(dark, clampf(n * 0.8, 0.0, 1.0)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


static func _hash(x: int, y: int, seed: int) -> float:
	var n := x * 374761393 + y * 668265263 + seed * 1274126177
	n = (n ^ (n >> 13)) * 1274126177
	return float(n & 0x7fffffff) / 2147483647.0


static func _vnoise(x: float, y: float, seed: int) -> float:
	var x0 := int(floor(x))
	var y0 := int(floor(y))
	var fx := x - float(x0)
	var fy := y - float(y0)
	var u := fx * fx * (3.0 - 2.0 * fx)
	var v := fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(_hash(x0, y0, seed), _hash(x0 + 1, y0, seed), u), lerpf(_hash(x0, y0 + 1, seed), _hash(x0 + 1, y0 + 1, seed), u), v)


static func _fbm(x: float, y: float, seed: int) -> float:
	return _vnoise(x, y, seed) * 0.57 + _vnoise(x * 2.1, y * 2.1, seed + 17) * 0.28 + _vnoise(x * 4.3, y * 4.3, seed + 31) * 0.15
