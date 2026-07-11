extends Node2D

const STONE_SCENE := preload("res://scenes/Stone.tscn")
const STONES_GROUP := "stones"
const DEFAULT_THROW_CONFIG_PATH := "res://data/throw_physics_config.tres"

@export var stone_color: String = "yellow"
@export var clear_previous_stones_each_throw: bool = true
@export var stone_spawn_position := Vector2(360.0, 1000.0)
@export var settled_speed_threshold := 8.0
@export var settled_frames_required := 5
@export var scratch_line_fallback_y := 433.0
@export var rink_end_y := -70.0
@export var camera_overview_position := Vector2(360.0, 640.0)
@export var camera_overview_zoom := Vector2(1.0, 1.0)
@export var camera_house_target_zoom := Vector2(1.0, 1.0)
@export var camera_throw_setup_zoom := Vector2(1.42, 1.42)
@export var camera_follow_zoom := Vector2(1.68, 1.68)
@export var camera_follow_lerp_speed := 8.0
@export var camera_follow_top_margin := 640.0
@export var camera_overview_bottom_padding := 0.0
@export var spawn_from_rink_bottom_margin := 280.0
@export var rink_end_margin := 120.0
@export var camera_bounds_padding := 120.0
@export var target_side_padding := 28.0
@export var throw_config: Resource

var house_center := Vector2.ZERO
var house_radius := 0.0
var rink_top_y := 0.0
var rink_bottom_y := 0.0
var rink_left_x := 0.0
var rink_right_x := 0.0

@onready var camera: Camera2D = $Camera2D
@onready var rink_sprite: Sprite2D = $Rink
@onready var house: Area2D = $Rink/house
@onready var house_area_shape: CollisionShape2D = $Rink/house/houseArea
@onready var scratch_line: Line2D = $Rink/house/scratchline
@onready var target_marker: Polygon2D = get_node_or_null("TargetMarker") as Polygon2D
@onready var lock_target_button: BaseButton = get_node_or_null("CanvasLayer/LockTargetButton") as BaseButton
@onready var stage_prompt_label: Label = get_node_or_null("CanvasLayer/StagePromptLabel") as Label
@onready var scoreboard_panel: CanvasItem = get_node_or_null("CanvasLayer/scoreboard") as CanvasItem
@onready var end_score_label: Label = get_node_or_null("CanvasLayer/EndScoreLabel") as Label
@onready var rock_selection_panel: CanvasItem = get_node_or_null("CanvasLayer/Rockselection") as CanvasItem
@onready var debug_panel: Control = get_node_or_null("CanvasLayer/DebugPanel") as Control
@onready var debug_label: RichTextLabel = get_node_or_null("CanvasLayer/DebugPanel/DebugText") as RichTextLabel
@onready var stat_panel: Control = get_node_or_null("CanvasLayer/StatSelection") as Control
@onready var stat_vbox: Control = get_node_or_null("CanvasLayer/StatSelection/VBoxContainer") as Control
@onready var power_label: RichTextLabel = get_node_or_null("CanvasLayer/StatSelection/VBoxContainer/Power") as RichTextLabel
@onready var spin_label: RichTextLabel = get_node_or_null("CanvasLayer/StatSelection/VBoxContainer/Spin") as RichTextLabel
@onready var precision_label: RichTextLabel = get_node_or_null("CanvasLayer/StatSelection/VBoxContainer/Precision") as RichTextLabel
@onready var power_bar: HSlider = get_node_or_null("CanvasLayer/StatSelection/VBoxContainer/Power/PowerBar") as HSlider
@onready var spin_bar: HSlider = get_node_or_null("CanvasLayer/StatSelection/VBoxContainer/Spin/SpinBar") as HSlider
@onready var precision_bar: HSlider = get_node_or_null("CanvasLayer/StatSelection/VBoxContainer/Precision/PrecisionBar") as HSlider

var active_stone: RigidBody2D
var followed_stone: RigidBody2D
var human_target_lock_pending := false
var has_active_target := false
var active_target_position: Vector2 = Vector2.ZERO
var sandbox_stone_profile := Stone.new("Sandbox", 33, 33, 33, 100, 1, 0, Stone.MIN_VARIANT, 100, 100, 100)


func _ready() -> void:
	randomize()
	_ensure_throw_config()

	if has_node("Rink/walls"):
		$Rink/walls.add_to_group("side_walls")

	_refresh_rink_geometry()
	_setup_ui()
	_wire_stat_selector_inputs()
	_update_stat_selector_ui()
	_spawn_next_stone()


func _setup_ui() -> void:
	if is_instance_valid(end_score_label):
		end_score_label.visible = false

	if is_instance_valid(scoreboard_panel):
		scoreboard_panel.visible = false

	if is_instance_valid(rock_selection_panel):
		rock_selection_panel.visible = false

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

	if is_instance_valid(debug_panel):
		debug_panel.visible = true

	if is_instance_valid(debug_label):
		debug_label.text = "Sandbox ready.\nPlace marker, lock, throw, sweep."

	_set_stat_selector_visible(false)


func _wire_stat_selector_inputs() -> void:
	_connect_stat_slider_input(power_bar, "power")
	_connect_stat_slider_input(spin_bar, "spin")
	_connect_stat_slider_input(precision_bar, "precision")


func _connect_stat_slider_input(slider: HSlider, stat_name: String) -> void:
	if not is_instance_valid(slider):
		return

	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.mouse_filter = Control.MOUSE_FILTER_STOP
	slider.focus_mode = Control.FOCUS_CLICK
	if not slider.value_changed.is_connected(_on_stat_slider_value_changed.bind(stat_name)):
		slider.value_changed.connect(_on_stat_slider_value_changed.bind(stat_name))


func _on_stat_slider_value_changed(value: float, stat_name: String) -> void:
	_set_sandbox_stat(stat_name, int(round(value)))


func _set_sandbox_stat(stat_name: String, value: int) -> void:
	var clamped_value := clampi(value, 0, 100)
	match stat_name:
		"power":
			sandbox_stone_profile.set_power(clamped_value)
		"spin":
			sandbox_stone_profile.set_spin(clamped_value)
		"precision":
			sandbox_stone_profile.set_precision(clamped_value)
		_:
			return

	_update_stat_selector_ui()
	if human_target_lock_pending:
		_apply_profile_to_active_stone()


func _update_stat_selector_ui() -> void:
	if is_instance_valid(power_bar):
		power_bar.value = sandbox_stone_profile.power
	if is_instance_valid(spin_bar):
		spin_bar.value = sandbox_stone_profile.spin
	if is_instance_valid(precision_bar):
		precision_bar.value = sandbox_stone_profile.precision

	if is_instance_valid(power_label):
		power_label.text = "POWER  %d" % sandbox_stone_profile.power
	if is_instance_valid(spin_label):
		spin_label.text = "SPIN  %d" % sandbox_stone_profile.spin
	if is_instance_valid(precision_label):
		precision_label.text = "PRECISION  %d" % sandbox_stone_profile.precision


func _apply_profile_to_active_stone() -> void:
	if not is_instance_valid(active_stone):
		return

	if active_stone.has_method("set_throw_profile"):
		active_stone.set_throw_profile(sandbox_stone_profile)
	active_stone.set_meta("selected_stone_data", sandbox_stone_profile)


func _ensure_throw_config() -> void:
	if throw_config != null:
		return

	var loaded_config := load(DEFAULT_THROW_CONFIG_PATH)
	if loaded_config != null and loaded_config.has_method("get_throw_distance_scale"):
		throw_config = loaded_config


func _process(delta: float) -> void:
	if is_instance_valid(camera) and is_instance_valid(followed_stone):
		var follow_weight := clampf(delta * camera_follow_lerp_speed, 0.0, 1.0)
		var target_y := lerpf(camera.global_position.y, followed_stone.global_position.y, follow_weight)
		camera.global_position = Vector2(camera.global_position.x, target_y)
		camera.global_position = _clamp_camera_center_to_rink(camera.global_position, camera.zoom, camera_follow_top_margin)

	_update_debug_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not human_target_lock_pending:
		return

	if _is_pointing_at_stat_selector():
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


func _is_pointing_at_stat_selector() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if not is_instance_valid(hovered):
		return false

	if is_instance_valid(stat_panel) and (hovered == stat_panel or stat_panel.is_ancestor_of(hovered)):
		return true

	if is_instance_valid(stat_vbox) and (hovered == stat_vbox or stat_vbox.is_ancestor_of(hovered)):
		return true

	return false


func _spawn_next_stone() -> void:
	if clear_previous_stones_each_throw:
		for node in get_tree().get_nodes_in_group(STONES_GROUP):
			if is_instance_valid(node):
				node.queue_free()

	followed_stone = null
	_clear_target_ui()

	var stone := STONE_SCENE.instantiate() as RigidBody2D
	stone.position = stone_spawn_position
	add_child(stone)
	stone.add_to_group(STONES_GROUP)

	if stone.has_method("set_stone_color"):
		stone.set_stone_color(stone_color)
	if stone.has_method("set_throw_config") and throw_config != null:
		stone.set_throw_config(throw_config)
	if stone.has_method("set_throw_profile"):
		stone.set_throw_profile(sandbox_stone_profile)
	stone.set_meta("selected_stone_data", sandbox_stone_profile)
	if stone.has_method("set_throw_distance_scale"):
		stone.set_throw_distance_scale(_get_throw_distance_scale())
	if stone.has_method("set_player_control_enabled"):
		stone.set_player_control_enabled(true)

	stone.stone_stopped.connect(_on_stone_stopped)
	if stone.has_signal("stone_launched"):
		stone.stone_launched.connect(_on_stone_launched)

	active_stone = stone
	_start_human_target_stage(stone)


func _on_stone_launched(stone: RigidBody2D) -> void:
	if stone != active_stone:
		return

	human_target_lock_pending = false
	if is_instance_valid(lock_target_button):
		lock_target_button.visible = false

	_set_stage_prompt("Swipe to sweep")
	followed_stone = stone
	_set_stat_selector_visible(false)
	_set_camera_zoom(camera_follow_zoom)


func _on_stone_stopped(stone: RigidBody2D) -> void:
	if stone != active_stone:
		return

	_clear_target_ui()
	_set_stage_prompt("")

	await _wait_for_all_stones_to_settle()
	_prune_out_of_play_stones()
	_spawn_next_stone()


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
	var scratch_line_y: float = _get_scratch_line_y()

	for node in get_tree().get_nodes_in_group(STONES_GROUP):
		if not is_instance_valid(node):
			continue

		var stone := node as RigidBody2D
		if stone == null:
			continue

		if stone.has_method("should_remove_on_reset") and stone.should_remove_on_reset(scratch_line_y, rink_end_y):
			stone.queue_free()


func _get_throw_distance_scale() -> float:
	var throw_distance: float = maxf(absf(stone_spawn_position.y - house_center.y), 1.0)
	if throw_config == null or not throw_config.has_method("get_throw_distance_scale"):
		_ensure_throw_config()
	if throw_config == null or not throw_config.has_method("get_throw_distance_scale"):
		return 1.0

	return float(throw_config.call("get_throw_distance_scale", throw_distance))


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


func _get_top_aligned_camera_center_y(zoom: Vector2) -> float:
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.y <= 0.0:
		return rink_top_y

	var half_view_height_world := viewport_size.y * 0.5 * zoom.y
	return rink_top_y + half_view_height_world


func _clamp_camera_center_to_rink(center: Vector2, zoom: Vector2, top_margin: float = 0.0) -> Vector2:
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.y <= 0.0:
		return center

	var half_view_height_world := viewport_size.y * 0.5 * zoom.y
	var min_center_y := rink_top_y + half_view_height_world - maxf(top_margin, 0.0)
	return Vector2(center.x, maxf(center.y, min_center_y))


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


func _get_scratch_line_y() -> float:
	if is_instance_valid(scratch_line) and scratch_line.points.size() > 0:
		return scratch_line.to_global(scratch_line.points[0]).y

	return scratch_line_fallback_y


func _move_camera_to_house_target(focus_position: Vector2 = Vector2.INF) -> void:
	if not is_instance_valid(camera):
		return

	var desired_target := Vector2(house_center.x, _get_top_aligned_camera_center_y(camera_house_target_zoom))
	if focus_position != Vector2.INF:
		desired_target.y = focus_position.y

	camera.global_position = _clamp_camera_center_to_rink(desired_target, camera_house_target_zoom)
	camera.zoom = camera_house_target_zoom


func _set_camera_zoom(target_zoom: Vector2) -> void:
	if not is_instance_valid(camera):
		return

	camera.zoom = target_zoom


func _start_human_target_stage(stone: RigidBody2D) -> void:
	human_target_lock_pending = true
	has_active_target = false
	active_target_position = Vector2.ZERO
	_apply_profile_to_active_stone()
	_set_stat_selector_visible(true)

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

	human_target_lock_pending = false
	if is_instance_valid(lock_target_button):
		lock_target_button.visible = false
	_set_stat_selector_visible(false)

	if active_stone.has_method("confirm_target_marker"):
		active_stone.confirm_target_marker()

	_set_stage_prompt("Drag from stone to set direction and power")
	_move_camera_to_throw_setup(active_stone.global_position)


func _move_camera_to_throw_setup(target_position: Vector2) -> void:
	if not is_instance_valid(camera):
		return

	camera.global_position = _clamp_camera_center_to_rink(target_position, camera_throw_setup_zoom)
	camera.zoom = camera_throw_setup_zoom


func _clear_target_ui() -> void:
	human_target_lock_pending = false
	has_active_target = false
	active_target_position = Vector2.ZERO
	_set_stat_selector_visible(false)
	if is_instance_valid(target_marker):
		target_marker.visible = false
	if is_instance_valid(lock_target_button):
		lock_target_button.visible = false
		lock_target_button.disabled = true


func _set_stat_selector_visible(show_selector: bool) -> void:
	if is_instance_valid(stat_panel):
		stat_panel.visible = show_selector
	if is_instance_valid(stat_vbox):
		stat_vbox.visible = show_selector


func _set_stage_prompt(text: String) -> void:
	if not is_instance_valid(stage_prompt_label):
		return

	stage_prompt_label.text = text
	stage_prompt_label.visible = text != ""


func _update_debug_panel() -> void:
	if not is_instance_valid(debug_label):
		return

	if not is_instance_valid(active_stone) or not active_stone.has_method("get_debug_telemetry"):
		debug_label.text = "Sandbox ready.\nWaiting for active stone telemetry..."
		return

	var telemetry: Dictionary = active_stone.get_debug_telemetry()
	if telemetry.is_empty():
		debug_label.text = "Sandbox ready.\nTelemetry unavailable."
		return

	var speed := float(telemetry.get("speed", 0.0))
	var velocity: Vector2 = telemetry.get("velocity", Vector2.ZERO)
	var decel := float(telemetry.get("deceleration", 0.0))
	var curl_force: Vector2 = telemetry.get("curl_force", Vector2.ZERO)
	var sweep_force: Vector2 = telemetry.get("sweep_force", Vector2.ZERO)
	var total_force: Vector2 = telemetry.get("total_force", Vector2.ZERO)
	var spin := float(telemetry.get("spin_degrees", 0.0))
	var phase := int(telemetry.get("throw_phase", -1))
	var has_target_marker := bool(telemetry.get("has_target_marker", false))
	var marker_debug: Dictionary = telemetry.get("marker_debug", {})
	var live_target_distance := float(marker_debug.get("live_target_distance", 0.0))
	var live_simulated_distance := float(marker_debug.get("live_simulated_distance", 0.0))
	var live_distance_delta := float(marker_debug.get("live_distance_delta", 0.0))
	var live_green_window := float(marker_debug.get("live_green_window", 0.0))
	var live_match_strength := float(marker_debug.get("live_match_strength", 0.0))
	var launch_target_distance := float(marker_debug.get("launch_target_distance", 0.0))
	var launch_simulated_distance := float(marker_debug.get("launch_simulated_distance", 0.0))
	var launch_distance_delta := float(marker_debug.get("launch_distance_delta", 0.0))
	var launch_green_window := float(marker_debug.get("launch_green_window", 0.0))
	var final_travel_distance := float(marker_debug.get("final_travel_distance", 0.0))
	var final_target_delta := float(marker_debug.get("final_target_delta", 0.0))
	var final_prediction_delta := float(marker_debug.get("final_prediction_delta", 0.0))
	var throw_debug: Dictionary = telemetry.get("throw_debug", {})
	var throw_id := int(throw_debug.get("throw_id", 0))
	var drag_length := float(throw_debug.get("drag_length", 0.0))
	var launch_power_ratio := float(throw_debug.get("launch_power_ratio", 0.0))
	var scaled_min_power := float(throw_debug.get("scaled_min_power", 0.0))
	var scaled_max_power := float(throw_debug.get("scaled_max_power", 0.0))
	var power_multiplier := float(throw_debug.get("power_multiplier", 1.0))
	var power_jitter_multiplier := float(throw_debug.get("power_jitter_multiplier", 1.0))
	var pending_launch_power := float(throw_debug.get("pending_launch_power", 0.0))
	var launch_speed := float(throw_debug.get("launch_speed", 0.0))
	var predicted_decel_only_distance := float(throw_debug.get("predicted_decel_only_distance", 0.0))
	var predicted_full_distance := float(throw_debug.get("predicted_full_distance", 0.0))
	var runtime_distance := float(throw_debug.get("runtime_distance", 0.0))
	var integrated_decel := float(throw_debug.get("integrated_decel", 0.0))
	var integrated_forward_sweep := float(throw_debug.get("integrated_forward_sweep", 0.0))
	var stage_time_early := float(throw_debug.get("stage_time_early", 0.0))
	var stage_time_mid := float(throw_debug.get("stage_time_mid", 0.0))
	var stage_time_tail := float(throw_debug.get("stage_time_tail", 0.0))
	var along_track_error := float(throw_debug.get("along_track_error", 0.0))
	var cross_track_error := float(throw_debug.get("cross_track_error", 0.0))
	var sample_count := int(throw_debug.get("sample_count", 0))

	debug_label.text = "[b]Physics Sandbox[/b]\n"
	debug_label.text += "Phase: %d\n" % phase
	debug_label.text += "Speed: %.2f px/s\n" % speed
	debug_label.text += "Velocity: (%.2f, %.2f)\n" % [velocity.x, velocity.y]
	debug_label.text += "Decel: %.2f px/s^2\n" % decel
	debug_label.text += "Spin: %.2f deg\n" % spin
	debug_label.text += "Curl force: (%.2f, %.2f)\n" % [curl_force.x, curl_force.y]
	debug_label.text += "Sweep force: (%.2f, %.2f)\n" % [sweep_force.x, sweep_force.y]
	debug_label.text += "Total force: (%.2f, %.2f)\n" % [total_force.x, total_force.y]
	debug_label.text += "\n[b]Marker Accuracy[/b]\n"
	debug_label.text += "Marker active: %s\n" % ("yes" if has_target_marker else "no")
	if has_target_marker:
		debug_label.text += "Aim sim/target: %.1f / %.1f px\n" % [live_simulated_distance, live_target_distance]
		debug_label.text += "Aim delta: %.1f px (window %.1f, strength %.2f)\n" % [live_distance_delta, live_green_window, live_match_strength]
		debug_label.text += "Launch sim/target: %.1f / %.1f px\n" % [launch_simulated_distance, launch_target_distance]
		debug_label.text += "Launch delta: %.1f px (window %.1f)\n" % [launch_distance_delta, launch_green_window]
		if final_travel_distance > 0.0:
			debug_label.text += "Final travel: %.1f px\n" % final_travel_distance
			debug_label.text += "Final-target error: %.1f px\n" % final_target_delta
			debug_label.text += "Final-prediction error: %.1f px\n" % final_prediction_delta

	debug_label.text += "\n[b]Throw Diagnostics[/b]\n"
	debug_label.text += "Throw id: %d\n" % throw_id
	debug_label.text += "Drag len / ratio: %.1f px / %.3f\n" % [drag_length, launch_power_ratio]
	debug_label.text += "Scaled min/max: %.1f / %.1f\n" % [scaled_min_power, scaled_max_power]
	debug_label.text += "Power mult/jitter: %.3f / %.3f\n" % [power_multiplier, power_jitter_multiplier]
	debug_label.text += "Pending power / speed: %.1f / %.1f\n" % [pending_launch_power, launch_speed]
	debug_label.text += "Predicted decel/full: %.1f / %.1f px\n" % [predicted_decel_only_distance, predicted_full_distance]
	debug_label.text += "Runtime dist: %.1f px\n" % runtime_distance
	debug_label.text += "Along/Cross error: %.1f / %.1f px\n" % [along_track_error, cross_track_error]
	debug_label.text += "Stage time E/M/T: %.2f / %.2f / %.2f s\n" % [stage_time_early, stage_time_mid, stage_time_tail]
	debug_label.text += "Int decel / fwd sweep: %.1f / %.1f\n" % [integrated_decel, integrated_forward_sweep]
	debug_label.text += "Samples: %d\n" % sample_count
