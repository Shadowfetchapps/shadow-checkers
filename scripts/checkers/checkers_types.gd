class_name CheckersTypes
extends RefCounted

## Shared constants, square helpers and precomputed lookup tables.
##
## Board: 64-square index `sq = rank * 8 + file`, a1 = 0, h8 = 63. Only dark
## squares ((file + rank) even, so a1 is dark) are playable. White men start on
## ranks 1-3, Black men on ranks 6-8, for every variant.
##
## Piece encoding: `pack(type, color) = type | (color << 4)`, so
## white man = 1, white king = 2, black man = 17, black king = 18.
##
## The static tables below are built by `_static_init()` when the class is first
## loaded (on the main thread: every script that uses them references this class
## at parse time). `CheckersAI.warmup()` calls build_tables() as well.

const WHITE := 0
const BLACK := 1

const NONE := 0
const MAN := 1
const KING := 2

const W_MAN := 1
const W_KING := 2
const B_MAN := 17
const B_KING := 18

const FILE_NAMES: Array[String] = ["a", "b", "c", "d", "e", "f", "g", "h"]
const PIECE_LETTERS: Array[String] = ["", "m", "k"]

## Direction order used by every table: 0 = NE (+1,+1), 1 = NW (-1,+1),
## 2 = SE (+1,-1), 3 = SW (-1,-1). White men move along 0/1, Black men 2/3.
const DIAG_DIRS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]

## Legacy v1 start FEN (English, Black to move). Still accepted by from_fen().
const START_FEN := "1b1b1b1b/b1b1b1b1/1b1b1b1b/8/8/w1w1w1w1/1w1w1w1w/w1w1w1w1 b - 0 1"

## Compact move key layout (engine search interface and AI):
## bits 0-31 capture mask over dark-square indices (sq >> 1), bits 32-37 from,
## bits 38-43 to, bit 44 promotes, bits 45-49 capture count.
const KEY_MASK32 := 0xFFFFFFFF
const KEY_FROM_SHIFT := 32
const KEY_TO_SHIFT := 38
const KEY_PROMO := 1 << 44
const KEY_NCAP_SHIFT := 45

## Neighbour table: NB[sq * 4 + dir] = adjacent square or -1.
static var NB: PackedInt32Array
## The 32 dark squares in ascending 64-index order (a1, c1, e1, g1, b2, ...).
static var DARK: PackedInt32Array
## Dark index (sq >> 1) back to the 64-index square.
static var IDX2SQ: PackedInt32Array
## PDN numbering (1..32) per 64-square, -1 for light squares; and the inverse.
static var SQ2NUM: PackedInt32Array
static var NUM2SQ: PackedInt32Array
## (1 << k) % 37 is distinct for k in 0..31, so MOD37[(1 << k) % 37] = k.
static var MOD37: PackedInt32Array
## Zobrist keys: ZOBRIST[sq * 32 + piece] for piece values 1, 2, 17, 18.
static var ZOBRIST: PackedInt64Array
static var ZOBRIST_SIDE: int = 0
static var _ready := false


static func _static_init() -> void:
	build_tables()


static func build_tables() -> void:
	if _ready:
		return
	var nb := PackedInt32Array()
	nb.resize(256)
	for s in 64:
		var f := s & 7
		var r := s >> 3
		for d in 4:
			var v: Vector2i = DIAG_DIRS[d]
			var nf := f + v.x
			var nr := r + v.y
			nb[s * 4 + d] = ((nr << 3) | nf) if (nf >= 0 and nf < 8 and nr >= 0 and nr < 8) else -1
	var dark := PackedInt32Array()
	var idx2 := PackedInt32Array()
	idx2.resize(32)
	for s in 64:
		if (((s & 7) + (s >> 3)) & 1) == 0:
			dark.append(s)
			idx2[s >> 1] = s
	var s2n := PackedInt32Array()
	s2n.resize(64)
	s2n.fill(-1)
	var n2s := PackedInt32Array()
	n2s.resize(33)
	n2s.fill(-1)
	var num := 1
	for row in 8:
		var rank := 7 - row
		for f in 8:
			if ((f + rank) & 1) == 0:
				var s := (rank << 3) | f
				s2n[s] = num
				n2s[num] = s
				num += 1
	var m37 := PackedInt32Array()
	m37.resize(37)
	m37.fill(-1)
	for k in 32:
		m37[(1 << k) % 37] = k
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5AD0C4EC
	var z := PackedInt64Array()
	z.resize(64 * 32)
	for i in z.size():
		z[i] = (int(rng.randi()) << 32) ^ int(rng.randi()) ^ (int(rng.randi()) << 13)
	NB = nb
	DARK = dark
	IDX2SQ = idx2
	SQ2NUM = s2n
	NUM2SQ = n2s
	MOD37 = m37
	ZOBRIST = z
	ZOBRIST_SIDE = (int(rng.randi()) << 32) ^ int(rng.randi())
	_ready = true


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


## Standard PDN / English numbering: 1 = b8, 2 = d8, 3 = f8, 4 = h8, 5 = a7 ...
## 29 = a1, 30 = c1, 31 = e1, 32 = g1. Returns -1 for light or invalid squares.
static func square_number(s: int) -> int:
	if s < 0 or s > 63:
		return -1
	return SQ2NUM[s]


## Inverse of square_number(); -1 when n is outside 1..32.
static func square_from_number(n: int) -> int:
	if n < 1 or n > 32:
		return -1
	return NUM2SQ[n]


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


## Decode helpers for compact move keys.
static func key_from(k: int) -> int:
	return (k >> KEY_FROM_SHIFT) & 63


static func key_to(k: int) -> int:
	return (k >> KEY_TO_SHIFT) & 63


static func key_ncap(k: int) -> int:
	return (k >> KEY_NCAP_SHIFT) & 31


static func key_promotes(k: int) -> bool:
	return (k & KEY_PROMO) != 0
