# CurlingChamp Gameplay Reference

This file describes the game as it currently behaves in code, not just the long-term design goal. Future agents should treat this as the authoritative summary of the playable loop and the systems that are still placeholders.

## Core Fantasy

CurlingChamp is a single-player curling management game built around owning a roster of named curling stones, improving them over time, and climbing a league schedule by winning weekly matches. The long-term fantasy is closer to a creature or sports management sim than a pure sports game: the player is supposed to collect, train, buy, sell, and eventually breed better stones.

Right now, the strongest implemented pillar is the actual on-ice curling match. The management layer exists, but only some of it is functional.

## Current Playable Loop

The current loop is:

1. Start or load a save slot.
2. Enter the main hub.
3. Review money and current date in the top bar.
4. Optionally open collection, auction, calendar, or training.
5. Play the scheduled weekly match.
6. When the match ends, the week result is recorded, the other league games are simulated, and the current week advances by 1.
7. Repeat until the schedule ends.

Important implementation detail: there is no separate "end week" button. The week only advances when a match completes through `game_manager.complete_week_after_match()`.

## Game Structure By Layer

### 1. Meta / Management Layer

The management layer revolves around global state stored in `game_manager.gd`:

- Player identity: `player_name`, `player_color`, `opponent_color`
- Calendar: `week`, `year`
- Economy: `money`
- Roster: `player_stones`
- Shop inventory: `store_stones`
- Schedule: `Schedule`
- League table: `LeaguePlayers`
- Records: season record, all-time record, majors won
- Weekly trainer lock: `trainer_week_used`

The project currently starts with:

- 4 player stones
- 4 store stones
- 21 schedule weeks
- 25 AI league players
- $100 starting money by default

These defaults come from `data/new_game_template.json` plus fallback generation in `game_manager.gd`.

### 2. Match Layer

The match scene is a playable curling game, controlled by `scripts/curlinggame.gd` and `scripts/stone.gd`.

- Matches default to 3 ends.
- Each side throws 5 stones per end.
- Human and AI alternate throws.
- When both sides have thrown all stones for the end, the game scores the house.
- The side that scores starts the next end.
- If the match is tied after the configured maximum ends, the game keeps going into extra ends until the tie is broken.

When the match finishes, it displays a result banner, records the human result in the save state, simulates the rest of the league, advances the week, and automatically returns to the main hub.

### 3. Training Layer

Training is the only management system besides match progression that currently changes stone stats.

The player chooses:

- one stat focus: `Speed`, `Precision`, or `Spin`
- one owned stone to train

The trainer can only be used once per in-game week. This is enforced by `trainer_week_used`.

The training scene then runs a 5-shot minigame and awards a permanent stat increase to the selected stone.

## Stone Model

Stones are data objects defined by `scripts/stone_data.gd` as the `Stone` class.

Each stone currently stores:

- `name`
- `age`
- `wins`
- `variant` (sprite variant id)
- `power`
- `spin`
- `precision`
- `condition`
- `power_potential`
- `spin_potential`
- `precision_potential`

### Meaning of the stats

- `power`: currently the stat increased by "Speed" training
- `spin`: currently the stat increased by spin training
- `precision`: currently the stat increased by precision training
- `condition`: displayed in UI and reduced by throw wear and hard collisions
- `*_potential`: hard cap for future growth on that stat

Important naming mismatch: the trainer UI calls one stat `Speed`, but the underlying data field it modifies is `power`.

Current throw behavior derives a per-throw profile from the selected stone when the human player locks target. Power changes launch force, spin changes effective curl authority, precision changes aim jitter and spin-setter speed, and each throw adds condition wear that is applied after the match. Stones that reach 0 condition are removed from the roster after the match and will not appear in later selection screens.

## Match Gameplay Details

### Human turn flow

For a player-controlled stone:

1. Target stage: the camera moves to the house and the player taps to place a target marker.
2. Confirm stage: the player can retap to adjust, then presses `Lock Target` to continue.
3. Shot setup stage: the camera returns to the throwing hack, and the player drags from the stone to set direction and power.
4. Spin stage: on drag release, the spin selector overlay appears.
5. Release stage: the player chooses spin amount/direction and the stone launches.
6. Sweep stage: while the stone is in flight, swipe input adds small, capped forward and lateral influence.
7. Resolve stage: once the stone settles, normal turn progression resumes.

This multi-stage flow only applies to human-controlled stones. AI stones continue to launch directly from AI shot selection.

### Stone behavior

The physics stone supports:

- target marker placement and lock confirmation
- pull-back aiming after target lock
- an in-aim guide line from stone to target marker
- capped launch power
- stone-stat-driven launch profiling for human throws
- configurable spin input in degrees
- curling force while the stone is moving
- bounded sweep influence while moving (with decay and per-throw cap)
- visual spin on the sprite
- gradual deceleration and stop detection
- removal if it hits side walls or leaves legal play bounds
- post-match wear reporting for human stones

### Sweep and slowdown model (current)

Sweep behavior is now proximity-driven rather than direction-driven:

- Sweep input samples where the player is swiping relative to the moving stone.
- Influence comes from front and side arcs around the current velocity direction.
- Swipe vector direction does not directly determine sweep direction in the proximity model.

Current sweep response shaping:

- Influence falls off by distance from the stone within a configurable radius.
- Influence is weighted separately for front push and side influence.
- A low-speed amplification curve increases sweep effect as stone speed drops.
- Per-sample force and per-throw total influence are both capped.
- Applied sweep force is blended over time to avoid jitter/snaps.
- A rollback toggle still exists to use the legacy directional sweep path if needed.

Curl preservation during sweeping:

- Lateral sweep influence is scaled down as spin ratio rises.
- This keeps spin/curl identity visible while still allowing meaningful sweeping late in travel.

Deceleration model is staged and blended:

- Early and mid stages preserve overall travel pacing feel.
- Tail stage reduces deceleration to extend the settle window.
- Stage transitions are smooth-blended (no hard step).
- Stop cutoff remains active to prevent endless drift.

Training parity:

- Training mode now loads the same throw physics config resource path used by match mode.
- Training player stones now apply the selected roster stone throw profile, matching stat-driven throw behavior used in match mode.

### Scoring

End scoring is classic curling-style "count the closest color until the other side has a closer stone":

- Only stones inside the house count.
- The closest stone determines the scoring color.
- Every consecutive stone of that same color, ordered by distance to the button, counts as 1 point until the other color appears.

### Match progression result

On match completion the game:

- updates human season and all-time record
- writes the result text into the current schedule entry
- simulates the other league players' games for that week
- increments `week` by 1, capped to schedule size

## AI Opponents

AI behavior is implemented in `scripts/ai_player.gd`.

Opponent skill is read from the scheduled league opponent for the current week. That skill is converted into:

- aim noise
- power variance
- think time
- strategic depth

AI shot selection currently supports:

- draw to the house
- takeout when the opponent is scoring
- second scoring draw when already sitting one
- guard placement at higher difficulties
- curling around guards at higher difficulties

Planning details:

- AI now builds multiple shot candidates per shot type (target points, spin bands, and power seeds).
- Candidate targeting is house-relative (radius and spawn-to-house geometry), not fixed pixel offsets.
- Forward prediction uses runtime stone launch/deceleration/curl values read from the active stone context.
- Candidates are scored by strategy objective (scoring swing, takeout quality, guard lane value) plus collision risk.
- Final choice uses difficulty-based randomness from a top candidate band:
	- low difficulty samples a wider band with more noise
	- high difficulty picks near-best candidates more consistently

Difficulty ranges from 1 to 10.

## Schedule, Season, and League

The schedule is stored as an array of dictionaries. Each entry can hold:

- `week`
- `is_major`
- `opponent`
- `venue`
- `rink_name`
- `result`
- `event_name`
- `rounds`

League players are stored separately as dictionaries with:

- `name`
- `record`
- `skill`

### Important current behavior

- Default schedules are generated as 21 regular weeks.
- Opponents are assigned from the league player list.
- Rink names are assigned from `lists/rink_names.txt`.
- Other league matches are simulated by random pairings weighted by player skill.

### Important limitation

The data format supports majors, but the default new game flow does not currently generate a major schedule. Major weeks only exist if they are manually seeded into template or save data.

## Training Gameplay Details

The training minigame has 3 modes:

### Speed

- One opponent stone is placed in the house.
- The player tries to knock it out and leave their own stone in the house.
- Points depend on how close the player's stone finishes to the button.

### Spin

- A frozen guard is placed in front of the house.
- The player tries to curl around it and finish in the house.
- Points depend on final distance to the button.

### Precision

- Two or three opponent stones are placed in the house.
- The player must finish closer to the button than all of them.
- Points depend on final distance to the button.

### Training rewards

Each shot awards:

- 400 points for button-level placement
- 300 points for inner ring
- 200 points for mid ring
- 100 points for outer ring
- 0 on failure

After 5 shots, the total score is converted into a permanent boost:

- high score: `+10`
- medium score: `+7`
- low score: `+5`

This boost is applied directly to the selected `Stone`, respecting that stat's potential cap.

## Menu Functions

### Start Menu

The start menu supports 3 save slots. Each slot can:

- load an existing game
- start a new game
- delete the slot

New game setup currently lets the player choose:

- player name
- player stone color

### Main Hub

The main hub is the central routing screen. It shows:

- current money
- current date
- buttons for game, collection, auction, calendar, and training
- decorative menu stones in the background

### Collection

The collection screen displays the player's stones as cards. It is currently a read-only roster view.

### Calendar

The calendar screen has 3 tabs:

- Schedule
- Standings
- Stats

It shows:

- week-by-week opponent or major event data
- league standings including the human player
- all-time human record
- majors won list

### Auction

The auction screen has a buy tab and a sell tab, and it renders both store stones and player stones as cards.

Current limitation: it is display-only. There is no buy, sell, pricing, or money-transfer logic yet.

## Features That Exist In Design But Not Yet In Code

These ideas are part of the project fantasy, but are not fully implemented right now:

- breeding gameplay
- working auction economy
- stone abilities or traits
- stone stats affecting throw physics
- roster or lineup selection for matches
- condition or fatigue systems affecting performance
- tournament bracket or multi-round major flow
- playoffs at end of season
- end-of-match results breakdown beyond the banner

## Known Placeholder and Legacy Surfaces

The project contains UI that suggests future or inherited systems:

- `scenes/menus/breeder.tscn` exists as a large placeholder UI
- that breeding scene has no active gameplay script behind it
- some labels in that scene still use old non-curling terminology such as `Stamina` and `Acceleration`

Future agents should not assume those screens are wired up just because the UI exists.

## What To Treat As Canonical Today

If an agent needs to reason about what the player can actually do today, the safest summary is:

- create or load a save
- manage a roster of stones as persistent data
- view schedule and standings
- play a full curling match against a week-specific AI opponent
- complete one training minigame per week to improve one stone stat
- carry that progress forward through autosaved global state

Anything beyond that should be treated as planned, partial, or placeholder unless verified in code first.