class_name PuzzleBrowser
extends Modal

## Built-in tactics grouped by rules variant, with progress.

var _content: VBoxContainer
var _progress: ProgressBar
var _progress_label: Label


func _init() -> void:
	super("Puzzles", 840, true, 520)
	set_subtitle("Shots, breeches, and forced wins — each verified by the test suite. Any move that still wins counts.")
	var head := UIKit.hbox(12)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 8)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.show_percentage = false
	head.add_child(_progress)
	_progress_label = UIKit.label("", "Gold")
	head.add_child(_progress_label)
	body.add_child(head)
	_content = UIKit.vbox(12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_content)
	add_footer_button(UIKit.button("Close", close, "GhostButton"))


func open() -> void:
	_populate()
	super.open()


func _populate() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	var all := _load()
	var solved := 0
	for p in all:
		if ProfileStore.is_puzzle_solved(str(p.get("id", ""))):
			solved += 1
	_progress.max_value = maxi(all.size(), 1)
	_progress.value = solved
	_progress_label.text = "%d / %d solved" % [solved, all.size()]
	if all.is_empty():
		_content.add_child(UIKit.label("No puzzles are installed.", "Muted"))
		return
	for v in ["english", "russian", "brazilian"]:
		var group: Array = []
		for i in all.size():
			if str(all[i].get("variant", "english")) == v:
				group.append(i)
		if group.is_empty():
			continue
		_content.add_child(UIKit.label(CheckersRules.variant_name(v).to_upper(), "Kicker"))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		for i in group:
			grid.add_child(_tile(all[i], i))
		_content.add_child(grid)


func _load() -> Array:
	if ClassDB.class_exists("CheckersPuzzles") or ResourceLoader.exists("res://scripts/checkers/checkers_puzzles.gd"):
		var script: Script = load("res://scripts/checkers/checkers_puzzles.gd")
		if script and script.has_method("load_all"):
			return script.call("load_all")
	return []


func _tile(p: Dictionary, index: int) -> Button:
	var b := Button.new()
	b.theme_type_variation = "ChipButton"
	b.custom_minimum_size = Vector2(186, 80)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var solved := ProfileStore.is_puzzle_solved(str(p.get("id", "")))
	var v := UIKit.vbox(3)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 9
	v.offset_right = -10
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UIKit.hbox(6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(UIKit.label("#%d" % (index + 1), "Faint"))
	top.add_child(UIKit.spacer())
	if solved:
		top.add_child(UIKit.icon_rect("check", 14, ThemeFactory.SUCCESS))
	top.add_child(UIKit.label("★".repeat(int(p.get("difficulty", 1))), "Gold"))
	v.add_child(top)
	var t := UIKit.label(str(p.get("title", "Puzzle")), "Subheader")
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(t)
	var side := CheckersTypes.WHITE if str(p.get("side", "w")) == "w" else CheckersTypes.BLACK
	var goal := "win" if str(p.get("goal", "gain")) == "win" else "gain %s" % str(p.get("gain", 1))
	v.add_child(UIKit.label("%s to play and %s" % [MaterialLibrary.side_label(side), goal], "Caption"))
	for c in v.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	b.mouse_entered.connect(func(): AudioManager.play("ui_hover"))
	b.pressed.connect(func():
		AudioManager.play("ui_click")
		GameSession.configure_puzzle(p, index)
		get_tree().change_scene_to_file("res://scenes/main/game.tscn")
	)
	return b
