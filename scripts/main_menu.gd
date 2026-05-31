extends Control

const CURLING_GAME_SCENE := preload("res://scenes/CurlingGame.tscn")
const MENU_STONE_SCENE := preload("res://scenes/MenuStone.tscn")
const COLLECTION_SCENE := preload("res://scenes/menus/collection.tscn")
const MIN_SPAWN_INTERVAL := 2.6
const MAX_SPAWN_INTERVAL := 3.4
const TARGET_STONE_THRESHOLD := 3
const SPAWN_MARGIN := 140.0
const HOUSE_TARGET_RADIUS_FACTOR := 0.55
const OPENING_SPEED_SCALE_MIN := 0.55
const OPENING_SPEED_SCALE_MAX := 0.78
const OPENING_ACCURACY_SCALE_MIN := 0.2
const OPENING_ACCURACY_SCALE_MAX := 0.45
const ATTACK_SPEED_SCALE_MIN := 1.0
const ATTACK_SPEED_SCALE_MAX := 1.28
const ATTACK_ACCURACY_SCALE_MIN := 0.75
const ATTACK_ACCURACY_SCALE_MAX := 1.25

@onready var game_button: BaseButton = $BG/GameButton
@onready var rocks_button: BaseButton = $BG/RocksButton
@onready var background_root: CanvasItem = $BG
@onready var house_node: Area2D = $BG/house
@onready var house_area: CollisionShape2D = $BG/house/houseArea
@onready var money_label: RichTextLabel = $TopBar/money/RichTextLabel
@onready var date_label: RichTextLabel = $TopBar/Date/RichTextLabel

var _spawn_timer: Timer
var _menu_stones: Array[RigidBody2D] = []
var _stone_layer: Node2D


func _ready() -> void:
	randomize()
	if is_instance_valid(game_button):
		game_button.pressed.connect(_on_game_button_pressed)
	if is_instance_valid(rocks_button):
		rocks_button.pressed.connect(_on_rocks_button_pressed)

	var manager := get_node_or_null("/root/game_manager")
	if manager != null and manager.has_signal("state_changed"):
		manager.state_changed.connect(_refresh_header_text)
	_refresh_header_text()

	_setup_stone_layer()
	_setup_spawn_timer()
	_schedule_next_spawn()


func _on_game_button_pressed() -> void:
	get_tree().change_scene_to_packed(CURLING_GAME_SCENE)


func _on_rocks_button_pressed() -> void:
	get_tree().change_scene_to_packed(COLLECTION_SCENE)


func _refresh_header_text() -> void:
	var manager := get_node_or_null("/root/game_manager")
	if manager == null:
		return

	if is_instance_valid(money_label) and manager.has_method("get_money_text"):
		money_label.text = manager.get_money_text()

	if is_instance_valid(date_label) and manager.has_method("get_date_text"):
		date_label.text = manager.get_date_text()


func _setup_stone_layer() -> void:
	_stone_layer = Node2D.new()
	_stone_layer.name = "StoneLayer"
	background_root.add_child(_stone_layer)
	background_root.move_child(_stone_layer, 0)


func _setup_spawn_timer() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = true
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)


func _schedule_next_spawn() -> void:
	if not is_instance_valid(_spawn_timer):
		return
	_spawn_timer.start(randf_range(MIN_SPAWN_INTERVAL, MAX_SPAWN_INTERVAL))


func _on_spawn_timer_timeout() -> void:
	_spawn_menu_stone()
	_schedule_next_spawn()


func _spawn_menu_stone() -> void:
	if not is_instance_valid(_stone_layer):
		return

	var stone := MENU_STONE_SCENE.instantiate() as RigidBody2D
	if stone == null:
		return

	stone.global_position = _get_random_offscreen_spawn_position()
	_stone_layer.add_child(stone)
	_menu_stones.append(stone)
	stone.tree_exited.connect(_on_menu_stone_tree_exited.bind(stone))

	var is_opening_shot := _get_active_stones().size() <= TARGET_STONE_THRESHOLD
	var target := _get_next_target_position(stone)
	if stone.has_method("launch_toward"):
		if is_opening_shot:
			stone.launch_toward(
				target,
				randf_range(OPENING_SPEED_SCALE_MIN, OPENING_SPEED_SCALE_MAX),
				randf_range(OPENING_ACCURACY_SCALE_MIN, OPENING_ACCURACY_SCALE_MAX)
			)
		else:
			stone.launch_toward(
				target,
				randf_range(ATTACK_SPEED_SCALE_MIN, ATTACK_SPEED_SCALE_MAX),
				randf_range(ATTACK_ACCURACY_SCALE_MIN, ATTACK_ACCURACY_SCALE_MAX)
			)


func _get_random_offscreen_spawn_position() -> Vector2:
	var rect := get_viewport().get_visible_rect()
	var side := randi() % 4

	match side:
		0:
			return Vector2(randf_range(rect.position.x, rect.end.x), rect.position.y - SPAWN_MARGIN)
		1:
			return Vector2(rect.end.x + SPAWN_MARGIN, randf_range(rect.position.y, rect.end.y))
		2:
			return Vector2(randf_range(rect.position.x, rect.end.x), rect.end.y + SPAWN_MARGIN)
		_:
			return Vector2(rect.position.x - SPAWN_MARGIN, randf_range(rect.position.y, rect.end.y))


func _get_next_target_position(new_stone: RigidBody2D) -> Vector2:
	var active_stones := _get_active_stones()
	if active_stones.size() <= TARGET_STONE_THRESHOLD:
		return _get_house_target_position()

	active_stones.erase(new_stone)
	if active_stones.is_empty():
		return _get_house_target_position()

	var target_stone := active_stones[randi() % active_stones.size()]
	return target_stone.global_position


func _get_house_target_position() -> Vector2:
	if not is_instance_valid(house_node):
		return get_viewport().get_visible_rect().get_center()

	var center := house_node.global_position
	var target_radius := 120.0

	if is_instance_valid(house_area) and house_area.shape is CircleShape2D:
		var shape := house_area.shape as CircleShape2D
		target_radius = shape.radius * HOUSE_TARGET_RADIUS_FACTOR

	var angle := randf_range(0.0, TAU)
	var distance := sqrt(randf()) * target_radius
	return center + Vector2.RIGHT.rotated(angle) * distance


func _get_active_stones() -> Array[RigidBody2D]:
	var stones: Array[RigidBody2D] = []
	for stone in _menu_stones:
		if is_instance_valid(stone):
			stones.append(stone)
	_menu_stones = stones
	return stones


func _on_menu_stone_tree_exited(stone: RigidBody2D) -> void:
	_menu_stones.erase(stone)
