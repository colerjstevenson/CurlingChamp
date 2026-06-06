extends Node2D

const ROCK_WINDOW_SCENE := preload("res://scenes/controls/RockWindow.tscn")
const STORE_CARD_LAYOUT_SIZE := Vector2(595.0, 920.0)
const BUY_CARD_LAYOUT_SIZE := STORE_CARD_LAYOUT_SIZE * 0.55
const CARD_BASE_SCALE := Vector2(0.5, 0.5)
const BUY_CARD_CONTENT_SCALE := Vector2(0.5, 0.5)

@onready var buy_panel: Control = $Buy
@onready var sell_panel: Control = $Sell
@onready var buy_grid: GridContainer = $Buy/GridContainer
@onready var sell_scroll_container: ScrollContainer = $Sell/ScrollContainer
@onready var sell_list: HBoxContainer = $Sell/ScrollContainer/HBoxContainer
@onready var buy_button: TextureButton = $BuyButton
@onready var sell_button: TextureButton = $SellButton

var _is_drag_scrolling_sell := false


func _ready() -> void:
	_populate_buy_grid()
	_populate_sell_list()
	_initialize_tab_state()


func _buy_pressed() -> void:
	_set_active_tab(true)


func _sell_pressed() -> void:
	_set_active_tab(false)


func _input(event: InputEvent) -> void:
	if not _is_sell_drag_available():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _is_pointer_over_sell_scroll(event.position):
			_is_drag_scrolling_sell = true
		elif not event.pressed:
			_is_drag_scrolling_sell = false

	if event is InputEventMouseMotion and _is_drag_scrolling_sell:
		_scroll_sell_by_delta(event.relative.x)
		get_viewport().set_input_as_handled()

	if event is InputEventScreenTouch:
		if event.pressed and _is_pointer_over_sell_scroll(event.position):
			_is_drag_scrolling_sell = true
		elif not event.pressed:
			_is_drag_scrolling_sell = false

	if event is InputEventScreenDrag and _is_drag_scrolling_sell:
		_scroll_sell_by_delta(event.relative.x)
		get_viewport().set_input_as_handled()


func _set_active_tab(show_buy: bool) -> void:
	if is_instance_valid(buy_panel):
		buy_panel.visible = show_buy
	if is_instance_valid(sell_panel):
		sell_panel.visible = not show_buy
	if show_buy:
		_is_drag_scrolling_sell = false
	if is_instance_valid(buy_button):
		buy_button.disabled = show_buy
	if is_instance_valid(sell_button):
		sell_button.disabled = not show_buy


func _initialize_tab_state() -> void:
	if is_instance_valid(buy_button):
		buy_button.disabled = false
	if is_instance_valid(sell_button):
		sell_button.disabled = false

	if is_instance_valid(buy_panel) and buy_panel.visible:
		_set_active_tab(true)
		return

	_set_active_tab(false)


func _populate_buy_grid() -> void:
	if not is_instance_valid(buy_grid):
		return

	for child in buy_grid.get_children():
		child.queue_free()

	var manager := get_node_or_null("/root/game_manager")
	if manager == null:
		return

	var stones: Array = []
	if manager.has_method("get_store_stones"):
		stones = manager.get_store_stones()
	elif "store_stones" in manager:
		stones = manager.store_stones

	for stone in stones:
		var card := ROCK_WINDOW_SCENE.instantiate()
		if card == null:
			continue

		buy_grid.add_child(card)
		card.custom_minimum_size = BUY_CARD_LAYOUT_SIZE
		card.size = BUY_CARD_LAYOUT_SIZE
		card.scale = CARD_BASE_SCALE

		var buy_panel_node := card.get_node_or_null("Panel") as CanvasItem
		if buy_panel_node != null:
			buy_panel_node.scale = BUY_CARD_CONTENT_SCALE

		if card.has_method("setup_from_stone"):
			card.call_deferred("setup_from_stone", stone)


func _is_sell_drag_available() -> bool:
	return is_instance_valid(sell_panel) and sell_panel.visible and is_instance_valid(sell_scroll_container)


func _is_pointer_over_sell_scroll(pointer_position: Vector2) -> bool:
	var scroll_rect := Rect2(sell_scroll_container.global_position, sell_scroll_container.size)
	return scroll_rect.has_point(pointer_position)


func _scroll_sell_by_delta(delta_x: float) -> void:
	var target := sell_scroll_container.scroll_horizontal - int(delta_x)
	var max_scroll := int(_max_sell_horizontal_scroll())
	target = int(clampf(target, 0.0, float(max_scroll)))

	sell_scroll_container.scroll_horizontal = target


func _max_sell_horizontal_scroll() -> float:
	if not is_instance_valid(sell_scroll_container):
		return 0.0

	var h_scroll_bar := sell_scroll_container.get_h_scroll_bar()
	if is_instance_valid(h_scroll_bar):
		return maxf(0.0, h_scroll_bar.max_value)

	if not is_instance_valid(sell_list):
		return 0.0

	return maxf(0.0, sell_list.get_combined_minimum_size().x - sell_scroll_container.size.x)


func _populate_sell_list() -> void:
	if not is_instance_valid(sell_list):
		return

	for child in sell_list.get_children():
		child.queue_free()

	var manager := get_node_or_null("/root/game_manager")
	if manager == null:
		return

	var stones: Array = []
	if manager.has_method("get_player_stones"):
		stones = manager.get_player_stones()
	elif "player_stones" in manager:
		stones = manager.player_stones

	for stone in stones:
		var card := ROCK_WINDOW_SCENE.instantiate()
		if card == null:
			continue

		sell_list.add_child(card)
		card.custom_minimum_size = STORE_CARD_LAYOUT_SIZE
		card.size = STORE_CARD_LAYOUT_SIZE
		card.scale = CARD_BASE_SCALE

		if card.has_method("setup_from_stone"):
			card.call_deferred("setup_from_stone", stone)
