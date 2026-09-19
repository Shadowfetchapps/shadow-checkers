class_name CheckersTypes
extends RefCounted

const WHITE := 0
const BLACK := 1

const NONE := 0
const MAN := 1
const KING := 2

const FLAG_CAPTURE := 1
const FLAG_PROMO := 2
const FLAG_CONTINUE := 4

const FILE_NAMES: Array[String] = ["a", "b", "c", "d", "e", "f", "g", "h"]
const PIECE_LETTERS: Array[String] = ["", "m", "k"]

const DIAG_DIRS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]

## English/American: Black moves first. Dark squares only.
const START_FEN := "1b1b1b1b/b1b1b1b1/1b1b1b1b/8/8/w1w1w1w1/1w1w1w1w/w1w1w1w1 b - 0 1"


static func opp(side: int) -> int:
	return 1 - side


static func pack(type: int, color: int) -> int:
	if type == NONE:
		return 0
	return type | (color << 4)


static func ptype(p: int) -> int:
	return p & 0x0F


static func pcolor(p: int) -> int:
	return p >> 4


static func sq(file: int, rank: int) -> int:
	return (rank << 3) | file


static func file_of(s: int) -> int:
	return s & 7


static func rank_of(s: int) -> int:
	return s >> 3


static func in_board(file: int, rank: int) -> bool:
	return file >= 0 and file < 8 and rank >= 0 and rank < 8


static func is_dark(s: int) -> bool:
	return ((file_of(s) + rank_of(s)) & 1) == 0


static func is_dark_fr(file: int, rank: int) -> bool:
	return ((file + rank) & 1) == 0


static func algebraic(s: int) -> String:
	if s < 0 or s > 63:
		return "-"
	return "%s%d" % [FILE_NAMES[file_of(s)], rank_of(s) + 1]


static func parse_square(text: String) -> int:
	if text.length() < 2:
		return -1
	var f := text.unicode_at(0) - 97
	var r := text.unicode_at(1) - 49
	if not in_board(f, r):
		return -1
	return sq(f, r)


static func piece_char(p: int) -> String:
	var t := ptype(p)
	if t == NONE:
		return "."
	var ch := "w" if t == MAN else "W"
	if pcolor(p) == BLACK:
		ch = "b" if t == MAN else "B"
	return ch


static func side_name(side: int) -> String:
	return "White" if side == WHITE else "Black"


static func piece_name(type: int) -> String:
	match type:
		MAN:
			return "Man"
		KING:
			return "King"
		_:
			return ""


static func promotion_rank(side: int) -> int:
	return 7 if side == WHITE else 0


static func man_forward(side: int) -> int:
	return 1 if side == WHITE else -1
