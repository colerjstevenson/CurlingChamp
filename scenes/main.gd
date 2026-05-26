extends Node2D

const STONE_SCENE := preload("res://scenes/Stone.tscn")
const PLAYER_COLORS := ["blue", "red"]
const STONES_GROUP := "stones"

@export var stones_per_player := 5
@export var stone_spawn_position := Vector2(360.0, 1150.0)
@export var settled_speed_threshold := 8.0
@export var settled_frames_required := 5
@export var red_line_y := -1253.0
@export var rink_end_y := -2525.0

@onready var camera: Camera2D = $Camera2D

var current_player_index := 0
var throws_by_color := {
	"blue": 0,
	"red": 0,
}
var active_stone: RigidBody2D


func _ready() -> void:
	if has_node("walls"):
		$walls.add_to_group("side_walls")
	_spawn_next_stone()


func _spawn_next_stone() -> void:
	if _match_finished():
		active_stone = null
		return

	var color: String = PLAYER_COLORS[current_player_index]
	var stone := STONE_SCENE.instantiate() as RigidBody2D
	stone.position = stone_spawn_position
	add_child(stone)
	stone.add_to_group(STONES_GROUP)

	if stone.has_method("set_stone_color"):
		stone.set_stone_color(color)

	stone.stone_stopped.connect(_on_stone_stopped)
	active_stone = stone

	if camera.has_method("set_target"):
		camera.set_target(stone)


func _on_stone_stopped(stone: RigidBody2D) -> void:
	if stone != active_stone:
		return

	var color: String = PLAYER_COLORS[current_player_index]
	throws_by_color[color] += 1
	current_player_index = 1 - current_player_index

	await _wait_for_all_stones_to_settle()
	_prune_out_of_play_stones()

	if _match_finished():
		active_stone = null
		return

	_spawn_next_stone()


func _match_finished() -> bool:
	return throws_by_color["blue"] >= stones_per_player and throws_by_color["red"] >= stones_per_player


func _wait_for_all_stones_to_settle() -> void:
	var settled_frames := 0
	while settled_frames < settled_frames_required:
		await get_tree().physics_frame
		if _all_stones_settled():
			settled_frames += 1
		else:
			settled_frames = 0


func _all_stones_settled() -> bool:
	for node in get_tree().get_nodes_in_group(STONES_GROUP):
		if not is_instance_valid(node):
			continue

		var stone := node as RigidBody2D
		if stone == null:
			continue

		if stone.linear_velocity.length() > settled_speed_threshold:
			return false

	return true


func _prune_out_of_play_stones() -> void:
	for node in get_tree().get_nodes_in_group(STONES_GROUP):
		if not is_instance_valid(node):
			continue

		var stone := node as RigidBody2D
		if stone == null:
			continue

		if stone.has_method("should_remove_on_reset") and stone.should_remove_on_reset(red_line_y, rink_end_y):
			stone.queue_free()
