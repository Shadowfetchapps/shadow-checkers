extends "res://tests/test_base.gd"

## Puzzle set verification: every entry is replayed and re-proved with the
## exact solver (CheckersPuzzles) against all defences.

const MAX_CALL_MS := 800

var _slowest_ms := 0
var _slowest_what := ""


func run_all() -> bool:
	suite_name = "puzzles"
	_test_set_shape()
	_test_embedded_copy()
	_test_api_basics()
	_test_every_puzzle()
	ok("slowest solver call %d ms (%s) < %d ms" % [_slowest_ms, _slowest_what, MAX_CALL_MS], _slowest_ms < MAX_CALL_MS)
	return failed == 0


func _timed_solving(e: CheckersEngine, uci: String, pz: Dictionary, left: int) -> bool:
	var t0 := Time.get_ticks_msec()
	var r := CheckersPuzzles.is_solving_move(e, uci, pz, left)
	_note(Time.get_ticks_msec() - t0, "%s is_solving_move %s" % [pz["id"], uci])
	return r


func _timed_defense(e: CheckersEngine, pz: Dictionary, left: int, pref: String) -> String:
	var t0 := Time.get_ticks_msec()
	var r := CheckersPuzzles.best_defense(e, pz, left, pref)
	_note(Time.get_ticks_msec() - t0, "%s best_defense" % pz["id"])
	return r


func _note(ms: int, what: String) -> void:
	if ms > _slowest_ms:
		_slowest_ms = ms
		_slowest_what = what


func _test_set_shape() -> void:
	section("puzzle set")
	var all := CheckersPuzzles.load_all()
	ok("at least 30 puzzles (%d)" % all.size(), all.size() >= 30)
	var per := {"english": 0, "russian": 0, "brazilian": 0}
	var ids := {}
	var keys_ok := true
	for pz in all:
		per[pz["variant"]] = int(per.get(pz["variant"], 0)) + 1
		ids[pz["id"]] = true
		for k in ["id", "title", "variant", "fen", "side", "goal", "gain", "solution", "plies", "theme", "difficulty"]:
			if not pz.has(k):
				keys_ok = false
		if str(pz["title"]).is_empty() or str(pz["theme"]).is_empty():
			keys_ok = false
		if not ["gain", "win"].has(pz["goal"]) or int(pz["difficulty"]) < 1 or int(pz["difficulty"]) > 5:
			keys_ok = false
	ok("english >= 20 (%d)" % per["english"], per["english"] >= 20)
	ok("russian >= 4 (%d)" % per["russian"], per["russian"] >= 4)
	ok("brazilian >= 4 (%d)" % per["brazilian"], per["brazilian"] >= 4)
	eq("ids unique", ids.size(), all.size())
	ok("every entry has all fields", keys_ok)
	var a := CheckersPuzzles.load_all()
	a[0]["title"] = "mutated"
	ok("load_all returns copies", CheckersPuzzles.load_all()[0]["title"] != "mutated")
	ok("find by id", not CheckersPuzzles.find(all[0]["id"]).is_empty() and CheckersPuzzles.find("nope").is_empty())


func _test_embedded_copy() -> void:
	section("embedded copy")
	var file_text := FileAccess.get_file_as_string(CheckersPuzzles.PATH)
	var from_file := CheckersPuzzles.parse_text(file_text)
	var embedded := CheckersPuzzles.parse_text(CheckersPuzzles.EMBEDDED)
	ok("data file parses", from_file.size() >= 30)
	eq("embedded copy matches data/puzzles.json", JSON.stringify(embedded), JSON.stringify(from_file))


func _test_api_basics() -> void:
	section("solver API")
	var pz := {"id": "t", "variant": "english", "fen": "W:We3,d2,c3,c1:Bc5,e5,a7,g7", "side": "w", "goal": "gain", "gain": 1.0, "solution": PackedStringArray(["e3d4", "c5e3", "d2f4d6"]), "plies": 3}
	var e := CheckersPuzzles.start_engine(pz)
	ok("start engine", e != null and e.side_to_move == CheckersTypes.WHITE)
	eq("validate", CheckersPuzzles.validate(pz), "")
	ok("shot is a solving move", CheckersPuzzles.is_solving_move(e, "e3d4", pz, 3))
	ok("numeric notation accepted", CheckersPuzzles.is_solving_move(e, "23-18", pz, 3))
	ok("other move is not", not CheckersPuzzles.is_solving_move(e, "c1b2", pz, 3))
	ok("too few plies fails", not CheckersPuzzles.is_solving_move(e, "e3d4", pz, 1))
	ok("illegal move is not", not CheckersPuzzles.is_solving_move(e, "e3e4", pz, 3))
	eq("solving_moves unique", CheckersPuzzles.solving_moves(e, pz, 3), PackedStringArray(["e3d4"]))
	eq("min plies", CheckersPuzzles.min_plies(e, pz, 7), 3)
	ok("engine untouched by solver", e.history.is_empty() and e.to_fen() == "W:W22,23,26,30:B5,8,14,15")
	e.apply_move(e.find_uci("e3d4"))
	ok("wrong side for is_solving_move", not CheckersPuzzles.is_solving_move(e, "c5e3", pz, 2))
	eq("forced reply", CheckersPuzzles.best_defense(e, pz, 2, ""), "c5e3")
	e.apply_move(e.find_uci("c5e3"))
	eq("gain so far is -1", CheckersPuzzles.gain_so_far(e, pz), -1.0)
	e.apply_move(e.find_uci("d2f4d6"))
	ok("goal met", CheckersPuzzles.goal_met(e, pz))
	eq("gain so far is +1", CheckersPuzzles.gain_so_far(e, pz), 1.0)
	var win := {"variant": "english", "fen": "W:Wc3:Bd4", "side": "w", "goal": "win", "gain": 1.0}
	var we := CheckersPuzzles.start_engine(win)
	ok("win goal: last piece", CheckersPuzzles.is_solving_move(we, "c3e5", win, 1))
	we.apply_move(we.find_uci("c3e5"))
	eq("no defence when defender has no moves", CheckersPuzzles.best_defense(we, win, 2, ""), "")


func _test_every_puzzle() -> void:
	for pz in CheckersPuzzles.load_all():
		var id: String = pz["id"]
		section("%s %s (%s, %s)" % [id, pz["title"], pz["variant"], pz["theme"]])
		var err := CheckersPuzzles.validate(pz)
		ok("%s valid (FEN, legal line, goal met at end)" % id, err.is_empty(), err)
		if not err.is_empty():
			continue
		var sol: PackedStringArray = pz["solution"]
		var plies: int = pz["plies"]
		var start := CheckersPuzzles.start_engine(pz)
		ok("%s side matches FEN" % id, start.side_to_move == CheckersPuzzles.solver_side(pz))
		# Main line: every solver move solves, every reply is a best defence.
		var e := start.clone()
		var line_ok := true
		var detail := ""
		for i in sol.size():
			var left := plies - i
			if i % 2 == 0:
				if not _timed_solving(e, sol[i], pz, left):
					line_ok = false
					detail = "solver move %d %s does not solve" % [i + 1, sol[i]]
					break
			else:
				var r := _timed_defense(e, pz, left, sol[i])
				if r != sol[i]:
					line_ok = false
					detail = "defence %d: expected %s, best is %s" % [i + 1, sol[i], r]
					break
			e.apply_move(e.find_uci(sol[i]))
			if i < sol.size() - 1 and i % 2 == 0 and CheckersPuzzles.goal_met(e, pz):
				line_ok = false
				detail = "goal already met after ply %d" % (i + 1)
				break
		ok("%s main line is solving moves vs best defence" % id, line_ok, detail)
		# No shortcut.
		if plies >= 3:
			ok("%s no shorter solution" % id, not CheckersPuzzles.solves(start, pz, plies - 2))
		# Not "any move wins": at least one alternative first move fails.
		var alts := 0
		var failing := 0
		var solving := 0
		for m in start.generate_legal_moves():
			if _timed_solving(start, m.to_uci(), pz, plies):
				solving += 1
			elif m.to_uci() != sol[0]:
				failing += 1
			alts += 1
		ok("%s has a failing alternative (%d of %d legal first moves solve)" % [id, solving, alts], failing >= 1 and alts >= 2)
