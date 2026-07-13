extends RefCounted

## difficulty: 1 (worst) to 10 (best). Set this from curlinggame.gd after instantiating.
var difficulty: int = 5
var debug_telemetry_enabled: bool = false

var rng := RandomNumberGenerator.new()

const _STONE_DIAMETER := 30.0
const _SIM_DT := 1.0 / 60.0
const _SIM_MAX_STEPS := 480
const _MIN_SOLVE_DISTANCE := 6.0


func _init() -> void:
	rng.randomize()


func get_think_time() -> float:
	var p := _get_difficulty_params()
	return rng.randf_range(p["think_min"], p["think_max"])


func choose_shot(planning_context: Dictionary, stone: RigidBody2D, stones_data: Array[Dictionary], stones_per_player: int) -> Dictionary:
	var context := _normalize_context(planning_context, stone)
	var p := _apply_match_state_params(_get_difficulty_params(), context)
	var spawn: Vector2 = context["stone_spawn_position"]
	var house_center: Vector2 = context["house_center"]
	var house_radius: float = context["house_radius"]
	var ai_color: String = String(stone.get("stone_color"))

	# Exclude the stone currently being thrown -- it sits at spawn and has not been placed yet.
	var placed: Array[Dictionary] = []
	var spawn_exclusion_radius := maxf(_STONE_DIAMETER * 1.5, house_radius * 0.12)
	for sd in stones_data:
		if (sd["position"] as Vector2).distance_to(spawn) > spawn_exclusion_radius:
			placed.append(sd)

	var board := _analyze_board(placed, house_center, house_radius, ai_color)
	var ai_thrown: int = (board["ai_stones_in_house"] as Array).size() + int(board["ai_outside_count"])
	var stones_remaining: int = maxi(stones_per_player - ai_thrown, 0)
	var shot_type: String = _choose_shot_type(board, stones_remaining, p, context)

	var candidates := _generate_candidates(shot_type, board, context, p)
	if candidates.is_empty():
		candidates = _generate_candidates("draw", board, context, p)
	if candidates.is_empty():
		var fallback_min_power := float(stone.get("min_power"))
		if fallback_min_power <= 0.0:
			fallback_min_power = 260.0
		return {"direction": Vector2.UP, "power": fallback_min_power, "spin": 0.0}

	var scored: Array[Dictionary] = []
	for candidate in candidates:
		var estimate := _estimate_candidate(candidate, context, placed, ai_color)
		var score := _score_candidate(shot_type, candidate, estimate, board, context, p)
		scored.append({
			"candidate": candidate,
			"estimate": estimate,
			"score": score,
		})

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)

	var selected := _pick_candidate(scored, p)
	var shot_candidate: Dictionary = selected["candidate"]
	var shot_estimate: Dictionary = selected["estimate"]
	var shot_direction := (shot_candidate["target"] as Vector2 - spawn).normalized()
	if shot_direction == Vector2.ZERO:
		shot_direction = Vector2.UP
	var board_summary := {
		"ai_in_house": (board["ai_stones_in_house"] as Array).size(),
		"opp_in_house": (board["opp_stones_in_house"] as Array).size(),
		"opp_guards": (board["opp_guards"] as Array).size(),
		"ai_is_scoring": bool(board["ai_is_scoring"]),
		"opp_is_scoring": bool(board["opp_is_scoring"]),
		"closest_ai_distance": -1.0 if float(board["closest_ai_distance"]) == INF else float(board["closest_ai_distance"]),
		"closest_opp_distance": -1.0 if float(board["closest_opp_distance"]) == INF else float(board["closest_opp_distance"]),
	}
	var debug_info := {
		"mode": "planned_shot",
		"ai_color": ai_color,
		"difficulty": difficulty,
		"shot_type": String(shot_candidate.get("shot_type", shot_type)),
		"candidate_count": scored.size(),
		"selected_score": float(selected["score"]),
		"target": shot_candidate["target"],
		"predicted_stop": shot_estimate["predicted_stop"],
		"power": float(shot_estimate["power"]),
		"spin": float(shot_candidate["spin"]),
		"target_delta": float(shot_estimate["target_delta"]),
		"house_delta": float(shot_estimate["house_delta"]),
		"collision_risk": float(shot_estimate["collision_risk"]),
		"stones_remaining": stones_remaining,
		"board": board_summary,
	}

	var debug_line := ""
	if debug_telemetry_enabled:
		debug_line = "AI %s score=%.2f delta=%.1f house=%.1f risk=%.2f" % [
			String(shot_candidate.get("shot_type", shot_type)),
			float(selected["score"]),
			float(shot_estimate["target_delta"]),
			float(shot_estimate["house_delta"]),
			float(shot_estimate["collision_risk"]),
		]

	return {
		"direction": shot_direction,
		"power": float(shot_estimate["power"]),
		"spin": float(shot_candidate["spin"]),
		"debug_info": debug_info,
		"debug_line": debug_line,
	}


# ---------------------------------------------------------------------------
# Context / Physics
# ---------------------------------------------------------------------------

func _normalize_context(planning_context: Dictionary, stone: RigidBody2D) -> Dictionary:
	var spawn := planning_context.get("stone_spawn_position", stone.global_position) as Vector2
	var house_center := planning_context.get("house_center", spawn + Vector2(0.0, -700.0)) as Vector2
	var house_radius := maxf(float(planning_context.get("house_radius", 120.0)), 1.0)
	var throw_distance_scale := maxf(float(planning_context.get("throw_distance_scale", stone.get("throw_distance_scale"))), 0.0001)
	var match_state := planning_context.get("match_state", {}) as Dictionary

	var current_end := maxi(int(match_state.get("current_end", 1)), 1)
	var max_ends := maxi(int(match_state.get("max_ends", current_end)), current_end)
	var ai_score := int(match_state.get("ai_score", 0))
	var opponent_score := int(match_state.get("opponent_score", 0))
	var ends_remaining := maxi(max_ends - current_end, 0)
	match_state = {
		"current_end": current_end,
		"max_ends": max_ends,
		"ends_remaining": ends_remaining,
		"ai_score": ai_score,
		"opponent_score": opponent_score,
		"score_diff": ai_score - opponent_score,
		"ai_has_hammer": bool(match_state.get("ai_has_hammer", false)),
	}

	var physics := planning_context.get("physics", {}) as Dictionary
	if physics.is_empty():
		var min_power := float(stone.get("min_power"))
		var max_power := float(stone.get("max_power"))
		if min_power <= 0.0:
			min_power = 260.0
		if max_power <= min_power:
			max_power = maxf(min_power + 0.001, 800.0)
		physics = {
			"throw_distance_scale": throw_distance_scale,
			"launch_speed_multiplier": float(stone.get("launch_speed_multiplier")),
			"stop_deceleration": float(stone.get("stop_deceleration")),
			"low_speed_threshold": float(stone.get("low_speed_threshold")),
			"extra_low_speed_deceleration": float(stone.get("extra_low_speed_deceleration")),
			"stop_speed_cutoff": float(stone.get("stop_speed_cutoff")),
			"use_staged_deceleration_profile": bool(stone.get("use_staged_deceleration_profile")),
			"decel_stage_early_value": float(stone.get("decel_stage_early_value")),
			"decel_stage_mid_value": float(stone.get("decel_stage_mid_value")),
			"decel_stage_tail_value": float(stone.get("decel_stage_tail_value")),
			"decel_stage_mid_speed": float(stone.get("decel_stage_mid_speed")),
			"decel_stage_tail_speed": float(stone.get("decel_stage_tail_speed")),
			"decel_stage_blend_band": float(stone.get("decel_stage_blend_band")),
			"max_curl_acceleration": float(stone.get("max_curl_acceleration")),
			"max_spin_input_degrees": float(stone.get("max_spin_input_degrees")),
			"min_power": min_power,
			"max_power": max_power,
		}

	physics["throw_distance_scale"] = throw_distance_scale
	physics["launch_speed_multiplier"] = maxf(float(physics.get("launch_speed_multiplier", 1.35)), 0.0001)
	physics["stop_speed_cutoff"] = maxf(float(physics.get("stop_speed_cutoff", 6.0)), 0.0001)
	physics["max_spin_input_degrees"] = maxf(float(physics.get("max_spin_input_degrees", 270.0)), 0.0001)
	physics["min_power"] = maxf(float(physics.get("min_power", 260.0)), 0.0)
	physics["max_power"] = maxf(float(physics.get("max_power", 800.0)), physics["min_power"] + 0.001)

	return {
		"stone_spawn_position": spawn,
		"house_center": house_center,
		"house_radius": house_radius,
		"rink_forward": (house_center - spawn).normalized(),
		"rink_lateral": Vector2(-(house_center - spawn).normalized().y, (house_center - spawn).normalized().x),
		"match_state": match_state,
		"physics": physics,
	}


# ---------------------------------------------------------------------------
# Board Analysis
# ---------------------------------------------------------------------------

func _analyze_board(placed: Array[Dictionary], house_center: Vector2, house_radius: float, ai_color: String) -> Dictionary:
	var ai_in_house: Array[Dictionary] = []
	var opp_in_house: Array[Dictionary] = []
	var ai_outside_count := 0
	var opp_guards: Array = []
	var closest_opponent := house_center
	var closest_opp_dist := INF
	var closest_ai := house_center
	var closest_ai_dist := INF

	for sd in placed:
		var pos: Vector2 = sd["position"]
		var color: String = String(sd["color"])
		var dist := pos.distance_to(house_center)
		if color == ai_color:
			if dist <= house_radius:
				ai_in_house.append({"position": pos, "distance": dist})
				if dist < closest_ai_dist:
					closest_ai_dist = dist
					closest_ai = pos
			else:
				ai_outside_count += 1
		else:
			if dist <= house_radius:
				opp_in_house.append({"position": pos, "distance": dist})
				if dist < closest_opp_dist:
					closest_opp_dist = dist
					closest_opponent = pos
			elif pos.y > house_center.y + (house_radius * 0.05):
				# Between the house and the throwing end -- a potential guard.
				opp_guards.append(pos)

	ai_in_house.sort_custom(func(a, b): return a["distance"] < b["distance"])
	opp_in_house.sort_custom(func(a, b): return a["distance"] < b["distance"])

	var ai_is_scoring := false
	var opp_is_scoring := false
	if not ai_in_house.is_empty() and not opp_in_house.is_empty():
		ai_is_scoring = float(ai_in_house[0]["distance"]) < float(opp_in_house[0]["distance"])
		opp_is_scoring = not ai_is_scoring
	elif not ai_in_house.is_empty():
		ai_is_scoring = true
	elif not opp_in_house.is_empty():
		opp_is_scoring = true

	return {
		"ai_stones_in_house": ai_in_house,
		"opp_stones_in_house": opp_in_house,
		"ai_outside_count": ai_outside_count,
		"opp_guards": opp_guards,
		"ai_is_scoring": ai_is_scoring,
		"opp_is_scoring": opp_is_scoring,
		"closest_opponent": closest_opponent,
		"closest_opp_distance": closest_opp_dist,
		"closest_ai": closest_ai,
		"closest_ai_distance": closest_ai_dist,
	}


# ---------------------------------------------------------------------------
# Strategy Selection
# ---------------------------------------------------------------------------

func _choose_shot_type(board: Dictionary, stones_remaining: int, p: Dictionary, context: Dictionary) -> String:
	var match_state := context["match_state"] as Dictionary
	var score_diff := int(match_state.get("score_diff", 0))
	var ends_remaining := int(match_state.get("ends_remaining", 0))
	var ai_has_hammer := bool(match_state.get("ai_has_hammer", false))
	var late_game := ends_remaining <= 1

	# Low difficulty: mostly draw, occasional random takeout.
	if int(p["strategy_level"]) == 0:
		return "takeout" if rng.randf() < 0.28 else "draw"

	if late_game and score_diff > 0 and bool(board["ai_is_scoring"]) and stones_remaining <= 2:
		if rng.randf() < float(p["late_lead_guard_chance"]):
			return "guard"

	if late_game and score_diff < 0 and stones_remaining <= 2:
		if bool(board["opp_is_scoring"]):
			return "takeout"
		if not ai_has_hammer and rng.randf() < float(p["late_trail_guard_chance"]):
			return "guard"

	# Basic and full strategy: react to board state.
	if bool(board["opp_is_scoring"]):
		return "takeout"

	if bool(board["ai_is_scoring"]):
		var ai_in_house := board["ai_stones_in_house"] as Array
		if ai_in_house.size() == 1 and stones_remaining >= 2:
			return "draw_second"
		if int(p["strategy_level"]) >= 2 and ai_in_house.size() >= 2 and stones_remaining >= 1:
			if rng.randf() < p["guard_choice_chance"]:
				return "guard"

	return "draw"


func _apply_match_state_params(base_params: Dictionary, context: Dictionary) -> Dictionary:
	var adjusted := base_params.duplicate(true)
	var match_state := context["match_state"] as Dictionary
	var score_diff := int(match_state.get("score_diff", 0))
	var ends_remaining := int(match_state.get("ends_remaining", 0))
	var max_ends := maxi(int(match_state.get("max_ends", 1)), 1)
	var late_weight := 1.0 - (float(ends_remaining) / float(max_ends))
	late_weight = clampf(late_weight, 0.0, 1.0)

	if score_diff < 0:
		var trailing_by := minf(float(-score_diff), 4.0)
		adjusted["scoring_swing_weight"] = float(adjusted["scoring_swing_weight"]) + trailing_by * lerpf(0.8, 2.6, late_weight)
		adjusted["in_house_bonus"] = float(adjusted["in_house_bonus"]) + trailing_by * lerpf(0.5, 1.8, late_weight)
		adjusted["collision_risk_weight"] = maxf(2.0, float(adjusted["collision_risk_weight"]) - trailing_by * lerpf(0.2, 1.1, late_weight))
		adjusted["guard_choice_chance"] = maxf(0.08, float(adjusted["guard_choice_chance"]) - trailing_by * lerpf(0.02, 0.07, late_weight))
		adjusted["takeout_power_bias"] = float(adjusted["takeout_power_bias"]) + trailing_by * lerpf(0.0, 0.02, late_weight)
	elif score_diff > 0:
		var leading_by := minf(float(score_diff), 4.0)
		adjusted["collision_risk_weight"] = float(adjusted["collision_risk_weight"]) + leading_by * lerpf(0.5, 1.8, late_weight)
		adjusted["guard_choice_chance"] = minf(0.85, float(adjusted["guard_choice_chance"]) + leading_by * lerpf(0.03, 0.09, late_weight))
		adjusted["guard_band_bonus"] = float(adjusted["guard_band_bonus"]) + leading_by * lerpf(0.4, 1.4, late_weight)
		adjusted["takeout_hit_weight"] = maxf(8.0, float(adjusted["takeout_hit_weight"]) - leading_by * lerpf(0.2, 0.8, late_weight))

	adjusted["guard_choice_chance"] = clampf(float(adjusted["guard_choice_chance"]), 0.05, 0.9)
	return adjusted


# ---------------------------------------------------------------------------
# Candidate Generation
# ---------------------------------------------------------------------------

func _generate_candidates(shot_type: String, board: Dictionary, context: Dictionary, p: Dictionary) -> Array[Dictionary]:
	var targets: Array[Vector2] = []
	var spin_ratios: Array[float] = []
	var power_seeds: Array[float] = _build_power_seeds(int(p["power_seed_count"]), float(p["power_seed_half_span"]))
	var shot_power_bias := 1.0
	var house_center: Vector2 = context["house_center"]
	var spawn: Vector2 = context["stone_spawn_position"]
	var lateral := context["rink_lateral"] as Vector2
	if lateral.length_squared() < 0.00001:
		lateral = Vector2.RIGHT

	match shot_type:
		"takeout":
			targets = _build_takeout_targets(board, context, p)
			spin_ratios = [
				-float(p["takeout_spin_ratio"]),
				0.0,
				float(p["takeout_spin_ratio"]),
			]
			shot_power_bias = float(p["takeout_power_bias"])
		"guard":
			targets = _build_guard_targets(context, p)
			spin_ratios = [
				-float(p["guard_spin_ratio"]),
				0.0,
				float(p["guard_spin_ratio"]),
			]
			shot_power_bias = float(p["guard_power_bias"])
		"draw_second":
			targets = _build_draw_targets(board, context, p, true)
			spin_ratios = _build_draw_spin_ratios(board, context, p)
			shot_power_bias = float(p["draw_second_power_bias"])
		_:
			targets = _build_draw_targets(board, context, p, false)
			spin_ratios = _build_draw_spin_ratios(board, context, p)
			shot_power_bias = float(p["draw_power_bias"])

	var candidates: Array[Dictionary] = []
	var max_spin: float = float(context["physics"]["max_spin_input_degrees"])
	for target in targets:
		for spin_ratio in spin_ratios:
			for power_seed in power_seeds:
				candidates.append({
					"shot_type": shot_type,
					"target": target,
					"spin": clampf(spin_ratio, -1.0, 1.0) * max_spin,
					"power_seed": power_seed,
					"shot_power_bias": shot_power_bias,
				})

	# Add slight target scatter by difficulty to keep weak AI less repeatable.
	for i in range(candidates.size()):
		var candidate: Dictionary = candidates[i]
		var noisy_target := candidate["target"] as Vector2
		var noise := float(p["target_noise_px"])
		if noise > 0.0:
			noisy_target += lateral * rng.randf_range(-noise, noise)
			noisy_target += (house_center - spawn).normalized() * rng.randf_range(-noise * 0.6, noise * 0.4)
		candidate["target"] = noisy_target
		candidates[i] = candidate

	return candidates


func _build_draw_targets(board: Dictionary, context: Dictionary, p: Dictionary, second_stone: bool) -> Array[Vector2]:
	var house_center: Vector2 = context["house_center"]
	var house_radius: float = context["house_radius"]
	var lateral := context["rink_lateral"] as Vector2
	if lateral.length_squared() < 0.00001:
		lateral = Vector2.RIGHT

	var forward := (house_center - context["stone_spawn_position"] as Vector2).normalized()
	if forward.length_squared() < 0.00001:
		forward = Vector2.UP

	var ring := house_radius * float(p["draw_ring_ratio"])
	var targets: Array[Vector2] = [house_center]
	targets.append(house_center + lateral * ring)
	targets.append(house_center - lateral * ring)
	targets.append(house_center + forward * ring * 0.45)

	if second_stone:
		var ai_in_house := board["ai_stones_in_house"] as Array
		var offset_ratio := float(p["draw_second_offset_ratio"])
		if not ai_in_house.is_empty():
			var existing_pos: Vector2 = ai_in_house[0]["position"]
			var away := (existing_pos - house_center).normalized()
			if away == Vector2.ZERO:
				away = lateral
			targets = [house_center + away.rotated(PI * 0.36) * (house_radius * offset_ratio)]
		else:
			targets = [house_center + lateral * (house_radius * offset_ratio)]

	return targets


func _build_takeout_targets(board: Dictionary, context: Dictionary, p: Dictionary) -> Array[Vector2]:
	var target := board["closest_opponent"] as Vector2
	var house_center: Vector2 = context["house_center"]
	var lateral := context["rink_lateral"] as Vector2
	if lateral.length_squared() < 0.00001:
		lateral = Vector2.RIGHT

	if float(board["closest_opp_distance"]) == INF:
		target = house_center

	var flank: float = float(context["house_radius"]) * float(p["takeout_flank_ratio"])
	return [
		target,
		target + lateral * flank,
		target - lateral * flank,
	]


func _build_guard_targets(context: Dictionary, p: Dictionary) -> Array[Vector2]:
	var house_center: Vector2 = context["house_center"]
	var house_radius: float = context["house_radius"]
	var forward := (house_center - context["stone_spawn_position"] as Vector2).normalized()
	if forward.length_squared() < 0.00001:
		forward = Vector2.UP
	var lateral := context["rink_lateral"] as Vector2
	if lateral.length_squared() < 0.00001:
		lateral = Vector2.RIGHT

	var min_front := house_radius * float(p["guard_front_min_ratio"])
	var max_front := house_radius * float(p["guard_front_max_ratio"])
	var lane_half := house_radius * float(p["guard_lane_half_width_ratio"])
	var front := rng.randf_range(min_front, max_front)
	var center_guard := house_center - forward * front

	return [
		center_guard,
		center_guard + lateral * lane_half,
		center_guard - lateral * lane_half,
	]


func _build_draw_spin_ratios(board: Dictionary, context: Dictionary, p: Dictionary) -> Array[float]:
	var base: Array[float] = [
		-float(p["draw_spin_ratio"]),
		0.0,
		float(p["draw_spin_ratio"]),
	]
	if not bool(p["use_guard_curl"]):
		return base

	var spawn: Vector2 = context["stone_spawn_position"]
	var target: Vector2 = context["house_center"]
	var blocker := _find_blocking_guard(spawn, target, board["opp_guards"], context["house_radius"] * float(p["guard_block_width_ratio"]))
	if blocker.x >= INF:
		return base

	var strong := float(p["curl_around_guard_spin_ratio"])
	if blocker.x <= context["house_center"].x:
		base.append(strong)
	else:
		base.append(-strong)
	return base


func _build_power_seeds(seed_count: int, half_span: float) -> Array[float]:
	var count := maxi(seed_count, 1)
	if count == 1:
		var single: Array[float] = [1.0]
		return single

	var seeds: Array[float] = []
	for i in range(count):
		var t := float(i) / float(count - 1)
		seeds.append(lerpf(1.0 - half_span, 1.0 + half_span, t))
	return seeds


# ---------------------------------------------------------------------------
# Estimation / Scoring
# ---------------------------------------------------------------------------

func _estimate_candidate(candidate: Dictionary, context: Dictionary, placed: Array[Dictionary], ai_color: String) -> Dictionary:
	var spawn: Vector2 = context["stone_spawn_position"]
	var target: Vector2 = candidate["target"]
	var physics: Dictionary = context["physics"]
	var direction := (target - spawn).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.UP

	var base_power := _calculate_base_power(spawn, target, physics)
	var min_power := float(physics["min_power"])
	var max_power := float(physics["max_power"])
	var seeded_power := base_power * float(candidate["power_seed"]) * float(candidate["shot_power_bias"])
	var power := clampf(seeded_power, min_power, max_power)
	var stop_pos := _simulate_stop_point(spawn, direction, power, float(candidate["spin"]), physics)
	var path_risk := _estimate_path_collision_risk(spawn, stop_pos, placed, ai_color)

	return {
		"power": power,
		"predicted_stop": stop_pos,
		"target_delta": stop_pos.distance_to(target),
		"house_delta": stop_pos.distance_to(context["house_center"]),
		"collision_risk": path_risk,
	}


func _score_candidate(shot_type: String, _candidate: Dictionary, estimate: Dictionary, board: Dictionary, context: Dictionary, p: Dictionary) -> float:
	var house_radius: float = context["house_radius"]
	var house_delta: float = estimate["house_delta"]
	var target_delta: float = estimate["target_delta"]
	var stop_pos: Vector2 = estimate["predicted_stop"]
	var spawn: Vector2 = context["stone_spawn_position"]
	var score := 0.0

	score -= target_delta * float(p["landing_delta_weight"])
	score -= float(estimate["collision_risk"]) * float(p["collision_risk_weight"])

	match shot_type:
		"takeout":
			var opp_target: Vector2 = board["closest_opponent"]
			var path_clearance := _point_to_segment_dist(opp_target, spawn, stop_pos)
			var takeout_window := house_radius * float(p["takeout_window_ratio"])
			var hit_quality := clampf(1.0 - (path_clearance / maxf(takeout_window, 0.001)), 0.0, 1.0)
			score += hit_quality * float(p["takeout_hit_weight"])
			score -= stop_pos.distance_to(opp_target) * float(p["takeout_stop_weight"])
			score += _estimate_scoring_swing(house_delta, board, house_radius) * float(p["scoring_swing_weight"])
		"guard":
			var forward: Vector2 = ((context["house_center"] as Vector2) - spawn).normalized()
			if forward.length_squared() < 0.00001:
				forward = Vector2.UP
			var dist_ahead: float = ((context["house_center"] as Vector2) - stop_pos).dot(forward)
			var min_front := house_radius * float(p["guard_front_min_ratio"])
			var max_front := house_radius * float(p["guard_front_max_ratio"])
			if dist_ahead >= min_front and dist_ahead <= max_front:
				score += float(p["guard_band_bonus"])
			var guard_anchor: Vector2 = board["closest_ai"] if float(board["closest_ai_distance"]) < INF else context["house_center"]
			var lane_dist := _point_to_segment_dist(stop_pos, spawn, guard_anchor)
			score += maxf(0.0, (house_radius * float(p["guard_lane_half_width_ratio"])) - lane_dist) * float(p["guard_lane_weight"])
			score -= house_delta * float(p["guard_house_penalty_weight"])
		_:
			score += _estimate_scoring_swing(house_delta, board, house_radius) * float(p["scoring_swing_weight"])
			if house_delta <= house_radius:
				score += float(p["in_house_bonus"])
			if shot_type == "draw_second":
				var closest_ai := board["closest_ai"] as Vector2
				if float(board["closest_ai_distance"]) < INF:
					var desired_sep := house_radius * float(p["draw_second_separation_ratio"])
					var sep_err := absf(stop_pos.distance_to(closest_ai) - desired_sep)
					score -= sep_err * float(p["draw_second_sep_weight"])

	return score


func _estimate_scoring_swing(new_ai_best: float, board: Dictionary, house_radius: float) -> float:
	var current_ai := float(board["closest_ai_distance"])
	var current_opp := float(board["closest_opp_distance"])

	var best_ai_after := current_ai
	if new_ai_best <= house_radius:
		best_ai_after = minf(best_ai_after, new_ai_best)

	var before_margin := (current_opp - current_ai) if (current_ai < INF and current_opp < INF) else 0.0
	var after_margin := (current_opp - best_ai_after) if (best_ai_after < INF and current_opp < INF) else 0.0

	if current_opp == INF and best_ai_after <= house_radius:
		return 2.0
	if best_ai_after == INF:
		return -1.0
	return after_margin - before_margin


# ---------------------------------------------------------------------------
# Power / Forward Simulation
# ---------------------------------------------------------------------------

func _calculate_base_power(spawn: Vector2, target: Vector2, physics: Dictionary) -> float:
	var distance := spawn.distance_to(target)
	var min_power := float(physics["min_power"])
	if distance <= _MIN_SOLVE_DISTANCE:
		return min_power

	var required_speed := _estimate_required_launch_speed(distance, physics)
	var launch_multiplier := maxf(float(physics["launch_speed_multiplier"]), 0.0001)
	var throw_distance_scale := maxf(float(physics["throw_distance_scale"]), 0.0001)
	var denom := launch_multiplier * throw_distance_scale
	if denom <= 0.0001:
		return min_power

	var solved_power := required_speed / denom
	if is_nan(solved_power) or is_inf(solved_power):
		return min_power
	return solved_power


func _estimate_required_launch_speed(distance: float, physics: Dictionary) -> float:
	if distance <= 0.0:
		return 0.0

	var max_launch_speed := maxf(float(physics["max_power"]) * float(physics["throw_distance_scale"]) * float(physics["launch_speed_multiplier"]), 1.0)
	var lower := 0.0
	var upper := max_launch_speed
	var upper_distance := _estimate_stop_distance_for_speed(upper, physics)
	var grow_attempts := 0
	while upper_distance < distance and grow_attempts < 8:
		upper *= 1.4
		upper_distance = _estimate_stop_distance_for_speed(upper, physics)
		grow_attempts += 1

	for _i in range(18):
		var mid := (lower + upper) * 0.5
		var mid_distance := _estimate_stop_distance_for_speed(mid, physics)
		if mid_distance < distance:
			lower = mid
		else:
			upper = mid

	return upper


func _estimate_stop_distance_for_speed(initial_speed: float, physics: Dictionary) -> float:
	var speed := maxf(initial_speed, 0.0)
	if speed <= float(physics["stop_speed_cutoff"]):
		return 0.0

	var distance := 0.0
	for _step in range(_SIM_MAX_STEPS):
		if speed <= float(physics["stop_speed_cutoff"]):
			break
		var decel := maxf(_get_speed_based_deceleration(speed, physics), 0.001)
		var next_speed := maxf(speed - (decel * _SIM_DT), 0.0)
		distance += ((speed + next_speed) * 0.5) * _SIM_DT
		speed = next_speed
	return distance


func _simulate_stop_point(start: Vector2, direction: Vector2, power: float, spin_degrees: float, physics: Dictionary) -> Vector2:
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP

	var velocity := dir * (power * float(physics["throw_distance_scale"]) * float(physics["launch_speed_multiplier"]))
	var pos := start
	var stop_cutoff := float(physics["stop_speed_cutoff"])
	var max_spin := maxf(float(physics["max_spin_input_degrees"]), 0.001)
	var spin_ratio := clampf(absf(spin_degrees) / max_spin, 0.0, 1.0)

	for _step in range(_SIM_MAX_STEPS):
		var speed := velocity.length()
		if speed <= stop_cutoff:
			break

		if spin_ratio > 0.0 and speed > 0.0:
			var vel_dir := velocity / speed
			var perp := Vector2(-vel_dir.y, vel_dir.x)
			var curl_sign: float = 1.0 if spin_degrees < 0.0 else -1.0
			var curl_accel := perp * curl_sign * float(physics["max_curl_acceleration"]) * spin_ratio
			velocity += curl_accel * _SIM_DT

		speed = velocity.length()
		if speed <= stop_cutoff:
			break

		var decel := maxf(_get_speed_based_deceleration(speed, physics), 0.001)
		velocity = velocity.move_toward(Vector2.ZERO, decel * _SIM_DT)
		pos += velocity * _SIM_DT

	return pos


func _get_speed_based_deceleration(speed: float, physics: Dictionary) -> float:
	if not bool(physics.get("use_staged_deceleration_profile", true)):
		var fallback_decel := float(physics.get("stop_deceleration", 320.0))
		var low_speed_threshold := maxf(float(physics.get("low_speed_threshold", 180.0)), 0.001)
		if speed < low_speed_threshold:
			var fallback_t := 1.0 - (speed / low_speed_threshold)
			fallback_decel += float(physics.get("extra_low_speed_deceleration", 220.0)) * fallback_t
		return maxf(0.0, fallback_decel)

	var early_value := maxf(0.0, float(physics.get("decel_stage_early_value", 220.0)))
	var mid_value := maxf(0.0, float(physics.get("decel_stage_mid_value", 245.0)))
	var tail_value := maxf(0.0, float(physics.get("decel_stage_tail_value", 95.0)))
	var blend_band := maxf(0.001, float(physics.get("decel_stage_blend_band", 40.0)))

	var mid_blend := _get_stage_blend_amount(speed, float(physics.get("decel_stage_mid_speed", 130.0)), blend_band)
	var tail_blend := _get_stage_blend_amount(speed, float(physics.get("decel_stage_tail_speed", 48.0)), blend_band)

	var decel := lerpf(early_value, mid_value, mid_blend)
	decel = lerpf(decel, tail_value, tail_blend)
	return maxf(0.0, decel)


func _get_stage_blend_amount(speed: float, stage_speed: float, blend_band: float) -> float:
	var half_band := blend_band * 0.5
	var blend_start := stage_speed + half_band
	var blend_end := stage_speed - half_band
	if speed >= blend_start:
		return 0.0
	if speed <= blend_end:
		return 1.0

	var t := (blend_start - speed) / maxf(blend_start - blend_end, 0.001)
	return _smoothstep01(clampf(t, 0.0, 1.0))


func _smoothstep01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - (2.0 * t))


# ---------------------------------------------------------------------------
# Risk / Geometry Helpers
# ---------------------------------------------------------------------------

func _estimate_path_collision_risk(path_a: Vector2, path_b: Vector2, placed: Array[Dictionary], ai_color: String) -> float:
	var risk := 0.0
	for sd in placed:
		var pos: Vector2 = sd["position"]
		var dist := _point_to_segment_dist(pos, path_a, path_b)
		if dist > _STONE_DIAMETER * 1.25:
			continue

		var t := _segment_progress(pos, path_a, path_b)
		if t <= 0.05 or t >= 0.98:
			continue

		var base := clampf(1.0 - (dist / (_STONE_DIAMETER * 1.25)), 0.0, 1.0)
		var color_weight := 1.2 if String(sd["color"]) == ai_color else 0.9
		risk += base * color_weight

	return risk


func _segment_progress(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var d := seg_b - seg_a
	var len_sq := d.dot(d)
	if len_sq <= 0.0001:
		return 0.0
	return clampf((point - seg_a).dot(d) / len_sq, 0.0, 1.0)


func _find_blocking_guard(spawn: Vector2, target: Vector2, guards: Array, block_width: float) -> Vector2:
	for guard_var in guards:
		var guard_pos: Vector2 = guard_var
		var progress := _segment_progress(guard_pos, spawn, target)
		if progress <= 0.1 or progress >= 0.95:
			continue
		if _point_to_segment_dist(guard_pos, spawn, target) < maxf(block_width, _STONE_DIAMETER):
			return guard_pos
	return Vector2(INF, INF)


func _point_to_segment_dist(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var d := seg_b - seg_a
	var len_sq := d.dot(d)
	if len_sq < 0.0001:
		return point.distance_to(seg_a)
	var t := clampf((point - seg_a).dot(d) / len_sq, 0.0, 1.0)
	return point.distance_to(seg_a + d * t)


# ---------------------------------------------------------------------------
# Candidate Selection
# ---------------------------------------------------------------------------

func _pick_candidate(scored: Array[Dictionary], p: Dictionary) -> Dictionary:
	if scored.is_empty():
		return {}
	if scored.size() == 1:
		return scored[0]

	var top_fraction := clampf(float(p["top_pick_fraction"]), 0.1, 1.0)
	var top_count := maxi(1, int(ceil(float(scored.size()) * top_fraction)))
	var sharpness := maxf(float(p["selection_sharpness"]), 0.05)
	var score_floor := float(scored[top_count - 1]["score"])

	var weighted_indices: Array[int] = []
	var weighted_prefix: Array[float] = []
	var running := 0.0
	for i in range(top_count):
		var score := float(scored[i]["score"])
		var normalized := maxf(score - score_floor, 0.0) + 0.001
		var weight := pow(normalized, sharpness)
		running += weight
		weighted_indices.append(i)
		weighted_prefix.append(running)

	if running <= 0.0:
		return scored[0]

	var pick := rng.randf() * running
	for i in range(weighted_prefix.size()):
		if pick <= weighted_prefix[i]:
			return scored[weighted_indices[i]]

	return scored[0]


# ---------------------------------------------------------------------------
# Difficulty Parameters
# ---------------------------------------------------------------------------

func _get_difficulty_params() -> Dictionary:
	var d := float(clamp(difficulty, 1, 10))
	var t := (d - 1.0) / 9.0  # 0.0 at difficulty 1, 1.0 at difficulty 10.

	var strategy_level := 0
	if d > 6.0:
		strategy_level = 2
	elif d > 3.0:
		strategy_level = 1

	return {
		# High values make lower difficulties less precise.
		"target_noise_px":               lerpf(34.0, 3.0, t),
		"power_seed_count":              int(round(lerpf(2.0, 5.0, t))),
		"power_seed_half_span":          lerpf(0.20, 0.025, t),
		"top_pick_fraction":             lerpf(0.70, 0.13, t),
		"selection_sharpness":           lerpf(0.7, 2.9, t),

		# Relative targeting values (house-space, not fixed pixels).
		"draw_ring_ratio":               lerpf(0.28, 0.18, t),
		"draw_second_offset_ratio":      lerpf(0.36, 0.23, t),
		"draw_second_separation_ratio":  lerpf(0.34, 0.26, t),
		"guard_front_min_ratio":         lerpf(1.05, 0.75, t),
		"guard_front_max_ratio":         lerpf(1.65, 1.15, t),
		"guard_lane_half_width_ratio":   lerpf(0.42, 0.26, t),
		"guard_block_width_ratio":       lerpf(0.40, 0.26, t),
		"takeout_flank_ratio":           lerpf(0.20, 0.08, t),
		"takeout_window_ratio":          lerpf(0.42, 0.22, t),

		# Spin intent.
		"draw_spin_ratio":               lerpf(0.18, 0.10, t),
		"curl_around_guard_spin_ratio":  lerpf(0.56, 0.42, t),
		"guard_spin_ratio":              lerpf(0.14, 0.08, t),
		"takeout_spin_ratio":            lerpf(0.08, 0.03, t),

		# Shot-type power shaping.
		"draw_power_bias":               lerpf(0.98, 1.00, t),
		"draw_second_power_bias":        lerpf(0.99, 1.01, t),
		"guard_power_bias":              lerpf(0.92, 0.99, t),
		"takeout_power_bias":            lerpf(1.20, 1.11, t),

		# Scoring terms.
		"landing_delta_weight":          lerpf(0.050, 0.085, t),
		"collision_risk_weight":         lerpf(7.0, 12.0, t),
		"scoring_swing_weight":          lerpf(8.0, 14.0, t),
		"in_house_bonus":                lerpf(6.0, 10.0, t),
		"draw_second_sep_weight":        lerpf(0.03, 0.07, t),
		"takeout_hit_weight":            lerpf(22.0, 38.0, t),
		"takeout_stop_weight":           lerpf(0.06, 0.11, t),
		"guard_band_bonus":              lerpf(7.0, 12.0, t),
		"guard_lane_weight":             lerpf(0.07, 0.11, t),
		"guard_house_penalty_weight":    lerpf(0.025, 0.050, t),

		# Strategy gates.
		"strategy_level":                strategy_level,
		"guard_choice_chance":           lerpf(0.26, 0.45, t),
		"late_lead_guard_chance":        lerpf(0.40, 0.66, t),
		"late_trail_guard_chance":       lerpf(0.18, 0.34, t),
		"use_guard_curl":                d >= 6.0,

		# Keep AI response snappy so post-turn handoff does not feel stalled.
		"think_min":                     lerpf(0.25, 0.08, t),
		"think_max":                     lerpf(0.7, 0.18, t),
	}
