extends Node

## Drives the real game through its main screens and saves screenshots.
## Launched from the main menu with:  godot --path . -- --visual-qa [--shots=DIR] [--quality=high]
## tools/capture_screenshots.sh points XDG dirs at a scratch folder first.

var _dir := "res://docs/screenshots"
var _shots: PackedStringArray = PackedStringArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_dir = a.trim_prefix("--shots=")
		elif a.begins_with("--quality="):
			SettingsStore.graphics_quality = a.trim_prefix("--quality=")
	SettingsStore.music_enabled = false
	SettingsStore.apply_audio()
	DirAccess.make_dir_recursive_absolute(_abs(_dir))
	await _run()
	print("visual_qa wrote %d shots" % _shots.size())
	for s in _shots:
		print("  ", s)
	get_tree().quit(0 if _shots.size() >= 6 else 1)


func _run() -> void:
	await _settle(4.0)
	_shot("01-main-menu")
	var menu := get_tree().current_scene
	var ng: Modal = menu.get("_new_game")
	if ng:
		ng.open()
		await _settle(0.8)
		_shot("02-new-game")
		ng.close()
		await _settle(0.4)

	GameSession.configure_ai(true, "club", "10+0", "english")
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
	await _settle(2.6)
	_shot("03-game-start")
	var world := _controller()
	if world == null:
		return
	var movable := world.engine.movable_squares()
	if not movable.is_empty():
		world._select(movable[movable.size() / 2])
		await _settle(0.6)
		_shot("04-legal-moves")
		world._deselect()

	# A short English line that sets up a capture for the second player.
	GameSession.configure_local(true, "10+0", "english")
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
	await _settle(2.0)
	world = _controller()
	for mv in ["11-15", "23-19", "8-11", "22-17", "15-18"]:
		var m := world.engine.find_uci(mv)
		if m:
			world._play(m)
			await _settle(0.9)
	_shot("05-forced-capture")
	var cap := world.engine.generate_legal_moves()
	if not cap.is_empty():
		world._play(cap[0])
		await _settle(1.2)
		_shot("06-after-capture")

	var ui := get_tree().current_scene.get_node("UI")
	ui.call("_open_settings")
	await _settle(0.9)
	_shot("07-settings")
	for c in ui.root.get_children():
		if c is SettingsPanel:
			(c as SettingsPanel).close()
	await _settle(0.4)

	GameSession.configure_analysis("", "", "russian")
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
	await _settle(2.0)
	world = _controller()
	for i in 10:
		var legal := world.engine.generate_legal_moves()
		if legal.is_empty():
			break
		world._play(legal[(i * 7) % legal.size()])
		await _settle(0.6)
	await _settle(2.0)
	_shot("08-analysis-russian")

	var puzzles: Array = []
	if ResourceLoader.exists("res://scripts/checkers/checkers_puzzles.gd"):
		puzzles = load("res://scripts/checkers/checkers_puzzles.gd").call("load_all")
	if not puzzles.is_empty():
		GameSession.configure_puzzle(puzzles[0], 0)
		get_tree().change_scene_to_file("res://scenes/main/game.tscn")
		await _settle(2.4)
		_shot("09-puzzle")

	GameSession.configure_ai(false, "master", "5+0", "brazilian")
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
	await _settle(4.5)
	world = _controller()
	if world:
		world.resign()
		await _settle(2.2)
		_shot("10-result")


func _controller() -> GameController:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("World") as GameController if scene else null


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var path := _abs(_dir).path_join(name + ".png")
	img.save_png(path)
	_shots.append(path)


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p
