extends "res://tests/test_base.gd"

## English/American rules and the general engine API (ported from the v1 suite
## to full-turn moves, plus new coverage).


func run_all() -> bool:
	suite_name = "english"
	_test_start_position()
	_test_dark_squares_only()
	_test_man_movement()
	_test_blocked_pieces()
	_test_captures()
	_test_forced_capture()
	_test_multi_jump()
	_test_branching_prefix()
	_test_promotion()
	_test_promotion_ends_jump()
	_test_king_moves()
	_test_king_captures()
	_test_king_loop()
	_test_win_no_pieces()
	_test_win_no_moves()
	_test_illegal_rejected()
	_test_undo_redo()
	_test_undo_redo_multi()
	_test_black_moves_first()
	_test_perft_start()
	_test_draw_move_rule()
	_test_draw_repetition()
	_test_movable_squares()
	_test_results_and_tokens()
	_test_clone_and_cache()
	_test_hash_incremental()
	_test_generation_speed()
	return failed == 0


func _e() -> CheckersEngine:
	return CheckersEngine.new("english")


func _test_start_position() -> void:
	section("start position")
	var e := _e()
	eq("start fen", e.to_fen(), "B:W21,22,23,24,25,26,27,28,29,30,31,32:B1,2,3,4,5,6,7,8,9,10,11,12")
	eq("start_fen stored", e.start_fen, CheckersRules.start_fen("english"))
	eq("12 white", e.piece_count(CheckersTypes.WHITE), 12)
	eq("12 black", e.piece_count(CheckersTypes.BLACK), 12)
	eq("no kings", e.king_count(CheckersTypes.WHITE) + e.king_count(CheckersTypes.BLACK), 0)
	eq("7 legal at start", count(e), 7)
	eq("black to move", e.side_to_move, CheckersTypes.BLACK)
	ok("not over", not e.game_over())
	ok("no forced capture at start", not e.must_capture())
	eq("variant", e.variant, "english")
	eq("halfmove 0", e.halfmove, 0)
	eq("fullmove 1", e.fullmove, 1)


func _test_dark_squares_only() -> void:
	section("dark squares")
	var e := _e()
	var all_dark := true
	for s in 64:
		if e.piece_at(s) != 0 and not CheckersTypes.is_dark(s):
			all_dark = false
	ok("every piece on a dark square", all_dark)
	ok("a1 is dark", CheckersTypes.is_dark(sqa("a1")))
	ok("b1 is light", not CheckersTypes.is_dark(sqa("b1")))
	ok("b1 not occupied", e.piece_at(sqa("b1")) == 0)
	ok("piece_at out of range is empty", e.piece_at(-1) == 0 and e.piece_at(64) == 0)


func _test_man_movement() -> void:
	section("man movement")
	var e := _e()
	ok("b6a5", has(e, "b6a5"))
	ok("b6c5", has(e, "b6c5"))
	ok("h6g5", has(e, "h6g5"))
	ok("no backward black", not has(e, "b6a7") and not has(e, "b6c7"))
	ok("no sideways", not has(e, "b6b5"))
	ok("no two-step quiet", not has(e, "b6d4"))
	ok("play b6c5", play(e, "b6c5") != null)
	eq("white to move after quiet", e.side_to_move, CheckersTypes.WHITE)
	ok("white man forward c3d4", has(e, "c3d4"))
	ok("white man forward c3b4", has(e, "c3b4"))
	ok("white no backward", not has(e, "c3b2") and not has(e, "c3d2"))
	var lonely := pos("english", "W:Wc5:Bh8")
	eq("lonely white 2 quiets", count_from(lonely, "c5"), 2)
	ok("c5d6", has(lonely, "c5d6"))
	ok("c5b6", has(lonely, "c5b6"))
	ok("c5 no back", not has(lonely, "c5b4") and not has(lonely, "c5d4"))
	var m := lonely.find_uci("c5d6")
	ok("quiet move shape", m != null and m.path.size() == 2 and not m.is_capture() and m.capture_count() == 0)
	ok("quiet move fields", m != null and m.piece == CheckersTypes.MAN and m.color == CheckersTypes.WHITE and not m.promotes and m.promote_index == -1)
	ok("from/to helpers", m != null and m.from_sq() == sqa("c5") and m.to_sq() == sqa("d6"))


func _test_blocked_pieces() -> void:
	section("blocked pieces")
	var e := pos("english", "W:Wc3,b4,d4:Bh8")
	eq("blocked white man 0", count_from(e, "c3"), 0)
	var e2 := pos("english", "B:Wc5,e5:Bd6")
	eq("blocked-by-enemy is jump", count_from(e2, "d6"), 2)
	ok("d6b4", has(e2, "d6b4"))
	ok("d6f4", has(e2, "d6f4"))
	var e3 := pos("english", "W:Wa1,b2:Bh8")
	eq("corner man blocked", count_from(e3, "a1"), 0)


func _test_captures() -> void:
	section("captures")
	var e := pos("english", "B:Wd4,a1:Bc5")
	var m := play(e, "c5e3")
	ok("capture played", m != null and m.is_capture())
	ok("capture fields", m != null and m.captures == p("d4") and m.captured_pieces == PackedInt32Array([CheckersTypes.W_MAN]))
	eq("landed e3", CheckersTypes.ptype(e.piece_at(sqa("e3"))), CheckersTypes.MAN)
	eq("captured removed", e.piece_at(sqa("d4")), 0)
	eq("origin empty", e.piece_at(sqa("c5")), 0)
	eq("side switched", e.side_to_move, CheckersTypes.WHITE)
	var no := pos("english", "B:Wa1:Bc5,d4")
	ok("cannot jump own", not has(no, "c5e3"))
	var back := pos("english", "B:Wd6,a1:Bc5")
	ok("man cannot capture backward (english)", not has(back, "c5e7"))
	ok("quiet moves instead", has(back, "c5b4") and has(back, "c5d4"))


func _test_forced_capture() -> void:
	section("forced capture")
	var e := pos("english", "B:Wd4,h2:Bc5,a5")
	eq("only the jump is legal", count(e), 1)
	ok("jump c5e3", has(e, "c5e3"))
	ok("must_capture", e.must_capture())
	ok("quiet a5b4 forbidden", not has(e, "a5b4"))
	ok("quiet c5b4 forbidden", not has(e, "c5b4"))
	ok("play quiet rejected", e.play_path(p("a5", "b4")) == null)
	eq("movable squares = capturer", e.movable_squares(), p("c5"))


func _test_multi_jump() -> void:
	section("multi-jump (one full turn)")
	var e := pos("english", "B:Wd4,f2,a1:Bc5")
	eq("one legal move", count(e), 1)
	eq("next landing after origin", e.next_landings(p("c5")), p("e3"))
	eq("next landing after first hop", e.next_landings(p("c5", "e3")), p("g1"))
	eq("complete path has no further landings", e.next_landings(p("c5", "e3", "g1")).size(), 0)
	eq("candidates for origin", e.candidates_for_prefix(p("c5")).size(), 1)
	var mv := e.play_path(p("c5", "e3", "g1"))
	ok("full sequence played", mv != null and mv.capture_count() == 2)
	ok("captures in order", mv != null and mv.captures == p("d4", "f2"))
	ok("promoted on last rank", CheckersTypes.ptype(e.piece_at(sqa("g1"))) == CheckersTypes.KING)
	ok("promote flags", mv != null and mv.promotes and mv.promote_index == 2)
	ok("both whites gone", e.piece_at(sqa("d4")) == 0 and e.piece_at(sqa("f2")) == 0)
	eq("white to move", e.side_to_move, CheckersTypes.WHITE)
	eq("one history entry per turn", e.history.size(), 1)
	eq("uci is full path", mv.to_uci() if mv else "", "c5e3g1")
	eq("english notation numeric", mv.notation if mv else "", "14x23x32")
	ok("numbered notation", e.numbered_notation() == "1. 14x23x32", e.numbered_notation())
	var partial := pos("english", "B:Wd4,f2,a1:Bc5")
	ok("partial path is not a move", partial.play_path(p("c5", "e3")) == null)
	ok("find_uci abbreviated capture", partial.find_uci("14x32") != null)
	ok("find_uci dashed algebraic", partial.find_uci("c5-e3-g1") != null)
	ok("find_uci x algebraic", partial.find_uci("c5xe3xg1") != null)
	ok("find_uci numeric full", partial.find_uci("14x23x32") != null)


func _test_branching_prefix() -> void:
	section("branching multi-jump input")
	var e := pos("english", "B:Wd6,b4,d4,f2:Be7")
	eq("two sequences", ucis(e), PackedStringArray(["e7c5a3", "e7c5e3g1"]))
	eq("origin candidates", e.candidates_for_prefix(p("e7")).size(), 2)
	eq("single first landing", e.next_landings(p("e7")), p("c5"))
	eq("branch at c5", sorted_ints(e.next_landings(p("e7", "c5"))), sorted_ints(p("a3", "e3")))
	eq("one candidate via e3", e.candidates_for_prefix(p("e7", "c5", "e3")).size(), 1)
	eq("then g1", e.next_landings(p("e7", "c5", "e3")), p("g1"))
	ok("a3 branch complete", e.find_path(p("e7", "c5", "a3")) != null and e.next_landings(p("e7", "c5", "a3")).is_empty())
	eq("captured square is not a landing", e.candidates_for_prefix(p("e7", "d6")).size(), 0)
	eq("empty prefix = all", e.candidates_for_prefix(PackedInt32Array()).size(), 2)
	var long := e.find_path(p("e7", "c5", "e3", "g1"))
	ok("long branch crowns at end", long != null and long.promotes and long.promote_index == 3 and long.capture_count() == 3)
	eq("long notation", long.notation if long else "", "7x14x23x32")
	eq("short notation", e.find_path(p("e7", "c5", "a3")).notation, "7x14x21")
	ok("find_path rejects unknown", e.find_path(p("e7", "c5")) == null)


func _test_promotion() -> void:
	section("promotion")
	var e := pos("english", "W:Wc7:Bh2")
	var m := play(e, "c7b8")
	ok("promo move", m != null and m.promotes and m.promote_index == 1)
	eq("now king", CheckersTypes.ptype(e.piece_at(sqa("b8"))), CheckersTypes.KING)
	eq("white color kept", CheckersTypes.pcolor(e.piece_at(sqa("b8"))), CheckersTypes.WHITE)
	var b := pos("english", "B:Wa7:Bd2")
	var mb := play(b, "d2c1")
	ok("black promo", mb != null and mb.promotes)
	eq("black king", CheckersTypes.ptype(b.piece_at(sqa("c1"))), CheckersTypes.KING)
	eq("king count", b.king_count(CheckersTypes.BLACK), 1)


func _test_promotion_ends_jump() -> void:
	section("crowning ends the move (english)")
	var e := pos("english", "W:Wf6:Be7,c7")
	eq("only the crowning jump", ucis(e), PackedStringArray(["f6d8"]))
	var m := play(e, "f6d8")
	ok("crowning jump", m != null and m.promotes and m.is_capture())
	eq("is king", CheckersTypes.ptype(e.piece_at(sqa("d8"))), CheckersTypes.KING)
	eq("black to move", e.side_to_move, CheckersTypes.BLACK)
	ok("c7 still there", e.piece_at(sqa("c7")) != 0)


func _test_king_moves() -> void:
	section("king moves")
	var e := pos("english", "W:WKd4:Bh8")
	eq("king 4 quiets", count_from(e, "d4"), 4)
	ok("d4e5 d4c5 d4e3 d4c3", has(e, "d4e5") and has(e, "d4c5") and has(e, "d4e3") and has(e, "d4c3"))
	ok("king not flying", not has(e, "d4f6") and not has(e, "d4a1"))
	var e2 := pos("english", "W:WKd4,e5:Bh8")
	eq("king blocked one way", count_from(e2, "d4"), 3)
	var km := e.find_uci("d4e5")
	ok("king move fields", km != null and km.piece == CheckersTypes.KING and not km.promotes)


func _test_king_captures() -> void:
	section("king captures")
	var e := pos("english", "W:WKd4:Be5,c3")
	eq("forced king jumps", count(e), 2)
	ok("d4f6 and d4b2", has(e, "d4f6") and has(e, "d4b2"))
	ok("no quiet while jump", not has(e, "d4c5"))
	var m := play(e, "d4f6")
	ok("king captured", m != null and e.piece_at(sqa("e5")) == 0)
	eq("king on f6", CheckersTypes.ptype(e.piece_at(sqa("f6"))), CheckersTypes.KING)
	var back := pos("english", "W:WKd4:Bc5")
	ok("english king captures in any direction", has(back, "d4b6"))


func _test_king_loop() -> void:
	section("king may finish on its own origin")
	var e := pos("english", "W:WKc1:Bd2,d4,b4,b2")
	var loops := 0
	for m in e.generate_legal_moves():
		if m.from_sq() == m.to_sq() and m.capture_count() == 4:
			loops += 1
	eq("two loop directions", loops, 2)
	var m := play(e, "c1e3c5a3c1")
	ok("loop applied", m != null)
	eq("all four captured", e.piece_count(CheckersTypes.BLACK), 0)
	ok("king back on c1", e.piece_at(sqa("c1")) == CheckersTypes.W_KING)
	e.undo()
	eq("undo loop restores 4", e.piece_count(CheckersTypes.BLACK), 4)
	ok("undo loop king on c1", e.piece_at(sqa("c1")) == CheckersTypes.W_KING)


func _test_win_no_pieces() -> void:
	section("win: no pieces")
	var e := pos("english", "W:Wc3:Bd4")
	play(e, "c3e5")
	eq("black has 0", e.piece_count(CheckersTypes.BLACK), 0)
	ok("game over", e.game_over())
	eq("no pieces result", e.result, CheckersEngine.Result.NO_PIECES)
	eq("white wins", e.result_side, CheckersTypes.WHITE)
	eq("reason", e.result_reason(), "No pieces")
	eq("text", e.result_text(), "White wins — Black has no pieces")
	ok("no moves after game over", play(e, "e5f6") == null)


func _test_win_no_moves() -> void:
	section("win: no moves")
	var e := pos("english", "B:WKb2,Kc3:Ba1")
	eq("no legal moves", count(e), 0)
	ok("game over blocked", e.game_over())
	eq("no-moves result", e.result, CheckersEngine.Result.NO_MOVES)
	eq("white wins blocked", e.result_side, CheckersTypes.WHITE)
	eq("text", e.result_text(), "White wins — Black has no moves")
	eq("token", e.result_token(), "1-0")


func _test_illegal_rejected() -> void:
	section("illegal moves")
	var e := _e()
	ok("onto own", e.play_path(p("a7", "b6")) == null)
	ok("light square", e.play_path(p("b6", "b5")) == null)
	ok("empty origin", e.play_path(p("a4", "b5")) == null)
	ok("wrong side", e.play_path(p("c3", "d4")) == null)
	ok("off board", e.find_uci("h6i5") == null)
	ok("garbage", e.find_uci("zz") == null and e.find_uci("") == null and e.find_uci("99-100") == null)
	ok("apply null", e.apply_move(null) == null)
	var foreign := CheckersMove.new()
	foreign.path = p("b6", "d4")
	ok("apply foreign illegal move", e.apply_move(foreign) == null)
	var legal_copy := CheckersMove.new()
	legal_copy.path = p("b6", "c5")
	var applied := e.apply_move(legal_copy)
	ok("apply constructed legal path", applied != null and applied.notation == "9-14")
	eq("history untouched on failures", e.history.size(), 1)


func _test_undo_redo() -> void:
	section("undo / redo")
	var e := _e()
	var fen0 := e.to_fen()
	var key0 := e.hash_key()
	play(e, "b6c5")
	play(e, "c3d4")
	eq("two turns stored", e.history.size(), 2)
	ok("can undo", e.can_undo())
	ok("undo returns move", e.undo() != null)
	eq("undo one turn", e.side_to_move, CheckersTypes.WHITE)
	e.undo()
	eq("back to start side", e.side_to_move, CheckersTypes.BLACK)
	eq("fen restored", e.to_fen(), fen0)
	eq("hash restored", e.hash_key(), key0)
	ok("undo on empty history", e.undo() == null)
	ok("can redo", e.can_redo())
	var r := e.redo()
	ok("redo", r != null and e.piece_at(sqa("c5")) != 0)
	eq("redo notation", r.notation if r else "", "9-14")
	eq("redo stack shrinks", e.redo_stack.size(), 1)
	play(e, "c3b4")
	eq("new move clears redo", e.redo_stack.size(), 0)
	ok("cannot redo", not e.can_redo() and e.redo() == null)


func _test_undo_redo_multi() -> void:
	section("undo / redo multi-jump turn")
	var multi := pos("english", "B:Wd4,f2,h2:Bc5")
	var fen0 := multi.to_fen()
	play(multi, "c5e3g1")
	multi.undo()
	ok("undo multi restores origin", multi.piece_at(sqa("c5")) == CheckersTypes.B_MAN)
	ok("whites restored", multi.piece_at(sqa("d4")) == CheckersTypes.W_MAN and multi.piece_at(sqa("f2")) == CheckersTypes.W_MAN)
	eq("no crowned piece left", multi.piece_at(sqa("g1")), 0)
	eq("black to move after undo multi", multi.side_to_move, CheckersTypes.BLACK)
	eq("fen identical", multi.to_fen(), fen0)
	var r := multi.redo()
	ok("redo multi", r != null and r.capture_count() == 2 and multi.piece_at(sqa("g1")) == CheckersTypes.B_KING)
	# Undo is blocked by resignation / timeout like v1.
	var e := _e()
	play(e, "b6c5")
	e.resign(CheckersTypes.WHITE)
	ok("no undo after resignation", not e.can_undo())
	var t := _e()
	play(t, "b6c5")
	t.flag_timeout(CheckersTypes.BLACK)
	ok("no undo after timeout", not t.can_undo())
	var d := _e()
	play(d, "b6c5")
	d.agree_draw()
	ok("undo allowed after agreed draw", d.can_undo())
	ok("no redo while over", not d.can_redo())


func _test_black_moves_first() -> void:
	section("english first move")
	eq("rules: black first", CheckersRules.first_to_move("english"), CheckersTypes.BLACK)
	eq("engine black first", _e().side_to_move, CheckersTypes.BLACK)
	eq("a1 white man", _e().piece_at(sqa("a1")), CheckersTypes.W_MAN)
	eq("h8 black man", _e().piece_at(sqa("h8")), CheckersTypes.B_MAN)


func _test_perft_start() -> void:
	section("perft (full turns)")
	var e := _e()
	var want := [1, 7, 49, 302, 1469, 7361, 36768]
	for d in range(1, 7):
		eq("perft %d" % d, e.perft(d), want[d])
	eq("perft leaves position intact", e.to_fen(), CheckersRules.start_fen("english"))
	eq("perft 0", e.perft(0), 1)


func _test_draw_move_rule() -> void:
	section("move-rule draw (english 80 plies)")
	var e := pos("english", "W:WKa1:BKh8:H79")
	eq("halfmove from FEN", e.halfmove, 79)
	play(e, "a1b2")
	eq("draw after 80 king plies", e.result, CheckersEngine.Result.DRAW_MOVE_RULE)
	ok("draw is game over", e.game_over())
	eq("no winner", e.result_side, -1)
	eq("reason", e.result_reason(), "Move rule")
	eq("token", e.result_token(), "1/2-1/2")
	var m := pos("english", "W:Wc3,Ka1:BKh8:H79")
	play(m, "c3d4")
	eq("man move resets counter", m.halfmove, 0)
	ok("man move avoids the draw", not m.game_over())
	var c := pos("english", "W:WKc3:Bd4,Kh8:H79")
	play(c, "c3e5")
	eq("capture resets counter", c.halfmove, 0)
	var k := pos("english", "W:WKa1:BKh8:H10")
	play(k, "a1b2")
	eq("king move increments", k.halfmove, 11)
	k.undo()
	eq("undo restores counter", k.halfmove, 10)


func _test_draw_repetition() -> void:
	section("threefold repetition")
	var e := pos("english", "W:WKc3:BKg7")
	eq("start counted once", e.repetition_count(), 1)
	var cycle := ["c3d4", "g7f6", "d4c3", "f6g7", "c3d4", "g7f6", "d4c3", "f6g7"]
	var played := 0
	for u in cycle:
		if play(e, u) == null:
			break
		played += 1
		if e.game_over():
			break
	eq("played all 8", played, 8)
	eq("threefold draw", e.result, CheckersEngine.Result.DRAW_REPETITION)
	eq("repetition count 3", e.repetition_count(), 3)
	eq("reason", e.result_reason(), "Threefold repetition")
	e.undo()
	ok("undo clears repetition draw", not e.game_over())
	eq("count back to 2", e.repetition_count(), 2)


func _test_movable_squares() -> void:
	section("movable squares / legal_from")
	var e := _e()
	eq("four black men can move at start", e.movable_squares().size(), 4)
	eq("b6 has two moves", e.legal_from(sqa("b6")).size(), 2)
	eq("a7 has none", e.legal_from(sqa("a7")).size(), 0)


func _test_results_and_tokens() -> void:
	section("results and PDN tokens")
	var e := _e()
	eq("ongoing token", e.result_token(), "*")
	eq("ongoing text", e.result_text(), "Black to move")
	eq("ongoing reason", e.result_reason(), "")
	e.resign(CheckersTypes.BLACK)
	eq("black resigns -> 1-0", e.result_token(), "1-0")
	eq("resign text", e.result_text(), "Black resigns — White wins")
	eq("resign reason", e.result_reason(), "Resignation")
	var w := _e()
	w.resign(CheckersTypes.WHITE)
	eq("white resigns -> 0-1", w.result_token(), "0-1")
	var t := _e()
	t.flag_timeout(CheckersTypes.WHITE)
	eq("timeout token", t.result_token(), "0-1")
	eq("timeout reason", t.result_reason(), "Time forfeit")
	ok("timeout text", t.result_text().begins_with("Black wins on time"), t.result_text())
	var d := _e()
	d.agree_draw()
	eq("agreed token", d.result_token(), "1/2-1/2")
	eq("agreed reason", d.result_reason(), "Agreement")
	ok("apply refused when over", play(d, "b6c5") == null)


func _test_clone_and_cache() -> void:
	section("clone and cache")
	var e := _e()
	play(e, "b6c5")
	var c := e.clone()
	eq("clone fen", c.to_fen(), e.to_fen())
	eq("clone history", c.history.size(), 1)
	eq("clone hash", c.hash_key(), e.hash_key())
	play(c, "c3d4")
	eq("clone independent", e.history.size(), 1)
	var a := e.generate_legal_moves()
	a.clear()
	ok("returned array is a copy", e.generate_legal_moves().size() > 0)
	c.undo()
	eq("clone undo matches", c.to_fen(), e.to_fen())


func _test_hash_incremental() -> void:
	section("incremental zobrist")
	var e := _e()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var good := true
	for i in 60:
		var ms := e.generate_legal_moves()
		if ms.is_empty() or e.game_over():
			break
		e.apply_move(ms[rng.randi_range(0, ms.size() - 1)])
		var fresh := CheckersEngine.new("english")
		fresh.from_fen(e.to_fen())
		if fresh.hash_key() != e.hash_key():
			good = false
	ok("incremental hash equals recomputed", good)
	var sq := pos("english", "W:Wc3:Bf6")
	var sw := pos("english", "B:Wc3:Bf6")
	ok("side to move changes hash", sq.hash_key() != sw.hash_key())


func _test_generation_speed() -> void:
	section("UI generation speed")
	var e := _e()
	for u in ["b6a5", "c3d4", "f6g5", "b2c3", "g7f6", "d2e3"]:
		play(e, u)
	var t0 := Time.get_ticks_usec()
	for i in 50:
		e._cache_ok = false
		e.generate_legal_moves()
	var per := (Time.get_ticks_usec() - t0) / 50.0
	ok("generate_legal_moves under 2 ms (%.0f us)" % per, per < 2000.0)
