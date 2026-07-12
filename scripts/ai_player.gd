extends RefCounted

## difficulty: 1 (worst) to 10 (best). Set this from main.gd after instantiating.
var difficulty: int = 5

var rng := RandomNumberGenerator.new()

const _STONE_DIAMETER := 30.0


func _init() -> void:
	rng.randomize()


func get_think_time() -> float:
	var p := _get_difficulty_params()
	return rng.randf_range(p["think_min"], p["think_max"])


func choose_shot(stone_spawn_position: Vector2, stone: RigidBody2D, stones_data: Array[Dictionary], house_center: Vector2, house_radius: float, stones_per_player: int) -> Dictionary:
	var ai_color: String = String(stone.get("stone_color"))
	var max_spin: float = float(stone.get("max_spin_input_degrees"))
	var p := _get_difficulty_params()

	# Exclude the stone currently being thrown -- it sits at spawn and hasn't been placed yet.
	var placed: Array[Dictionary] = []
	for sd in stones_data:
		if (sd["position"] as Vector2).distance_to(stone_spawn_position) > 50.0:
			placed.append(sd)

	var board := _analyze_board(placed, house_center, house_radius, ai_color)

	var ai_thrown: int = (board["ai_stones_in_house"] as Array).size() + int(board["ai_outside_count"])
	var stones_remaining: int = maxi(stones_per_player - ai_thrown, 0)

	var shot_type: String = _choose_shot_type(board, stones_remaining, p)

	match shot_type:
		"takeout":
			return _build_takeout(stone_spawn_position, board["closest_opponent"], stone, max_spin, p)
		"guard":
			return _build_guard(stone_spawn_position, house_center, house_radius, stone, max_spin, p)
		"draw_second":
			return _build_draw(stone_spawn_position, house_center, house_radius, board, stone, max_spin, p, true)
		_:
			return _build_draw(stone_spawn_position, house_center, house_radius, board, stone, max_spin, p, false)


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

	for sd in placed:
		var pos: Vector2 = sd["position"]
		var color: String = String(sd["color"])
		var dist := pos.distance_to(house_center)
		if color == ai_color:
			if dist <= house_radius:
				ai_in_house.append({"position": pos, "distance": dist})
			else:
				ai_outside_count += 1
		else:
			if dist <= house_radius:
				opp_in_house.append({"position": pos, "distance": dist})
				if dist < closest_opp_dist:
					closest_opp_dist = dist
					closest_opponent = pos
			elif pos.y > house_center.y + house_radius:
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
	}


# ---------------------------------------------------------------------------
# Strategy Selection
# ---------------------------------------------------------------------------

func _choose_shot_type(board: Dictionary, stones_remaining: int, p: Dictionary) -> String:
	# Low difficulty: mostly draw, occasional random takeout -- ignores board state entirely.
	if int(p["strategy_level"]) == 0:
		return "takeout" if rng.randf() < 0.3 else "draw"

	# Basic and full strategy: react to board state.
	if bool(board["opp_is_scoring"]):
		return "takeout"

	if bool(board["ai_is_scoring"]):
		var ai_in_house := board["ai_stones_in_house"] as Array
		if ai_in_house.size() == 1 and stones_remaining >= 2:
			return "draw_second"
		if int(p["strategy_level"]) >= 2 and ai_in_house.size() >= 2 and stones_remaining >= 1:
			if rng.randf() < 0.4:
				return "guard"

	return "draw"


# ---------------------------------------------------------------------------
# Shot Builders
# ---------------------------------------------------------------------------

func _build_draw(spawn: Vector2, house_center: Vector2, _house_radius: float, board: Dictionary, stone: RigidBody2D, max_spin: float, p: Dictionary, second_stone: bool) -> Dictionary:
	var target := house_center

	if second_stone:
		var ai_in_house := board["ai_stones_in_house"] as Array
		if not ai_in_house.is_empty():
			# Cluster the second stone slightly off-centre, away from the first.
			var existing_pos: Vector2 = ai_in_house[0]["position"]
			var offset_dir := (existing_pos - house_center).normalized()
			if offset_dir == Vector2.ZERO:
				offset_dir = Vector2(1.0, 0.0)
			target = house_center + offset_dir.rotated(PI * 0.45) * 20.0

	target.x += rng.randf_range(-p["noise"], p["noise"])
	target.y += rng.randf_range(-p["noise"], p["noise"])

	# Default spin: small wobble only; overridden below if curling around a guard.
	var spin: float = rng.randf_range(-max_spin * 0.05, max_spin * 0.05)

	if bool(p["use_guard_curl"]):
		var opp_guards: Array = board["opp_guards"]
		if not opp_guards.is_empty():
			var blocker := _find_blocking_guard(spawn, target, opp_guards)
			if blocker.x < INF:
				if blocker.x <= house_center.x:
					# Guard on the left -- swing right; positive spin (left curl) brings it back.
					spin = max_spin * 0.42
					target.x = house_center.x + 55.0
				else:
					# Guard on the right -- swing left; negative spin (right curl) brings it back.
					spin = -max_spin * 0.42
					target.x = house_center.x - 55.0

	# Pre-compensate the aim direction for the expected lateral drift from spin.
	var spin_ratio := absf(spin) / maxf(max_spin, 1.0)
	target.x += signf(spin) * 38.0 * spin_ratio

	var direction := (target - spawn).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.UP

	var power := _calculate_power(spawn, target, stone)
	power *= rng.randf_range(p["power_min"], p["power_max"])
	var max_power: float = float(stone.get("max_power"))
	power = clampf(power, max_power * 0.25, max_power * 0.78)

	return {"direction": direction, "power": power, "spin": spin}


func _build_takeout(spawn: Vector2, target_pos: Vector2, stone: RigidBody2D, max_spin: float, p: Dictionary) -> Dictionary:
	# Aim directly at the opponent stone. Near-zero spin to keep the path straight.
	var target := target_pos
	var noise: float = p["noise"]
	target.x += rng.randf_range(-noise * 0.35, noise * 0.35)
	target.y += rng.randf_range(-noise * 0.35, noise * 0.35)

	var direction := (target - spawn).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.UP

	# Extra power to push the opponent stone out of the house.
	var power := _calculate_power(spawn, target, stone) * 1.18
	power *= rng.randf_range(p["power_min"], p["power_max"])
	var max_power: float = float(stone.get("max_power"))
	power = clampf(power, max_power * 0.3, max_power * 0.85)

	var spin: float = rng.randf_range(-max_spin * 0.03, max_spin * 0.03)
	return {"direction": direction, "power": power, "spin": spin}


func _build_guard(spawn: Vector2, house_center: Vector2, house_radius: float, stone: RigidBody2D, max_spin: float, p: Dictionary) -> Dictionary:
	# Land the stone just in front of the house to protect a scoring position.
	var guard_y := house_center.y + house_radius + rng.randf_range(40.0, 80.0)
	var guard_x := house_center.x + rng.randf_range(-house_radius * 0.3, house_radius * 0.3)
	var target := Vector2(guard_x, guard_y)
	target.x += rng.randf_range(-p["noise"], p["noise"])

	var spin: float = rng.randf_range(-max_spin * 0.05, max_spin * 0.05)
	var spin_ratio := absf(spin) / maxf(max_spin, 1.0)
	target.x += signf(spin) * 38.0 * spin_ratio

	var direction := (target - spawn).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.UP

	var power := _calculate_power(spawn, target, stone)
	power *= rng.randf_range(p["power_min"], p["power_max"])
	var max_power: float = float(stone.get("max_power"))
	power = clampf(power, max_power * 0.2, max_power * 0.65)

	return {"direction": direction, "power": power, "spin": spin}


# ---------------------------------------------------------------------------
# Physics / Path Helpers
# ---------------------------------------------------------------------------

func _calculate_power(spawn: Vector2, target: Vector2, stone: RigidBody2D) -> float:
	var distance := spawn.distance_to(target)
	var stop_deceleration: float = float(stone.get("stop_deceleration"))
	var launch_speed_multiplier: float = float(stone.get("launch_speed_multiplier"))
	var throw_distance_scale: float = maxf(float(stone.get("throw_distance_scale")), 0.01)
	# Factor 2.1 accounts for the extra low-speed deceleration phase in stone.gd.
	var desired_speed := sqrt(maxf(distance * stop_deceleration * 2.1, 0.0))
	# Match flow scales AI input power by throw_distance_scale before launch_shot,
	# so normalize here to avoid unintentionally overdriving long-sheet throws.
	return desired_speed / maxf(launch_speed_multiplier * throw_distance_scale, 0.01)


func _find_blocking_guard(spawn: Vector2, target: Vector2, guards: Array) -> Vector2:
	var min_y := minf(spawn.y, target.y)
	var max_y := maxf(spawn.y, target.y)
	for guard_var in guards:
		var guard_pos: Vector2 = guard_var
		if guard_pos.y < min_y or guard_pos.y > max_y:
			continue
		if _point_to_segment_dist(guard_pos, spawn, target) < _STONE_DIAMETER * 1.5:
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
# Difficulty Parameters
# ---------------------------------------------------------------------------

func _get_difficulty_params() -> Dictionary:
	var d := float(clamp(difficulty, 1, 10))
	var t := (d - 1.0) / 9.0  # 0.0 at difficulty 1, 1.0 at difficulty 10.

	var strategy_level := 0
	if d > 6.0:
		strategy_level = 2  # Full: guard curl, guard placement, all shot types.
	elif d > 3.0:
		strategy_level = 1  # Basic: takeout/draw/draw_second, no guards.

	var power_half_range := lerpf(0.18, 0.01, t)

	return {
		"noise":          lerpf(32.0, 4.0, t),
		"power_min":      1.0 - power_half_range,
		"power_max":      1.0 + power_half_range,
		"strategy_level": strategy_level,
		"use_guard_curl": d >= 6.0,
		# Keep AI response snappy so post-turn handoff does not feel stalled.
		"think_min":      lerpf(0.25, 0.08, t),
		"think_max":      lerpf(0.7, 0.18, t),
	}
