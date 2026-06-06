extends RefCounted
class_name Stone

const MIN_VARIANT := 1
const MAX_VARIANT := 51

var name: String
var age: int
var wins: int
var variant: int

var power: int
var spin: int
var precision: int
var condition: int
var power_potential: int
var spin_potential: int
var precision_potential: int


func _init(
	stone_name: String = "",
	stone_power: int = 0,
	stone_spin: int = 0,
	stone_precision: int = 0,
	stone_condition: int = 0,
	stone_age: int = 1,
	stone_wins: int = 0,
	stone_variant: int = 1,
	stone_power_potential: int = 100,
	stone_spin_potential: int = 100,
	stone_precision_potential: int = 100
) -> void:
	name = stone_name
	power_potential = _clamp_potential(stone_power_potential)
	spin_potential = _clamp_potential(stone_spin_potential)
	precision_potential = _clamp_potential(stone_precision_potential)
	power = mini(_clamp_stat(stone_power), power_potential)
	spin = mini(_clamp_stat(stone_spin), spin_potential)
	precision = mini(_clamp_stat(stone_precision), precision_potential)
	condition = _clamp_stat(stone_condition)
	age = max(stone_age, 0)
	wins = max(stone_wins, 0)
	variant = _clamp_variant(stone_variant)


func add_win() -> void:
	wins += 1


func set_condition(new_condition: int) -> void:
	condition = _clamp_stat(new_condition)


func set_power(new_power: int) -> void:
	power = mini(_clamp_stat(new_power), power_potential)


func set_spin(new_spin: int) -> void:
	spin = mini(_clamp_stat(new_spin), spin_potential)


func set_precision(new_precision: int) -> void:
	precision = mini(_clamp_stat(new_precision), precision_potential)


func _clamp_stat(value: int) -> int:
	return clampi(value, 0, 100)


func _clamp_potential(value: int) -> int:
	return clampi(value, 1, 100)


func _clamp_variant(value: int) -> int:
	return clampi(value, MIN_VARIANT, MAX_VARIANT)
