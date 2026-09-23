extends "res://tests/test_base.gd"

## Russian and Brazilian rules: flying kings, backward captures, Turkish strike,
## mid-capture crowning, majority capture, move order and draw counters.


func run_all() -> bool:
	suite_name = "variants"
	_test_table()
	_test_first_mover()
	_test_flying_quiet()
	_test_long_range_capture()
	_test_must_land_where_capture_continues()
	_test_direction_change()
	_test_cannot_jump_twice()
	_test_turkish_strike_blocks()
	_test_men_capture_backward()
	_test_russian_mid_capture_crowning()
	_test_brazilian_no_mid_capture_crowning()
	_test_majority_rule()
	_test_crowning_quiet()
	_test_notation()
	_test_draw_counters()
	_test_perft_reference()
	_test_undo_flying_multi()
	return failed == 0


func _test_table() -> void:
	section("variant table")
	var vs := CheckersRules.variants()
	eq("three variants", vs.size(), 3)
	eq("order", [vs[0]["id"], vs[1]["id"], vs[2]["id"]], ["english", "russian", "brazilian"])
	var keys_ok := true
	for v in vs:
		for k in ["id", "name", "blurb", "first"]:
			if not v.has(k):
				keys_ok = false
	ok("rows have id/name/blurb/first", keys_ok)
	eq("english name", CheckersRules.variant_name("english"), "English Draughts")
	eq("russian name", CheckersRules.variant_name("russian"), "Russian Draughts")
	eq("brazilian name", CheckersRules.variant_name("brazilian"), "Brazilian Draughts")
	eq("unknown variant falls back to english", CheckersEngine.new("klingon").variant, "english")
	eq("game types", [CheckersRules.game_type("english"), CheckersRules.game_type("russian"), CheckersRules.game_type("brazilian")], ["21", "25", "26"])
	eq("game type parse", CheckersRules.variant_from_game_type("25,W,8,8,A0,0"), "russian")
	eq("unsupported game type", CheckersRules.variant_from_game_type("20"), "")
	eq("draw plies", [CheckersRules.draw_plies("english"), CheckersRules.draw_plies("russian"), CheckersRules.draw_plies("brazilian")], [80, 30, 50])


func _test_first_mover() -> void:
	section("side to move first")
	eq("russian white first", CheckersRules.first_to_move("russian"), CheckersTypes.WHITE)
	eq("brazilian white first", CheckersRules.first_to_move("brazilian"), CheckersTypes.WHITE)
	var r := CheckersEngine.new("russian")
	eq("russian engine white to move", r.side_to_move, CheckersTypes.WHITE)
	eq("russian 7 moves", count(r), 7)
	ok("russian white opening a3b4", has(r, "a3b4"))
	var b := CheckersEngine.new("brazilian")
	eq("brazilian engine white to move", b.side_to_move, CheckersTypes.WHITE)
	eq("same start squares", b.to_fen(), "W:W21,22,23,24,25,26,27,28,29,30,31,32:B1,2,3,4,5,6,7,8,9,10,11,12")
	var e := CheckersEngine.new("english")
	e.set_variant("russian")
	eq("set_variant resets to white first", e.side_to_move, CheckersTypes.WHITE)
	eq("set_variant variant", e.variant, "russian")


func _test_flying_quiet() -> void:
	section("flying king quiet moves")
	for v in ["russian", "brazilian"]:
		var e := pos(v, "W:WKd4:Bh6")
		eq("%s king d4 has 13 squares" % v, count_from(e, "d4"), 13)
		ok("%s d4a1 and d4h8" % v, has(e, "d4a1") and has(e, "d4h8"))
		var blocked := pos(v, "W:WKd4,f6:Bh6")
		ok("%s own piece blocks the ray" % v, not has(blocked, "d4g7") and has(blocked, "d4e5"))
	var en := pos("english", "W:WKd4:Bh6")
	eq("english king only 4", count_from(en, "d4"), 4)


func _test_long_range_capture() -> void:
	section("long-range capture, several landings")
	for v in ["russian", "brazilian"]:
		var e := pos(v, "W:WKa1:Bd4")
		eq("%s four landing squares" % v, ucis(e), PackedStringArray(["a1e5", "a1f6", "a1g7", "a1h8"]))
		ok("%s capture forced" % v, e.must_capture())
		eq("%s next_landings lists all" % v, sorted_ints(e.next_landings(p("a1"))), sorted_ints(p("e5", "f6", "g7", "h8")))
		var m := play(e, "a1g7")
		ok("%s captured piece removed" % v, m != null and e.piece_at(sqa("d4")) == 0 and e.piece_at(sqa("g7")) == CheckersTypes.W_KING)
	var en := pos("english", "W:WKa1:Bd4")
	ok("english king cannot capture at distance", not en.must_capture())


func _test_must_land_where_capture_continues() -> void:
	section("king must land where the capture continues")
	for v in ["russian", "brazilian"]:
		var e := pos(v, "W:WKa1:Bd4,g5")
		eq("%s only f6 continues" % v, ucis(e), PackedStringArray(["a1f6h4"]))
		var m := e.find_uci("a1f6h4")
		ok("%s two captures" % v, m != null and m.captures == p("d4", "g5"))


func _test_direction_change() -> void:
	section("multi-capture changing direction")
	for v in ["russian", "brazilian"]:
		var e := pos(v, "W:WKa1:Bb2,c5")
		eq("%s NE then NW" % v, ucis(e), PackedStringArray(["a1d4a7", "a1d4b6"]))
		eq("%s landing after origin" % v, e.next_landings(p("a1")), p("d4"))
		eq("%s branch after d4" % v, sorted_ints(e.next_landings(p("a1", "d4"))), sorted_ints(p("b6", "a7")))


func _test_cannot_jump_twice() -> void:
	section("Turkish strike: no piece jumped twice")
	for v in ["russian", "brazilian"]:
		var e := pos(v, "W:WKd4:Bf6")
		eq("%s two single captures" % v, ucis(e), PackedStringArray(["d4g7", "d4h8"]))
		var all_one := true
		for m in e.generate_legal_moves():
			if m.capture_count() != 1:
				all_one = false
		ok("%s never re-jumps f6" % v, all_one)


func _test_turkish_strike_blocks() -> void:
	section("Turkish strike: captured pieces block until the move ends")
	var e := pos("russian", "W:WKc1:Bd2,d4,b4,b2,f4")
	var mx := 0
	for m in e.generate_legal_moves():
		mx = maxi(mx, m.capture_count())
	eq("max four captures (f4 is shielded by captured d2)", mx, 4)
	ok("loop back to c1 exists", has(e, "c1e3c5a3c1"))
	ok("free choice keeps shorter sequences (russian)", has(e, "c1e3g5"))
	var m := play(e, "c1e3c5a3c1")
	ok("all four removed after the move", m != null and e.piece_count(CheckersTypes.BLACK) == 1 and e.piece_at(sqa("f4")) == CheckersTypes.B_MAN)
	var b := pos("brazilian", "W:WKc1:Bd2,d4,b4,b2,f4")
	var all_four := true
	for bm in b.generate_legal_moves():
		if bm.capture_count() != 4:
			all_four = false
	ok("brazilian keeps only maximum sequences", all_four and count(b) == 4)


func _test_men_capture_backward() -> void:
	section("men capture backwards")
	eq("russian man captures back", ucis(pos("russian", "W:Wd4:Bc3")), PackedStringArray(["d4b2"]))
	eq("brazilian man captures back", ucis(pos("brazilian", "W:Wd4:Bc3")), PackedStringArray(["d4b2"]))
	eq("english man does not", ucis(pos("english", "W:Wd4:Bc3")), PackedStringArray(["d4c5", "d4e5"]))
	var bl := pos("russian", "B:Wd6:Be5")
	ok("black man captures back too", has(bl, "e5c7"))
	var q := pos("russian", "W:Wd4:Bh8")
	ok("men still move forward only", not has(q, "d4c3") and not has(q, "d4e3") and has(q, "d4c5"))


func _test_russian_mid_capture_crowning() -> void:
	section("russian: crowned mid-capture, continues as a king")
	var e := pos("russian", "W:Wb6:Bc7,f6")
	eq("continues as flying king", ucis(e), PackedStringArray(["b6d8g5", "b6d8h4"]))
	var m := e.find_uci("b6d8h4")
	ok("promotes at index 1", m != null and m.promotes and m.promote_index == 1 and m.piece == CheckersTypes.MAN)
	play(e, "b6d8h4")
	eq("king on h4", e.piece_at(sqa("h4")), CheckersTypes.W_KING)
	eq("both captured", e.piece_count(CheckersTypes.BLACK), 0)
	var e2 := pos("russian", "W:Wb6:Bc7,e7")
	eq("adjacent piece: king landings f6/g5/h4", ucis(e2), PackedStringArray(["b6d8f6", "b6d8g5", "b6d8h4"]))
	var e3 := pos("russian", "W:Wb6:Bc7,e7")
	play(e3, "b6d8f6")
	eq("russian crowned piece stays king", e3.piece_at(sqa("f6")), CheckersTypes.W_KING)
	e3.undo()
	eq("undo restores the man", e3.piece_at(sqa("b6")), CheckersTypes.W_MAN)


func _test_brazilian_no_mid_capture_crowning() -> void:
	section("brazilian: passing the last row mid-capture does not crown")
	var e := pos("brazilian", "W:Wb6:Bc7,e7")
	eq("continues as a man", ucis(e), PackedStringArray(["b6d8f6"]))
	var m := play(e, "b6d8f6")
	ok("not promoted", m != null and not m.promotes and m.promote_index == -1)
	eq("still a man on f6", e.piece_at(sqa("f6")), CheckersTypes.W_MAN)
	var stop := pos("brazilian", "W:Wb6:Bc7,f6")
	eq("ends on last row -> crowned", ucis(stop), PackedStringArray(["b6d8"]))
	var sm := play(stop, "b6d8")
	ok("crowned when the move ends there", sm != null and sm.promotes and stop.piece_at(sqa("d8")) == CheckersTypes.W_KING)


func _test_majority_rule() -> void:
	section("majority capture")
	eq("brazilian must take two", ucis(pos("brazilian", "W:Wa1,e3:Bb2,f4,f6")), PackedStringArray(["e3g5e7"]))
	eq("russian free choice", ucis(pos("russian", "W:Wa1,e3:Bb2,f4,f6")), PackedStringArray(["a1c3", "e3g5e7"]))
	eq("english free choice", ucis(pos("english", "W:Wa1,e3:Bb2,f4,f6")), PackedStringArray(["a1c3", "e3g5e7"]))
	# Kings and men count equally: two men beat one king.
	var b := pos("brazilian", "W:Wa1,e3:BKb2,f4,f6")
	eq("two men outweigh a king", ucis(b), PackedStringArray(["e3g5e7"]))


func _test_crowning_quiet() -> void:
	section("quiet crowning in flying variants")
	var r := pos("russian", "W:Wc7:Bh2")
	var m := play(r, "c7d8")
	ok("quiet crown", m != null and m.promotes and r.piece_at(sqa("d8")) == CheckersTypes.W_KING)
	var b := pos("brazilian", "B:Wa7:Bf2")
	var mb := play(b, "f2g1")
	ok("black crowns on rank 1", mb != null and b.piece_at(sqa("g1")) == CheckersTypes.B_KING)


func _test_notation() -> void:
	section("variant notation")
	var r := CheckersEngine.new("russian")
	var m := play(r, "c3d4")
	eq("russian quiet notation", m.notation if m else "", "c3-d4")
	var c := pos("russian", "W:WKa1:Bb2,c5")
	var cm := play(c, "a1d4b6")
	eq("russian capture notation", cm.notation if cm else "", "a1:d4:b6")
	ok("find_uci colon form", pos("russian", "W:WKa1:Bb2,c5").find_uci("a1:d4:b6") != null)
	ok("find_uci numeric form works in any variant", pos("russian", "W:WKa1:Bb2,c5").find_uci("29x18x9") != null)
	var b := CheckersEngine.new("brazilian")
	play(b, "c3d4")
	play(b, "f6e5")
	eq("brazilian numbering (white first)", b.numbered_notation(), "1. c3-d4 f6-e5")
	eq("move number for ply", [b.move_number_for_ply(0), b.move_number_for_ply(1), b.move_number_for_ply(2)], [1, 1, 2])
	var bf := pos("russian", "B:Wc3:Bf6")
	play(bf, "f6e5")
	play(bf, "c3d4")
	eq("black-to-move start numbering", bf.numbered_notation(), "1... f6-e5 2. c3-d4")


func _test_draw_counters() -> void:
	section("variant draw counters")
	var r := pos("russian", "W:WKa1:BKh8:H29")
	play(r, "a1b2")
	eq("russian draw at 30 king plies", r.result, CheckersEngine.Result.DRAW_MOVE_RULE)
	ok("russian draw text", r.result_text().contains("15 moves"), r.result_text())
	var r2 := pos("russian", "W:WKa1:BKh8:H28")
	play(r2, "a1b2")
	ok("russian not yet at 29", not r2.game_over())
	var b := pos("brazilian", "W:WKa1:BKh8:H49")
	play(b, "a1b2")
	eq("brazilian draw at 50", b.result, CheckersEngine.Result.DRAW_MOVE_RULE)
	var b2 := pos("brazilian", "W:WKa1,c3:BKh8:H49")
	play(b2, "c3d4")
	ok("brazilian man move resets", not b2.game_over() and b2.halfmove == 0)
	var rep := pos("russian", "W:WKa1:BKh6")
	for u in ["a1b2", "h6g5", "b2a1", "g5h6", "a1b2", "h6g5", "b2a1", "g5h6"]:
		play(rep, u)
	eq("russian threefold", rep.result, CheckersEngine.Result.DRAW_REPETITION)


func _test_perft_reference() -> void:
	section("perft (full turns) vs reference counts")
	var r := CheckersEngine.new("russian")
	eq("russian perft 5", r.perft(5), 7482)
	eq("russian perft 6", r.perft(6), 37986)
	var b := CheckersEngine.new("brazilian")
	eq("brazilian perft 5", b.perft(5), 7473)
	eq("brazilian perft 6", b.perft(6), 37628)


func _test_undo_flying_multi() -> void:
	section("undo flying multi-capture")
	var e := pos("brazilian", "W:WKc1:Bd2,d4,b4,b2,f4")
	var f0 := e.to_fen()
	var k0 := e.hash_key()
	play(e, "c1a3c5e3g5")
	eq("one black left", e.piece_count(CheckersTypes.BLACK), 1)
	e.undo()
	eq("fen restored", e.to_fen(), f0)
	eq("hash restored", e.hash_key(), k0)
	var r := e.redo()
	ok("redo", r != null and r.to_uci() == "c1a3c5e3g5")
