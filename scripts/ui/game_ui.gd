extends CanvasLayer

var controller: GameController
var _status: Label
var _clock_w: Label
var _clock_b: Label
var _history: RichTextLabel
var _cap_w: Label
var _cap_b: Label
var _pause: PanelContainer
var _end: PanelContainer
var _fen_box: LineEdit
var _thinking: Label


func _ready() -> void:
	layer = 10
	controller = get_parent().get_node("World") as GameController
	_build()
	controller.state_changed.connect(_refresh)
	controller.game_ended.connect(_show_end)
	_refresh()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ThemeFactory.make()
	add_child(root)
	root.add_child(_top_bar())
	root.add_child(_side_panel())
	root.add_child(_bottom_bar())
	_thinking = Label.new()
	_thinking.text = "Shadow is thinking…"
	_thinking.visible = false
	_thinking.add_theme_color_override("font_color", ThemeFactory.accent())
	_thinking.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_thinking.offset_top = 72
	_thinking.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_thinking)
	_pause = _make_pause()
	root.add_child(_pause)
	_end = _make_end()
	root.add_child(_end)


func _top_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_top = 12
	bar.offset_bottom = 64
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var title := Label.new()
	title.text = "SHADOW CHECKERS"
	var df: FontFile = load("res://assets/fonts/InterDisplay-SemiBold.ttf")
	if df:
		title.add_theme_font_override("font", df)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", ThemeFactory.accent())
	row.add_child(title)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_status)
	row.add_child(_btn("Undo", controller.undo))
	row.add_child(_btn("Redo", controller.redo))
	row.add_child(_btn("Flip", controller.flip_board))
	row.add_child(_btn("Pause", _toggle_pause))
	return bar


func _side_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -320
	panel.offset_right = -16
	panel.offset_top = 80
	panel.offset_bottom = -90
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_heading("Clocks"))
	var clocks := HBoxContainer.new()
	_clock_w = _clock_label("W  ∞")
	_clock_b = _clock_label("B  ∞")
	clocks.add_child(_clock_w)
	clocks.add_child(_clock_b)
	v.add_child(clocks)
	v.add_child(_heading("Captured"))
	_cap_w = Label.new()
	_cap_b = Label.new()
	_cap_w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cap_b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_cap_w)
	v.add_child(_cap_b)
	v.add_child(_heading("Move history"))
	_history = RichTextLabel.new()
	_history.bbcode_enabled = true
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.scroll_following = true
	_history.fit_content = false
	v.add_child(_history)
	v.add_child(_heading("Position"))
	_fen_box = LineEdit.new()
	_fen_box.editable = true
	v.add_child(_fen_box)
	var fen_row := HBoxContainer.new()
	fen_row.add_child(_btn("Copy", func(): DisplayServer.clipboard_set(controller.export_fen())))
	fen_row.add_child(_btn("Load", _load_fen))
	v.add_child(fen_row)
	return panel


func _bottom_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 16
	bar.offset_right = -336
	bar.offset_top = -78
	bar.offset_bottom = -16
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	row.add_child(_btn("Save", func(): _toast_save(controller.save_now())))
	row.add_child(_btn("Restart", controller.restart))
	row.add_child(_btn("Resign", controller.resign))
	row.add_child(_btn("Menu", _to_menu))
	var hint := Label.new()
	hint.text = "LMB select/move   RMB orbit   Wheel zoom   MMB pan   H reset   F flip   Z undo"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", ThemeFactory.muted())
	row.add_child(hint)
	return bar


func _make_pause() -> PanelContainer:
	var p := _modal("Paused")
	var v: VBoxContainer = p.get_node("V")
	v.add_child(_btn("Resume", _toggle_pause))
	v.add_child(_btn("Settings", _open_settings))
	v.add_child(_btn("Resign", func(): _toggle_pause(); controller.resign()))
	v.add_child(_btn("Main menu", _to_menu))
	p.visible = false
	return p


func _make_end() -> PanelContainer:
	var p := _modal("Game over")
	var v: VBoxContainer = p.get_node("V")
	var msg := Label.new()
	msg.name = "Msg"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(msg)
	v.add_child(_btn("New game", func(): p.visible = false; controller.restart()))
	v.add_child(_btn("Save", func(): controller.save_now()))
	v.add_child(_btn("Main menu", _to_menu))
	p.visible = false
	return p


func _modal(title: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(360, 80)
	p.offset_left = -200
	p.offset_right = 200
	p.offset_top = -140
	p.offset_bottom = 140
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 12)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var df: FontFile = load("res://assets/fonts/InterDisplay-SemiBold.ttf")
	if df:
		t.add_theme_font_override("font", df)
	t.add_theme_font_size_override("font_size", 22)
	v.add_child(t)
	p.add_child(v)
	return p


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		AudioManager.play("ui")
		cb.call()
	)
	return b


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", ThemeFactory.accent())
	return l


func _clock_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	return l


func _refresh() -> void:
	if controller == null:
		return
	var e := controller.engine
	_status.text = e.result_text()
	_clock_w.text = "White  %s" % _fmt(controller.white_clock)
	_clock_b.text = "Black  %s" % _fmt(controller.black_clock)
	if not controller.clock_enabled:
		_clock_w.text = "White  ∞"
		_clock_b.text = "Black  ∞"
	_history.text = _history_bb(e)
	_cap_w.text = "White took  " + _captured(e, CheckersTypes.BLACK)
	_cap_b.text = "Black took  " + _captured(e, CheckersTypes.WHITE)
	_fen_box.text = e.to_fen()
	_thinking.visible = controller._ai_busy
	controller.paused = _pause.visible


func _history_bb(e: CheckersEngine) -> String:
	var groups: Array = e.turn_groups()
	if groups.is_empty():
		return "[color=#7f8c96]No moves yet[/color]"
	var parts: PackedStringArray = PackedStringArray()
	for i in groups.size():
		parts.append("[color=#6ad4e8]%d.[/color]" % (i + 1))
		var hops: Array = groups[i]
		if hops.size() == 1 and not hops[0].is_capture():
			parts.append("%s-%s" % [CheckersTypes.algebraic(hops[0].from_sq), CheckersTypes.algebraic(hops[0].to_sq)])
		else:
			var bits: PackedStringArray = PackedStringArray()
			bits.append(CheckersTypes.algebraic(hops[0].from_sq))
			for h in hops:
				bits.append(CheckersTypes.algebraic(h.to_sq))
			parts.append("x".join(bits))
	return " ".join(parts)


func _captured(e: CheckersEngine, color: int) -> String:
	var men := 0
	var kings := 0
	for sq in 64:
		var p := e.piece_at(sq)
		if p != 0 and CheckersTypes.pcolor(p) == color:
			if CheckersTypes.ptype(p) == CheckersTypes.KING:
				kings += 1
			else:
				men += 1
	var missing := 12 - men - kings
	if missing <= 0:
		return "—"
	var s := ""
	for i in missing:
		s += "●"
	return "%s  (%d)" % [s, missing]


func _fmt(t: float) -> String:
	var s := int(ceil(t))
	return "%d:%02d" % [int(s / 60.0), s % 60]


func _toggle_pause() -> void:
	_pause.visible = not _pause.visible
	controller.paused = _pause.visible
	_end.visible = false


func _show_end(text: String) -> void:
	_end.visible = true
	var msg := _end.get_node("V/Msg") as Label
	if msg:
		msg.text = text


func _load_fen() -> void:
	if controller.engine.from_fen(_fen_box.text.strip_edges()):
		controller.last_from = -1
		controller.last_to = -1
		controller.rebuild_pieces()
		controller._deselect()
		controller.state_changed.emit()


func _toast_save(path: String) -> void:
	_status.text = "Saved  " + path.get_file() if path != "" else "Save failed"


func _open_settings() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/settings_menu.tscn")


func _to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		_toggle_pause()
