extends Node2D

const STONE_SCENE := preload("res://scenes/Stone.tscn")
const AI_PLAYER := preload("res://scripts/ai_player.gd")
const STONES_GROUP := "stones"
const BLUE_STONE_ICON := preload("res://assets/curling/stones/stone_blue_top.png")
const RED_STONE_ICON := preload("res://assets/curling/stones/stone_red_top.png")
const YELLOW_STONE_ICON := preload("res://assets/curling/stones/stone_yellow_top.png")

@export var stones_per_player := 5
@export var ai_enabled := true
@export var ai_player_color := "red"
@export var human_player_color := "yellow"
## Name shown on the scoreboard for the human player.
@export var human_player_name: String = "Player"
## Name shown on the scoreboard for the AI player.
@export var ai_player_name: String = "AI"
## Per-throw stone colors for the human player (must have stones_per_player entries).
## Leave empty to use human_player_color for all throws.
@export var human_player_stones: Array[String] = []
@export var stone_spawn_position := Vector2(360.0, 1000.0)
@export var settled_speed_threshold := 8.0
@export var settled_frames_required := 5
@export var scratch_line_fallback_y := 433.0
@export var rink_end_y := -70
@export var camera_overview_position := Vector2(360.0, 640)
@export var camera_overview_zoom := Vector2(1.0, 1.0)
@export var camera_follow_zoom := Vector2(1.5, 1.5)
@export var camera_follow_lerp_speed := 6.0
@export var camera_overview_delay := 0.25
@export var max_ends := 3
@export var end_score_extra_hold_seconds := 1.0
@export var ai_difficulty: int = 5
@export var auto_return_to_menu := true
@export var match_result_hold_seconds := 3.0
@export_file("*.tscn") var return_to_scene_path: String = "res://scenes/Main.tscn"
var house_center
var house_radius

var PLAYER_COLORS := [human_player_color, ai_player_color]

@onready var camera: Camera2D = $Camera2D
@onready var end_score_label: Label = $CanvasLayer/EndScoreLabel
@onready var scoreboard_panel: TextureRect = $CanvasLayer/scoreboard
@onready var score_1_label: RichTextLabel = $CanvasLayer/scoreboard/score1
@onready var score_2_label: RichTextLabel = $CanvasLayer/scoreboard/score2
@onready var end_label: RichTextLabel = $CanvasLayer/scoreboard/end
@onready var rocks_1_box: HBoxContainer = $CanvasLayer/scoreboard/rocks1
@onready var rocks_2_box: HBoxContainer = $CanvasLayer/scoreboard/rocks2
@onready var scratch_line: Line2D = $house/scratchline
@onready var name_1_label: RichTextLabel = $CanvasLayer/scoreboard/name1
@onready var name_2_label: RichTextLabel = $CanvasLayer/scoreboard/name2

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
var ai_player = null
var camera_tween: Tween
var camera_delay_tween: Tween
var starting_player_index := 0
var hammer_icon_texture: Texture2D


func _ready() -> void:
	randomize()
	starting_player_index = randi_range(0, PLAYER_COLORS.size() - 1)
	current_player_index = starting_player_index
	hammer_icon_texture = _load_hammer_icon_texture()
	_apply_player_names()

	if human_player_stones.size() > 0 and human_player_stones.size() != stones_per_player:
		push_warning("CurlingGame: human_player_stones has %d entries but stones_per_player is %d; ignoring stone set." % [human_player_stones.size(), stones_per_player])
		human_player_stones = []

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
	ai_player = AI_PLAYER.new()
	ai_player.difficulty = ai_difficulty
	_update_scoreboard_ui()
	_update_rocks_left_ui()
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

	# Use per-stone color override for the human player when a stone set was provided.
	var spawn_color := color
	if color == human_player_color and human_player_stones.size() == stones_per_player:
		var throw_index: int = int(throws_by_color.get(human_player_color, 0))
		spawn_color = human_player_stones[throw_index]

	if stone.has_method("set_stone_color"):
		stone.set_stone_color(spawn_color)
	if stone.has_method("set_player_control_enabled"):
		stone.set_player_control_enabled(not _is_ai_turn(color))

	stone.stone_stopped.connect(_on_stone_stopped)
	if stone.has_signal("stone_launched"):
		stone.stone_launched.connect(_on_stone_launched)
	if stone.has_signal("spin_selection_started"):
		stone.spin_selection_started.connect(_on_spin_selection_started)
	if stone.has_signal("spin_selection_completed"):
		stone.spin_selection_completed.connect(_on_spin_selection_completed)
	active_stone = stone

	if _is_ai_turn(color):
		_start_ai_turn(stone)

	#if camera.has_method("set_target"):
		#camera.set_target(stone)


func _on_stone_launched(stone: RigidBody2D) -> void:
	if stone != active_stone:
		return

	if is_instance_valid(camera_delay_tween):
		camera_delay_tween.kill()

	followed_stone = stone
	var launched_color: String = PLAYER_COLORS[current_player_index]
	_update_rocks_left_ui(launched_color, throws_by_color[launched_color] + 1)
	_set_camera_zoom(camera_follow_zoom)


func _on_stone_stopped(stone: RigidBody2D) -> void:
	if stone != active_stone:
		return

	var color: String = PLAYER_COLORS[current_player_index]
	throws_by_color[color] += 1
	_update_rocks_left_ui()
	current_player_index = 1 - current_player_index

	await _wait_for_all_stones_to_settle()
	_prune_out_of_play_stones()

	if _match_finished():
		var end_score: Dictionary = _calculate_end_score()
		_show_end_score(end_score)
		_set_next_end_starting_player(end_score)
		active_stone = null
		_advance_to_next_end()
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

	var shot: Dictionary = ai_player.choose_shot(
		stone_spawn_position,
		stone,
		_collect_stone_data(),
		house_center,
		house_radius,
		stones_per_player
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
	var scratch_line_y: float = _get_scratch_line_y()

	for node in get_tree().get_nodes_in_group(STONES_GROUP):
		if not is_instance_valid(node):
			continue

		var stone := node as RigidBody2D
		if stone == null:
			continue

		if stone.has_method("should_remove_on_reset") and stone.should_remove_on_reset(scratch_line_y, rink_end_y):
			stone.queue_free()


func _get_scratch_line_y() -> float:
	if is_instance_valid(scratch_line) and scratch_line.points.size() > 0:
		return scratch_line.to_global(scratch_line.points[0]).y

	return scratch_line_fallback_y


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

	_update_scoreboard_ui()

	if not is_instance_valid(end_score_label):
		return

	if points <= 0:
		end_score_label.text = "Blank end - no score"
		end_score_label.add_theme_color_override("font_color", Color.BLACK)
	else:
		end_score_label.text = "%s scores %d" % [scoring_color.capitalize(), points]
		end_score_label.add_theme_color_override("font_color", _stone_color_to_ui_color(scoring_color))

	end_score_label.visible = true


func _advance_to_next_end() -> void:
	await get_tree().create_timer(1.6).timeout
	if current_end >= max_ends and not _is_match_tied():
		_end_match()
		return

	if end_score_extra_hold_seconds > 0.0:
		await get_tree().create_timer(end_score_extra_hold_seconds).timeout

	current_end += 1
	_reset_end_state()
	_update_scoreboard_ui()
	if is_instance_valid(end_score_label):
		end_score_label.visible = false
		end_score_label.text = ""
	_spawn_next_stone()


func _is_match_tied() -> bool:
	var human_score: int = int(scores_by_color.get(human_player_color, 0))
	var ai_score: int = int(scores_by_color.get(ai_player_color, 0))
	return human_score == ai_score


func _end_match() -> void:
	active_stone = null
	followed_stone = null
	_move_camera_to_overview()

	var human_score: int = int(scores_by_color.get(human_player_color, 0))
	var ai_score: int = int(scores_by_color.get(ai_player_color, 0))
	var result_text := ""

	if human_score > ai_score:
		result_text = "%s wins %d-%d" % [human_player_name, human_score, ai_score]
	elif ai_score > human_score:
		result_text = "%s wins %d-%d" % [ai_player_name, ai_score, human_score]
	else:
		result_text = "Match tied %d-%d" % [human_score, ai_score]

	if is_instance_valid(end_score_label):
		end_score_label.text = result_text
		if human_score > ai_score:
			end_score_label.add_theme_color_override("font_color", _stone_color_to_ui_color(human_player_color))
		elif ai_score > human_score:
			end_score_label.add_theme_color_override("font_color", _stone_color_to_ui_color(ai_player_color))
		else:
			end_score_label.add_theme_color_override("font_color", Color.BLACK)
		end_score_label.visible = true

	if auto_return_to_menu and return_to_scene_path != "":
		_schedule_return_to_menu()


func _schedule_return_to_menu() -> void:
	var delay := maxf(match_result_hold_seconds, 0.0)
	if delay <= 0.0:
		_go_to_return_scene()
		return

	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(_go_to_return_scene)


func _go_to_return_scene() -> void:
	if return_to_scene_path == "":
		return

	get_tree().change_scene_to_file(return_to_scene_path)


func _stone_color_to_ui_color(stone_color: String) -> Color:
	match stone_color:
		"red":
			return Color(0.9, 0.2, 0.2, 1.0)
		"yellow":
			return Color(0.95, 0.82, 0.2, 1.0)
		"blue":
			return Color(0.2, 0.45, 0.95, 1.0)
		_:
			return Color.BLACK


## Applies human_player_name and ai_player_name to the scoreboard name labels.
func _apply_player_names() -> void:
	if is_instance_valid(name_1_label):
		name_1_label.text = human_player_name
	if is_instance_valid(name_2_label):
		name_2_label.text = ai_player_name


func _on_spin_selection_started(_stone: RigidBody2D) -> void:
	if is_instance_valid(scoreboard_panel):
		scoreboard_panel.visible = false


func _on_spin_selection_completed(_stone: RigidBody2D) -> void:
	if is_instance_valid(scoreboard_panel):
		scoreboard_panel.visible = true


func _reset_end_state() -> void:
	for node in get_tree().get_nodes_in_group(STONES_GROUP):
		if is_instance_valid(node):
			node.queue_free()

	throws_by_color[human_player_color] = 0
	throws_by_color[ai_player_color] = 0
	_update_rocks_left_ui()
	current_player_index = starting_player_index
	active_stone = null
	followed_stone = null
	_queue_camera_overview()


func _set_next_end_starting_player(score: Dictionary) -> void:
	var scoring_color: String = String(score.get("color", ""))
	if scoring_color == "":
		return

	var next_index := PLAYER_COLORS.find(scoring_color)
	if next_index >= 0:
		starting_player_index = next_index


func _update_scoreboard_ui() -> void:
	if is_instance_valid(score_1_label):
		score_1_label.text = str(scores_by_color.get(human_player_color, 0))

	if is_instance_valid(score_2_label):
		score_2_label.text = str(scores_by_color.get(ai_player_color, 0))

	if is_instance_valid(end_label):
		end_label.text = "End\n%d" % current_end


func _update_rocks_left_ui(override_color: String = "", override_throws: int = -1) -> void:
	if not is_instance_valid(rocks_1_box) or not is_instance_valid(rocks_2_box):
		return

	var player_one_color: String = human_player_color
	var player_two_color: String = ai_player_color
	var player_one_throws: int = int(throws_by_color.get(player_one_color, 0))
	var player_two_throws: int = int(throws_by_color.get(player_two_color, 0))

	if override_color == player_one_color and override_throws >= 0:
		player_one_throws = override_throws
	if override_color == player_two_color and override_throws >= 0:
		player_two_throws = override_throws

	var player_one_left: int = maxi(stones_per_player - player_one_throws, 0)
	var player_two_left: int = maxi(stones_per_player - player_two_throws, 0)
	var player_one_has_hammer: bool = _player_has_hammer(player_one_color)
	var player_two_has_hammer: bool = _player_has_hammer(player_two_color)

	_populate_rocks_box(rocks_1_box, player_one_color, player_one_left, player_one_has_hammer)
	_populate_rocks_box(rocks_2_box, player_two_color, player_two_left, player_two_has_hammer)


func _populate_rocks_box(box: HBoxContainer, stone_color: String, stones_left: int, has_hammer: bool) -> void:
	for child in box.get_children():
		child.queue_free()

	var icon_texture: Texture2D = _stone_color_to_icon(stone_color)
	if icon_texture == null:
		return

	for _i in range(stones_left):
		var icon := TextureRect.new()
		icon.texture = icon_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(16.0, 16.0)
		box.add_child(icon)

	if has_hammer and hammer_icon_texture != null:
		var hammer_icon := TextureRect.new()
		hammer_icon.texture = hammer_icon_texture
		hammer_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hammer_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hammer_icon.custom_minimum_size = Vector2(14.0, 14.0)
		box.add_child(hammer_icon)


func _player_has_hammer(player_color: String) -> bool:
	if PLAYER_COLORS.size() < 2:
		return false

	var starting_color: String = String(PLAYER_COLORS[starting_player_index])
	return player_color != starting_color


func _load_hammer_icon_texture() -> Texture2D:
	var candidate_paths := [
		"res://assets/hammer.png",
		"res://assets/pngtree-retro-8-bit-hammer-icon-with-transparent-background-vector-png-image_16300563.png",
	]

	for path in candidate_paths:
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			return ImageTexture.create_from_image(image)

	return null


func _stone_color_to_icon(stone_color: String) -> Texture2D:
	match stone_color:
		"red":
			return RED_STONE_ICON
		"yellow":
			return YELLOW_STONE_ICON
		"blue":
			return BLUE_STONE_ICON
		_:
			return null


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
