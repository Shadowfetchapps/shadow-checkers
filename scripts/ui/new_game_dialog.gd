class_name NewGameDialog
extends Modal

## Set up a game: opponent, rules variant, side, Shadow's strength, clock,
## and an optional custom starting position. Remembers the last choices.

var _mode := "ai"
var _variant := "english"
var _order := "first"
var _level := "club"
var _clock := "10+0"
var _start := "standard"
var _ai_section: VBoxContainer
var _order_row: Control
var _order_holder: VBoxContainer
var _variant_blurb: Label
var _fen_edit: LineEdit
var _fen_error: Label


func _init() -> void:
	super("New game", 780, true, 580)
	var last := SettingsStore.last_new_game
	_mode = str(last.get("mode", "ai"))
	_variant = str(last.get("variant", SettingsStore.variant))
	_order = str(last.get("order", "first"))
	_level = str(last.get("level", SettingsStore.ai_level))
	_clock = str(last.get("clock", SettingsStore.clock_preset))

	body.add_child(UIKit.label("OPPONENT", "Kicker"))
	body.add_child(UIKit.chips([["Play Shadow", "ai"], ["Two players, one board", "local"]], _mode, func(v):
		_mode = v
		_ai_section.visible = v == "ai"
	, 180))

	body.add_child(UIKit.gap(2))
	body.add_child(UIKit.label("RULES", "Kicker"))
	var variants: Array = []
	for v in CheckersRules.variants():
		variants.append([str(v.get("name")).replace(" Draughts", ""), str(v.get("id")), str(v.get("blurb", ""))])
	body.add_child(UIKit.chips(variants, _variant, func(v):
		_variant = v
		_variant_blurb.text = CheckersRules.variant_blurb(v)
		_rebuild_order()
	, 140))
	_variant_blurb = UIKit.label(CheckersRules.variant_blurb(_variant), "Caption", true)
	body.add_child(_variant_blurb)

	_ai_section = UIKit.vbox(10)
	_ai_section.add_child(UIKit.gap(2))
	_ai_section.add_child(UIKit.label("YOUR SIDE", "Kicker"))
	_order_holder = UIKit.vbox(0)
	_ai_section.add_child(_order_holder)
	_rebuild_order()
	_ai_section.add_child(UIKit.gap(2))
	_ai_section.add_child(UIKit.label("SHADOW'S STRENGTH", "Kicker"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var group := ButtonGroup.new()
	for l in CheckersAI.levels():
		var id := str(l.get("id"))
		var b := Button.new()
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == _level
		b.custom_minimum_size = Vector2(232, 76)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var v := UIKit.vbox(2)
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 14
		v.offset_top = 10
		v.offset_right = -10
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(UIKit.label(str(l.get("name")), "Subheader"))
		var blurb := UIKit.label(str(l.get("blurb", "")), "Caption", true)
		blurb.add_theme_font_size_override("font_size", 12)
		v.add_child(blurb)
		for c in v.get_children():
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		b.mouse_entered.connect(func(): AudioManager.play("ui_hover"))
		b.toggled.connect(func(on: bool):
			if on:
				AudioManager.play("ui_click")
				_level = id
		)
		grid.add_child(b)
	_ai_section.add_child(grid)
	_ai_section.visible = _mode == "ai"
	body.add_child(_ai_section)

	body.add_child(UIKit.gap(2))
	body.add_child(UIKit.label("TIME CONTROL", "Kicker"))
	body.add_child(UIKit.chips([["No clock", "none"], ["1 + 0", "1+0"], ["3 + 2", "3+2"], ["5 + 0", "5+0"], ["10 + 0", "10+0"], ["15 + 10", "15+10"], ["30 + 0", "30+0"]], _clock, func(v): _clock = v, 84))

	body.add_child(UIKit.gap(2))
	body.add_child(UIKit.label("STARTING POSITION", "Kicker"))
	body.add_child(UIKit.chips([["Standard", "standard"], ["From FEN", "fen"]], _start, func(v):
		_start = v
		_fen_edit.visible = v == "fen"
		_fen_error.visible = false
	, 110))
	_fen_edit = LineEdit.new()
	_fen_edit.placeholder_text = "PDN FEN, e.g. W:W21,22,23,K30:B1,2,K12"
	_fen_edit.visible = false
	body.add_child(_fen_edit)
	_fen_error = UIKit.label("", "Caption", true)
	_fen_error.add_theme_color_override("font_color", ThemeFactory.DANGER)
	_fen_error.visible = false
	body.add_child(_fen_error)

	add_footer_button(UIKit.button("Cancel", close, "GhostButton"))
	add_footer_button(UIKit.button("Start game", _start_game, "PrimaryButton", "play"))


func _rebuild_order() -> void:
	for c in _order_holder.get_children():
		_order_holder.remove_child(c)
		c.queue_free()
	var first := CheckersRules.first_to_move(_variant)
	var second := CheckersTypes.opp(first)
	_order_holder.add_child(UIKit.chips([
		["%s — moves first" % MaterialLibrary.side_label(first), "first"],
		["%s — moves second" % MaterialLibrary.side_label(second), "second"],
		["Random", "random"],
	], _order, func(v): _order = v, 150))


func _start_game() -> void:
	var fen := ""
	if _start == "fen":
		fen = _fen_edit.text.strip_edges()
		var probe := CheckersEngine.new(_variant)
		if not probe.from_fen(fen):
			_fen_error.text = "That position could not be read. Use PDN FEN, e.g. W:W21,22:B1,K12."
			_fen_error.visible = true
			AudioManager.play("illegal")
			return
	SettingsStore.last_new_game = {"mode": _mode, "variant": _variant, "order": _order, "level": _level, "clock": _clock}
	SettingsStore.variant = _variant
	if _mode == "ai":
		SettingsStore.ai_level = _level
	SettingsStore.clock_preset = _clock
	SettingsStore.save_settings()
	if _mode == "ai":
		var first := _order == "first" or (_order == "random" and randi() % 2 == 0)
		GameSession.configure_ai(first, _level, _clock, _variant)
	else:
		GameSession.configure_local(_clock != "none", _clock, _variant)
	GameSession.pending_fen = fen
	SaveManager.clear_autosave()
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
