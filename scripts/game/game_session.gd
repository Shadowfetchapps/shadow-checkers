extends Node

## Hand-off between the menus and the game scene: what kind of game to start
## (mode, rules variant, sides, strength, clock). Read once by the game scene.

enum Mode { LOCAL, AI, PUZZLE, ANALYSIS }

var mode: Mode = Mode.LOCAL
var variant: String = "english"
var ai_side: int = CheckersTypes.WHITE
var ai_level: String = "club"
var load_path: String = ""
var pending_fen: String = ""
var pending_pdn: String = ""
var white_name: String = "White"
var black_name: String = "Black"
var clock_base: int = 600
var clock_increment: int = 0
var puzzle: Dictionary = {}
var puzzle_index: int = -1


func reset_defaults() -> void:
	mode = Mode.LOCAL
	variant = SettingsStore.variant
	ai_side = CheckersTypes.WHITE
	ai_level = SettingsStore.ai_level
	load_path = ""
	pending_fen = ""
	pending_pdn = ""
	white_name = "White"
	black_name = "Black"
	var tc := SettingsStore.clock_base_increment()
	clock_base = tc.x
	clock_increment = tc.y
	puzzle = {}
	puzzle_index = -1


func configure_local(with_clock: bool = true, preset: String = "", p_variant: String = "") -> void:
	reset_defaults()
	mode = Mode.LOCAL
	if p_variant != "":
		variant = p_variant
	if not with_clock:
		clock_base = 0
		clock_increment = 0
	elif preset != "":
		_set_clock(preset)


## `player_first`: the human takes the side that moves first in this variant.
func configure_ai(player_first: bool = true, level: String = "", preset: String = "", p_variant: String = "") -> void:
	reset_defaults()
	mode = Mode.AI
	if p_variant != "":
		variant = p_variant
	var first := CheckersRules.first_to_move(variant)
	ai_side = CheckersTypes.opp(first) if player_first else first
	if level != "":
		ai_level = level
	var me := SettingsStore.player_name
	white_name = "Shadow" if ai_side == CheckersTypes.WHITE else me
	black_name = "Shadow" if ai_side == CheckersTypes.BLACK else me
	if preset != "":
		_set_clock(preset)


func configure_analysis(fen: String = "", pdn: String = "", p_variant: String = "") -> void:
	reset_defaults()
	mode = Mode.ANALYSIS
	if p_variant != "":
		variant = p_variant
	clock_base = 0
	clock_increment = 0
	pending_fen = fen
	pending_pdn = pdn


func configure_puzzle(p: Dictionary, index: int) -> void:
	reset_defaults()
	mode = Mode.PUZZLE
	puzzle = p
	puzzle_index = index
	variant = str(p.get("variant", "english"))
	clock_base = 0
	clock_increment = 0
	pending_fen = str(p.get("fen", ""))
	var solver := CheckersTypes.WHITE if str(p.get("side", "w")) == "w" else CheckersTypes.BLACK
	ai_side = CheckersTypes.opp(solver)
	white_name = SettingsStore.player_name if solver == CheckersTypes.WHITE else "Defender"
	black_name = SettingsStore.player_name if solver == CheckersTypes.BLACK else "Defender"


func _set_clock(preset: String) -> void:
	var tc := SettingsStore.clock_base_increment(preset)
	clock_base = tc.x
	clock_increment = tc.y


func is_ai() -> bool:
	return mode == Mode.AI


func human_sides() -> Array[int]:
	match mode:
		Mode.AI, Mode.PUZZLE:
			return [CheckersTypes.opp(ai_side)]
		_:
			return [CheckersTypes.WHITE, CheckersTypes.BLACK]


func mode_label() -> String:
	var v := CheckersRules.variant_name(variant).replace(" Draughts", "")
	match mode:
		Mode.AI:
			return "%s · vs Shadow · %s" % [v, _level_name(ai_level)]
		Mode.PUZZLE:
			return "%s · Puzzle" % v
		Mode.ANALYSIS:
			return "%s · Analysis" % v
		_:
			return "%s · Two players" % v


func time_control_label() -> String:
	if clock_base <= 0:
		return "No clock"
	return "%d+%d" % [int(clock_base / 60.0), clock_increment]


func _level_name(id: String) -> String:
	for l in CheckersAI.levels():
		if str(l.get("id", "")) == id:
			return str(l.get("name", id))
	return id.capitalize()
