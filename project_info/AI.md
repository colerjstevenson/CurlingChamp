# CurlingChamp AI Guide

This document explains how the match AI currently works in CurlingChamp in plain language. It is meant to be readable by players, designers, and future contributors.

## At a Glance

The curling AI is a rule-based planner that:

1. Looks at the current board.
2. Decides what kind of shot makes sense for the board and match situation.
3. Builds several possible versions of that shot.
4. Simulates where each one is likely to finish.
5. Scores the options.
6. Chooses one based on difficulty.

The main implementation lives in [scripts/ai_player.gd](scripts/ai_player.gd), and match flow passes week-to-week opponent difficulty in from [scripts/curlinggame.gd](scripts/curlinggame.gd) and [scripts/game_manager.gd](scripts/game_manager.gd).

## Where Difficulty Comes From

Each scheduled opponent has a skill value from 1 to 10.

- `1` means very weak play.
- `10` means very strong play.

That value is read from the current week's opponent data and assigned to the AI for the match. Higher difficulty does not give the AI secret physics bonuses. Instead, it changes how well the AI plans and how reliably it picks strong shots.

## What the AI Knows

When it is the AI's turn, the match provides a planning context with the current sheet and stone information. That includes:

- the stone spawn position
- the house center
- the house radius
- the current throw-distance scale
- the active stone's launch, slowdown, and curl settings
- match state:
	- current end
	- maximum ends
	- AI score
	- opponent score
	- whether AI has hammer

This matters because the AI aims using the same runtime throw behavior the player interacts with. It is trying to predict real in-game outcomes, not using a separate simplified rule set.

It also means the AI can shift its risk profile based on game context. The same board can lead to different decisions depending on whether the AI is protecting a late lead or chasing points.

## Core Decision Loop

### 1. Board analysis

The AI first sorts out the current state of play.

It checks:

- which AI stones are already in the house
- which opponent stones are in the house
- which side is currently scoring
- whether there are opponent guards between the throwing end and the house
- which stone is closest for each side

This gives the AI a compact summary of the board before it decides on strategy.

### 2. Shot type selection

The AI currently chooses between four main shot categories:

| Shot type | What it means | When it is usually chosen |
| --- | --- | --- |
| `draw` | Try to place a stone in the house | Default option |
| `draw_second` | Add a second scoring stone with some separation | When AI is already scoring and wants support |
| `takeout` | Remove or challenge the opponent's best stone | When the opponent is scoring |
| `guard` | Put a stone in front to protect scoring stones or clog the lane | Higher difficulties, usually after AI is already in a good position |

At low difficulty, the AI is much simpler and mostly throws draws with occasional takeouts.

At mid and high difficulty, it reacts more to the board state and starts using guard logic more often.

The AI now also reacts to score and end progression.

- late while leading: it becomes more protective and is more likely to pick guard-oriented decisions when already in a good scoring position
- late while trailing: it increases urgency, values scoring swing more heavily, and becomes more willing to accept risk to recover points

### 3. Candidate generation

Once it picks a shot type, the AI creates a set of possible attempts rather than committing to a single aim point immediately.

Each candidate can vary by:

- target point
- spin amount
- power seed
- shot-specific power bias

Important detail: targets are built relative to the house size and lane direction, not from hardcoded old-sheet pixel offsets. That keeps the planner more stable if rink scale or throw tuning changes.

### 4. Forward simulation

For every candidate, the AI estimates where the stone will stop.

That estimate uses:

- launch speed multiplier
- throw-distance scale
- staged deceleration values
- stop-speed cutoff
- curl acceleration
- spin amount

The result is a predicted stop point, plus a measure of how far it missed the intended target and how risky the path is.

### 5. Candidate scoring

The AI then scores each possible shot.

All candidates are penalized for:

- missing the intended landing spot
- traveling through dangerous traffic

After that, the scoring changes by shot type.

#### Draw and draw_second

These prioritize:

- improving scoring position
- finishing inside the house
- in `draw_second`, ending with useful spacing from the AI's first scoring stone

#### Takeout

These prioritize:

- lining up a clean hit on the opponent's closest stone
- finishing near the target line
- improving the scoring margin after contact

#### Guard

These prioritize:

- stopping in a useful band in front of the house
- occupying the lane between the hack and an AI scoring stone
- avoiding over-rolling deep into the house

### 6. Final selection

After scoring, the AI does not always pick the exact best candidate.

That final choice is where much of the difficulty feel comes from:

- weak AI samples from a much wider top band
- strong AI samples from a much narrower top band
- weak AI also uses more noise in aiming and broader power variation
- strong AI uses tighter targeting, narrower power ranges, and sharper selection

This keeps low difficulty from feeling robotic while allowing high difficulty to feel deliberate.

## Score And End Awareness

Beyond static difficulty, the AI applies match-state adjustments before strategy and candidate scoring.

### Match-state signals used

- score differential (AI score minus opponent score)
- current end and maximum ends
- ends remaining
- hammer ownership

### Practical effect on behavior

When trailing, especially late:

- scoring swing terms are weighted more heavily
- in-house value is increased
- collision-risk penalties are relaxed
- guard preference is reduced so it does not over-defend while behind

When leading, especially late:

- collision-risk penalties are increased
- guard preference and guard-value terms are increased
- overaggressive takeout weighting is reduced

This creates a more realistic game flow where the AI preserves advantages when ahead and pushes for comeback lines when behind.

## What Difficulty Changes

Difficulty mostly changes planning quality, not raw capability.

### Low difficulty: 1 to 3

- larger target noise
- fewer candidate variations checked
- wider power variance
- weaker final candidate selection
- mostly simple draw behavior
- only occasional takeouts
- no advanced guard-curl planning

### Mid difficulty: 4 to 6

- better targeting
- more stable power choices
- stronger reaction to whether the opponent is scoring
- begins using more structured strategy
- can choose between offensive and defensive play more reliably

### High difficulty: 7 to 10

- smallest target noise
- most candidate coverage
- strongest score-based selection
- regular use of guard logic
- can add curl intent to work around blocking guards
- more consistent placement and takeout pressure

## Strategy Mechanics in Practice

Here is the practical behavior the current AI is built around.

### If the opponent is scoring

The AI usually switches to a takeout plan.

It focuses on the opponent's closest stone, tests direct and flanking lines, and values any shot that can improve the scoring swing.

### If the AI is already scoring

The AI often keeps building pressure instead of always throwing another button-seeking draw.

It may:

- add a second stone in the house
- spread that second stone away from the first
- place a guard at higher difficulties

### If guards block the center line

At higher difficulty, the AI can intentionally include stronger spin options for draw attempts so it has a chance to curl around traffic instead of only throwing straight lines.

## Think Time

Difficulty also changes how long the AI appears to think before throwing.

- low difficulty waits a bit longer
- high difficulty responds faster

This is mainly for pacing and feel. The AI is still using the same planning pipeline underneath.

## What the AI Does Not Do

The current AI does not:

- learn from previous matches
- remember your tendencies
- model long multi-shot end plans several turns ahead
- cheat by teleporting stones or ignoring physics
- change the throw physics config during play

It makes one shot decision at a time using the current board, the active stone's runtime throw values, and its difficulty tuning.

## Why This Design Works

This approach fits the game well because it is:

- predictable enough to tune
- grounded in the same throw behavior the player sees
- flexible across rink and physics adjustments
- easy to scale from casual to challenging opponents

It also makes future tuning straightforward. If the AI feels too strong or too weak, difficulty parameters can be adjusted without rewriting the entire match system.

## Related Files

- [scripts/ai_player.gd](scripts/ai_player.gd): main shot planning, simulation, scoring, and difficulty tuning
- [scripts/curlinggame.gd](scripts/curlinggame.gd): hands the current board and stone context to the AI during match flow
- [scripts/game_manager.gd](scripts/game_manager.gd): stores weekly opponent skill values used to set difficulty
- [project_info/gameplay.md](project_info/gameplay.md): broader gameplay reference, including the current AI summary