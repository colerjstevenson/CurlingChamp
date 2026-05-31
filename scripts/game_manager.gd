extends Node

signal state_changed

const Stone = preload("res://scripts/stone_data.gd")
const ROCK_NAMES_PATH := "res://lists/rockNames.txt"
const STARTING_STONE_COUNT := 4
const STONE_COLORS := ["red", "blue", "yellow"]

var player_name: String = "John Smith"

var week: int = 1
var year: int = 1
var money: int = 100
var player_stones: Array[Stone] = []


func _ready() -> void:
	randomize()
	_ensure_starting_stones()


func set_week(new_week: int) -> void:
	week = max(new_week, 1)
	emit_signal("state_changed")


func set_year(new_year: int) -> void:
	year = max(new_year, 1)
	emit_signal("state_changed")


func set_money(new_money: int) -> void:
	money = new_money
	emit_signal("state_changed")


func set_date(new_year: int, new_week: int) -> void:
	year = max(new_year, 1)
	week = max(new_week, 1)
	emit_signal("state_changed")


func add_money(amount: int) -> void:
	money += amount
	emit_signal("state_changed")


func get_date_text() -> String:
	return "Year %d Week %d" % [year, week]


func get_money_text() -> String:
	return "$%d" % money


func get_player_stones() -> Array[Stone]:
	return player_stones


func _ensure_starting_stones() -> void:
	if not player_stones.is_empty():
		return

	var names := _load_rock_names()
	var used_names: Dictionary = {}

	for i in range(STARTING_STONE_COUNT):
		var stone_name := _pick_random_name(names, used_names, i)
		used_names[stone_name] = true
		var stone_color := _pick_random_stone_color()

		var new_stone: Stone = Stone.new(
			stone_name,
			stone_color,
			_roll_stat(),
			_roll_stat(),
			_roll_stat(),
			_roll_stat(),
			randi_range(1, 10),
			0
		)
		player_stones.append(new_stone)

	emit_signal("state_changed")


func _load_rock_names() -> Array[String]:
	if not FileAccess.file_exists(ROCK_NAMES_PATH):
		return []

	var file := FileAccess.open(ROCK_NAMES_PATH, FileAccess.READ)
	if file == null:
		return []

	var names: Array[String] = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line != "":
			names.append(line)

	return names


func _pick_random_name(names: Array[String], used_names: Dictionary, index: int) -> String:
	if names.is_empty():
		return "Stone %d" % [index + 1]

	var available_names: Array[String] = []
	for candidate in names:
		if not used_names.has(candidate):
			available_names.append(candidate)

	if available_names.is_empty():
		return names[randi() % names.size()]

	return available_names[randi() % available_names.size()]


func _roll_stat() -> int:
	return randi_range(0, 100)


func _pick_random_stone_color() -> String:
	return STONE_COLORS[randi() % STONE_COLORS.size()]
