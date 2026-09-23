class_name CheckersBook
extends RefCounted

## English opening book. Source of truth: res://data/opening_book_english.txt
## (one variation per line, PDN numbers). If that file is not packed into an
## export (plain .txt files need the export include filter "data/*.txt"), the
## embedded copy below is used; a test keeps both identical.
##
## Built once into a position-keyed table (Zobrist key -> {uci: weight}), so
## transpositions between lines are found. Thread-safe: built under a Mutex,
## normally from CheckersAI.warmup() on the main thread.

const PATH := "res://data/opening_book_english.txt"

static var _mutex: Mutex = Mutex.new()
static var _loaded := false
static var _table: Dictionary = {}
static var _lines: PackedStringArray = PackedStringArray()
static var _bad: PackedStringArray = PackedStringArray()


static func ensure_loaded() -> void:
	_mutex.lock()
	if not _loaded:
		_build()
		_loaded = true
	_mutex.unlock()


## Raw variation lines (comments stripped).
static func lines() -> PackedStringArray:
	ensure_loaded()
	return _lines


## Lines that failed to replay when the book was built (should be empty).
static func bad_lines() -> PackedStringArray:
	ensure_loaded()
	return _bad


static func read_source_text() -> String:
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			return f.get_as_text()
	return EMBEDDED


static func parse_lines(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for raw in text.split("\n"):
		var t := raw.strip_edges()
		if t.is_empty() or t.begins_with("#"):
			continue
		out.append(t)
	return out


## Book continuations for the engine's current position: {uci: weight}.
static func continuations(engine: CheckersEngine) -> Dictionary:
	if engine.variant != "english":
		return {}
	ensure_loaded()
	return _table.get(engine.hash_key(), {})


## Pick a book move (full-turn uci) or "" when out of book. uniform = true picks
## any listed continuation with equal chance (lower levels, ballot-style
## variety); otherwise weighted by how many lines use it.
static func pick(engine: CheckersEngine, rng: RandomNumberGenerator, uniform: bool) -> String:
	var cont := continuations(engine)
	if cont.is_empty():
		return ""
	var keys := cont.keys()
	keys.sort()
	var total := 0
	for k in keys:
		total += 1 if uniform else int(cont[k])
	var r := rng.randi_range(0, total - 1)
	for k in keys:
		r -= 1 if uniform else int(cont[k])
		if r < 0:
			var m := engine.find_uci(str(k))
			return m.to_uci() if m != null else ""
	return ""


static func _build() -> void:
	_table = {}
	_bad = PackedStringArray()
	_lines = parse_lines(read_source_text())
	for line in _lines:
		var e := CheckersEngine.new("english")
		for tok in line.split(" ", false):
			var m := e.find_uci(tok)
			if m == null:
				_bad.append(line)
				break
			var key := e.hash_key()
			var bucket: Dictionary = _table.get(key, {})
			var u := m.to_uci()
			bucket[u] = int(bucket.get(u, 0)) + 1
			_table[key] = bucket
			if e.apply_move(m) == null:
				_bad.append(line)
				break


const EMBEDDED := """
11-15 23-19 8-11 22-17 4-8 17-13 15-18 24-20 11-15 28-24 8-11 26-23
11-15 23-19 8-11 22-17 9-13 17-14 10x17 21x14 15-18 24-20
11-15 23-19 8-11 22-17 3-8 25-22 11-16 26-23
11-15 23-19 8-11 22-17 15-18 17-13 11-15 24-20
11-15 23-19 9-14 22-17 5-9 17-13
11-15 23-19 9-14 22-17 7-11 25-22 11-16 26-23
11-15 23-19 9-14 22-17 6-9 17-13
11-15 23-19 9-14 27-23 8-11 22-18 15x22
11-15 23-19 9-13 22-18 15x22 25x18 8-11
11-15 23-19 7-11 22-17 9-13 17-14 10x17 21x14
11-15 22-18 15x22 25x18 8-11 29-25 4-8 25-22
11-15 22-18 15x22 25x18 12-16 29-25 9-13 18-14
11-15 22-18 15x22 25x18 10-15
11-15 22-17 8-11 17-13 4-8 25-22 9-14 24-20
11-15 22-17 15-19 24x15 10x19 23x16 12x19 25-22
11-15 22-17 9-13 17-14 10x17 21x14 15-18
11-15 21-17 9-13 25-21 8-11 17-14 10x17 21x14
11-15 24-19 15x24 28x19 8-11 22-18 11-15 18x11 7x16
11-15 24-20 8-11 28-24 4-8 23-19
11-15 23-18 8-11 27-23 4-8 23-19 10-14 19x10
11-15 23-18 9-14 18x9 5x14 22-17 8-11
11-15 24-19 15x24 27x20 8-11 22-18
9-14 22-17 11-15 25-22 8-11 24-19 15x24 28x19
9-14 22-18 5-9 24-19 11-16
9-14 23-18 14x23 27x18 5-9 26-23 11-15 18x11
9-14 24-20 11-15 22-18 15x22
9-13 22-18 11-15 18x11 8x15 24-20
9-13 23-18 11-16 26-23 5-9 24-19
10-14 24-20 11-15 22-17 7-10 17-13 15-19 23x16
10-14 23-19 14-18 22x15 11x18
10-15 22-17 11-16 23-18 15x22 25x18 8-11
10-15 21-17 9-13 24-20 11-16 20x11 7x16 17-14
11-16 24-20 16-19 23x16 12x19 22-17 8-12 25-22
11-16 22-18 16-20 24-19 8-11 25-22 10-14
11-16 23-19 16x23 27x18 8-11 26-23 4-8 22-17
12-16 24-20 8-12 23-19 16x23 27x18 10-15 22-17
12-16 22-18 16-20 25-22 10-14 24-19
9-13 21-17 5-9 25-21 11-15 23-18
9-13 22-17 13x22 25x18 11-15 18x11 8x15
9-13 22-18 10-14 18x9 5x14 24-19
9-13 24-20 10-15 22-18 15x22 25x18
9-14 22-17 5-9 17-13 11-15 25-22
9-14 22-18 5-9 25-22 11-16 24-20
9-14 24-19 11-15 22-18 15x24 18x9 5x14 28x19
9-14 24-20 5-9 22-18 11-15 18x11 8x15
10-14 22-17 7-10 17-13 11-15 25-22
10-14 23-19 11-16 22-18 16x23
10-14 24-20 6-10 22-18 11-15 18x11
10-15 21-17 11-16 23-18 16-20 18x11
10-15 23-18 12-16 26-23 8-12 24-20
10-15 24-19 15x24 28x19 11-15 19x10 6x15
11-15 21-17 8-11 17-13 4-8 23-19
11-15 22-17 15-19 23x16 12x19 24x15 10x19
11-16 21-17 16-19 23x16 12x19 24x15 10x19
11-16 22-18 10-14 25-22 16-20 24-19
11-16 24-19 8-11 22-18 4-8 25-22
12-16 23-18 16-19 24x15 10x19 27-24
12-16 24-19 8-12 22-18 16-20 25-22
11-15 23-18 8-11 26-23 4-8
"""
