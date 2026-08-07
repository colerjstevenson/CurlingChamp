extends Node2D

const TRAINING_STATS := ["Speed", "Precision", "Spin"]
const TRAINING_GAME_SCENE := preload("res://scenes/TrainingGame.tscn")

@onready var stat_label: RichTextLabel = $StatSelector/RichTextLabel
@onready var rock_selector: Control = $RockPanel/RockSelector
@onready var rock_left_arrow: TextureButton = $RockPanel/RockSelector/LeftArrow2
@onready var rock_right_arrow: TextureButton = $RockPanel/RockSelector/RightArrow2
@onready var start_button: TextureButton = $RockPanel/StartButton
@onready var comeback_panel: CanvasLayer = $RockPanel

var _selected_stat_index := 0
var _selected_rock_index := 0
var _player_stones: Array[Stone] = []


func _ready() -> void:
	_load_player_stones()
	_refresh_stat_label()
	_refresh_rock_card()
	_refresh_rock_arrow_state()
	_refresh_weekly_lock()


func _on_stat_left_pressed() -> void:
	if TRAINING_STATS.is_empty():
		return
	_selected_stat_index = posmod(_selected_stat_index - 1, TRAINING_STATS.size())
	_refresh_stat_label()


func _on_stat_right_pressed() -> void:
	if TRAINING_STATS.is_empty():
		return
	_selected_stat_index = posmod(_selected_stat_index + 1, TRAINING_STATS.size())
	_refresh_stat_label()


func _on_rock_left_pressed() -> void:
	if _player_stones.is_empty():
		return
	_selected_rock_index = posmod(_selected_rock_index - 1, _player_stones.size())
	_refresh_rock_card()


func _on_rock_right_pressed() -> void:
	if _player_stones.is_empty():
		return
	_selected_rock_index = posmod(_selected_rock_index + 1, _player_stones.size())
	_refresh_rock_card()


func _start_pressed() -> void:
	var manager := get_node_or_null("/root/game_manager")
	if manager == null:
		return

	# Guard: only one training session per week.
	if manager.has_method("is_training_available") and not manager.is_training_available():
		return

	manager.set_meta("trainer_selected_stat", TRAINING_STATS[_selected_stat_index])
	if not _player_stones.is_empty() and _selected_rock_index < _player_stones.size():
		manager.set_meta("trainer_selected_rock_index", _selected_rock_index)
		manager.set_meta("trainer_selected_rock_name", _player_stones[_selected_rock_index].name)

	get_tree().change_scene_to_packed(TRAINING_GAME_SCENE)


func _load_player_stones() -> void:
	_player_stones.clear()
	var manager := get_node_or_null("/root/game_manager")
	if manager == null or not manager.has_method("get_player_stones"):
		return

	_player_stones = manager.get_player_stones()
	_selected_rock_index = clampi(_selected_rock_index, 0, max(_player_stones.size() - 1, 0))


func _refresh_stat_label() -> void:
	if not is_instance_valid(stat_label):
		return
	if TRAINING_STATS.is_empty():
		stat_label.text = "[center]N/A[/center]"
		return

	stat_label.text = "[center]%s[/center]" % TRAINING_STATS[_selected_stat_index]


func _refresh_rock_card() -> void:
	if not is_instance_valid(rock_selector):
		return
	if _player_stones.is_empty():
		return
	if not rock_selector.has_method("setup_from_stone"):
		return

	rock_selector.call("setup_from_stone", _player_stones[_selected_rock_index])


func _refresh_rock_arrow_state() -> void:
	var has_multiple_rocks := _player_stones.size() > 1
	if is_instance_valid(rock_left_arrow):
		rock_left_arrow.disabled = not has_multiple_rocks
	if is_instance_valid(rock_right_arrow):
		rock_right_arrow.disabled = not has_multiple_rocks


func _refresh_weekly_lock() -> void:
	var manager := get_node_or_null("/root/game_manager")
	var available := true
	if manager != null and manager.has_method("is_training_available"):
		available = manager.is_training_available()

	if is_instance_valid(start_button):
		start_button.disabled = not available
	if is_instance_valid(comeback_panel):
		comeback_panel.visible = available
