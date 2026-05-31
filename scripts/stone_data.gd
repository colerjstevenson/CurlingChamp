extends RefCounted
class_name Stone

var name: String
var color: String
var age: int
var wins: int

var power: int
var spin: int
var precision: int
var condition: int


func _init(
	stone_name: String = "",
	stone_color: String = "red",
	stone_power: int = 0,
	stone_spin: int = 0,
	stone_precision: int = 0,
	stone_condition: int = 0,
	stone_age: int = 1,
	stone_wins: int = 0
) -> void:
	name = stone_name
	color = stone_color
	power = _clamp_stat(stone_power)
	spin = _clamp_stat(stone_spin)
	precision = _clamp_stat(stone_precision)
	condition = _clamp_stat(stone_condition)
	age = max(stone_age, 0)
	wins = max(stone_wins, 0)


func add_win() -> void:
	wins += 1


func set_condition(new_condition: int) -> void:
	condition = _clamp_stat(new_condition)


func _clamp_stat(value: int) -> int:
	return clampi(value, 0, 100)
