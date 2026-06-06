extends Control

enum MenuTab {
	SCHEDULE,
	STANDINGS,
	STATS,
}

const GAME_MANAGER_PATH := "/root/game_manager"
const STANDING_ROW_SCENE := preload("res://scenes/controls/StandingRow.tscn")
const STANDING_ROW_HEIGHT := 68.0
const STANDING_NAME_FONT_MAX := 31
const STANDING_NAME_FONT_MIN := 17

@onready var schedule_layer: CanvasLayer = $Schedule
@onready var standings_layer: CanvasLayer = $Standings
@onready var stats_layer: CanvasLayer = $Stats

@onready var schedule_button: TextureButton = $ScheduleButton
@onready var standings_button: TextureButton = $StandingsButton
@onready var stats_button: TextureButton = $StatsButton

@onready var schedule_week_label: RichTextLabel = $Schedule/Panel/Week
@onready var schedule_labels: RichTextLabel = $Schedule/Panel/Labels
@onready var schedule_opponent_label: RichTextLabel = $Schedule/Panel/Opponent
@onready var schedule_opponent_record_label: RichTextLabel = $Schedule/Panel/Record
@onready var schedule_venue_label: RichTextLabel = $Schedule/Panel/Venue
@onready var schedule_result_label: RichTextLabel = $Schedule/Panel/Result
@onready var schedule_major_panel: ColorRect = $Schedule/Panel/Major
@onready var schedule_major_event_label: RichTextLabel = $Schedule/Panel/Major/Event
@onready var schedule_major_rounds_label: RichTextLabel = $Schedule/Panel/Major/Rounds
@onready var prev_week_button: TextureButton = $Schedule/PrevWeek
@onready var next_week_button: TextureButton = $Schedule/NextWeek

@onready var standings_list: VBoxContainer = $Standings/Panel/ScrollContainer/HBoxContainer

@onready var stats_record_label: RichTextLabel = $Stats/Panel/Record
@onready var stats_majors_list: VBoxContainer = $Stats/Panel/Majors/HBoxContainer

var _schedule_data: Array[Dictionary] = []
var _league_players: Array[Dictionary] = []
var _selected_schedule_week_index: int = 0


func _ready() -> void:
	var manager := _get_game_manager()
	if manager != null and manager.has_signal("state_changed"):
		manager.state_changed.connect(_refresh_from_manager)

	_refresh_from_manager()
	_show_schedule()


func _show_schedule() -> void:
	_set_active_tab(MenuTab.SCHEDULE)


func _show_standings() -> void:
	_set_active_tab(MenuTab.STANDINGS)


func _show_stats() -> void:
	_set_active_tab(MenuTab.STATS)


func _buy_pressed() -> void:
	# Preserve compatibility with existing scene signal hookups.
	_show_schedule()


func _sell_pressed() -> void:
	# Keep compatibility if any old connection still points here.
	_show_standings()


func _on_prev_week_pressed() -> void:
	if _schedule_data.is_empty():
		return

	_selected_schedule_week_index = max(_selected_schedule_week_index - 1, 0)
	_refresh_schedule_view()


func _on_next_week_pressed() -> void:
	if _schedule_data.is_empty():
		return

	_selected_schedule_week_index = min(_selected_schedule_week_index + 1, _schedule_data.size() - 1)
	_refresh_schedule_view()


func _set_active_tab(active_tab: MenuTab) -> void:
	if is_instance_valid(schedule_layer):
		schedule_layer.visible = active_tab == MenuTab.SCHEDULE
	if is_instance_valid(standings_layer):
		standings_layer.visible = active_tab == MenuTab.STANDINGS
	if is_instance_valid(stats_layer):
		stats_layer.visible = active_tab == MenuTab.STATS

	if is_instance_valid(schedule_button):
		schedule_button.disabled = active_tab == MenuTab.SCHEDULE
	if is_instance_valid(standings_button):
		standings_button.disabled = active_tab == MenuTab.STANDINGS
	if is_instance_valid(stats_button):
		stats_button.disabled = active_tab == MenuTab.STATS


func _refresh_from_manager() -> void:
	var manager := _get_game_manager()
	if manager == null:
		return

	if manager.has_method("get_schedule"):
		_schedule_data = manager.get_schedule()
	if manager.has_method("get_league_players"):
		_league_players = manager.get_league_players()

	_selected_schedule_week_index = _get_initial_schedule_week_index(manager)
	_refresh_schedule_view()
	_refresh_standings_view(manager)
	_refresh_stats_view(manager)


func _refresh_schedule_view() -> void:
	if _schedule_data.is_empty():
		if is_instance_valid(schedule_week_label):
			schedule_week_label.text = "Week 0 of 0"
		if is_instance_valid(prev_week_button):
			prev_week_button.disabled = true
		if is_instance_valid(next_week_button):
			next_week_button.disabled = true
		return

	_selected_schedule_week_index = clampi(_selected_schedule_week_index, 0, _schedule_data.size() - 1)
	var entry: Dictionary = _schedule_data[_selected_schedule_week_index]
	var week_number := int(entry.get("week", _selected_schedule_week_index + 1))
	var total_weeks := _schedule_data.size()
	var is_major := bool(entry.get("is_major", false))
	var venue := String(entry.get("venue", ""))
	var rink_name := String(entry.get("rink_name", ""))
	var display_venue := rink_name if rink_name != "" else venue
	var result := String(entry.get("result", ""))

	if is_instance_valid(schedule_week_label):
		schedule_week_label.text = "Week %d of %d" % [week_number, total_weeks]

	if is_instance_valid(schedule_major_panel):
		schedule_major_panel.visible = is_major

	if is_instance_valid(schedule_labels):
		schedule_labels.text = "Venue:" if is_major else "Opponent:\n\n\nVenue:"

	if is_instance_valid(schedule_opponent_label):
		schedule_opponent_label.visible = not is_major
		_fit_name_label(schedule_opponent_label, String(entry.get("opponent", "TBD")), 41, 24, 408.0)

	if is_instance_valid(schedule_opponent_record_label):
		schedule_opponent_record_label.visible = not is_major
		schedule_opponent_record_label.text = _get_opponent_record_text(String(entry.get("opponent", "")))

	if is_instance_valid(schedule_major_event_label):
		schedule_major_event_label.text = String(entry.get("event_name", "Major Event"))

	if is_instance_valid(schedule_major_rounds_label):
		var rounds := int(entry.get("rounds", 0))
		schedule_major_rounds_label.text = "%d Round%s" % [rounds, "" if rounds == 1 else "s"]

	if is_instance_valid(schedule_venue_label):
		schedule_venue_label.text = display_venue if display_venue != "" else "TBD"

	if is_instance_valid(schedule_result_label):
		schedule_result_label.visible = result != ""
		schedule_result_label.text = result

	if is_instance_valid(prev_week_button):
		prev_week_button.disabled = _selected_schedule_week_index <= 0
	if is_instance_valid(next_week_button):
		next_week_button.disabled = _selected_schedule_week_index >= _schedule_data.size() - 1


func _refresh_standings_view(manager: Node) -> void:
	if not is_instance_valid(standings_list):
		return

	_clear_container(standings_list)
	standings_list.add_theme_constant_override("separation", 6)

	var standings_rows: Array[Dictionary] = []
	var seen_names: Dictionary = {}
	var human_name := String(manager.get("player_name"))
	if manager.has_method("get_human_season_record"):
		var human_record: Dictionary = manager.get_human_season_record()
		standings_rows.append({
			"name": human_name,
			"wins": int(human_record.get("wins", 0)),
			"losses": int(human_record.get("losses", 0)),
			"is_human": true,
		})
		seen_names[human_name] = true

	for player in _league_players:
		var player_name := String(player.get("name", "Unknown"))
		if seen_names.has(player_name):
			continue

		var record: Dictionary = player.get("record", {})
		standings_rows.append({
			"name": player_name,
			"wins": int(record.get("wins", 0)),
			"losses": int(record.get("losses", 0)),
			"is_human": false,
		})
		seen_names[player_name] = true

	standings_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("wins", 0)) != int(b.get("wins", 0)):
			return int(a.get("wins", 0)) > int(b.get("wins", 0))
		if int(a.get("losses", 0)) != int(b.get("losses", 0)):
			return int(a.get("losses", 0)) < int(b.get("losses", 0))
		return String(a.get("name", "")) < String(b.get("name", ""))
	)

	for i in range(standings_rows.size()):
		var row: Dictionary = standings_rows[i]
		var row_control := STANDING_ROW_SCENE.instantiate() as Control
		if row_control == null:
			continue

		# Keep each row at a fixed size so the panel remains fixed and the ScrollContainer handles overflow.
		row_control.custom_minimum_size = Vector2(0.0, STANDING_ROW_HEIGHT)
		row_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_control.size_flags_vertical = Control.SIZE_FILL

		var rank_label := row_control.get_node_or_null("Rank") as RichTextLabel
		var name_label := row_control.get_node_or_null("Name") as RichTextLabel
		var record_label := row_control.get_node_or_null("Record") as RichTextLabel

		if is_instance_valid(rank_label):
			rank_label.text = "%d." % [i + 1]
		if is_instance_valid(name_label):
			_fit_standing_name_label(name_label, String(row.get("name", "Unknown")))
		if is_instance_valid(record_label):
			record_label.text = "%d - %d" % [
				int(row.get("wins", 0)),
				int(row.get("losses", 0)),
			]

		if bool(row.get("is_human", false)):
			_apply_human_standing_row_style(rank_label, name_label, record_label)

		standings_list.add_child(row_control)


func _refresh_stats_view(manager: Node) -> void:
	if manager.has_method("get_human_all_time_record") and is_instance_valid(stats_record_label):
		var all_time_record: Dictionary = manager.get_human_all_time_record()
		stats_record_label.text = "%d - %d" % [
			int(all_time_record.get("wins", 0)),
			int(all_time_record.get("losses", 0)),
		]

	if not is_instance_valid(stats_majors_list):
		return

	_clear_container(stats_majors_list)

	if not manager.has_method("get_human_majors_won"):
		return

	var majors_won: Array[Dictionary] = manager.get_human_majors_won()
	if majors_won.is_empty():
		var none_label := RichTextLabel.new()
		none_label.fit_content = true
		none_label.scroll_active = false
		none_label.text = "No majors won yet"
		stats_majors_list.add_child(none_label)
		return

	for major in majors_won:
		var major_label := RichTextLabel.new()
		major_label.fit_content = true
		major_label.scroll_active = false
		major_label.text = "Year %d Week %d - %s" % [
			int(major.get("year", 1)),
			int(major.get("week", 1)),
			String(major.get("event_name", "Major Event")),
		]
		stats_majors_list.add_child(major_label)


func _get_initial_schedule_week_index(manager: Node) -> int:
	if _schedule_data.is_empty():
		return 0

	var current_week := int(manager.get("week"))
	return clampi(current_week - 1, 0, _schedule_data.size() - 1)


func _get_opponent_record_text(opponent_name: String) -> String:
	if opponent_name == "":
		return "0 - 0"

	for player in _league_players:
		if String(player.get("name", "")) != opponent_name:
			continue

		var record: Dictionary = player.get("record", {})
		return "%d - %d" % [int(record.get("wins", 0)), int(record.get("losses", 0))]

	return "0 - 0"


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _apply_human_standing_row_style(rank_label: RichTextLabel, name_label: RichTextLabel, record_label: RichTextLabel) -> void:
	if is_instance_valid(rank_label):
		rank_label.add_theme_color_override("default_color", Color(1.0, 0.88, 0.28, 1.0))
	if is_instance_valid(name_label):
		name_label.add_theme_color_override("default_color", Color(1.0, 0.95, 0.65, 1.0))
	if is_instance_valid(record_label):
		record_label.add_theme_color_override("default_color", Color(0.55, 0.95, 0.55, 1.0))


func _fit_standing_name_label(name_label: RichTextLabel, player_name: String) -> void:
	_fit_name_label(name_label, player_name, STANDING_NAME_FONT_MAX, STANDING_NAME_FONT_MIN, 287.0)


func _fit_name_label(name_label: RichTextLabel, player_name: String, max_font_size: int, min_font_size: int, fallback_width: float) -> void:
	if not is_instance_valid(name_label):
		return

	name_label.text = player_name
	name_label.clip_contents = true
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF

	var font := name_label.get_theme_font("normal_font")
	if font == null:
		return

	var available_width: float = name_label.size.x
	if available_width <= 0.0:
		available_width = fallback_width

	var fitted_size := min_font_size
	for candidate in range(max_font_size, min_font_size - 1, -1):
		var text_width := font.get_string_size(player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, candidate).x
		if text_width <= available_width:
			fitted_size = candidate
			break

	name_label.add_theme_font_size_override("normal_font_size", fitted_size)


func _get_game_manager() -> Node:
	return get_node_or_null(GAME_MANAGER_PATH)
