class_name CheckersPdn
extends RefCounted

## PDN (Portable Draughts Notation) export / import.
##
## Export writes the seven standard tags plus GameType (english "21",
## russian "25", brazilian "26") and FEN when the game did not start from the
## variant's standard position. Result uses the PDN convention: first number is
## White's score ("1-0" White won, "0-1" Black won, "1/2-1/2", "*").
##
## Import reads the first game in the text: tags, move numbers ("12." "12..."),
## comments {..} and ; to end of line, variations (..), NAGs ($n), move
## annotations (! ?) and result tokens (also the 2-0 / 0-2 / 1-1 draughts
## scoring). The variant comes from GameType (default english). The engine's
## result is what the moves produce; a decisive Result tag on an unfinished game
## is left in headers["Result"] for the caller (e.g. resignations).

const TAG_ORDER: Array[String] = ["Event", "Site", "Date", "Round", "White", "Black", "Result", "GameType"]
const RESULT_TOKENS: Array[String] = ["1-0", "0-1", "1/2-1/2", "*", "2-0", "0-2", "1-1", "0-0", "½-½"]


static func export_game(engine: CheckersEngine, headers: Dictionary = {}) -> String:
	var tags := {}
	tags["Event"] = str(headers.get("Event", "Shadow Checkers game"))
	tags["Site"] = str(headers.get("Site", "Shadow Checkers"))
	tags["Date"] = str(headers.get("Date", _today()))
	tags["Round"] = str(headers.get("Round", "-"))
	tags["White"] = str(headers.get("White", "White"))
	tags["Black"] = str(headers.get("Black", "Black"))
	tags["Result"] = engine.result_token()
	tags["GameType"] = CheckersRules.game_type(engine.variant)
	var lines := PackedStringArray()
	for t in TAG_ORDER:
		lines.append("[%s \"%s\"]" % [t, _escape(str(tags[t]))])
	var std := CheckersRules.start_fen(engine.variant)
	if engine.start_fen != std and not engine.start_fen.is_empty():
		lines.append("[FEN \"%s\"]" % _escape(engine.start_fen))
	for k in headers.keys():
		var key := str(k)
		if TAG_ORDER.has(key) or key == "FEN":
			continue
		lines.append("[%s \"%s\"]" % [key, _escape(str(headers[k]))])
	lines.append("")
	var text := engine.numbered_notation()
	text = (text + " " + engine.result_token()).strip_edges()
	lines.append(_wrap(text, 79))
	return "\n".join(lines) + "\n"


static func import_game(text: String) -> Dictionary:
	var out := {"ok": false, "error": "", "headers": {}, "engine": null}
	var headers := {}
	var body := ""
	var in_moves := false
	for raw_line in text.replace("\r", "").split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			if in_moves:
				break
			var tag := _parse_tag(line)
			if not tag.is_empty():
				headers[tag[0]] = tag[1]
			continue
		if line.is_empty():
			continue
		in_moves = true
		body += line + "\n"
	out["headers"] = headers
	var variant := "english"
	if headers.has("GameType"):
		variant = CheckersRules.variant_from_game_type(str(headers["GameType"]))
		if variant.is_empty():
			out["error"] = "unsupported GameType %s" % str(headers["GameType"])
			return out
	var engine := CheckersEngine.new(variant)
	if headers.has("FEN") and not str(headers["FEN"]).strip_edges().is_empty():
		if not engine.from_fen(str(headers["FEN"])):
			out["error"] = "bad FEN tag"
			return out
	var tokens := _tokenize(body)
	var ply := 0
	for tok in tokens:
		if RESULT_TOKENS.has(tok):
			break
		var m := engine.find_uci(tok)
		if m == null or engine.apply_move(m) == null:
			out["error"] = "illegal or unknown move '%s' at ply %d" % [tok, ply + 1]
			out["engine"] = engine
			return out
		ply += 1
	out["ok"] = true
	out["engine"] = engine
	return out


static func _tokenize(body: String) -> PackedStringArray:
	# Strip comments and variations first.
	var clean := ""
	var depth_brace := 0
	var depth_paren := 0
	var line_comment := false
	for i in body.length():
		var c := body.substr(i, 1)
		if line_comment:
			if c == "\n":
				line_comment = false
				clean += " "
			continue
		if depth_brace > 0:
			if c == "}":
				depth_brace -= 1
			continue
		if c == "{":
			depth_brace += 1
			continue
		if c == ";" and depth_paren == 0:
			line_comment = true
			continue
		if c == "(":
			depth_paren += 1
			continue
		if c == ")":
			depth_paren = maxi(depth_paren - 1, 0)
			continue
		if depth_paren > 0:
			continue
		clean += c
	var out := PackedStringArray()
	for raw in clean.replace("\n", " ").replace("\t", " ").split(" ", false):
		var tok := raw.strip_edges()
		if tok.is_empty() or tok.begins_with("$"):
			continue
		if RESULT_TOKENS.has(tok):
			out.append(tok)
			continue
		# Move numbers: "12." "12..." or glued "12.11-15".
		var dot := tok.find(".")
		if dot > 0 and tok.substr(0, dot).is_valid_int():
			var rest := tok.substr(dot).lstrip(".")
			if rest.is_empty():
				continue
			tok = rest
		tok = tok.rstrip("!?")
		if tok.is_empty():
			continue
		out.append(tok)
	return out


static func _parse_tag(line: String) -> Array:
	var inner := line.substr(1, line.length() - 2).strip_edges()
	var sp := inner.find(" ")
	if sp <= 0:
		return []
	var name := inner.substr(0, sp)
	var val := inner.substr(sp + 1).strip_edges()
	if val.begins_with("\"") and val.ends_with("\"") and val.length() >= 2:
		val = val.substr(1, val.length() - 2)
	val = val.replace("\\\"", "\"").replace("\\\\", "\\")
	return [name, val]


static func _escape(s: String) -> String:
	return s.replace("\\", "\\\\").replace("\"", "\\\"")


static func _today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d.%02d.%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


static func _wrap(text: String, width: int) -> String:
	var lines := PackedStringArray()
	var cur := ""
	for w in text.split(" ", false):
		if cur.is_empty():
			cur = w
		elif cur.length() + 1 + w.length() > width:
			lines.append(cur)
			cur = w
		else:
			cur += " " + w
	if not cur.is_empty():
		lines.append(cur)
	return "\n".join(lines)
