extends RefCounted

## Tiny assertion helper shared by the headless suites.

var suite_name := "suite"
var passed := 0
var failed := 0
var errors: PackedStringArray = PackedStringArray()


func run_all() -> bool:
	return true


func section(title: String) -> void:
	print("[%s] %s" % [suite_name, title])


func ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  ok    ", name)
	else:
		failed += 1
		var msg := name if detail.is_empty() else "%s — %s" % [name, detail]
		errors.append("[%s] %s" % [suite_name, msg])
		print("  FAIL  ", msg)


func eq(name: String, got: Variant, want: Variant) -> void:
	ok(name, got == want, "got %s, want %s" % [str(got), str(want)])


# ---------------------------------------------------------------- helpers ----

func sqa(alg: String) -> int:
	return CheckersTypes.parse_square(alg)


## Build a PackedInt32Array path from algebraic squares: p("c5", "e3", "g1").
func p(a: String, b: String = "", c: String = "", d: String = "", e: String = "", f: String = "") -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in [a, b, c, d, e, f]:
		if not s.is_empty():
			out.append(CheckersTypes.parse_square(s))
	return out


func pos(variant: String, fen: String) -> CheckersEngine:
	var e := CheckersEngine.new(variant)
	var loaded := e.from_fen(fen)
	if not loaded:
		ok("fixture FEN parses: %s" % fen, false)
	return e


func ucis(e: CheckersEngine) -> PackedStringArray:
	var out := PackedStringArray()
	for m in e.generate_legal_moves():
		out.append(m.to_uci())
	out.sort()
	return out


func has(e: CheckersEngine, uci: String) -> bool:
	for m in e.generate_legal_moves():
		if m.to_uci() == uci:
			return true
	return false


func count(e: CheckersEngine) -> int:
	return e.generate_legal_moves().size()


func count_from(e: CheckersEngine, alg: String) -> int:
	return e.legal_from(sqa(alg)).size()


func play(e: CheckersEngine, uci: String) -> CheckersMove:
	var m := e.find_uci(uci)
	if m == null:
		return null
	return e.apply_move(m)


func sorted_ints(a: PackedInt32Array) -> PackedInt32Array:
	var b := a.duplicate()
	b.sort()
	return b
