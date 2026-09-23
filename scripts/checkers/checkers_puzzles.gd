class_name CheckersPuzzles
extends RefCounted

## Verified tactic puzzles (data/puzzles.json, with an embedded copy for exports).
##
## Puzzle entry:
##   {id, title, variant, fen, side ("w"/"b"), goal ("gain"/"win"), gain,
##    solution [full-turn uci...], plies, theme, difficulty 1-5}
##
## Goal semantics (checked only right after a solver move, i.e. with the
## defender to move):
##   "win"  - the defender has no pieces or no legal moves.
##   "gain" - the defender has no pieces/moves, OR the defender has no capture
##            available (so the material cannot be won straight back) and the
##            solver's material balance has improved by at least `gain`
##            compared with the puzzle's start position.
## Material balance: man = 1, king = 1.5 in english, 2.5 in russian/brazilian
## (flying kings); computed internally in half-men.
## `plies` counts full turns of both sides; the solver moves first, so a
## solution of N plies contains (N + 1) / 2 solver moves.
##
## is_solving_move() / best_defense() run an exact AND/OR search (all defender
## replies) with a transposition table on a private clone of the engine, so
## alternative correct moves are accepted. Typical cost is a few ms; the test
## suite asserts every call on the shipped set stays well under a second.

const PATH := "res://data/puzzles.json"
const NODE_LIMIT := 400000

static var _mutex: Mutex = Mutex.new()
static var _cache: Array[Dictionary] = []
static var _loaded := false


# ------------------------------------------------------------- loading ----

static func load_all() -> Array[Dictionary]:
	_mutex.lock()
	if not _loaded:
		_cache = parse_text(read_source_text())
		_loaded = true
	var out: Array[Dictionary] = []
	for p in _cache:
		out.append(p.duplicate(true))
	_mutex.unlock()
	return out


static func find(id: String) -> Dictionary:
	for p in load_all():
		if p["id"] == id:
			return p
	return {}


static func read_source_text() -> String:
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var t := f.get_as_text()
			if not t.strip_edges().is_empty():
				return t
	return EMBEDDED


static func parse_text(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parsed: Variant = JSON.parse_string(text)
	var arr: Array = []
	if parsed is Array:
		arr = parsed
	elif parsed is Dictionary and (parsed as Dictionary).has("puzzles"):
		arr = parsed["puzzles"]
	for raw in arr:
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		var sol := PackedStringArray()
		for u in d.get("solution", []):
			sol.append(str(u))
		out.append({
			"id": str(d.get("id", "")),
			"title": str(d.get("title", "")),
			"variant": CheckersRules.normalize(str(d.get("variant", "english"))),
			"fen": str(d.get("fen", "")),
			"side": str(d.get("side", "w")),
			"goal": str(d.get("goal", "gain")),
			"gain": float(d.get("gain", 1)),
			"solution": sol,
			"plies": int(d.get("plies", sol.size())),
			"theme": str(d.get("theme", "")),
			"difficulty": clampi(int(d.get("difficulty", 1)), 1, 5),
		})
	return out


## Fresh engine at the puzzle's start position (null if the FEN is bad).
static func start_engine(puzzle: Dictionary) -> CheckersEngine:
	var e := CheckersEngine.new(str(puzzle.get("variant", "english")))
	if not e.from_fen(str(puzzle.get("fen", ""))):
		return null
	return e


static func solver_side(puzzle: Dictionary) -> int:
	return CheckersTypes.BLACK if str(puzzle.get("side", "w")).to_lower() == "b" else CheckersTypes.WHITE


## Material balance for `side` in half-men (man 2, king 3 english / 5 flying).
static func balance_half(squares: PackedInt32Array, side: int, variant: String) -> int:
	var kv := 5 if CheckersRules.flying_kings(variant) else 3
	var s := 0
	for q in CheckersTypes.DARK:
		var p := squares[q]
		if p == 0:
			continue
		var v := 2 if (p & 15) == CheckersTypes.MAN else kv
		s += v if (p >> 4) == side else -v
	return s


## Material improvement for the solver since the puzzle start, in men (float).
static func gain_so_far(engine: CheckersEngine, puzzle: Dictionary) -> float:
	var st := start_engine(puzzle)
	if st == null:
		return 0.0
	var side := solver_side(puzzle)
	return float(balance_half(engine.squares, side, engine.variant) - balance_half(st.squares, side, engine.variant)) / 2.0


## True when the goal is met in the engine's position (defender to move).
static func goal_met(engine: CheckersEngine, puzzle: Dictionary) -> bool:
	var s := _Solver.new(engine, puzzle)
	if not s.ok:
		return false
	return engine.side_to_move != s.solver and s.checkpoint(0)


# ------------------------------------------------------------- solving ----

## Solver to move: can the goal still be forced within plies_left plies?
static func solves(engine: CheckersEngine, puzzle: Dictionary, plies_left: int) -> bool:
	var s := _Solver.new(engine, puzzle)
	if not s.ok or engine.side_to_move != s.solver or plies_left < 1:
		return false
	return s.solve(plies_left, 0)


## Is `uci` (solver to move) a move that still forces the goal against best
## defence within plies_left plies (this move included)?
static func is_solving_move(engine: CheckersEngine, uci: String, puzzle: Dictionary, plies_left: int) -> bool:
	var s := _Solver.new(engine, puzzle)
	if not s.ok or engine.side_to_move != s.solver or plies_left < 1:
		return false
	var m := s.e.find_uci(uci)
	if m == null:
		return false
	return s.after_solver_move(m.search_key(), plies_left, 0)


## Defender to move: the reply that minimises the solver's outcome within
## plies_left plies (this reply included). Order of preference: a reply after
## which the solver can no longer force the goal; otherwise the reply that
## makes the solver need the most plies; ties go to `preferred`, then to the
## engine's move order. Returns "" when the defender has no legal move.
static func best_defense(engine: CheckersEngine, puzzle: Dictionary, plies_left: int, preferred: String = "") -> String:
	var legal := engine.generate_legal_moves()
	if legal.is_empty():
		return ""
	var s := _Solver.new(engine, puzzle)
	var pref := engine.find_uci(preferred) if not preferred.is_empty() else null
	var pref_uci := pref.to_uci() if pref != null else ""
	if not s.ok or engine.side_to_move == s.solver or plies_left < 2:
		return pref_uci if not pref_uci.is_empty() else legal[0].to_uci()
	var best_uci := ""
	var best_rank := -1
	for m in legal:
		var k := m.search_key()
		s.e.make_key(k)
		var rank := 0
		var need := s.min_plies(plies_left - 1, 1)
		if need < 0:
			rank = 1000
		else:
			rank = need
		s.e.unmake_key(k)
		var u := m.to_uci()
		if rank > best_rank or (rank == best_rank and u == pref_uci):
			best_rank = rank
			best_uci = u
	return best_uci


## Minimal number of plies (odd, <= max_plies) in which the solver (to move)
## forces the goal, or -1.
static func min_plies(engine: CheckersEngine, puzzle: Dictionary, max_plies: int) -> int:
	var s := _Solver.new(engine, puzzle)
	if not s.ok or engine.side_to_move != s.solver:
		return -1
	return s.min_plies(max_plies, 0)


## Legal solver moves (uci) that force the goal within plies_left.
static func solving_moves(engine: CheckersEngine, puzzle: Dictionary, plies_left: int) -> PackedStringArray:
	var out := PackedStringArray()
	var s := _Solver.new(engine, puzzle)
	if not s.ok or engine.side_to_move != s.solver:
		return out
	for m in s.e.generate_legal_moves():
		if s.after_solver_move(m.search_key(), plies_left, 0):
			out.append(m.to_uci())
	return out


## Full consistency check of one entry; returns "" when valid.
static func validate(puzzle: Dictionary) -> String:
	var e := start_engine(puzzle)
	if e == null:
		return "bad FEN"
	if e.side_to_move != solver_side(puzzle):
		return "side does not match FEN"
	var sol: PackedStringArray = puzzle.get("solution", PackedStringArray())
	var plies := int(puzzle.get("plies", 0))
	if sol.size() != plies or plies < 1 or plies % 2 == 0:
		return "plies must equal the (odd) solution length"
	for i in sol.size():
		var m := e.find_uci(sol[i])
		if m == null or e.apply_move(m) == null:
			return "illegal solution move %d '%s'" % [i + 1, sol[i]]
	if not goal_met(e, puzzle):
		return "goal not met at the end of the solution"
	return ""


class _Solver:
	extends RefCounted
	var ok := false
	var e: CheckersEngine
	var solver: int = 0
	var goal_win := false
	var need: int = 2
	var start_bal: int = 0
	var man_v := 2
	var king_v := 3
	var tt: Dictionary = {}
	var bufs: Array[PackedInt64Array] = []
	var nodes := 0

	func _init(src: CheckersEngine, puzzle: Dictionary) -> void:
		var st := CheckersPuzzles.start_engine(puzzle)
		if src == null or st == null:
			return
		e = src.clone()
		e.redo_stack.clear()
		solver = CheckersPuzzles.solver_side(puzzle)
		goal_win = str(puzzle.get("goal", "gain")) == "win"
		need = maxi(1, int(round(float(puzzle.get("gain", 1)) * 2.0)))
		king_v = 5 if CheckersRules.flying_kings(e.variant) else 3
		start_bal = CheckersPuzzles.balance_half(st.squares, solver, e.variant)
		for i in 40:
			var b := PackedInt64Array()
			b.resize(64)
			bufs.append(b)
		ok = true

	func balance() -> int:
		var sqs := e.squares
		var s := 0
		for q in CheckersTypes.DARK:
			var p := sqs[q]
			if p == 0:
				continue
			var v := man_v if (p & 15) == CheckersTypes.MAN else king_v
			s += v if (p >> 4) == solver else -v
		return s

	## Defender to move: is the goal met right now?
	func checkpoint(ply: int) -> bool:
		var buf: PackedInt64Array = bufs[ply]
		var n := e.generate_keys(buf)
		if n == 0:
			return true
		if goal_win:
			return false
		if (buf[0] & 0xFFFFFFFF) != 0:
			return false
		return balance() - start_bal >= need

	func after_solver_move(k: int, n: int, ply: int) -> bool:
		e.make_key(k)
		var r := checkpoint(ply + 1)
		if not r and n >= 3:
			r = defend(n - 1, ply + 1)
		e.unmake_key(k)
		return r

	## Solver to move, n >= 1 plies left.
	func solve(n: int, ply: int) -> bool:
		nodes += 1
		if nodes > CheckersPuzzles.NODE_LIMIT or ply >= 38:
			return false
		var key := e._key ^ (n * 0x5851F42D4C957F2D)
		if tt.has(key):
			return tt[key]
		var buf: PackedInt64Array = bufs[ply]
		var cnt := e.generate_keys(buf)
		var moves := buf.slice(0, cnt)
		var r := false
		# Promotions first, then the rest in generation order.
		for pass_i in 2:
			for i in cnt:
				var k := moves[i]
				var promo := (k & CheckersTypes.KEY_PROMO) != 0
				if (pass_i == 0) != promo:
					continue
				if after_solver_move(k, n, ply):
					r = true
					break
			if r:
				break
		tt[key] = r
		return r

	## Defender to move, n >= 2 plies left: does the solver succeed vs all replies?
	func defend(n: int, ply: int) -> bool:
		nodes += 1
		if nodes > CheckersPuzzles.NODE_LIMIT or ply >= 38:
			return false
		var key := e._key ^ (n * 0x5851F42D4C957F2D)
		if tt.has(key):
			return tt[key]
		var buf: PackedInt64Array = bufs[ply]
		var cnt := e.generate_keys(buf)
		var moves := buf.slice(0, cnt)
		var r := true
		for i in cnt:
			var k := moves[i]
			e.make_key(k)
			var sub := solve(n - 1, ply + 1)
			e.unmake_key(k)
			if not sub:
				r = false
				break
		tt[key] = r
		return r

	## Solver to move: smallest odd n <= max_n that solves, or -1.
	func min_plies(max_n: int, ply: int) -> int:
		var n := 1
		while n <= max_n:
			if solve(n, ply):
				return n
			n += 2
		return -1


const EMBEDDED := """[
  {"id": "en-01", "title": "Trapped!", "variant": "english", "fen": "B:WK13,30:BK18,22,28", "side": "b", "goal": "gain", "gain": 1.5, "solution": ["d4c5", "c1d2", "c3e1"], "plies": 3, "theme": "king trap", "difficulty": 1},
  {"id": "en-02", "title": "Trapped! II", "variant": "english", "fen": "B:W5,10,11,13:B2,3,K19,22", "side": "b", "goal": "gain", "gain": 1.0, "solution": ["f4g5", "a5b6", "g5e7c5"], "plies": 3, "theme": "king trap", "difficulty": 1},
  {"id": "en-03", "title": "Two for One", "variant": "english", "fen": "B:WK14,17,K19:B23,K26,K31", "side": "b", "goal": "gain", "gain": 1.5, "solution": ["d2c1", "f4d2", "e1c3a5"], "plies": 3, "theme": "two-for-one", "difficulty": 2},
  {"id": "en-04", "title": "Three for One", "variant": "english", "fen": "W:W13,21,22,23,24,26,27,28,29,30,31,32:B1,3,4,5,6,7,8,9,10,12,14,15", "side": "w", "goal": "gain", "gain": 2.5, "solution": ["e3d4", "c5e3", "f2d4f6d8"], "plies": 3, "theme": "three-for-one", "difficulty": 2},
  {"id": "en-05", "title": "Breakthrough to the King Row", "variant": "english", "fen": "W:W12,18,20,21,22,23,25,27:B3,6,8,9,11,14,15", "side": "w", "goal": "gain", "gain": 1.5, "solution": ["h4g5", "f6h4", "d4f6h8"], "plies": 3, "theme": "breakthrough", "difficulty": 2},
  {"id": "en-06", "title": "Clean Sweep", "variant": "english", "fen": "B:WK5:BK9,K18,19,27", "side": "b", "goal": "win", "gain": 1.0, "solution": ["f4e3", "a7c5", "d4b6"], "plies": 3, "theme": "clean sweep", "difficulty": 2},
  {"id": "en-07", "title": "Two for One II", "variant": "english", "fen": "W:WK1,13,19,20,24:B7,10,11,12,16,K18", "side": "w", "goal": "gain", "gain": 1.5, "solution": ["b8c7", "g5e3", "c7e5c3"], "plies": 3, "theme": "two-for-one", "difficulty": 2},
  {"id": "en-08", "title": "Three for One II", "variant": "english", "fen": "W:W19,21,22,24,28,29,30,31,32:B1,3,7,8,10,12,13,15,16", "side": "w", "goal": "gain", "gain": 2.5, "solution": ["e1f2", "g5e3", "f2d4f6h8"], "plies": 3, "theme": "three-for-one", "difficulty": 2},
  {"id": "en-09", "title": "Breakthrough to the King Row II", "variant": "english", "fen": "W:W14,17,21,25,30,31,32:B4,5,6,7,11,15,16", "side": "w", "goal": "gain", "gain": 1.5, "solution": ["c5d6", "e7c5", "b4d6b8"], "plies": 3, "theme": "breakthrough", "difficulty": 2},
  {"id": "en-10", "title": "Two for One III", "variant": "english", "fen": "W:WK10,11,21,26,30,32:B1,3,18,19,24,28", "side": "w", "goal": "gain", "gain": 1.0, "solution": ["d2e3", "d4f2", "g1e3g5"], "plies": 3, "theme": "two-for-one", "difficulty": 2},
  {"id": "en-11", "title": "Two for One IV", "variant": "english", "fen": "W:W13,20,21,22,23,26,27,28,29,30,31,32:B1,2,3,4,5,6,9,10,11,14,15,16", "side": "w", "goal": "gain", "gain": 1.0, "solution": ["e3d4", "c5e3", "d2f4h6"], "plies": 3, "theme": "two-for-one", "difficulty": 2},
  {"id": "en-12", "title": "The Quiet Move", "variant": "english", "fen": "W:WK15,19,20,K22:BK8,12,K29", "side": "w", "goal": "gain", "gain": 1.5, "solution": ["h4g5", "g7h8", "e5f6", "a1b2", "c3a1"], "plies": 5, "theme": "quiet move", "difficulty": 3},
  {"id": "en-13", "title": "Race to Crown", "variant": "english", "fen": "W:W8,20,23,29:B11,13,15,21", "side": "w", "goal": "gain", "gain": 1.5, "solution": ["g7f8", "a5b4", "f8e7", "a3b2", "a1c3a5"], "plies": 5, "theme": "crowning race", "difficulty": 3},
  {"id": "en-14", "title": "The Quiet Move II", "variant": "english", "fen": "B:WK2,5,21,27:B1,13,16,20,28", "side": "b", "goal": "gain", "gain": 1.5, "solution": ["g5f4", "f2g3", "h4f2", "a3b4", "a5c3"], "plies": 5, "theme": "quiet move", "difficulty": 3},
  {"id": "en-15", "title": "Race to Crown II", "variant": "english", "fen": "B:WK1,22:BK14,16,27", "side": "b", "goal": "gain", "gain": 1.5, "solution": ["f2e1", "b8c7", "e1d2", "c3d4", "c5e3"], "plies": 5, "theme": "crowning race", "difficulty": 3},
  {"id": "en-16", "title": "Clean Sweep II", "variant": "english", "fen": "B:WK5:BK9,18,K23,25", "side": "b", "goal": "win", "gain": 1.0, "solution": ["b2c1", "a7c5", "e3d2", "c5e3", "d2f4"], "plies": 5, "theme": "clean sweep", "difficulty": 4},
  {"id": "en-17", "title": "Three for One III", "variant": "english", "fen": "B:W10,15,19,21,22,25,27:B1,2,3,6,8,18", "side": "b", "goal": "gain", "gain": 2.5, "solution": ["g7f6", "e5g7", "c7e5g3e1", "c3e5", "f8h6"], "plies": 5, "theme": "three-for-one", "difficulty": 4},
  {"id": "en-18", "title": "Breakthrough to the King Row III", "variant": "english", "fen": "W:W18,20,21,24,28,29,30,31,32:B1,2,3,8,10,11,12,13,16", "side": "w", "goal": "gain", "gain": 1.5, "solution": ["d4e5", "d6f4", "g3e5", "f6d4", "h4f6h8"], "plies": 5, "theme": "breakthrough", "difficulty": 4},
  {"id": "en-19", "title": "Race to Crown III", "variant": "english", "fen": "W:W18,19,21,23,24,31,32:B3,7,8,9,12,14,16", "side": "w", "goal": "gain", "gain": 1.5, "solution": ["g3h4", "e7f6", "d4e5", "f6d4f2", "h4f6h8", "c5d4", "g1e3c5a7"], "plies": 7, "theme": "crowning race", "difficulty": 4},
  {"id": "en-20", "title": "Trapped! III", "variant": "english", "fen": "B:WK3,K29:BK24,K30", "side": "b", "goal": "gain", "gain": 1.5, "solution": ["g3f4", "f8g7", "f4g5", "g7h8", "g5h6", "a1b2", "c1a3"], "plies": 7, "theme": "king trap", "difficulty": 4},
  {"id": "en-21", "title": "The Quiet Move III", "variant": "english", "fen": "B:W15,20,21,25,27,29,30:B1,2,3,6,12,14,19", "side": "b", "goal": "gain", "gain": 1.0, "solution": ["f4g3", "f2e3", "c5b4", "a3c5", "c7d6", "c5e7", "d8f6d4f2"], "plies": 7, "theme": "quiet move", "difficulty": 4},
  {"id": "en-22", "title": "The Decoy", "variant": "english", "fen": "W:W19,21,22,25,30,31,32:B1,3,9,11,12,13,23", "side": "w", "goal": "gain", "gain": 1.0, "solution": ["f4e5", "f6d4", "c3e5", "b6c5", "e1d2", "e3f2", "g1e3"], "plies": 7, "theme": "sacrifice", "difficulty": 5},
  {"id": "en-23", "title": "Clean Sweep III", "variant": "english", "fen": "B:WK19:B14,17,25,K26,K27", "side": "b", "goal": "win", "gain": 1.0, "solution": ["d2e3", "f4d2", "b2c1", "d2e1", "f2g3", "e1f2", "g3e1"], "plies": 7, "theme": "clean sweep", "difficulty": 5},
  {"id": "ru-01", "title": "Three for One", "variant": "russian", "fen": "B:W12,20,21,22,23,24,25,29,31,32:B1,3,4,5,7,10,11,13,14", "side": "b", "goal": "gain", "gain": 3.0, "solution": ["c5b4", "a3c5", "d6b4d2f4h2"], "plies": 3, "theme": "three-for-one", "difficulty": 2},
  {"id": "ru-02", "title": "Breakthrough to the King Row", "variant": "russian", "fen": "W:W10,20,23,24,26,27,29:B1,8,9,11,12,16", "side": "w", "goal": "gain", "gain": 2.5, "solution": ["d6e7", "f6d8", "h4f6h8"], "plies": 3, "theme": "breakthrough", "difficulty": 2},
  {"id": "ru-03", "title": "The Long Diagonal", "variant": "russian", "fen": "W:WK5,13,18,21,24,29:B7,11,12,20,K32", "side": "w", "goal": "gain", "gain": 2.5, "solution": ["g3f4", "g1c5", "a7d4h8"], "plies": 3, "theme": "flying king", "difficulty": 2},
  {"id": "ru-04", "title": "The Decoy", "variant": "russian", "fen": "W:W20,21,22,26,29,30,32:B2,5,11,12,K31", "side": "w", "goal": "gain", "gain": 1.5, "solution": ["g1f2", "e1g3", "h4f2"], "plies": 3, "theme": "sacrifice", "difficulty": 2},
  {"id": "ru-05", "title": "Race to Crown", "variant": "russian", "fen": "B:W18,20,22,25,26,27,30,32:B1,3,5,9,11,12,15,19", "side": "b", "goal": "gain", "gain": 2.5, "solution": ["f4g3", "f2e3", "b6a5", "h4f2", "a5b4", "c3a5", "e5c3e1g3"], "plies": 7, "theme": "crowning race", "difficulty": 4},
  {"id": "br-01", "title": "Trapped!", "variant": "brazilian", "fen": "W:W12,13,21,K22:B1,6,14,K23", "side": "w", "goal": "gain", "gain": 2.0, "solution": ["c3d4", "e3f4", "d4b6d8"], "plies": 3, "theme": "king trap", "difficulty": 1},
  {"id": "br-02", "title": "No Way Out", "variant": "brazilian", "fen": "W:W17,18,27,29,30,32:B16", "side": "w", "goal": "win", "gain": 1.0, "solution": ["f2g3", "g5h4", "g1f2"], "plies": 3, "theme": "no way out", "difficulty": 1},
  {"id": "br-03", "title": "Breakthrough to the King Row", "variant": "brazilian", "fen": "B:WK8,10,28,29:B16,17,19,20,21", "side": "b", "goal": "gain", "gain": 3.0, "solution": ["b4c3", "g7b2", "a3c1"], "plies": 3, "theme": "breakthrough", "difficulty": 2},
  {"id": "br-04", "title": "Three for One", "variant": "brazilian", "fen": "B:WK11,13,17,24,25,31:B5,6,8,9,12,15,23", "side": "b", "goal": "gain", "gain": 3.0, "solution": ["c7d6", "f6d4f2", "b6c5", "f2b6", "a7c5a3c1"], "plies": 5, "theme": "three-for-one", "difficulty": 4},
  {"id": "br-05", "title": "Race to Crown", "variant": "brazilian", "fen": "W:W12,13,17,20,21,23,25,26,27:B3,6,8,9,10,14,15,18", "side": "w", "goal": "gain", "gain": 2.0, "solution": ["h4g5", "e5f4", "d2c3", "f4d2", "c3e5", "d6f4", "b4d6b8"], "plies": 7, "theme": "crowning race", "difficulty": 4}
]
"""
