extends "res://tests/test_base.gd"

## Square numbering, FEN (PDN + legacy), move text parsing, PDN export/import,
## numbered notation and v1 legacy hop replay.


func run_all() -> bool:
	suite_name = "notation"
	_test_square_numbering()
	_test_pdn_fen()
	_test_legacy_fen()
	_test_fen_failure_keeps_position()
	_test_move_text_parsing()
	_test_numbered_notation()
	_test_legacy_hops()
	_test_pdn_roundtrip()
	_test_pdn_import_text()
	_test_pdn_import_errors()
	return failed == 0


func _test_square_numbering() -> void:
	section("PDN square numbers")
	var anchors := {1: "b8", 2: "d8", 3: "f8", 4: "h8", 5: "a7", 6: "c7", 7: "e7", 8: "g7", 9: "b6", 12: "h6", 13: "a5", 16: "g5", 17: "b4", 20: "h4", 21: "a3", 24: "g3", 25: "b2", 28: "h2", 29: "a1", 30: "c1", 31: "e1", 32: "g1"}
	for n in anchors.keys():
		eq("%d = %s" % [n, anchors[n]], CheckersTypes.algebraic(CheckersTypes.square_from_number(n)), anchors[n])
	var seen := {}
	var roundtrip := true
	var all_dark := true
	for n in range(1, 33):
		var s := CheckersTypes.square_from_number(n)
		if CheckersTypes.square_number(s) != n:
			roundtrip = false
		if not CheckersTypes.is_dark(s):
			all_dark = false
		seen[s] = true
	ok("number -> square -> number for all 32", roundtrip)
	ok("all numbered squares are dark", all_dark)
	eq("32 distinct squares", seen.size(), 32)
	var back := true
	var light_ok := true
	for s in 64:
		var n := CheckersTypes.square_number(s)
		if CheckersTypes.is_dark(s):
			if n < 1 or n > 32 or CheckersTypes.square_from_number(n) != s:
				back = false
		elif n != -1:
			light_ok = false
	ok("square -> number -> square for all dark", back)
	ok("light squares are -1", light_ok)
	eq("out of range", [CheckersTypes.square_from_number(0), CheckersTypes.square_from_number(33), CheckersTypes.square_number(-1), CheckersTypes.square_number(64)], [-1, -1, -1, -1])
	eq("side names", [CheckersTypes.side_name(CheckersTypes.WHITE), CheckersTypes.side_name(CheckersTypes.BLACK)], ["White", "Black"])


func _test_pdn_fen() -> void:
	section("PDN FEN")
	var e := CheckersEngine.new("english")
	play(e, "b6c5")
	var fen := e.to_fen()
	eq("fen after 9-14", fen, "W:W21,22,23,24,25,26,27,28,29,30,31,32:B1,2,3,4,5,6,7,8,10,11,12,14")
	var e2 := CheckersEngine.new("english")
	ok("parse", e2.from_fen(fen))
	eq("roundtrip", e2.to_fen(), fen)
	eq("roundtrip side", e2.side_to_move, e.side_to_move)
	var k := pos("english", "B:WK5,21:BK30,1")
	eq("kings prefixed", k.to_fen(), "B:WK5,21:B1,K30")
	eq("white king on a7", k.piece_at(sqa("a7")), CheckersTypes.W_KING)
	eq("black king on c1", k.piece_at(sqa("c1")), CheckersTypes.B_KING)
	var r := pos("english", "W:W21-32:B1-12")
	eq("ranges accepted", r.to_fen(), "W:W21,22,23,24,25,26,27,28,29,30,31,32:B1,2,3,4,5,6,7,8,9,10,11,12")
	var a := pos("russian", "W:Wa1,c3,Ke5:Bh8,Kb8")
	eq("algebraic squares accepted", a.to_fen(), "W:WK15,22,29:BK1,4")
	var hf := pos("english", "W:WKa1:BKh8:H12:F30")
	eq("H/F counters", [hf.halfmove, hf.fullmove], [12, 30])
	ok("start_fen keeps counters", hf.start_fen.ends_with(":H12:F30"), hf.start_fen)
	var dotted := pos("english", "B:W21:B1.")
	eq("trailing dot tolerated", dotted.to_fen(), "B:W21:B1")
	var empty_side := pos("english", "W:W21:B")
	eq("empty piece list", empty_side.piece_count(CheckersTypes.BLACK), 0)
	eq("white to move with moves: not over", empty_side.result, CheckersEngine.Result.NONE)


func _test_legacy_fen() -> void:
	section("legacy v1 FEN")
	var e := CheckersEngine.new("english")
	ok("legacy start parses", e.from_fen(CheckersTypes.START_FEN))
	eq("legacy start == PDN start", e.to_fen(), CheckersRules.start_fen("english"))
	eq("legacy side", e.side_to_move, CheckersTypes.BLACK)
	var mid := CheckersEngine.new("english")
	ok("legacy with kings and counters", mid.from_fen("8/8/8/2b5/3w4/8/5W2/8 b e3 7 12"))
	eq("pieces", [mid.piece_at(sqa("c5")), mid.piece_at(sqa("d4")), mid.piece_at(sqa("f2"))], [CheckersTypes.B_MAN, CheckersTypes.W_MAN, CheckersTypes.W_KING])
	eq("counters", [mid.halfmove, mid.fullmove], [7, 12])
	eq("continue field ignored, full move generated", ucis(mid), PackedStringArray(["c5e3g1"]))
	eq("legacy dump", CheckersFen.dump_legacy(CheckersEngine.new("english").squares, CheckersTypes.BLACK, 0, 1), CheckersTypes.START_FEN)


func _test_fen_failure_keeps_position() -> void:
	section("bad FEN leaves the position intact")
	var e := CheckersEngine.new("english")
	play(e, "b6c5")
	var before := e.to_fen()
	var hist := e.history.size()
	for bad in ["", "X:W1:B2", "W:W33:B1", "W:W1,1:B2", "W:Wb1:B2", "W:Q1:B2", "1b1b/8 b", "9/8/8/8/8/8/8/8 w", "W:W1-40:B2", "W:W1:W2"]:
		ok("rejects '%s'" % bad, not e.from_fen(bad))
	eq("fen unchanged", e.to_fen(), before)
	eq("history unchanged", e.history.size(), hist)


func _test_move_text_parsing() -> void:
	section("move text parsing")
	var e := CheckersEngine.new("english")
	for t in ["b6c5", "b6-c5", "9-14", " 9-14 ", "9-14!", "B6C5"]:
		var m := e.find_uci(t)
		ok("find_uci '%s'" % t, m != null and m.to_uci() == "b6c5")
	eq("parse squares numeric", CheckersEngine.parse_move_squares("22x15x6"), p("c3", "e5", "c7"))
	eq("parse squares algebraic", CheckersEngine.parse_move_squares("c3:e5:g7"), p("c3", "e5", "g7"))
	eq("parse squares concatenated", CheckersEngine.parse_move_squares("c3e5g7"), p("c3", "e5", "g7"))
	eq("bad text", CheckersEngine.parse_move_squares("c9d4").size(), 0)
	var amb := pos("english", "W:WKc1:Bd2,d4,b4,b2")
	ok("ambiguous loop with same captures resolves", amb.find_uci("30x30") != null)
	var two := pos("english", "B:Wd6,b4,d4,f2:Be7")
	ok("abbreviated resolves unique target", two.find_uci("7x21") != null and two.find_uci("7x21").to_uci() == "e7c5a3")
	ok("to_uci lossless", two.find_uci(two.find_uci("7x32").to_uci()).same_path(p("e7", "c5", "e3", "g1")))


func _test_numbered_notation() -> void:
	section("numbered notation")
	var e := CheckersEngine.new("english")
	for u in ["11-15", "23-19", "8-11", "22-17"]:
		ok("play %s" % u, play(e, u) != null)
	eq("english numbering", e.numbered_notation(), "1. 11-15 23-19 2. 8-11 22-17")
	eq("fullmove after two full moves", e.fullmove, 3)
	var w := pos("english", "W:W21,22:B1,2")
	play(w, "22-18")
	play(w, "1-6")
	eq("white-first english numbering", w.numbered_notation(), "1... 22-18 2. 1-6")
	var f := pos("english", "B:W21,22:B1,2:F17")
	play(f, "1-6")
	play(f, "22-18")
	eq("start move number from FEN", f.numbered_notation(), "17. 1-6 22-18")
	eq("move_number_for_ply", f.move_number_for_ply(2), 18)


func _test_legacy_hops() -> void:
	section("replay v1 hop list")
	var hops := ["b6c5", "c3d4", "a7b6", "b2c3", "c5b4", "a3c5", "c5a7", "f6e5"]
	var e := CheckersEngine.new("english")
	ok("replay succeeds", e.replay_legacy_hops(hops))
	eq("hops grouped into 7 turns", e.history.size(), 7)
	eq("double jump is one turn", e.history[5].to_uci() if e.history.size() > 5 else "", "a3c5a7")
	eq("two pieces taken in that turn", e.history[5].capture_count() if e.history.size() > 5 else -1, 2)
	eq("white to move after f6e5", e.side_to_move, CheckersTypes.WHITE)
	var ref := CheckersEngine.new("english")
	for u in ["b6c5", "c3d4", "a7b6", "b2c3", "c5b4", "a3c5a7", "f6e5"]:
		play(ref, u)
	eq("same position as full-turn replay", e.to_fen(), ref.to_fen())
	var bad := CheckersEngine.new("english")
	play(bad, "b6a5")
	var before := bad.to_fen()
	ok("illegal hop list rejected", not bad.replay_legacy_hops(["b6c5", "c3d4", "c5e3"]))
	eq("engine untouched after failure", bad.to_fen(), before)
	eq("history untouched after failure", bad.history.size(), 1)
	var dangling := CheckersEngine.new("english")
	ok("unfinished multi-jump rejected", not dangling.replay_legacy_hops(["b6c5", "c3d4", "a7b6", "b2c3", "c5b4", "a3c5"]))
	var fresh := CheckersEngine.new("english")
	ok("empty list is fine", fresh.replay_legacy_hops([]) and fresh.history.is_empty())


func _test_pdn_roundtrip() -> void:
	section("PDN export -> import")
	var e := CheckersEngine.new("english")
	for u in ["b6c5", "c3d4", "a7b6", "b2c3", "c5b4", "a3c5a7"]:
		play(e, u)
	var text := CheckersPdn.export_game(e, {"Event": "Test \"quoted\"", "White": "Ann", "Black": "Bob", "Date": "2026.09.23", "Annotator": "Shadow"})
	ok("has GameType 21", text.contains("[GameType \"21\"]"))
	ok("has Result *", text.contains("[Result \"*\"]"))
	ok("no FEN for standard start", not text.contains("[FEN"))
	ok("extra header kept", text.contains("[Annotator \"Shadow\"]"))
	ok("movetext numeric", text.contains("1. 9-14 22-18 2. 5-9 25-22 3. 14-17 21x14x5 *"), text)
	var r := CheckersPdn.import_game(text)
	ok("import ok", bool(r["ok"]), str(r["error"]))
	var ie: CheckersEngine = r["engine"]
	ok("same position", ie != null and ie.to_fen() == e.to_fen())
	ok("same notation", ie != null and ie.numbered_notation() == e.numbered_notation())
	eq("header escaped roundtrip", r["headers"].get("Event", ""), "Test \"quoted\"")
	eq("white header", r["headers"].get("White", ""), "Ann")
	# Russian with a custom start and a finished game.
	var rs := pos("russian", "W:WKa1:Bb2,c5")
	play(rs, "a1d4b6")
	var rtext := CheckersPdn.export_game(rs, {})
	ok("russian GameType 25", rtext.contains("[GameType \"25\"]"))
	ok("russian FEN tag", rtext.contains("[FEN \"W:WK29:B14,25\"]"), rtext)
	ok("russian result 1-0", rtext.contains("[Result \"1-0\"]") and rtext.strip_edges().ends_with("1-0"))
	ok("russian algebraic movetext", rtext.contains("1. a1:d4:b6"))
	var rr := CheckersPdn.import_game(rtext)
	ok("russian import ok", bool(rr["ok"]), str(rr["error"]))
	var re: CheckersEngine = rr["engine"]
	ok("russian variant restored", re != null and re.variant == "russian")
	ok("russian result restored", re != null and re.result == CheckersEngine.Result.NO_PIECES and re.result_token() == "1-0")
	var br := CheckersEngine.new("brazilian")
	play(br, "c3d4")
	ok("brazilian GameType 26", CheckersPdn.export_game(br, {}).contains("[GameType \"26\"]"))
	var bi := CheckersPdn.import_game(CheckersPdn.export_game(br, {}))
	ok("brazilian roundtrip", bool(bi["ok"]) and (bi["engine"] as CheckersEngine).variant == "brazilian" and (bi["engine"] as CheckersEngine).history.size() == 1)
	var dr := pos("english", "W:WKa1:BKh8")
	dr.agree_draw()
	ok("draw token exported", CheckersPdn.export_game(dr, {}).contains("[Result \"1/2-1/2\"]"))


func _test_pdn_import_text() -> void:
	section("PDN import of hand-written text")
	var text := """[Event "Club night"]
[White "W. Player"]
[Black "B. Player"]
[Result "1-0"]

1. 11-15 {the Old Faithful} 23-19 2. 8-11 (2. 9-14 22-17) 22-17 ; comment
3. 4-8 17-13 $1 4. 15-18! 24-20 1-0
"""
	var r := CheckersPdn.import_game(text)
	ok("import ok", bool(r["ok"]), str(r["error"]))
	var e: CheckersEngine = r["engine"]
	eq("english by default", e.variant if e else "", "english")
	eq("eight plies", e.history.size() if e else -1, 8)
	eq("notation", e.numbered_notation() if e else "", "1. 11-15 23-19 2. 8-11 22-17 3. 4-8 17-13 4. 15-18 24-20")
	eq("result header kept", r["headers"].get("Result", ""), "1-0")
	ok("game itself not over", e != null and not e.game_over())
	var glued := CheckersPdn.import_game("[GameType \"21\"]\n1.11-15 23-19 2.8-11 *")
	ok("glued move numbers", bool(glued["ok"]) and (glued["engine"] as CheckersEngine).history.size() == 3, str(glued["error"]))
	var ru := CheckersPdn.import_game("[GameType \"25\"]\n1. c3-d4 f6-e5 2. d4:f6 g7:e5 *")
	ok("russian algebraic import", bool(ru["ok"]) and (ru["engine"] as CheckersEngine).history.size() == 4, str(ru["error"]))


func _test_pdn_import_errors() -> void:
	section("PDN import errors")
	var bad := CheckersPdn.import_game("1. 11-15 11-15 *")
	ok("illegal move reported", not bool(bad["ok"]) and str(bad["error"]).contains("11-15"))
	var gt := CheckersPdn.import_game("[GameType \"20\"]\n1. 32-28 *")
	ok("unsupported GameType", not bool(gt["ok"]) and str(gt["error"]).contains("GameType"))
	var fen := CheckersPdn.import_game("[FEN \"nonsense\"]\n*")
	ok("bad FEN tag", not bool(fen["ok"]))
