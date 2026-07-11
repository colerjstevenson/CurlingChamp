extends Resource
class_name ThrowPhysicsConfig

# --- General ---
# Stat value used when no stone is provided (fallback for previews or AI defaults)
@export var baseline_stat: float = 33.0

# --- Throw Distance Scaling ---
# Screen length (pixels) used as the 1x reference for throw distance scaling
@export var throw_distance_reference_length: float = 1280.0
# Minimum distance scale factor (clamps short drags)
@export var throw_distance_scale_min: float = 1.0
# Maximum distance scale factor (clamps long drags)
@export var throw_distance_scale_max: float = 3.0
# Multiplier applied to the raw distance ratio before clamping, adds extra reach
@export var throw_distance_extra_boost: float = 1.1

# --- Input & Launch ---
# Pixel radius around the stone within which a drag is recognized as a grab
@export var grab_radius: float = 64.0
# Minimum launch speed (pixels/sec) applied even at very short drag lengths
@export var min_power: float = 260.0
# Maximum launch speed (pixels/sec) achievable at full drag power
@export var max_power: float = 840.0
# Maximum pixel length of the power-aim arrow UI
@export var arrow_max_length: float = 200.0
# Scales the raw drag vector into actual launch velocity
@export var launch_speed_multiplier: float = 1.28
# Minimum distance scale when mapping drag to power (legacy, prefer staged profile)
@export var min_throw_distance_scale: float = 0.75
# Maximum distance scale when mapping drag to power (legacy, prefer staged profile)
@export var max_throw_distance_scale: float = 2.0

# --- Deceleration ---
# Base deceleration (px/s^2) applied while the stone is moving normally
@export var stop_deceleration: float = 250.0
# Speed (px/s) below which extra low-speed deceleration kicks in
@export var low_speed_threshold: float = 150.0
# Additional deceleration (px/s^2) added once speed drops below low_speed_threshold
@export var extra_low_speed_deceleration: float = 140.0
# Speed (px/s) at which the stone is forced to a full stop
@export var stop_speed_cutoff: float = 5.0
# When true, uses the three-stage deceleration profile instead of the flat values above
@export var use_staged_deceleration_profile: bool = true
# Deceleration (px/s^2) during the early (fast) stage of travel
@export var decel_stage_early_value: float = 220.0
# Deceleration (px/s^2) during the mid stage of travel
@export var decel_stage_mid_value: float = 245.0
# Deceleration (px/s^2) during the slow tail stage of travel
@export var decel_stage_tail_value: float = 95.0
# Speed (px/s) at which the stone transitions from early to mid deceleration
@export var decel_stage_mid_speed: float = 130.0
# Speed (px/s) at which the stone transitions from mid to tail deceleration
@export var decel_stage_tail_speed: float = 48.0
# Speed band (px/s) over which blending between adjacent stages is smoothed
@export var decel_stage_blend_band: float = 40.0

# --- Spin & Curl ---
# Maximum angle (degrees) the player can input for spin on the spin-setter UI
@export var max_spin_input_degrees: float = 270.0
# Maximum lateral acceleration (px/s^2) curl can apply at peak spin
@export var max_curl_acceleration: float = 360.0
# Maximum rotation speed (degrees/sec) of the visual stone sprite spin animation
@export var max_visual_spin_speed_degrees: float = 840.0

# --- Guide Line ---
# Pixel width of the aim guide line drawn before release
@export var guide_line_width: float = 2.0

# --- Sweeping ---
# Maximum forward speed boost (px/s) sweeping can add along the stone's travel direction
@export var sweep_max_forward_boost: float = 80.0
# Maximum lateral speed boost (px/s) sweeping can add perpendicular to travel
@export var sweep_max_lateral_boost: float = 80.0
# Rate (px/s per second) at which accumulated sweep influence decays when not sweeping
@export var sweep_decay_rate: float = 25.0
# Minimum stone speed (px/s) below which sweeping has no effect
@export var sweep_speed_floor: float = 20
# Maximum total accumulated sweep boost (px/s) that can be applied in one throw
@export var sweep_total_influence_cap: float = 160000.0
# When true, sweep force uses a proximity/zone model instead of a uniform boost
@export var sweep_use_proximity_model: bool = true
# Radius (px) around the stone within which sweepers apply the proximity force
@export var sweep_influence_radius: float = 230.0
# Relative weight of force applied directly in front of the stone
@export var sweep_front_weight: float = 1.0
# Relative weight of force applied to the sides of the stone
@export var sweep_side_weight: float = 1.0
# Maximum force (px/s^2) the proximity sweep model can apply per frame
@export var sweep_proximity_max_force: float = 80.0
# Minimum sweep amplification factor at high stone speed (no extra boost)
@export var sweep_low_speed_amp_min: float = 1.0
# Maximum sweep amplification factor at low stone speed (extra boost when nearly stopped)
@export var sweep_low_speed_amp_max: float = 2.8
# Stone speed (px/s) at which the low-speed sweep amplification begins to ramp up
@export var sweep_low_speed_amp_start_speed: float = 170.0
# Stone speed (px/s) at which the low-speed sweep amplification reaches its maximum
@export var sweep_low_speed_amp_end_speed: float = 55.0
# Minimum fraction of spin-induced lateral velocity preserved after sweeping
@export var sweep_spin_lateral_preserve_min: float = 0.58
# Blend factor controlling how much lateral sweep force overrides spin-induced curl
@export var sweep_spin_lateral_blend: float = 0.85

# --- Collisions & Wear ---
# Stone speed (px/s) above which a collision counts as a "hard" impact for wear purposes
@export var hard_collision_speed_threshold: float = 230.0
# Minimum durability points deducted from a stone on a normal throw
@export var base_throw_wear_min: int = 1
# Maximum durability points deducted from a stone on a normal throw
@export var base_throw_wear_max: int = 3
# Minimum durability points deducted from a hard collision
@export var hard_collision_wear_min: int = 5
# Maximum durability points deducted from a hard collision
@export var hard_collision_wear_max: int = 7

# --- Spin Setter UI ---
# Base rotation speed (degrees/sec) of the spin-setter indicator at neutral stat
@export var spin_setter_speed_base: float = 180.0
# Maximum spin angle (degrees) reachable on the spin-setter arc
@export var spin_setter_max_spin_degrees: float = 270.0
# Time (seconds) the spin-setter takes to decelerate to a stop after release
@export var spin_setter_stop_duration: float = 0.5

# --- Stone Stats: Power ---
# Launch speed multiplier for a stone with the minimum power stat
@export var power_multiplier_low: float = 0.78
# Launch speed multiplier for a stone with the maximum power stat
@export var power_multiplier_high: float = 1.32

# --- Stone Stats: Spin ---
# Curl-force multiplier for a stone with the minimum spin stat
@export var spin_authority_low: float = 0.78
# Curl-force multiplier for a stone with the maximum spin stat
@export var spin_authority_high: float = 1.32

# --- Stone Stats: Precision ---
# Aim jitter (degrees) for a stone with the minimum precision stat (least accurate)
@export var precision_aim_jitter_low: float = 7.5
# Aim jitter (degrees) for a stone with the maximum precision stat (most accurate)
@export var precision_aim_jitter_high: float = 0.0
# Power jitter fraction (+/-) for a stone with the minimum precision stat
@export var precision_power_jitter_low: float = 0.045
# Power jitter fraction (+/-) for a stone with the maximum precision stat
@export var precision_power_jitter_high: float = 0.0
# Spin-setter speed multiplier for a stone with the minimum precision stat (faster = harder)
@export var precision_spin_speed_low: float = 1.25
# Spin-setter speed multiplier for a stone with the maximum precision stat (slower = easier)
@export var precision_spin_speed_high: float = 0.72
func get_throw_distance_scale(distance: float) -> float:
	if throw_distance_reference_length <= 0.0:
		return 1.0

	var distance_scale := (distance / throw_distance_reference_length) * throw_distance_extra_boost
	return clampf(distance_scale, throw_distance_scale_min, throw_distance_scale_max)


func build_throw_profile(stone: Stone, include_jitter: bool = true) -> Dictionary:
	var power_stat := int(baseline_stat)
	var spin_stat := int(baseline_stat)
	var precision_stat := int(baseline_stat)
	if stone != null:
		power_stat = int(stone.power)
		spin_stat = int(stone.spin)
		precision_stat = int(stone.precision)

	var power_multiplier := get_stat_multiplier(power_stat, power_multiplier_low, power_multiplier_high)
	var spin_authority_multiplier := get_stat_multiplier(spin_stat, spin_authority_low, spin_authority_high)
	var spin_setter_speed_multiplier := get_stat_multiplier(precision_stat, precision_spin_speed_low, precision_spin_speed_high)
	var aim_jitter_degrees := 0.0
	var power_jitter_multiplier := 1.0
	if include_jitter:
		var precision_jitter := get_stat_multiplier(precision_stat, precision_aim_jitter_low, precision_aim_jitter_high)
		var precision_power_jitter := get_stat_multiplier(precision_stat, precision_power_jitter_low, precision_power_jitter_high)
		aim_jitter_degrees = randf_range(-precision_jitter, precision_jitter)
		power_jitter_multiplier = randf_range(1.0 - precision_power_jitter, 1.0 + precision_power_jitter)

	return {
		"power_multiplier": power_multiplier,
		"spin_authority_multiplier": spin_authority_multiplier,
		"precision_stat": precision_stat,
		"spin_setter_speed_multiplier": spin_setter_speed_multiplier,
		"launch_aim_jitter_degrees": aim_jitter_degrees,
		"launch_power_jitter_multiplier": power_jitter_multiplier,
		"base_throw_wear": randi_range(base_throw_wear_min, base_throw_wear_max) if include_jitter else base_throw_wear_min,
		"hard_collision_wear_min": hard_collision_wear_min,
		"hard_collision_wear_max": hard_collision_wear_max,
		"hard_collision_speed_threshold": hard_collision_speed_threshold,
		"max_spin_input_degrees": max_spin_input_degrees,
	}


func get_stat_multiplier(stat_value: int, low_multiplier: float, high_multiplier: float) -> float:
	var clamped_stat := clampf(float(stat_value), 0.0, 100.0)
	if is_equal_approx(clamped_stat, baseline_stat):
		return 1.0

	if clamped_stat < baseline_stat:
		var below_ratio := clamped_stat / maxf(baseline_stat, 1.0)
		return lerpf(low_multiplier, 1.0, below_ratio)

	var above_ratio := (clamped_stat - baseline_stat) / maxf(100.0 - baseline_stat, 1.0)
	return lerpf(1.0, high_multiplier, above_ratio)