class_name CheckersAI
extends RefCounted

## "Shadow" - the computer opponent.
##
## Search: iterative deepening, negamax alpha-beta with PVS and light late-move
## reductions, a Zobrist transposition table in fixed-size packed arrays, move
## ordering (TT move, captures by count, promotions, two killers per ply,
## history heuristic), forced-move extension and a quiescence phase that keeps
## searching while the side to move must capture. Draw awareness uses the real
## game history (repetition since the last irreversible move, move-rule counter).
##
## All search work happens on a private CheckersEngine through its compact
## search interface (generate_keys / make_key / unmake_key) - no scene tree, no
## autoloads, safe on WorkerThreadPool. Static tables are built on class load
## (main thread) and by warmup().

const INF := 1000000
const MATE := 100000
const MATE_BOUND := 99000
const MAX_PLY := 96
const TT_BITS := 18
const TT_EXACT := 0
const TT_LOWER := 1
const TT_UPPER := 2

const LEVELS: Array[Dictionary] = [
	{"id": "beginner", "name": "Beginner", "blurb": "Looks one or two moves ahead and often plays loosely."},
	{"id": "casual", "name": "Casual", "blurb": "A relaxed opponent that sees simple shots but not deep ones."},
	{"id": "club", "name": "Club", "blurb": "Solid club strength. Punishes loose pieces and plays sensible openings."},
	{"id": "advanced", "name": "Advanced", "blurb": "Calculates tactics deeply and understands the endgame."},
	{"id": "expert", "name": "Expert", "blurb": "Strong, deterministic search with only opening-book variety."},
	{"id": "master", "name": "Master", "blurb": "Full strength. Thinks about 2.5 seconds per move."},
]

## Search profiles. noise: +- random centi-men added to exact root scores
## (lower levels). shallow: chance of playing from the depth-1 result.
const PROFILES := {
	"beginner": {"depth": 2, "time": 250, "noise": 70, "shallow": 0.3, "book": true, "book_uniform": true},
	"casual": {"depth": 4, "time": 400, "noise": 35, "shallow": 0.08, "book": true, "book_uniform": true},
	"club": {"depth": 6, "time": 800, "noise": 14, "shallow": 0.0, "book": true, "book_uniform": true},
	"advanced": {"depth": 12, "time": 1200, "noise": 4, "shallow": 0.0, "book": true, "book_uniform": false},
	"expert": {"depth": 64, "time": 1800, "noise": 0, "shallow": 0.0, "book": true, "book_uniform": false},
	"master": {"depth": 64, "time": 2500, "noise": 0, "shallow": 0.0, "book": true, "book_uniform": false},
	"analysis": {"depth": 64, "time": 3000, "noise": 0, "shallow": 0.0, "book": false, "book_uniform": false},
}

## Forward "cone" per [color * 64 + sq] as a dark-index bitmask: enemy men can
## never enter a man's cone, so an empty cone means a runaway man.
static var _cone: PackedInt64Array = PackedInt64Array()
static var _static_mutex: Mutex = Mutex.new()
static var _static_ready := false


static func _static_init() -> void:
	_build_static()


static func _build_static() -> void:
	_static_mutex.lock()
	if not _static_ready:
		CheckersTypes.build_tables()
		var cone := PackedInt64Array()
		cone.resize(128)
		for color in 2:
			for s in 64:
				var f := s & 7
				var r := s >> 3
				var m := 0
				for t in CheckersTypes.DARK:
					var tf := t & 7
					var tr := t >> 3
					var dr := (tr - r) if color == CheckersTypes.WHITE else (r - tr)
					if dr > 0 and absi(tf - f) <= dr:
						m |= 1 << (t >> 1)
				cone[color * 64 + s] = m
		_cone = cone
		_static_ready = true
	_static_mutex.unlock()


## Build every static table (call once on the main thread at startup).
static func warmup() -> void:
	CheckersTypes.build_tables()
	_build_static()
	CheckersBook.ensure_loaded()


static func levels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in LEVELS:
		out.append(l.duplicate())
	return out


static func level_id_from_legacy(old: String) -> String:
	match old.strip_edges().to_lower():
		"easy":
			return "casual"
		"medium":
			return "club"
		"hard":
			return "advanced"
		"master":
			return "master"
		"beginner", "casual", "club", "advanced", "expert":
			return old.strip_edges().to_lower()
		_:
			return "club"


static func profile(level: String) -> Dictionary:
	return PROFILES.get(level, PROFILES["club"])


## Synchronous helper (tests, tools): returns a move object from
## engine.generate_legal_moves(), or null when there is none.
static func choose(engine: CheckersEngine, level: String = "club") -> CheckersMove:
	if engine == null or engine.game_over():
		return null
	var job := SearchJob.new()
	job.variant = engine.variant
	job.level = level
	var ai := CheckersAI.new()
	ai._run(job, engine.clone())
	if job.best_uci.is_empty():
		return null
	for m in engine.generate_legal_moves():
		if m.to_uci() == job.best_uci:
			return m
	return null


class SearchJob:
	extends RefCounted
	var variant: String = "english"
	var start_fen: String = ""
	var moves_uci: PackedStringArray = PackedStringArray()
	var level: String = "club"
	var time_ms: int = -1
	var max_depth: int = -1
	var use_book: bool = true
	var cancelled: bool = false
	## 0 = random seed; any other value makes lower-level randomness repeatable.
	var seed: int = 0
	# outputs
	var best_uci: String = ""
	var score: int = 0
	var score_white: int = 0
	var win_in: int = 0
	var depth: int = 0
	var nodes: int = 0
	var nps: int = 0
	var pv: PackedStringArray = PackedStringArray()
	var from_book: bool = false
	var elapsed_ms: int = 0
	var error: String = ""
	var done: bool = false

	func run() -> void:
		var e := CheckersEngine.new(variant)
		if not start_fen.is_empty() and not e.from_fen(start_fen):
			error = "bad start_fen"
			done = true
			return
		for u in moves_uci:
			var m := e.find_uci(u)
			if m == null or e.apply_move(m) == null:
				error = "cannot replay move '%s'" % u
				done = true
				return
		var ai := CheckersAI.new()
		ai._run(self, e)


# ------------------------------------------------------------ instance ----

var _e: CheckersEngine
var _job: SearchJob
var _tt_key: PackedInt64Array
var _tt_move: PackedInt64Array
var _tt_data: PackedInt64Array
var _tt_mask: int = 0
var _killers: PackedInt64Array
var _hist: PackedInt32Array
var _bufs: Array[PackedInt64Array] = []
var _ord: Array[PackedInt32Array] = []
var _pst: PackedInt32Array
var _nb: PackedInt32Array
var _dark: PackedInt32Array
var _nodes: int = 0
var _stop := false
var _no_timeout := false
var _deadline: int = 0
var _root_keys: PackedInt64Array
var _root_scores: PackedInt32Array
var _root_n: int = 0
var _final_keys: PackedInt64Array = PackedInt64Array()
var _final_scores: PackedInt32Array = PackedInt32Array()
var _exact_root := false
var _iter_first_done := false
var _iter_best_key: int = 0
var _iter_best_score: int = 0
var _flying := false
var _english := true
var _king_val := 150
var _bridge := 0


func _run(job: SearchJob, e: CheckersEngine) -> void:
	var t0 := Time.get_ticks_msec()
	_job = job
	_e = e
	var prof := profile(job.level)
	var rng := RandomNumberGenerator.new()
	if job.seed != 0:
		rng.seed = job.seed
	else:
		rng.randomize()
	job.best_uci = ""
	job.pv = PackedStringArray()
	job.from_book = false
	if e.game_over():
		job.error = "game over"
		job.done = true
		return
	var legal := e.generate_legal_moves()
	if legal.is_empty():
		job.error = "no legal moves"
		job.done = true
		return
	if job.use_book and bool(prof["book"]) and job.level != "analysis":
		var bu := CheckersBook.pick(e, rng, bool(prof["book_uniform"]))
		if not bu.is_empty():
			job.best_uci = bu
			job.from_book = true
			job.pv = PackedStringArray([bu])
			job.score = 0
			job.score_white = 0
			job.depth = 0
			job.elapsed_ms = Time.get_ticks_msec() - t0
			job.done = true
			return
	var max_depth: int = int(prof["depth"])
	if job.max_depth > 0:
		max_depth = mini(job.max_depth, MAX_PLY - 8)
	var shallow: float = float(prof["shallow"])
	if shallow > 0.0 and rng.randf() < shallow:
		max_depth = 1
	var time_ms: int = int(prof["time"])
	if job.time_ms > 0:
		time_ms = job.time_ms
	var noise: int = int(prof["noise"])
	_setup()
	_exact_root = noise > 0
	_deadline = t0 + time_ms
	var result := _iterate(max_depth, time_ms, t0)
	var best_key: int = result["key"]
	if noise > 0 and _final_keys.size() > 1:
		var best_s := -INF
		for i in _final_keys.size():
			var s := _final_scores[i]
			if s > -MATE_BOUND and s < MATE_BOUND:
				s += rng.randi_range(-noise, noise)
			if s > best_s:
				best_s = s
				best_key = _final_keys[i]
	job.best_uci = _uci_for_key(best_key)
	if job.best_uci.is_empty():
		job.best_uci = legal[0].to_uci()
	job.score = int(result["score"])
	job.score_white = job.score if e.side_to_move == CheckersTypes.WHITE else -job.score
	job.win_in = 0
	if job.score > MATE_BOUND:
		job.win_in = (MATE - job.score + 1) / 2
	elif job.score < -MATE_BOUND:
		job.win_in = -((MATE + job.score + 1) / 2)
	job.depth = int(result["depth"])
	job.nodes = _nodes
	job.elapsed_ms = Time.get_ticks_msec() - t0
	job.nps = int(_nodes * 1000 / maxi(job.elapsed_ms, 1))
	job.pv = _extract_pv(best_key, job.depth)
	job.done = true


func _setup() -> void:
	_nb = CheckersTypes.NB
	_dark = CheckersTypes.DARK
	var size := 1 << TT_BITS
	_tt_mask = size - 1
	_tt_key = PackedInt64Array()
	_tt_key.resize(size)
	_tt_move = PackedInt64Array()
	_tt_move.resize(size)
	_tt_data = PackedInt64Array()
	_tt_data.resize(size)
	_killers = PackedInt64Array()
	_killers.resize(MAX_PLY * 2 + 4)
	_hist = PackedInt32Array()
	_hist.resize(2 * 64 * 64)
	_bufs.clear()
	_ord.clear()
	for i in MAX_PLY + 2:
		var b := PackedInt64Array()
		b.resize(48)
		_bufs.append(b)
		var o := PackedInt32Array()
		o.resize(48)
		_ord.append(o)
	_nodes = 0
	_stop = false
	_flying = _e._flying
	_english = _e.variant == "english"
	_king_val = 300 if _flying else 150
	_build_pst()


# --------------------------------------------------------- evaluation ----

func _build_pst() -> void:
	var total := 0
	for s in _dark:
		if _e.squares[s] != 0:
			total += 1
	var eg := clampf((24.0 - float(total)) / 20.0, 0.0, 1.0)
	var adv_mg: Array
	var adv_eg: Array
	if _flying:
		adv_mg = [0, 2, 5, 8, 12, 18, 26, 0]
		adv_eg = [0, 8, 16, 26, 40, 56, 76, 0]
	else:
		adv_mg = [0, 1, 3, 5, 8, 12, 17, 0]
		adv_eg = [0, 6, 12, 20, 30, 42, 58, 0]
	_bridge = int(round(22.0 * (1.0 - eg))) if _english else 0
	_pst = PackedInt32Array()
	_pst.resize(19 * 64)
	for s in _dark:
		for color in 2:
			var rs := s if color == CheckersTypes.WHITE else 63 - s
			var r := rs >> 3
			var f := rs & 7
			var v := 100.0 + lerpf(float(adv_mg[r]), float(adv_eg[r]), eg)
			if f >= 2 and f <= 5 and r >= 2 and r <= 5:
				v += 5.0 * (1.0 - eg) + 2.0
			if f == 0 or f == 7:
				v -= 3.0
			if r == 0:
				v += 7.0 * (1.0 - eg)
			var sign := 1 if color == CheckersTypes.WHITE else -1
			_pst[(CheckersTypes.pack(CheckersTypes.MAN, color) << 6) | s] = sign * int(round(v))
			var dx := absi(f * 2 - 7)
			var dy := absi(r * 2 - 7)
			var d := (dx + dy) / 2
			var kv := float(_king_val) + float(7 - d) * (2.0 + 4.0 * eg)
			if _flying:
				if f == r:
					kv += 18.0
				elif f + r == 6 or f + r == 8:
					kv += 7.0
			elif f == 0 or f == 7 or r == 0 or r == 7:
				kv -= 6.0
			_pst[(CheckersTypes.pack(CheckersTypes.KING, color) << 6) | s] = sign * int(round(kv))


## Static evaluation in centi-men from the side to move's point of view.
func _eval() -> int:
	var sqs := _e.squares
	var pst := _pst
	var nb := _nb
	var sc := 0
	var wm := 0
	var wk := 0
	var bm := 0
	var bk := 0
	var mob := 0
	var wocc := 0
	var bocc := 0
	for s in _dark:
		var p := sqs[s]
		if p == 0:
			continue
		sc += pst[(p << 6) | s]
		if p == 1:
			wm += 1
			wocc |= 1 << (s >> 1)
			var t := nb[s * 4]
			if t >= 0 and sqs[t] == 0:
				mob += 1
			t = nb[s * 4 + 1]
			if t >= 0 and sqs[t] == 0:
				mob += 1
		elif p == 17:
			bm += 1
			bocc |= 1 << (s >> 1)
			var t := nb[s * 4 + 2]
			if t >= 0 and sqs[t] == 0:
				mob -= 1
			t = nb[s * 4 + 3]
			if t >= 0 and sqs[t] == 0:
				mob -= 1
		elif p == 2:
			wk += 1
			wocc |= 1 << (s >> 1)
		else:
			bk += 1
			bocc |= 1 << (s >> 1)
	var wn := wm + wk
	var bn := bm + bk
	if wn == 0:
		return -MATE_BOUND + 500 if _e.side_to_move == CheckersTypes.WHITE else MATE_BOUND - 500
	if bn == 0:
		return MATE_BOUND - 500 if _e.side_to_move == CheckersTypes.WHITE else -MATE_BOUND + 500
	sc += mob * 3
	var total := wn + bn
	# Back-rank bridge (English: Black keeps 1 & 3, White 30 & 32).
	if _bridge > 0:
		if sqs[2] == 1 and sqs[6] == 1:
			sc += _bridge
		if sqs[57] == 17 and sqs[61] == 17:
			sc -= _bridge
	# Runaway men: empty forward cone of enemy pieces.
	if total <= 16:
		var cone := _cone
		if wm > 0:
			for s in _dark:
				if s < 24 or sqs[s] != 1:
					continue
				if (bocc & cone[s]) == 0:
					sc += (40 if bk == 0 else 15) + (s >> 3) * 6
		if bm > 0:
			for s in _dark:
				if s > 39 or sqs[s] != 17:
					continue
				if (wocc & cone[64 + s]) == 0:
					sc -= (40 if wk == 0 else 15) + (7 - (s >> 3)) * 6
	# Trade down when ahead.
	var mat := (wm - bm) * 100 + (wk - bk) * _king_val
	sc += mat * (24 - total) / 48
	# Drawish material.
	if wm == 0 and bm == 0 and wk == bk:
		sc /= 8
	elif _flying and total <= 4:
		if (wn == 1 and wk == 1 and bn <= 2) or (bn == 1 and bk == 1 and wn <= 2):
			sc /= 8
		elif wn == 1 and wk == 1 and bn == 3 and bm == 0:
			if _on_main_diagonal(CheckersTypes.W_KING):
				sc /= 8
		elif bn == 1 and bk == 1 and wn == 3 and wm == 0:
			if _on_main_diagonal(CheckersTypes.B_KING):
				sc /= 8
	return sc if _e.side_to_move == CheckersTypes.WHITE else -sc


func _on_main_diagonal(piece: int) -> bool:
	var sqs := _e.squares
	for s in [0, 9, 18, 27, 36, 45, 54, 63]:
		if sqs[s] == piece:
			return true
	return false


# ------------------------------------------------------------- search ----

func _iterate(max_depth: int, time_ms: int, t0: int) -> Dictionary:
	var e := _e
	_root_keys = PackedInt64Array()
	_root_keys.resize(64)
	_root_n = e.generate_keys(_root_keys)
	_root_scores = PackedInt32Array()
	_root_scores.resize(_root_n)
	var best_key := _root_keys[0]
	var best_score := 0
	var done_depth := 0
	_final_keys = PackedInt64Array()
	_final_scores = PackedInt32Array()
	if _root_n == 1:
		# Forced move: answer at once with a quick shallow score.
		_no_timeout = false
		_deadline = mini(_deadline, Time.get_ticks_msec() + 60)
		var fs := _root_search(mini(max_depth, 6), -INF, INF)
		return {"key": best_key, "score": fs if not _stop else 0, "depth": 1}
	for depth in range(1, max_depth + 1):
		_no_timeout = depth == 1
		var s := _root_search(depth, -INF, INF)
		if _stop:
			# Use a partly searched iteration when the previous best was
			# re-searched at this depth (and possibly beaten by another move).
			if _iter_first_done and not _exact_root:
				best_key = _iter_best_key
				best_score = _iter_best_score
			break
		best_key = _root_keys[0]
		best_score = s
		done_depth = depth
		_final_keys = _root_keys.slice(0, _root_n)
		_final_scores = _root_scores.duplicate()
		var elapsed := Time.get_ticks_msec() - t0
		if absi(s) > MATE_BOUND and MATE - absi(s) <= depth:
			break
		# Do not start an iteration that is unlikely to finish.
		if elapsed * 5 > time_ms * 3:
			break
	return {"key": best_key, "score": best_score, "depth": done_depth}


## Root search; reorders _root_keys so the best move is first (stable by score).
func _root_search(depth: int, alpha: int, beta: int) -> int:
	var e := _e
	var n := _root_n
	var best := -INF
	var a := alpha
	_iter_first_done = false
	for i in n:
		var mv := _root_keys[i]
		e.make_key(mv)
		var s := 0
		if e.halfmove >= e.draw_plies or e.is_repeat():
			s = 0
			_nodes += 1
		elif i == 0 or _exact_root:
			s = -_search(depth - 1, -beta, -a, 1)
		else:
			s = -_search(depth - 1, -a - 1, -a, 1)
			if s > a and not _stop:
				s = -_search(depth - 1, -beta, -a, 1)
		e.unmake_key(mv)
		if _stop:
			if i == 0:
				return 0
			# Keep a partially searched iteration only if a move beat the old best.
			break
		_root_scores[i] = s
		if s > best:
			best = s
			_iter_best_key = mv
			_iter_best_score = s
			if not _exact_root and s > a:
				a = s
		if i == 0:
			_iter_first_done = true
	if _stop:
		return 0
	# Stable sort root moves by score, best first.
	var idx := []
	for i in n:
		idx.append(i)
	var scores := _root_scores
	idx.sort_custom(func(x: int, y: int) -> bool:
		if scores[x] != scores[y]:
			return scores[x] > scores[y]
		return x < y
	)
	var nk := PackedInt64Array()
	nk.resize(_root_keys.size())
	var ns := PackedInt32Array()
	ns.resize(n)
	for j in n:
		nk[j] = _root_keys[idx[j]]
		ns[j] = scores[idx[j]]
	_root_keys = nk
	_root_scores = ns
	return best


func _search(depth: int, alpha: int, beta: int, ply: int) -> int:
	_nodes += 1
	if (_nodes & 255) == 0:
		if _job != null and _job.cancelled:
			_stop = true
		elif not _no_timeout and Time.get_ticks_msec() >= _deadline:
			_stop = true
	if _stop:
		return 0
	var e := _e
	if e.halfmove >= e.draw_plies or e.is_repeat():
		return 0
	if ply >= MAX_PLY:
		return _eval()
	# Mate distance pruning.
	var ma := -MATE + ply
	if alpha < ma:
		alpha = ma
		if alpha >= beta:
			return alpha
	var mb := MATE - ply - 1
	if beta > mb:
		beta = mb
		if alpha >= beta:
			return beta
	var key := e._key
	var slot := key & _tt_mask
	var tt_mv := 0
	var d0 := depth if depth > 0 else 0
	if _tt_key[slot] == key:
		var data := _tt_data[slot]
		tt_mv = _tt_move[slot]
		if ((data >> 20) & 255) >= d0:
			var ts := (data & 0xFFFFF) - 0x80000
			if ts > MATE_BOUND:
				ts -= ply
			elif ts < -MATE_BOUND:
				ts += ply
			var tf := (data >> 28) & 3
			if tf == TT_EXACT:
				return ts
			if tf == TT_LOWER and ts >= beta:
				return ts
			if tf == TT_UPPER and ts <= alpha:
				return ts
	var buf: PackedInt64Array = _bufs[ply]
	var n := e.generate_keys(buf)
	if n == 0:
		return -MATE + ply
	var capture := (buf[0] & 0xFFFFFFFF) != 0
	if depth <= 0 and not capture:
		return _eval()
	var new_depth := depth - 1
	if n == 1 or depth <= 0:
		new_depth = d0
	# Order.
	var ord: PackedInt32Array = _ord[ply]
	if ord.size() < n:
		ord.resize(n + 16)
	var color := e.side_to_move
	var k1 := _killers[ply * 2]
	var k2 := _killers[ply * 2 + 1]
	var hist := _hist
	for i in n:
		var mv := buf[i]
		var o := 0
		if mv == tt_mv:
			o = 10000000
		elif (mv & 0xFFFFFFFF) != 0:
			o = 1000000 + ((mv >> 45) & 31) * 10000
			if (mv & CheckersTypes.KEY_PROMO) != 0:
				o += 5000
		elif (mv & CheckersTypes.KEY_PROMO) != 0:
			o = 500000
		elif mv == k1:
			o = 400000
		elif mv == k2:
			o = 390000
		else:
			o = hist[(color << 12) | (((mv >> 32) & 63) << 6) | ((mv >> 38) & 63)]
		ord[i] = o
	var alpha0 := alpha
	var best := -INF
	var best_mv := 0
	for i in n:
		# Selection sort step.
		var bi := i
		var bo := ord[i]
		for j in range(i + 1, n):
			if ord[j] > bo:
				bo = ord[j]
				bi = j
		var mv := buf[bi]
		if bi != i:
			buf[bi] = buf[i]
			buf[i] = mv
			ord[bi] = ord[i]
			ord[i] = bo
		var quiet := (mv & 0xFFFFFFFF) == 0 and (mv & CheckersTypes.KEY_PROMO) == 0
		e.make_key(mv)
		var s := 0
		if i == 0:
			s = -_search(new_depth, -beta, -alpha, ply + 1)
		else:
			var rd := new_depth
			if quiet and depth >= 3 and i >= 3 and mv != k1 and mv != k2 and not capture:
				rd = new_depth - 1
			s = -_search(rd, -alpha - 1, -alpha, ply + 1)
			if s > alpha and rd < new_depth and not _stop:
				s = -_search(new_depth, -alpha - 1, -alpha, ply + 1)
			if s > alpha and s < beta and not _stop:
				s = -_search(new_depth, -beta, -alpha, ply + 1)
		e.unmake_key(mv)
		if _stop:
			return 0
		if s > best:
			best = s
			best_mv = mv
			if s > alpha:
				alpha = s
				if s >= beta:
					if quiet:
						if mv != k1:
							_killers[ply * 2 + 1] = k1
							_killers[ply * 2] = mv
						var hi := (color << 12) | (((mv >> 32) & 63) << 6) | ((mv >> 38) & 63)
						hist[hi] += d0 * d0 + 1
						if hist[hi] > 300000:
							for q in hist.size():
								hist[q] >>= 1
					break
	var flag := TT_EXACT
	if best <= alpha0:
		flag = TT_UPPER
	elif best >= beta:
		flag = TT_LOWER
	var ss := best
	if ss > MATE_BOUND:
		ss += ply
	elif ss < -MATE_BOUND:
		ss -= ply
	_tt_key[slot] = key
	_tt_move[slot] = best_mv
	_tt_data[slot] = (ss + 0x80000) | (mini(d0, 255) << 20) | (flag << 28)
	return best


# ------------------------------------------------------------ helpers ----

func _uci_for_key(k: int) -> String:
	for m in _e.generate_legal_moves():
		if m.search_key() == k:
			return m.to_uci()
	return ""


func _extract_pv(first: int, depth: int) -> PackedStringArray:
	var out := PackedStringArray()
	var e := _e
	var made: Array[int] = []
	var mv := first
	var limit := maxi(depth, 1) + 4
	while mv != 0 and made.size() < limit:
		var u := _uci_for_key(mv)
		if u.is_empty():
			break
		out.append(u)
		e.make_key(mv)
		made.append(mv)
		if e.is_repeat():
			break
		var slot := e._key & _tt_mask
		if _tt_key[slot] != e._key:
			break
		mv = _tt_move[slot]
	while not made.is_empty():
		e.unmake_key(made.pop_back())
	return out
