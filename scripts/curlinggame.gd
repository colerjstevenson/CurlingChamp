extends Node2D

const STONE_SCENE := preload("res://scenes/Stone.tscn")
const AI_PLAYER := preload("res://scripts/ai_player.gd")
const ROCK_WINDOW_SCENE := preload("res://scenes/controls/RockWindow.tscn")
const STONES_GROUP := "stones"
const BLUE_STONE_ICON := preload("res://assets/curling/stones/stone_blue_top.png")
const RED_STONE_ICON := preload("res://assets/curling/stones/stone_red_top.png")
const YELLOW_STONE_ICON := preload("res://assets/curling/stones/stone_yellow_top.png")
const ROCK_CARD_LAYOUT_SIZE := Vector2(595.0, 920.0)
const ROCK_CARD_MIN_SCALE := 0.20
const ROCK_CARD_MAX_SCALE := 0.43
const ROCK_CARD_HEIGHT_FRACTION := 1.5
const ROCK_CARD_MIN_SPACING := 8
const ROCK_CARD_MAX_SPACING := 20
const ROCK_SELECTION_WHEEL_SCROLL_STEP := 120
const DEFAULT_ROCK_NAME := "Base Stone"
const DEFAULT_ROCK_STAT := 33
const DEFAULT_THROW_CONFIG_PATH := "res://data/throw_physics_config.tres"

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
@export var rink_end_y := -70.0
@export var camera_overview_position := Vector2(360.0, 640)
@export var camera_overview_zoom := Vector2(1.0, 1.0)
@export var camera_house_target_zoom := Vector2(1.0, 1.0)
@export var camera_throw_setup_zoom := Vector2(1.42, 1.42)
@export var camera_follow_zoom := Vector2(1.68, 1.68)
@export var camera_follow_lerp_speed := 8.0
@export var camera_follow_top_margin := 640
@export var camera_overview_delay := 0.25
@export var camera_overview_bottom_padding := 0.0
@export var spawn_from_rink_bottom_margin := 280.0
@export var rink_end_margin := 120.0
@export var camera_bounds_padding := 120.0
@export var target_house_buffer := 180.0
@export var target_side_padding := 28.0
@export var max_ends := 3
@export var end_score_extra_hold_seconds := 1.0
@export var ai_difficulty: int = 5
@export var human_throws_first := true
@export var auto_return_to_menu := true
@export var match_result_hold_seconds := 3.0
@export_file("*.tscn") var return_to_scene_path: String = "res://scenes/main.tscn"
@export var throw_config: Resource
var house_center
var house_radius
var rink_top_y := 0.0
var rink_bottom_y := 0.0
var rink_left_x := 0.0
var rink_right_x := 0.0

var PLAYER_COLORS := [human_player_color, ai_player_color]

@onready var camera: Camera2D = $Camera2D
@onready var rink_sprite: Sprite2D = $Rink
@onready var house: Area2D = $Rink/house
@onready var house_area_shape: CollisionShape2D = $Rink/house/houseArea
@onready var end_score_label: Label = $CanvasLayer/EndScoreLabel
@onready var scoreboard_panel: TextureRect = $CanvasLayer/scoreboard
@onready var score_1_label: RichTextLabel = $CanvasLayer/scoreboard/score1
@onready var score_2_label: RichTextLabel = $CanvasLayer/scoreboard/score2
@onready var end_label: RichTextLabel = $CanvasLayer/scoreboard/end
@onready var rocks_1_box: HBoxContainer = $CanvasLayer/scoreboard/rocks1
@onready var rocks_2_box: HBoxContainer = $CanvasLayer/scoreboard/rocks2
@onready var scratch_line: Line2D = $Rink/house/scratchline
@onready var name_1_label: RichTextLabel = $CanvasLayer/scoreboard/name1
@onready var name_2_label: RichTextLabel = $CanvasLayer/scoreboard/name2
@onready var target_marker: Polygon2D = get_node_or_null("TargetMarker") as Polygon2D
@onready var lock_target_button: BaseButton = get_node_or_null("CanvasLayer/LockTargetButton") as BaseButton
@onready var stage_prompt_label: Label = get_node_or_null("CanvasLayer/StagePromptLabel") as Label
@onready var rock_selection_panel: Panel = get_node_or_null("CanvasLayer/Rockselection") as Panel
@onready var rock_selection_scroll: ScrollContainer = get_node_or_null("CanvasLayer/Rockselection/ScrollContainer") as ScrollContainer
@onready var rock_selection_list: HBoxContainer = get_node_or_null("CanvasLayer/Rockselection/ScrollContainer/HBoxContainer") as HBoxContainer

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
var human_target_lock_pending := false
var has_active_target := false
var active_target_position: Vector2 = Vector2.ZERO
var selectable_stones: Array[Stone] = []
var rock_cards: Array[Control] = []
var used_stone_indices_this_end: Dictionary = {}
var pending_human_stone_wear_by_index: Dictionary = {}
var selected_stone_index := 0
var pending_human_stone_index := 0
var _is_drag_scrolling_rock_selection := false


func _ready() -> void:
	randomize()
	_ensure_throw_config()
	_load_week_settings_from_manager()
	if human_throws_first:
		starting_player_index = maxi(0, PLAYER_COLORS.find(human_player_color))
	else:
		starting_player_index = randi_range(0, PLAYER_COLORS.size() - 1)
	current_player_index = starting_player_index
	hammer_icon_texture = _load_hammer_icon_texture()
	_apply_player_names()

	if human_player_stones.size() > 0 and human_player_stones.size() != stones_per_player:
		push_warning("CurlingGame: human_player_stones has %d entries but stones_per_player is %d; ignoring stone set." % [human_player_stones.size(), stones_per_player])
		human_player_stones = []

	if has_node("Rink/walls"):
		$Rink/walls.add_to_group("side_walls")

	_refresh_rink_geometry()

	if is_instance_valid(end_score_label):
		end_score_label.visible = false
		end_score_label.text = ""
	if is_instance_valid(camera):
		camera.global_position = _clamp_camera_center_to_rink(camera_overview_position, camera_overview_zoom)
		camera.zoom = camera_overview_zoom
	if is_instance_valid(target_marker):
		target_marker.visible = false
	if is_instance_valid(lock_target_button):
		lock_target_button.visible = false
		lock_target_button.disabled = true
		if not lock_target_button.pressed.is_connected(_on_lock_target_pressed):
			lock_target_button.pressed.connect(_on_lock_target_pressed)
	if is_instance_valid(stage_prompt_label):
		stage_prompt_label.visible = false
		stage_prompt_label.text = ""
	ai_player = AI_PLAYER.new()
	ai_player.difficulty = ai_difficulty
	_build_human_rock_selection()
	_set_rock_selection_visible(false)
	_update_scoreboard_ui()
	_update_rocks_left_ui()
	_spawn_next_stone()


func _ensure_throw_config() -> void:
	if throw_config != null:
		return

	var loaded_config := load(DEFAULT_THROW_CONFIG_PATH)
	if loaded_config != null and loaded_config.has_method("get_throw_distance_scale"):
		throw_config = loaded_config


func _process(delta: float) -> void:
	if not is_instance_valid(camera):
		return

	var follow_top_margin := 0.0

	if is_instance_valid(followed_stone):
		var follow_weight := clampf(delta * camera_follow_lerp_speed, 0.0, 1.0)
		var target_y := lerpf(camera.global_position.y, followed_stone.global_position.y, follow_weight)
		camera.global_position = Vector2(camera.global_position.x, target_y)
		follow_top_margin = camera_follow_top_margin

	camera.global_position = _clamp_camera_center_to_rink(camera.global_position, camera.zoom, follow_top_margin)


func _input(event: InputEvent) -> void:
	if not _is_rock_selection_scroll_available():
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_is_drag_scrolling_rock_selection = false
		if event is InputEventScreenTouch and not event.pressed:
			_is_drag_scrolling_rock_selection = false
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _is_pointer_over_rock_selection_scroll(event.position):
				_is_drag_scrolling_rock_selection = true
			elif not event.pressed:
				_is_drag_scrolling_rock_selection = false
		elif event.pressed and _is_pointer_over_rock_selection_scroll(event.position):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_rock_selection_by_delta(float(ROCK_SELECTION_WHEEL_SCROLL_STEP))
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_rock_selection_by_delta(float(-ROCK_SELECTION_WHEEL_SCROLL_STEP))
				get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and _is_drag_scrolling_rock_selection:
		_scroll_rock_selection_by_delta(event.relative.x)
		get_viewport().set_input_as_handled()

	if event is InputEventScreenTouch:
		if event.pressed and _is_pointer_over_rock_selection_scroll(event.position):
			_is_drag_scrolling_rock_selection = true
		elif not event.pressed:
			_is_drag_scrolling_rock_selection = false

	if event is InputEventScreenDrag and _is_drag_scrolling_rock_selection:
		_scroll_rock_selection_by_delta(event.relative.x)
		get_viewport().set_input_as_handled()


func _clamp_camera_center_to_rink(center: Vector2, zoom: Vector2, top_margin: float = 0.0) -> Vector2:
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.y <= 0.0:
		return center

	var half_view_height_world := viewport_size.y * 0.5 * zoom.y
	var min_center_y := rink_top_y + half_view_height_world - maxf(top_margin, 0.0)
	return Vector2(center.x, maxf(center.y, min_center_y))


func _get_top_aligned_camera_center_y(zoom: Vector2) -> float:
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.y <= 0.0:
		return rink_top_y

	var half_view_height_world := viewport_size.y * 0.5 * zoom.y
	return rink_top_y + half_view_height_world


func _refresh_rink_geometry() -> void:
	if not is_instance_valid(rink_sprite) or rink_sprite.texture == null:
		return

	rink_top_y = rink_sprite.global_position.y - (rink_sprite.texture.get_height() * rink_sprite.global_scale.y * 0.5)
	rink_bottom_y = rink_sprite.global_position.y + (rink_sprite.texture.get_height() * rink_sprite.global_scale.y * 0.5)

	if is_instance_valid(house_area_shape):
		house_center = house_area_shape.global_position
	elif is_instance_valid(house):
		house_center = house.global_position

	if is_instance_valid(house_area_shape) and house_area_shape.shape is CircleShape2D:
		var circle_shape := house_area_shape.shape as CircleShape2D
		house_radius = circle_shape.radius * maxf(absf(house_area_shape.global_scale.x), absf(house_area_shape.global_scale.y))

	stone_spawn_position = Vector2(house_center.x, rink_bottom_y - spawn_from_rink_bottom_margin)
	rink_end_y = rink_top_y + rink_end_margin
	camera_overview_position = Vector2(house_center.x, _get_bottom_aligned_overview_y())

	if is_instance_valid(camera):
		var half_width := rink_sprite.texture.get_width() * rink_sprite.global_scale.x * 0.5
		rink_left_x = rink_sprite.global_position.x - half_width
		rink_right_x = rink_sprite.global_position.x + half_width
		camera.limit_left = int(floor(rink_sprite.global_position.x - half_width - camera_bounds_padding))
		camera.limit_right = int(ceil(rink_sprite.global_position.x + half_width + camera_bounds_padding))
		camera.limit_top = int(floor(rink_top_y - camera_bounds_padding))
		camera.limit_bottom = int(ceil(rink_bottom_y + camera_bounds_padding))


func _get_bottom_aligned_overview_y() -> float:
	var viewport_size: Vector2 = get_viewport_rect().size
	var half_view_height_world := viewport_size.y * 0.5 * camera_overview_zoom.y
	return rink_bottom_y - half_view_height_world - camera_overview_bottom_padding


func _spawn_next_stone() -> void:
	followed_stone = null
	_clear_target_ui()

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
	if stone.has_method("set_throw_config") and throw_config != null:
		stone.set_throw_config(throw_config)
	if stone.has_method("set_throw_distance_scale"):
		stone.set_throw_distance_scale(_get_throw_distance_scale())
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
		_set_rock_selection_visible(false)
		_set_stage_prompt("")
		_queue_camera_overview()
		_start_ai_turn(stone)
	else:
		_start_human_target_stage(stone)

	#if camera.has_method("set_target"):
		#camera.set_target(stone)


func _on_stone_launched(stone: RigidBody2D) -> void:
	if stone != active_stone:
		return

	human_target_lock_pending = false
	if is_instance_valid(lock_target_button):
		lock_target_button.visible = false
	_set_stage_prompt("Swipe to sweep")

	if is_instance_valid(camera_delay_tween):
		camera_delay_tween.kill()

	followed_stone = stone
	var launched_color: String = PLAYER_COLORS[current_player_index]
	if launched_color == human_player_color:
		if pending_human_stone_index > 0:
			used_stone_indices_this_end[pending_human_stone_index] = true
		_refresh_rock_selection_ui()
		_set_rock_selection_visible(false)
	_update_rocks_left_ui(launched_color, throws_by_color[launched_color] + 1)
	_set_camera_zoom(camera_follow_zoom)


func _on_stone_stopped(stone: RigidBody2D) -> void:
	if stone != active_stone:
		return

	_clear_target_ui()
	_set_stage_prompt("")

	var color: String = PLAYER_COLORS[current_player_index]
	throws_by_color[color] += 1
	_record_human_stone_wear_from_throw(stone)
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
	_clear_target_ui()
	_set_stage_prompt("")
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
		var scaled_power: float = float(shot.get("power", 0.0)) * _get_throw_distance_scale()
		stone.launch_shot(
			shot.get("direction", Vector2.UP),
			scaled_power,
			float(shot.get("spin", 0.0))
		)


func _get_throw_distance_scale() -> float:
	var throw_distance: float = maxf(absf(stone_spawn_position.y - house_center.y), 1.0)
	if throw_config == null or not throw_config.has_method("get_throw_distance_scale"):
		_ensure_throw_config()
	if throw_config == null or not throw_config.has_method("get_throw_distance_scale"):
		return 1.0

	return float(throw_config.call("get_throw_distance_scale", throw_distance))


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

	# Notify game_manager: record result, simulate league, advance week.
	var manager := get_node_or_null("/root/game_manager")
	if manager != null and manager.has_method("complete_week_after_match"):
		manager.complete_week_after_match(human_score > ai_score, pending_human_stone_wear_by_index)

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


## Reads the current week from game_manager and updates ai_difficulty and
## ai_player_name to match the scheduled opponent.
func _load_week_settings_from_manager() -> void:
	var manager := get_node_or_null("/root/game_manager")
	if manager == null:
		return

	var gm_week := int(manager.get("week"))
	var gm_player_name := String(manager.get("player_name"))
	if gm_player_name != "":
		human_player_name = gm_player_name

	if manager.has_method("get_opponent_skill_for_week"):
		ai_difficulty = int(manager.get_opponent_skill_for_week(gm_week))

	if manager.has_method("get_opponent_name_for_week"):
		var opp_name: String = manager.get_opponent_name_for_week(gm_week)
		if opp_name != "":
			ai_player_name = opp_name


func _on_spin_selection_started(_stone: RigidBody2D) -> void:
	if is_instance_valid(scoreboard_panel):
		scoreboard_panel.visible = false
	_set_stage_prompt("")


func _on_spin_selection_completed(_stone: RigidBody2D) -> void:
	if is_instance_valid(scoreboard_panel):
		scoreboard_panel.visible = true
	_set_stage_prompt("Swipe to sweep")


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
	used_stone_indices_this_end.clear()
	selected_stone_index = 0
	pending_human_stone_index = 0
	_refresh_rock_selection_ui()
	_clear_target_ui()
	_set_stage_prompt("")
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

	var overview_target := _clamp_camera_center_to_rink(camera_overview_position, camera_overview_zoom)
	camera_tween = create_tween()
	camera_tween.set_parallel(true)
	camera_tween.tween_property(camera, "zoom", camera_overview_zoom, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera, "global_position", overview_target, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


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


func _unhandled_input(event: InputEvent) -> void:
	if not human_target_lock_pending:
		return

	if not is_instance_valid(active_stone):
		return

	if event is InputEventScreenTouch:
		if not event.pressed:
			return
	elif event is InputEventMouseButton:
		if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
			return
	else:
		return

	var raw_target := get_global_mouse_position()
	if not _is_target_candidate_valid(raw_target):
		return

	active_target_position = _clamp_target_to_bounds(raw_target)
	has_active_target = true

	if is_instance_valid(target_marker):
		target_marker.global_position = active_target_position
		target_marker.visible = true

	if active_stone.has_method("set_target_marker_position"):
		active_stone.set_target_marker_position(active_target_position)

	_move_camera_to_house_target(active_target_position)

	if is_instance_valid(lock_target_button):
		lock_target_button.disabled = false

	_set_stage_prompt("Tap to adjust marker, then press Lock Target")


func _start_human_target_stage(stone: RigidBody2D) -> void:
	human_target_lock_pending = true
	has_active_target = false
	active_target_position = Vector2.ZERO
	pending_human_stone_index = 0
	_ensure_valid_selected_rock()
	_refresh_rock_selection_ui()
	_set_rock_selection_visible(true)
	if is_instance_valid(target_marker):
		target_marker.visible = false
	if is_instance_valid(lock_target_button):
		lock_target_button.visible = true
		lock_target_button.disabled = true
	if stone.has_method("set_throw_phase_targeting"):
		stone.set_throw_phase_targeting()
	_set_stage_prompt("Tap to place marker, then press Lock Target")
	_move_camera_to_house_target()


func _on_lock_target_pressed() -> void:
	if not human_target_lock_pending:
		return

	if not has_active_target:
		return

	if not is_instance_valid(active_stone):
		return
	pending_human_stone_index = selected_stone_index
	_apply_selected_stone_to_stone_node(active_stone, pending_human_stone_index)

	human_target_lock_pending = false
	if is_instance_valid(lock_target_button):
		lock_target_button.visible = false
	_set_rock_selection_visible(false)

	if active_stone.has_method("confirm_target_marker"):
		active_stone.confirm_target_marker()

	_set_stage_prompt("Drag from stone to set direction and power")
	_move_camera_to_throw_setup(active_stone.global_position)


func _clear_target_ui() -> void:
	human_target_lock_pending = false
	has_active_target = false
	pending_human_stone_index = 0
	if is_instance_valid(target_marker):
		target_marker.visible = false
	if is_instance_valid(lock_target_button):
		lock_target_button.visible = false
		lock_target_button.disabled = true
	_set_rock_selection_visible(false)


func _set_stage_prompt(text: String) -> void:
	if not is_instance_valid(stage_prompt_label):
		return

	stage_prompt_label.text = text
	stage_prompt_label.visible = text != ""


func _move_camera_to_house_target(focus_position: Vector2 = Vector2.INF) -> void:
	if not is_instance_valid(camera):
		return

	if is_instance_valid(camera_delay_tween):
		camera_delay_tween.kill()

	if is_instance_valid(camera_tween):
		camera_tween.kill()

	var desired_target := Vector2(house_center.x, _get_top_aligned_camera_center_y(camera_house_target_zoom))
	if focus_position != Vector2.INF:
		desired_target.y = focus_position.y

	var house_target := _clamp_camera_center_to_rink(desired_target, camera_house_target_zoom)
	camera_tween = create_tween()
	camera_tween.set_parallel(true)
	camera_tween.tween_property(camera, "zoom", camera_house_target_zoom, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera, "global_position", house_target, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _move_camera_to_throw_setup(target_position: Vector2) -> void:
	if not is_instance_valid(camera):
		return

	if is_instance_valid(camera_delay_tween):
		camera_delay_tween.kill()

	if is_instance_valid(camera_tween):
		camera_tween.kill()

	var setup_target := _clamp_camera_center_to_rink(target_position, camera_throw_setup_zoom)
	camera_tween = create_tween()
	camera_tween.set_parallel(true)
	camera_tween.tween_property(camera, "zoom", camera_throw_setup_zoom, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera, "global_position", setup_target, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _is_target_candidate_valid(world_position: Vector2) -> bool:
	if world_position.x < rink_left_x + target_side_padding:
		return false
	if world_position.x > rink_right_x - target_side_padding:
		return false

	var scratch_y: float = _get_scratch_line_y()
	if world_position.y > scratch_y:
		return false
	if world_position.y < rink_top_y:
		return false

	return true


func _clamp_target_to_bounds(world_position: Vector2) -> Vector2:
	var scratch_y: float = _get_scratch_line_y()
	var x := clampf(world_position.x, rink_left_x, rink_right_x)
	var y := clampf(world_position.y, rink_top_y, scratch_y)
	return Vector2(x, y)


func _build_human_rock_selection() -> void:
	if not is_instance_valid(rock_selection_list):
		return

	for child in rock_selection_list.get_children():
		child.queue_free()

	selectable_stones.clear()
	rock_cards.clear()
	used_stone_indices_this_end.clear()
	pending_human_stone_wear_by_index.clear()
	selected_stone_index = 0
	pending_human_stone_index = 0

	selectable_stones.append(_create_default_rock())

	var manager := get_node_or_null("/root/game_manager")
	if manager != null and manager.has_method("get_player_stones"):
		var owned_stones: Array[Stone] = manager.get_player_stones()
		for stone in owned_stones:
			if stone != null:
				selectable_stones.append(stone)

	var card_scale := _get_rock_card_scale()
	var card_display_size := ROCK_CARD_LAYOUT_SIZE * card_scale
	rock_selection_list.add_theme_constant_override("separation", _get_rock_card_spacing(card_display_size.x))

	for index in range(selectable_stones.size()):
		var slot := Control.new()
		slot.custom_minimum_size = card_display_size
		slot.size = card_display_size
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rock_selection_list.add_child(slot)

		var card := ROCK_WINDOW_SCENE.instantiate() as Control
		if card == null:
			slot.queue_free()
			continue

		slot.add_child(card)
		card.anchor_left = 0.0
		card.anchor_top = 0.0
		card.anchor_right = 0.0
		card.anchor_bottom = 0.0
		card.offset_left = 0.0
		card.offset_top = 0.0
		card.offset_right = ROCK_CARD_LAYOUT_SIZE.x
		card.offset_bottom = ROCK_CARD_LAYOUT_SIZE.y
		card.position = Vector2.ZERO
		card.size = ROCK_CARD_LAYOUT_SIZE
		card.custom_minimum_size = ROCK_CARD_LAYOUT_SIZE
		card.pivot_offset = Vector2.ZERO
		card.scale = Vector2(card_scale, card_scale)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_rock_card_gui_input.bind(index))

		if card.has_method("setup_from_stone"):
			card.call_deferred("setup_from_stone", selectable_stones[index])

		rock_cards.append(card)

	_refresh_rock_selection_ui()


func _get_rock_card_scale() -> float:
	if not is_instance_valid(rock_selection_scroll):
		return ROCK_CARD_MAX_SCALE

	var available_height := rock_selection_scroll.size.y
	if available_height <= 0.0:
		available_height = rock_selection_scroll.get_combined_minimum_size().y

	if available_height <= 0.0:
		return ROCK_CARD_MAX_SCALE

	var target_height := available_height * ROCK_CARD_HEIGHT_FRACTION
	var height_limited_scale := target_height / ROCK_CARD_LAYOUT_SIZE.y
	return clampf(height_limited_scale, ROCK_CARD_MIN_SCALE, ROCK_CARD_MAX_SCALE)


func _get_rock_card_spacing(card_width: float) -> int:
	var spacing := int(round(card_width * 0.06))
	return clampi(spacing, ROCK_CARD_MIN_SPACING, ROCK_CARD_MAX_SPACING)


func _create_default_rock() -> Stone:
	return Stone.new(
		DEFAULT_ROCK_NAME,
		DEFAULT_ROCK_STAT,
		DEFAULT_ROCK_STAT,
		DEFAULT_ROCK_STAT,
		DEFAULT_ROCK_STAT,
		1,
		0,
		Stone.MIN_VARIANT,
		100,
		100,
		100
	)


func _on_rock_card_gui_input(event: InputEvent, stone_index: int) -> void:
	if not human_target_lock_pending:
		return

	var is_click := false
	if event is InputEventMouseButton:
		is_click = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		is_click = event.pressed

	if not is_click:
		return

	if stone_index > 0 and bool(used_stone_indices_this_end.get(stone_index, false)):
		return

	selected_stone_index = stone_index
	_refresh_rock_selection_ui()


func _refresh_rock_selection_ui() -> void:
	if rock_cards.is_empty():
		return

	for index in range(rock_cards.size()):
		var card := rock_cards[index]
		if not is_instance_valid(card):
			continue

		var is_used := index > 0 and bool(used_stone_indices_this_end.get(index, false))
		var is_broken := false
		if index < selectable_stones.size() and selectable_stones[index] != null:
			is_broken = int(selectable_stones[index].condition) <= 0
		var is_selected := index == selected_stone_index

		if card.has_method("set_used_overlay_visible"):
			card.call("set_used_overlay_visible", is_used or is_broken)
		if card.has_method("set_selected_overlay_visible"):
			card.call("set_selected_overlay_visible", is_selected)
		if card.has_method("set_selectable"):
			card.call("set_selectable", not is_used and not is_broken)


func _ensure_valid_selected_rock() -> void:
	if selected_stone_index > 0 and bool(used_stone_indices_this_end.get(selected_stone_index, false)):
		selected_stone_index = 0
	elif selected_stone_index < selectable_stones.size() and selected_stone_index >= 0:
		var selected_stone := selectable_stones[selected_stone_index]
		if selected_stone != null and int(selected_stone.condition) <= 0:
			selected_stone_index = 0


func _set_rock_selection_visible(should_show: bool) -> void:
	if is_instance_valid(rock_selection_panel):
		rock_selection_panel.visible = should_show
	if not should_show:
		_is_drag_scrolling_rock_selection = false


func _is_rock_selection_scroll_available() -> bool:
	return is_instance_valid(rock_selection_panel) and rock_selection_panel.visible and is_instance_valid(rock_selection_scroll)


func _is_pointer_over_rock_selection_scroll(pointer_position: Vector2) -> bool:
	var scroll_rect := Rect2(rock_selection_scroll.global_position, rock_selection_scroll.size)
	return scroll_rect.has_point(pointer_position)


func _scroll_rock_selection_by_delta(delta_x: float) -> void:
	if not is_instance_valid(rock_selection_scroll):
		return

	var target := rock_selection_scroll.scroll_horizontal - int(delta_x)
	var max_scroll := int(_max_rock_selection_horizontal_scroll())
	target = int(clampf(target, 0.0, float(max_scroll)))

	rock_selection_scroll.scroll_horizontal = target


func _max_rock_selection_horizontal_scroll() -> float:
	if not is_instance_valid(rock_selection_scroll):
		return 0.0

	var h_scroll_bar := rock_selection_scroll.get_h_scroll_bar()
	if is_instance_valid(h_scroll_bar):
		return maxf(0.0, h_scroll_bar.max_value)

	if not is_instance_valid(rock_selection_list):
		return 0.0

	return maxf(0.0, rock_selection_list.get_combined_minimum_size().x - rock_selection_scroll.size.x)


func _apply_selected_stone_to_stone_node(stone: RigidBody2D, stone_index: int) -> void:
	if not is_instance_valid(stone):
		return

	if selectable_stones.is_empty():
		return

	var safe_index := clampi(stone_index, 0, selectable_stones.size() - 1)
	stone.set_meta("selected_stone_index", safe_index)
	stone.set_meta("selected_stone_data", selectable_stones[safe_index])
	if stone.has_method("set_throw_profile"):
		stone.set_throw_profile(selectable_stones[safe_index])


func _record_human_stone_wear_from_throw(stone: RigidBody2D) -> void:
	if stone == null or not stone.has_method("get_throw_condition_report"):
		return

	var report: Dictionary = stone.get_throw_condition_report()
	if report.is_empty():
		return

	var stone_index := int(report.get("stone_index", -1))
	var wear := int(report.get("wear", 0))
	if stone_index <= 0 or wear <= 0:
		return

	pending_human_stone_wear_by_index[stone_index] = int(pending_human_stone_wear_by_index.get(stone_index, 0)) + wear
