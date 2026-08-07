extends Node2D
class_name BreederMenu

## State layer names - these should match the scene hierarchy
const SELECTOR_LAYER := "BreedingSelector"
const IN_PROGRESS_LAYER := "BreedingIP"
const FAILED_LAYER := "BreedingFailed"
const SUCCESS_LAYER := "BreedingSuccess"
const STONE_PICKER_LAYER := "selector"

## Breeding constants
const BREEDING_DURATION_WEEKS := 3
const BASE_SUCCESS_RATE := 0.75
const ROCK_WINDOW_SCENE := preload("res://scenes/controls/RockWindow.tscn")
const ROCK_WINDOW_LAYOUT_SIZE := Vector2(595.0, 920.0)
const ROCK_WINDOW_SCALE := Vector2(0.22, 0.22)
const STONE_PICKER_TAP_MAX_DRAG := 18.0
const MAIN_MENU_SCENE_PATH := "res://scenes/Main.tscn"

## Node references
var selector_layer: Control
var in_progress_layer: Control
var failed_layer: Control
var success_layer: Control
var back_button: TextureButton

var stone_picker_layer: Control
var stone_picker_scroll: ScrollContainer
var stone_picker_hbox: HBoxContainer
var stone_picker_close_button: TextureButton

var selector_male_button: TextureButton
var selector_female_button: TextureButton
var selector_breed_button: TextureButton
var selector_male_text: RichTextLabel
var selector_female_text: RichTextLabel
var selector_preview: TextureRect

var in_progress_panel: TextureRect
var in_progress_text: RichTextLabel

var failed_close_button: TextureButton

var success_preview: TextureRect
var success_stats: VBoxContainer

var success_offspring_name_edit: TextEdit
var success_keep_button: TextureButton
var success_sell_button: TextureButton
var success_keep_empty_slots_label: RichTextLabel
var success_sell_value_label: RichTextLabel

## Breeding state (local cache)
var selected_male_id: int = -1
var selected_female_id: int = -1
var _current_stone_picker_type: String = ""  # "male" or "female"
var _stone_picker_rocks: Array = []  # Store instantiated rock windows
var _is_drag_scrolling_picker := false
var _picker_drag_distance := 0.0
var _active_touch_index := -1


func _ready() -> void:
	_setup_node_references()
	_connect_signals()
	_update_layer_visibility()


func _input(event: InputEvent) -> void:
	if not _is_stone_picker_drag_available():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _is_pointer_over_stone_picker(event.position):
			_is_drag_scrolling_picker = true
			_picker_drag_distance = 0.0
		elif not event.pressed:
			_is_drag_scrolling_picker = false

	if event is InputEventMouseMotion and _is_drag_scrolling_picker:
		_picker_drag_distance += absf(event.relative.x) + absf(event.relative.y)
		_scroll_stone_picker_by_delta(event.relative.x)
		get_viewport().set_input_as_handled()

	if event is InputEventScreenTouch:
		if event.pressed and _is_pointer_over_stone_picker(event.position):
			_is_drag_scrolling_picker = true
			_picker_drag_distance = 0.0
			_active_touch_index = event.index
		elif not event.pressed and event.index == _active_touch_index:
			_is_drag_scrolling_picker = false
			_active_touch_index = -1

	if event is InputEventScreenDrag and event.index == _active_touch_index and _is_drag_scrolling_picker:
		_picker_drag_distance += absf(event.relative.x) + absf(event.relative.y)
		_scroll_stone_picker_by_delta(event.relative.x)
		get_viewport().set_input_as_handled()


func _setup_node_references() -> void:
	selector_layer = get_node_or_null(SELECTOR_LAYER)
	in_progress_layer = get_node_or_null(IN_PROGRESS_LAYER)
	failed_layer = get_node_or_null(FAILED_LAYER)
	success_layer = get_node_or_null(SUCCESS_LAYER)
	back_button = get_node_or_null("Back")
	stone_picker_layer = get_node_or_null(STONE_PICKER_LAYER)
	
	if selector_layer:
		selector_male_button = selector_layer.get_node_or_null("maleSelector")
		selector_female_button = selector_layer.get_node_or_null("femaleSelector")
		selector_breed_button = selector_layer.get_node_or_null("BreedButton")
		selector_male_text = selector_layer.get_node_or_null("maleSelector/maleText")
		selector_female_text = selector_layer.get_node_or_null("femaleSelector/femaleText")
		selector_preview = selector_layer.get_node_or_null("Preview")
	
	if stone_picker_layer:
		stone_picker_scroll = stone_picker_layer.get_node_or_null("ScrollContainer")
		stone_picker_hbox = stone_picker_layer.get_node_or_null("ScrollContainer/HBoxContainer")
		stone_picker_close_button = stone_picker_layer.get_node_or_null("close")
	
	if failed_layer:
		failed_close_button = failed_layer.get_node_or_null("Panal/close")
	
	if success_layer:
		success_preview = success_layer.get_node_or_null("Preview")
		success_stats = success_preview.get_node_or_null("Stats") if success_preview else null
		success_offspring_name_edit = success_layer.get_node_or_null("TextEdit")
		success_keep_button = success_layer.get_node_or_null("KeepButton")
		success_sell_button = success_layer.get_node_or_null("SellButton")
		if success_keep_button:
			success_keep_empty_slots_label = success_keep_button.get_node_or_null("EmptySlots")
		if success_sell_button:
			success_sell_value_label = success_sell_button.get_node_or_null("Value")


func _connect_signals() -> void:
	if selector_male_button:
		if not selector_male_button.pressed.is_connected(_on_male_selector_pressed):
			selector_male_button.pressed.connect(_on_male_selector_pressed)

	if back_button:
		if not back_button.pressed.is_connected(_on_back_pressed):
			back_button.pressed.connect(_on_back_pressed)
	
	if selector_female_button:
		if not selector_female_button.pressed.is_connected(_on_female_selector_pressed):
			selector_female_button.pressed.connect(_on_female_selector_pressed)
	
	if selector_breed_button:
		if not selector_breed_button.pressed.is_connected(_on_breed_button_pressed):
			selector_breed_button.pressed.connect(_on_breed_button_pressed)
	
	if failed_close_button:
		if not failed_close_button.pressed.is_connected(_on_failed_close_pressed):
			failed_close_button.pressed.connect(_on_failed_close_pressed)
	
	if stone_picker_close_button:
		if not stone_picker_close_button.pressed.is_connected(_on_stone_picker_close_pressed):
			stone_picker_close_button.pressed.connect(_on_stone_picker_close_pressed)
	
	if success_keep_button:
		if not success_keep_button.pressed.is_connected(_on_keep_offspring_pressed):
			success_keep_button.pressed.connect(_on_keep_offspring_pressed)
	
	if success_sell_button:
		if not success_sell_button.pressed.is_connected(_on_sell_offspring_pressed):
			success_sell_button.pressed.connect(_on_sell_offspring_pressed)
	
	# Monitor week changes
	if game_manager and not game_manager.state_changed.is_connected(_on_game_state_changed):
		game_manager.state_changed.connect(_on_game_state_changed)


func _update_layer_visibility() -> void:
	var _is_breeder_active := game_manager.breeder_active
	var is_result_ready := game_manager.breeder_result != null
	
	# Hide stone picker by default
	if stone_picker_layer:
		stone_picker_layer.visible = false
	
	# Determine which layer to show
	if is_result_ready:
		# Success layer
		_show_layer(SUCCESS_LAYER)
		_update_success_display()
	elif game_manager.breeder_active:
		# In-progress layer
		_show_layer(IN_PROGRESS_LAYER)
		_update_in_progress_display()
	else:
		# Selector layer (default)
		_show_layer(SELECTOR_LAYER)
		_update_selector_display()
		selected_male_id = -1
		selected_female_id = -1


func _show_layer(layer_name: String) -> void:
	if selector_layer:
		selector_layer.visible = (layer_name == SELECTOR_LAYER)
	if in_progress_layer:
		in_progress_layer.visible = (layer_name == IN_PROGRESS_LAYER)
	if failed_layer:
		failed_layer.visible = (layer_name == FAILED_LAYER)
	if success_layer:
		success_layer.visible = (layer_name == SUCCESS_LAYER)


func _update_selector_display() -> void:
	if not selector_layer:
		return
	
	# Update male button text
	if selected_male_id >= 0 and selected_male_id < game_manager.player_stones.size():
		var stone = game_manager.player_stones[selected_male_id]
		if selector_male_text:
			selector_male_text.text = "[center]%s[/center]" % stone.name
	else:
		if selector_male_text:
			selector_male_text.text = "[center]Select Rock[/center]"
	
	# Update female button text
	if selected_female_id >= 0 and selected_female_id < game_manager.player_stones.size():
		var stone = game_manager.player_stones[selected_female_id]
		if selector_female_text:
			selector_female_text.text = "[center]%s[/center]" % stone.name
	else:
		if selector_female_text:
			selector_female_text.text = "[center]Select Rock[/center]"
	
	# Enable breed button only if two different stones are selected
	if selector_breed_button:
		var can_breed = (selected_male_id >= 0 and selected_female_id >= 0 and 
						selected_male_id != selected_female_id)
		selector_breed_button.disabled = not can_breed
	
	# Update preview stats
	if selected_male_id >= 0 and selected_female_id >= 0:
		_update_preview_stats()


func _update_preview_stats() -> void:
	if not selector_preview:
		return
	
	if selected_male_id < 0 or selected_female_id < 0:
		return
	
	var male_stone = game_manager.player_stones[selected_male_id]
	var female_stone = game_manager.player_stones[selected_female_id]
	
	# Find the stats containers and update them
	var stats_container = selector_preview.get_node_or_null("Stats")
	if not stats_container:
		return
	
	# Update each stat row (Speed, Spin, Precision)
	for i in range(min(3, stats_container.get_child_count())):
		var stat_label = stats_container.get_child(i)
		if stat_label is RichTextLabel:
			var progress_bars = []
			for child in stat_label.get_children():
				if child is ProgressBar:
					progress_bars.append(child)
			
			if progress_bars.size() >= 2:
				match i:
					0:  # Speed/Power
						progress_bars[0].value = male_stone.power
						progress_bars[1].value = female_stone.power
					1:  # Stamina/Spin
						progress_bars[0].value = male_stone.spin
						progress_bars[1].value = female_stone.spin
					2:  # Acceleration/Precision
						progress_bars[0].value = male_stone.precision
						progress_bars[1].value = female_stone.precision


func _update_in_progress_display() -> void:
	if not in_progress_layer:
		return
	
	var weeks_remaining = game_manager.breeder_finish_week - game_manager.week
	if weeks_remaining < 0:
		weeks_remaining = 0
	
	if in_progress_text:
		var text = "Breeding in Progress\n\n"
		text += "Weeks remaining: %d" % weeks_remaining
		in_progress_text.text = text


func _update_success_display() -> void:
	if not success_layer or not game_manager.breeder_result:
		return
	
	var offspring = game_manager.breeder_result
	
	# Clear and focus name field
	if success_offspring_name_edit:
		success_offspring_name_edit.text = ""
		success_offspring_name_edit.grab_focus()
	
	# Update preview stats similar to selector
	if success_stats:
		var stat_rows = []
		for child in success_stats.get_children():
			if child is RichTextLabel:
				stat_rows.append(child)
		
		if stat_rows.size() >= 3:
			if stat_rows[0].get_child_count() >= 1:
				stat_rows[0].get_child(0).value = offspring.power
			if stat_rows[1].get_child_count() >= 1:
				stat_rows[1].get_child(0).value = offspring.spin
			if stat_rows[2].get_child_count() >= 1:
				stat_rows[2].get_child(0).value = offspring.precision
	
	# Update keep button - show available slots
	if success_keep_button:
		var store_slots_available = game_manager.STORE_STONE_COUNT - game_manager.store_stones.size()
		var player_slots_available = game_manager.player_stones.size() < 10  # Cap at 10 stones
		var can_keep = store_slots_available > 0 or player_slots_available
		
		success_keep_button.disabled = not can_keep
		
		if success_keep_empty_slots_label:
			var slot_text = "%d Available stone slots" % store_slots_available
			success_keep_empty_slots_label.text = slot_text
	
	# Update sell button - show offspring value
	if success_sell_button:
		success_sell_button.disabled = false
		
		var offspring_value = offspring.calculate_value(game_manager.week)
		var sell_price = int(offspring_value * 0.8)  # Sell for 80% of value
		
		if success_sell_value_label:
			var value_text = "Starting Bid:\n$%d" % sell_price
			success_sell_value_label.text = value_text


func _on_male_selector_pressed() -> void:
	_current_stone_picker_type = "male"
	_show_stone_picker()


func _on_female_selector_pressed() -> void:
	_current_stone_picker_type = "female"
	_show_stone_picker()


func _show_stone_picker() -> void:
	if not stone_picker_layer:
		return
	
	# Clear previous rock windows
	if stone_picker_hbox:
		for child in stone_picker_hbox.get_children():
			child.queue_free()
		_stone_picker_rocks.clear()
	
	# Populate with player stones
	for i in range(game_manager.player_stones.size()):
		var stone = game_manager.player_stones[i]
		var rock_window = ROCK_WINDOW_SCENE.instantiate()
		if rock_window == null:
			continue
		
		stone_picker_hbox.add_child(rock_window)
		rock_window.custom_minimum_size = ROCK_WINDOW_LAYOUT_SIZE
		rock_window.size = ROCK_WINDOW_LAYOUT_SIZE
		rock_window.scale = ROCK_WINDOW_SCALE
		rock_window.setup_from_stone(stone)
		
		# Connect to selection
		rock_window.gui_input.connect(_on_rock_window_input.bindv([i]))
		
		_stone_picker_rocks.append(rock_window)
		
		# Show selection highlight if this stone is already selected
		if (_current_stone_picker_type == "male" and i == selected_male_id) or \
		   (_current_stone_picker_type == "female" and i == selected_female_id):
			rock_window.set_selected_overlay_visible(true)
	
	# Show the stone picker layer
	stone_picker_layer.visible = true


func _on_rock_window_input(event: InputEvent, stone_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _picker_drag_distance <= STONE_PICKER_TAP_MAX_DRAG:
			_select_stone_from_picker(stone_index)

	if event is InputEventScreenTouch and not event.pressed:
		if _picker_drag_distance <= STONE_PICKER_TAP_MAX_DRAG:
			_select_stone_from_picker(stone_index)


func _on_stone_picker_close_pressed() -> void:
	_close_stone_picker()


func _close_stone_picker() -> void:
	_is_drag_scrolling_picker = false
	_picker_drag_distance = 0.0
	_active_touch_index = -1

	if stone_picker_layer:
		stone_picker_layer.visible = false
	
	_update_selector_display()


func _select_stone_from_picker(stone_index: int) -> void:
	# Select this stone
	if _current_stone_picker_type == "male":
		selected_male_id = stone_index
	elif _current_stone_picker_type == "female":
		selected_female_id = stone_index

	# Update highlights
	for i in range(_stone_picker_rocks.size()):
		var rock_window = _stone_picker_rocks[i]
		if rock_window and rock_window.has_method("set_selected_overlay_visible"):
			rock_window.set_selected_overlay_visible(i == stone_index)

	# Close picker and return to selector
	_close_stone_picker()


func _is_stone_picker_drag_available() -> bool:
	return stone_picker_layer != null and stone_picker_layer.visible and stone_picker_scroll != null


func _is_pointer_over_stone_picker(pointer_position: Vector2) -> bool:
	var scroll_rect := Rect2(stone_picker_scroll.global_position, stone_picker_scroll.size)
	return scroll_rect.has_point(pointer_position)


func _scroll_stone_picker_by_delta(delta_x: float) -> void:
	var target := stone_picker_scroll.scroll_horizontal - int(delta_x)
	var max_scroll := int(_max_stone_picker_horizontal_scroll())
	target = int(clampf(target, 0.0, float(max_scroll)))
	stone_picker_scroll.scroll_horizontal = target


func _max_stone_picker_horizontal_scroll() -> float:
	if not stone_picker_scroll:
		return 0.0

	var h_scroll_bar := stone_picker_scroll.get_h_scroll_bar()
	if h_scroll_bar:
		return maxf(0.0, h_scroll_bar.max_value)

	if not stone_picker_hbox:
		return 0.0

	return maxf(0.0, stone_picker_hbox.get_combined_minimum_size().x - stone_picker_scroll.size.x)


func _on_breed_button_pressed() -> void:
	if selected_male_id < 0 or selected_female_id < 0 or selected_male_id == selected_female_id:
		return
	
	# Start the breeding job
	game_manager.breeder_active = true
	game_manager.breeder_parent1_id = selected_male_id
	game_manager.breeder_parent2_id = selected_female_id
	game_manager.breeder_finish_week = game_manager.week + BREEDING_DURATION_WEEKS
	game_manager.breeder_result = null
	
	# Emit state changed to trigger auto-save
	game_manager.state_changed.emit()
	
	# Update UI
	_update_layer_visibility()


func _on_failed_close_pressed() -> void:
	# Reset breeder state back to selector
	game_manager.breeder_active = false
	game_manager.breeder_parent1_id = -1
	game_manager.breeder_parent2_id = -1
	game_manager.breeder_finish_week = -1
	game_manager.breeder_result = null
	game_manager.state_changed.emit()
	
	_update_layer_visibility()


func _on_keep_offspring_pressed() -> void:
	if not game_manager.breeder_result:
		return
	
	var offspring = game_manager.breeder_result
	
	# Get name from text edit
	if success_offspring_name_edit:
		var offspring_name = success_offspring_name_edit.text.strip_edges()
		if offspring_name == "":
			offspring_name = offspring.name  # Use generated name if empty
		offspring.name = offspring_name
	
	# Add to player's stone collection
	game_manager.player_stones.append(offspring)
	
	# Clear breeder state
	game_manager.breeder_active = false
	game_manager.breeder_parent1_id = -1
	game_manager.breeder_parent2_id = -1
	game_manager.breeder_finish_week = -1
	game_manager.breeder_result = null
	
	game_manager.state_changed.emit()
	_update_layer_visibility()


func _on_sell_offspring_pressed() -> void:
	if not game_manager.breeder_result:
		return
	
	var offspring = game_manager.breeder_result
	
	# Calculate sell price
	var offspring_value = offspring.calculate_value(game_manager.week)
	var sell_price = int(offspring_value * 0.8)  # Sell for 80% of value
	
	# Add money to player
	game_manager.money += sell_price
	
	# Clear breeder state (don't add to collection)
	game_manager.breeder_active = false
	game_manager.breeder_parent1_id = -1
	game_manager.breeder_parent2_id = -1
	game_manager.breeder_finish_week = -1
	game_manager.breeder_result = null
	
	game_manager.state_changed.emit()
	_update_layer_visibility()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _on_game_state_changed() -> void:
	# Check if breeding job is complete
	if game_manager.breeder_active and game_manager.week >= game_manager.breeder_finish_week:
		_resolve_breeding_job()
	
	_update_layer_visibility()


func _resolve_breeding_job() -> void:
	if not game_manager.breeder_active:
		return
	
	if game_manager.breeder_parent1_id < 0 or game_manager.breeder_parent2_id < 0:
		return
	
	var parent1 = game_manager.player_stones[game_manager.breeder_parent1_id]
	var parent2 = game_manager.player_stones[game_manager.breeder_parent2_id]
	
	# Calculate success chance
	var success_chance = _calculate_success_chance(parent1, parent2)
	var roll = randf()
	
	if roll < success_chance:
		# Breeding succeeded
		var offspring = _generate_offspring(parent1, parent2)
		game_manager.breeder_result = offspring
		game_manager.breeder_active = false
	else:
		# Breeding failed
		game_manager.breeder_active = false
		# Show failed layer
		_show_layer(FAILED_LAYER)
		game_manager.state_changed.emit()
		return
	
	game_manager.state_changed.emit()


func _calculate_success_chance(parent1: Stone, parent2: Stone) -> float:
	# Base success rate
	var success_rate = BASE_SUCCESS_RATE
	
	# Bonus for good condition
	var avg_condition = (parent1.condition + parent2.condition) / 2.0
	if avg_condition >= 80:
		success_rate += 0.15
	elif avg_condition >= 60:
		success_rate += 0.10
	elif avg_condition < 40:
		success_rate -= 0.20
	
	# Bonus for high potential
	var avg_potential = (
		(parent1.power_potential + parent2.power_potential) / 2.0 +
		(parent1.spin_potential + parent2.spin_potential) / 2.0 +
		(parent1.precision_potential + parent2.precision_potential) / 2.0
	) / 3.0
	
	if avg_potential >= 90:
		success_rate += 0.10
	elif avg_potential >= 75:
		success_rate += 0.05
	
	# Clamp to valid range
	return clampf(success_rate, 0.15, 0.95)


func _generate_offspring(parent1: Stone, parent2: Stone) -> Stone:
	# Generate offspring name
	var offspring_name = _generate_offspring_name()
	
	# Blend parent stats with variance
	var power = _blend_stat(parent1.power, parent2.power, parent1.condition, parent2.condition)
	var spin = _blend_stat(parent1.spin, parent2.spin, parent1.condition, parent2.condition)
	var precision = _blend_stat(parent1.precision, parent2.precision, parent1.condition, parent2.condition)
	
	# Blend potentials (slightly weighted toward average)
	var power_potential = _blend_potential(parent1.power_potential, parent2.power_potential)
	var spin_potential = _blend_potential(parent1.spin_potential, parent2.spin_potential)
	var precision_potential = _blend_potential(parent1.precision_potential, parent2.precision_potential)
	
	# Offspring starts with good condition and age 1
	var condition = 85 + randi() % 16  # 85-100
	var age = 1
	var wins = 0
	var variant = randi_range(Stone.MIN_VARIANT, Stone.MAX_VARIANT)
	
	return Stone.new(
		offspring_name,
		power,
		spin,
		precision,
		condition,
		age,
		wins,
		variant,
		power_potential,
		spin_potential,
		precision_potential,
		Stone.Origin.BRED
	)


func _blend_stat(stat1: int, stat2: int, condition1: int, condition2: int) -> int:
	# Average of parents
	var base = (stat1 + stat2) / 2.0
	
	# Variance based on condition
	var avg_condition = (condition1 + condition2) / 2.0
	var variance_range = 0
	
	if avg_condition >= 80:
		variance_range = randi_range(-3, 8)  # Bias upward for healthy parents
	elif avg_condition >= 60:
		variance_range = randi_range(-5, 5)  # Neutral
	else:
		variance_range = randi_range(-8, 3)  # Bias downward for poor condition
	
	return clampi(int(base) + variance_range, 1, 100)


func _blend_potential(potential1: int, potential2: int) -> int:
	# Average of parents with small variance
	var base = (potential1 + potential2) / 2.0
	var variance = randi_range(-5, 5)
	return clampi(int(base) + variance, 1, 100)


func _generate_offspring_name() -> String:
	# Try to load a random name from the rock names list
	var rock_names = []
	if FileAccess.file_exists("res://lists/rockNames.txt"):
		var file = FileAccess.open("res://lists/rockNames.txt", FileAccess.READ)
		if file:
			var content = file.get_as_text()
			rock_names = content.split("\n", false)
	
	if rock_names.size() > 0:
		return rock_names[randi() % rock_names.size()]
	
	# Fallback name
	return "Offspring_%d" % randi()
