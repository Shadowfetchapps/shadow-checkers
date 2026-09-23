class_name CheckersRules
extends RefCounted

## Variant table and rule switches.
##
## Every variant uses the same 8x8 board and orientation: a1 is dark, White men
## start on ranks 1-3, Black men on ranks 6-8.
##
## Draw counters (CheckersEngine.halfmove counts plies since the last capture or
## man move for every variant; a man move is irreversible, like a pawn move):
##   english   - 80 plies (40 moves each) with no capture and no man move.
##               (v1 reset only on captures; resetting on man moves too matches the
##               ACF/EDA "no advance and no capture" wording and cannot draw a game
##               that is still making progress.)
##   russian   - 30 plies (15 moves each) with only king moves and no captures
##               (simplification of the "both sides have kings" 15-move rule).
##   brazilian - 50 plies (25 moves each) with only king moves and no captures.
##   all       - threefold repetition of the same position with the same side to move.

const VARIANT_IDS: Array[String] = ["english", "russian", "brazilian"]

const _TABLE := {
	"english": {
		"id": "english",
		"name": "English Draughts",
		"blurb": "Checkers as played in the UK and US. Black moves first, men move and capture forward only, kings step one square. Capturing is compulsory, but you may choose any capture sequence.",
		"first": 1,
		"flying": false,
		"men_back": false,
		"majority": false,
		"crown_mid": false,
		"draw_plies": 80,
		"game_type": "21",
		"numeric": true,
	},
	"russian": {
		"id": "russian",
		"name": "Russian Draughts",
		"blurb": "Shashki. White moves first, men capture backwards too, kings fly along diagonals. A man crowned mid-capture keeps jumping as a king. Any capture sequence may be chosen.",
		"first": 0,
		"flying": true,
		"men_back": true,
		"majority": false,
		"crown_mid": true,
		"draw_plies": 30,
		"game_type": "25",
		"numeric": false,
	},
	"brazilian": {
		"id": "brazilian",
		"name": "Brazilian Draughts",
		"blurb": "International rules on an 8x8 board. White moves first, flying kings, men capture backwards, and you must take the maximum number of pieces.",
		"first": 0,
		"flying": true,
		"men_back": true,
		"majority": true,
		"crown_mid": false,
		"draw_plies": 50,
		"game_type": "26",
		"numeric": false,
	},
}

const ENGLISH_START := "B:W21,22,23,24,25,26,27,28,29,30,31,32:B1,2,3,4,5,6,7,8,9,10,11,12"
const WHITE_FIRST_START := "W:W21,22,23,24,25,26,27,28,29,30,31,32:B1,2,3,4,5,6,7,8,9,10,11,12"


static func variants() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in VARIANT_IDS:
		var t: Dictionary = _TABLE[id]
		out.append({
			"id": id,
			"name": t["name"],
			"blurb": t["blurb"],
			"first": int(t["first"]),
		})
	return out


static func is_valid(variant: String) -> bool:
	return _TABLE.has(variant)


## Unknown ids fall back to "english".
static func normalize(variant: String) -> String:
	var v := variant.strip_edges().to_lower()
	return v if _TABLE.has(v) else "english"


static func _row(variant: String) -> Dictionary:
	return _TABLE.get(variant, _TABLE["english"])


static func first_to_move(variant: String) -> int:
	return int(_row(variant)["first"])


static func second_to_move(variant: String) -> int:
	return 1 - first_to_move(variant)


static func variant_name(variant: String) -> String:
	return str(_row(variant)["name"])


static func variant_blurb(variant: String) -> String:
	return str(_row(variant)["blurb"])


static func flying_kings(variant: String) -> bool:
	return bool(_row(variant)["flying"])


static func men_capture_backward(variant: String) -> bool:
	return bool(_row(variant)["men_back"])


static func majority_capture(variant: String) -> bool:
	return bool(_row(variant)["majority"])


static func crown_mid_capture(variant: String) -> bool:
	return bool(_row(variant)["crown_mid"])


## Plies without a capture or man move after which the game is drawn.
static func draw_plies(variant: String) -> int:
	return int(_row(variant)["draw_plies"])


static func game_type(variant: String) -> String:
	return str(_row(variant)["game_type"])


static func numeric_notation(variant: String) -> bool:
	return bool(_row(variant)["numeric"])


## PDN GameType tag value ("21", "25,W,8,8,A0,0" ...) -> variant id, "" if unsupported.
static func variant_from_game_type(gt: String) -> String:
	var head := gt.strip_edges().split(",")[0].strip_edges()
	if head.is_empty():
		return "english"
	for id in VARIANT_IDS:
		if str(_TABLE[id]["game_type"]) == head:
			return id
	return ""


static func start_fen(variant: String) -> String:
	return ENGLISH_START if first_to_move(variant) == CheckersTypes.BLACK else WHITE_FIRST_START


static func move_rule_text(variant: String) -> String:
	match normalize(variant):
		"russian":
			return "15 moves each with only kings moving"
		"brazilian":
			return "25 moves each with only kings moving"
		_:
			return "40 moves each without a capture or man move"
