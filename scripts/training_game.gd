extends Node2D

## Training minigame controller.
## Spawns preset opponent stones, lets the player throw 5 shots, scores the result,
## then returns to the trainer scene and applies the stat boost.

signal training_complete(stat: String, score: int)

const STONE_SCENE := preload("res://scenes/Stone.tscn")
const STONES_GROUP := "stones"
const TRAINING_SHOTS := 5

## Set by trainer_menu before changing scene.
@export var training_stat: String = "Speed"
@export var training_rock_index: int = 0

@export var human_player_color := "yellow"
@export var opponent_color := "red"
@export var stone_spawn_position := Vector2(360.0, 1000.0)
@export var settled_speed_threshold := 8.0
@export var settled_frames_required := 5
@export var rink_end_y := -70
@export var camera_overview_position := Vector2(360.0, 640.0)
@export var camera_overview_zoom := Vector2(1.0, 1.0)
@export var camera_follow_zoom := Vector2(1.5, 1.5)
@export var camera_follow_lerp_speed := 6.0
@export var camera_overview_delay := 0.25

## House position and radius — read from scene nodes in _ready().
var house_center := Vector2(360.0, 64.0)
var house_radius := 111.0
## Distance to the guard zone centre (pixels above the house).
var guard_zone_y := -120.0

var _shots_taken := 0
var _total_score := 0
var _active_stone: RigidBody2D = null
var _followed_stone: RigidBody2D = null

@onready var camera: Camera2D = $Camera2D
@onready var scratch_line: Line2D = $house/scratchline
@onready var score_label: RichTextLabel = $CanvasLayer/ScoreLabel
@onready var shot_label: RichTextLabel = $CanvasLayer/ShotLabel
@onready var result_label: Label = $CanvasLayer/ResultLabel


func _ready() -> void:
	randomize()
	house_center = $house.position
	house_radius = $house/houseArea.shape.radius
	guard_zone_y = house_center.y + house_radius + 80.0

	# Read training params written by trainer_menu into game_manager metadata.
	var manager := get_node_or_null("/root/game_manager")
	if manager != null:
		if manager.has_meta("trainer_selected_stat"):
			training_stat = String(manager.get_meta("trainer_selected_stat"))
		if manager.has_meta("trainer_selected_rock_index"):
			training_rock_index = int(manager.get_meta("trainer_selected_rock_index"))

	if is_instance_valid(result_label):
		result_label.visible = false

	if is_instance_valid(camera):
		camera.global_position = camera_overview_position
		camera.zoom = camera_overview_zoom

	_update_hud()
	_start_next_shot()


func _process(delta: float) -> void:
	if not is_instance_valid(camera):
		return
	if not is_instance_valid(_followed_stone):
		return

	var weight := clampf(delta * camera_follow_lerp_speed, 0.0, 1.0)
	var ty := lerpf(camera.global_position.y, _followed_stone.global_position.y, weight)
	camera.global_position = Vector2(camera.global_position.x, ty)


# ---------------------------------------------------------------------------
# Shot lifecycle
# ---------------------------------------------------------------------------

func _start_next_shot() -> void:
	if _shots_taken >= TRAINING_SHOTS:
		_finish_training()
		return

	_clear_all_stones()
	_place_opponent_stones()
	_move_camera_to_overview()

	var stone := STONE_SCENE.instantiate() as RigidBody2D
	stone.position = stone_spawn_position
	add_child(stone)
	stone.add_to_group(STONES_GROUP)
	stone.set_stone_color(human_player_color)
	stone.set_player_control_enabled(true)
	stone.stone_stopped.connect(_on_player_stone_stopped)
	if stone.has_signal("stone_launched"):
		stone.stone_launched.connect(_on_stone_launched)
	_active_stone = stone


func _on_stone_launched(stone: RigidBody2D) -> void:
	if stone != _active_stone:
		return
	_followed_stone = stone
	_set_camera_zoom(camera_follow_zoom)


func _on_player_stone_stopped(stone: RigidBody2D) -> void:
	if stone != _active_stone:
		return

	await _wait_for_all_stones_to_settle()
	_prune_out_of_bounds()
	_score_shot()
	_shots_taken += 1
	_update_hud()
	_active_stone = null
	_followed_stone = null

	await get_tree().create_timer(1.2).timeout
	_start_next_shot()


# ---------------------------------------------------------------------------
# Opponent stone placement
# ---------------------------------------------------------------------------

func _place_opponent_stones() -> void:
	match training_stat:
		"Speed":
			_place_speed_stones()
		"Spin":
			_place_spin_stones()
		"Precision":
			_place_precision_stones()
		_:
			_place_speed_stones()


func _place_speed_stones() -> void:
	# One opponent stone randomly placed inside the house — NOT frozen so it can be knocked out.
	var angle := randf_range(0.0, TAU)
	var dist := randf_range(0.0, house_radius * 0.7)
	_spawn_opponent_stone(house_center + Vector2.RIGHT.rotated(angle) * dist, false)


func _place_spin_stones() -> void:
	# One guard stone placed in front of the house — frozen so it acts as a fixed obstacle.
	var offset_x := randf_range(-40.0, 40.0)
	_spawn_opponent_stone(Vector2(house_center.x + offset_x, guard_zone_y), true)


func _place_precision_stones() -> void:
	# 2–3 opponent stones placed in the house — NOT frozen so collisions feel natural.
	var count := randi_range(2, 3)
	for i in range(count):
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(house_radius * 0.15, house_radius * 0.85)
		_spawn_opponent_stone(house_center + Vector2.RIGHT.rotated(angle) * dist, false)


func _spawn_opponent_stone(pos: Vector2, frozen: bool = false) -> RigidBody2D:
	var stone := STONE_SCENE.instantiate() as RigidBody2D
	stone.position = pos
	add_child(stone)
	stone.add_to_group(STONES_GROUP)
	stone.set_stone_color(opponent_color)
	stone.set_player_control_enabled(false)
	stone.freeze = frozen
	return stone


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------

func _score_shot() -> void:
	var points := 0
	match training_stat:
		"Speed":
			points = _score_speed()
		"Spin":
			points = _score_spin()
		"Precision":
			points = _score_precision()

	_total_score += points

	if is_instance_valid(score_label):
		score_label.text = "Score: %d  (+%d)" % [_total_score, points]
	await get_tree().create_timer(0.6).timeout
	if is_instance_valid(score_label):
		score_label.text = "Score: %d" % _total_score


func _score_speed() -> int:
	# Points for player stone landing in house; opponent stone must be outside.
	var player_stone: RigidBody2D = _find_player_stone_in_house()
	if player_stone == null:
		return 0 # Player stone left the house — no points.

	var opponent_in_house := false
	for node in get_tree().get_nodes_in_group(STONES_GROUP):
		if not is_instance_valid(node):
			continue
		if String(node.get("stone_color")) == opponent_color:
			var dist: float = node.position.distance_to(house_center)
			if dist <= house_radius:
				opponent_in_house = true
				break

	if opponent_in_house:
		return 0 # Didn't knock out the opponent — no points.

	# Points based on closeness of player stone to centre.
	var player_dist: float = player_stone.position.distance_to(house_center)
	return _distance_to_points(player_dist)


func _score_spin() -> int:
	# Points for landing in the house (guard must have been passed).
	# Guard is frozen — if player stone is in house it curled around it.
	var player_stone: RigidBody2D = _find_player_stone_in_house()
	if player_stone == null:
		return 0

	var player_dist: float = player_stone.position.distance_to(house_center)
	return _distance_to_points(player_dist)


func _score_precision() -> int:
	# Points if the player stone is closer to center than all opponent stones in house.
	var player_stone: RigidBody2D = _find_player_stone_in_house()
	if player_stone == null:
		return 0

	var player_dist: float = player_stone.position.distance_to(house_center)

	for node in get_tree().get_nodes_in_group(STONES_GROUP):
		if not is_instance_valid(node):
			continue
		if String(node.get("stone_color")) == opponent_color:
			var dist: float = node.position.distance_to(house_center)
			if dist <= player_dist:
				return 0 # An opponent stone is equal or closer — no points.

	return _distance_to_points(player_dist)


func _distance_to_points(dist: float) -> int:
	# Closer = more points. 4-ring scoring like real curling, adapted.
	var ratio := dist / house_radius
	if ratio <= 0.25:
		return 400 # Button (very centre).
	elif ratio <= 0.5:
		return 300
	elif ratio <= 0.75:
		return 200
	else:
		return 100


func _find_player_stone_in_house() -> RigidBody2D:
	for node in get_tree().get_nodes_in_group(STONES_GROUP):
		if not is_instance_valid(node):
			continue
		var stone := node as RigidBody2D
		if stone == null:
			continue
		if String(stone.get("stone_color")) == human_player_color:
			var dist: float = stone.position.distance_to(house_center)
			if dist <= house_radius:
				return stone
	return null


# ---------------------------------------------------------------------------
# Training complete
# ---------------------------------------------------------------------------

func _finish_training() -> void:
	_clear_all_stones()
	_move_camera_to_overview()

	var boost := _score_to_boost(_total_score)
	var max_possible := TRAINING_SHOTS * 400

	if is_instance_valid(result_label):
		result_label.text = "Training complete!\nScore: %d / %d\n+%d %s" % [
			_total_score, max_possible, boost, training_stat
		]
		result_label.visible = true

	# Apply the stat boost to the chosen stone and lock trainer for this week.
	var manager := get_node_or_null("/root/game_manager")
	if manager != null:
		_apply_stat_boost(manager, boost)
		if manager.has_method("set_trainer_week_used"):
			manager.set_trainer_week_used()
		emit_signal("training_complete", training_stat, _total_score)

	await get_tree().create_timer(3.5).timeout
	get_tree().change_scene_to_file("res://scenes/menus/trainer.tscn")


func _score_to_boost(score: int) -> int:
	var max_possible := TRAINING_SHOTS * 400  # 2000 total
	var ratio := float(score) / float(max_possible)
	if ratio >= 0.66:
		return 10
	elif ratio >= 0.33:
		return 7
	else:
		return 5


func _apply_stat_boost(manager: Node, boost: int) -> void:
	var stones: Array = manager.get_player_stones()
	if training_rock_index < 0 or training_rock_index >= stones.size():
		return

	var stone: Stone = stones[training_rock_index]
	if stone == null:
		return

	match training_stat:
		"Speed":
			stone.set_power(stone.power + boost)
		"Spin":
			stone.set_spin(stone.spin + boost)
		"Precision":
			stone.set_precision(stone.precision + boost)

	manager.emit_signal("state_changed")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _clear_all_stones() -> void:
	for node in get_tree().get_nodes_in_group(STONES_GROUP):
		if is_instance_valid(node):
			node.queue_free()


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


func _prune_out_of_bounds() -> void:
	var scratch_y: float = _get_scratch_line_y()
	for node in get_tree().get_nodes_in_group(STONES_GROUP):
		if not is_instance_valid(node):
			continue
		var stone := node as RigidBody2D
		if stone == null:
			continue
		if stone.has_method("should_remove_on_reset") and stone.should_remove_on_reset(scratch_y, rink_end_y):
			stone.queue_free()


func _get_scratch_line_y() -> float:
	if is_instance_valid(scratch_line) and scratch_line.points.size() > 0:
		return scratch_line.to_global(scratch_line.points[0]).y
	return 433.0


func _move_camera_to_overview() -> void:
	if not is_instance_valid(camera):
		return
	var tween := create_tween()
	tween.tween_property(camera, "global_position", camera_overview_position, camera_overview_delay)
	tween.parallel().tween_property(camera, "zoom", camera_overview_zoom, camera_overview_delay)


func _set_camera_zoom(zoom: Vector2) -> void:
	if not is_instance_valid(camera):
		return
	var tween := create_tween()
	tween.tween_property(camera, "zoom", zoom, 0.25)


func _update_hud() -> void:
	if is_instance_valid(shot_label):
		shot_label.text = "Shot %d / %d   |   %s" % [
			mini(_shots_taken + 1, TRAINING_SHOTS), TRAINING_SHOTS, training_stat
		]
	if is_instance_valid(score_label):
		score_label.text = "Score: %d" % _total_score
