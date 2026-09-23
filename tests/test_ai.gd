extends "res://tests/test_base.gd"

## Synchronous AI tests: level table, legality in every variant, tactics,
## draw awareness, determinism, opening book.

const VARIANTS := ["english", "russian", "brazilian"]


func run_all() -> bool:
	suite_name = "ai"
	CheckersAI.warmup()
	_test_levels_table()
	_test_book()
	_test_levels_all_variants()
	_test_choose_returns_engine_move()
	_test_time_budgets()
	_test_two_for_one_shot()
	_test_forced_win_reporting()
	_test_takes_draw_by_repetition()
	_test_analysis_deterministic()
	_test_job_errors()
	_test_playthrough()
	return failed == 0


func _job(variant: String, level: String, fen: String = "", moves: Array = [], time_ms: int = -1) -> CheckersAI.SearchJob:
	var j := CheckersAI.SearchJob.new()
	j.variant = variant
	j.level = level
	j.start_fen = fen
	j.moves_uci = PackedStringArray(moves)
	j.time_ms = time_ms
	return j


func _legal_on(variant: String, fen: String, moves: Array, uci: String) -> bool:
	var e := CheckersEngine.new(variant)
	if not fen.is_empty():
		e.from_fen(fen)
	for u in moves:
		play(e, u)
	var m := e.find_uci(uci)
	return m != null and m.to_uci() == uci


func _test_levels_table() -> void:
	section("levels")
	var ls := CheckersAI.levels()
	var ids := []
	for l in ls:
		ids.append(l["id"])
		ok("level %s has name and blurb" % l["id"], not str(l.get("name", "")).is_empty() and not str(l.get("blurb", "")).is_empty())
	eq("level ids", ids, ["beginner", "casual", "club", "advanced", "expert", "master"])
	eq("legacy easy", CheckersAI.level_id_from_legacy("easy"), "casual")
	eq("legacy medium", CheckersAI.level_id_from_legacy("medium"), "club")
	eq("legacy hard", CheckersAI.level_id_from_legacy("hard"), "advanced")
	eq("legacy master", CheckersAI.level_id_from_legacy("master"), "master")
	eq("legacy unknown", CheckersAI.level_id_from_legacy("wizard"), "club")
	eq("new ids pass through", CheckersAI.level_id_from_legacy("expert"), "expert")


func _test_book() -> void:
	section("opening book")
	var lines := CheckersBook.lines()
	ok("30-60 book lines (%d)" % lines.size(), lines.size() >= 30 and lines.size() <= 60)
	eq("no bad lines", CheckersBook.bad_lines(), PackedStringArray())
	var all_legal := true
	for line in lines:
		var e := CheckersEngine.new("english")
		for tok in line.split(" ", false):
			var m := e.find_uci(tok)
			if m == null or e.apply_move(m) == null:
				all_legal = false
				print("    illegal book move '%s' in: %s" % [tok, line])
				break
	ok("every book line replays legally", all_legal)
	var file_text := FileAccess.get_file_as_string(CheckersBook.PATH)
	eq("embedded copy matches data file", CheckersBook.parse_lines(CheckersBook.EMBEDDED), CheckersBook.parse_lines(file_text))
	var start := CheckersEngine.new("english")
	ok("book knows the start", CheckersBook.continuations(start).size() >= 5)
	eq("no book for russian", CheckersBook.continuations(CheckersEngine.new("russian")).size(), 0)
	var j := _job("english", "master")
	j.run()
	ok("master opens from book", j.from_book and _legal_on("english", "", [], j.best_uci), j.best_uci)
	var nb := _job("english", "club", "", [], 150)
	nb.use_book = false
	nb.run()
	ok("use_book=false searches", not nb.from_book and nb.depth >= 1 and _legal_on("english", "", [], nb.best_uci))
	var an := _job("english", "analysis", "", [], 150)
	an.run()
	ok("analysis never uses the book", not an.from_book and an.depth >= 1)
	var firsts := {}
	for i in 40:
		var b := _job("english", "casual")
		b.run()
		firsts[b.best_uci] = true
	ok("casual varies its first move (%d distinct)" % firsts.size(), firsts.size() >= 3)


func _test_levels_all_variants() -> void:
	section("every level plays legal moves in every variant")
	for v in VARIANTS:
		for l in CheckersAI.levels():
			var j := _job(v, l["id"], "", ["c3d4", "f6e5"] if v != "english" else ["f6e5", "c3d4"], 200)
			j.use_book = false
			j.run()
			ok("%s %s legal (%s d%d)" % [v, l["id"], j.best_uci, j.depth], j.error.is_empty() and _legal_on(v, "", ["c3d4", "f6e5"] if v != "english" else ["f6e5", "c3d4"], j.best_uci))


func _test_choose_returns_engine_move() -> void:
	section("choose() helper")
	var e := CheckersEngine.new("english")
	var m := CheckersAI.choose(e, "beginner")
	ok("returns a move", m != null)
	var found := false
	for x in e.generate_legal_moves():
		if x == m:
			found = true
	ok("move object comes from generate_legal_moves()", found)
	ok("choose leaves engine untouched", e.history.is_empty() and e.to_fen() == CheckersRules.start_fen("english"))
	var over := pos("english", "W:Wc3:Bd4")
	over.apply_move(over.find_uci("c3e5"))
	ok("null when game over", CheckersAI.choose(over, "club") == null)
	var forced := pos("russian", "W:Wd4:Bc3,h8")
	var fm := CheckersAI.choose(forced, "master")
	ok("single legal move returned at once", fm != null and fm.to_uci() == "d4b2")


func _test_time_budgets() -> void:
	section("time budgets (non-book position)")
	var e := CheckersEngine.new("english")
	for u in ["f6e5", "c3d4", "e5c3", "b2d4"]:
		play(e, u)
	for l in ["beginner", "casual", "club", "advanced", "expert", "master"]:
		var t0 := Time.get_ticks_msec()
		var j := CheckersAI.SearchJob.new()
		j.variant = "english"
		j.moves_uci = PackedStringArray(["f6e5", "c3d4", "e5c3", "b2d4"])
		j.level = l
		j.use_book = false
		j.run()
		var dt := Time.get_ticks_msec() - t0
		var budget: int = int(CheckersAI.profile(l)["time"])
		ok("%s legal: %s d%d %dn %dnps %dms" % [l, j.best_uci, j.depth, j.nodes, j.nps, dt], e.find_uci(j.best_uci) != null)
		ok("%s within budget (%d <= %d + 400)" % [l, dt, budget], dt <= budget + 400)
		ok("%s pv starts with best" % l, j.pv.size() >= 1 and j.pv[0] == j.best_uci)


func _test_two_for_one_shot() -> void:
	section("finds a 2-for-1 shot")
	var fen := "W:We3,d2,c3,c1:Bc5,e5,a7,g7"
	for l in ["club", "advanced", "master"]:
		var j := _job("english", l, fen, [], 600)
		j.run()
		eq("%s plays 23-18 (e3d4)" % l, j.best_uci, "e3d4")
	var a := _job("english", "analysis", fen, [], 1500)
	a.run()
	eq("analysis plays the shot", a.best_uci, "e3d4")
	ok("analysis sees it wins material (score %d)" % a.score, a.score >= 60)
	ok("pv shows the recapture", a.pv.size() >= 3 and a.pv[1] == "c5e3" and a.pv[2] == "d2f4d6", str(a.pv))
	eq("score_white matches (white to move)", a.score_white, a.score)


func _test_forced_win_reporting() -> void:
	section("forced win reporting")
	var j := _job("english", "analysis", "W:Wc3:Bd4", [], 500)
	j.run()
	eq("takes the last piece", j.best_uci, "c3e5")
	eq("win in 1", j.win_in, 1)
	ok("mate score", j.score > 90000)
	var b := _job("russian", "analysis", "B:WKa1,Kc1,Ke1,Kg1:Bh8", [], 800)
	b.run()
	ok("losing side sees negative score", b.score < -200, str(b.score))
	ok("score_white is White's view", b.score_white == -b.score)


func _test_takes_draw_by_repetition() -> void:
	section("draw awareness from game history")
	var fen := "W:WKc1:BKh8,Kf8,Kd8"
	var moves := ["c1b2", "h8g7", "b2a1", "g7h8", "a1b2", "h8g7", "b2c1", "g7h8"]
	var e := pos("english", fen)
	for u in moves:
		play(e, u)
	eq("position seen twice", e.repetition_count(), 2)
	for l in ["club", "master"]:
		var j := _job("english", l, fen, moves, 500)
		j.run()
		eq("%s (a king down) repeats for the draw" % l, j.best_uci, "c1b2")
	var ahead := _job("english", "master", "B:WKc1:BKh8,Kf8,Kd8", ["h8g7", "c1b2", "g7h8", "b2a1", "h8g7", "a1b2", "g7h8", "b2c1"], 500)
	ahead.run()
	ok("winning side avoids the repetition", ahead.best_uci != "h8g7" and not ahead.best_uci.is_empty(), ahead.best_uci)
	var d := e.clone()
	play(d, "c1b2")
	eq("engine agrees it is a draw", d.result, CheckersEngine.Result.DRAW_REPETITION)


func _test_analysis_deterministic() -> void:
	section("analysis is deterministic")
	var moves := ["c3d4", "f6g5", "b2c3", "g7f6"]
	var a := _job("russian", "analysis", "", moves, 30000)
	a.max_depth = 6
	a.run()
	var b := _job("russian", "analysis", "", moves, 30000)
	b.max_depth = 6
	b.run()
	eq("same move", a.best_uci, b.best_uci)
	eq("same score", a.score, b.score)
	eq("same nodes", a.nodes, b.nodes)
	eq("same pv", a.pv, b.pv)
	eq("depth honoured", a.depth, 6)
	var m1 := _job("english", "master", "", ["f6e5", "c3d4", "e5c3", "b2d4"], 30000)
	m1.max_depth = 5
	m1.use_book = false
	m1.run()
	var m2 := _job("english", "master", "", ["f6e5", "c3d4", "e5c3", "b2d4"], 30000)
	m2.max_depth = 5
	m2.use_book = false
	m2.run()
	ok("master deterministic out of book", m1.best_uci == m2.best_uci and m1.nodes == m2.nodes)


func _test_job_errors() -> void:
	section("job errors")
	var bad := _job("english", "club", "", ["c3d4"])
	bad.run()
	ok("illegal history reported", not bad.error.is_empty() and bad.best_uci.is_empty() and bad.done)
	var fen := _job("english", "club", "garbage")
	fen.run()
	ok("bad fen reported", not fen.error.is_empty())
	var over := _job("english", "club", "B:WKa1:B")
	over.run()
	ok("finished game has no move", over.best_uci.is_empty() and not over.error.is_empty())


func _test_playthrough() -> void:
	section("AI vs random playthrough")
	for v in VARIANTS:
		var e := CheckersEngine.new(v)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		var plies := 0
		var bad := false
		while not e.game_over() and plies < 60:
			var pick: CheckersMove
			if plies % 2 == 0:
				var j := CheckersAI.SearchJob.new()
				j.variant = v
				j.start_fen = e.start_fen
				for h in e.history:
					j.moves_uci.append(h.to_uci())
				j.level = "casual"
				j.time_ms = 60
				j.seed = 99 + plies
				j.run()
				pick = e.find_uci(j.best_uci)
				if pick == null:
					bad = true
					break
			else:
				var ms := e.generate_legal_moves()
				pick = ms[rng.randi_range(0, ms.size() - 1)]
			if e.apply_move(pick) == null:
				bad = true
				break
			plies += 1
		ok("%s playthrough legal (%d plies, %s)" % [v, plies, e.result_text()], not bad and plies > 10)
		if e.game_over():
			ok("%s ended with a real result" % v, e.result != CheckersEngine.Result.NONE and not e.result_text().is_empty())
