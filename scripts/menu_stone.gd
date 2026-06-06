extends RigidBody2D

const BLUE_TOP_TEXTURE := preload("res://assets/curling/stones/stone_blue_top.png")
const RED_TOP_TEXTURE := preload("res://assets/curling/stones/stone_red_top.png")
const YELLOW_TOP_TEXTURE := preload("res://assets/curling/stones/stone_yellow_top.png")
const STONE_TEXTURES := [BLUE_TOP_TEXTURE, RED_TOP_TEXTURE, YELLOW_TOP_TEXTURE]

@export var min_launch_speed := 580.0
@export var max_launch_speed := 980.0
@export var min_accuracy_error_degrees := 0.35
@export var max_accuracy_error_degrees := 10.0
@export var travel_deceleration := 170.0
@export var stop_speed_cutoff := 16.0
@export var offscreen_buffer := 10.0
@export var offscreen_remove_delay := 1.6

@onready var stone_sprite: Sprite2D = $Sprite

var _base_accuracy_error_degrees := 0.0
var _was_ever_visible := false
var _offscreen_cleanup_queued := false


func _ready() -> void:
	gravity_scale = 0.0
	_base_accuracy_error_degrees = randf_range(min_accuracy_error_degrees, max_accuracy_error_degrees)
	_set_random_texture()


func launch_toward(target_position: Vector2, speed_scale: float = 1.0, accuracy_scale: float = 1.0) -> void:
	var to_target := target_position - global_position
	if to_target == Vector2.ZERO:
		to_target = Vector2.UP

	var launch_direction := to_target.normalized()
	var scaled_accuracy := _base_accuracy_error_degrees * maxf(0.0, accuracy_scale)
	var launch_error := deg_to_rad(randf_range(-scaled_accuracy, scaled_accuracy))
	launch_direction = launch_direction.rotated(launch_error)

	var launch_speed := randf_range(min_launch_speed, max_launch_speed) * maxf(0.0, speed_scale)
	linear_velocity = launch_direction * launch_speed
	angular_velocity = randf_range(-8.0, 8.0)


func _physics_process(_delta: float) -> void:
	if _offscreen_cleanup_queued:
		return

	linear_velocity = linear_velocity.move_toward(Vector2.ZERO, travel_deceleration * _delta)
	if linear_velocity.length() < stop_speed_cutoff:
		linear_velocity = Vector2.ZERO

	var visible_rect := get_viewport().get_visible_rect()
	if visible_rect.has_point(global_position):
		_was_ever_visible = true
		return

	if _was_ever_visible and not visible_rect.grow($CollisionShape2D.shape.radius + offscreen_buffer).has_point(global_position):
		_queue_offscreen_cleanup()


func _queue_offscreen_cleanup() -> void:
	_offscreen_cleanup_queued = true
	var timer := get_tree().create_timer(offscreen_remove_delay)
	timer.timeout.connect(_on_offscreen_cleanup_timeout)


func _on_offscreen_cleanup_timeout() -> void:
	if is_inside_tree():
		queue_free()


func _set_random_texture() -> void:
	if stone_sprite == null:
		return
	stone_sprite.texture = STONE_TEXTURES[randi() % STONE_TEXTURES.size()]
