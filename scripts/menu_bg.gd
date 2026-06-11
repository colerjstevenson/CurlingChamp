extends Control

@export var background_color: Color = Color(0.26, 0.58, 0.72, 1.0)
@export_range(0.0, 0.8, 0.01) var stone_lighten_amount := 0.14
@export var min_stone_speed := 180.0
@export var max_stone_speed := 260.0
@export var edge_padding := -150.0
@export_range(1, 50, 1) var rock_count := 35
@export var rock_template_path: NodePath = NodePath("Rock1")

@onready var bg_rect: ColorRect = $BG
@onready var rock_template: RigidBody2D = get_node_or_null(rock_template_path) as RigidBody2D
var rocks: Array[RigidBody2D] = []

var _velocities: Dictionary = {}
var _half_sizes: Dictionary = {}


func _ready() -> void:
	randomize()
	_initialize_rocks()
	_prepare_rocks()
	_apply_colors()
	_randomize_rock_positions()
	_randomize_rock_velocities()


func _initialize_rocks() -> void:
	rocks.clear()
	_velocities.clear()
	_half_sizes.clear()

	_collect_rocks()
	if not is_instance_valid(rock_template):
		if rocks.is_empty():
			return
		rock_template = rocks[0]

	for rock in rocks:
		if rock != rock_template:
			rock.queue_free()

	rocks.clear()
	rock_template.name = "Rock1"
	rocks.append(rock_template)

	for i in range(2, rock_count + 1):
		var spawned := rock_template.duplicate() as RigidBody2D
		if spawned == null:
			continue

		spawned.name = "Rock%d" % i
		add_child(spawned)
		rocks.append(spawned)


func _collect_rocks() -> void:
	rocks.clear()
	for child in get_children():
		if child is RigidBody2D and child.name.begins_with("Rock"):
			rocks.append(child as RigidBody2D)


func _process(delta: float) -> void:
	var play_rect := _get_play_rect()
	if play_rect.size.x <= 0.0 or play_rect.size.y <= 0.0:
		return

	for rock in rocks:
		if not is_instance_valid(rock):
			continue

		var velocity: Vector2 = _velocities.get(rock, Vector2.ZERO)
		if velocity == Vector2.ZERO:
			continue

		var half_size: Vector2 = _half_sizes.get(rock, Vector2(24.0, 24.0))
		var min_x := play_rect.position.x + half_size.x
		var max_x := play_rect.end.x - half_size.x
		var min_y := play_rect.position.y + half_size.y
		var max_y := play_rect.end.y - half_size.y

		var next_position := rock.position + velocity * delta

		if next_position.x <= min_x:
			next_position.x = min_x
			velocity.x = absf(velocity.x)
		elif next_position.x >= max_x:
			next_position.x = max_x
			velocity.x = -absf(velocity.x)

		if next_position.y <= min_y:
			next_position.y = min_y
			velocity.y = absf(velocity.y)
		elif next_position.y >= max_y:
			next_position.y = max_y
			velocity.y = -absf(velocity.y)

		rock.position = next_position
		_velocities[rock] = velocity


func set_background_palette(new_color: Color) -> void:
	background_color = new_color
	if is_inside_tree():
		_apply_colors()


func _prepare_rocks() -> void:
	for rock in rocks:
		if not is_instance_valid(rock):
			continue

		rock.freeze = true
		rock.gravity_scale = 0.0
		rock.linear_velocity = Vector2.ZERO
		rock.angular_velocity = 0.0
		_half_sizes[rock] = _get_rock_half_size(rock)


func _apply_colors() -> void:
	if is_instance_valid(bg_rect):
		bg_rect.color = background_color

	var stone_color := background_color.lerp(Color.WHITE, stone_lighten_amount)
	for rock in rocks:
		var sprite := rock.get_node_or_null("Sprite2D") as Sprite2D
		if sprite != null:
			sprite.modulate = stone_color


func _randomize_rock_positions() -> void:
	var play_rect := _get_play_rect()
	if play_rect.size.x <= 0.0 or play_rect.size.y <= 0.0:
		return

	var placed_positions: Array[Vector2] = []
	for rock in rocks:
		if not is_instance_valid(rock):
			continue

		var half_size: Vector2 = _half_sizes.get(rock, Vector2(24.0, 24.0))
		var min_x := play_rect.position.x + half_size.x
		var max_x := play_rect.end.x - half_size.x
		var min_y := play_rect.position.y + half_size.y
		var max_y := play_rect.end.y - half_size.y

		if min_x >= max_x or min_y >= max_y:
			rock.position = play_rect.get_center()
			continue

		var candidate := Vector2.ZERO
		for _attempt in range(12):
			candidate = Vector2(
				randf_range(min_x, max_x),
				randf_range(min_y, max_y)
			)
			if _is_far_enough(candidate, placed_positions, half_size.length() * 1.2):
				break

		rock.position = candidate
		placed_positions.append(candidate)


func _randomize_rock_velocities() -> void:
	for rock in rocks:
		if not is_instance_valid(rock):
			continue

		var direction := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
		var speed := randf_range(min_stone_speed, max_stone_speed)
		_velocities[rock] = direction * speed


func _is_far_enough(point: Vector2, others: Array[Vector2], min_distance: float) -> bool:
	for other in others:
		if point.distance_to(other) < min_distance:
			return false
	return true


func _get_play_rect() -> Rect2:
	if not is_instance_valid(bg_rect):
		return Rect2()
	var rect := bg_rect.get_rect()
	return rect.grow_individual(-edge_padding, -edge_padding, -edge_padding, -edge_padding)


func _get_rock_half_size(rock: RigidBody2D) -> Vector2:
	var sprite := rock.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or sprite.texture == null:
		return Vector2(24.0, 24.0)

	return sprite.texture.get_size() * sprite.scale.abs() * 0.5
