# Throwing Logic and Physics Overview

This document lays out how a throw is built, launched, simulated, and resolved in the current codebase.

Scope:
- Human throw flow in match mode
- AI throw flow and how AI power maps into the same physics
- Physics model for deceleration, curl, sweep, and stopping
- Stone stat multipliers and per-throw profile generation
- Current tuned values from the active resource
- Debug telemetry and practical tuning guidance

Primary files:
- `scripts/stone.gd`
- `scripts/throw_physics_config.gd`
- `data/throw_physics_config.tres`
- `scripts/curlinggame.gd`
- `scripts/curling_sandbox.gd`
- `scripts/ai_player.gd`

## 1. Ownership and data flow

1. `curlinggame.gd` (or `curling_sandbox.gd`) spawns a `Stone` node.
2. Scene controller injects the throw config resource and computed throw distance scale:
   - `stone.set_throw_config(throw_config)`
   - `stone.set_throw_distance_scale(_get_throw_distance_scale())`
3. For human throws, selected stone stats are attached before lock/launch:
   - `set_meta("selected_stone_data", ...)`
   - `set_throw_profile(selected_stone)`
4. `stone.gd` executes all launch and in-flight physics.

## 2. Throw profile and stat scaling

`ThrowPhysicsConfig.build_throw_profile(stone, include_jitter)` returns a per-throw dictionary containing:
- Power multiplier
- Spin authority multiplier
- Spin-setter speed multiplier
- Aim jitter in degrees
- Power jitter multiplier
- Base wear for this throw
- Hard-collision wear rules

### Baseline stat model

Baseline is `33`.

`get_stat_multiplier` behavior:
- At exactly baseline: multiplier is `1.0`
- Below baseline: lerp from `low_multiplier -> 1.0`
- Above baseline: lerp from `1.0 -> high_multiplier`

So each stat has a smooth piecewise-linear effect centered at 33.

## 3. Throw distance scaling

Distance scale is computed from sheet geometry:
- `throw_distance = abs(stone_spawn_y - house_center_y)`
- `distance_scale = clamp((throw_distance / reference_length) * extra_boost, scale_min, scale_max)`

Then the stone clamps this again through `min_throw_distance_scale` and `max_throw_distance_scale` when calling `set_throw_distance_scale`.

Effectively, launch power bounds become:
- `scaled_min_power = min_power * throw_distance_scale`
- `scaled_max_power = max_power * throw_distance_scale`

## 4. Human throw lifecycle

Human throw phases in `stone.gd`:
1. Target marker placement (`PHASE_TARGET_MARKER`)
2. Marker confirmation (`PHASE_CONFIRM_MARKER`)
3. Drag aim/power (`PHASE_SET_SHOT`)
4. Spin picker (`PHASE_SET_SPIN`)
5. In flight (`PHASE_IN_FLIGHT`)
6. Settled (`PHASE_SETTLED`)

### Marker and lock

`curlinggame.gd` controls UI/camera and calls:
- `set_target_marker_position`
- `confirm_target_marker`

### Drag to power

On drag release:
- Pull ratio = drag length / `arrow_max_length`
- Raw power = lerp(`scaled_min_power`, `scaled_max_power`, pull_ratio)
- Apply profile jitter/multipliers and clamp back to scaled min/max
- Store pending launch direction/power
- Open spin setter

### Spin selection and launch

When spin is selected:
- `current_spin_degrees = clamp(spin_input * spin_authority_multiplier, -max_spin, +max_spin)`
- Final velocity at launch:
  - `linear_velocity = pending_direction * pending_power * launch_speed_multiplier`

## 5. AI throw lifecycle

`ai_player.gd` returns `{direction, power, spin}`.

Important normalization behavior:
- AI `_calculate_power` divides by `throw_distance_scale` so shot planning is not overdriven on long sheets.
- `curlinggame.gd` multiplies AI power by `_get_throw_distance_scale()` before calling `launch_shot`.

This keeps AI in the same final launch space as human throws.

AI power estimate uses:
- `desired_speed = sqrt(distance * stop_deceleration * 2.1)`
- then converts to pre-launch power using launch multiplier and distance scale normalization.

## 6. In-flight physics model

`stone.gd._physics_process(delta)` applies, in order:
1. Spin curl acceleration
2. Sweep acceleration
3. Visual spin update
4. Deceleration toward zero velocity
5. Stop cutoff snap to zero

### Deceleration

Two modes:
- Flat mode: `stop_deceleration` + extra low-speed decel ramp below threshold
- Staged mode (default): early/mid/tail decel values blended with smoothstep over configurable speed bands

Core update:
- `linear_velocity = linear_velocity.move_toward(Vector2.ZERO, decel * delta)`
- If speed < `stop_speed_cutoff`, force full stop

### Curl force

If spin is non-zero:
- Compute spin ratio from absolute spin against max spin
- Compute perpendicular vector to current velocity
- Apply lateral acceleration:
  - `curl_accel = perp * sign * max_curl_acceleration * spin_ratio`
- Add to velocity each frame

### Sweep force

Two input modes:
- Legacy directional swipe model
- Proximity model (active)

Proximity model:
- Uses sweep pointer world position relative to moving stone
- Requires pointer within `sweep_influence_radius`
- Splits influence into forward and side components from local alignment
- Applies low-speed amplification curve
- Caps per-sample force and total accumulated influence

Applied sweep is smoothed by blend rate and then decays toward zero over time.

Lateral sweep is reduced by spin ratio using:
- `sweep_spin_lateral_preserve_min`
- `sweep_spin_lateral_blend`

This preserves visible curl identity while allowing sweep correction.

## 7. Stop estimation and marker feedback

`stone.gd` contains internal kinematic simulation for predicted stopping distance:
- `_estimate_stop_distance_for_speed(initial_speed)`
- Integrates speed loss at fixed timestep using current deceleration model

Used for:
- Live marker match strength coloring while dragging
- Launch prediction diagnostics
- Required speed/power inversion for target distance support logic

Marker green window depends on precision and distance:
- Base window lerp from about 56 px (low precision) to 16 px (high precision)
- Also respects a floor of about 3% of target distance

## 8. Wear and collision handling

Per throw:
- Base wear comes from profile (`base_throw_wear_min/max`)

Per hard collision:
- If collision speed >= `hard_collision_speed_threshold`
- Add random wear in `hard_collision_wear_min/max`

Report path:
- `stone.get_throw_condition_report()`
- `curlinggame._record_human_stone_wear_from_throw(stone)` collects wear for post-throw application

## 9. Current tuned values (active resource)

From `data/throw_physics_config.tres`:
- Launch: `min_power=260`, `max_power=800`, `arrow_max_length=350`, `launch_speed_multiplier=1.0`
- Decel profile: early `220`, mid `234`, tail `72`, mid speed `126`, tail speed `46`, blend band `46`
- Curl: `max_curl_acceleration=140`
- Sweep proximity on, with radius `230`, max force `80`, low-speed amp up to `1.8`
- Sweep influence cap: `300`
- Spin setter max degrees in resource: `150`
- Stat multipliers: power and spin low/high `0.78 / 1.32`
- Precision spin speed low/high `2.0 / 0.72`

Note: resource values override defaults in `throw_physics_config.gd`.

## 10. Debugging and instrumentation

`stone.get_debug_telemetry()` exposes:
- Instant speed/velocity/deceleration
- Per-frame curl/sweep/total force vectors
- Marker live and launch deltas
- Throw diagnostics (power, predicted distance, integrated decel, stage times, sample count)

`curling_sandbox.gd` continuously reads this telemetry and prints a formatted panel for tuning.

## 11. Review notes from this pass

1. Physics chain is coherent: launch -> spin/curl -> sweep -> staged decel -> stop cutoff.
2. Distance scaling is consistently used across human and AI paths, with AI explicitly normalized before handoff.
3. Throw config is correctly centralized and injected into both match and sandbox.
4. Potential issue: wear aggregation in `curlinggame.gd` ignores `stone_index <= 0`, which skips index 0 stones for wear recording. If roster indexing is zero-based, this under-reports wear for the first selectable stone.

## 12. Practical tuning order

When tuning feel, change in this order:
1. Decel stage values and stage speeds (overall travel curve)
2. Launch bounds and launch multiplier (input-to-speed feel)
3. Curl acceleration and max spin bounds (arc shape)
4. Sweep radius/force/caps and low-speed amplification (late-throw control)
5. Stat multiplier ranges (stone differentiation)

This avoids compensating one subsystem with another and keeps behavior predictable.
