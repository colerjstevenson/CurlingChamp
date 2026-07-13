extends Node

signal state_changed

const ROCK_NAMES_PATH := "res://lists/rockNames.txt"
const FIRST_NAMES_PATH := "res://lists/first-names.txt"
const LAST_NAMES_PATH := "res://lists/last-names.txt"
const RINK_NAMES_PATH := "res://lists/rink_names.txt"
const NEW_GAME_TEMPLATE_PATH := "res://data/new_game_template.json"
const LIST_PATHS := [
	ROCK_NAMES_PATH,
	FIRST_NAMES_PATH,
	LAST_NAMES_PATH,
	RINK_NAMES_PATH,
]
const STARTING_STONE_COUNT := 4
const STORE_STONE_COUNT := 4
const DEFAULT_SEASON_WEEKS := 21
const DEFAULT_LEAGUE_PLAYER_COUNT := 25
const STONE_VARIANT_MIN := 1
const STONE_VARIANT_MAX := 51
const VALID_STONE_COLORS := ["red", "blue", "yellow"]
const DEFAULT_PLAYER_NAME := "John Smith"
const DEFAULT_PLAYER_COLOR := "yellow"
const DEFAULT_OPPONENT_COLOR := "red"
const DEFAULT_WEEK := 1
const DEFAULT_YEAR := 1
const DEFAULT_MONEY := 100

var player_name: String = DEFAULT_PLAYER_NAME
var player_color: String = DEFAULT_PLAYER_COLOR
var opponent_color: String = DEFAULT_OPPONENT_COLOR

var week: int = DEFAULT_WEEK
var year: int = DEFAULT_YEAR
var money: int = DEFAULT_MONEY
var player_stones: Array[Stone] = []
var store_stones: Array[Stone] = []
var Schedule: Array[Dictionary] = []
var LeaguePlayers: Array[Dictionary] = []
var HumanSeasonRecord: Dictionary = {
	"wins": 0,
	"losses": 0,
}
var HumanAllTimeRecord: Dictionary = {
	"wins": 0,
	"losses": 0,
}
var HumanMajorsWon: Array[Dictionary] = []
## The week number in which the player last used the trainer (-1 = never trained).
var trainer_week_used: int = -1
var current_save_slot: int = 0
var _suspend_autosave: bool = false


func _ready() -> void:
	randomize()
	_seed_user_lists_from_res()

	if not state_changed.is_connected(_on_state_changed_autosave):
		state_changed.connect(_on_state_changed_autosave)


func load_game_from_slot(slot_index: int) -> bool:
	if slot_index < 1 or slot_index > SaveFile.MAX_SAVE_SLOTS:
		return false

	var loaded_state := SaveFile.load_game_state(slot_index)
	if loaded_state.is_empty():
		return false

	current_save_slot = slot_index
	_suspend_autosave = true
	_apply_loaded_state(loaded_state)
	_ensure_starting_stones()
	_ensure_store_stones()
	_ensure_league_players()
	_ensure_schedule()
	_prune_broken_player_stones()
	_suspend_autosave = false

	emit_signal("state_changed")
	_save_progress()
	return true


func start_new_game_in_slot(slot_index: int, requested_player_name: String, requested_player_color: String) -> bool:
	if slot_index < 1 or slot_index > SaveFile.MAX_SAVE_SLOTS:
		return false

	current_save_slot = slot_index
	_suspend_autosave = true
	_apply_new_game_defaults(requested_player_name, requested_player_color)
	_ensure_starting_stones()
	_ensure_store_stones()
	_ensure_league_players()
	_ensure_schedule()
	_prune_broken_player_stones()
	_suspend_autosave = false

	emit_signal("state_changed")
	_save_progress()
	return true


func get_current_save_slot() -> int:
	return current_save_slot


func _load_progress() -> bool:
	if current_save_slot < 1:
		return false

	var loaded_state := SaveFile.load_game_state()
	if loaded_state.is_empty():
		return false

	_apply_loaded_state(loaded_state)
	return true


func _save_progress() -> bool:
	if current_save_slot < 1:
		return false
	return SaveFile.save_game_state(_export_save_state(), current_save_slot)


func _on_state_changed_autosave() -> void:
	if _suspend_autosave:
		return
	_save_progress()


func _export_save_state() -> Dictionary:
	return {
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"player_name": player_name,
		"player_color": player_color,
		"opponent_color": opponent_color,
		"week": week,
		"year": year,
		"money": money,
		"player_stones": player_stones,
		"store_stones": store_stones,
		"schedule": Schedule,
		"league_players": LeaguePlayers,
		"human_season_record": HumanSeasonRecord,
		"human_all_time_record": HumanAllTimeRecord,
		"human_majors_won": HumanMajorsWon,
		"trainer_week_used": trainer_week_used,
	}


func _apply_new_game_defaults(requested_player_name: String, requested_player_color: String) -> void:
	var template := _load_new_game_template()
	var template_player_name := String(template.get("player_name", DEFAULT_PLAYER_NAME)).strip_edges()
	if template_player_name == "":
		template_player_name = DEFAULT_PLAYER_NAME

	var trimmed_name := requested_player_name.strip_edges()
	if trimmed_name == "":
		trimmed_name = template_player_name

	var template_player_color := _normalize_stone_color(
		String(template.get("player_color", DEFAULT_PLAYER_COLOR)),
		DEFAULT_PLAYER_COLOR
	)
	var template_opponent_color := _normalize_stone_color(
		String(template.get("opponent_color", DEFAULT_OPPONENT_COLOR)),
		DEFAULT_OPPONENT_COLOR
	)
	var template_week: int = max(int(template.get("week", DEFAULT_WEEK)), 1)
	var template_year: int = max(int(template.get("year", DEFAULT_YEAR)), 1)
	var template_money := int(template.get("money", DEFAULT_MONEY))

	player_name = trimmed_name
	player_color = _normalize_stone_color(requested_player_color, template_player_color)
	opponent_color = template_opponent_color
	week = template_week
	year = template_year
	money = template_money

	player_stones = _deserialize_stones_from_template(template.get("player_stones", []))
	store_stones = _deserialize_stones_from_template(template.get("store_stones", []))

	var template_schedule: Variant = template.get("schedule", [])
	Schedule = _to_dictionary_array(template_schedule)

	var template_league_players: Variant = template.get("league_players", [])
	LeaguePlayers = _to_dictionary_array(template_league_players)

	var default_record := {
		"wins": 0,
		"losses": 0,
	}
	HumanSeasonRecord = _record_with_defaults(template.get("human_season_record", default_record), default_record)
	HumanAllTimeRecord = _record_with_defaults(template.get("human_all_time_record", default_record), default_record)

	var template_majors: Variant = template.get("human_majors_won", [])
	HumanMajorsWon = _to_dictionary_array(template_majors)

	trainer_week_used = int(template.get("trainer_week_used", -1))


func _load_new_game_template() -> Dictionary:
	if not FileAccess.file_exists(NEW_GAME_TEMPLATE_PATH):
		return {}

	var file := FileAccess.open(NEW_GAME_TEMPLATE_PATH, FileAccess.READ)
	if file == null:
		push_warning("game_manager: failed to open new game template")
		return {}

	var raw_text := file.get_as_text()
	if raw_text.strip_edges() == "":
		return {}

	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is not Dictionary:
		push_warning("game_manager: new game template must be a JSON object")
		return {}

	return parsed


func _to_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var converted: Array[Dictionary] = []
	if raw_value is not Array:
		return converted

	for entry in raw_value:
		if entry is Dictionary:
			converted.append(entry.duplicate(true))

	return converted


func _deserialize_stones_from_template(raw_stones: Variant) -> Array[Stone]:
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
			int(raw_stone.get("condition", 100)),
			int(raw_stone.get("age", 1)),
			int(raw_stone.get("wins", 0)),
			int(raw_stone.get("variant", STONE_VARIANT_MIN)),
			int(raw_stone.get("power_potential", 100)),
			int(raw_stone.get("spin_potential", 100)),
			int(raw_stone.get("precision_potential", 100))
		))

	return stones


func _apply_loaded_state(loaded_state: Dictionary) -> void:
	player_name = String(loaded_state.get("player_name", player_name))
	player_color = _normalize_stone_color(String(loaded_state.get("player_color", player_color)), player_color)
	opponent_color = _normalize_stone_color(String(loaded_state.get("opponent_color", opponent_color)), opponent_color)
	week = max(int(loaded_state.get("week", week)), 1)
	year = max(int(loaded_state.get("year", year)), 1)
	money = int(loaded_state.get("money", money))

	var loaded_player_stones: Variant = loaded_state.get("player_stones", player_stones)
	if loaded_player_stones is Array:
		player_stones = loaded_player_stones

	var loaded_store_stones: Variant = loaded_state.get("store_stones", store_stones)
	if loaded_store_stones is Array:
		store_stones = loaded_store_stones

	var loaded_schedule: Variant = loaded_state.get("schedule", Schedule)
	if loaded_schedule is Array:
		Schedule = loaded_schedule

	var loaded_league_players: Variant = loaded_state.get("league_players", LeaguePlayers)
	if loaded_league_players is Array:
		LeaguePlayers = loaded_league_players

	HumanSeasonRecord = _record_with_defaults(loaded_state.get("human_season_record", HumanSeasonRecord), HumanSeasonRecord)
	HumanAllTimeRecord = _record_with_defaults(loaded_state.get("human_all_time_record", HumanAllTimeRecord), HumanAllTimeRecord)

	var loaded_majors: Variant = loaded_state.get("human_majors_won", HumanMajorsWon)
	if loaded_majors is Array:
		HumanMajorsWon = loaded_majors

	trainer_week_used = int(loaded_state.get("trainer_week_used", -1))


func _record_with_defaults(raw_record: Variant, fallback: Dictionary) -> Dictionary:
	if raw_record is not Dictionary:
		return fallback.duplicate(true)

	var record: Dictionary = raw_record.duplicate(true)
	record["wins"] = int(record.get("wins", fallback.get("wins", 0)))
	record["losses"] = int(record.get("losses", fallback.get("losses", 0)))
	return record


func set_week(new_week: int) -> void:
	week = max(new_week, 1)
	emit_signal("state_changed")


## Returns true if the player has not yet trained this calendar week.
func is_training_available() -> bool:
	return trainer_week_used != week


## Mark the trainer as used for the current week. Called from training_game.gd.
func set_trainer_week_used() -> void:
	trainer_week_used = week
	emit_signal("state_changed")


func set_year(new_year: int) -> void:
	year = max(new_year, 1)
	emit_signal("state_changed")


func set_money(new_money: int) -> void:
	money = new_money
	emit_signal("state_changed")


func set_player_color(new_color: String) -> void:
	player_color = _normalize_stone_color(new_color, player_color)
	emit_signal("state_changed")


func set_opponent_color(new_color: String) -> void:
	opponent_color = _normalize_stone_color(new_color, opponent_color)
	emit_signal("state_changed")


func set_date(new_year: int, new_week: int) -> void:
	year = max(new_year, 1)
	week = max(new_week, 1)
	emit_signal("state_changed")


func add_money(amount: int) -> void:
	money += amount
	emit_signal("state_changed")


func get_date_text() -> String:
	return "Year %d Week %d" % [year, week]


func get_money_text() -> String:
	return "$%d" % money


func get_player_stones() -> Array[Stone]:
	return player_stones


func get_store_stones() -> Array[Stone]:
	return store_stones


func get_schedule() -> Array[Dictionary]:
	return Schedule


func get_league_players() -> Array[Dictionary]:
	return LeaguePlayers


func get_human_season_record() -> Dictionary:
	return HumanSeasonRecord.duplicate(true)


func get_human_all_time_record() -> Dictionary:
	return HumanAllTimeRecord.duplicate(true)


func get_human_majors_won() -> Array[Dictionary]:
	return HumanMajorsWon.duplicate(true)


func record_human_match_result(did_win: bool, is_major: bool = false, major_event_name: String = "") -> void:
	if did_win:
		HumanSeasonRecord["wins"] = int(HumanSeasonRecord.get("wins", 0)) + 1
		HumanAllTimeRecord["wins"] = int(HumanAllTimeRecord.get("wins", 0)) + 1
	else:
		HumanSeasonRecord["losses"] = int(HumanSeasonRecord.get("losses", 0)) + 1
		HumanAllTimeRecord["losses"] = int(HumanAllTimeRecord.get("losses", 0)) + 1

	if did_win and is_major and major_event_name != "":
		HumanMajorsWon.append({
			"event_name": major_event_name,
			"year": year,
			"week": week,
		})

	emit_signal("state_changed")


func reset_human_season_record() -> void:
	HumanSeasonRecord["wins"] = 0
	HumanSeasonRecord["losses"] = 0
	emit_signal("state_changed")


func set_schedule_week_match(week_number: int, opponent: String, venue: String, result: String = "", rink_name: String = "") -> void:
	var entry := _get_schedule_entry(week_number)
	if entry.is_empty():
		return

	entry["is_major"] = false
	entry["opponent"] = opponent
	entry["venue"] = venue
	entry["result"] = result
	entry["event_name"] = ""
	entry["rounds"] = 0
	if rink_name != "":
		entry["rink_name"] = rink_name
	Schedule[week_number - 1] = entry
	emit_signal("state_changed")


func set_schedule_week_major(week_number: int, event_name: String, venue: String, rounds: int, result: String = "", rink_name: String = "") -> void:
	var entry := _get_schedule_entry(week_number)
	if entry.is_empty():
		return

	entry["is_major"] = true
	entry["opponent"] = ""
	entry["venue"] = venue
	entry["result"] = result
	entry["event_name"] = event_name
	entry["rounds"] = max(rounds, 1)
	if rink_name != "":
		entry["rink_name"] = rink_name
	Schedule[week_number - 1] = entry
	emit_signal("state_changed")


func set_schedule_week_result(week_number: int, result: String) -> void:
	var entry := _get_schedule_entry(week_number)
	if entry.is_empty():
		return

	entry["result"] = result
	Schedule[week_number - 1] = entry
	emit_signal("state_changed")


func set_schedule_week_rink(week_number: int, rink_name: String) -> void:
	var entry := _get_schedule_entry(week_number)
	if entry.is_empty():
		return

	entry["rink_name"] = rink_name
	Schedule[week_number - 1] = entry
	emit_signal("state_changed")


func reroll_store_stones() -> void:
	_refresh_store_stones()
	emit_signal("state_changed")


## Returns the skill (1–10) of the opponent scheduled for the given week.
## Falls back to 5 if the opponent is not found in the league player list.
func get_opponent_skill_for_week(week_number: int) -> int:
	var entry := _get_schedule_entry(week_number)
	if entry.is_empty():
		return 5
	var opponent_name := String(entry.get("opponent", ""))
	if opponent_name == "":
		return 5
	for player in LeaguePlayers:
		if String(player.get("name", "")) == opponent_name:
			return int(player.get("skill", 5))
	return 5


## Returns the name of the opponent scheduled for the given week.
## Returns an empty string if the week is a major or has no opponent.
func get_opponent_name_for_week(week_number: int) -> String:
	var entry := _get_schedule_entry(week_number)
	if entry.is_empty():
		return ""
	if bool(entry.get("is_major", false)):
		return ""
	return String(entry.get("opponent", ""))


## Simulates all league player games for the given week.
## Players are randomly paired; each pair's winner is determined by
## a skill-weighted probability. The human player is excluded since
## their result is recorded separately via complete_week_after_match().
func simulate_other_league_games_for_week(_week_number: int = -1) -> void:
	if LeaguePlayers.is_empty():
		return

	# Collect indices of all non-human league players.
	var sim_indices: Array[int] = []
	for i in range(LeaguePlayers.size()):
		sim_indices.append(i)
	sim_indices.shuffle()

	# Pair them up and simulate.
	var idx := 0
	while idx + 1 < sim_indices.size():
		var a_idx: int = sim_indices[idx]
		var b_idx: int = sim_indices[idx + 1]

		var a_skill: float = float(int(LeaguePlayers[a_idx].get("skill", 5)))
		var b_skill: float = float(int(LeaguePlayers[b_idx].get("skill", 5)))
		var a_win_prob: float = a_skill / (a_skill + b_skill)
		var a_wins: bool = randf() < a_win_prob

		var a_record: Dictionary = LeaguePlayers[a_idx].get("record", {"wins": 0, "losses": 0}).duplicate()
		var b_record: Dictionary = LeaguePlayers[b_idx].get("record", {"wins": 0, "losses": 0}).duplicate()

		if a_wins:
			a_record["wins"] = int(a_record.get("wins", 0)) + 1
			b_record["losses"] = int(b_record.get("losses", 0)) + 1
		else:
			b_record["wins"] = int(b_record.get("wins", 0)) + 1
			a_record["losses"] = int(a_record.get("losses", 0)) + 1

		var a_player: Dictionary = LeaguePlayers[a_idx].duplicate()
		var b_player: Dictionary = LeaguePlayers[b_idx].duplicate()
		a_player["record"] = a_record
		b_player["record"] = b_record
		LeaguePlayers[a_idx] = a_player
		LeaguePlayers[b_idx] = b_player

		idx += 2

	emit_signal("state_changed")


## Records the human match result, applies any stone wear, sets the schedule result text,
## simulates other league games, and advances to the next week. Call this after a match ends.
func complete_week_after_match(did_win: bool, wear_reports: Dictionary = {}) -> void:
	var current_entry := _get_schedule_entry(week)
	var is_major := bool(current_entry.get("is_major", false))
	var major_name := String(current_entry.get("event_name", ""))
	var opponent_name := String(current_entry.get("opponent", ""))

	# Update human record.
	if did_win:
		HumanSeasonRecord["wins"] = int(HumanSeasonRecord.get("wins", 0)) + 1
		HumanAllTimeRecord["wins"] = int(HumanAllTimeRecord.get("wins", 0)) + 1
		if is_major and major_name != "":
			HumanMajorsWon.append({
				"event_name": major_name,
				"year": year,
				"week": week,
			})
	else:
		HumanSeasonRecord["losses"] = int(HumanSeasonRecord.get("losses", 0)) + 1
		HumanAllTimeRecord["losses"] = int(HumanAllTimeRecord.get("losses", 0)) + 1

	# Write result text into the schedule entry.
	var result_text: String
	if is_major:
		result_text = "Win" if did_win else "Loss"
	elif opponent_name != "":
		result_text = ("W - Beat " if did_win else "L - Lost to ") + opponent_name
	else:
		result_text = "Win" if did_win else "Loss"

	if week >= 1 and week <= Schedule.size():
		var entry := Schedule[week - 1].duplicate()
		entry["result"] = result_text
		Schedule[week - 1] = entry

	_apply_post_match_stone_wear(wear_reports)

	# Simulate the rest of the league for this week.
	simulate_other_league_games_for_week()

	# Advance to next week (cap at season length so it doesn't overflow).
	week = mini(week + 1, Schedule.size())

	emit_signal("state_changed")


func _apply_post_match_stone_wear(wear_reports: Dictionary) -> void:
	if wear_reports.is_empty():
		return

	var broken_indices: Array[int] = []
	for key in wear_reports.keys():
		var stone_index := int(key)
		if stone_index <= 0:
			continue

		var roster_index := stone_index - 1
		if roster_index < 0 or roster_index >= player_stones.size():
			continue

		var wear := maxi(int(wear_reports.get(key, 0)), 0)
		if wear <= 0:
			continue

		var stone := player_stones[roster_index]
		if stone == null:
			continue

		stone.set_condition(maxi(stone.condition - wear, 0))
		if stone.condition <= 0:
			broken_indices.append(roster_index)

	broken_indices.sort()
	broken_indices.reverse()
	for broken_index in broken_indices:
		player_stones.remove_at(broken_index)


func _prune_broken_player_stones() -> void:
	var broken_indices: Array[int] = []
	for index in range(player_stones.size() - 1, -1, -1):
		var stone := player_stones[index]
		if stone == null or int(stone.condition) <= 0:
			broken_indices.append(index)

	for broken_index in broken_indices:
		player_stones.remove_at(broken_index)


func _ensure_starting_stones() -> void:
	if not player_stones.is_empty():
		return

	var names := _load_rock_names()
	var used_names: Dictionary = {}

	for i in range(STARTING_STONE_COUNT):
		var stone_name := _pick_random_name(names, used_names, i)
		used_names[stone_name] = true
		var new_stone := _build_random_stone(stone_name)
		player_stones.append(new_stone)

	emit_signal("state_changed")


func _ensure_store_stones() -> void:
	if not store_stones.is_empty():
		return
	_refresh_store_stones()


func _refresh_store_stones() -> void:
	store_stones.clear()

	var names := _load_rock_names()
	var used_names: Dictionary = {}

	for i in range(STORE_STONE_COUNT):
		var stone_name := _pick_random_name(names, used_names, i)
		used_names[stone_name] = true
		store_stones.append(_build_random_stone(stone_name))


func _ensure_schedule() -> void:
	if not Schedule.is_empty():
		return

	for i in range(DEFAULT_SEASON_WEEKS):
		Schedule.append(_build_default_schedule_week(i + 1))

	_assign_schedule_opponents_from_league()
	_assign_schedule_rinks_from_list()

	emit_signal("state_changed")


func _build_default_schedule_week(week_number: int) -> Dictionary:
	return {
		"week": week_number,
		"is_major": false,
		"opponent": "",
		"venue": "",
		"rink_name": "",
		"result": "",
		"event_name": "",
		"rounds": 0,
	}


func _ensure_league_players() -> void:
	if not LeaguePlayers.is_empty():
		return

	var first_names := _load_name_list(FIRST_NAMES_PATH)
	var last_names := _load_name_list(LAST_NAMES_PATH)
	var used_names: Dictionary = {}

	for i in range(DEFAULT_LEAGUE_PLAYER_COUNT):
		var full_name := _build_unique_full_name(first_names, last_names, used_names, i)
		used_names[full_name] = true
		LeaguePlayers.append({
			"name": full_name,
			"record": {
				"wins": 0,
				"losses": 0,
			},
			"skill": randi_range(1, 10),
		})

	emit_signal("state_changed")


func _assign_schedule_opponents_from_league() -> void:
	if Schedule.is_empty() or LeaguePlayers.is_empty():
		return

	var opponent_names: Array[String] = []
	for player in LeaguePlayers:
		opponent_names.append(String(player.get("name", "")))

	if opponent_names.is_empty():
		return

	opponent_names.shuffle()
	var opponent_index := 0

	for i in range(Schedule.size()):
		var entry: Dictionary = Schedule[i].duplicate()
		if bool(entry.get("is_major", false)):
			continue

		entry["opponent"] = opponent_names[opponent_index]
		Schedule[i] = entry
		opponent_index = (opponent_index + 1) % opponent_names.size()


func _assign_schedule_rinks_from_list() -> void:
	if Schedule.is_empty():
		return

	var rink_names := _load_name_list(RINK_NAMES_PATH)
	if rink_names.is_empty():
		return

	rink_names.shuffle()
	var rink_index := 0

	for i in range(Schedule.size()):
		var entry: Dictionary = Schedule[i].duplicate()
		var rink_name := rink_names[rink_index]
		entry["rink_name"] = rink_name

		# Keep venue populated for any legacy UI paths that still read this field.
		if String(entry.get("venue", "")) == "":
			entry["venue"] = rink_name

		Schedule[i] = entry
		rink_index = (rink_index + 1) % rink_names.size()


func _build_unique_full_name(first_names: Array[String], last_names: Array[String], used_names: Dictionary, index: int) -> String:
	var first_name := _pick_random_name(first_names, {}, index)
	var last_name := _pick_random_name(last_names, {}, index)
	var full_name := "%s %s" % [first_name, last_name]

	if not used_names.has(full_name):
		return full_name

	for i in range(10):
		first_name = _pick_random_name(first_names, {}, index + i)
		last_name = _pick_random_name(last_names, {}, index + i)
		full_name = "%s %s" % [first_name, last_name]
		if not used_names.has(full_name):
			return full_name

	return "%s %d" % [full_name, index + 1]


func _get_schedule_entry(week_number: int) -> Dictionary:
	if week_number < 1 or week_number > Schedule.size():
		return {}
	return Schedule[week_number - 1].duplicate()


func _build_random_stone(stone_name: String) -> Stone:
	var power_potential := _roll_potential()
	var spin_potential := _roll_potential()
	var precision_potential := _roll_potential()

	return Stone.new(
		stone_name,
		randi_range(0, power_potential),
		randi_range(0, spin_potential),
		randi_range(0, precision_potential),
		_roll_stat(),
		randi_range(1, 10),
		0,
		randi_range(STONE_VARIANT_MIN, STONE_VARIANT_MAX),
		power_potential,
		spin_potential,
		precision_potential
	)


func _load_rock_names() -> Array[String]:
	return _load_name_list(ROCK_NAMES_PATH)


func _load_name_list(path: String) -> Array[String]:
	var user_path := _to_user_list_path(path)
	var names := _read_name_list_from_file(user_path)
	if not names.is_empty():
		return names

	names = _read_name_list_from_file(path)
	if not names.is_empty():
		return names

	push_warning("game_manager: list file could not be loaded from %s or %s" % [user_path, path])
	return []


func _seed_user_lists_from_res() -> void:
	DirAccess.make_dir_recursive_absolute("user://lists")

	for res_path in LIST_PATHS:
		var user_path := _to_user_list_path(res_path)
		if FileAccess.file_exists(user_path):
			continue
		if not FileAccess.file_exists(res_path):
			continue

		var source := FileAccess.open(res_path, FileAccess.READ)
		if source == null:
			continue

		var target := FileAccess.open(user_path, FileAccess.WRITE)
		if target == null:
			continue

		target.store_string(source.get_as_text())


func _to_user_list_path(res_path: String) -> String:
	var file_name := res_path.get_file()
	return "user://lists/%s" % file_name


func _read_name_list_from_file(path: String) -> Array[String]:
	if not FileAccess.file_exists(path):
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []

	var names: Array[String] = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line != "":
			names.append(line)

	return names


func _pick_random_name(names: Array[String], used_names: Dictionary, index: int) -> String:
	if names.is_empty():
		return "Stone %d" % [index + 1]

	var available_names: Array[String] = []
	for candidate in names:
		if not used_names.has(candidate):
			available_names.append(candidate)

	if available_names.is_empty():
		return names[randi() % names.size()]

	return available_names[randi() % available_names.size()]


func _roll_stat() -> int:
	return randi_range(0, 100)


func _roll_potential() -> int:
	return randi_range(1, 100)


func _normalize_stone_color(requested_color: String, fallback_color: String) -> String:
	if VALID_STONE_COLORS.has(requested_color):
		return requested_color
	if VALID_STONE_COLORS.has(fallback_color):
		return fallback_color
	return VALID_STONE_COLORS[0]
