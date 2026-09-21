class_name ThemeFactory
extends RefCounted


static func make() -> Theme:
	var theme := Theme.new()
	var regular: FontFile = load("res://assets/fonts/Inter-Regular.ttf")
	var medium: FontFile = load("res://assets/fonts/Inter-Medium.ttf")
	var display: FontFile = load("res://assets/fonts/InterDisplay-SemiBold.ttf")
	if regular:
		theme.default_font = regular
	theme.default_font_size = 16
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.11, 0.15, 0.20, 0.94)
	btn.border_color = Color(0.32, 0.58, 0.66, 0.58)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(9)
	btn.content_margin_left = 18
	btn.content_margin_right = 18
	btn.content_margin_top = 10
	btn.content_margin_bottom = 10
	var btn_h := btn.duplicate()
	btn_h.bg_color = Color(0.16, 0.24, 0.30, 0.97)
	btn_h.border_color = Color(0.50, 0.90, 0.98, 0.95)
	var btn_p := btn.duplicate()
	btn_p.bg_color = Color(0.10, 0.30, 0.36, 0.97)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.055, 0.07, 0.10, 0.93)
	panel.border_color = Color(0.24, 0.36, 0.42, 0.55)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(14)
	panel.content_margin_left = 16
	panel.content_margin_right = 16
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	var empty := StyleBoxEmpty.new()
	theme.set_stylebox("normal", "Button", btn)
	theme.set_stylebox("hover", "Button", btn_h)
	theme.set_stylebox("pressed", "Button", btn_p)
	theme.set_stylebox("focus", "Button", btn_h)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_color("font_color", "Button", Color(0.88, 0.93, 0.96))
	theme.set_color("font_hover_color", "Button", Color(0.96, 0.99, 1.0))
	theme.set_color("font_color", "Label", Color(0.84, 0.90, 0.94))
	if medium:
		theme.set_font("font", "Button", medium)
	if display:
		theme.set_font("font", "Header", display)
	theme.set_stylebox("normal", "LineEdit", _field())
	theme.set_stylebox("focus", "LineEdit", _field(true))
	theme.set_stylebox("normal", "ItemList", _field())
	theme.set_stylebox("grabber_area", "HSlider", empty)
	return theme


static func _field(focus := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.09, 0.12, 0.96)
	s.border_color = Color(0.42, 0.82, 0.92, 0.85) if focus else Color(0.26, 0.36, 0.42, 0.62)
	s.set_border_width_all(1)
	s.set_corner_radius_all(7)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func accent() -> Color:
	return Color(0.46, 0.88, 0.96)


static func gold() -> Color:
	return Color(0.95, 0.78, 0.38)


static func muted() -> Color:
	return Color(0.64, 0.72, 0.78)
