extends RigidBody2D

signal stone_stopped(stone: RigidBody2D)

const BLUE_TOP_TEXTURE := preload("res://assets/curling/stones/stone_blue_top.png")
const RED_TOP_TEXTURE := preload("res://assets/curling/stones/stone_red_top.png")
const YELLOW_TOP_TEXTURE := preload("res://assets/curling/stones/stone_yellow_top.png")
const WALLS_GROUP := "side_walls"

var dragging = false
var drag_start = Vector2()
var pending_launch_direction: Vector2 = Vector2.ZERO
var pending_launch_power: float = 0.0
var current_spin_degrees: float = 0.0
var has_launched := false
var has_reported_stop := false
var can_aim := true
var stone_color := "blue"
var touched_side_wall := false
@onready var stone_sprite: Sprite2D = $Sprite

@export var grab_radius := 64.0
@export var max_power := 1600.0
@export var arrow_max_length := 360.0
@export var launch_speed_multiplier := 1.35
@export var arrow_low_power_color := Color(1.0, 0.95, 0.2, 0.95)
@export var arrow_high_power_color := Color(1.0, 0.15, 0.1, 0.98)
@export var stop_deceleration := 320.0
@export var low_speed_threshold := 180.0
@export var extra_low_speed_deceleration := 220.0
@export var stop_speed_cutoff := 6.0
@export var max_spin_input_degrees := 270.0
@export var max_curl_acceleration := 420.0
@export var max_visual_spin_speed_degrees := 900.0

const SpinSetter = preload("res://scenes/spin_setter.tscn")


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func set_stone_color(color: String) -> void:
	stone_color = color
	match color:
		"red":
			stone_sprite.texture = RED_TOP_TEXTURE
		"yellow":
			stone_sprite.texture = YELLOW_TOP_TEXTURE
		_:
			stone_sprite.texture = BLUE_TOP_TEXTURE


func _input(event):
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed and can_aim and not dragging and get_global_mouse_position().distance_to(global_position) < grab_radius:
			dragging = true
			drag_start = get_global_mouse_position()
			linear_velocity = Vector2.ZERO
			freeze = true
		elif dragging and not event.pressed:
			dragging = false
			can_aim = false
			var drag_vector = drag_start - get_global_mouse_position()
			var launch_vector = drag_vector.limit_length(arrow_max_length)
			var pull_ratio: float = clampf(launch_vector.length() / arrow_max_length, 0.0, 1.0)
			var power: float = max_power * pull_ratio
			var direction = launch_vector.normalized()
			
			# Store launch parameters and show spin setter
			pending_launch_direction = direction
			pending_launch_power = power
			_show_spin_setter()
			queue_redraw()

func _draw():
	if dragging:
		var aim_vector = (drag_start - get_global_mouse_position()).limit_length(arrow_max_length)
		if aim_vector.length() < 8.0:
			return
		var power_ratio: float = clampf(aim_vector.length() / arrow_max_length, 0.0, 1.0)
		var arrow_color: Color = arrow_low_power_color.lerp(arrow_high_power_color, power_ratio)

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
		return

	var speed := linear_velocity.length()
	if speed <= 0.0:
		_emit_stop_if_needed()
		return

	_apply_spin_curl(delta, speed)
	_apply_visual_spin(delta, speed)

	var decel := stop_deceleration
	if speed < low_speed_threshold:
		var t := 1.0 - (speed / low_speed_threshold)
		decel += extra_low_speed_deceleration * t

	linear_velocity = linear_velocity.move_toward(Vector2.ZERO, decel * delta)
	if linear_velocity.length() < stop_speed_cutoff:
		linear_velocity = Vector2.ZERO
		_emit_stop_if_needed()


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
	linear_velocity += perp * curl_sign * max_curl_acceleration * spin_ratio * delta


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
	var spin_setter = SpinSetter.instantiate()
	get_tree().root.add_child(spin_setter)
	spin_setter.spin_selected.connect(_on_spin_selected)
	spin_setter.setup(stone_color)


func _on_spin_selected(spin_degrees: float) -> void:
	# Apply the spin rotation to the stone
	current_spin_degrees = spin_degrees
	rotation_degrees = spin_degrees
	has_launched = true
	has_reported_stop = false
	
	# Launch the stone with the stored parameters
	linear_velocity = pending_launch_direction * pending_launch_power * launch_speed_multiplier
	freeze = false


func _emit_stop_if_needed() -> void:
	if not has_launched or has_reported_stop:
		return
	has_reported_stop = true
	stone_stopped.emit(self)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group(WALLS_GROUP):
		touched_side_wall = true


func should_remove_on_reset(red_line_y: float, rink_end_y: float) -> bool:
	if touched_side_wall:
		return true

	if global_position.y < rink_end_y:
		return true

	if global_position.y > red_line_y:
		return true

	return false
