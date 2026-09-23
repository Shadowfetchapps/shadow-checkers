class_name PieceIcons
extends Node

## Renders the actual 3D discs (current style) into small UI thumbnails in a
## single off-screen pass, cached per piece style.

signal icons_ready

const CELL := 112

static var _icons: Dictionary = {}
static var _style := ""

var _busy := false


static func get_icon(type: int, color: int) -> Texture2D:
	return _icons.get("%d_%d" % [color, type])


static func has_icons() -> bool:
	return not _icons.is_empty() and _style == MaterialLibrary.current_pieces


func render() -> void:
	if has_icons():
		icons_ready.emit()
		return
	if _busy or DisplayServer.get_name() == "headless":
		return
	_busy = true
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL * 4, CELL)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky_env := WorldLook.make_environment()
	if sky_env.sky:
		env.sky = sky_env.sky
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.9
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.5, 0.48, 0.42)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -30, 0)
	key.light_energy = 1.6
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 160, 0)
	rim.light_energy = 1.0
	world.add_child(rim)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.position = Vector3(0, 1.4, 1.4)
	cam.rotation_degrees = Vector3(-45, 0, 0)
	cam.current = true
	world.add_child(cam)
	var order := [[CheckersTypes.MAN, CheckersTypes.WHITE], [CheckersTypes.KING, CheckersTypes.WHITE], [CheckersTypes.MAN, CheckersTypes.BLACK], [CheckersTypes.KING, CheckersTypes.BLACK]]
	for i in order.size():
		var v := PieceMeshBuilder.build(order[i][0], order[i][1])
		v.position = Vector3((i - 1.5) * 1.0, 0.0, 0.0) + Vector3(0, -0.14, -0.14)
		world.add_child(v)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img:
		_icons.clear()
		for i in order.size():
			var region := img.get_region(Rect2i(i * CELL, 0, CELL, CELL))
			region.generate_mipmaps()
			_icons["%d_%d" % [order[i][1], order[i][0]]] = ImageTexture.create_from_image(region)
		_style = MaterialLibrary.current_pieces
	vp.queue_free()
	_busy = false
	icons_ready.emit()
