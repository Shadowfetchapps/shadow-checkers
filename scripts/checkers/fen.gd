class_name CheckersFen
extends RefCounted

## FEN helpers. Pure functions: parse() never touches an engine, it returns a
## Dictionary {ok, error, squares, side, halfmove, fullmove, legacy} so callers
## can commit only on success.
##
## PDN FEN:   "B:W21,22,K30:B1,2,3"  side to move, then the White and Black
##            piece lists (kings prefixed with K). Also accepted on input:
##            ranges ("W21-32"), algebraic squares ("Wc3,Kd4"), a trailing ".",
##            surrounding quotes, and the lidraughts counters ":H12:F30".
## Legacy v1: "1b1b1b1b/b1b1b1b1/1b1b1b1b/8/8/w1w1w1w1/1w1w1w1w/w1w1w1w1 b - 0 1"
##            (rank 8 first; w/W white man/king, b/B black man/king; the v1
##            "must continue" field is ignored because v2 has no mid-turn state).


static func dump(squares: PackedInt32Array, side: int) -> String:
	var w := PackedStringArray()
	var b := PackedStringArray()
	for n in range(1, 33):
		var s := CheckersTypes.square_from_number(n)
		var p := squares[s]
		if p == 0:
			continue
		var tok := ("K%d" % n) if CheckersTypes.ptype(p) == CheckersTypes.KING else str(n)
		if CheckersTypes.pcolor(p) == CheckersTypes.WHITE:
			w.append(tok)
		else:
			b.append(tok)
	return "%s:W%s:B%s" % ["W" if side == CheckersTypes.WHITE else "B", ",".join(w), ",".join(b)]


## Legacy v1 board dump (kept for tooling / debugging).
static func dump_legacy(squares: PackedInt32Array, side: int, halfmove: int, fullmove: int) -> String:
	var rows := PackedStringArray()
	for rank in range(7, -1, -1):
		var empty := 0
		var row := ""
		for file in 8:
			var p := squares[CheckersTypes.sq(file, rank)]
			if p == 0:
				empty += 1
			else:
				if empty > 0:
					row += str(empty)
					empty = 0
				row += CheckersTypes.piece_char(p)
		if empty > 0:
			row += str(empty)
		rows.append(row)
	return "%s %s - %d %d" % ["/".join(rows), "w" if side == CheckersTypes.WHITE else "b", halfmove, fullmove]


static func parse(fen: String) -> Dictionary:
	var text := fen.strip_edges()
	if text.begins_with("\"") and text.ends_with("\"") and text.length() >= 2:
		text = text.substr(1, text.length() - 2).strip_edges()
	if text.is_empty():
		return _fail("empty FEN")
	if text.contains("/"):
		return _parse_legacy(text)
	return _parse_pdn(text)


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


static func _empty_board() -> PackedInt32Array:
	var b := PackedInt32Array()
	b.resize(64)
	return b


static func _parse_pdn(text: String) -> Dictionary:
	var t := text
	while t.ends_with("."):
		t = t.substr(0, t.length() - 1)
	var parts := t.split(":")
	if parts.size() < 1:
		return _fail("missing side to move")
	var head := parts[0].strip_edges().to_upper()
	var side := -1
	if head == "W":
		side = CheckersTypes.WHITE
	elif head == "B":
		side = CheckersTypes.BLACK
	else:
		return _fail("bad side to move '%s'" % parts[0])
	var squares := _empty_board()
	var halfmove := 0
	var fullmove := 1
	var seen_color := [false, false]
	for i in range(1, parts.size()):
		var tok := parts[i].strip_edges()
		if tok.is_empty():
			continue
		var c0 := tok.substr(0, 1).to_upper()
		if c0 == "H" and tok.substr(1).is_valid_int():
			halfmove = maxi(int(tok.substr(1)), 0)
			continue
		if c0 == "F" and tok.substr(1).is_valid_int():
			fullmove = maxi(int(tok.substr(1)), 1)
			continue
		var color := -1
		if c0 == "W":
			color = CheckersTypes.WHITE
		elif c0 == "B":
			color = CheckersTypes.BLACK
		else:
			return _fail("bad piece list '%s'" % tok)
		if seen_color[color]:
			return _fail("duplicate %s list" % CheckersTypes.side_name(color))
		seen_color[color] = true
		var list := tok.substr(1).strip_edges()
		if list.is_empty():
			continue
		for raw in list.split(","):
			var item := raw.strip_edges()
			if item.is_empty():
				continue
			var king := false
			if item.substr(0, 1).to_upper() == "K":
				king = true
				item = item.substr(1).strip_edges()
			var sqs := _parse_items(item)
			if sqs.is_empty():
				return _fail("bad square '%s'" % raw)
			for s in sqs:
				if squares[s] != 0:
					return _fail("square %s listed twice" % CheckersTypes.algebraic(s))
				squares[s] = CheckersTypes.pack(CheckersTypes.KING if king else CheckersTypes.MAN, color)
	return {
		"ok": true,
		"error": "",
		"squares": squares,
		"side": side,
		"halfmove": halfmove,
		"fullmove": fullmove,
		"legacy": false,
	}


## "12" / "5-8" (range) / "c3" -> list of 64-index squares, empty on error.
static func _parse_items(item: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if item.is_valid_int():
		var s := CheckersTypes.square_from_number(int(item))
		if s >= 0:
			out.append(s)
		return out
	if item.contains("-"):
		var ab := item.split("-")
		if ab.size() == 2 and ab[0].strip_edges().is_valid_int() and ab[1].strip_edges().is_valid_int():
			var a := int(ab[0])
			var b := int(ab[1])
			if a < 1 or b > 32 or a > b:
				return PackedInt32Array()
			for n in range(a, b + 1):
				out.append(CheckersTypes.square_from_number(n))
		return out
	var lower := item.to_lower()
	if lower.length() == 2:
		var s := CheckersTypes.parse_square(lower)
		if s >= 0 and CheckersTypes.is_dark(s):
			out.append(s)
	return out


static func _parse_legacy(text: String) -> Dictionary:
	var parts := text.split(" ", false)
	if parts.size() < 2:
		return _fail("legacy FEN needs board and side")
	var ranks := parts[0].split("/")
	if ranks.size() != 8:
		return _fail("legacy FEN needs 8 ranks")
	var squares := _empty_board()
	for i in 8:
		var rank := 7 - i
		var file := 0
		var row := ranks[i]
		for j in row.length():
			var ch := row.substr(j, 1)
			if ch >= "1" and ch <= "8":
				file += int(ch)
				continue
			var packed := -1
			match ch:
				"w":
					packed = CheckersTypes.W_MAN
				"W":
					packed = CheckersTypes.W_KING
				"b":
					packed = CheckersTypes.B_MAN
				"B":
					packed = CheckersTypes.B_KING
			if packed < 0 or file > 7:
				return _fail("bad legacy rank '%s'" % row)
			var s := CheckersTypes.sq(file, rank)
			if not CheckersTypes.is_dark(s):
				return _fail("piece on light square %s" % CheckersTypes.algebraic(s))
			squares[s] = packed
			file += 1
		if file != 8:
			return _fail("legacy rank '%s' is not 8 squares" % row)
	var side_tok := parts[1].to_lower()
	if side_tok != "w" and side_tok != "b":
		return _fail("bad side to move '%s'" % parts[1])
	var halfmove := 0
	var fullmove := 1
	if parts.size() > 3 and parts[3].is_valid_int():
		halfmove = maxi(int(parts[3]), 0)
	if parts.size() > 4 and parts[4].is_valid_int():
		fullmove = maxi(int(parts[4]), 1)
	return {
		"ok": true,
		"error": "",
		"squares": squares,
		"side": CheckersTypes.WHITE if side_tok == "w" else CheckersTypes.BLACK,
		"halfmove": halfmove,
		"fullmove": fullmove,
		"legacy": true,
	}
