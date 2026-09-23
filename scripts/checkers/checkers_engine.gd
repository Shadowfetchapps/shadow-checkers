class_name CheckersEngine
extends RefCounted

## Rules engine for English, Russian and Brazilian draughts.
##
## A CheckersMove is one complete turn (a quiet move or a whole capture
## sequence). Capture sequences are generated with the Turkish-strike rule for
## every variant: captured pieces stay on the board (blocking) until the turn
## ends and may not be jumped twice. With short kings (English) this is
## equivalent to removing pieces as they are jumped.
##
## halfmove = plies since the last capture or man move (all variants); the draw
## threshold is CheckersRules.draw_plies(variant): 80 english, 30 russian,
## 50 brazilian. fullmove starts at 1 and increments after the variant's second
## mover completes a turn (after White in English, after Black otherwise).
##
## Two interfaces share one generator:
##   * UI/game:   generate_legal_moves(), apply_move(), undo(), ... (objects)
##   * search:    generate_keys(), make_key(), unmake_key() (compact ints, see
##                CheckersTypes.KEY_*); used by perft and CheckersAI.

enum Result {
	NONE,
	NO_MOVES,
	NO_PIECES,
	RESIGNATION,
	TIMEOUT,
	DRAW_AGREED,
	DRAW_MOVE_RULE,
	DRAW_REPETITION,
}

const REPETITION_DRAW := 3

var variant: String = "english"
var squares: PackedInt32Array = PackedInt32Array()
var side_to_move: int = CheckersTypes.BLACK
var halfmove: int = 0
var fullmove: int = 1
var history: Array[CheckersMove] = []
var redo_stack: Array[CheckersMove] = []
var result: Result = Result.NONE
var result_side: int = -1
var start_fen: String = ""
var resigned_side: int = -1
var timed_out_side: int = -1
## Side to move and move number of the start position (for numbering).
var start_side: int = CheckersTypes.BLACK
var start_fullmove: int = 1

# Rule switches cached from CheckersRules (hot path).
var _flying := false
var _men_back := false
var _majority := false
var _crown_mid := false
var draw_plies := 80
var _first := CheckersTypes.BLACK
var _numeric := true

# Search state: incremental Zobrist key, per-ply key / halfmove stacks and a
# stack of captured piece values for unmake.
var _key: int = 0
var _ply: int = 0
var pos_keys: PackedInt64Array = PackedInt64Array()
var _hstack: PackedInt32Array = PackedInt32Array()
var _ustack: PackedInt32Array = PackedInt32Array()
var _usp: int = 0

# Generator scratch.
var _path: PackedInt32Array = PackedInt32Array()
var _caps: PackedInt32Array = PackedInt32Array()
var _g_color: int = 0
var _g_type: int = 0
var _g_promo_at: int = -1
var _g_max: int = 0
var _g_objects := false
var _g_keys: PackedInt64Array
var _g_n: int = 0
var _g_list: Array[CheckersMove] = []

# Legal move cache for the current position (objects).
var _cache: Array[CheckersMove] = []
var _cache_ok := false


func _init(p_variant: String = "english") -> void:
	CheckersTypes.build_tables()
	squares.resize(64)
	pos_keys.resize(256)
	_hstack.resize(256)
	_ustack.resize(256)
	_path.resize(40)
	_caps.resize(40)
	set_variant(p_variant)


# ---------------------------------------------------------------- setup ----

func set_variant(v: String) -> void:
	variant = CheckersRules.normalize(v)
	_flying = CheckersRules.flying_kings(variant)
	_men_back = CheckersRules.men_capture_backward(variant)
	_majority = CheckersRules.majority_capture(variant)
	_crown_mid = CheckersRules.crown_mid_capture(variant)
	draw_plies = CheckersRules.draw_plies(variant)
	_first = CheckersRules.first_to_move(variant)
	_numeric = CheckersRules.numeric_notation(variant)
	reset()


func reset() -> void:
	from_fen(CheckersRules.start_fen(variant))


## Empty board, variant's first mover to move. Use set_piece() then
## set_side_to_move() / load_position() to build test or editor positions.
func clear() -> void:
	var sqs := PackedInt32Array()
	sqs.resize(64)
	load_position(sqs, _first)


func set_piece(s: int, p: int) -> void:
	if s < 0 or s > 63:
		return
	var sqs := squares.duplicate()
	sqs[s] = p if CheckersTypes.is_dark(s) else 0
	load_position(sqs, side_to_move, halfmove, fullmove)


func set_side_to_move(side: int) -> void:
	load_position(squares.duplicate(), side, halfmove, fullmove)


## Replace the position; clears history/redo and makes it the new start.
func load_position(sqs: PackedInt32Array, side: int, p_halfmove: int = 0, p_fullmove: int = 1) -> void:
	var b := PackedInt32Array()
	b.resize(64)
	for s in 64:
		if s < sqs.size() and CheckersTypes.is_dark(s):
			var p := sqs[s]
			if p == CheckersTypes.W_MAN or p == CheckersTypes.W_KING or p == CheckersTypes.B_MAN or p == CheckersTypes.B_KING:
				b[s] = p
	squares = b
	side_to_move = side & 1
	halfmove = maxi(p_halfmove, 0)
	fullmove = maxi(p_fullmove, 1)
	history.clear()
	redo_stack.clear()
	result = Result.NONE
	result_side = -1
	resigned_side = -1
	timed_out_side = -1
	start_side = side_to_move
	start_fullmove = fullmove
	_ply = 0
	_usp = 0
	_key = _compute_key()
	pos_keys[0] = _key
	_hstack[0] = halfmove
	_cache_ok = false
	start_fen = _fen_with_counters()
	_refresh_result()


func clone() -> CheckersEngine:
	var e := CheckersEngine.new(variant)
	e._copy_from(self)
	return e


func _copy_from(o: CheckersEngine) -> void:
	variant = o.variant
	_flying = o._flying
	_men_back = o._men_back
	_majority = o._majority
	_crown_mid = o._crown_mid
	draw_plies = o.draw_plies
	_first = o._first
	_numeric = o._numeric
	squares = o.squares.duplicate()
	side_to_move = o.side_to_move
	halfmove = o.halfmove
	fullmove = o.fullmove
	result = o.result
	result_side = o.result_side
	resigned_side = o.resigned_side
	timed_out_side = o.timed_out_side
	start_fen = o.start_fen
	start_side = o.start_side
	start_fullmove = o.start_fullmove
	_key = o._key
	_ply = o._ply
	pos_keys = o.pos_keys.duplicate()
	_hstack = o._hstack.duplicate()
	_ustack = o._ustack.duplicate()
	_usp = o._usp
	history.clear()
	for m in o.history:
		history.append(m.duplicate_move())
	redo_stack.clear()
	for m in o.redo_stack:
		redo_stack.append(m.duplicate_move())
	_cache_ok = false


# -------------------------------------------------------------- queries ----

func piece_at(s: int) -> int:
	if s < 0 or s > 63:
		return 0
	return squares[s]


func piece_count(side: int) -> int:
	var n := 0
	for s in CheckersTypes.DARK:
		var p := squares[s]
		if p != 0 and (p >> 4) == side:
			n += 1
	return n


func king_count(side: int) -> int:
	var n := 0
	var k := CheckersTypes.pack(CheckersTypes.KING, side)
	for s in CheckersTypes.DARK:
		if squares[s] == k:
			n += 1
	return n


func generate_legal_moves() -> Array[CheckersMove]:
	if not _cache_ok:
		_cache = _gen_objects()
		_cache_ok = true
	var out: Array[CheckersMove] = []
	out.assign(_cache)
	return out


func legal_from(s: int) -> Array[CheckersMove]:
	var out: Array[CheckersMove] = []
	for m in generate_legal_moves():
		if m.path[0] == s:
			out.append(m)
	return out


func movable_squares() -> PackedInt32Array:
	var out := PackedInt32Array()
	for m in generate_legal_moves():
		if not out.has(m.path[0]):
			out.append(m.path[0])
	return out


func must_capture() -> bool:
	var ms := generate_legal_moves()
	return not ms.is_empty() and ms[0].is_capture()


## Legal moves whose path starts with prefix (prefix[0] = origin). An empty
## prefix returns every legal move.
func candidates_for_prefix(prefix: PackedInt32Array) -> Array[CheckersMove]:
	var out: Array[CheckersMove] = []
	for m in generate_legal_moves():
		if m.starts_with(prefix):
			out.append(m)
	return out


## Distinct squares that may follow prefix among the candidates. Empty when the
## prefix is itself a complete move (or matches nothing).
func next_landings(prefix: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var k := prefix.size()
	for m in candidates_for_prefix(prefix):
		if m.path.size() > k and not out.has(m.path[k]):
			out.append(m.path[k])
	return out


func find_path(p: PackedInt32Array) -> CheckersMove:
	for m in generate_legal_moves():
		if m.same_path(p):
			return m
	return null


## Accepts "c3e5g7", "c3-e5", "c3xe5xg7", "c3:e5:g7", "11-15", "22x15x6" and
## abbreviated captures ("22x6") when they identify one move (or several moves
## with the same captured set).
func find_uci(uci: String) -> CheckersMove:
	var p := parse_move_squares(uci)
	if p.size() < 2:
		return null
	var exact := find_path(p)
	if exact != null:
		return exact
	var cands: Array[CheckersMove] = []
	for m in generate_legal_moves():
		if m.path[0] != p[0] or m.to_sq() != p[p.size() - 1]:
			continue
		var j := 1
		for i in range(1, m.path.size() - 1):
			if j < p.size() - 1 and m.path[i] == p[j]:
				j += 1
		if j == p.size() - 1:
			cands.append(m)
	if cands.is_empty():
		return null
	var mask0 := cands[0]._key & CheckersTypes.KEY_MASK32
	for c in cands:
		if (c._key & CheckersTypes.KEY_MASK32) != mask0:
			return null
	return cands[0]


## Parse a move string into squares (64-index). Algebraic when it contains
## file letters, otherwise PDN numbers. Returns an empty array on error.
static func parse_move_squares(text: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var t := text.strip_edges().to_lower()
	if t.is_empty():
		return out
	var has_alpha := false
	for i in t.length():
		var c := t.unicode_at(i)
		if c >= 97 and c <= 104:
			has_alpha = true
			break
	if has_alpha:
		var i := 0
		while i < t.length():
			var c := t.unicode_at(i)
			if c >= 97 and c <= 104:
				if i + 1 >= t.length():
					return PackedInt32Array()
				var s := CheckersTypes.parse_square(t.substr(i, 2))
				if s < 0:
					return PackedInt32Array()
				out.append(s)
				i += 2
			elif c == 45 or c == 120 or c == 58 or c == 32:
				i += 1
			elif c == 33 or c == 63 or c == 43 or c == 35 or c == 42:
				i += 1
			else:
				return PackedInt32Array()
		return out
	var num := ""
	for i in t.length() + 1:
		var c := t.unicode_at(i) if i < t.length() else 45
		if c >= 48 and c <= 57:
			num += char(c)
			continue
		if c != 45 and c != 120 and c != 58 and c != 32 and c != 33 and c != 63 and c != 42:
			return PackedInt32Array()
		if not num.is_empty():
			var s := CheckersTypes.square_from_number(int(num))
			if s < 0:
				return PackedInt32Array()
			out.append(s)
			num = ""
	return out


# ------------------------------------------------------------ game flow ----

func apply_move(m: CheckersMove, clear_redo: bool = true) -> CheckersMove:
	if m == null or result != Result.NONE:
		return null
	var legal := find_path(m.path)
	if legal == null:
		return null
	var am := legal.duplicate_move()
	am.notation = notation_for(am)
	am.prev_halfmove = halfmove
	make_key(am._key)
	history.append(am)
	if clear_redo:
		redo_stack.clear()
	_refresh_result()
	return am


func play_path(p: PackedInt32Array) -> CheckersMove:
	var m := find_path(p)
	if m == null:
		return null
	return apply_move(m)


## Convenience for tests/tools: play "c3d4" / "11-15" style text.
func play_uci(text: String) -> CheckersMove:
	var m := find_uci(text)
	if m == null:
		return null
	return apply_move(m)


func undo() -> CheckersMove:
	if history.is_empty():
		return null
	var m: CheckersMove = history.pop_back()
	unmake_key(m._key)
	redo_stack.append(m)
	result = Result.NONE
	result_side = -1
	resigned_side = -1
	timed_out_side = -1
	return m


func redo() -> CheckersMove:
	if redo_stack.is_empty() or result != Result.NONE:
		return null
	var m: CheckersMove = redo_stack.pop_back()
	var r := apply_move(m, false)
	if r == null:
		redo_stack.clear()
	return r


func can_undo() -> bool:
	return not history.is_empty() and result != Result.RESIGNATION and result != Result.TIMEOUT


func can_redo() -> bool:
	return not redo_stack.is_empty() and result == Result.NONE


func resign(side: int) -> void:
	result = Result.RESIGNATION
	resigned_side = side
	result_side = CheckersTypes.opp(side)


func flag_timeout(side: int) -> void:
	result = Result.TIMEOUT
	timed_out_side = side
	result_side = CheckersTypes.opp(side)


func agree_draw() -> void:
	result = Result.DRAW_AGREED
	result_side = -1


func game_over() -> bool:
	return result != Result.NONE


func result_text() -> String:
	var w := CheckersTypes.side_name(result_side) if result_side >= 0 else ""
	var l := CheckersTypes.side_name(CheckersTypes.opp(result_side)) if result_side >= 0 else ""
	match result:
		Result.NO_MOVES:
			return "%s wins — %s has no moves" % [w, l]
		Result.NO_PIECES:
			return "%s wins — %s has no pieces" % [w, l]
		Result.RESIGNATION:
			return "%s resigns — %s wins" % [CheckersTypes.side_name(resigned_side), w]
		Result.TIMEOUT:
			return "%s wins on time — %s flagged" % [w, CheckersTypes.side_name(timed_out_side)]
		Result.DRAW_AGREED:
			return "Draw by agreement"
		Result.DRAW_MOVE_RULE:
			return "Draw — %s" % CheckersRules.move_rule_text(variant)
		Result.DRAW_REPETITION:
			return "Draw — position repeated three times"
		_:
			return "%s to move" % CheckersTypes.side_name(side_to_move)


func result_reason() -> String:
	match result:
		Result.NO_MOVES:
			return "No moves"
		Result.NO_PIECES:
			return "No pieces"
		Result.RESIGNATION:
			return "Resignation"
		Result.TIMEOUT:
			return "Time forfeit"
		Result.DRAW_AGREED:
			return "Agreement"
		Result.DRAW_MOVE_RULE:
			return "Move rule"
		Result.DRAW_REPETITION:
			return "Threefold repetition"
		_:
			return ""


## PDN convention: first number is White's score.
func result_token() -> String:
	if result == Result.NONE:
		return "*"
	if result_side == CheckersTypes.WHITE:
		return "1-0"
	if result_side == CheckersTypes.BLACK:
		return "0-1"
	return "1/2-1/2"


func repetition_count() -> int:
	var n := 0
	var lo := maxi(0, _ply - halfmove)
	var k := _key
	var i := _ply
	while i >= lo:
		if pos_keys[i] == k:
			n += 1
		i -= 1
	return n


func hash_key() -> int:
	return _key


# ------------------------------------------------------------------ FEN ----

func to_fen() -> String:
	return CheckersFen.dump(squares, side_to_move)


func from_fen(fen: String) -> bool:
	var r := CheckersFen.parse(fen)
	if not bool(r.get("ok", false)):
		return false
	load_position(r["squares"], int(r["side"]), int(r["halfmove"]), int(r["fullmove"]))
	return true


func _fen_with_counters() -> String:
	var f := to_fen()
	if halfmove != 0 or fullmove != 1:
		f += ":H%d:F%d" % [halfmove, fullmove]
	return f


# ------------------------------------------------------------- notation ----

## english: "11-15" / "22x15x6"; russian & brazilian: "c3-d4" / "c3:e5:g7".
func notation_for(m: CheckersMove) -> String:
	var bits := PackedStringArray()
	for q in m.path:
		if _numeric:
			bits.append(str(CheckersTypes.square_number(q)))
		else:
			bits.append(CheckersTypes.algebraic(q))
	if m.is_capture():
		return ("x" if _numeric else ":").join(bits)
	return "-".join(bits)


func move_number_for_ply(ply: int) -> int:
	if start_side == _first:
		return start_fullmove + ply / 2
	return start_fullmove + (ply + 1) / 2


func numbered_notation() -> String:
	var parts := PackedStringArray()
	for i in history.size():
		var m := history[i]
		var who := start_side if (i % 2) == 0 else 1 - start_side
		if who == _first:
			parts.append("%d." % move_number_for_ply(i))
		elif i == 0:
			parts.append("%d..." % move_number_for_ply(i))
		parts.append(m.notation if not m.notation.is_empty() else notation_for(m))
	return " ".join(parts)


# --------------------------------------------------------------- legacy ----

## Rebuild a game from a v1 save's per-hop list (["c3d4", "f6e5", "d4f6", ...])
## played from this engine's start position. Hops are grouped into full turns
## with candidates_for_prefix(). On failure the engine is left unchanged.
func replay_legacy_hops(hop_ucis: Array) -> bool:
	var backup := clone()
	from_fen(start_fen)
	var i := 0
	var ok := true
	while ok and i < hop_ucis.size():
		var ab := _hop(hop_ucis[i])
		i += 1
		if ab.is_empty():
			ok = false
			break
		var prefix := ab
		while true:
			var cands := candidates_for_prefix(prefix)
			if cands.is_empty():
				ok = false
				break
			var done: CheckersMove = null
			for c in cands:
				if c.path.size() == prefix.size():
					done = c
					break
			if done != null:
				if apply_move(done) == null:
					ok = false
				break
			if i >= hop_ucis.size():
				ok = false
				break
			var nxt := _hop(hop_ucis[i])
			i += 1
			if nxt.is_empty() or nxt[0] != prefix[prefix.size() - 1]:
				ok = false
				break
			prefix.append(nxt[1])
	if not ok:
		_copy_from(backup)
		return false
	return true


func _hop(v: Variant) -> PackedInt32Array:
	var t := str(v).strip_edges().to_lower()
	if t.length() < 4:
		return PackedInt32Array()
	var a := CheckersTypes.parse_square(t.substr(0, 2))
	var b := CheckersTypes.parse_square(t.substr(2, 2))
	if a < 0 or b < 0:
		return PackedInt32Array()
	return PackedInt32Array([a, b])


# ---------------------------------------------------------------- perft ----

## Number of full-turn move sequences at depth (draw rules ignored).
func perft(depth: int) -> int:
	if depth <= 0:
		return 1
	var buf := PackedInt64Array()
	buf.resize(64)
	var n := generate_keys(buf)
	if depth == 1:
		return n
	var total := 0
	for i in n:
		var k := buf[i]
		make_key(k)
		total += perft(depth - 1)
		unmake_key(k)
	return total


# ------------------------------------------------------- result refresh ----

func _refresh_result() -> void:
	if result == Result.RESIGNATION or result == Result.TIMEOUT or result == Result.DRAW_AGREED:
		return
	result = Result.NONE
	result_side = -1
	if piece_count(side_to_move) == 0:
		result = Result.NO_PIECES
		result_side = CheckersTypes.opp(side_to_move)
		return
	if generate_legal_moves().is_empty():
		result = Result.NO_MOVES
		result_side = CheckersTypes.opp(side_to_move)
		return
	if halfmove >= draw_plies:
		result = Result.DRAW_MOVE_RULE
		return
	if repetition_count() >= REPETITION_DRAW:
		result = Result.DRAW_REPETITION
		return


# ------------------------------------------------------ search interface ----

## Fill `out` with compact move keys for the side to move; returns the count.
## `out` grows if needed. Honours mandatory and majority capture.
func generate_keys(out: PackedInt64Array) -> int:
	_g_objects = false
	_g_keys = out
	_g_n = 0
	_generate()
	return _g_n


## Make a compact move. Updates squares, Zobrist key, counters and stacks.
func make_key(k: int) -> void:
	var sqs := squares
	var z := CheckersTypes.ZOBRIST
	var from := (k >> 32) & 63
	var to := (k >> 38) & 63
	var p := sqs[from]
	var h := _key ^ z[from * 32 + p]
	sqs[from] = 0
	var np := p
	if (k & CheckersTypes.KEY_PROMO) != 0:
		np = p + 1
	sqs[to] = np
	h ^= z[to * 32 + np]
	var m := k & 0xFFFFFFFF
	if m != 0:
		var us := _ustack
		var sp := _usp
		if sp + 16 >= us.size():
			us.resize(us.size() * 2)
		var mod := CheckersTypes.MOD37
		var i2s := CheckersTypes.IDX2SQ
		while m != 0:
			var b := m & -m
			var cs := i2s[mod[b % 37]]
			var cp := sqs[cs]
			us[sp] = cp
			sp += 1
			h ^= z[cs * 32 + cp]
			sqs[cs] = 0
			m ^= b
		_usp = sp
	var ply := _ply + 1
	if ply >= pos_keys.size():
		pos_keys.resize(pos_keys.size() * 2)
		_hstack.resize(pos_keys.size())
	_hstack[ply] = halfmove
	if (k & 0xFFFFFFFF) != 0 or (p & 15) == CheckersTypes.MAN:
		halfmove = 0
	else:
		halfmove += 1
	if side_to_move != _first:
		fullmove += 1
	side_to_move ^= 1
	h ^= CheckersTypes.ZOBRIST_SIDE
	_key = h
	pos_keys[ply] = h
	_ply = ply
	_cache_ok = false


func unmake_key(k: int) -> void:
	var sqs := squares
	var from := (k >> 32) & 63
	var to := (k >> 38) & 63
	side_to_move ^= 1
	if side_to_move != _first:
		fullmove -= 1
	halfmove = _hstack[_ply]
	_ply -= 1
	_key = pos_keys[_ply]
	var np := sqs[to]
	sqs[to] = 0
	sqs[from] = (np - 1) if (k & CheckersTypes.KEY_PROMO) != 0 else np
	var m := k & 0xFFFFFFFF
	if m != 0:
		var sp := _usp - ((k >> 45) & 31)
		_usp = sp
		var us := _ustack
		var mod := CheckersTypes.MOD37
		var i2s := CheckersTypes.IDX2SQ
		while m != 0:
			var b := m & -m
			sqs[i2s[mod[b % 37]]] = us[sp]
			sp += 1
			m ^= b
	_cache_ok = false


## True when the current position already occurred since the last
## irreversible move (search-time repetition = draw).
func is_repeat() -> bool:
	var lo := _ply - halfmove
	if lo < 0:
		lo = 0
	var k := _key
	var i := _ply - 2
	while i >= lo:
		if pos_keys[i] == k:
			return true
		i -= 2
	return false


func search_ply() -> int:
	return _ply


func _compute_key() -> int:
	var h := 0
	var z := CheckersTypes.ZOBRIST
	for s in CheckersTypes.DARK:
		var p := squares[s]
		if p != 0:
			h ^= z[s * 32 + p]
	if side_to_move == CheckersTypes.BLACK:
		h ^= CheckersTypes.ZOBRIST_SIDE
	return h


# ------------------------------------------------------------ generator ----

func _gen_objects() -> Array[CheckersMove]:
	_g_objects = true
	_g_list = []
	_g_n = 0
	_generate()
	var out := _g_list
	_g_list = []
	for m in out:
		m.notation = notation_for(m)
	return out


func _generate() -> void:
	if not _g_objects:
		_generate_compact()
		return
	var sqs := squares
	var nb := CheckersTypes.NB
	var side := side_to_move
	var own_man := 1 | (side << 4)
	var own_king := own_man + 1
	var flying := _flying
	var md0 := 0 if side == CheckersTypes.WHITE else 2
	var md1 := 4 if _men_back else md0 + 2
	if _men_back:
		md0 = 0
	_g_color = side
	_g_max = 0
	# Capture pass: cheap inline pre-check, full DFS only where a jump exists.
	for s in CheckersTypes.DARK:
		var p := sqs[s]
		if p != own_man and p != own_king:
			continue
		var can := false
		if p == own_king and flying:
			can = true
		else:
			var d := md0
			var d_end := md1
			if p == own_king:
				d = 0
				d_end = 4
			while d < d_end:
				var e := nb[s * 4 + d]
				if e >= 0:
					var pe := sqs[e]
					if pe != 0 and (pe >> 4) != side:
						var l := nb[e * 4 + d]
						if l >= 0 and sqs[l] == 0:
							can = true
							break
				d += 1
		if can:
			_g_type = p & 15
			_g_promo_at = -1
			_path[0] = s
			sqs[s] = 0
			_cap_dfs(s, p == own_king, 0, 0)
			sqs[s] = p
	if _g_n > 0:
		return
	var fd := 0 if side == CheckersTypes.WHITE else 2
	var prank := 7 if side == CheckersTypes.WHITE else 0
	for s in CheckersTypes.DARK:
		var p := sqs[s]
		if p == own_man:
			var t := nb[s * 4 + fd]
			if t >= 0 and sqs[t] == 0:
				_emit_quiet(s, t, (t >> 3) == prank)
			t = nb[s * 4 + fd + 1]
			if t >= 0 and sqs[t] == 0:
				_emit_quiet(s, t, (t >> 3) == prank)
		elif p == own_king:
			for d in 4:
				var t := nb[s * 4 + d]
				while t >= 0 and sqs[t] == 0:
					_emit_quiet(s, t, false)
					if not flying:
						break
					t = nb[t * 4 + d]


## Search fast path: one pass that emits quiet moves until the first capture is
## found, then switches to captures only (dropping the quiets).
func _generate_compact() -> void:
	var sqs := squares
	var nb := CheckersTypes.NB
	var side := side_to_move
	var own_man := 1 | (side << 4)
	var own_king := own_man + 1
	var flying := _flying
	var md0 := 0 if side == CheckersTypes.WHITE else 2
	var md1 := 4 if _men_back else md0 + 2
	if _men_back:
		md0 = 0
	var fd := 0 if side == CheckersTypes.WHITE else 2
	var prank := 7 if side == CheckersTypes.WHITE else 0
	var promo_bit := CheckersTypes.KEY_PROMO
	_g_color = side
	_g_max = 0
	_g_n = 0
	var out := _g_keys
	var n := 0
	var capmode := false
	for s in CheckersTypes.DARK:
		var p := sqs[s]
		if p != own_man and p != own_king:
			continue
		var can := false
		if p == own_man or not flying:
			var d := md0
			var d_end := md1
			if p == own_king:
				d = 0
				d_end = 4
			while d < d_end:
				var e := nb[s * 4 + d]
				if e >= 0:
					var pe := sqs[e]
					if pe != 0 and (pe >> 4) != side:
						var l := nb[e * 4 + d]
						if l >= 0 and sqs[l] == 0:
							can = true
							break
				d += 1
		else:
			for d in 4:
				var e := nb[s * 4 + d]
				while e >= 0 and sqs[e] == 0:
					e = nb[e * 4 + d]
				if e >= 0 and (sqs[e] >> 4) != side:
					var l := nb[e * 4 + d]
					if l >= 0 and sqs[l] == 0:
						can = true
						break
		if can:
			if not capmode:
				capmode = true
				_g_n = 0
			_g_type = p & 15
			_g_promo_at = -1
			_path[0] = s
			sqs[s] = 0
			_cap_dfs(s, p == own_king, 0, 0)
			sqs[s] = p
			continue
		if capmode:
			continue
		if p == own_man:
			if n + 4 >= out.size():
				out.resize(out.size() * 2 + 16)
			var t := nb[s * 4 + fd]
			if t >= 0 and sqs[t] == 0:
				out[n] = (s << 32) | (t << 38) | (promo_bit if (t >> 3) == prank else 0)
				n += 1
			t = nb[s * 4 + fd + 1]
			if t >= 0 and sqs[t] == 0:
				out[n] = (s << 32) | (t << 38) | (promo_bit if (t >> 3) == prank else 0)
				n += 1
		else:
			if n + 32 >= out.size():
				out.resize(out.size() * 2 + 32)
			for d in 4:
				var t := nb[s * 4 + d]
				while t >= 0 and sqs[t] == 0:
					out[n] = (s << 32) | (t << 38)
					n += 1
					if not flying:
						break
					t = nb[t * 4 + d]
	if not capmode:
		_g_n = n


func _emit_quiet(from: int, to: int, promo: bool) -> void:
	var k := (from << 32) | (to << 38)
	if promo:
		k |= CheckersTypes.KEY_PROMO
	if _g_objects:
		var m := CheckersMove.new()
		m.path = PackedInt32Array([from, to])
		m.piece = _g_type_at(from)
		m.color = _g_color
		m.promotes = promo
		m.promote_index = 1 if promo else -1
		m._key = k
		_g_list.append(m)
		_g_n += 1
		return
	if _g_n >= _g_keys.size():
		_g_keys.resize(_g_keys.size() * 2 + 16)
	_g_keys[_g_n] = k
	_g_n += 1


func _g_type_at(s: int) -> int:
	return squares[s] & 15


## Depth-first capture search from s. Returns true when at least one capture
## was available from s (the caller then does not emit a terminal move there).
func _cap_dfs(s: int, king: bool, mask: int, n: int) -> bool:
	var sqs := squares
	var nb := CheckersTypes.NB
	var color := _g_color
	var found := false
	var d0 := 0
	var d1 := 4
	if not king and not _men_back:
		d0 = 0 if color == CheckersTypes.WHITE else 2
		d1 = d0 + 2
	var flying := king and _flying
	for d in range(d0, d1):
		var e := nb[s * 4 + d]
		if flying:
			while e >= 0 and sqs[e] == 0:
				e = nb[e * 4 + d]
		if e < 0:
			continue
		var pe := sqs[e]
		if pe == 0 or (pe >> 4) == color:
			continue
		var bit := 1 << (e >> 1)
		if (mask & bit) != 0:
			continue
		var l := nb[e * 4 + d]
		if l < 0 or sqs[l] != 0:
			continue
		found = true
		var nmask := mask | bit
		_caps[n] = e
		if not flying:
			_path[n + 1] = l
			var k2 := king
			var crowned := false
			if not king and _crown_mid and (l >> 3) == (7 if color == CheckersTypes.WHITE else 0):
				k2 = true
				crowned = true
				_g_promo_at = n + 1
			if not _cap_dfs(l, k2, nmask, n + 1):
				_emit_capture(n + 1, l, nmask)
			if crowned:
				_g_promo_at = -1
		else:
			var any := false
			var t := l
			while t >= 0 and sqs[t] == 0:
				_path[n + 1] = t
				if _cap_dfs(t, true, nmask, n + 1):
					any = true
				t = nb[t * 4 + d]
			if not any:
				t = l
				while t >= 0 and sqs[t] == 0:
					_path[n + 1] = t
					_emit_capture(n + 1, t, nmask)
					t = nb[t * 4 + d]
	return found


func _emit_capture(ncap: int, last: int, mask: int) -> void:
	if ncap < _g_max and _majority:
		return
	if ncap > _g_max:
		if _majority and _g_n > 0:
			_g_n = 0
			if _g_objects:
				_g_list.clear()
		_g_max = ncap
	var origin := _path[0]
	var promo := false
	var pidx := -1
	if _g_type == CheckersTypes.MAN:
		if _g_promo_at >= 0:
			promo = true
			pidx = _g_promo_at
		elif (last >> 3) == (7 if _g_color == CheckersTypes.WHITE else 0):
			promo = true
			pidx = ncap
	var k := mask | (origin << 32) | (last << 38) | (ncap << 45)
	if promo:
		k |= CheckersTypes.KEY_PROMO
	if _g_objects:
		var m := CheckersMove.new()
		m.path = _path.slice(0, ncap + 1)
		m.captures = _caps.slice(0, ncap)
		var cp := PackedInt32Array()
		cp.resize(ncap)
		for i in ncap:
			cp[i] = squares[_caps[i]]
		m.captured_pieces = cp
		m.piece = _g_type
		m.color = _g_color
		m.promotes = promo
		m.promote_index = pidx
		m._key = k
		_g_list.append(m)
		_g_n += 1
		return
	if _g_n >= _g_keys.size():
		_g_keys.resize(_g_keys.size() * 2 + 16)
	_g_keys[_g_n] = k
	_g_n += 1
