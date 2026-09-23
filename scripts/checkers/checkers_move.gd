class_name CheckersMove
extends RefCounted

## One complete turn: a quiet step/slide, or a full capture sequence.
##
## path      [from, landing1, landing2, ...] (always at least 2 squares; a king
##           loop may end on its own origin square).
## captures  captured squares in capture order (empty for quiet moves).

var path: PackedInt32Array = PackedInt32Array()
var captures: PackedInt32Array = PackedInt32Array()
var captured_pieces: PackedInt32Array = PackedInt32Array()
## Piece TYPE before the move (CheckersTypes.MAN / KING).
var piece: int = 0
var color: int = 0
## True when a man ends the move as a king.
var promotes: bool = false
## Index into path where crowning happened (Russian mid-capture), else the last
## index for an ordinary crowning, or -1.
var promote_index: int = -1
## Display notation for the variant (set by the engine on apply / generation).
var notation: String = ""

## Private: compact search key (see CheckersTypes.KEY_*), undo bookkeeping.
var _key: int = 0
var prev_halfmove: int = 0
var _uci: String = ""


func from_sq() -> int:
	return path[0] if path.size() > 0 else -1


func to_sq() -> int:
	return path[path.size() - 1] if path.size() > 0 else -1


func is_capture() -> bool:
	return captures.size() > 0


func capture_count() -> int:
	return captures.size()


## v1 compatibility helper.
func is_promotion() -> bool:
	return promotes


## Concatenated algebraic path: "c3d4", "c3e5g7". Lossless; used by saves.
func to_uci() -> String:
	if _uci.is_empty():
		var s := ""
		for q in path:
			s += CheckersTypes.algebraic(q)
		_uci = s
	return _uci


func search_key() -> int:
	return _key


func same_path(p: PackedInt32Array) -> bool:
	if p.size() != path.size():
		return false
	for i in p.size():
		if p[i] != path[i]:
			return false
	return true


func starts_with(prefix: PackedInt32Array) -> bool:
	if prefix.size() > path.size():
		return false
	for i in prefix.size():
		if prefix[i] != path[i]:
			return false
	return true


func describe() -> String:
	if not notation.is_empty():
		return notation
	var sep := ":" if is_capture() else "-"
	var bits := PackedStringArray()
	for q in path:
		bits.append(CheckersTypes.algebraic(q))
	return sep.join(bits)


func duplicate_move() -> CheckersMove:
	var m := CheckersMove.new()
	m.path = path.duplicate()
	m.captures = captures.duplicate()
	m.captured_pieces = captured_pieces.duplicate()
	m.piece = piece
	m.color = color
	m.promotes = promotes
	m.promote_index = promote_index
	m.notation = notation
	m._key = _key
	m.prev_halfmove = prev_halfmove
	m._uci = _uci
	return m
