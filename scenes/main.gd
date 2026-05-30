extends Node2D

const STONE_SCENE := preload("res://scenes/Stone.tscn")
const AI_PLAYER := preload("res://scenes/ai_player.gd")
const STONES_GROUP := "stones"

@export var stones_per_player := 5
@export var ai_enabled := true
@export var ai_player_color := "red"
@export var human_player_color := "yellow"
@export var stone_spawn_position := Vector2(360.0, 1000.0)
@export var settled_speed_threshold := 8.0
@export var settled_frames_required := 5
@export var red_line_y := 425
@export var rink_end_y := -80
@export var camera_overview_position := Vector2(360.0, 640)
@export var camera_overview_zoom := Vector2(1.0, 1.0)
@export var camera_follow_zoom := Vector2(1.5, 1.5)
@export var camera_follow_lerp_speed := 6.0
@export var camera_overview_delay := 0.25
var house_center
var house_radius

var PLAYER_COLORS := [human_player_color, ai_player_color]

@onready var camera: Camera2D = $Camera2D
@onready var end_score_label: Label = $CanvasLayer/EndScoreLabel
@onready var scoreboard = $CanvasLayer/ScoreBoard

var current_player_index := 0
var current_end := 1
var throws_by_color := {
	human_player_color: 0,
	ai_player_color: 0,
}
var scores_by_color := {
	human_player_color: 0,
	ai_player_color: 0,
}
var active_stone: RigidBody2D
var followed_stone: RigidBody2D
var ai_player = AI_PLAYER.new()
var camera_tween: Tween
var camera_delay_tween: Tween


func _ready() -> void:
	if has_node("walls"):
		$walls.add_to_group("side_walls")
	if is_instance_valid(end_score_label):
		end_score_label.visible = false
		end_score_label.text = ""
	if is_instance_valid(camera):
		camera.global_position = camera_overview_position
		camera.zoom = camera_overview_zoom
	house_center = $house.position
	house_radius = $house/houseArea.shape.radius
	if is_instance_valid(scoreboard):
		scoreboard.setup(PLAYER_COLORS, stones_per_player)
		scoreboard.set_end(current_end)
	_spawn_next_stone()


func _process(delta: float) -> void:
	if not is_instance_valid(camera):
		return

	if not is_instance_valid(followed_stone):
		return

	var follow_weight := clampf(delta * camera_follow_lerp_speed, 0.0, 1.0)
	var target_y := lerpf(camera.global_position.y, followed_stone.global_position.y, follow_weight)
	camera.global_position = Vector2(camera.global_position.x, target_y)


func _spawn_next_stone() -> void:
	followed_stone = null
	_queue_camera_overview()

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
	if stone.has_method("set_player_control_enabled"):
		stone.set_player_control_enabled(not _is_ai_turn(color))

	stone.stone_stopped.connect(_on_stone_stopped)
	if stone.has_signal("stone_launched"):
		stone.stone_launched.connect(_on_stone_launched)
	active_stone = stone

	if is_instance_valid(scoreboard):
		scoreboard.set_stones_thrown(color, throws_by_color[color])

	if _is_ai_turn(color):
		_start_ai_turn(stone)

	#if camera.has_method("set_target"):
		#camera.set_target(stone)


func _on_stone_launched(stone: RigidBody2D) -> void:
	if stone != active_stone:
		return

	if is_instance_valid(camera_delay_tween):
		camera_delay_tween.kill()

	var launched_color: String = PLAYER_COLORS[current_player_index]
	if is_instance_valid(scoreboard):
		scoreboard.set_stones_thrown(launched_color, throws_by_color[launched_color] + 1)

	followed_stone = stone
	_set_camera_zoom(camera_follow_zoom)


func _on_stone_stopped(stone: RigidBody2D) -> void:
	if stone != active_stone:
		return

	var color: String = PLAYER_COLORS[current_player_index]
	throws_by_color[color] += 1
	current_player_index = 1 - current_player_index

	await _wait_for_all_stones_to_settle()
	_prune_out_of_play_stones()

	if _match_finished():
		_show_end_score(_calculate_end_score())
		active_stone = null
		return

	_spawn_next_stone()


func _match_finished() -> bool:
	return throws_by_color[human_player_color] >= stones_per_player and throws_by_color[ai_player_color] >= stones_per_player


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


func _is_ai_turn(color: String) -> bool:
	return ai_enabled and color == ai_player_color


func _start_ai_turn(stone: RigidBody2D) -> void:
	await get_tree().create_timer(ai_player.get_think_time()).timeout
	if not is_instance_valid(stone) or stone != active_stone:
		return

	var shot := ai_player.choose_shot(
		stone_spawn_position,
		stone,
		_collect_stone_data(),
		house_center,
		house_radius
	)

	if stone.has_method("launch_shot"):
		stone.launch_shot(
			shot.get("direction", Vector2.UP),
			float(shot.get("power", 0.0)),
			float(shot.get("spin", 0.0))
		)


func _collect_stone_data() -> Array[Dictionary]:
	var stones: Array[Dictionary] = []

	for node in get_tree().get_nodes_in_group(STONES_GROUP):
		if not is_instance_valid(node):
			continue

		var stone := node as RigidBody2D
		if stone == null:
			continue

		stones.append({
			"color": String(stone.get("stone_color")),
			"position": stone.position,
		})

	return stones


func _prune_out_of_play_stones() -> void:
	for node in get_tree().get_nodes_in_group(STONES_GROUP):
		if not is_instance_valid(node):
			continue

		var stone := node as RigidBody2D
		if stone == null:
			continue

		if stone.has_method("should_remove_on_reset") and stone.should_remove_on_reset(red_line_y, rink_end_y):
			stone.queue_free()


func _calculate_end_score() -> Dictionary:
	var in_house: Array[Dictionary] = []

	for node in get_tree().get_nodes_in_group(STONES_GROUP):
		if not is_instance_valid(node):
			continue

		var stone := node as RigidBody2D
		if stone == null:
			continue

		var distance := stone.position.distance_to(house_center)
		if distance <= house_radius:
			in_house.append({
				"color": String(stone.get("stone_color")),
				"distance": distance,
			})

	if in_house.is_empty():
		return {
			"color": "",
			"points": 0,
		}

	in_house.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["distance"] < b["distance"]
	)

	var scoring_color: String = in_house[0]["color"]
	var points := 0
	for stone_data in in_house:
		if String(stone_data["color"]) != scoring_color:
			break
		points += 1

	return {
		"color": scoring_color,
		"points": points,
	}


func _show_end_score(score: Dictionary) -> void:
	var scoring_color: String = String(score.get("color", ""))
	var points: int = int(score.get("points", 0))

	if scoring_color != "" and points > 0 and scores_by_color.has(scoring_color):
		scores_by_color[scoring_color] += points

	if is_instance_valid(scoreboard):
		for c in PLAYER_COLORS:
			scoreboard.set_score(c, scores_by_color.get(c, 0))

	if not is_instance_valid(end_score_label):
		return

	if points <= 0:
		end_score_label.text = "Blank end - no score"
	else:
		end_score_label.text = "%s scores %d" % [scoring_color.capitalize(), points]

	end_score_label.visible = true


func _move_camera_to_overview() -> void:
	if not is_instance_valid(camera):
		return

	if is_instance_valid(camera_tween):
		camera_tween.kill()

	camera_tween = create_tween()
	camera_tween.set_parallel(true)
	camera_tween.tween_property(camera, "zoom", camera_overview_zoom, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera, "global_position", camera_overview_position, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _queue_camera_overview() -> void:
	if not is_instance_valid(camera):
		return

	if is_instance_valid(camera_delay_tween):
		camera_delay_tween.kill()

	if camera_overview_delay <= 0.0:
		_move_camera_to_overview()
		return

	camera_delay_tween = create_tween()
	camera_delay_tween.tween_interval(camera_overview_delay)
	camera_delay_tween.tween_callback(_move_camera_to_overview)


func _set_camera_zoom(target_zoom: Vector2) -> void:
	if not is_instance_valid(camera):
		return

	if is_instance_valid(camera_tween):
		camera_tween.kill()

	camera_tween = create_tween()
	camera_tween.tween_property(camera, "zoom", target_zoom, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
