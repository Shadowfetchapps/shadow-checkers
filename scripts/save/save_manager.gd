class_name SaveManager
extends RefCounted


static func save_game(engine: CheckersEngine, extra: Dictionary = {}) -> String:
	SettingsStore.ensure_dirs()
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	var path := SettingsStore.saves_dir().path_join("game-%s.json" % stamp)
	var ucis: Array = []
	for m in engine.history:
		ucis.append(m.to_uci())
	var payload := {
		"version": 1,
		"game": "shadow-checkers",
		"saved_at": Time.get_datetime_string_from_system(),
		"fen": engine.to_fen(),
		"history_uci": ucis,
		"notation": engine.numbered_notation(),
		"mode": extra.get("mode", "local"),
		"ai_side": extra.get("ai_side", 0),
		"ai_difficulty": extra.get("ai_difficulty", SettingsStore.ai_difficulty),
		"clock": extra.get("clock", {}),
		"settings": SettingsStore.to_dict(),
		"white_name": extra.get("white_name", "White"),
		"black_name": extra.get("black_name", "Black"),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(payload, "\t"))
	return path


static func load_game(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


static func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	SettingsStore.ensure_dirs()
	var dir := DirAccess.open(SettingsStore.saves_dir())
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			var path := SettingsStore.saves_dir().path_join(name)
			var data := load_game(path)
			out.append({
				"path": path,
				"name": name,
				"saved_at": str(data.get("saved_at", "")),
				"fen": str(data.get("fen", "")),
				"mode": str(data.get("mode", "local")),
			})
		name = dir.get_next()
	out.sort_custom(func(a, b): return str(a.get("saved_at", "")) > str(b.get("saved_at", "")))
	return out


static func apply_to_engine(engine: CheckersEngine, data: Dictionary) -> bool:
	var ucis: Array = data.get("history_uci", [])
	if ucis.is_empty():
		var fen := str(data.get("fen", ""))
		if fen.is_empty():
			return false
		return engine.from_fen(fen)
	engine.reset()
	for i in ucis.size():
		var u := str(ucis[i])
		if u.length() < 4:
			return false
		var m := engine.play(CheckersTypes.parse_square(u.substr(0, 2)), CheckersTypes.parse_square(u.substr(2, 2)))
		if m == null:
			return false
	return true
