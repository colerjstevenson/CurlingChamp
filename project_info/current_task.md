## Plan: AI Recalibration For New Rink And Throw System

Rebuild opponent shot planning so AI remains accurate under the resized rink and updated throw physics, while keeping all tuning values in `data/throw_physics_config.tres` untouched. The implementation keeps runtime behavior grounded in throw config-derived values already applied to stones, and replaces fragile fixed-offset aiming with geometry- and simulation-driven targeting.

**Steps**
1. Phase 1: Stabilize AI physics inputs
1.1 Update `scripts/ai_player.gd` `choose_shot` contract to accept a context dictionary from `curlinggame` containing: `throw_distance_scale`, `house_center`, `house_radius`, `stone_spawn_position`, and active deceleration/curl parameters read from the spawned stone.
1.2 Keep source-of-truth in throw config indirectly by reading runtime values already applied to the stone node, and remove dependence on hardcoded constants for power estimation wherever possible.
1.3 Add guardrails in power solving for edge cases (zero launch multiplier, zero distance scale, very short distances) to avoid `NaN`/`INF` behavior.

2. Phase 2: Replace fixed-offset shot targeting with rink-relative geometry
2.1 Refactor draw, guard, and takeout target builders in `scripts/ai_player.gd` to derive lateral and longitudinal offsets from `house_radius` and spawn-to-house vector rather than absolute pixels (`20`, `38`, `40-80`, `55`).
2.2 Introduce named per-difficulty tuning parameters in `_get_difficulty_params` for relative offsets, spin intent, and acceptable landing tolerance.
2.3 Keep the existing strategy categories (`draw`, `draw_second`, `takeout`, `guard`) but make each target choice computed in normalized rink-space.

3. Phase 3: Add candidate-based shot planner (full-overhaul core)
3.1 Implement candidate generation per shot type (multiple target points, spin bands, and power seeds) in `scripts/ai_player.gd`.
3.2 Add a lightweight forward estimator in `scripts/ai_player.gd` that predicts stop point and lateral curl drift using runtime deceleration/curl parameters from the current stone.
3.3 Score candidates by objective: scoring improvement, takeout probability, guard protection value, and collision risk with known guards/stones.
3.4 Select best candidate with difficulty-based randomness (high difficulty near-deterministic, low difficulty wider pick band).

4. Phase 4: Integrate and preserve scene flow
4.1 Update `scripts/curlinggame.gd` `_start_ai_turn` to pass enriched planning context to `ai_player.choose_shot` while preserving existing launch call flow.
4.2 Retain existing normalization contract: AI returns pre-scale power, game applies `_get_throw_distance_scale` before `launch_shot`.
4.3 Add optional debug toggles in `scripts/curlinggame.gd` and `scripts/ai_player.gd` for one-line telemetry of selected candidate and predicted-vs-target delta (disabled by default).

5. Phase 5: Calibration pass without config edits
5.1 Tune only AI-side coefficients in `scripts/ai_player.gd` so shot outcomes align with current throw config behavior.
5.2 Validate guard placement band and second-stone clustering across low/mid/high difficulty using house-relative coordinates.
5.3 Ensure no changes are made to `data/throw_physics_config.tres` per scope decision.

6. Phase 6: Documentation and task tracking
6.1 Update `project_info/task_state.md` with what AI changed, what remained unchanged, and known follow-up tuning opportunities.
6.2 If behavior expectations changed materially, add a short AI section update in `project_info/gameplay.md`.

**Relevant files**
- `scripts/ai_player.gd` - primary overhaul: targeting model, candidate generation, scoring, runtime physics usage.
- `scripts/curlinggame.gd` - pass planning context into `choose_shot`, keep launch scaling contract intact.
- `scripts/stone.gd` - reference only for runtime physics fields already loaded from throw config; modify only if absolutely needed for read access helper methods.
- `project_info/task_state.md` - record task outcomes.
- `project_info/gameplay.md` - update only if player-visible AI behavior description changes.

**Verification**
1. Static consistency check: confirm `ai_player.gd` contains no fixed pixel magic offsets tied to old rink geometry for draw/guard/curl pre-compensation.
2. Contract check: confirm `_start_ai_turn` in `curlinggame.gd` still multiplies AI power by `_get_throw_distance_scale` exactly once before `launch_shot`.
3. Parameter provenance check: verify AI planner reads deceleration/curl/launch data from active stone runtime values (which come from throw config), not duplicated constants.
4. Behavior sanity review: inspect candidate scoring weights and ensure each shot type objective matches strategy intent (takeout prioritizes opponent removal, guard prioritizes blocking lane).
5. Regression check: run parser/lint diagnostics with `get_errors` for edited files and resolve all new errors.
6. Manual in-editor review checklist: low difficulty should be noisier and less optimal; high difficulty should produce tighter draw/takeout targeting under current sheet dimensions.

**Decisions**
- Included scope: full AI overhaul focused on shot planning and accuracy.
- Included scope: code-only changes; no modifications to `throw_physics_config.tres`.
- Source of truth: throw physics config values as represented on runtime stone properties.
- Excluded scope: non-AI gameplay refactors, scene hierarchy changes, asset changes, save format changes.

**Further considerations**
1. If runtime telemetry shows estimator bias after rollout, add a small adaptive correction term per shot type (still AI-only) rather than altering throw config.
2. If `stone.gd` lacks a clean read surface for current decel stage parameters, add a minimal getter method instead of exposing many fields directly.
3. If match-length tuning is needed later, add difficulty-specific candidate-count limits to control think quality vs responsiveness.
