# Task State: Proximity-Based Sweeping Rework

## Last Completed Phase
- Phase 6: Parity, Regression, Documentation

## What Was Implemented
- Training parity: [scripts/training_game.gd](scripts/training_game.gd) now uses the same throw config path (`res://data/throw_physics_config.tres`) and applies `set_throw_config` + throw distance scale to spawned stones.
- Training parity: player training stones now apply the selected roster stone throw profile via `set_throw_profile`, matching stat-driven throw behavior from match flow.
- Updated [project_info/gameplay.md](project_info/gameplay.md) with final sweep model, speed scaling, staged deceleration, and tuning assumptions.
- Regression-focused code-path verification completed for:
	- human throw sequence continuity (target -> lock -> drag -> spin -> sweep -> resolve)
	- AI throw path safety and launch path in match mode
	- end scoring and post-match progression/week advance path
	- save/load state persistence pathways and autosave signal flow

## Validation Status For Phase 6 Gate
- Match/training parity for throw config and throw profile path has been implemented.
- Core regression paths remain connected in code and unmodified behaviors still route through existing manager/save systems.
- Documentation now reflects the final sweeping and slowdown model.
- No parser/type errors reported in changed files.

## Next Phase
- Current task phases complete. Optional follow-up: in-engine feel/timing passes and numeric retuning after live playtests.
