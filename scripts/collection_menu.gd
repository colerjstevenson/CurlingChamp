extends Control

const ROCK_WINDOW_SCENE := preload("res://scenes/controls/RockWindow.tscn")
const CARD_LAYOUT_SIZE := Vector2(595.0, 920.0)
const CARD_SCALE := Vector2(0.22, 0.22)

@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var rock_list: HBoxContainer = $ScrollContainer/HBoxContainer

var _is_drag_scrolling := false
var _last_drag_position := Vector2.ZERO


func _ready() -> void:
	_hide_horizontal_scroll_bar()
	_populate_stone_collection()
	# Wait one frame so ScrollContainer computes final content extents.
	call_deferred("_hide_horizontal_scroll_bar")


func _input(event: InputEvent) -> void:
	if not is_instance_valid(scroll_container):
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _is_pointer_over_scroll(event.position):
			_is_drag_scrolling = true
			_last_drag_position = event.position
		elif not event.pressed:
			_is_drag_scrolling = false

	if event is InputEventMouseMotion and _is_drag_scrolling:
		_scroll_by_delta(event.relative.x)
		_last_drag_position = event.position
		accept_event()

	if event is InputEventScreenTouch:
		if event.pressed and _is_pointer_over_scroll(event.position):
			_is_drag_scrolling = true
			_last_drag_position = event.position
		elif not event.pressed:
			_is_drag_scrolling = false

	if event is InputEventScreenDrag and _is_drag_scrolling:
		_scroll_by_delta(event.relative.x)
		_last_drag_position = event.position
		accept_event()


func _populate_stone_collection() -> void:
	if not is_instance_valid(rock_list):
		return

	for child in rock_list.get_children():
		child.queue_free()

	var manager := get_node_or_null("/root/game_manager")
	if manager == null or not manager.has_method("get_player_stones"):
		return

	var stones: Array = manager.get_player_stones()
	for stone in stones:
		var card := ROCK_WINDOW_SCENE.instantiate()
		if card == null:
			continue

		rock_list.add_child(card)
		card.custom_minimum_size = CARD_LAYOUT_SIZE
		card.size = CARD_LAYOUT_SIZE
		card.scale = CARD_SCALE
		

		if card.has_method("setup_from_stone"):
			card.call_deferred("setup_from_stone", stone)


func _hide_horizontal_scroll_bar() -> void:
	if not is_instance_valid(scroll_container):
		return

	var h_scroll_bar := scroll_container.get_h_scroll_bar()
	if is_instance_valid(h_scroll_bar):
		h_scroll_bar.visible = false
		h_scroll_bar.custom_minimum_size.y = 0.0
		h_scroll_bar.size_flags_vertical = Control.SIZE_SHRINK_END


func _is_pointer_over_scroll(pointer_position: Vector2) -> bool:
	var scroll_rect := Rect2(scroll_container.global_position, scroll_container.size)
	return scroll_rect.has_point(pointer_position)


func _scroll_by_delta(delta_x: float) -> void:
	var target := scroll_container.scroll_horizontal - int(delta_x)
	var max_scroll := int(_max_horizontal_scroll())
	target = int(clampf(target, 0.0, float(max_scroll)))

	scroll_container.scroll_horizontal = target


func _max_horizontal_scroll() -> float:
	if not is_instance_valid(scroll_container):
		return 0.0

	var h_scroll_bar := scroll_container.get_h_scroll_bar()
	if is_instance_valid(h_scroll_bar):
		return maxf(0.0, h_scroll_bar.max_value)

	if not is_instance_valid(rock_list):
		return 0.0

	return maxf(0.0, rock_list.get_combined_minimum_size().x - scroll_container.size.x)
