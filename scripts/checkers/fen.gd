class_name CheckersFen
extends RefCounted


static func dump(engine: CheckersEngine) -> String:
	var rows: PackedStringArray = PackedStringArray()
	for rank in range(7, -1, -1):
		var empty := 0
		var row := ""
		for file in 8:
			var p := engine.squares[CheckersTypes.sq(file, rank)]
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
	var board := "/".join(rows)
	var stm := "w" if engine.side_to_move == CheckersTypes.WHITE else "b"
	var cont := CheckersTypes.algebraic(engine.must_continue_sq) if engine.must_continue_sq >= 0 else "-"
	return "%s %s %s %d %d" % [board, stm, cont, engine.halfmove, engine.fullmove]


static func parse(engine: CheckersEngine, fen: String) -> bool:
	var parts := fen.strip_edges().split(" ")
	if parts.size() < 2:
		return false
	engine.clear()
	var ranks := parts[0].split("/")
	if ranks.size() != 8:
		return false
	for i in 8:
		var rank := 7 - i
		var file := 0
		for j in ranks[i].length():
			var ch := ranks[i].substr(j, 1)
			if ch >= "1" and ch <= "8":
				file += int(ch)
			else:
				var packed := _parse_piece(ch)
				if packed < 0 or file > 7:
					return false
				engine.squares[CheckersTypes.sq(file, rank)] = packed
				file += 1
		if file != 8:
			return false
	engine.side_to_move = CheckersTypes.WHITE if parts[1] == "w" else CheckersTypes.BLACK
	engine.must_continue_sq = -1
	if parts.size() > 2 and parts[2] != "-":
		engine.must_continue_sq = CheckersTypes.parse_square(parts[2])
	engine.halfmove = int(parts[3]) if parts.size() > 3 else 0
	engine.fullmove = int(parts[4]) if parts.size() > 4 else 1
	engine.result = CheckersEngine.Result.NONE
	engine.next_turn_id = 1
	return true


static func _parse_piece(ch: String) -> int:
	match ch:
		"w":
			return CheckersTypes.pack(CheckersTypes.MAN, CheckersTypes.WHITE)
		"W":
			return CheckersTypes.pack(CheckersTypes.KING, CheckersTypes.WHITE)
		"b":
			return CheckersTypes.pack(CheckersTypes.MAN, CheckersTypes.BLACK)
		"B":
			return CheckersTypes.pack(CheckersTypes.KING, CheckersTypes.BLACK)
		_:
			return -1
