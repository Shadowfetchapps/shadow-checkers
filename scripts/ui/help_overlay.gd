class_name HelpOverlay
extends Modal

## Controls reference plus the rules of the variant being played.

const SHORTCUTS := [
	["Left click / drag", "Select a disc and move it"],
	["Click each landing", "Enter a multi-jump one hop at a time"],
	["Esc / X", "Take back the hops of an unfinished jump"],
	["Right drag", "Orbit the camera"],
	["Middle drag", "Pan"],
	["Wheel", "Zoom"],
	["Q / E", "Orbit left / right"],
	["C", "Reset camera"],
	["T", "Top-down view"],
	["F", "Flip board"],
	["H", "Hint"],
	["Ctrl+Z / Ctrl+Y", "Take back / replay"],
	["← / →", "Step through the game"],
	["F11", "Fullscreen"],
	["F1", "This help"],
]

const RULES := {
	"english": [
		"8×8 board, dark squares only. Black moves first.",
		"Men move and capture diagonally forward. Kings move one square in any direction.",
		"Capturing is compulsory, but you may choose which capture to make; a multi-jump must be finished.",
		"A man that reaches the far row is crowned and the move ends.",
		"Win by capturing every piece or leaving the opponent without a move. Draw by threefold repetition or 40 moves each without a capture or man move.",
	],
	"russian": [
		"White moves first. Men move forward and capture both forwards and backwards.",
		"Kings fly: they move and capture along a whole diagonal, landing on any empty square beyond.",
		"Capturing is compulsory; you may choose which sequence to take, but must finish it.",
		"A man that reaches the far row mid-capture is crowned at once and keeps capturing as a king.",
		"Captured discs stay on the board until the move ends and can't be jumped twice.",
	],
	"brazilian": [
		"International rules on an 8×8 board. White moves first; men capture backwards too.",
		"Kings fly along whole diagonals.",
		"You must take the sequence that captures the most pieces (kings and men count the same).",
		"A man is crowned only if its move ends on the far row.",
		"Captured discs stay on the board until the move ends and can't be jumped twice.",
	],
}


func _init() -> void:
	super("Controls and rules", 660, true, 480)
	body.add_child(UIKit.label("CONTROLS", "Kicker"))
	body.add_child(shortcut_grid())
	for v in ["english", "russian", "brazilian"]:
		body.add_child(UIKit.gap(6))
		body.add_child(UIKit.label(CheckersRules.variant_name(v).to_upper(), "Kicker"))
		for line in RULES[v]:
			var row := UIKit.hbox(10)
			row.add_child(UIKit.icon_rect("check", 14))
			var l := UIKit.label(line, "Muted", true)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			body.add_child(row)
	add_footer_button(UIKit.button("Got it", close, "PrimaryButton"))


static func shortcut_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 22)
	g.add_theme_constant_override("v_separation", 8)
	for s in SHORTCUTS:
		var key := PanelContainer.new()
		key.theme_type_variation = "Inset"
		var kl := UIKit.label(s[0], "Tabular")
		kl.add_theme_color_override("font_color", ThemeFactory.GOLD_BRIGHT)
		key.add_child(kl)
		key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var wrap := UIKit.hbox(0)
		wrap.custom_minimum_size.x = 190
		wrap.add_child(key)
		g.add_child(wrap)
		var d := UIKit.label(s[1], "Muted")
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.add_child(d)
	return g
