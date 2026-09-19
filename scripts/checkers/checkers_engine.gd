class_name CheckersEngine
extends RefCounted

enum Result {
	NONE,
	NO_MOVES,
	NO_PIECES,
	RESIGNATION,
	TIMEOUT,
	DRAW_AGREED,
}

var squares: PackedInt32Array = PackedInt32Array()
var side_to_move: int = CheckersTypes.BLACK
var must_continue_sq: int = -1
var halfmove: int = 0
var fullmove: int = 1
var next_turn_id: int = 1
var history: Array[CheckersMove] = []
var redo_stack: Array[CheckersMove] = []
var result: Result = Result.NONE
var result_side: int = -1
var resigned_side: int = -1
var timed_out_side: int = -1


func _init() -> void:
	squares.resize(64)
	reset()


func reset() -> void:
	from_fen(CheckersTypes.START_FEN)


func clear() -> void:
	for i in 64:
		squares[i] = 0
	side_to_move = CheckersTypes.BLACK
	must_continue_sq = -1
	halfmove = 0
	fullmove = 1
	next_turn_id = 1
	history.clear()
	redo_stack.clear()
	result = Result.NONE
	result_side = -1
	resigned_side = -1
	timed_out_side = -1


func clone() -> CheckersEngine:
	var e := CheckersEngine.new()
	e.squares = squares.duplicate()
	e.side_to_move = side_to_move
	e.must_continue_sq = must_continue_sq
	e.halfmove = halfmove
	e.fullmove = fullmove
	e.next_turn_id = next_turn_id
	e.result = result
	e.result_side = result_side
	e.resigned_side = resigned_side
	e.timed_out_side = timed_out_side
	e.history.clear()
	for m in history:
		e.history.append(m.duplicate_move())
	e.redo_stack.clear()
	for m in redo_stack:
		e.redo_stack.append(m.duplicate_move())
	return e


func piece_at(sq: int) -> int:
	if sq < 0 or sq > 63:
		return 0
	return squares[sq]


func piece_count(side: int) -> int:
	var n := 0
	for i in 64:
		var p := squares[i]
		if p != 0 and CheckersTypes.pcolor(p) == side:
			n += 1
	return n


func generate_legal_moves() -> Array[CheckersMove]:
	if must_continue_sq >= 0:
		return _generate_jumps_from(must_continue_sq)
	var jumps := _generate_all_jumps()
	if not jumps.is_empty():
		return jumps
	return _generate_quiets()


func generate_legal_from(from_sq: int) -> Array[CheckersMove]:
	var out: Array[CheckersMove] = []
	for m in generate_legal_moves():
		if m.from_sq == from_sq:
			out.append(m)
	return out


func has_jumps(side: int = -1) -> bool:
	var who := side_to_move if side < 0 else side
	if must_continue_sq >= 0 and who == side_to_move:
		return not _generate_jumps_from(must_continue_sq).is_empty()
	for sq in 64:
		var p := squares[sq]
		if p == 0 or CheckersTypes.pcolor(p) != who:
			continue
		if not _jumps_from_raw(sq).is_empty():
			return true
	return false


func find_move(from_sq: int, to_sq: int) -> CheckersMove:
	for m in generate_legal_moves():
		if m.matches(from_sq, to_sq):
			return m
	return null


func is_legal(from_sq: int, to_sq: int) -> bool:
	return find_move(from_sq, to_sq) != null


func play(from_sq: int, to_sq: int) -> CheckersMove:
	var m := find_move(from_sq, to_sq)
	if m == null:
		return null
	return apply_move(m)


func apply_move(m: CheckersMove, clear_redo: bool = true) -> CheckersMove:
	if result != Result.NONE:
		return null
	if must_continue_sq < 0:
		m.turn_id = next_turn_id
	else:
		m.turn_id = history[history.size() - 1].turn_id if not history.is_empty() else next_turn_id
	if (m.flags & CheckersTypes.FLAG_CONTINUE) == 0 and must_continue_sq >= 0:
		m.flags |= CheckersTypes.FLAG_CONTINUE
	_make(m)
	m.notation = m.describe()
	m.uci = m.to_uci()
	if clear_redo:
		redo_stack.clear()
	history.append(m)
	if m.ended_turn:
		next_turn_id += 1
	_refresh_result()
	return m


func undo() -> CheckersMove:
	if history.is_empty():
		return null
	var m: CheckersMove = history.pop_back()
	_unmake(m)
	redo_stack.append(m)
	if history.is_empty():
		next_turn_id = 1
	elif history[history.size() - 1].ended_turn:
		next_turn_id = history[history.size() - 1].turn_id + 1
	else:
		next_turn_id = history[history.size() - 1].turn_id
	result = Result.NONE
	result_side = -1
	resigned_side = -1
	timed_out_side = -1
	return m


func undo_turn() -> void:
	if history.is_empty():
		return
	var tid: int = history[history.size() - 1].turn_id
	while not history.is_empty() and history[history.size() - 1].turn_id == tid:
		undo()


func redo() -> CheckersMove:
	if redo_stack.is_empty():
		return null
	var m: CheckersMove = redo_stack.pop_back()
	return apply_move(m, false)


func redo_turn() -> void:
	if redo_stack.is_empty():
		return
	var tid: int = redo_stack[redo_stack.size() - 1].turn_id
	while not redo_stack.is_empty() and redo_stack[redo_stack.size() - 1].turn_id == tid:
		if redo() == null:
			break


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
	match result:
		Result.NO_MOVES:
			return "%s wins — %s has no moves" % [CheckersTypes.side_name(result_side), CheckersTypes.side_name(CheckersTypes.opp(result_side))]
		Result.NO_PIECES:
			return "%s wins — %s has no pieces" % [CheckersTypes.side_name(result_side), CheckersTypes.side_name(CheckersTypes.opp(result_side))]
		Result.RESIGNATION:
			return "%s resigns — %s wins" % [CheckersTypes.side_name(resigned_side), CheckersTypes.side_name(result_side)]
		Result.TIMEOUT:
			return "%s flagged — %s wins" % [CheckersTypes.side_name(timed_out_side), CheckersTypes.side_name(result_side)]
		Result.DRAW_AGREED:
			return "Draw by agreement"
		_:
			if must_continue_sq >= 0:
				return "%s must continue jumping" % CheckersTypes.side_name(side_to_move)
			return "%s to move" % CheckersTypes.side_name(side_to_move)


func to_fen() -> String:
	return CheckersFen.dump(self)


func from_fen(fen: String) -> bool:
	if not CheckersFen.parse(self, fen):
		return false
	_refresh_result()
	return true


func make_raw(m: CheckersMove) -> void:
	_make(m)


func unmake_raw(m: CheckersMove) -> void:
	_unmake(m)


func perft(depth: int) -> int:
	if depth <= 0:
		return 1
	var n := 0
	for m in generate_legal_moves():
		_make(m)
		if must_continue_sq >= 0:
			n += perft(depth)
		else:
			n += perft(depth - 1)
		_unmake(m)
	return n


func hop_history() -> PackedStringArray:
	var out := PackedStringArray()
	for m in history:
		out.append(m.to_uci())
	return out


func numbered_notation() -> String:
	if history.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	var i := 0
	var shown := 0
	while i < history.size():
		var tid: int = history[i].turn_id
		var hops: Array[CheckersMove] = []
		while i < history.size() and history[i].turn_id == tid:
			hops.append(history[i])
			i += 1
		shown += 1
		parts.append("%d." % shown)
		parts.append(_format_turn(hops))
	return " ".join(parts)


func turn_groups() -> Array:
	var groups: Array = []
	var i := 0
	while i < history.size():
		var tid: int = history[i].turn_id
		var hops: Array[CheckersMove] = []
		while i < history.size() and history[i].turn_id == tid:
			hops.append(history[i])
			i += 1
		groups.append(hops)
	return groups


func _format_turn(hops: Array[CheckersMove]) -> String:
	if hops.is_empty():
		return ""
	if hops.size() == 1 and not hops[0].is_capture():
		return "%s-%s" % [CheckersTypes.algebraic(hops[0].from_sq), CheckersTypes.algebraic(hops[0].to_sq)]
	var bits: PackedStringArray = PackedStringArray()
	bits.append(CheckersTypes.algebraic(hops[0].from_sq))
	for h in hops:
		bits.append(CheckersTypes.algebraic(h.to_sq))
	return "x".join(bits)


func _refresh_result() -> void:
	if result == Result.RESIGNATION or result == Result.TIMEOUT or result == Result.DRAW_AGREED:
		return
	if must_continue_sq >= 0:
		result = Result.NONE
		result_side = -1
		return
	if piece_count(side_to_move) == 0:
		result = Result.NO_PIECES
		result_side = CheckersTypes.opp(side_to_move)
		return
	if generate_legal_moves().is_empty():
		result = Result.NO_MOVES
		result_side = CheckersTypes.opp(side_to_move)
		return
	result = Result.NONE
	result_side = -1


func _dirs_for(type: int, color: int) -> Array[Vector2i]:
	if type == CheckersTypes.KING:
		return CheckersTypes.DIAG_DIRS
	var fwd := CheckersTypes.man_forward(color)
	var out: Array[Vector2i] = []
	out.append(Vector2i(1, fwd))
	out.append(Vector2i(-1, fwd))
	return out


func _generate_all_jumps() -> Array[CheckersMove]:
	var moves: Array[CheckersMove] = []
	for sq in 64:
		var p := squares[sq]
		if p == 0 or CheckersTypes.pcolor(p) != side_to_move:
			continue
		moves.append_array(_generate_jumps_from(sq))
	return moves


func _generate_jumps_from(sq: int) -> Array[CheckersMove]:
	var built: Array[CheckersMove] = []
	for hop in _jumps_from_raw(sq):
		built.append(_build_from_raw(hop))
	return built


func _jumps_from_raw(sq: int) -> Array:
	var raw: Array = []
	var p := squares[sq]
	if p == 0:
		return raw
	var type := CheckersTypes.ptype(p)
	var color := CheckersTypes.pcolor(p)
	var f := CheckersTypes.file_of(sq)
	var r := CheckersTypes.rank_of(sq)
	for d: Vector2i in _dirs_for(type, color):
		var mf: int = f + d.x
		var mr: int = r + d.y
		var lf: int = f + d.x * 2
		var lr: int = r + d.y * 2
		if not CheckersTypes.in_board(mf, mr) or not CheckersTypes.in_board(lf, lr):
			continue
		var mid := CheckersTypes.sq(mf, mr)
		var land := CheckersTypes.sq(lf, lr)
		var cap := squares[mid]
		if cap == 0 or CheckersTypes.pcolor(cap) == color:
			continue
		if squares[land] != 0:
			continue
		raw.append({"from": sq, "to": land, "cap_sq": mid, "cap": cap})
	return raw


func _generate_quiets() -> Array[CheckersMove]:
	var moves: Array[CheckersMove] = []
	for sq in 64:
		var p := squares[sq]
		if p == 0 or CheckersTypes.pcolor(p) != side_to_move:
			continue
		var type := CheckersTypes.ptype(p)
		var f := CheckersTypes.file_of(sq)
		var r := CheckersTypes.rank_of(sq)
		for d: Vector2i in _dirs_for(type, CheckersTypes.pcolor(p)):
			var nf: int = f + d.x
			var nr: int = r + d.y
			if not CheckersTypes.in_board(nf, nr):
				continue
			var to := CheckersTypes.sq(nf, nr)
			if squares[to] != 0:
				continue
			moves.append(_build(sq, to, type, 0, -1, 0))
	return moves


func _build_from_raw(hop: Dictionary) -> CheckersMove:
	var from_sq: int = hop["from"]
	var to_sq: int = hop["to"]
	var p := squares[from_sq]
	return _build(from_sq, to_sq, CheckersTypes.ptype(p), hop["cap"], hop["cap_sq"], CheckersTypes.FLAG_CAPTURE)


func _build(from_sq: int, to_sq: int, piece: int, captured: int, cap_sq: int, flags: int) -> CheckersMove:
	var m := CheckersMove.new()
	m.from_sq = from_sq
	m.to_sq = to_sq
	m.piece = piece
	m.color = side_to_move
	m.captured = captured
	m.captured_sq = cap_sq
	if piece == CheckersTypes.MAN and CheckersTypes.rank_of(to_sq) == CheckersTypes.promotion_rank(side_to_move):
		flags |= CheckersTypes.FLAG_PROMO
	if must_continue_sq >= 0:
		flags |= CheckersTypes.FLAG_CONTINUE
	m.flags = flags
	return m


func _make(m: CheckersMove) -> void:
	m.prev_must_continue = must_continue_sq
	m.prev_halfmove = halfmove
	m.color = side_to_move
	var moving := squares[m.from_sq]
	squares[m.from_sq] = 0
	if m.captured_sq >= 0:
		squares[m.captured_sq] = 0
	if m.is_promotion():
		squares[m.to_sq] = CheckersTypes.pack(CheckersTypes.KING, side_to_move)
	else:
		squares[m.to_sq] = moving
	var ends := true
	# English/American: crowning ends the turn even if the new king could jump.
	if m.is_capture() and not m.is_promotion():
		must_continue_sq = m.to_sq
		if not _jumps_from_raw(m.to_sq).is_empty():
			ends = false
	if ends:
		must_continue_sq = -1
		m.ended_turn = true
		if side_to_move == CheckersTypes.WHITE:
			fullmove += 1
		side_to_move = CheckersTypes.opp(side_to_move)
	else:
		must_continue_sq = m.to_sq
		m.ended_turn = false
	if m.is_capture():
		halfmove = 0
	else:
		halfmove += 1


func _unmake(m: CheckersMove) -> void:
	if m.ended_turn:
		if m.color == CheckersTypes.WHITE:
			fullmove -= 1
	side_to_move = m.color
	must_continue_sq = m.prev_must_continue
	halfmove = m.prev_halfmove
	squares[m.from_sq] = CheckersTypes.pack(m.piece, m.color)
	squares[m.to_sq] = 0
	if m.captured_sq >= 0:
		squares[m.captured_sq] = m.captured
