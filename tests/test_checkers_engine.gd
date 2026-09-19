class_name TestCheckersEngine
extends RefCounted

var _passed := 0
var _failed := 0
var _errors: PackedStringArray = PackedStringArray()


func run_all() -> bool:
	_passed = 0
	_failed = 0
	_errors.clear()
	_test_start_position()
	_test_dark_squares_only()
	_test_man_movement()
	_test_blocked_pieces()
	_test_captures()
	_test_forced_capture()
	_test_multi_jump()
	_test_promotion()
	_test_promotion_ends_jump()
	_test_king_moves()
	_test_king_captures()
	_test_win_no_pieces()
	_test_win_no_moves()
	_test_illegal_rejected()
	_test_undo_redo()
	_test_fen_roundtrip()
	_test_black_moves_first()
	_test_perft_start()
	print("\n==============================")
	print("Shadow Checkers  —  %d passed, %d failed" % [_passed, _failed])
	for e in _errors:
		print("  FAIL  ", e)
	print("==============================\n")
	return _failed == 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ok    ", name)
	else:
		_failed += 1
		var msg := name if detail.is_empty() else "%s — %s" % [name, detail]
		_errors.append(msg)
		print("  FAIL  ", msg)


func _e() -> CheckersEngine:
	return CheckersEngine.new()


func _has(engine: CheckersEngine, uci: String) -> bool:
	for m in engine.generate_legal_moves():
		if m.to_uci() == uci:
			return true
	return false


func _count(engine: CheckersEngine) -> int:
	return engine.generate_legal_moves().size()


func _count_from(engine: CheckersEngine, from_alg: String) -> int:
	return engine.generate_legal_from(CheckersTypes.parse_square(from_alg)).size()


func _place(engine: CheckersEngine, alg: String, type: int, color: int) -> void:
	engine.squares[CheckersTypes.parse_square(alg)] = CheckersTypes.pack(type, color)


func _empty(side: int = CheckersTypes.BLACK) -> CheckersEngine:
	var e := CheckersEngine.new()
	e.clear()
	e.side_to_move = side
	e.result = CheckersEngine.Result.NONE
	return e


func _test_start_position() -> void:
	print("start position")
	var e := _e()
	_ok("start fen prefix", e.to_fen().begins_with("1b1b1b1b/b1b1b1b1/1b1b1b1b/8/8/w1w1w1w1/1w1w1w1w/w1w1w1w1 b"))
	_ok("12 white", e.piece_count(CheckersTypes.WHITE) == 12, str(e.piece_count(CheckersTypes.WHITE)))
	_ok("12 black", e.piece_count(CheckersTypes.BLACK) == 12, str(e.piece_count(CheckersTypes.BLACK)))
	_ok("7 legal at start", _count(e) == 7, str(_count(e)))
	_ok("black to move", e.side_to_move == CheckersTypes.BLACK)
	_ok("not over", not e.game_over())


func _test_dark_squares_only() -> void:
	print("dark squares")
	var e := _e()
	for sq in 64:
		var p := e.piece_at(sq)
		if p != 0:
			_ok("piece on dark %s" % CheckersTypes.algebraic(sq), CheckersTypes.is_dark(sq))
	_ok("a1 is dark", CheckersTypes.is_dark(CheckersTypes.parse_square("a1")))
	_ok("b1 is light", not CheckersTypes.is_dark(CheckersTypes.parse_square("b1")))
	_ok("b1 not occupied", e.piece_at(CheckersTypes.parse_square("b1")) == 0)


func _test_man_movement() -> void:
	print("man movement")
	var e := _e()
	_ok("b6a5", _has(e, "b6a5"))
	_ok("b6c5", _has(e, "b6c5"))
	_ok("h6g5", _has(e, "h6g5"))
	_ok("no backward black", not _has(e, "b6a7") and not _has(e, "b6c7"))
	_ok("no sideways", not _has(e, "b6b5"))
	_ok("no two-step quiet", not _has(e, "b6d4"))
	e.play(CheckersTypes.parse_square("b6"), CheckersTypes.parse_square("c5"))
	_ok("white to move after quiet", e.side_to_move == CheckersTypes.WHITE)
	_ok("white man forward c3d4", _has(e, "c3d4"))
	_ok("white man forward c3b4", _has(e, "c3b4"))
	_ok("white no backward", not _has(e, "c3b2") and not _has(e, "c3d2"))
	var lonely := _empty(CheckersTypes.WHITE)
	_place(lonely, "c5", CheckersTypes.MAN, CheckersTypes.WHITE)
	_ok("lonely white 2 quiets", _count_from(lonely, "c5") == 2, str(_count_from(lonely, "c5")))
	_ok("c5d6", _has(lonely, "c5d6"))
	_ok("c5b6", _has(lonely, "c5b6"))
	_ok("c5 no back", not _has(lonely, "c5b4") and not _has(lonely, "c5d4"))


func _test_blocked_pieces() -> void:
	print("blocked pieces")
	var e := _empty(CheckersTypes.WHITE)
	_place(e, "c3", CheckersTypes.MAN, CheckersTypes.WHITE)
	_place(e, "b4", CheckersTypes.MAN, CheckersTypes.WHITE)
	_place(e, "d4", CheckersTypes.MAN, CheckersTypes.WHITE)
	_ok("blocked white man 0", _count_from(e, "c3") == 0, str(_count_from(e, "c3")))
	var e2 := _empty(CheckersTypes.BLACK)
	_place(e2, "d6", CheckersTypes.MAN, CheckersTypes.BLACK)
	_place(e2, "c5", CheckersTypes.MAN, CheckersTypes.WHITE)
	_place(e2, "e5", CheckersTypes.MAN, CheckersTypes.WHITE)
	# Both forwards occupied but both are jumpable — jumps required.
	_ok("blocked-by-enemy is jump", _count_from(e2, "d6") == 2, str(_count_from(e2, "d6")))
	_ok("d6b4", _has(e2, "d6b4"))
	_ok("d6f4", _has(e2, "d6f4"))
	var e3 := _empty(CheckersTypes.WHITE)
	_place(e3, "a1", CheckersTypes.MAN, CheckersTypes.WHITE)
	_place(e3, "b2", CheckersTypes.MAN, CheckersTypes.WHITE)
	_ok("corner man blocked", _count_from(e3, "a1") == 0)


func _test_captures() -> void:
	print("captures")
	var e := _empty(CheckersTypes.BLACK)
	_place(e, "c5", CheckersTypes.MAN, CheckersTypes.BLACK)
	_place(e, "d4", CheckersTypes.MAN, CheckersTypes.WHITE)
	var m := e.play(CheckersTypes.parse_square("c5"), CheckersTypes.parse_square("e3"))
	_ok("capture played", m != null and m.is_capture())
	_ok("landed e3", CheckersTypes.ptype(e.piece_at(CheckersTypes.parse_square("e3"))) == CheckersTypes.MAN)
	_ok("captured removed", e.piece_at(CheckersTypes.parse_square("d4")) == 0)
	_ok("origin empty", e.piece_at(CheckersTypes.parse_square("c5")) == 0)
	_ok("side switched", e.side_to_move == CheckersTypes.WHITE)
	var no := _empty(CheckersTypes.BLACK)
	_place(no, "c5", CheckersTypes.MAN, CheckersTypes.BLACK)
	_place(no, "d4", CheckersTypes.MAN, CheckersTypes.BLACK)
	_ok("cannot jump own", not _has(no, "c5e3"))
	var back := _empty(CheckersTypes.BLACK)
	_place(back, "c5", CheckersTypes.MAN, CheckersTypes.BLACK)
	_place(back, "d6", CheckersTypes.MAN, CheckersTypes.WHITE)
	_ok("man cannot capture backward", not _has(back, "c5e7"))


func _test_forced_capture() -> void:
	print("forced capture")
	var e := _empty(CheckersTypes.BLACK)
	_place(e, "c5", CheckersTypes.MAN, CheckersTypes.BLACK)
	_place(e, "a5", CheckersTypes.MAN, CheckersTypes.BLACK)
	_place(e, "d4", CheckersTypes.MAN, CheckersTypes.WHITE)
	_ok("only the jump is legal", _count(e) == 1, str(_count(e)))
	_ok("jump c5e3", _has(e, "c5e3"))
	_ok("quiet a5b4 forbidden", not _has(e, "a5b4"))
	_ok("quiet c5b4 forbidden", not _has(e, "c5b4"))
	_ok("play quiet rejected", e.play(CheckersTypes.parse_square("a5"), CheckersTypes.parse_square("b4")) == null)


func _test_multi_jump() -> void:
	print("multi-jump")
	var e := _empty(CheckersTypes.BLACK)
	_place(e, "c5", CheckersTypes.MAN, CheckersTypes.BLACK)
	_place(e, "d4", CheckersTypes.MAN, CheckersTypes.WHITE)
	_place(e, "f2", CheckersTypes.MAN, CheckersTypes.WHITE)
	var first := e.play(CheckersTypes.parse_square("c5"), CheckersTypes.parse_square("e3"))
	_ok("first hop", first != null and first.is_capture())
	_ok("must continue", e.must_continue_sq == CheckersTypes.parse_square("e3"))
	_ok("still black", e.side_to_move == CheckersTypes.BLACK)
	_ok("only e3g1", _count(e) == 1 and _has(e, "e3g1"), str(_count(e)))
	_ok("cannot switch piece", e.play(CheckersTypes.parse_square("c5"), CheckersTypes.parse_square("b4")) == null)
	var second := e.play(CheckersTypes.parse_square("e3"), CheckersTypes.parse_square("g1"))
	_ok("second hop", second != null)
	_ok("promoted on last rank", CheckersTypes.ptype(e.piece_at(CheckersTypes.parse_square("g1"))) == CheckersTypes.KING)
	_ok("both whites gone", e.piece_at(CheckersTypes.parse_square("d4")) == 0 and e.piece_at(CheckersTypes.parse_square("f2")) == 0)
	_ok("turn ended after promo/sequence", e.must_continue_sq < 0)
	_ok("white to move", e.side_to_move == CheckersTypes.WHITE)
	_ok("same turn id", first.turn_id == second.turn_id)
	var grouped := e.turn_groups()
	_ok("one turn group", grouped.size() == 1)
	_ok("notation multi", e.numbered_notation().contains("c5xe3xg1"), e.numbered_notation())


func _test_promotion() -> void:
	print("promotion")
	var e := _empty(CheckersTypes.WHITE)
	_place(e, "b7", CheckersTypes.MAN, CheckersTypes.WHITE)
	var m := e.play(CheckersTypes.parse_square("b7"), CheckersTypes.parse_square("a8"))
	_ok("promo move", m != null and m.is_promotion())
	_ok("now king", CheckersTypes.ptype(e.piece_at(CheckersTypes.parse_square("a8"))) == CheckersTypes.KING)
	_ok("white color kept", CheckersTypes.pcolor(e.piece_at(CheckersTypes.parse_square("a8"))) == CheckersTypes.WHITE)
	var b := _empty(CheckersTypes.BLACK)
	_place(b, "c2", CheckersTypes.MAN, CheckersTypes.BLACK)
	var mb := b.play(CheckersTypes.parse_square("c2"), CheckersTypes.parse_square("d1"))
	_ok("black promo", mb != null and mb.is_promotion())
	_ok("black king", CheckersTypes.ptype(b.piece_at(CheckersTypes.parse_square("d1"))) == CheckersTypes.KING)


func _test_promotion_ends_jump() -> void:
	print("promotion ends jump")
	var e := _empty(CheckersTypes.WHITE)
	_place(e, "f6", CheckersTypes.MAN, CheckersTypes.WHITE)
	_place(e, "e7", CheckersTypes.MAN, CheckersTypes.BLACK)
	_place(e, "c7", CheckersTypes.MAN, CheckersTypes.BLACK)
	# f6xe8 (d8) crowns. New king could jump c7 to b6, but English rules end the turn.
	var m := e.play(CheckersTypes.parse_square("f6"), CheckersTypes.parse_square("d8"))
	_ok("crowning jump", m != null and m.is_promotion() and m.is_capture())
	_ok("is king", CheckersTypes.ptype(e.piece_at(CheckersTypes.parse_square("d8"))) == CheckersTypes.KING)
	_ok("turn ended", e.must_continue_sq < 0)
	_ok("black to move", e.side_to_move == CheckersTypes.BLACK)
	_ok("c7 still there", e.piece_at(CheckersTypes.parse_square("c7")) != 0)


func _test_king_moves() -> void:
	print("king moves")
	var e := _empty(CheckersTypes.WHITE)
	_place(e, "d4", CheckersTypes.KING, CheckersTypes.WHITE)
	_ok("king 4 quiets", _count_from(e, "d4") == 4, str(_count_from(e, "d4")))
	_ok("d4e5", _has(e, "d4e5"))
	_ok("d4c5", _has(e, "d4c5"))
	_ok("d4e3", _has(e, "d4e3"))
	_ok("d4c3", _has(e, "d4c3"))
	_ok("king not flying", not _has(e, "d4f6") and not _has(e, "d4a1"))
	_place(e, "e5", CheckersTypes.MAN, CheckersTypes.WHITE)
	_ok("king blocked one way", _count_from(e, "d4") == 3, str(_count_from(e, "d4")))


func _test_king_captures() -> void:
	print("king captures")
	var e := _empty(CheckersTypes.WHITE)
	_place(e, "d4", CheckersTypes.KING, CheckersTypes.WHITE)
	_place(e, "e5", CheckersTypes.MAN, CheckersTypes.BLACK)
	_place(e, "c3", CheckersTypes.MAN, CheckersTypes.BLACK)
	_ok("forced king jumps", _count(e) == 2, str(_count(e)))
	_ok("d4f6", _has(e, "d4f6"))
	_ok("d4b2", _has(e, "d4b2"))
	_ok("no quiet while jump", not _has(e, "d4c5"))
	e.play(CheckersTypes.parse_square("d4"), CheckersTypes.parse_square("f6"))
	_ok("king captured", e.piece_at(CheckersTypes.parse_square("e5")) == 0)
	_ok("king on f6", CheckersTypes.ptype(e.piece_at(CheckersTypes.parse_square("f6"))) == CheckersTypes.KING)


func _test_win_no_pieces() -> void:
	print("win no pieces")
	var e := _empty(CheckersTypes.WHITE)
	_place(e, "c3", CheckersTypes.MAN, CheckersTypes.WHITE)
	_place(e, "d4", CheckersTypes.MAN, CheckersTypes.BLACK)
	e.play(CheckersTypes.parse_square("c3"), CheckersTypes.parse_square("e5"))
	_ok("black has 0", e.piece_count(CheckersTypes.BLACK) == 0)
	_ok("game over", e.game_over())
	_ok("no pieces result", e.result == CheckersEngine.Result.NO_PIECES)
	_ok("white wins", e.result_side == CheckersTypes.WHITE)


func _test_win_no_moves() -> void:
	print("win no moves")
	var e := _empty(CheckersTypes.BLACK)
	# Black man on a1 (dark) has no backward/forward off-board; blocked.
	# White king on b2 occupies the only adjacent dark. Black to move, no jumps (b2 is own-side? white is opponent — can jump?)
	# a1 man black: forward is -rank, off the board. No quiet. Jump would need mid on off-board or...
	# Better: white pieces occupy both forward squares and landings are off/occupied.
	_place(e, "a1", CheckersTypes.MAN, CheckersTypes.BLACK)
	_place(e, "b2", CheckersTypes.KING, CheckersTypes.WHITE)
	_place(e, "c3", CheckersTypes.KING, CheckersTypes.WHITE)
	# Black a1: no forward (off board). Jump NE would be b2 landing c3 — occupied. No moves.
	e._refresh_result()
	_ok("no legal moves", _count(e) == 0)
	_ok("game over blocked", e.game_over())
	_ok("no-moves result", e.result == CheckersEngine.Result.NO_MOVES)
	_ok("white wins blocked", e.result_side == CheckersTypes.WHITE)


func _test_illegal_rejected() -> void:
	print("illegal")
	var e := _e()
	_ok("onto own", e.play(CheckersTypes.parse_square("a7"), CheckersTypes.parse_square("b6")) == null)
	_ok("light square", e.play(CheckersTypes.parse_square("b6"), CheckersTypes.parse_square("b5")) == null)
	_ok("empty origin", e.play(CheckersTypes.parse_square("a4"), CheckersTypes.parse_square("b5")) == null)
	_ok("wrong side", e.play(CheckersTypes.parse_square("c3"), CheckersTypes.parse_square("d4")) == null)
	_ok("off board", e.find_move(CheckersTypes.parse_square("h6"), CheckersTypes.parse_square("i5")) == null)


func _test_undo_redo() -> void:
	print("undo redo")
	var e := _e()
	var fen0 := e.to_fen()
	e.play(CheckersTypes.parse_square("b6"), CheckersTypes.parse_square("c5"))
	e.play(CheckersTypes.parse_square("c3"), CheckersTypes.parse_square("d4"))
	_ok("two hops stored", e.history.size() == 2)
	e.undo_turn()
	_ok("undo one turn", e.side_to_move == CheckersTypes.WHITE)
	e.undo_turn()
	_ok("back to start side", e.side_to_move == CheckersTypes.BLACK)
	_ok("fen restored", e.to_fen().split(" ")[0] == fen0.split(" ")[0])
	e.redo_turn()
	_ok("redo", e.piece_at(CheckersTypes.parse_square("c5")) != 0)
	var multi := _empty(CheckersTypes.BLACK)
	_place(multi, "c5", CheckersTypes.MAN, CheckersTypes.BLACK)
	_place(multi, "d4", CheckersTypes.MAN, CheckersTypes.WHITE)
	_place(multi, "f2", CheckersTypes.MAN, CheckersTypes.WHITE)
	multi.play(CheckersTypes.parse_square("c5"), CheckersTypes.parse_square("e3"))
	multi.play(CheckersTypes.parse_square("e3"), CheckersTypes.parse_square("g1"))
	multi.undo_turn()
	_ok("undo multi restores both", multi.piece_at(CheckersTypes.parse_square("c5")) != 0)
	_ok("whites restored", multi.piece_at(CheckersTypes.parse_square("d4")) != 0 and multi.piece_at(CheckersTypes.parse_square("f2")) != 0)
	_ok("black to move after undo multi", multi.side_to_move == CheckersTypes.BLACK)


func _test_fen_roundtrip() -> void:
	print("fen")
	var e := _e()
	e.play(CheckersTypes.parse_square("b6"), CheckersTypes.parse_square("c5"))
	var fen := e.to_fen()
	var e2 := _e()
	_ok("parse", e2.from_fen(fen))
	_ok("roundtrip board", e2.to_fen().split(" ")[0] == fen.split(" ")[0])
	_ok("roundtrip side", e2.side_to_move == e.side_to_move)
	var mid := _empty(CheckersTypes.BLACK)
	_place(mid, "c5", CheckersTypes.MAN, CheckersTypes.BLACK)
	_place(mid, "d4", CheckersTypes.MAN, CheckersTypes.WHITE)
	_place(mid, "f2", CheckersTypes.MAN, CheckersTypes.WHITE)
	mid.play(CheckersTypes.parse_square("c5"), CheckersTypes.parse_square("e3"))
	var f2 := mid.to_fen()
	var e3 := _e()
	e3.from_fen(f2)
	_ok("continue square in fen", e3.must_continue_sq == CheckersTypes.parse_square("e3"), f2)
	_ok("continue jumps", _has(e3, "e3g1"))


func _test_black_moves_first() -> void:
	print("english first move")
	var e := _e()
	_ok("official black first", e.side_to_move == CheckersTypes.BLACK)
	_ok("white pieces on ranks 1-3", CheckersTypes.rank_of(CheckersTypes.parse_square("a1")) == 0)
	_ok("a1 white man", CheckersTypes.pcolor(e.piece_at(CheckersTypes.parse_square("a1"))) == CheckersTypes.WHITE)


func _test_perft_start() -> void:
	print("perft")
	var e := _e()
	_ok("perft 1 = 7", e.perft(1) == 7, str(e.perft(1)))
	var p2 := e.perft(2)
	_ok("perft 2 = 49", p2 == 49, str(p2))
	# Depth 3 is 7*7*7 if no captures open; captures appear after some 2-move sequences.
	var p3 := e.perft(3)
	_ok("perft 3 > 200", p3 > 200, str(p3))
