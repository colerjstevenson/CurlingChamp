extends RigidBody2D

signal stone_stopped(stone: RigidBody2D)
signal stone_launched(stone: RigidBody2D)
signal spin_selection_started(stone: RigidBody2D)
signal spin_selection_completed(stone: RigidBody2D)
signal target_selection_started(stone: RigidBody2D)
signal target_selected(stone: RigidBody2D, target_position: Vector2)
signal target_locked(stone: RigidBody2D, target_position: Vector2)
signal sweep_started(stone: RigidBody2D)
signal sweep_ended(stone: RigidBody2D)

const BLUE_TOP_TEXTURE := preload("res://assets/curling/stones/stone_blue_top.png")
const RED_TOP_TEXTURE := preload("res://assets/curling/stones/stone_red_top.png")
const YELLOW_TOP_TEXTURE := preload("res://assets/curling/stones/stone_yellow_top.png")
const WALLS_GROUP := "side_walls"
const STONES_GROUP := "stones"
const DEFAULT_THROW_CONFIG_PATH := "res://data/throw_physics_config.tres"
const DEBUG_THROW_SAMPLE_INTERVAL := 0.1
const DEBUG_THROW_MAX_SAMPLES := 120

enum ThrowPhase {
	PHASE_TARGET_MARKER,
	PHASE_CONFIRM_MARKER,
	PHASE_SET_SHOT,
	PHASE_SET_SPIN,
	PHASE_IN_FLIGHT,
	PHASE_SETTLED,
}

var dragging = false
var drag_start = Vector2()
var pending_launch_direction: Vector2 = Vector2.ZERO
var pending_launch_power: float = 0.0
var current_spin_degrees: float = 0.0
var has_launched := false
var has_reported_stop := false
var can_aim := true
var player_control_enabled := true
var stone_color := "blue"
var touched_side_wall := false
var throw_phase: ThrowPhase = ThrowPhase.PHASE_TARGET_MARKER
var has_target_marker := false
var target_marker_position: Vector2 = Vector2.ZERO
var sweep_forward_boost := 0.0
var sweep_lateral_boost := 0.0
var sweep_applied_forward_boost := 0.0
var sweep_applied_lateral_boost := 0.0
var sweep_total_influence := 0.0
var sweep_was_active := false
var sweep_particles: GPUParticles2D
var sweep_particles_on_canvas_layer := false
var _throw_profile: Dictionary = {}
var _condition_wear_total := 0
var _selected_stone_condition := 0
var _debug_last_speed := 0.0
var _debug_last_deceleration := 0.0
var _debug_last_curl_force := Vector2.ZERO
var _debug_last_sweep_force := Vector2.ZERO
var _debug_last_total_force := Vector2.ZERO
var _debug_marker_live_target_distance := 0.0
var _debug_marker_live_simulated_distance := 0.0
var _debug_marker_live_distance_delta := 0.0
var _debug_marker_live_green_window := 0.0
var _debug_marker_live_match_strength := 0.0
var _debug_marker_launch_target_distance := 0.0
var _debug_marker_launch_simulated_distance := 0.0
var _debug_marker_launch_distance_delta := 0.0
var _debug_marker_launch_green_window := 0.0
var _debug_marker_launch_start_position := Vector2.ZERO
var _debug_marker_final_travel_distance := 0.0
var _debug_marker_final_target_delta := 0.0
var _debug_marker_final_prediction_delta := 0.0
var _debug_throw_id := 0
var _debug_throw_drag_length := 0.0
var _debug_throw_launch_power_ratio := 0.0
var _debug_throw_scaled_min_power := 0.0
var _debug_throw_scaled_max_power := 0.0
var _debug_throw_power_multiplier := 1.0
var _debug_throw_power_jitter_multiplier := 1.0
var _debug_throw_pending_launch_power := 0.0
var _debug_throw_launch_speed := 0.0
var _debug_throw_predicted_decel_only_distance := 0.0
var _debug_throw_predicted_full_distance := 0.0
var _debug_throw_launch_direction := Vector2.ZERO
var _debug_throw_elapsed := 0.0
var _debug_throw_next_sample_time := 0.0
var _debug_throw_distance_accum := 0.0
var _debug_throw_last_position := Vector2.ZERO
var _debug_throw_integrated_decel := 0.0
var _debug_throw_integrated_forward_sweep := 0.0
var _debug_throw_stage_time_early := 0.0
var _debug_throw_stage_time_mid := 0.0
var _debug_throw_stage_time_tail := 0.0
var _debug_throw_along_track_error := 0.0
var _debug_throw_cross_track_error := 0.0
var _debug_throw_samples: Array = []
var _marker_required_speed_cache_distance := -1.0
var _marker_required_speed_cache_value := 0.0
@onready var stone_sprite: Sprite2D = $Sprite

@export var throw_config: Resource

var grab_radius := 64.0
var min_power := 260.0
var max_power := 800.0
var arrow_max_length := 150.0
var min_launch_pull_ratio := 0.12
var launch_speed_multiplier := 1.35
var throw_distance_scale := 1.0
var min_throw_distance_scale := 0.75
var max_throw_distance_scale := 2.0
var arrow_low_power_color := Color(1.0, 0.95, 0.2, 0.95)
var arrow_high_power_color := Color(1.0, 0.15, 0.1, 0.98)
var arrow_weight_match_color := Color(0.2, 1.0, 0.25, 0.98)
var marker_green_window_low := 130.0
var marker_green_window_high := 48.0
var marker_green_window_precision_exponent := 1.35
var marker_green_window_distance_ratio := 0.09
var stop_deceleration := 320.0
var low_speed_threshold := 180.0
var extra_low_speed_deceleration := 220.0
var stop_speed_cutoff := 6.0
var use_staged_deceleration_profile := true
var decel_stage_early_value := 220.0
var decel_stage_mid_value := 245.0
var decel_stage_tail_value := 95.0
var decel_stage_mid_speed := 130.0
var decel_stage_tail_speed := 48.0
var decel_stage_blend_band := 40.0
var max_spin_input_degrees := 270.0
var spin_setter_max_spin_degrees := 150.0
var max_curl_acceleration := 420.0
var max_visual_spin_speed_degrees := 900.0
var guide_line_color := Color(1.0, 0.75, 0.75, 0.75)
var guide_line_width := 2.0
var sweep_max_forward_boost := 30.0
var sweep_max_lateral_boost := 20.0
var sweep_decay_rate := 45.0
var sweep_speed_floor := 90.0
var sweep_total_influence_cap := 120.0
@export var sweep_use_proximity_model := true
@export var sweep_influence_radius := 130.0
@export var sweep_front_weight := 1.0
@export var sweep_side_weight := 0.75
@export var sweep_side_front_gate_bias := 0.3
var sweep_proximity_max_force := 42.0
var sweep_low_speed_amp_min := 1.0
var sweep_low_speed_amp_max := 1.8
var sweep_low_speed_amp_start_speed := 170.0
var sweep_low_speed_amp_end_speed := 55.0
var sweep_force_blend_rate := 160.0
var sweep_spin_lateral_preserve_min := 0.58
var sweep_spin_lateral_blend := 0.85
@export var sweep_particle_offset := Vector2(0.0, 20.0)
@export var sweep_particle_color := Color8(255, 174, 23, 230)
@export var sweep_particle_amount := 26
@export var sweep_particle_lifetime := 0.34

const SpinSetter = preload("res://scenes/controls/spin_setter.tscn")


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Keep travel fully controlled by our scripted deceleration model.
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	_ensure_throw_config()
	_apply_throw_config()
	_setup_sweep_particles()


func _exit_tree() -> void:
	if not is_instance_valid(sweep_particles):
		return

	sweep_particles.emitting = false
	sweep_particles.queue_free()


func _setup_sweep_particles() -> void:
	sweep_particles = GPUParticles2D.new()
	sweep_particles.name = "SweepParticles"
	sweep_particles.amount = maxi(1, sweep_particle_amount)
	sweep_particles.lifetime = maxf(0.05, sweep_particle_lifetime)
	sweep_particles.one_shot = false
	sweep_particles.explosiveness = 0.25
	sweep_particles.randomness = 0.6
	sweep_particles.local_coords = true
	sweep_particles.emitting = false
	sweep_particles.position = sweep_particle_offset
	sweep_particles.modulate = sweep_particle_color
	sweep_particles.z_index = 3
	sweep_particles.texture = _build_sweep_particle_texture()

	var particle_material := ParticleProcessMaterial.new()
	particle_material.direction = Vector3(0.0, 1.0, 0.0)
	particle_material.spread = 40.0
	particle_material.gravity = Vector3(0.0, 260.0, 0.0)
	particle_material.initial_velocity_min = 32.0
	particle_material.initial_velocity_max = 68.0
	particle_material.scale_min = 0.5
	particle_material.scale_max = 1.0
	sweep_particles.process_material = particle_material

	var particle_parent: Node = self
	var current_scene := get_tree().current_scene
	if is_instance_valid(current_scene):
		var canvas_layer := current_scene.get_node_or_null("CanvasLayer")
		if is_instance_valid(canvas_layer):
			particle_parent = canvas_layer
			sweep_particles_on_canvas_layer = true

	particle_parent.add_child(sweep_particles)


func _build_sweep_particle_texture() -> Texture2D:
	var image := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center := Vector2(5.0, 5.0)
	for y in range(10):
		for x in range(10):
			var dist := Vector2(float(x), float(y)).distance_to(center)
			if dist > 4.6:
				continue
			var alpha := clampf(1.0 - (dist / 4.6), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	return ImageTexture.create_from_image(image)


func _set_sweep_particles_active(active: bool) -> void:
	if not is_instance_valid(sweep_particles):
		return

	sweep_particles.emitting = active


func _update_sweep_particles_position_from_event(event: InputEvent) -> void:
	if not is_instance_valid(sweep_particles):
		return

	var screen_position := Vector2.ZERO
	if event is InputEventScreenDrag:
		screen_position = event.position
	elif event is InputEventMouseMotion:
		screen_position = event.position
	else:
		return

	if sweep_particles_on_canvas_layer:
		sweep_particles.position = screen_position + sweep_particle_offset
		return

	var canvas_transform := get_viewport().get_canvas_transform()
	var world_position := canvas_transform.affine_inverse() * screen_position
	sweep_particles.global_position = world_position + sweep_particle_offset


func set_throw_config(config: Resource) -> void:
	throw_config = config
	_apply_throw_config()


func set_throw_profile(selected_stone: Stone) -> void:
	if throw_config == null:
		_ensure_throw_config()

	if throw_config == null:
		_throw_profile = {}
		_selected_stone_condition = 0
		return

	_throw_profile = throw_config.call("build_throw_profile", selected_stone, true)
	_selected_stone_condition = 0 if selected_stone == null else int(selected_stone.condition)
	_condition_wear_total = 0


func get_throw_condition_report() -> Dictionary:
	if _throw_profile.is_empty() and _condition_wear_total <= 0:
		return {}

	var stone_index := -1
	if has_meta("selected_stone_index"):
		stone_index = int(get_meta("selected_stone_index"))

	return {
		"stone_index": stone_index,
		"wear": _condition_wear_total,
		"selected_condition": _selected_stone_condition,
		"broken": _selected_stone_condition > 0 and (_selected_stone_condition - _condition_wear_total) <= 0,
	}


func get_debug_telemetry() -> Dictionary:
	return {
		"speed": _debug_last_speed,
		"velocity": linear_velocity,
		"deceleration": _debug_last_deceleration,
		"curl_force": _debug_last_curl_force,
		"sweep_force": _debug_last_sweep_force,
		"total_force": _debug_last_total_force,
		"spin_degrees": current_spin_degrees,
		"throw_phase": int(throw_phase),
		"has_target_marker": has_target_marker,
		"target_marker_position": target_marker_position,
		"marker_debug": {
			"live_target_distance": _debug_marker_live_target_distance,
			"live_simulated_distance": _debug_marker_live_simulated_distance,
			"live_distance_delta": _debug_marker_live_distance_delta,
			"live_green_window": _debug_marker_live_green_window,
			"live_match_strength": _debug_marker_live_match_strength,
			"launch_target_distance": _debug_marker_launch_target_distance,
			"launch_simulated_distance": _debug_marker_launch_simulated_distance,
			"launch_distance_delta": _debug_marker_launch_distance_delta,
			"launch_green_window": _debug_marker_launch_green_window,
			"launch_start_position": _debug_marker_launch_start_position,
			"final_travel_distance": _debug_marker_final_travel_distance,
			"final_target_delta": _debug_marker_final_target_delta,
			"final_prediction_delta": _debug_marker_final_prediction_delta,
		},
		"throw_debug": {
			"throw_id": _debug_throw_id,
			"drag_length": _debug_throw_drag_length,
			"launch_power_ratio": _debug_throw_launch_power_ratio,
			"scaled_min_power": _debug_throw_scaled_min_power,
			"scaled_max_power": _debug_throw_scaled_max_power,
			"power_multiplier": _debug_throw_power_multiplier,
			"power_jitter_multiplier": _debug_throw_power_jitter_multiplier,
			"pending_launch_power": _debug_throw_pending_launch_power,
			"launch_speed": _debug_throw_launch_speed,
			"predicted_decel_only_distance": _debug_throw_predicted_decel_only_distance,
			"predicted_full_distance": _debug_throw_predicted_full_distance,
			"runtime_distance": _debug_throw_distance_accum,
			"integrated_decel": _debug_throw_integrated_decel,
			"integrated_forward_sweep": _debug_throw_integrated_forward_sweep,
			"stage_time_early": _debug_throw_stage_time_early,
			"stage_time_mid": _debug_throw_stage_time_mid,
			"stage_time_tail": _debug_throw_stage_time_tail,
			"along_track_error": _debug_throw_along_track_error,
			"cross_track_error": _debug_throw_cross_track_error,
			"sample_count": _debug_throw_samples.size(),
			"samples": _debug_throw_samples,
		},
	}


func _ensure_throw_config() -> void:
	if throw_config != null:
		return

	var loaded_config := load(DEFAULT_THROW_CONFIG_PATH)
	if loaded_config != null and loaded_config.has_method("build_throw_profile"):
		throw_config = loaded_config


func _apply_throw_config() -> void:
	if throw_config == null:
		return

	grab_radius = float(_get_throw_config_value("grab_radius", grab_radius))
	min_power = float(_get_throw_config_value("min_power", min_power))
	max_power = float(_get_throw_config_value("max_power", max_power))
	arrow_max_length = float(_get_throw_config_value("arrow_max_length", arrow_max_length))
	min_launch_pull_ratio = clampf(float(_get_throw_config_value("min_launch_pull_ratio", min_launch_pull_ratio)), 0.0, 1.0)
	launch_speed_multiplier = float(_get_throw_config_value("launch_speed_multiplier", launch_speed_multiplier))
	min_throw_distance_scale = float(_get_throw_config_value("min_throw_distance_scale", min_throw_distance_scale))
	max_throw_distance_scale = float(_get_throw_config_value("max_throw_distance_scale", max_throw_distance_scale))
	min_power = clampf(min_power, 0.0, max_power)
	stop_deceleration = float(_get_throw_config_value("stop_deceleration", stop_deceleration))
	low_speed_threshold = float(_get_throw_config_value("low_speed_threshold", low_speed_threshold))
	extra_low_speed_deceleration = float(_get_throw_config_value("extra_low_speed_deceleration", extra_low_speed_deceleration))
	stop_speed_cutoff = float(_get_throw_config_value("stop_speed_cutoff", stop_speed_cutoff))
	use_staged_deceleration_profile = bool(_get_throw_config_value("use_staged_deceleration_profile", use_staged_deceleration_profile))
	decel_stage_early_value = float(_get_throw_config_value("decel_stage_early_value", decel_stage_early_value))
	decel_stage_mid_value = float(_get_throw_config_value("decel_stage_mid_value", decel_stage_mid_value))
	decel_stage_tail_value = float(_get_throw_config_value("decel_stage_tail_value", decel_stage_tail_value))
	decel_stage_mid_speed = float(_get_throw_config_value("decel_stage_mid_speed", decel_stage_mid_speed))
	decel_stage_tail_speed = float(_get_throw_config_value("decel_stage_tail_speed", decel_stage_tail_speed))
	decel_stage_blend_band = float(_get_throw_config_value("decel_stage_blend_band", decel_stage_blend_band))
	max_spin_input_degrees = float(_get_throw_config_value("max_spin_input_degrees", max_spin_input_degrees))
	spin_setter_max_spin_degrees = float(_get_throw_config_value("spin_setter_max_spin_degrees", spin_setter_max_spin_degrees))
	max_curl_acceleration = float(_get_throw_config_value("max_curl_acceleration", max_curl_acceleration))
	max_visual_spin_speed_degrees = float(_get_throw_config_value("max_visual_spin_speed_degrees", max_visual_spin_speed_degrees))
	guide_line_width = float(_get_throw_config_value("guide_line_width", guide_line_width))
	marker_green_window_low = float(_get_throw_config_value("marker_green_window_low", marker_green_window_low))
	marker_green_window_high = float(_get_throw_config_value("marker_green_window_high", marker_green_window_high))
	marker_green_window_precision_exponent = float(_get_throw_config_value("marker_green_window_precision_exponent", marker_green_window_precision_exponent))
	marker_green_window_distance_ratio = float(_get_throw_config_value("marker_green_window_distance_ratio", marker_green_window_distance_ratio))
	sweep_max_forward_boost = float(_get_throw_config_value("sweep_max_forward_boost", sweep_max_forward_boost))
	sweep_max_lateral_boost = float(_get_throw_config_value("sweep_max_lateral_boost", sweep_max_lateral_boost))
	sweep_decay_rate = float(_get_throw_config_value("sweep_decay_rate", sweep_decay_rate))
	sweep_speed_floor = float(_get_throw_config_value("sweep_speed_floor", sweep_speed_floor))
	sweep_total_influence_cap = float(_get_throw_config_value("sweep_total_influence_cap", sweep_total_influence_cap))
	sweep_use_proximity_model = bool(_get_throw_config_value("sweep_use_proximity_model", sweep_use_proximity_model))
	sweep_influence_radius = float(_get_throw_config_value("sweep_influence_radius", sweep_influence_radius))
	sweep_front_weight = float(_get_throw_config_value("sweep_front_weight", sweep_front_weight))
	sweep_side_weight = float(_get_throw_config_value("sweep_side_weight", sweep_side_weight))
	sweep_proximity_max_force = float(_get_throw_config_value("sweep_proximity_max_force", sweep_proximity_max_force))
	sweep_low_speed_amp_min = float(_get_throw_config_value("sweep_low_speed_amp_min", sweep_low_speed_amp_min))
	sweep_low_speed_amp_max = float(_get_throw_config_value("sweep_low_speed_amp_max", sweep_low_speed_amp_max))
	sweep_low_speed_amp_start_speed = float(_get_throw_config_value("sweep_low_speed_amp_start_speed", sweep_low_speed_amp_start_speed))
	sweep_low_speed_amp_end_speed = float(_get_throw_config_value("sweep_low_speed_amp_end_speed", sweep_low_speed_amp_end_speed))
	sweep_spin_lateral_preserve_min = float(_get_throw_config_value("sweep_spin_lateral_preserve_min", sweep_spin_lateral_preserve_min))
	sweep_spin_lateral_blend = float(_get_throw_config_value("sweep_spin_lateral_blend", sweep_spin_lateral_blend))
	_marker_required_speed_cache_distance = -1.0
	if throw_config.has_method("build_throw_profile"):
		_throw_profile = throw_config.call("build_throw_profile", Stone.new("", 33, 33, 33, 33, 1, 0, Stone.MIN_VARIANT, 100, 100, 100), false)


func _get_throw_config_value(property_name: String, fallback_value: Variant) -> Variant:
	if throw_config == null:
		return fallback_value

	var value: Variant = throw_config.get(property_name)
	if value == null:
		return fallback_value

	return value


func set_stone_color(color: String) -> void:
	stone_color = color
	match color:
		"red":
			stone_sprite.texture = RED_TOP_TEXTURE
		"yellow":
			stone_sprite.texture = YELLOW_TOP_TEXTURE
		_:
			stone_sprite.texture = BLUE_TOP_TEXTURE


func set_player_control_enabled(enabled: bool) -> void:
	player_control_enabled = enabled
	throw_phase = ThrowPhase.PHASE_TARGET_MARKER if enabled else ThrowPhase.PHASE_SET_SHOT
	can_aim = not enabled
	if not enabled:
		dragging = false
		has_target_marker = false
		queue_redraw()


func set_throw_phase_targeting() -> void:
	if not player_control_enabled:
		return
	throw_phase = ThrowPhase.PHASE_TARGET_MARKER
	can_aim = false
	dragging = false
	target_selection_started.emit(self)
	queue_redraw()


func set_target_marker_position(target_position: Vector2) -> void:
	if not player_control_enabled:
		return
	has_target_marker = true
	target_marker_position = target_position
	_marker_required_speed_cache_distance = -1.0
	throw_phase = ThrowPhase.PHASE_CONFIRM_MARKER
	target_selected.emit(self, target_marker_position)
	queue_redraw()


func confirm_target_marker() -> void:
	if not player_control_enabled or not has_target_marker:
		return
	throw_phase = ThrowPhase.PHASE_SET_SHOT
	can_aim = true
	target_locked.emit(self, target_marker_position)
	queue_redraw()


func has_valid_target_marker() -> bool:
	return has_target_marker


func set_throw_distance_scale(distance_scale: float) -> void:
	throw_distance_scale = clampf(distance_scale, min_throw_distance_scale, max_throw_distance_scale)


func launch_shot(direction: Vector2, power: float, spin_degrees: float) -> void:
	if direction == Vector2.ZERO:
		return

	can_aim = false
	dragging = false
	var profile := _get_active_throw_profile()
	pending_launch_direction = direction.normalized().rotated(deg_to_rad(float(profile.get("launch_aim_jitter_degrees", 0.0))))
	var scaled_min_power: float = min_power * throw_distance_scale
	var scaled_max_power: float = max_power * throw_distance_scale
	var power_multiplier := float(profile.get("power_multiplier", 1.0))
	var power_jitter_multiplier := float(profile.get("launch_power_jitter_multiplier", 1.0))
	pending_launch_power = clampf(power * power_multiplier * power_jitter_multiplier, scaled_min_power, scaled_max_power)
	throw_phase = ThrowPhase.PHASE_IN_FLIGHT
	_launch_with_spin(spin_degrees)


func _input(event):
	if not player_control_enabled:
		return

	if throw_phase == ThrowPhase.PHASE_IN_FLIGHT:
		_handle_sweep_input(event)
		return

	if throw_phase != ThrowPhase.PHASE_SET_SHOT:
		return

	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed and can_aim and not dragging and get_global_mouse_position().distance_to(global_position) < grab_radius:
			dragging = true
			drag_start = get_global_mouse_position()
			linear_velocity = Vector2.ZERO
			freeze = true
		elif dragging and not event.pressed:
			dragging = false
			var drag_vector = drag_start - get_global_mouse_position()
			var launch_vector = drag_vector.limit_length(arrow_max_length)
			var pull_ratio: float = clampf(launch_vector.length() / arrow_max_length, 0.0, 1.0)

			if pull_ratio < min_launch_pull_ratio:
				# Ignore weak pullbacks so quick clicks/releases do not produce limp misfires.
				can_aim = true
				throw_phase = ThrowPhase.PHASE_SET_SHOT
				freeze = false
				pending_launch_direction = Vector2.ZERO
				pending_launch_power = 0.0
				_debug_throw_drag_length = launch_vector.length()
				_debug_throw_launch_power_ratio = pull_ratio
				queue_redraw()
				return

			can_aim = false
			throw_phase = ThrowPhase.PHASE_SET_SPIN
			var scaled_min_power: float = min_power * throw_distance_scale
			var scaled_max_power: float = max_power * throw_distance_scale
			var power: float = lerpf(scaled_min_power, scaled_max_power, pull_ratio)
			var direction = launch_vector.normalized()
			var profile := _get_active_throw_profile()
			var power_multiplier := float(profile.get("power_multiplier", 1.0))
			var power_jitter_multiplier := float(profile.get("launch_power_jitter_multiplier", 1.0))
			
			# Store launch parameters and show spin setter
			pending_launch_direction = direction.rotated(deg_to_rad(float(profile.get("launch_aim_jitter_degrees", 0.0))))
			pending_launch_power = clampf(power * power_multiplier * power_jitter_multiplier, scaled_min_power, scaled_max_power)
			_debug_throw_drag_length = launch_vector.length()
			_debug_throw_launch_power_ratio = pull_ratio
			_show_spin_setter()
			queue_redraw()

func _draw():
	if throw_phase == ThrowPhase.PHASE_SET_SHOT and has_target_marker:
		var local_target := to_local(target_marker_position)
		draw_line(Vector2.ZERO, local_target, guide_line_color, guide_line_width)

	if dragging:
		var aim_vector = (drag_start - get_global_mouse_position()).limit_length(arrow_max_length)
		if aim_vector.length() < 8.0:
			return
		var power_ratio: float = clampf(aim_vector.length() / arrow_max_length, 0.0, 1.0)
		var arrow_color: Color = arrow_low_power_color.lerp(arrow_high_power_color, power_ratio)
		var marker_match_strength := _get_marker_weight_match_strength(power_ratio)
		if marker_match_strength > 0.0:
			arrow_color = arrow_color.lerp(arrow_weight_match_color, marker_match_strength)

		var tip = aim_vector
		draw_line(Vector2.ZERO, tip, arrow_color, 4.0)

		var head_length = min(28.0, aim_vector.length() * 0.25)
		var left = tip - aim_vector.normalized().rotated(deg_to_rad(28.0)) * head_length
		var right = tip - aim_vector.normalized().rotated(deg_to_rad(-28.0)) * head_length
		draw_line(tip, left, arrow_color, 4.0)
		draw_line(tip, right, arrow_color, 4.0)

func _process(_delta):
	if dragging:
		queue_redraw()

func _physics_process(delta):
	if dragging or freeze:
		_debug_last_speed = 0.0
		_debug_last_deceleration = 0.0
		_debug_last_curl_force = Vector2.ZERO
		_debug_last_sweep_force = Vector2.ZERO
		_debug_last_total_force = Vector2.ZERO
		return

	var speed := linear_velocity.length()
	_debug_last_speed = speed
	_debug_last_curl_force = Vector2.ZERO
	_debug_last_sweep_force = Vector2.ZERO
	_debug_last_total_force = Vector2.ZERO
	_debug_last_deceleration = 0.0
	if speed <= 0.0:
		_emit_stop_if_needed()
		return

	_apply_spin_curl(delta, speed)
	_apply_sweep_effect(delta, speed)
	_apply_visual_spin(delta, speed)

	var decel := _get_speed_based_deceleration(speed)
	_debug_last_deceleration = decel
	if speed > 0.0:
		var velocity_dir := linear_velocity / speed
		_debug_last_total_force += velocity_dir * -decel
		_record_debug_throw_sample(delta, speed, decel)

	linear_velocity = linear_velocity.move_toward(Vector2.ZERO, decel * delta)
	if linear_velocity.length() < stop_speed_cutoff:
		linear_velocity = Vector2.ZERO
		throw_phase = ThrowPhase.PHASE_SETTLED
		_reset_sweep_state()
		_emit_stop_if_needed()


func _get_speed_based_deceleration(speed: float) -> float:
	if not use_staged_deceleration_profile:
		var fallback_decel := stop_deceleration
		if speed < low_speed_threshold:
			var fallback_t := 1.0 - (speed / maxf(low_speed_threshold, 0.001))
			fallback_decel += extra_low_speed_deceleration * fallback_t
		return maxf(0.0, fallback_decel)

	var early_value := maxf(0.0, decel_stage_early_value)
	var mid_value := maxf(0.0, decel_stage_mid_value)
	var tail_value := maxf(0.0, decel_stage_tail_value)
	var blend_band := maxf(0.001, decel_stage_blend_band)

	var mid_blend := _get_stage_blend_amount(speed, decel_stage_mid_speed, blend_band)
	var tail_blend := _get_stage_blend_amount(speed, decel_stage_tail_speed, blend_band)

	var decel := lerpf(early_value, mid_value, mid_blend)
	decel = lerpf(decel, tail_value, tail_blend)
	return maxf(0.0, decel)


func _get_stage_blend_amount(speed: float, stage_speed: float, blend_band: float) -> float:
	var half_band := blend_band * 0.5
	var blend_start := stage_speed + half_band
	var blend_end := stage_speed - half_band
	if speed >= blend_start:
		return 0.0
	if speed <= blend_end:
		return 1.0

	var t := (blend_start - speed) / maxf(blend_start - blend_end, 0.001)
	return _smoothstep01(clampf(t, 0.0, 1.0))


func _smoothstep01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - (2.0 * t))


func _get_decel_stage_name(speed: float) -> String:
	if not use_staged_deceleration_profile:
		return "flat"

	var half_band := maxf(0.001, decel_stage_blend_band) * 0.5
	if speed > (decel_stage_mid_speed + half_band):
		return "early"
	if speed > (decel_stage_tail_speed + half_band):
		return "mid"
	return "tail"


func _capture_debug_launch_inputs() -> void:
	var profile := _get_active_throw_profile()
	_debug_throw_scaled_min_power = min_power * throw_distance_scale
	_debug_throw_scaled_max_power = max_power * throw_distance_scale
	_debug_throw_power_multiplier = maxf(float(profile.get("power_multiplier", 1.0)), 0.01)
	_debug_throw_power_jitter_multiplier = maxf(float(profile.get("launch_power_jitter_multiplier", 1.0)), 0.01)
	_debug_throw_pending_launch_power = pending_launch_power
	var denom := maxf(_debug_throw_scaled_max_power - _debug_throw_scaled_min_power, 0.001)
	var power_ratio := (pending_launch_power - _debug_throw_scaled_min_power) / denom
	_debug_throw_launch_power_ratio = clampf(power_ratio, 0.0, 1.0)


func _reset_debug_throw_runtime_state() -> void:
	_debug_throw_elapsed = 0.0
	_debug_throw_next_sample_time = 0.0
	_debug_throw_distance_accum = 0.0
	_debug_throw_last_position = global_position
	_debug_throw_integrated_decel = 0.0
	_debug_throw_integrated_forward_sweep = 0.0
	_debug_throw_stage_time_early = 0.0
	_debug_throw_stage_time_mid = 0.0
	_debug_throw_stage_time_tail = 0.0
	_debug_throw_along_track_error = 0.0
	_debug_throw_cross_track_error = 0.0
	_debug_throw_samples.clear()


func _record_debug_throw_sample(delta: float, speed: float, decel: float) -> void:
	if not has_launched or throw_phase != ThrowPhase.PHASE_IN_FLIGHT:
		return

	var frame_distance := global_position.distance_to(_debug_throw_last_position)
	_debug_throw_distance_accum += frame_distance
	_debug_throw_last_position = global_position

	var stage_name := _get_decel_stage_name(speed)
	match stage_name:
		"early":
			_debug_throw_stage_time_early += delta
		"mid":
			_debug_throw_stage_time_mid += delta
		"tail":
			_debug_throw_stage_time_tail += delta

	_debug_throw_integrated_decel += decel * delta

	var forward_sweep := 0.0
	var forward_curl := 0.0
	if speed > 0.0:
		var velocity_dir := linear_velocity / speed
		forward_sweep = _debug_last_sweep_force.dot(velocity_dir)
		forward_curl = _debug_last_curl_force.dot(velocity_dir)
		_debug_throw_integrated_forward_sweep += forward_sweep * delta

	_debug_throw_elapsed += delta
	if _debug_throw_elapsed + 0.0001 < _debug_throw_next_sample_time:
		return

	while _debug_throw_elapsed + 0.0001 >= _debug_throw_next_sample_time and _debug_throw_samples.size() < DEBUG_THROW_MAX_SAMPLES:
		_debug_throw_samples.append({
			"t": _debug_throw_elapsed,
			"speed": speed,
			"decel": decel,
			"distance": _debug_throw_distance_accum,
			"forward_sweep": forward_sweep,
			"forward_curl": forward_curl,
			"stage": stage_name,
		})
		_debug_throw_next_sample_time += DEBUG_THROW_SAMPLE_INTERVAL


func _get_marker_weight_match_strength(power_ratio: float) -> float:
	if not has_target_marker:
		_debug_marker_live_target_distance = 0.0
		_debug_marker_live_simulated_distance = 0.0
		_debug_marker_live_distance_delta = 0.0
		_debug_marker_live_green_window = 0.0
		_debug_marker_live_match_strength = 0.0
		return 0.0

	var target_distance := global_position.distance_to(target_marker_position)
	if target_distance <= 0.0:
		_debug_marker_live_target_distance = 0.0
		_debug_marker_live_simulated_distance = 0.0
		_debug_marker_live_distance_delta = 0.0
		_debug_marker_live_green_window = 0.0
		_debug_marker_live_match_strength = 0.0
		return 0.0

	var simulated_distance := _estimate_stop_distance_for_power_ratio(power_ratio)

	var precision := _get_selected_stone_precision()
	var precision_ratio := clampf(precision / 100.0, 0.0, 1.0)
	var green_window := _get_marker_green_window(target_distance, precision_ratio)
	var distance_delta := absf(simulated_distance - target_distance)
	_debug_marker_live_target_distance = target_distance
	_debug_marker_live_simulated_distance = simulated_distance
	_debug_marker_live_distance_delta = distance_delta
	_debug_marker_live_green_window = green_window
	if distance_delta >= green_window:
		_debug_marker_live_match_strength = 0.0
		return 0.0

	var closeness := clampf(1.0 - (distance_delta / maxf(green_window, 0.001)), 0.0, 1.0)
	_debug_marker_live_match_strength = _smoothstep01(closeness)
	return _debug_marker_live_match_strength


func _get_marker_green_window(target_distance: float, precision_ratio: float) -> float:
	# Keep the baseline marker band forgiving and taper toward tighter windows at high precision.
	# Distance scaling should widen long throws without fully overriding precision tuning.
	var clamped_precision := clampf(precision_ratio, 0.0, 1.0)
	var precision_exp := maxf(0.01, marker_green_window_precision_exponent)
	var precision_t := pow(clamped_precision, precision_exp)
	var low_window := maxf(0.0, marker_green_window_low)
	var high_window := maxf(0.0, marker_green_window_high)
	var stat_window := lerpf(low_window, high_window, precision_t)
	var distance_window := target_distance * maxf(0.0, marker_green_window_distance_ratio)
	var distance_bonus := maxf(0.0, distance_window - low_window)
	return stat_window + distance_bonus


func _estimate_stop_distance_for_power_ratio(power_ratio: float) -> float:
	var scaled_min_power: float = min_power * throw_distance_scale
	var scaled_max_power: float = max_power * throw_distance_scale
	if scaled_max_power <= scaled_min_power:
		return 0.0

	var profile := _get_active_throw_profile()
	var power_multiplier := maxf(float(profile.get("power_multiplier", 1.0)), 0.01)
	var power_jitter_multiplier := maxf(float(profile.get("launch_power_jitter_multiplier", 1.0)), 0.01)
	var launch_power := lerpf(scaled_min_power, scaled_max_power, clampf(power_ratio, 0.0, 1.0))
	var launch_speed := launch_power * power_multiplier * power_jitter_multiplier * launch_speed_multiplier
	return _estimate_stop_distance_for_speed(launch_speed)


func _get_power_ratio_for_launch_speed(desired_speed: float) -> float:
	var scaled_min_power: float = min_power * throw_distance_scale
	var scaled_max_power: float = max_power * throw_distance_scale
	if scaled_max_power <= scaled_min_power:
		return 0.0

	var profile := _get_active_throw_profile()
	var power_multiplier := maxf(float(profile.get("power_multiplier", 1.0)), 0.01)
	var power_jitter_multiplier := maxf(float(profile.get("launch_power_jitter_multiplier", 1.0)), 0.01)
	var desired_launch_power := maxf(desired_speed / maxf(launch_speed_multiplier, 0.01), 0.0)
	var unclamped_power := desired_launch_power / (power_multiplier * power_jitter_multiplier)
	return clampf(inverse_lerp(scaled_min_power, scaled_max_power, unclamped_power), 0.0, 1.0)


func _get_required_speed_for_marker_distance(distance: float) -> float:
	var quantized_distance := snappedf(maxf(distance, 0.0), 2.0)
	if is_equal_approx(quantized_distance, _marker_required_speed_cache_distance):
		return _marker_required_speed_cache_value

	var estimated_speed := _estimate_required_launch_speed(quantized_distance)
	_marker_required_speed_cache_distance = quantized_distance
	_marker_required_speed_cache_value = estimated_speed
	return estimated_speed


func _estimate_required_launch_speed(distance: float) -> float:
	if distance <= 0.0:
		return 0.0

	var max_launch_speed := maxf(max_power * throw_distance_scale * launch_speed_multiplier, 1.0)
	var upper := max_launch_speed
	var upper_distance := _estimate_stop_distance_for_speed(upper)
	var grow_attempts := 0
	while upper_distance < distance and grow_attempts < 8:
		upper *= 1.45
		upper_distance = _estimate_stop_distance_for_speed(upper)
		grow_attempts += 1

	var lower := 0.0
	for _i in range(16):
		var mid := (lower + upper) * 0.5
		var mid_distance := _estimate_stop_distance_for_speed(mid)
		if mid_distance < distance:
			lower = mid
		else:
			upper = mid

	return upper


func _estimate_stop_distance_for_speed(initial_speed: float) -> float:
	var speed := maxf(initial_speed, 0.0)
	if speed <= stop_speed_cutoff:
		return 0.0

	var distance := 0.0
	var step_dt := 1.0 / 90.0
	var max_steps := 2700
	for _step in range(max_steps):
		if speed <= stop_speed_cutoff:
			break

		var decel := maxf(_get_speed_based_deceleration(speed), 0.001)
		var next_speed := maxf(speed - (decel * step_dt), 0.0)
		distance += ((speed + next_speed) * 0.5) * step_dt
		speed = next_speed

	return distance


func _get_selected_stone_precision() -> float:
	if has_meta("selected_stone_data"):
		var selected_data: Variant = get_meta("selected_stone_data")
		if selected_data is Stone:
			return float(selected_data.precision)
		if selected_data is Dictionary:
			return float(selected_data.get("precision", 33))

	if not _throw_profile.is_empty() and _throw_profile.has("precision_stat"):
		return float(_throw_profile.get("precision_stat", 33.0))

	return 33.0


func _apply_spin_curl(delta: float, speed: float) -> void:
	if is_zero_approx(current_spin_degrees):
		return

	var spin_ratio := clampf(abs(current_spin_degrees) / max_spin_input_degrees, 0.0, 1.0)
	if spin_ratio <= 0.0:
		return

	var dir := linear_velocity / speed
	# Perpendicular to forward direction; with the sign below this maps:
	# negative spin -> right curl, positive spin -> left curl.
	var perp := Vector2(-dir.y, dir.x)
	var curl_sign: float = 1.0 if current_spin_degrees < 0.0 else -1.0
	var curl_accel := perp * curl_sign * max_curl_acceleration * spin_ratio
	_debug_last_curl_force = curl_accel
	_debug_last_total_force += curl_accel
	linear_velocity += curl_accel * delta


func _apply_visual_spin(delta: float, speed: float) -> void:
	if stone_sprite == null or is_zero_approx(current_spin_degrees):
		return

	var spin_ratio := clampf(abs(current_spin_degrees) / max_spin_input_degrees, 0.0, 1.0)
	if spin_ratio <= 0.0:
		return

	# More speed keeps more visible spin, tapering as the stone slows.
	var speed_ratio := clampf(speed / low_speed_threshold, 0.25, 1.0)
	var spin_sign: float = 1.0 if current_spin_degrees < 0.0 else -1.0
	var visual_spin_speed := max_visual_spin_speed_degrees * spin_ratio * speed_ratio
	stone_sprite.rotation_degrees += spin_sign * visual_spin_speed * delta


func _show_spin_setter() -> void:
	spin_selection_started.emit(self)
	var spin_setter = SpinSetter.instantiate()
	var ui_parent: Node = get_tree().root
	var current_scene := get_tree().current_scene
	if is_instance_valid(current_scene):
		var canvas_layer := current_scene.get_node_or_null("CanvasLayer")
		if is_instance_valid(canvas_layer):
			ui_parent = canvas_layer
		else:
			ui_parent = current_scene
	ui_parent.add_child(spin_setter)
	spin_setter.spin_selected.connect(_on_spin_selected)
	var profile := _get_active_throw_profile()
	if spin_setter.has_method("set_spin_speed_scale"):
		spin_setter.set_spin_speed_scale(float(profile.get("spin_setter_speed_multiplier", 1.0)))
	if spin_setter.has_method("set_spin_bounds"):
		spin_setter.set_spin_bounds(spin_setter_max_spin_degrees)
	if spin_setter.has_method("set_stop_duration") and throw_config != null:
		spin_setter.set_stop_duration(throw_config.spin_setter_stop_duration)
	spin_setter.setup(stone_color, float(profile.get("spin_setter_speed_multiplier", 1.0)), spin_setter_max_spin_degrees, throw_config.spin_setter_stop_duration if throw_config != null else 0.5)


func _on_spin_selected(spin_degrees: float) -> void:
	spin_selection_completed.emit(self)
	throw_phase = ThrowPhase.PHASE_IN_FLIGHT
	_launch_with_spin(spin_degrees)


func _launch_with_spin(spin_degrees: float) -> void:
	# Apply the spin rotation to the stone
	var profile := _get_active_throw_profile()
	var spin_authority := float(profile.get("spin_authority_multiplier", 1.0))
	current_spin_degrees = clampf(spin_degrees * spin_authority, -max_spin_input_degrees, max_spin_input_degrees)
	rotation_degrees = current_spin_degrees
	has_launched = true
	has_reported_stop = false
	throw_phase = ThrowPhase.PHASE_IN_FLIGHT
	_reset_sweep_state()
	_condition_wear_total = int(profile.get("base_throw_wear", 0))
	_debug_marker_launch_start_position = global_position
	_debug_marker_final_travel_distance = 0.0
	_debug_marker_final_target_delta = 0.0
	_debug_marker_final_prediction_delta = 0.0
	_debug_throw_id += 1
	_capture_debug_launch_inputs()
	_debug_throw_launch_direction = pending_launch_direction.normalized()
	_debug_throw_launch_speed = pending_launch_power * launch_speed_multiplier
	_debug_throw_predicted_decel_only_distance = _estimate_stop_distance_for_speed(_debug_throw_launch_speed)
	_debug_throw_predicted_full_distance = _debug_throw_predicted_decel_only_distance
	_reset_debug_throw_runtime_state()

	if has_target_marker:
		var launch_target_distance := global_position.distance_to(target_marker_position)
		var launch_speed := pending_launch_power * launch_speed_multiplier
		var launch_simulated_distance := _estimate_stop_distance_for_speed(launch_speed)
		var launch_precision_ratio := clampf(_get_selected_stone_precision() / 100.0, 0.0, 1.0)
		_debug_marker_launch_target_distance = launch_target_distance
		_debug_marker_launch_simulated_distance = launch_simulated_distance
		_debug_marker_launch_distance_delta = absf(launch_simulated_distance - launch_target_distance)
		_debug_marker_launch_green_window = _get_marker_green_window(launch_target_distance, launch_precision_ratio)
	else:
		_debug_marker_launch_target_distance = 0.0
		_debug_marker_launch_simulated_distance = 0.0
		_debug_marker_launch_distance_delta = 0.0
		_debug_marker_launch_green_window = 0.0
	
	# Launch the stone with the stored parameters
	linear_velocity = pending_launch_direction * pending_launch_power * launch_speed_multiplier
	freeze = false
	stone_launched.emit(self)


func _handle_sweep_input(event: InputEvent) -> void:
	if not has_launched or freeze:
		return

	var speed := linear_velocity.length()
	if speed < sweep_speed_floor:
		return

	if sweep_use_proximity_model:
		_apply_proximity_sweep_input(event)
		return

	_apply_directional_sweep_input(event)


func _apply_directional_sweep_input(event: InputEvent) -> void:
	var swipe_delta := Vector2.ZERO
	if event is InputEventScreenDrag:
		swipe_delta = event.relative
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		swipe_delta = event.relative

	if swipe_delta == Vector2.ZERO:
		return

	_update_sweep_particles_position_from_event(event)

	var normalized := swipe_delta / 180.0
	var forward_factor := clampf(-normalized.y, 0.0, 1.0)
	var lateral_factor := clampf(normalized.x, -1.0, 1.0)
	if forward_factor <= 0.0 and is_zero_approx(lateral_factor):
		return

	var forward_add := sweep_max_forward_boost * forward_factor
	var lateral_add := sweep_max_lateral_boost * lateral_factor
	var contribution := absf(forward_add) + absf(lateral_add)
	var remaining := maxf(0.0, sweep_total_influence_cap - sweep_total_influence)
	if remaining <= 0.0 or contribution <= 0.0:
		return

	if contribution > remaining:
		var contribution_scale := remaining / contribution
		forward_add *= contribution_scale
		lateral_add *= contribution_scale
		contribution = remaining

	sweep_forward_boost = clampf(sweep_forward_boost + forward_add, -sweep_max_forward_boost, sweep_max_forward_boost)
	sweep_lateral_boost = clampf(sweep_lateral_boost + lateral_add, -sweep_max_lateral_boost, sweep_max_lateral_boost)
	sweep_total_influence += contribution

	if not sweep_was_active:
		sweep_was_active = true
		_set_sweep_particles_active(true)
		sweep_started.emit(self)


func _apply_proximity_sweep_input(event: InputEvent) -> void:
	var drag_strength := _extract_drag_strength(event)
	if drag_strength <= 0.0:
		return

	var world_position := _extract_event_world_position(event)
	if world_position == Vector2.INF:
		return

	_update_sweep_particles_position_from_event(event)

	var speed := linear_velocity.length()
	if speed <= 0.0:
		return

	var to_sweep := world_position - global_position
	var distance := to_sweep.length()
	if distance <= 0.0 or distance > sweep_influence_radius:
		return

	var direction_to_sweep := to_sweep / distance
	var forward_dir := linear_velocity / speed
	var right_dir := Vector2(-forward_dir.y, forward_dir.x)

	var front_alignment := clampf(direction_to_sweep.dot(forward_dir), 0.0, 1.0)
	var side_alignment := absf(direction_to_sweep.dot(right_dir))
	var side_front_gate := clampf(direction_to_sweep.dot(forward_dir) + sweep_side_front_gate_bias, 0.0, 1.0)
	var proximity_factor := clampf(1.0 - (distance / maxf(sweep_influence_radius, 0.001)), 0.0, 1.0)
	var speed_amp := _get_sweep_speed_amplification(speed)
	var sample_strength := proximity_factor * drag_strength * speed_amp

	if sample_strength <= 0.0:
		return

	var forward_add := sweep_max_forward_boost * sample_strength * sweep_front_weight * front_alignment
	var lateral_sign := signf(direction_to_sweep.dot(right_dir))
	var lateral_add := sweep_max_lateral_boost * sample_strength * sweep_side_weight * side_alignment * side_front_gate * lateral_sign
	var combined_force := Vector2(forward_add, lateral_add)
	var max_proximity_force := maxf(0.0, sweep_proximity_max_force)
	if max_proximity_force > 0.0 and combined_force.length() > max_proximity_force:
		combined_force = combined_force.normalized() * max_proximity_force
		forward_add = combined_force.x
		lateral_add = combined_force.y

	_apply_sweep_accumulation(forward_add, lateral_add)


func _get_sweep_speed_amplification(speed: float) -> float:
	var min_amp := maxf(0.0, sweep_low_speed_amp_min)
	var max_amp := maxf(min_amp, sweep_low_speed_amp_max)
	var start_speed := maxf(sweep_low_speed_amp_start_speed, sweep_low_speed_amp_end_speed)
	var end_speed := minf(sweep_low_speed_amp_start_speed, sweep_low_speed_amp_end_speed)

	if is_equal_approx(start_speed, end_speed):
		return max_amp if speed <= end_speed else min_amp

	if speed >= start_speed:
		return min_amp

	if speed <= end_speed:
		return max_amp

	var t := clampf((start_speed - speed) / maxf(start_speed - end_speed, 0.001), 0.0, 1.0)
	return lerpf(min_amp, max_amp, t)


func _extract_drag_strength(event: InputEvent) -> float:
	if event is InputEventScreenDrag:
		return clampf(event.relative.length() / 180.0, 0.0, 1.0)

	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		return clampf(event.relative.length() / 180.0, 0.0, 1.0)

	return 0.0


func _extract_event_world_position(event: InputEvent) -> Vector2:
	var screen_position := Vector2.INF
	if event is InputEventScreenDrag:
		screen_position = event.position
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		screen_position = event.position

	if screen_position == Vector2.INF:
		return Vector2.INF

	var canvas_transform := get_viewport().get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_position


func _apply_sweep_accumulation(forward_add: float, lateral_add: float) -> void:
	var adjusted_forward := forward_add
	var adjusted_lateral := lateral_add
	var contribution := absf(adjusted_forward) + absf(adjusted_lateral)
	var remaining := maxf(0.0, sweep_total_influence_cap - sweep_total_influence)
	if remaining <= 0.0 or contribution <= 0.0:
		return

	if contribution > remaining:
		var contribution_scale := remaining / contribution
		adjusted_forward *= contribution_scale
		adjusted_lateral *= contribution_scale
		contribution = remaining

	sweep_forward_boost = clampf(sweep_forward_boost + adjusted_forward, -sweep_max_forward_boost, sweep_max_forward_boost)
	sweep_lateral_boost = clampf(sweep_lateral_boost + adjusted_lateral, -sweep_max_lateral_boost, sweep_max_lateral_boost)
	sweep_total_influence += contribution

	if not sweep_was_active:
		sweep_was_active = true
		_set_sweep_particles_active(true)
		sweep_started.emit(self)


func _apply_sweep_effect(delta: float, speed: float) -> void:
	if throw_phase != ThrowPhase.PHASE_IN_FLIGHT:
		return

	if speed < sweep_speed_floor:
		_reset_sweep_state()
		return

	sweep_applied_forward_boost = move_toward(sweep_applied_forward_boost, sweep_forward_boost, sweep_force_blend_rate * delta)
	sweep_applied_lateral_boost = move_toward(sweep_applied_lateral_boost, sweep_lateral_boost, sweep_force_blend_rate * delta)

	if not is_zero_approx(sweep_applied_forward_boost) or not is_zero_approx(sweep_applied_lateral_boost):
		var dir := linear_velocity / speed
		var perp := Vector2(-dir.y, dir.x)
		var spin_ratio := clampf(abs(current_spin_degrees) / maxf(max_spin_input_degrees, 0.001), 0.0, 1.0)
		var preserve_min := clampf(sweep_spin_lateral_preserve_min, 0.0, 1.0)
		var blend_factor := clampf(sweep_spin_lateral_blend, 0.0, 1.0)
		var lateral_scale := lerpf(1.0, preserve_min, spin_ratio * blend_factor)
		var sweep_accel := (dir * sweep_applied_forward_boost) + (perp * (sweep_applied_lateral_boost * lateral_scale))
		_debug_last_sweep_force = sweep_accel
		_debug_last_total_force += sweep_accel
		linear_velocity += dir * sweep_applied_forward_boost * delta
		linear_velocity += perp * (sweep_applied_lateral_boost * lateral_scale) * delta

	sweep_forward_boost = move_toward(sweep_forward_boost, 0.0, sweep_decay_rate * delta)
	sweep_lateral_boost = move_toward(sweep_lateral_boost, 0.0, sweep_decay_rate * delta)

	if is_zero_approx(sweep_forward_boost) and is_zero_approx(sweep_lateral_boost) and is_zero_approx(sweep_applied_forward_boost) and is_zero_approx(sweep_applied_lateral_boost) and sweep_was_active:
		sweep_was_active = false
		_set_sweep_particles_active(false)
		sweep_ended.emit(self)


func _reset_sweep_state() -> void:
	_set_sweep_particles_active(false)
	if sweep_was_active:
		sweep_was_active = false
		sweep_ended.emit(self)
	sweep_forward_boost = 0.0
	sweep_lateral_boost = 0.0
	sweep_applied_forward_boost = 0.0
	sweep_applied_lateral_boost = 0.0
	sweep_total_influence = 0.0


func _emit_stop_if_needed() -> void:
	if not has_launched or has_reported_stop:
		return

	if has_target_marker:
		_debug_marker_final_travel_distance = _debug_marker_launch_start_position.distance_to(global_position)
		_debug_marker_final_target_delta = _debug_marker_final_travel_distance - _debug_marker_launch_target_distance
		_debug_marker_final_prediction_delta = _debug_marker_final_travel_distance - _debug_marker_launch_simulated_distance
		if _debug_throw_launch_direction.length_squared() > 0.0:
			var error_vector := target_marker_position - global_position
			var launch_dir := _debug_throw_launch_direction.normalized()
			var launch_perp := Vector2(-launch_dir.y, launch_dir.x)
			_debug_throw_along_track_error = error_vector.dot(launch_dir)
			_debug_throw_cross_track_error = error_vector.dot(launch_perp)
	else:
		_debug_marker_final_travel_distance = 0.0
		_debug_marker_final_target_delta = 0.0
		_debug_marker_final_prediction_delta = 0.0
		_debug_throw_along_track_error = 0.0
		_debug_throw_cross_track_error = 0.0

	if player_control_enabled and has_target_marker:
		print("THROW_DEBUG_REPORT %s" % JSON.stringify({
			"throw_id": _debug_throw_id,
			"launch": {
				"drag_length": _debug_throw_drag_length,
				"launch_power_ratio": _debug_throw_launch_power_ratio,
				"scaled_min_power": _debug_throw_scaled_min_power,
				"scaled_max_power": _debug_throw_scaled_max_power,
				"power_multiplier": _debug_throw_power_multiplier,
				"power_jitter_multiplier": _debug_throw_power_jitter_multiplier,
				"pending_launch_power": _debug_throw_pending_launch_power,
				"launch_speed": _debug_throw_launch_speed,
				"predicted_decel_only_distance": _debug_throw_predicted_decel_only_distance,
				"predicted_full_distance": _debug_throw_predicted_full_distance,
				"target_distance": _debug_marker_launch_target_distance,
				"predicted_distance": _debug_marker_launch_simulated_distance,
				"launch_delta": _debug_marker_launch_distance_delta,
			},
			"runtime": {
				"distance": _debug_throw_distance_accum,
				"integrated_decel": _debug_throw_integrated_decel,
				"integrated_forward_sweep": _debug_throw_integrated_forward_sweep,
				"stage_time_early": _debug_throw_stage_time_early,
				"stage_time_mid": _debug_throw_stage_time_mid,
				"stage_time_tail": _debug_throw_stage_time_tail,
				"samples": _debug_throw_samples,
			},
			"final": {
				"travel_distance": _debug_marker_final_travel_distance,
				"final_target_error": _debug_marker_final_target_delta,
				"final_prediction_error": _debug_marker_final_prediction_delta,
				"along_track_error": _debug_throw_along_track_error,
				"cross_track_error": _debug_throw_cross_track_error,
			},
		}))

	has_reported_stop = true
	stone_stopped.emit(self)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group(WALLS_GROUP):
		touched_side_wall = true

	if not has_launched or freeze:
		return

	if not _should_track_condition_wear():
		return

	if body.is_in_group(WALLS_GROUP) or body.is_in_group(STONES_GROUP):
		_register_collision_wear()


func should_remove_on_reset(red_line_y: float, rink_end_y: float) -> bool:
	if touched_side_wall:
		return true

	if global_position.y < rink_end_y:
		return true

	if global_position.y > red_line_y:
		return true

	return false


func _get_active_throw_profile() -> Dictionary:
	if not _throw_profile.is_empty():
		return _throw_profile

	if throw_config == null:
		_ensure_throw_config()

	if throw_config == null:
		return {}

	_throw_profile = throw_config.call("build_throw_profile", Stone.new("", 33, 33, 33, 33, 1, 0, Stone.MIN_VARIANT, 100, 100, 100), false)
	return _throw_profile


func _should_track_condition_wear() -> bool:
	return player_control_enabled and has_valid_target_marker()


func _register_collision_wear() -> void:
	if throw_config == null:
		return

	var speed := linear_velocity.length()
	if speed < throw_config.hard_collision_speed_threshold:
		return

	_condition_wear_total += randi_range(throw_config.hard_collision_wear_min, throw_config.hard_collision_wear_max)
