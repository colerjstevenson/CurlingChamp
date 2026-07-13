## AI Recalibration For New Rink And Throw System - Completed

### What changed
- Reworked AI shot planning in scripts/ai_player.gd to use a candidate-based planner instead of fixed target offsets.
- Updated AI choose_shot input contract to receive a planning context dictionary with:
	- throw_distance_scale
	- house_center
	- house_radius
	- stone_spawn_position
	- active runtime stone physics values (launch multiplier, staged deceleration fields, curl fields, power bounds).
- Replaced fixed pixel targeting with house-relative geometry for draw, draw_second, takeout, and guard candidate generation.
- Added per-difficulty tuning parameters for relative offsets, spin intent, power seed range, selection randomness, and scoring weights.
- Added a forward estimator that predicts stop point from runtime deceleration and curl values.
- Added candidate scoring terms for scoring swing, takeout quality, guard lane value, landing error, and path collision risk.
- Added difficulty-based candidate selection randomness using a top-band weighted picker.
- Added optional one-line AI telemetry (disabled by default):
	- curlinggame.gd export toggle ai_debug_telemetry
	- ai_player.gd toggle debug_telemetry_enabled

### Integration notes
- _start_ai_turn in scripts/curlinggame.gd now builds and passes planning context into ai_player.choose_shot.
- Existing launch contract is preserved:
	- AI returns pre-scale power.
	- Match flow multiplies by _get_throw_distance_scale exactly once before launch_shot.

### What remained unchanged
- No edits were made to data/throw_physics_config.tres.
- No non-AI scene hierarchy or save-format changes were introduced.
- Existing strategy categories remain intact: draw, draw_second, takeout, guard.

### Known follow-up tuning opportunities
- If telemetry shows systematic over/under-shoot for specific shot types, tune AI-side shot_power_bias and landing weights.
- If guard quality needs tighter lanes at high difficulty, adjust guard_lane_half_width_ratio and guard_lane_weight only.
- If think quality needs balancing versus responsiveness, tune power_seed_count and top_pick_fraction by difficulty.

## Mobile Start Menu Focus Fix - Completed

### What changed
- Removed automatic focus and virtual-keyboard requests when the start menu opens the new-game panel.
- The name field now only focuses when the player explicitly taps the field, which avoids the mobile startup path that was causing trouble.

### What remained unchanged
- Scene routing and save-slot logic were left alone.
- The explicit tap-to-focus and keyboard behavior on the name field still works.
