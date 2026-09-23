class_name TestPresentation
extends RefCounted

## Headless checks for the presentation layer: shared materials and theme
## switching, disc construction, settings migration and validation, save
## migration (including 1.x per-hop saves), rating maths, and UI blocks.

var _passed := 0
var _failed := 0
var _errors: PackedStringArray = PackedStringArray()


func run_all() -> bool:
	_passed = 0
	_failed = 0
	_errors.clear()
	print("presentation")
	_materials()
	_theme_switch()
	_discs()
	_settings()
	_saves()
	_legacy_save()
	_rating()
	_ui()
	print("\n==============================")
	print("Shadow Checkers presentation  —  %d passed, %d failed" % [_passed, _failed])
	for e in _errors:
		print("  FAIL  ", e)
	print("==============================\n")
	return _failed == 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ok    ", name)
	else:
		_failed += 1
		var msg := name if detail.is_empty() else "%s — %s" % [name, detail]
		_errors.append(msg)
		print("  FAIL  ", msg)


func _materials() -> void:
	MaterialLibrary.ensure()
	_ok("white body", MaterialLibrary.piece_body(CheckersTypes.WHITE) == MaterialLibrary.piece_white)
	_ok("black trim", MaterialLibrary.piece_trim(CheckersTypes.BLACK) == MaterialLibrary.trim_black)
	_ok("movable mark", MaterialLibrary.mark_movable != null and MaterialLibrary.mark_path != null)
	_ok("square variants", MaterialLibrary.dark_sq.size() == MaterialLibrary.SQUARE_VARIANTS)


func _theme_switch() -> void:
	var body := MaterialLibrary.piece_white
	for t in MaterialLibrary.BOARD_THEMES:
		for p in MaterialLibrary.PIECE_STYLES:
			MaterialLibrary.apply_theme(t, p)
	_ok("theme switch keeps identity", MaterialLibrary.piece_white == body)
	MaterialLibrary.apply_theme("classic", "classic")
	_ok("classic style names Red", MaterialLibrary.side_label(CheckersTypes.WHITE) == "Red" and MaterialLibrary.side_label(CheckersTypes.BLACK) == "Black")
	MaterialLibrary.apply_theme("club", "club")
	_ok("club style names White", MaterialLibrary.side_label(CheckersTypes.WHITE) == "White")
	MaterialLibrary.apply_theme("bogus", "bogus")
	_ok("unknown theme falls back", MaterialLibrary.current_board == "club" and MaterialLibrary.current_pieces == "club")


func _discs() -> void:
	var man := PieceMeshBuilder.height_of(CheckersTypes.MAN)
	var king := PieceMeshBuilder.height_of(CheckersTypes.KING)
	_ok("man height sane", man > 0.08 and man < 0.3, str(man))
	_ok("king taller than man", king > man * 1.6, "%f vs %f" % [king, man])
	_ok("disc radius fits a square", PieceMeshBuilder.radius_of(CheckersTypes.MAN) < 0.48)
	var a := PieceMeshBuilder.build(CheckersTypes.MAN, CheckersTypes.WHITE)
	var b := PieceMeshBuilder.build(CheckersTypes.MAN, CheckersTypes.BLACK)
	var ma := a.get_node("Mesh") as MeshInstance3D
	var mb := b.get_node("Mesh") as MeshInstance3D
	_ok("men share one mesh", ma.mesh == mb.mesh)
	_ok("colours differ", ma.get_surface_override_material(0) != mb.get_surface_override_material(0))
	var roles := {}
	for i in ma.mesh.get_surface_count():
		roles[PieceMeshBuilder.surface_role(ma.mesh, i)] = true
	_ok("disc has body and trim", roles.has("body") and roles.has("trim"))
	a.free()
	b.free()


func _settings() -> void:
	var s = load("res://scripts/save/settings_store.gd").new()
	s.from_dict({"fullscreen": true, "sound_volume": 0.5, "ai_difficulty": "easy", "clock_seconds": 900})
	_ok("1.x fullscreen", s.window_mode == "fullscreen")
	_ok("1.x difficulty", s.ai_level == "casual")
	_ok("1.x clock", s.clock_preset == "15+0" or s.clock_preset == "10+0")
	s.from_dict({"schema": 3, "variant": "martian", "board_theme": "plaid", "piece_style": "nope"})
	_ok("bad variant rejected", s.variant == "english")
	_ok("bad board rejected", s.board_theme == "club")
	var rt = load("res://scripts/save/settings_store.gd").new()
	rt.from_dict(s.to_dict())
	_ok("settings round trip", rt.to_dict() == s.to_dict())
	s.free()
	rt.free()


func _saves() -> void:
	var e := CheckersEngine.new("russian")
	var m := e.generate_legal_moves()[0]
	e.apply_move(m)
	var data := {"version": 2, "variant": "russian", "start_fen": "", "moves_uci": [m.to_uci()]}
	var e2 := CheckersEngine.new()
	_ok("v2 save replays", SaveManager.apply_to_engine(e2, data) and e2.variant == "russian" and e2.history.size() == 1)
	var bad := {"version": 2, "variant": "english", "start_fen": "", "moves_uci": ["a1h8"]}
	_ok("illegal save rejected", not SaveManager.apply_to_engine(CheckersEngine.new(), bad))


func _legacy_save() -> void:
	# A 1.x save stored one entry per hop from the English start position.
	var e := CheckersEngine.new("english")
	var hops: Array = []
	for i in 6:
		var legal := e.generate_legal_moves()
		var mv: CheckersMove = legal[0]
		for k in mv.path.size() - 1:
			hops.append(CheckersTypes.algebraic(mv.path[k]) + CheckersTypes.algebraic(mv.path[k + 1]))
		e.apply_move(mv)
	var n := SaveManager._normalize({"version": 1, "history_uci": hops, "mode": "ai", "ai_side": 0, "ai_difficulty": "hard"})
	_ok("v1 keeps hop list", n.has("legacy_hops"))
	_ok("v1 level mapped", str(n["ai_level"]) == "advanced")
	var e2 := CheckersEngine.new()
	_ok("v1 hops replay", SaveManager.apply_to_engine(e2, n) and e2.history.size() == 6 and e2.to_fen() == e.to_fen())


func _rating() -> void:
	var p = load("res://scripts/save/profile_store.gd").new()
	p.levels = {"english:club": {"w": 1, "d": 1, "l": 0}, "russian:master": {"w": 0, "d": 0, "l": 2}}
	var t: Dictionary = p.totals()
	_ok("totals across variants", t["games"] == 4 and t["w"] == 1 and t["l"] == 2)
	p.free()


func _ui() -> void:
	var th := ThemeFactory.make()
	for v in ["PrimaryButton", "GhostButton", "IconButton", "ChipButton", "MoveButton", "MainMenuButton"]:
		_ok("button variation %s" % v, th.get_type_variation_base(v) == "Button")
	_ok("crown icon", IconLibrary.get_icon("crown", 20).get_width() == 40)
	_ok("clock format", UIKit.format_clock(61.0) == "1:01")
