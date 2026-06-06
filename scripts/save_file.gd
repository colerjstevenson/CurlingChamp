extends RefCounted
class_name SaveFile

const SAVE_DIRECTORY := "user://saves"
const SAVE_PATH := "user://saves/player_data.json"
const SAVE_VERSION := 1


static func load_game_state() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
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


static func save_game_state(state: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIRECTORY)

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("save_file: failed to open save file for writing")
		return false

	file.store_string(JSON.stringify(_serialize_state(state)))
	file.flush()
	return true


static func _serialize_state(state: Dictionary) -> Dictionary:
	return {
		"version": SAVE_VERSION,
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
	}


static func _deserialize_state(state: Dictionary) -> Dictionary:
	return {
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
	}


static func _serialize_stones(raw_stones: Variant) -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	if raw_stones is not Array:
		return serialized

	for raw_stone in raw_stones:
		if raw_stone is not Stone:
			continue
		var stone: Stone = raw_stone
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


static func _deserialize_stones(raw_stones: Variant) -> Array[Stone]:
	var stones: Array[Stone] = []
	if raw_stones is not Array:
		return stones

	for raw_stone in raw_stones:
		if raw_stone is not Dictionary:
			continue
		stones.append(Stone.new(
			String(raw_stone.get("name", "")),
			int(raw_stone.get("power", 0)),
			int(raw_stone.get("spin", 0)),
			int(raw_stone.get("precision", 0)),
			int(raw_stone.get("condition", 0)),
			int(raw_stone.get("age", 1)),
			int(raw_stone.get("wins", 0)),
			int(raw_stone.get("variant", Stone.MIN_VARIANT)),
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