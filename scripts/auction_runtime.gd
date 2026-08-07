extends Node2D

const AUCTION_MENU_SCENE_PATH := "res://scenes/menus/auctionMenu.tscn"
const BIDDER_COUNT := 4
const INTRO_DELAY_SECONDS := 1.8
const OPEN_BIDDING_DELAY_SECONDS := 1.8
const COUNTDOWN_DELAY_SECONDS := 1.6
const RESULT_DELAY_SECONDS := 2.0
const STONE_VARIANT_TEXTURE_PATH := "res://assets/curling/stones/variants/%s/stone_variant_%s%04d.png"
const RED_SIDE_TEXTURE := preload("res://assets/curling/stones/stone_red_side.png")
const BLUE_SIDE_TEXTURE := preload("res://assets/curling/stones/stone_blue_side.png")
const YELLOW_SIDE_TEXTURE := preload("res://assets/curling/stones/stone_yellow_side.png")

const BIDDER_NONE := -2
const BIDDER_PLAYER := -1

enum AuctionState {
	INTRO,
	OPEN_BIDDING,
	COUNTDOWN_ONCE,
	COUNTDOWN_TWICE,
	COUNTDOWN_THREE,
	SOLD,
	COMPLETE,
}

@onready var message_label: RichTextLabel = $messageDiplay/text
@onready var stone_sprite: Sprite2D = $Rock
@onready var bidder_row: HBoxContainer = $Audience
@onready var bid_button_primary: TextureButton = $BidButton
@onready var bid_button_primary_text: RichTextLabel = $BidButton/text
@onready var bid_button_secondary: TextureButton = $BidButton2
@onready var bid_button_secondary_text: RichTextLabel = $BidButton2/text

var _manager: Node
var _pending_auction: Dictionary = {}
var _selected_stone: Stone
var _selected_stone_name: String = ""
var _mode: String = ""
var _state: AuctionState = AuctionState.INTRO
var _is_running: bool = false

var _current_bid: int = 0
var _starting_price: int = 0
var _highest_bidder: int = BIDDER_NONE
var _bid_step: int = 5
var _created_week: int = 1

var _ai_names: Array[String] = []
var _ai_profiles: Array[Dictionary] = []
var _ai_max_bids: Array[int] = []
var _ai_next_ready_time: Array[float] = []
var _priority_responder: int = BIDDER_NONE
var _bidder_sprites: Array[AnimatedSprite2D] = []
var _bid_animation_token: int = 0


func _ready() -> void:
	_manager = get_node_or_null("/root/game_manager")
	_initialize_ai_profiles()
	_initialize_bidder_defaults()

	if not _load_and_validate_pending_payload():
		_fail_and_return("Auction data missing. Returning to menu.")
		return

	if not _resolve_selected_stone():
		_fail_and_return("Selected stone is unavailable. Returning to menu.")
		return

	_configure_bid_ui_for_mode()
	_apply_stone_visual()
	_set_bid_button_text()

	_is_running = true
	call_deferred("_run_auction")


func player_bid() -> void:
	if not _is_running:
		return
	if _mode != "buy":
		return
	if _state == AuctionState.SOLD or _state == AuctionState.COMPLETE:
		return

	var next_bid := _current_bid + _bid_step
	if _manager == null:
		return

	if "money" in _manager and int(_manager.money) < next_bid:
		_set_message("You need %s to bid, but only have %s." % [
			_format_money(next_bid),
			_format_money(int(_manager.money)),
		])
		_update_player_bid_availability()
		return

	_apply_bid(BIDDER_PLAYER, next_bid)
	_set_message("You bid %s." % _format_money(next_bid))
	_state = AuctionState.OPEN_BIDDING


func _run_auction() -> void:
	_set_message(_build_opening_message())
	await get_tree().create_timer(INTRO_DELAY_SECONDS).timeout

	while _is_running and _state != AuctionState.COMPLETE:
		match _state:
			AuctionState.INTRO:
				_set_all_bidders_rest()
				_state = AuctionState.OPEN_BIDDING

			AuctionState.OPEN_BIDDING:
				_update_player_bid_availability()
				var did_bid := _simulate_ai_bid()
				if did_bid:
					await get_tree().create_timer(OPEN_BIDDING_DELAY_SECONDS).timeout
					continue
				_set_all_bidders_rest()
				_state = AuctionState.COUNTDOWN_ONCE

			AuctionState.COUNTDOWN_ONCE:
				var bid_before_once := _current_bid
				_set_all_bidders_rest()
				_set_message("going once at %s..." % _format_money(_current_bid))
				_attempt_sniping_bid(0.0)
				await get_tree().create_timer(COUNTDOWN_DELAY_SECONDS).timeout
				if _current_bid > bid_before_once:
					_state = AuctionState.OPEN_BIDDING
				else:
					_state = AuctionState.COUNTDOWN_TWICE

			AuctionState.COUNTDOWN_TWICE:
				var bid_before_twice := _current_bid
				_set_all_bidders_rest()
				_set_message("going twice at %s..." % _format_money(_current_bid))
				_attempt_sniping_bid(0.08)
				await get_tree().create_timer(COUNTDOWN_DELAY_SECONDS).timeout
				if _current_bid > bid_before_twice:
					_state = AuctionState.OPEN_BIDDING
				else:
					_state = AuctionState.COUNTDOWN_THREE

			AuctionState.COUNTDOWN_THREE:
				var bid_before_three := _current_bid
				_set_all_bidders_rest()
				_set_message("three times at %s..." % _format_money(_current_bid))
				_attempt_sniping_bid(0.16)
				await get_tree().create_timer(COUNTDOWN_DELAY_SECONDS).timeout
				if _current_bid > bid_before_three:
					_state = AuctionState.OPEN_BIDDING
				else:
					_state = AuctionState.SOLD

			AuctionState.SOLD:
				_finalize_auction_result()
				_state = AuctionState.COMPLETE

			AuctionState.COMPLETE:
				break


func _finalize_auction_result() -> void:
	_is_running = false
	_set_all_bidders_rest()
	_update_player_bid_availability()

	var winner_key := _winner_key_for_settlement()
	var settlement_ok := true
	if _manager != null and _manager.has_method("settle_pending_auction"):
		var settlement: Dictionary = _manager.settle_pending_auction(_current_bid, winner_key)
		if not bool(settlement.get("ok", false)):
			settlement_ok = false
			winner_key = "none"

	if not settlement_ok:
		_set_message("Auction voided due to settlement issue.")
	elif _highest_bidder == BIDDER_NONE:
		_set_message(_build_unsold_message())
	else:
		_set_message(_build_sold_message())

	await get_tree().create_timer(RESULT_DELAY_SECONDS).timeout
	if _manager != null and _manager.has_method("clear_pending_auction"):
		_manager.clear_pending_auction()
	_return_to_auction_menu()


func _simulate_ai_bid() -> bool:
	var now_seconds := Time.get_ticks_msec() / 1000.0
	var best_candidate: Dictionary = {}
	var best_score := -1.0

	for i in range(BIDDER_COUNT):
		var candidate := _evaluate_ai_bid_candidate(i, now_seconds)
		if candidate.is_empty():
			continue

		var candidate_score := float(candidate.get("score", 0.0))
		if candidate_score > best_score:
			best_candidate = candidate
			best_score = candidate_score

	if best_candidate.is_empty():
		return false

	var bidder_index := int(best_candidate.get("index", BIDDER_NONE))
	var bid_value := int(best_candidate.get("bid_value", _current_bid + _bid_step))
	if bidder_index < 0:
		return false

	_apply_bid(bidder_index, bid_value)
	_set_message("%s raises to %s. %s" % [
		_bidder_name_for_index(bidder_index),
		_format_money(bid_value),
		String(best_candidate.get("reaction", "")),
	])
	return true


func _apply_bid(bidder_index: int, bid_value: int) -> void:
	var previous_highest := _highest_bidder
	_current_bid = bid_value
	_highest_bidder = bidder_index
	_set_bid_button_text()

	if bidder_index >= 0:
		_set_bidder_cooldown(bidder_index)
		_play_ai_bid_animation(bidder_index)
	else:
		_set_all_bidders_rest()

	if previous_highest >= 0 and previous_highest != bidder_index:
		_priority_responder = previous_highest
	elif bidder_index == _priority_responder:
		_priority_responder = BIDDER_NONE


func _evaluate_ai_bid_candidate(bidder_index: int, now_seconds: float) -> Dictionary:
	if bidder_index < 0 or bidder_index >= BIDDER_COUNT:
		return {}
	if _highest_bidder == bidder_index:
		return {}
	if bidder_index >= _ai_max_bids.size() or bidder_index >= _ai_next_ready_time.size():
		return {}
	if now_seconds < _ai_next_ready_time[bidder_index]:
		return {}

	var next_bid := _current_bid + _bid_step
	var max_bid := _ai_max_bids[bidder_index]
	if next_bid > max_bid:
		return {}

	var profile := _profile_for_bidder(bidder_index)
	var aggression := clampf(float(profile.get("aggression", 0.5)), 0.0, 1.0)
	var patience := clampf(float(profile.get("patience", 0.5)), 0.0, 1.0)

	var bid_span: int = maxi(1, max_bid - _starting_price)
	var pressure := clampf(float(next_bid - _starting_price) / float(bid_span), 0.0, 1.0)
	var willingness := 1.0 - pressure

	var chance := 0.12 + (aggression * 0.46) + (willingness * 0.24) + ((1.0 - patience) * 0.08)
	if _priority_responder == bidder_index:
		chance += 0.18
	if _highest_bidder == BIDDER_PLAYER and _mode == "buy":
		chance += 0.1

	chance = clampf(chance, 0.0, 0.95)
	if randf() > chance:
		return {}

	var increment_steps := _pick_increment_steps(bidder_index, max_bid)
	var bid_value := _current_bid + (increment_steps * _bid_step)
	if bid_value > max_bid:
		bid_value = next_bid

	var score := chance + randf() * 0.12 + (aggression * 0.08)
	return {
		"index": bidder_index,
		"bid_value": bid_value,
		"score": score,
		"reaction": _reaction_for_bidder(bidder_index, increment_steps),
	}


func _attempt_sniping_bid(extra_chance: float) -> bool:
	var now_seconds := Time.get_ticks_msec() / 1000.0
	var candidates: Array[Dictionary] = []

	for i in range(BIDDER_COUNT):
		if i == _highest_bidder:
			continue
		if i >= _ai_max_bids.size() or i >= _ai_next_ready_time.size():
			continue
		if now_seconds < _ai_next_ready_time[i]:
			continue

		var max_bid := _ai_max_bids[i]
		var next_bid := _current_bid + _bid_step
		if next_bid > max_bid:
			continue

		var profile := _profile_for_bidder(i)
		var snipe_chance := clampf(float(profile.get("sniping_chance", 0.0)) + extra_chance, 0.0, 0.9)
		if _priority_responder == i:
			snipe_chance = minf(0.95, snipe_chance + 0.16)

		if randf() <= snipe_chance:
			candidates.append({
				"index": i,
				"bid_value": next_bid,
				"score": snipe_chance + randf() * 0.1,
			})

	if candidates.is_empty():
		return false

	var winner := candidates[0]
	for item in candidates:
		if float(item.get("score", 0.0)) > float(winner.get("score", 0.0)):
			winner = item

	var bidder_index := int(winner.get("index", BIDDER_NONE))
	var bid_value := int(winner.get("bid_value", _current_bid + _bid_step))
	if bidder_index < 0:
		return false

	_apply_bid(bidder_index, bid_value)
	_set_message("Late bid: %s moves it to %s!" % [
		_bidder_name_for_index(bidder_index),
		_format_money(bid_value),
	])
	return true


func _set_bidder_cooldown(bidder_index: int) -> void:
	if bidder_index < 0 or bidder_index >= _ai_next_ready_time.size():
		return

	var profile := _profile_for_bidder(bidder_index)
	var min_cooldown := maxf(float(profile.get("cooldown_min", 0.4)), 0.1)
	var max_cooldown := maxf(float(profile.get("cooldown_max", min_cooldown)), min_cooldown)
	_ai_next_ready_time[bidder_index] = (Time.get_ticks_msec() / 1000.0) + randf_range(min_cooldown, max_cooldown)


func _pick_increment_steps(bidder_index: int, max_bid: int) -> int:
	var profile := _profile_for_bidder(bidder_index)
	var aggression := clampf(float(profile.get("aggression", 0.5)), 0.0, 1.0)
	var can_jump := _current_bid + (_bid_step * 2) <= max_bid
	if can_jump and randf() < (0.1 + aggression * 0.25):
		return 2
	return 1


func _reaction_for_bidder(bidder_index: int, increment_steps: int) -> String:
	var profile := _profile_for_bidder(bidder_index)
	var aggression := float(profile.get("aggression", 0.5))
	if increment_steps >= 2:
		return "Bold jump."
	if aggression > 0.7:
		return "No hesitation."
	if aggression < 0.4:
		return "Measured raise."
	return "Keeps it moving."


func _load_and_validate_pending_payload() -> bool:
	if _manager == null or not _manager.has_method("get_pending_auction"):
		return false

	_pending_auction = _manager.get_pending_auction()
	if _pending_auction.is_empty():
		return false

	_mode = String(_pending_auction.get("mode", "")).to_lower()
	if _mode != "buy" and _mode != "sell":
		return false

	_starting_price = max(int(_pending_auction.get("starting_price", 0)), 0)
	_current_bid = _starting_price
	_created_week = max(int(_pending_auction.get("created_week", 1)), 1)
	_bid_step = _compute_bid_step(_starting_price)

	var stone_index := int(_pending_auction.get("stone_index", -1))
	if stone_index < 0:
		return false

	if _mode == "buy":
		var store_stones: Array = _manager.get_store_stones() if _manager.has_method("get_store_stones") else []
		if stone_index >= store_stones.size():
			return false
	else:
		var player_stones: Array = _manager.get_player_stones() if _manager.has_method("get_player_stones") else []
		if stone_index >= player_stones.size():
			return false

	return true


func _resolve_selected_stone() -> bool:
	if _manager == null:
		return false

	var stone_index := int(_pending_auction.get("stone_index", -1))
	if stone_index < 0:
		return false

	var source: Array = []
	if _mode == "buy" and _manager.has_method("get_store_stones"):
		source = _manager.get_store_stones()
	elif _mode == "sell" and _manager.has_method("get_player_stones"):
		source = _manager.get_player_stones()

	if stone_index >= source.size():
		return false

	_selected_stone = source[stone_index]
	if _selected_stone == null:
		return false

	_selected_stone_name = String(_pending_auction.get("stone_name", "")).strip_edges()
	if _selected_stone_name == "":
		_selected_stone_name = String(_selected_stone.name).strip_edges()
	if _selected_stone_name == "":
		_selected_stone_name = "stone"

	_initialize_ai_limits_for_selected_stone()
	return true


func _compute_bid_step(base_price: int) -> int:
	if base_price >= 500:
		return 25
	if base_price >= 250:
		return 10
	return 5


func _initialize_ai_limits_for_selected_stone() -> void:
	_ai_max_bids.clear()
	_ai_next_ready_time.clear()
	_priority_responder = BIDDER_NONE

	var valuation := _calculate_base_stone_value()
	var market_drift := clampf((_created_week - 1) * 0.02, 0.0, 0.32)

	for i in range(BIDDER_COUNT):
		var profile := _profile_for_bidder(i)
		var aggression := float(profile.get("aggression", 0.5))
		var budget_factor := float(profile.get("budget_factor", 1.0))
		var variance := randf_range(-0.08, 0.09)
		var personal_bias := aggression * 0.06
		var willingness_factor := maxf(0.72, budget_factor + market_drift + variance + personal_bias)
		var willingness := int(round(valuation * willingness_factor))
		_ai_max_bids.append(max(willingness, _starting_price))
		_ai_next_ready_time.append(0.0)


func _calculate_base_stone_value() -> int:
	if _selected_stone == null:
		return _starting_price

	if _mode == "sell" and _selected_stone.has_method("calculate_sell_price"):
		return max(int(_selected_stone.calculate_sell_price(_created_week)), _starting_price)

	if _selected_stone.has_method("calculate_buy_price"):
		return max(int(_selected_stone.calculate_buy_price(_created_week)), _starting_price)

	if _selected_stone.has_method("calculate_value"):
		return max(int(round(_selected_stone.calculate_value(_created_week))), _starting_price)

	return _starting_price


func _initialize_ai_profiles() -> void:
	_ai_profiles = [
		{
			"name": "Mara Quickhand",
			"variant_index": 1,
			"aggression": 0.75,
			"budget_factor": 1.08,
			"patience": 0.38,
			"sniping_chance": 0.18,
			"cooldown_min": 0.9,
			"cooldown_max": 1.6,
		},
		{
			"name": "Otis Ledger",
			"variant_index": 2,
			"aggression": 0.34,
			"budget_factor": 0.93,
			"patience": 0.82,
			"sniping_chance": 0.09,
			"cooldown_min": 1.2,
			"cooldown_max": 2.0,
		},
		{
			"name": "Rin Ashford",
			"variant_index": 4,
			"aggression": 0.58,
			"budget_factor": 1.0,
			"patience": 0.62,
			"sniping_chance": 0.23,
			"cooldown_min": 1.0,
			"cooldown_max": 1.8,
		},
		{
			"name": "Bex Kline",
			"variant_index": 6,
			"aggression": 0.86,
			"budget_factor": 1.15,
			"patience": 0.29,
			"sniping_chance": 0.3,
			"cooldown_min": 0.8,
			"cooldown_max": 1.5,
		},
	]


func _initialize_bidder_defaults() -> void:
	_ai_names.clear()
	_bidder_sprites.clear()
	for i in range(BIDDER_COUNT):
		var profile := _profile_for_bidder(i)
		_ai_names.append(String(profile.get("name", "Bidder %d" % (i + 1))))

	if not is_instance_valid(bidder_row):
		return

	var children := bidder_row.get_children()
	for i in range(children.size()):
		var slot := children[i]
		var sprite := slot.get_node_or_null("Sprite") as AnimatedSprite2D
		if sprite == null:
			_bidder_sprites.append(null)
			continue

		_bidder_sprites.append(sprite)

		var profile := _profile_for_bidder(i)
		var variant := clampi(int(profile.get("variant_index", i + 1)), 1, 6)
		var default_anim := "bidder%d_default" % variant
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(default_anim):
			sprite.play(default_anim)


func _set_all_bidders_rest() -> void:
	for i in range(_bidder_sprites.size()):
		_set_bidder_visual_state(i, false)


func _set_bidder_visual_state(bidder_index: int, is_bidding: bool) -> void:
	if bidder_index < 0 or bidder_index >= _bidder_sprites.size():
		return

	var sprite := _bidder_sprites[bidder_index]
	if sprite == null or sprite.sprite_frames == null:
		return

	var profile := _profile_for_bidder(bidder_index)
	var variant := clampi(int(profile.get("variant_index", bidder_index + 1)), 1, 6)
	var anim_name := "bidder%d_active" % variant if is_bidding else "bidder%d_default" % variant
	if sprite.sprite_frames.has_animation(anim_name):
		sprite.play(anim_name)


func _play_ai_bid_animation(bidder_index: int) -> void:
	if bidder_index < 0:
		return

	_bid_animation_token += 1
	var token := _bid_animation_token

	for i in range(_bidder_sprites.size()):
		_set_bidder_visual_state(i, i == bidder_index)

	call_deferred("_complete_bid_animation", token)


func _complete_bid_animation(token: int) -> void:
	await get_tree().create_timer(0.55).timeout
	if token != _bid_animation_token:
		return
	_set_all_bidders_rest()


func _configure_bid_ui_for_mode() -> void:
	var allow_player_bid := _mode == "buy"

	if is_instance_valid(bid_button_primary):
		bid_button_primary.visible = allow_player_bid
		bid_button_primary.disabled = not allow_player_bid
	if is_instance_valid(bid_button_secondary):
		bid_button_secondary.visible = allow_player_bid
		bid_button_secondary.disabled = not allow_player_bid

	if not allow_player_bid:
		_set_message("Sell mode: AI bidders only.")


func _update_player_bid_availability() -> void:
	if _mode != "buy":
		return
	if _manager == null:
		return

	var can_bid := true
	if "money" in _manager:
		can_bid = int(_manager.money) >= (_current_bid + _bid_step)

	if is_instance_valid(bid_button_primary):
		bid_button_primary.disabled = not can_bid
	if is_instance_valid(bid_button_secondary):
		bid_button_secondary.disabled = not can_bid


func _set_bid_button_text() -> void:
	var text := "Bid $%d" % (_current_bid + _bid_step)
	if is_instance_valid(bid_button_primary_text):
		bid_button_primary_text.text = text
	if is_instance_valid(bid_button_secondary_text):
		bid_button_secondary_text.text = text


func _set_message(message: String) -> void:
	if not is_instance_valid(message_label):
		return
	message_label.text = "[center]%s[/center]" % message


func _bidder_name_for_index(bidder_index: int) -> String:
	if bidder_index == BIDDER_PLAYER:
		return "Player"
	if bidder_index >= 0 and bidder_index < _ai_names.size():
		return _ai_names[bidder_index]
	return "Unknown"


func _apply_stone_visual() -> void:
	if not is_instance_valid(stone_sprite):
		return
	if _selected_stone == null:
		return

	var stone_color := _get_display_stone_color()
	var normalized_color := _normalize_variant_color(stone_color)
	var variant := clampi(int(_selected_stone.variant), Stone.MIN_VARIANT, Stone.MAX_VARIANT)
	var texture_path := STONE_VARIANT_TEXTURE_PATH % [normalized_color, normalized_color, variant]
	var texture := load(texture_path) as Texture2D
	if texture != null:
		stone_sprite.texture = texture
		return

	match normalized_color:
		"blue":
			stone_sprite.texture = BLUE_SIDE_TEXTURE
		"yellow":
			stone_sprite.texture = YELLOW_SIDE_TEXTURE
		_:
			stone_sprite.texture = RED_SIDE_TEXTURE


func _get_display_stone_color() -> String:
	if _manager != null and "player_color" in _manager:
		return String(_manager.player_color)
	return "red"


func _normalize_variant_color(stone_color: String) -> String:
	match stone_color:
		"blue", "yellow", "red":
			return stone_color
		_:
			return "red"


func _fail_and_return(message: String) -> void:
	_set_message(message)
	await get_tree().create_timer(1.2).timeout
	if _manager != null and _manager.has_method("clear_pending_auction"):
		_manager.clear_pending_auction()
	_return_to_auction_menu()


func _return_to_auction_menu() -> void:
	var error := get_tree().change_scene_to_file(AUCTION_MENU_SCENE_PATH)
	if error != OK:
		push_warning("auction_runtime: failed to return to auction menu")


func _profile_for_bidder(index: int) -> Dictionary:
	if index < 0 or index >= _ai_profiles.size():
		return {}
	return _ai_profiles[index]


func _winner_key_for_settlement() -> String:
	if _highest_bidder == BIDDER_NONE:
		return "none"
	if _mode == "buy" and _highest_bidder == BIDDER_PLAYER:
		return "player"
	return "ai"


func _build_opening_message() -> String:
	if _mode == "sell":
		return "Auction starts at %s for your %s. AI bidders only." % [
			_format_money(_starting_price),
			_selected_stone_name,
		]

	return "Auction starts at %s for %s. You can bid now." % [
		_format_money(_starting_price),
		_selected_stone_name,
	]


func _build_unsold_message() -> String:
	if _mode == "sell":
		return "No bids. Your %s remains in your collection." % _selected_stone_name
	return "No bids. %s remains available in the market." % _selected_stone_name


func _build_sold_message() -> String:
	if _mode == "buy" and _highest_bidder == BIDDER_PLAYER:
		return "Sold to you for %s!" % _format_money(_current_bid)

	if _mode == "sell":
		return "Sold! %s buys your %s for %s." % [
			_bidder_name_for_index(_highest_bidder),
			_selected_stone_name,
			_format_money(_current_bid),
		]

	return "Sold to %s for %s!" % [
		_bidder_name_for_index(_highest_bidder),
		_format_money(_current_bid),
	]


func _format_money(value: int) -> String:
	return "$%d" % max(value, 0)
