class_name CheckersAI
extends RefCounted

const INF := 1000000
const MATE := 200000
const VAL_MAN := 100
const VAL_KING := 175
const MAX_CONTINUE := 12

const PST_MAN: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0,
	5, 0, 5, 0, 5, 0, 5, 0,
	0, 8, 0, 8, 0, 8, 0, 8,
	10, 0, 12, 0, 12, 0, 10, 0,
	0, 16, 0, 18, 0, 18, 0, 16,
	22, 0, 24, 0, 24, 0, 22, 0,
	0, 30, 0, 32, 0, 32, 0, 30,
	0, 0, 0, 0, 0, 0, 0, 0,
]
const PST_KING: Array[int] = [
	-10, 0, -5, 0, -5, 0, -10, 0,
	0, 5, 0, 8, 0, 8, 0, 5,
	-5, 0, 12, 0, 12, 0, 5, 0,
	0, 10, 0, 16, 0, 16, 0, 10,
	-5, 0, 16, 0, 16, 0, 10, 0,
	0, 8, 0, 12, 0, 12, 0, 8,
	-5, 0, 8, 0, 8, 0, 5, 0,
	0, -10, 0, -5, 0, -5, 0, -10,
]

var _nodes: int = 0
var _limit: int = 20000
var _deadline_msec: int = 0
var _timed_out := false


class SearchJob:
	extends RefCounted
	var fen: String = ""
	var difficulty: String = "medium"
	var move_uci: String = ""
	var nodes: int = 0

	func run() -> void:
		var engine := CheckersEngine.new()
		if not engine.from_fen(fen):
			return
		var ai := CheckersAI.new()
		var move := ai.search_configured(engine, difficulty)
		nodes = ai._nodes
		if move:
			move_uci = move.to_uci()


static func profile(difficulty: String) -> Dictionary:
	match difficulty:
		"easy":
			return {"depth": 2, "noise": 48.0, "limit": 1800, "budget_ms": 90}
		"hard":
			return {"depth": 6, "noise": 0.0, "limit": 28000, "budget_ms": 700}
		"master":
			return {"depth": 8, "noise": 0.0, "limit": 60000, "budget_ms": 1400}
		_:
			return {"depth": 4, "noise": 12.0, "limit": 8000, "budget_ms": 280}


static func choose(engine: CheckersEngine, difficulty: String = "medium") -> CheckersMove:
	var ai := CheckersAI.new()
	return ai.search_configured(engine, difficulty)


func search_configured(engine: CheckersEngine, difficulty: String) -> CheckersMove:
	var p := profile(difficulty)
	return search(engine, int(p.depth), float(p.noise), int(p.limit), int(p.budget_ms))


func search(engine: CheckersEngine, depth: int, noise: float = 0.0, limit: int = 20000, budget_ms: int = 280) -> CheckersMove:
	_nodes = 0
	_limit = maxi(limit, 64)
	_timed_out = false
	_deadline_msec = Time.get_ticks_msec() + maxi(budget_ms, 16)
	var work := engine.clone()
	work.history.clear()
	work.redo_stack.clear()
	var moves := _ordered(work)
	if moves.is_empty():
		return null
	var best: CheckersMove = moves[0]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var max_depth := maxi(depth, 1)
	for d in range(1, max_depth + 1):
		if _expired():
			break
		var iter_best: CheckersMove = best
		var best_score := -INF
		for m in moves:
			if _expired():
				break
			work.make_raw(m)
			var score := 0
			if work.is_drawish():
				score = 0
			elif work.must_continue_sq >= 0:
				score = _negamax(work, d, -INF, INF, 0)
			else:
				score = -_negamax(work, d - 1, -INF, INF, 0)
			work.unmake_raw(m)
			if noise > 0.0 and d == max_depth:
				score += int(rng.randf_range(-noise, noise))
			if score > best_score:
				best_score = score
				iter_best = m
		if not _timed_out:
			best = iter_best
		else:
			break
	return best


func _negamax(e: CheckersEngine, depth: int, alpha: int, beta: int, continue_plies: int) -> int:
	_nodes += 1
	if _expired():
		return _eval(e)
	if e.is_drawish():
		return 0
	if e.piece_count(e.side_to_move) == 0:
		return -MATE - depth
	var moves := _ordered(e)
	if moves.is_empty():
		return -MATE - depth
	var in_sequence := e.must_continue_sq >= 0
	if in_sequence and continue_plies >= MAX_CONTINUE:
		return _eval(e)
	if depth <= 0 and not in_sequence:
		if e.has_jumps():
			return _quiesce(e, alpha, beta, 4)
		return _eval(e)
	for m in moves:
		e.make_raw(m)
		var score := 0
		if e.is_drawish():
			score = 0
		elif e.must_continue_sq >= 0:
			score = _negamax(e, depth, alpha, beta, continue_plies + 1)
		else:
			score = -_negamax(e, maxi(depth - 1, 0), -beta, -alpha, 0)
		e.unmake_raw(m)
		if score >= beta:
			return beta
		if score > alpha:
			alpha = score
	return alpha


func _quiesce(e: CheckersEngine, alpha: int, beta: int, extra: int) -> int:
	_nodes += 1
	if _expired():
		return _eval(e)
	if e.is_drawish():
		return 0
	var stand := _eval(e)
	if extra <= 0:
		return stand
	if not e.has_jumps() and e.must_continue_sq < 0:
		return stand
	if stand >= beta and e.must_continue_sq < 0:
		return beta
	if stand > alpha and e.must_continue_sq < 0:
		alpha = stand
	var moves := _ordered(e)
	if moves.is_empty():
		return -MATE
	for m in moves:
		e.make_raw(m)
		var score := 0
		if e.is_drawish():
			score = 0
		elif e.must_continue_sq >= 0:
			score = _quiesce(e, alpha, beta, extra - 1)
		else:
			score = -_quiesce(e, -beta, -alpha, extra - 1)
		e.unmake_raw(m)
		if score >= beta:
			return beta
		if score > alpha:
			alpha = score
	return alpha


func _eval(e: CheckersEngine) -> int:
	var score := 0
	var white_n := 0
	var black_n := 0
	var white_k := 0
	var black_k := 0
	for sq in 64:
		var p := e.squares[sq]
		if p == 0:
			continue
		var t := CheckersTypes.ptype(p)
		var c := CheckersTypes.pcolor(p)
		if c == CheckersTypes.WHITE:
			white_n += 1
			if t == CheckersTypes.KING:
				white_k += 1
		else:
			black_n += 1
			if t == CheckersTypes.KING:
				black_k += 1
		var idx := sq if c == CheckersTypes.WHITE else CheckersTypes.sq(CheckersTypes.file_of(sq), 7 - CheckersTypes.rank_of(sq))
		var val := VAL_KING if t == CheckersTypes.KING else VAL_MAN
		val += _pst(t, idx)
		val += _advance_hint(e, sq, t, c)
		score += val if c == CheckersTypes.WHITE else -val
	if white_n == 0:
		score = -MATE / 2
	elif black_n == 0:
		score = MATE / 2
	else:
		score += (white_n - black_n) * 6
		score += (white_k - black_k) * 8
	return score if e.side_to_move == CheckersTypes.WHITE else -score


func _advance_hint(e: CheckersEngine, sq: int, type: int, color: int) -> int:
	var n := 0
	var f := CheckersTypes.file_of(sq)
	var r := CheckersTypes.rank_of(sq)
	var dirs := e._dirs_for(type, color)
	for d: Vector2i in dirs:
		var nf: int = f + d.x
		var nr: int = r + d.y
		if not CheckersTypes.in_board(nf, nr):
			continue
		if e.squares[CheckersTypes.sq(nf, nr)] == 0:
			n += 2
	return n


func _pst(type: int, idx: int) -> int:
	if idx < 0 or idx > 63:
		return 0
	if type == CheckersTypes.KING:
		return PST_KING[idx]
	return PST_MAN[idx]


func _ordered(e: CheckersEngine) -> Array[CheckersMove]:
	var moves := e.generate_legal_moves()
	moves.sort_custom(func(a: CheckersMove, b: CheckersMove) -> bool:
		return _mvv(a) > _mvv(b)
	)
	return moves


func _mvv(m: CheckersMove) -> int:
	var s := 0
	if m.is_capture():
		s += 80 + (VAL_KING if CheckersTypes.ptype(m.captured) == CheckersTypes.KING else VAL_MAN)
	if m.is_promotion():
		s += 90
	return s


func _expired() -> bool:
	if _nodes > _limit:
		_timed_out = true
		return true
	if (_nodes & 63) == 0 and Time.get_ticks_msec() >= _deadline_msec:
		_timed_out = true
		return true
	return false
