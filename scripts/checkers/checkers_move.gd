class_name CheckersMove
extends RefCounted

var from_sq: int = 0
var to_sq: int = 0
var piece: int = 0
var color: int = 0
var captured: int = 0
var captured_sq: int = -1
var flags: int = 0
var turn_id: int = 0
var ended_turn: bool = true
var prev_must_continue: int = -1
var prev_halfmove: int = 0
var notation: String = ""
var uci: String = ""


func is_capture() -> bool:
	return (flags & CheckersTypes.FLAG_CAPTURE) != 0


func is_promotion() -> bool:
	return (flags & CheckersTypes.FLAG_PROMO) != 0


func is_continuation() -> bool:
	return (flags & CheckersTypes.FLAG_CONTINUE) != 0


func matches(from_s: int, to_s: int) -> bool:
	return from_sq == from_s and to_sq == to_s


func to_uci() -> String:
	if not uci.is_empty():
		return uci
	uci = CheckersTypes.algebraic(from_sq) + CheckersTypes.algebraic(to_sq)
	return uci


func describe() -> String:
	if not notation.is_empty():
		return notation
	var sep := "x" if is_capture() else "-"
	return "%s%s%s" % [CheckersTypes.algebraic(from_sq), sep, CheckersTypes.algebraic(to_sq)]


func duplicate_move() -> CheckersMove:
	var m := CheckersMove.new()
	m.from_sq = from_sq
	m.to_sq = to_sq
	m.piece = piece
	m.color = color
	m.captured = captured
	m.captured_sq = captured_sq
	m.flags = flags
	m.turn_id = turn_id
	m.ended_turn = ended_turn
	m.prev_must_continue = prev_must_continue
	m.prev_halfmove = prev_halfmove
	m.notation = notation
	m.uci = uci
	return m
