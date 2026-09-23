class_name SaveManager
extends RefCounted

## JSON save games under $XDG_DATA_HOME/shadow-checkers/saves.
## Format v2 stores the variant, the start position (PDN FEN), and every full
## turn as a lossless square path, so undo, review, and PDN export survive a
## reload. v1 files (1.x, per-hop history) are migrated on read.

const FORMAT := "shadow-checkers-save"
const VERSION := 2
const AUTOSAVE := "autosave.json"


static func autosave_path() -> String:
	return SettingsStore.saves_dir().path_join(AUTOSAVE)


static func has_autosave() -> bool:
	if not FileAccess.file_exists(autosave_path()):
		return false
	var d := load_game(autosave_path())
	return not d.is_empty() and not bool(d.get("finished", false))


static func clear_autosave() -> void:
	if FileAccess.file_exists(autosave_path()):
		DirAccess.remove_absolute(autosave_path())


## `state` comes from GameController.snapshot(). Returns the written path.
static func save_game(state: Dictionary, path: String = "") -> String:
	SettingsStore.ensure_dirs()
	if path.is_empty():
		var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
		path = SettingsStore.saves_dir().path_join("game-%s.json" % stamp)
	var payload := state.duplicate(true)
	payload["format"] = FORMAT
	payload["version"] = VERSION
	payload["app_version"] = str(ProjectSettings.get_setting("application/config/version", ""))
	payload["saved_at"] = Time.get_datetime_string_from_system()
	if not payload.has("created_at"):
		payload["created_at"] = payload["saved_at"]
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		return ""
	return path


static func load_game(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return {}
	return _normalize(parsed)


static func delete_save(path: String) -> bool:
	if not path.begins_with(SettingsStore.saves_dir()):
		return false
	return DirAccess.remove_absolute(path) == OK


static func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	SettingsStore.ensure_dirs()
	var dir := DirAccess.open(SettingsStore.saves_dir())
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json") and name != AUTOSAVE:
			var path := SettingsStore.saves_dir().path_join(name)
			var data := load_game(path)
			if not data.is_empty():
				data["path"] = path
				data["file"] = name
				out.append(data)
		name = dir.get_next()
	out.sort_custom(func(a, b): return str(a.get("saved_at", "")) > str(b.get("saved_at", "")))
	return out


## Rebuilds the saved game into `engine` (variant, start position, moves).
static func apply_to_engine(engine: CheckersEngine, data: Dictionary) -> bool:
	engine.set_variant(str(data.get("variant", "english")))
	if data.has("legacy_hops"):
		return engine.replay_legacy_hops(data["legacy_hops"])
	var start := str(data.get("start_fen", ""))
	if start != "" and not engine.from_fen(start):
		return false
	for u in data.get("moves_uci", []):
		if engine.play_uci(str(u)) == null:
			return false
	return true


static func summary(data: Dictionary) -> String:
	var moves: Array = data.get("moves_uci", data.get("legacy_hops", []))
	var state := str(data.get("result", "*"))
	var status := "in progress" if state == "*" else state
	return "%s · %d turns · %s" % [CheckersRules.variant_name(str(data.get("variant", "english"))), moves.size(), status]


static func _normalize(d: Dictionary) -> Dictionary:
	if int(d.get("version", 1)) >= 2 and d.has("moves_uci"):
		return d
	# v1 (1.x): {fen, history_uci (one entry per hop), mode, ai_side, ai_difficulty, clock}
	var out := {
		"format": FORMAT,
		"version": VERSION,
		"variant": "english",
		"saved_at": str(d.get("saved_at", "")),
		"created_at": str(d.get("saved_at", "")),
		"mode": str(d.get("mode", "local")),
		"ai_side": int(d.get("ai_side", CheckersTypes.WHITE)),
		"ai_level": {"easy": "casual", "medium": "club", "hard": "advanced", "master": "master"}.get(str(d.get("ai_difficulty", "medium")), "club"),
		"white_name": str(d.get("white_name", "White")),
		"black_name": str(d.get("black_name", "Black")),
		"start_fen": "",
		"moves_uci": [],
		"result": "*",
		"finished": false,
	}
	var hops: Array = d.get("history_uci", [])
	if hops.is_empty():
		out["start_fen"] = str(d.get("fen", ""))
	else:
		out["legacy_hops"] = hops
	var clock: Dictionary = d.get("clock", {})
	out["clock"] = {
		"base": int(clock.get("white", 600)),
		"increment": 0,
		"white": float(clock.get("white", 600.0)),
		"black": float(clock.get("black", 600.0)),
		"enabled": bool(clock.get("enabled", false)),
	}
	out["title"] = "%s vs %s" % [out["white_name"], out["black_name"]]
	return out
