extends RefCounted
class_name SaveFile

const STONE_DATA_SCRIPT := preload("res://scripts/stone_data.gd")

const SAVE_DIRECTORY := "user://saves"
const LEGACY_SAVE_PATH := "user://saves/player_data.json"
const SAVE_SLOT_PATH_TEMPLATE := "user://saves/player_data_slot_%d.json"
const MAX_SAVE_SLOTS := 3
const SAVE_VERSION := 1


static func load_game_state(slot_index: int = 1) -> Dictionary:
	var save_path := _get_slot_save_path(slot_index)
	if save_path == "":
		return {}

	if not FileAccess.file_exists(save_path):
		# Gracefully support old single-save installs by treating it as slot 1.
		if slot_index == 1 and FileAccess.file_exists(LEGACY_SAVE_PATH):
			save_path = LEGACY_SAVE_PATH
		else:
			return {}

	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_warning("save_file: failed to open save file for reading")
		return {}

	var raw_text: String = file.get_as_text()
	if raw_text.strip_edges() == "":
		return {}

	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is not Dictionary:
		push_warning("save_file: save file did not contain a dictionary")
		return {}

	return _deserialize_state(parsed)


static func save_game_state(state: Dictionary, slot_index: int = 1) -> bool:
	var save_path := _get_slot_save_path(slot_index)
	if save_path == "":
		return false

	DirAccess.make_dir_recursive_absolute(SAVE_DIRECTORY)

	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("save_file: failed to open save file for writing")
		return false

	file.store_string(JSON.stringify(_serialize_state(state)))
	file.flush()
	return true


static func slot_exists(slot_index: int) -> bool:
	var save_path := _get_slot_save_path(slot_index)
	if save_path == "":
		return false
	if FileAccess.file_exists(save_path):
		return true
	return slot_index == 1 and FileAccess.file_exists(LEGACY_SAVE_PATH)


static func get_slot_summary(slot_index: int) -> Dictionary:
	var state := load_game_state(slot_index)
	if state.is_empty():
		return {}

	return {
		"player_name": String(state.get("player_name", "John Smith")),
		"player_color": String(state.get("player_color", "yellow")),
		"money": int(state.get("money", 100)),
		"week": int(state.get("week", 1)),
		"year": int(state.get("year", 1)),
		"saved_at_unix": int(state.get("saved_at_unix", 0)),
	}


static func delete_slot(slot_index: int) -> bool:
	var had_files := slot_exists(slot_index)
	if not had_files:
		return true

	var delete_ok := true
	var save_path := _get_slot_save_path(slot_index)
	if save_path != "" and FileAccess.file_exists(save_path):
		var delete_error := DirAccess.remove_absolute(save_path)
		if delete_error != OK:
			push_warning("save_file: failed to delete slot save file %s" % save_path)
			delete_ok = false

	if slot_index == 1 and FileAccess.file_exists(LEGACY_SAVE_PATH):
		var legacy_delete_error := DirAccess.remove_absolute(LEGACY_SAVE_PATH)
		if legacy_delete_error != OK:
			push_warning("save_file: failed to delete legacy slot save file %s" % LEGACY_SAVE_PATH)
			delete_ok = false

	return delete_ok and not slot_exists(slot_index)


static func _get_slot_save_path(slot_index: int) -> String:
	if slot_index < 1 or slot_index > MAX_SAVE_SLOTS:
		push_warning("save_file: invalid save slot %d" % slot_index)
		return ""
	return SAVE_SLOT_PATH_TEMPLATE % slot_index


static func _serialize_state(state: Dictionary) -> Dictionary:
	var saved_at_unix := int(state.get("saved_at_unix", Time.get_unix_time_from_system()))
	if saved_at_unix <= 0:
		saved_at_unix = int(Time.get_unix_time_from_system())

	return {
		"version": SAVE_VERSION,
		"saved_at_unix": saved_at_unix,
		"player_name": String(state.get("player_name", "John Smith")),
		"player_color": String(state.get("player_color", "yellow")),
		"opponent_color": String(state.get("opponent_color", "red")),
		"week": int(state.get("week", 1)),
		"year": int(state.get("year", 1)),
		"money": int(state.get("money", 100)),
		"player_stones": _serialize_stones(state.get("player_stones", [])),
		"store_stones": _serialize_stones(state.get("store_stones", [])),
		"schedule": _duplicate_array_of_dictionaries(state.get("schedule", [])),
		"league_players": _duplicate_array_of_dictionaries(state.get("league_players", [])),
		"human_season_record": Dictionary(state.get("human_season_record", {})).duplicate(true),
		"human_all_time_record": Dictionary(state.get("human_all_time_record", {})).duplicate(true),
		"human_majors_won": _duplicate_array_of_dictionaries(state.get("human_majors_won", [])),
		"trainer_week_used": int(state.get("trainer_week_used", -1)),
	}


static func _deserialize_state(state: Dictionary) -> Dictionary:
	return {
		"saved_at_unix": int(state.get("saved_at_unix", 0)),
		"player_name": String(state.get("player_name", "John Smith")),
		"player_color": String(state.get("player_color", "yellow")),
		"opponent_color": String(state.get("opponent_color", "red")),
		"week": max(int(state.get("week", 1)), 1),
		"year": max(int(state.get("year", 1)), 1),
		"money": int(state.get("money", 100)),
		"player_stones": _deserialize_stones(state.get("player_stones", [])),
		"store_stones": _deserialize_stones(state.get("store_stones", [])),
		"schedule": _duplicate_array_of_dictionaries(state.get("schedule", [])),
		"league_players": _duplicate_array_of_dictionaries(state.get("league_players", [])),
		"human_season_record": Dictionary(state.get("human_season_record", {})).duplicate(true),
		"human_all_time_record": Dictionary(state.get("human_all_time_record", {})).duplicate(true),
		"human_majors_won": _duplicate_array_of_dictionaries(state.get("human_majors_won", [])),
		"trainer_week_used": int(state.get("trainer_week_used", -1)),
	}


static func _serialize_stones(raw_stones: Variant) -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	if raw_stones is not Array:
		return serialized

	for raw_stone in raw_stones:
		if raw_stone == null or raw_stone.get_script() != STONE_DATA_SCRIPT:
			continue
		var stone: Variant = raw_stone
		serialized.append({
			"name": stone.name,
			"power": stone.power,
			"spin": stone.spin,
			"precision": stone.precision,
			"condition": stone.condition,
			"age": stone.age,
			"wins": stone.wins,
			"variant": stone.variant,
			"power_potential": stone.power_potential,
			"spin_potential": stone.spin_potential,
			"precision_potential": stone.precision_potential,
		})

	return serialized


static func _deserialize_stones(raw_stones: Variant) -> Array:
	var stones: Array = []
	if raw_stones is not Array:
		return stones

	for raw_stone in raw_stones:
		if raw_stone is not Dictionary:
			continue
		stones.append(STONE_DATA_SCRIPT.new(
			String(raw_stone.get("name", "")),
			int(raw_stone.get("power", 0)),
			int(raw_stone.get("spin", 0)),
			int(raw_stone.get("precision", 0)),
			int(raw_stone.get("condition", 0)),
			int(raw_stone.get("age", 1)),
			int(raw_stone.get("wins", 0)),
			int(raw_stone.get("variant", STONE_DATA_SCRIPT.MIN_VARIANT)),
			int(raw_stone.get("power_potential", 100)),
			int(raw_stone.get("spin_potential", 100)),
			int(raw_stone.get("precision_potential", 100))
		))

	return stones


static func _duplicate_array_of_dictionaries(raw_value: Variant) -> Array[Dictionary]:
	var duplicated: Array[Dictionary] = []
	if raw_value is not Array:
		return duplicated

	for entry in raw_value:
		if entry is Dictionary:
			duplicated.append(entry.duplicate(true))

	return duplicated