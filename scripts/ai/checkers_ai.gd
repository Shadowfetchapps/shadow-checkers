class_name CheckersAI
extends RefCounted

const INF := 1000000
const MATE := 200000
const VAL_MAN := 100
const VAL_KING := 175

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


static func choose(engine: CheckersEngine, difficulty: String = "medium") -> CheckersMove:
	var depth := 4
	var noise := 0.0
	var limit := 20000
	match difficulty:
		"easy":
			depth = 2
			noise = 40.0
			limit = 2500
		"hard":
			depth = 6
			noise = 0.0
			limit = 90000
		"master":
			depth = 8
			noise = 0.0
			limit = 220000
		_:
			depth = 4
			noise = 10.0
			limit = 20000
	var ai := CheckersAI.new()
	return ai.search(engine, depth, noise, limit)


func search(engine: CheckersEngine, depth: int, noise: float = 0.0, limit: int = 20000) -> CheckersMove:
	_nodes = 0
	_limit = limit
	var work := engine.clone()
	work.history.clear()
	work.redo_stack.clear()
	var moves := _ordered(work)
	if moves.is_empty():
		return null
	var best: CheckersMove = moves[0]
	var best_score := -INF
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for m in moves:
		work.make_raw(m)
		var score := 0
		if work.must_continue_sq >= 0:
			score = _negamax(work, depth, -INF, INF)
		else:
			score = -_negamax(work, depth - 1, -INF, INF)
		work.unmake_raw(m)
		if noise > 0.0:
			score += int(rng.randf_range(-noise, noise))
		if score > best_score:
			best_score = score
			best = m
	return best


func _negamax(e: CheckersEngine, depth: int, alpha: int, beta: int) -> int:
	_nodes += 1
	if _nodes > _limit:
		return _eval(e)
	if e.piece_count(e.side_to_move) == 0:
		return -MATE - depth
	var moves := _ordered(e)
	if moves.is_empty():
		return -MATE - depth
	var in_sequence := e.must_continue_sq >= 0
	if depth <= 0 and not in_sequence:
		if e.has_jumps():
			return _quiesce(e, alpha, beta, 6)
		return _eval(e)
	for m in moves:
		e.make_raw(m)
		var score := 0
		if e.must_continue_sq >= 0:
			score = _negamax(e, depth, alpha, beta)
		else:
			score = -_negamax(e, maxi(depth - 1, 0), -beta, -alpha)
		e.unmake_raw(m)
		if score >= beta:
			return beta
		if score > alpha:
			alpha = score
	return alpha


func _quiesce(e: CheckersEngine, alpha: int, beta: int, extra: int) -> int:
	_nodes += 1
	if _nodes > _limit:
		return _eval(e)
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
		if e.must_continue_sq >= 0:
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
	for sq in 64:
		var p := e.squares[sq]
		if p == 0:
			continue
		var t := CheckersTypes.ptype(p)
		var c := CheckersTypes.pcolor(p)
		if c == CheckersTypes.WHITE:
			white_n += 1
		else:
			black_n += 1
		var idx := sq if c == CheckersTypes.WHITE else CheckersTypes.sq(CheckersTypes.file_of(sq), 7 - CheckersTypes.rank_of(sq))
		var val := VAL_KING if t == CheckersTypes.KING else VAL_MAN
		val += _pst(t, idx)
		score += val if c == CheckersTypes.WHITE else -val
	if white_n == 0:
		score = -MATE / 2
	elif black_n == 0:
		score = MATE / 2
	var mob := e.generate_legal_moves().size()
	score += mob * (2 if e.side_to_move == CheckersTypes.WHITE else -2)
	return score if e.side_to_move == CheckersTypes.WHITE else -score


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
