extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main.tscn"
const SAVE_FILE_SCRIPT := preload("res://scripts/save_file.gd")
const RED_STONE_TEXTURE := preload("res://assets/curling/stones/stone_red_side.png")
const BLUE_STONE_TEXTURE := preload("res://assets/curling/stones/stone_blue_side.png")
const YELLOW_STONE_TEXTURE := preload("res://assets/curling/stones/stone_yellow_side.png")
const SLOT_COUNT := 3
const AVAILABLE_COLORS := ["red", "blue", "yellow"]

@onready var main_layer: CanvasLayer = $MainLayer
@onready var new_game_setup: CanvasLayer = $NewGameSetup
@onready var name_input: LineEdit = $NewGameSetup/Panel/TextEdit
@onready var setup_stone_sprite: Sprite2D = $NewGameSetup/Panel/stone
@onready var left_arrow_button: TextureButton = $NewGameSetup/Panel/stone/LeftArrow
@onready var right_arrow_button: TextureButton = $NewGameSetup/Panel/stone/RightArrow
@onready var start_button: TextureButton = $NewGameSetup/Panel/Start
@onready var confirm_layer: CanvasLayer = $Confirm
@onready var confirm_yes_button: TextureButton = $Confirm/Panel/Yes
@onready var confirm_no_button: TextureButton = $Confirm/Panel/No

var _slot_views: Array[Dictionary] = []
var _selected_slot: int = 0
var _selected_color_index: int = 1
var _pending_delete_slot: int = 0


func _ready() -> void:
	if is_instance_valid(main_layer):
		main_layer.visible = true
	if is_instance_valid(new_game_setup):
		new_game_setup.visible = false
	if is_instance_valid(confirm_layer):
		confirm_layer.visible = false

	_cache_slot_views()
	_connect_signals()
	_refresh_slot_buttons()
	_update_setup_stone_preview()


func _cache_slot_views() -> void:
	_slot_views.clear()
	for slot in range(1, SLOT_COUNT + 1):
		var root_path := "MainLayer/Save%d" % slot
		var root := get_node_or_null(root_path) as TextureButton
		if root == null:
			continue

		var info_layer := root.get_node_or_null("InfoLayer") as CanvasLayer
		if info_layer == null:
			info_layer = root.get_node_or_null("CanvasLayer") as CanvasLayer

		_slot_views.append({
			"slot": slot,
			"button": root,
			"delete_button": root.get_node_or_null("delete") as TextureButton,
			"new_game_label": root.get_node_or_null("NewGame") as CanvasItem,
			"save_layer": info_layer,
			"name_label": info_layer.get_node_or_null("Name") as RichTextLabel if info_layer != null else null,
			"money_label": info_layer.get_node_or_null("date") as RichTextLabel if info_layer != null else null,
			"date_label": info_layer.get_node_or_null("Money") as RichTextLabel if info_layer != null else null,
			"stone_sprite": info_layer.get_node_or_null("StoneRedSide") as Sprite2D if info_layer != null else null,
		})


func _connect_signals() -> void:
	for slot_view in _slot_views:
		var button := slot_view.get("button") as TextureButton
		var delete_button := slot_view.get("delete_button") as TextureButton
		var slot_index := int(slot_view.get("slot", 0))
		if button != null:
			button.pressed.connect(_on_slot_button_pressed.bind(slot_index))
		if delete_button != null:
			delete_button.pressed.connect(_on_delete_pressed.bind(slot_index))

	if is_instance_valid(left_arrow_button):
		left_arrow_button.pressed.connect(_on_left_arrow_pressed)
	if is_instance_valid(right_arrow_button):
		right_arrow_button.pressed.connect(_on_right_arrow_pressed)
	if is_instance_valid(start_button):
		start_button.pressed.connect(_on_start_new_game_pressed)
	if is_instance_valid(confirm_yes_button):
		confirm_yes_button.pressed.connect(_on_confirm_delete_yes_pressed)
	if is_instance_valid(confirm_no_button):
		confirm_no_button.pressed.connect(_on_confirm_delete_no_pressed)
	if is_instance_valid(name_input):
		name_input.gui_input.connect(_on_name_input_gui_input)


func _refresh_slot_buttons() -> void:
	for slot_view in _slot_views:
		var slot_index := int(slot_view.get("slot", 0))
		var summary := SAVE_FILE_SCRIPT.get_slot_summary(slot_index)
		var has_save := not summary.is_empty()

		var save_layer := slot_view.get("save_layer") as CanvasLayer
		if save_layer != null:
			save_layer.visible = has_save

		var new_game_label := slot_view.get("new_game_label") as CanvasItem
		if new_game_label != null:
			new_game_label.visible = not has_save

		var delete_button := slot_view.get("delete_button") as CanvasItem
		if delete_button != null:
			delete_button.visible = has_save

		if not has_save:
			continue

		var name_label := slot_view.get("name_label") as RichTextLabel
		if name_label != null:
			name_label.text = String(summary.get("player_name", "John Smith"))

		var money_label := slot_view.get("money_label") as RichTextLabel
		if money_label != null:
			money_label.text = "$%d" % int(summary.get("money", 100))

		var date_label := slot_view.get("date_label") as RichTextLabel
		if date_label != null:
			date_label.text = _format_saved_date(int(summary.get("saved_at_unix", 0)))

		var stone_sprite := slot_view.get("stone_sprite") as Sprite2D
		if stone_sprite != null:
			stone_sprite.texture = _get_stone_texture(String(summary.get("player_color", "yellow")))


func _on_slot_button_pressed(slot_index: int) -> void:
	if SAVE_FILE_SCRIPT.slot_exists(slot_index):
		_load_existing_save(slot_index)
		return

	_show_new_game_setup(slot_index)


func _on_delete_pressed(slot_index: int) -> void:
	if not SAVE_FILE_SCRIPT.slot_exists(slot_index):
		return

	_pending_delete_slot = slot_index
	if is_instance_valid(new_game_setup):
		new_game_setup.visible = false
	if is_instance_valid(confirm_layer):
		confirm_layer.visible = true


func _on_confirm_delete_yes_pressed() -> void:
	if _pending_delete_slot < 1 or _pending_delete_slot > SLOT_COUNT:
		if is_instance_valid(confirm_layer):
			confirm_layer.visible = false
		return

	SAVE_FILE_SCRIPT.delete_slot(_pending_delete_slot)
	_pending_delete_slot = 0
	if is_instance_valid(confirm_layer):
		confirm_layer.visible = false
	_refresh_slot_buttons()


func _on_confirm_delete_no_pressed() -> void:
	_pending_delete_slot = 0
	if is_instance_valid(confirm_layer):
		confirm_layer.visible = false


func _load_existing_save(slot_index: int) -> void:
	var manager := get_node_or_null("/root/game_manager")
	if manager == null or not manager.has_method("load_game_from_slot"):
		push_warning("start_menu: game_manager is missing load_game_from_slot")
		return

	if not manager.load_game_from_slot(slot_index):
		push_warning("start_menu: failed to load save slot %d" % slot_index)
		return

	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _show_new_game_setup(slot_index: int) -> void:
	_selected_slot = slot_index
	if is_instance_valid(new_game_setup):
		new_game_setup.visible = true
	_update_setup_stone_preview()


func _focus_name_input_for_new_game() -> void:
	if not is_instance_valid(name_input):
		return

	name_input.grab_focus()
	_request_virtual_keyboard_for_name_input()


func _request_virtual_keyboard_for_name_input() -> void:
	if not is_instance_valid(name_input):
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return

	var input_rect := name_input.get_global_rect()
	var keyboard_rect := Rect2i(
		int(input_rect.position.x),
		int(input_rect.position.y),
		int(input_rect.size.x),
		int(input_rect.size.y)
	)
	DisplayServer.virtual_keyboard_show(name_input.text, keyboard_rect, DisplayServer.KEYBOARD_TYPE_DEFAULT)


func _on_name_input_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_focus_name_input_for_new_game()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_focus_name_input_for_new_game()


func _on_left_arrow_pressed() -> void:
	_selected_color_index = (_selected_color_index - 1 + AVAILABLE_COLORS.size()) % AVAILABLE_COLORS.size()
	_update_setup_stone_preview()


func _on_right_arrow_pressed() -> void:
	_selected_color_index = (_selected_color_index + 1) % AVAILABLE_COLORS.size()
	_update_setup_stone_preview()


func _on_start_new_game_pressed() -> void:
	if _selected_slot < 1 or _selected_slot > SLOT_COUNT:
		return

	var manager := get_node_or_null("/root/game_manager")
	if manager == null or not manager.has_method("start_new_game_in_slot"):
		push_warning("start_menu: game_manager is missing start_new_game_in_slot")
		return

	var requested_name := _read_player_name_input()
	var requested_color: String = AVAILABLE_COLORS[_selected_color_index]
	if not manager.start_new_game_in_slot(_selected_slot, requested_name, requested_color):
		push_warning("start_menu: failed to create new game in slot %d" % _selected_slot)
		return

	_refresh_slot_buttons()
	if is_instance_valid(new_game_setup):
		new_game_setup.visible = false

	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _read_player_name_input() -> String:
	if not is_instance_valid(name_input):
		return ""

	return name_input.text.strip_edges()


func _update_setup_stone_preview() -> void:
	if not is_instance_valid(setup_stone_sprite):
		return

	var selected_color: String = AVAILABLE_COLORS[_selected_color_index]
	setup_stone_sprite.texture = _get_stone_texture(selected_color)


func _get_stone_texture(stone_color: String) -> Texture2D:
	match stone_color:
		"red":
			return RED_STONE_TEXTURE
		"blue":
			return BLUE_STONE_TEXTURE
		"yellow":
			return YELLOW_STONE_TEXTURE
		_:
			return YELLOW_STONE_TEXTURE


func _format_saved_date(unix_time: int) -> String:
	if unix_time <= 0:
		return "Unknown Date"

	var date := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d" % [
		int(date.get("year", 0)),
		int(date.get("month", 0)),
		int(date.get("day", 0)),
	]
