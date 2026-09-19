extends Node

enum Mode { LOCAL, AI }

var mode: Mode = Mode.LOCAL
var ai_side: int = CheckersTypes.WHITE
var load_path: String = ""
var pending_fen: String = ""
var white_name: String = "White"
var black_name: String = "Black"
var clock_seconds: int = 600


func reset_defaults() -> void:
	mode = Mode.LOCAL
	ai_side = CheckersTypes.WHITE
	load_path = ""
	pending_fen = ""
	white_name = "White"
	black_name = "Black"
	clock_seconds = SettingsStore.clock_seconds


func configure_local(with_clock: bool = true) -> void:
	reset_defaults()
	mode = Mode.LOCAL
	white_name = "Player 1"
	black_name = "Player 2"
	clock_seconds = SettingsStore.clock_seconds if with_clock else 0


func configure_ai(player_white: bool = true) -> void:
	reset_defaults()
	mode = Mode.AI
	# English/American: Black moves first. "Play White" means the human is White.
	if player_white:
		ai_side = CheckersTypes.BLACK
		white_name = "You"
		black_name = "Shadow"
	else:
		ai_side = CheckersTypes.WHITE
		white_name = "Shadow"
		black_name = "You"
	clock_seconds = SettingsStore.clock_seconds
