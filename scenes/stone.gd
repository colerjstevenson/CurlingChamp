extends RigidBody2D

var dragging = false
var drag_start = Vector2()

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

func _input(event):
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed and not dragging and get_global_mouse_position().distance_to(global_position) < grab_radius:
			dragging = true
			drag_start = get_global_mouse_position()
			linear_velocity = Vector2.ZERO
			freeze = true
		elif dragging and not event.pressed:
			dragging = false
			var drag_vector = drag_start - get_global_mouse_position()
			var launch_vector = drag_vector.limit_length(arrow_max_length)
			var pull_ratio: float = clampf(launch_vector.length() / arrow_max_length, 0.0, 1.0)
			var power: float = max_power * pull_ratio
			var direction = launch_vector.normalized()
			linear_velocity = direction * power * launch_speed_multiplier
			freeze = false
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
		return

	var decel := stop_deceleration
	if speed < low_speed_threshold:
		var t := 1.0 - (speed / low_speed_threshold)
		decel += extra_low_speed_deceleration * t

	linear_velocity = linear_velocity.move_toward(Vector2.ZERO, decel * delta)
	if linear_velocity.length() < stop_speed_cutoff:
		linear_velocity = Vector2.ZERO
