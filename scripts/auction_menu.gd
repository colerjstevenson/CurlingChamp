extends Node2D

const ROCK_WINDOW_SCENE := preload("res://scenes/controls/RockWindow.tscn")
const STORE_CARD_LAYOUT_SIZE := Vector2(595.0, 920.0)
const BUY_CARD_LAYOUT_SIZE := STORE_CARD_LAYOUT_SIZE * 0.52
const CARD_BASE_SCALE := Vector2(0.5, 0.5)
const BUY_CARD_CONTENT_SCALE := Vector2(0.5, 0.5)

@onready var buy_panel: Control = $Buy
@onready var sell_panel: Control = $Sell
@onready var buy_grid: GridContainer = $Buy/GridContainer
@onready var sell_scroll_container: ScrollContainer = $Sell/ScrollContainer
@onready var sell_list: HBoxContainer = $Sell/ScrollContainer/HBoxContainer
@onready var buy_button: TextureButton = $BuyButton
@onready var sell_button: TextureButton = $SellButton
@onready var confirm_layer: CanvasLayer = $Confirm
@onready var confirm_label: RichTextLabel = $Confirm/Panel/Label
@onready var confirm_yes_button: TextureButton = $Confirm/Panel/Yes
@onready var confirm_no_button: TextureButton = $Confirm/Panel/No

var _is_drag_scrolling_sell := false
var _pending_mode: String = ""
var _pending_stone_index: int = -1
var _pending_starting_price: int = 0
var _pending_stone_name: String = ""


func _ready() -> void:
	if is_instance_valid(confirm_yes_button) and not confirm_yes_button.pressed.is_connected(_on_confirm_yes_pressed):
		confirm_yes_button.pressed.connect(_on_confirm_yes_pressed)
	if is_instance_valid(confirm_no_button) and not confirm_no_button.pressed.is_connected(_on_confirm_no_pressed):
		confirm_no_button.pressed.connect(_on_confirm_no_pressed)
	_set_confirm_visible(false)

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

	for stone_index in range(stones.size()):
		var stone: Stone = stones[stone_index]
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

		_configure_card_auction_button(card, stone, true, stone_index)


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

	for stone_index in range(stones.size()):
		var stone: Stone = stones[stone_index]
		var card := ROCK_WINDOW_SCENE.instantiate()
		if card == null:
			continue

		sell_list.add_child(card)
		card.custom_minimum_size = STORE_CARD_LAYOUT_SIZE
		card.size = STORE_CARD_LAYOUT_SIZE
		card.scale = CARD_BASE_SCALE

		if card.has_method("setup_from_stone"):
			card.call_deferred("setup_from_stone", stone)

		_configure_card_auction_button(card, stone, false, stone_index)


func _configure_card_auction_button(card: Node, stone: Stone, is_buy_card: bool, stone_index: int) -> void:
	if card == null:
		return

	var auction_button := card.get_node_or_null("Panel/AuctionButton") as TextureButton
	if not is_instance_valid(auction_button):
		return

	auction_button.visible = true
	var value := _get_stone_auction_value(stone, is_buy_card)
	var value_text := "$%d" % max(value, 0)
	_set_button_value_text(card, value_text)

	var mode := "buy" if is_buy_card else "sell"
	var stone_name := _get_stone_name(stone)
	var bound_handler := _on_card_auction_pressed.bind(mode, stone_index, max(value, 0), stone_name)
	if not auction_button.pressed.is_connected(bound_handler):
		auction_button.pressed.connect(bound_handler)


func _get_stone_auction_value(stone: Stone, is_buy_card: bool) -> int:
	if stone == null:
		return 0

	var manager := get_node_or_null("/root/game_manager")
	var week := 1
	if manager != null and "week" in manager:
		week = int(manager.week)

	if is_buy_card and stone.has_method("calculate_buy_price"):
		return int(stone.calculate_buy_price(week))

	if not is_buy_card and stone.has_method("calculate_sell_price"):
		return int(stone.calculate_sell_price(week))

	if stone.has_method("calculate_value"):
		return int(round(stone.calculate_value(week)))

	return 0


func _set_button_value_text(card: Node, value_text: String) -> void:
	var label := card.get_node_or_null("Panel/AuctionButton/Value") as RichTextLabel
	if is_instance_valid(label):
		label.text = value_text


func _on_card_auction_pressed(mode: String, stone_index: int, starting_price: int, stone_name: String) -> void:
	_pending_mode = mode
	_pending_stone_index = stone_index
	_pending_starting_price = max(starting_price, 0)
	_pending_stone_name = stone_name

	if is_instance_valid(confirm_label):
		confirm_label.text = _build_confirm_text(mode, stone_name)

	_set_confirm_visible(true)


func _on_confirm_yes_pressed() -> void:
	var manager := get_node_or_null("/root/game_manager")
	if manager == null:
		_set_confirm_visible(false)
		_clear_pending_selection()
		return

	if _pending_mode == "":
		_set_confirm_visible(false)
		return

	var payload := {
		"mode": _pending_mode,
		"stone_index": _pending_stone_index,
		"starting_price": _pending_starting_price,
		"created_week": int(manager.week) if "week" in manager else 1,
		"stone_name": _pending_stone_name,
	}

	if manager.has_method("set_pending_auction"):
		manager.set_pending_auction(payload)

	_set_confirm_visible(false)
	_clear_pending_selection()

	var error := get_tree().change_scene_to_file("res://scenes/auction.tscn")
	if error != OK:
		push_warning("auction_menu: failed to open auction scene")


func _on_confirm_no_pressed() -> void:
	_set_confirm_visible(false)
	_clear_pending_selection()


func _set_confirm_visible(show_confirm: bool) -> void:
	if is_instance_valid(confirm_layer):
		confirm_layer.visible = show_confirm


func _clear_pending_selection() -> void:
	_pending_mode = ""
	_pending_stone_index = -1
	_pending_starting_price = 0
	_pending_stone_name = ""


func _build_confirm_text(mode: String, stone_name: String) -> String:
	if mode == "buy":
		return "Are you sure you want to bid on %s?" % stone_name
	return "Are you sure you want to auction off %s?" % stone_name


func _get_stone_name(stone: Stone) -> String:
	if stone == null:
		return "this stone"

	if "name" in stone:
		var value := String(stone.name).strip_edges()
		if value != "":
			return value

	return "this stone"
