extends RefCounted

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func get_think_time() -> float:
	return rng.randf_range(0.35, 0.85)


func choose_shot(stone_spawn_position: Vector2, stone: RigidBody2D, stones_data: Array[Dictionary], house_center: Vector2, house_radius: float) -> Dictionary:
	var target := _choose_target(stones_data, house_center, house_radius, String(stone.get("stone_color")))
	var max_spin: float = float(stone.get("max_spin_input_degrees"))
	var spin: float = rng.randf_range(-max_spin * 0.35, max_spin * 0.35)
	var spin_ratio: float = absf(spin) / maxf(max_spin, 1.0)

	# Compensate slightly so curl still trends toward the target area.
	target.x += signf(spin) * 42.0 * spin_ratio
	target.x += rng.randf_range(-22.0, 22.0)
	target.y += rng.randf_range(-18.0, 26.0)

	var direction: Vector2 = (target - stone_spawn_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.UP

	var travel_distance: float = stone_spawn_position.distance_to(target)
	var stop_deceleration: float = float(stone.get("stop_deceleration"))
	var launch_speed_multiplier: float = float(stone.get("launch_speed_multiplier"))
	var max_power: float = float(stone.get("max_power"))
	var desired_speed: float = sqrt(maxf(travel_distance * stop_deceleration * 1.95, 0.0))
	desired_speed *= rng.randf_range(0.98, 1.08)

	var power: float = desired_speed / maxf(launch_speed_multiplier, 0.01)
	power = clampf(power, max_power * 0.28, max_power * 0.7)

	return {
		"direction": direction,
		"power": power,
		"spin": spin,
	}


func _choose_target(stones_data: Array[Dictionary], house_center: Vector2, house_radius: float, ai_color: String) -> Vector2:
	var best_opponent_distance := INF
	var best_opponent_position := house_center

	for stone_data in stones_data:
		if String(stone_data["color"]) == ai_color:
			continue

		var stone_position: Vector2 = stone_data["position"]
		var distance := stone_position.distance_to(house_center)
		if distance < best_opponent_distance:
			best_opponent_distance = distance
			best_opponent_position = stone_position

	if best_opponent_distance <= house_radius:
		return best_opponent_position + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-8.0, 10.0))

	return house_center + Vector2(rng.randf_range(-house_radius * 0.18, house_radius * 0.18), rng.randf_range(-house_radius * 0.1, house_radius * 0.16))
