extends Control

const CURLING_GAME_SCENE_PATH := "res://scenes/CurlingGame.tscn"
const MENU_STONE_SCENE_PATH := "res://scenes/MenuStone.tscn"
const COLLECTION_SCENE_PATH := "res://scenes/menus/collection.tscn"
const AUCTION_SCENE_PATH := "res://scenes/menus/auctionMenu.tscn"
const CALENDAR_SCENE_PATH := "res://scenes/menus/CalenderMenu.tscn"
const TRAINER_SCENE_PATH := "res://scenes/menus/trainer.tscn"
const BREEDER_SCENE_PATH := "res://scenes/menus/breeder.tscn"
const MIN_SPAWN_INTERVAL := 2.6
const MAX_SPAWN_INTERVAL := 3.4
const TARGET_STONE_THRESHOLD := 3
const MAX_ACTIVE_MENU_STONES := 12
const SPAWN_MARGIN := 240.0
const HOUSE_TARGET_RADIUS_FACTOR := 0.55
const OPENING_SPEED_SCALE_MIN := 0.55
const OPENING_SPEED_SCALE_MAX := 0.78
const OPENING_ACCURACY_SCALE_MIN := 0.15
const OPENING_ACCURACY_SCALE_MAX := 0.35
const ATTACK_SPEED_SCALE_MIN := 1.0
const ATTACK_SPEED_SCALE_MAX := 1.28
const ATTACK_ACCURACY_SCALE_MIN := 0.5
const ATTACK_ACCURACY_SCALE_MAX := 0.9
const AGGRESSIVE_ATTACK_SPEED_SCALE_MIN := 1.22
const AGGRESSIVE_ATTACK_SPEED_SCALE_MAX := 1.6
const AGGRESSIVE_ATTACK_ACCURACY_SCALE_MIN := 0.3
const AGGRESSIVE_ATTACK_ACCURACY_SCALE_MAX := 0.72
const PRESSURE_START_STONES := 3
const PRESSURE_FULL_STONES := 9
const STRATEGIC_NEIGHBOR_RADIUS := 130.0

@onready var game_button: BaseButton = $BG/GameButton
@onready var rocks_button: BaseButton = $BG/RocksButton
@onready var auction_button: BaseButton = $BG/AuctionButton
@onready var calendar_button: BaseButton = $BG/CalenderButton
@onready var training_button: BaseButton = $BG/TrainingButton
@onready var breeder_button: BaseButton = $BG/BreedingButton
@onready var background_root: CanvasItem = $BG
@onready var house_node: Area2D = $BG/house
@onready var house_area: CollisionShape2D = $BG/house/houseArea
@onready var money_label: RichTextLabel = $BG/TopBar/money/RichTextLabel
@onready var date_label: RichTextLabel = $BG/TopBar/Date/RichTextLabel

var _spawn_timer: Timer
var _menu_stones: Array[RigidBody2D] = []
var _stone_layer: Node2D
var _menu_stone_scene: PackedScene


func _ready() -> void:
	randomize()
	if is_instance_valid(game_button):
		game_button.pressed.connect(_on_game_button_pressed)
	if is_instance_valid(rocks_button):
		rocks_button.pressed.connect(_on_rocks_button_pressed)
	if is_instance_valid(auction_button):
		auction_button.pressed.connect(_on_auction_button_pressed)
	if is_instance_valid(calendar_button):
		calendar_button.pressed.connect(_on_calendar_button_pressed)
	if is_instance_valid(training_button):
		training_button.pressed.connect(_on_training_button_pressed)
	if is_instance_valid(breeder_button):
		breeder_button.pressed.connect(_on_breeder_button_pressed)

	var manager := get_node_or_null("/root/game_manager")
	if manager != null and manager.has_signal("state_changed"):
		manager.state_changed.connect(_refresh_header_text)
	_refresh_header_text()

	_setup_stone_layer()
	_setup_spawn_timer()
	_schedule_next_spawn()


func _on_game_button_pressed() -> void:
	get_tree().change_scene_to_file(CURLING_GAME_SCENE_PATH)


func _on_rocks_button_pressed() -> void:
	get_tree().change_scene_to_file(COLLECTION_SCENE_PATH)


func _on_auction_button_pressed() -> void:
	get_tree().change_scene_to_file(AUCTION_SCENE_PATH)


func _on_calendar_button_pressed() -> void:
	get_tree().change_scene_to_file(CALENDAR_SCENE_PATH)


func _on_training_button_pressed() -> void:
	get_tree().change_scene_to_file(TRAINER_SCENE_PATH)


func _on_breeder_button_pressed() -> void:
	get_tree().change_scene_to_file(BREEDER_SCENE_PATH)


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

	var active_count := _get_active_stones().size()
	var occupancy := clampf(float(active_count) / float(MAX_ACTIVE_MENU_STONES), 0.0, 1.0)
	var slowdown := lerpf(1.0, 1.45, occupancy)
	_spawn_timer.start(randf_range(MIN_SPAWN_INTERVAL * slowdown, MAX_SPAWN_INTERVAL * slowdown))


func _on_spawn_timer_timeout() -> void:
	_spawn_menu_stone()
	_schedule_next_spawn()


func _spawn_menu_stone() -> void:
	if not is_instance_valid(_stone_layer):
		return

	if _menu_stone_scene == null:
		_menu_stone_scene = load(MENU_STONE_SCENE_PATH) as PackedScene
		if _menu_stone_scene == null:
			push_warning("main_menu: failed to load MenuStone scene")
			return

	var active_stones := _get_active_stones()
	var active_count := active_stones.size()
	if active_count >= MAX_ACTIVE_MENU_STONES:
		return

	var is_opening_shot := active_count <= TARGET_STONE_THRESHOLD
	var target := _get_house_target_position()
	var spawn_position := _get_random_offscreen_spawn_position()
	if not is_opening_shot and not active_stones.is_empty():
		var shot_setup := _get_strategic_shot_setup(active_stones)
		spawn_position = shot_setup["spawn"]
		target = shot_setup["target"]

	var stone := _menu_stone_scene.instantiate() as RigidBody2D
	if stone == null:
		return

	stone.global_position = spawn_position
	_stone_layer.add_child(stone)
	_menu_stones.append(stone)
	stone.tree_exited.connect(_on_menu_stone_tree_exited.bind(stone))

	if stone.has_method("launch_toward"):
		if is_opening_shot:
			stone.launch_toward(
				target,
				randf_range(OPENING_SPEED_SCALE_MIN, OPENING_SPEED_SCALE_MAX),
				randf_range(OPENING_ACCURACY_SCALE_MIN, OPENING_ACCURACY_SCALE_MAX)
			)
		else:
			var pressure := _get_attack_pressure(active_count)
			var speed_min := lerpf(ATTACK_SPEED_SCALE_MIN, AGGRESSIVE_ATTACK_SPEED_SCALE_MIN, pressure)
			var speed_max := lerpf(ATTACK_SPEED_SCALE_MAX, AGGRESSIVE_ATTACK_SPEED_SCALE_MAX, pressure)
			var accuracy_min := lerpf(ATTACK_ACCURACY_SCALE_MIN, AGGRESSIVE_ATTACK_ACCURACY_SCALE_MIN, pressure)
			var accuracy_max := lerpf(ATTACK_ACCURACY_SCALE_MAX, AGGRESSIVE_ATTACK_ACCURACY_SCALE_MAX, pressure)
			stone.launch_toward(
				target,
				randf_range(speed_min, speed_max),
				randf_range(accuracy_min, accuracy_max)
			)


func _get_attack_pressure(active_count: int) -> float:
	var denom := maxf(1.0, float(PRESSURE_FULL_STONES - PRESSURE_START_STONES))
	return clampf(float(active_count - PRESSURE_START_STONES) / denom, 0.0, 1.0)


func _get_strategic_shot_setup(active_stones: Array[RigidBody2D]) -> Dictionary:
	var target_stone := _get_best_knockout_target(active_stones)
	var target_position := target_stone.global_position
	var cluster_center := _get_cluster_center(active_stones)
	var shot_direction := (target_position - cluster_center).normalized()
	if shot_direction == Vector2.ZERO:
		shot_direction = (target_position - _get_house_center_position()).normalized()
	if shot_direction == Vector2.ZERO:
		shot_direction = Vector2.RIGHT.rotated(randf_range(0.0, TAU))

	return {
		"spawn": _get_offscreen_spawn_aligned(target_position, shot_direction),
		"target": target_position
	}


func _get_best_knockout_target(active_stones: Array[RigidBody2D]) -> RigidBody2D:
	var house_center := _get_house_center_position()
	var best_target := active_stones[0]
	var best_score := -1000000.0

	for candidate in active_stones:
		var neighbor_score := 0.0
		for other in active_stones:
			if other == candidate:
				continue
			var distance := candidate.global_position.distance_to(other.global_position)
			if distance <= STRATEGIC_NEIGHBOR_RADIUS:
				neighbor_score += 1.0 - (distance / STRATEGIC_NEIGHBOR_RADIUS)

		var center_score := 1.0 / maxf(1.0, candidate.global_position.distance_to(house_center))
		var total_score := neighbor_score + center_score * 120.0
		if total_score > best_score:
			best_score = total_score
			best_target = candidate

	return best_target


func _get_cluster_center(active_stones: Array[RigidBody2D]) -> Vector2:
	if active_stones.is_empty():
		return _get_house_center_position()

	var center := Vector2.ZERO
	for stone in active_stones:
		center += stone.global_position
	return center / float(active_stones.size())


func _get_offscreen_spawn_aligned(target_position: Vector2, shot_direction: Vector2) -> Vector2:
	var rect := get_viewport().get_visible_rect()
	var x_min := rect.position.x - SPAWN_MARGIN
	var x_max := rect.end.x + SPAWN_MARGIN
	var y_min := rect.position.y - SPAWN_MARGIN
	var y_max := rect.end.y + SPAWN_MARGIN

	var direction := shot_direction.normalized()
	if direction == Vector2.ZERO:
		return _get_random_offscreen_spawn_position()

	if absf(direction.x) >= absf(direction.y):
		if direction.x > 0.0:
			var left_x := x_min
			var left_t := (target_position.x - left_x) / maxf(0.001, direction.x)
			var left_y := target_position.y - direction.y * left_t
			return Vector2(left_x, clampf(left_y, y_min, y_max))

		var right_x := x_max
		var right_t := (right_x - target_position.x) / maxf(0.001, -direction.x)
		var right_y := target_position.y + direction.y * right_t
		return Vector2(right_x, clampf(right_y, y_min, y_max))

	if direction.y > 0.0:
		var top_y := y_min
		var top_t := (target_position.y - top_y) / maxf(0.001, direction.y)
		var top_x := target_position.x - direction.x * top_t
		return Vector2(clampf(top_x, x_min, x_max), top_y)

	var bottom_y := y_max
	var bottom_t := (bottom_y - target_position.y) / maxf(0.001, -direction.y)
	var bottom_x := target_position.x + direction.x * bottom_t
	return Vector2(clampf(bottom_x, x_min, x_max), bottom_y)


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


func _get_house_center_position() -> Vector2:
	if is_instance_valid(house_node):
		return house_node.global_position
	return get_viewport().get_visible_rect().get_center()


func _get_active_stones() -> Array[RigidBody2D]:
	var stones: Array[RigidBody2D] = []
	for stone in _menu_stones:
		if is_instance_valid(stone):
			stones.append(stone)
	_menu_stones = stones
	return stones


func _on_menu_stone_tree_exited(stone: RigidBody2D) -> void:
	_menu_stones.erase(stone)
